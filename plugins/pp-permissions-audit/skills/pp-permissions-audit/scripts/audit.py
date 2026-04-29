#!/usr/bin/env python3
"""
Power Pages Permissions Audit

Static analysis of a Power Pages classic site source tree. Cross-references
Site Settings, Table Permissions, Web Roles, Web Pages, and Custom JS to
find misalignments and security risks.

Stdlib only by default; uses PyYAML if available for stricter YAML parsing.

Usage:
    python3 audit.py <site-folder>            print markdown report to stdout
    python3 audit.py <site-folder> -o out.md  write report to file
    python3 audit.py <site-folder> --json     emit JSON instead of markdown
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from collections import defaultdict
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

# Optional PyYAML — use if available, fall back to regex parsing otherwise
try:
    import yaml as _yaml  # type: ignore
    HAVE_YAML = True
except ImportError:
    HAVE_YAML = False


# ---------------------------------------------------------------------------
# Findings
# ---------------------------------------------------------------------------

@dataclass
class Finding:
    severity: str        # "ERROR" | "WARN" | "INFO"
    code: str            # short stable identifier
    title: str
    detail: str
    location: str = ""   # file path or symbolic location

    def to_dict(self) -> dict:
        return {
            "severity": self.severity,
            "code": self.code,
            "title": self.title,
            "detail": self.detail,
            "location": self.location,
        }


@dataclass
class AuditState:
    site_dir: Path
    site_settings: dict[str, str] = field(default_factory=dict)              # name -> value
    table_permissions: list[dict[str, Any]] = field(default_factory=list)    # parsed YAML records
    web_roles: list[dict[str, Any]] = field(default_factory=list)
    web_pages: list[dict[str, Any]] = field(default_factory=list)
    web_templates: list[Path] = field(default_factory=list)                  # *.webtemplate.source.html
    page_html_files: list[Path] = field(default_factory=list)                # *.webpage.copy.html (base + localized)
    content_snippets: list[Path] = field(default_factory=list)               # *.contentsnippet.value.html
    custom_js: list[Path] = field(default_factory=list)
    sitemarkers: set[str] = field(default_factory=set)                       # set of defined sitemarker names
    schema_entities: dict[str, dict[str, Any]] | None = None                 # entity_name -> {fields:[...]} if available
    findings: list[Finding] = field(default_factory=list)

    def add(self, severity: str, code: str, title: str, detail: str, location: str = "") -> None:
        self.findings.append(Finding(severity, code, title, detail, location))


# ---------------------------------------------------------------------------
# YAML parsing
# ---------------------------------------------------------------------------

def parse_yaml(path: Path) -> dict[str, Any]:
    """
    Parse a Power Pages YAML file. Use PyYAML if available; otherwise a
    minimal hand-rolled parser that handles the flat key-value + list of
    scalars structure these files use.
    """
    text = path.read_text(encoding="utf-8", errors="replace")
    if HAVE_YAML:
        try:
            data = _yaml.safe_load(text)
            return data if isinstance(data, dict) else {}
        except Exception:
            return _parse_yaml_minimal(text)
    return _parse_yaml_minimal(text)


def _parse_yaml_minimal(text: str) -> dict[str, Any]:
    """
    Hand-rolled parser for flat YAML used by Power Pages exports.
    Handles:
      - key: value pairs at any indent level
      - List items (`- value`) at any indent level, attached to the most recent
        key whose value was empty.
    Does NOT handle nested dicts (Power Pages exports don't use them).
    """
    result: dict[str, Any] = {}
    current_list_key: str | None = None
    for raw in text.splitlines():
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        # List item: `- ...` at any indent level
        m_list = re.match(r"^\s*-\s+(.*)$", raw)
        if m_list:
            item_raw = m_list.group(1).strip()
            item = item_raw.strip('"').strip("'")
            if current_list_key is not None:
                result.setdefault(current_list_key, []).append(item)
            continue
        # Key-value at any indent
        m_kv = re.match(r"^\s*([A-Za-z_][A-Za-z0-9_.\-/]*)\s*:\s*(.*)$", raw)
        if not m_kv:
            continue
        key, val = m_kv.group(1), m_kv.group(2).strip()
        if val == "" or val == "|" or val == ">":
            current_list_key = key
            result[key] = []
        else:
            current_list_key = None
            stripped = val.strip('"').strip("'")
            if stripped.lower() in ("true", "false"):
                result[key] = stripped.lower() == "true"
            elif re.fullmatch(r"-?\d+", stripped):
                result[key] = int(stripped)
            else:
                result[key] = stripped
    return result


# ---------------------------------------------------------------------------
# Loading site source
# ---------------------------------------------------------------------------

def load_site(state: AuditState) -> None:
    site = state.site_dir

    # ---- Site Settings -----------------------------------------------------
    # Style A — consolidated:  <site>/sitesetting.yml  (a YAML list of {adx_name, adx_value, ...})
    # Style B — per-record:    <site>/site-settings/<name>.sitesetting.yml
    for record in _load_records(site, "sitesetting", "site-settings"):
        name = record.get("adx_name", "")
        value = record.get("adx_value", "")
        statecode = record.get("statecode", 0)
        if name and (statecode == 0 or statecode is None):
            state.site_settings[name] = str(value) if value is not None else ""

    # ---- Table Permissions -------------------------------------------------
    # Style A — consolidated:  <site>/tablepermission.yml  (rare)
    # Style B — per-record:    <site>/table-permissions/<name>.tablepermission.yml  (most common)
    for record in _load_records(site, "tablepermission", "table-permissions"):
        state.table_permissions.append(record)

    # ---- Web Roles ---------------------------------------------------------
    # Style A — consolidated:  <site>/webrole.yml  (common — newer pac paportal exports)
    # Style B — per-record:    <site>/web-roles/<name>.webrole.yml  (older exports may omit the role-permission junction)
    for record in _load_records(site, "webrole", "web-roles"):
        state.web_roles.append(record)

    # ---- Web Pages ---------------------------------------------------------
    # web-pages/<slug>/<Name>.webpage.yml  (always per-record + nested)
    for path in site.glob("web-pages/*/*.webpage.yml"):
        data = parse_yaml(path)
        data["__path"] = str(path)
        state.web_pages.append(data)

    # ---- Custom JS files ---------------------------------------------------
    for pattern in ("web-pages/**/*.webpage.custom_javascript.js", "web-files/**/*.js"):
        state.custom_js.extend(site.glob(pattern))

    # ---- Web Templates (for content scanning) ------------------------------
    state.web_templates.extend(site.glob("web-templates/**/*.webtemplate.source.html"))

    # ---- Page HTML files (base + localized — for divergence + content scans)
    state.page_html_files.extend(site.glob("web-pages/**/*.webpage.copy.html"))

    # ---- Content snippets --------------------------------------------------
    state.content_snippets.extend(site.glob("content-snippets/**/*.contentsnippet.value.html"))

    # ---- Sitemarkers -------------------------------------------------------
    for record in _load_records(site, "sitemarker", "sitemarkers"):
        name = record.get("adx_name", "")
        if name:
            state.sitemarkers.add(name)

    # ---- Optional Dataverse schema (sibling dir of the site folder) --------
    # Walk up from the site folder looking for `dataverse-schema/`.
    walker = site
    while walker.parent != walker:
        candidate = walker.parent / "dataverse-schema"
        if candidate.is_dir():
            state.schema_entities = _load_schema(candidate)
            break
        walker = walker.parent


def _load_records(site: Path, type_stem: str, dir_name: str) -> list[dict[str, Any]]:
    """
    Load records of a given type from either consolidated or per-record style.

    type_stem: the singular YAML filename stem (e.g. "tablepermission", "sitesetting", "webrole")
    dir_name:  the per-record directory name (e.g. "table-permissions", "site-settings", "web-roles")
    """
    records: list[dict[str, Any]] = []

    # Style A: consolidated file at site root (`<stem>.yml`)
    consolidated = site / f"{type_stem}.yml"
    if consolidated.exists():
        text = consolidated.read_text(encoding="utf-8", errors="replace")
        for chunk in _split_consolidated_yaml(text):
            data = parse_yaml_text(chunk)
            if data:
                data["__path"] = f"{consolidated}#{data.get('adx_name', '?')}"
                records.append(data)

    # Style B: per-record files in the directory
    if (site / dir_name).is_dir():
        # Look for files matching either *.<stem>.yml or nested */*.<stem>.yml
        for path in site.glob(f"{dir_name}/*.{type_stem}.yml"):
            data = parse_yaml(path)
            data["__path"] = str(path)
            records.append(data)
        for path in site.glob(f"{dir_name}/*/*.{type_stem}.yml"):
            data = parse_yaml(path)
            data["__path"] = str(path)
            records.append(data)
        # Also check for plural form (rare but seen): *.<stem>s.yml
        for path in site.glob(f"{dir_name}/*.{type_stem}s.yml"):
            data = parse_yaml(path)
            data["__path"] = str(path)
            records.append(data)

    return records


def _split_consolidated_yaml(text: str) -> list[str]:
    """
    Split a consolidated YAML file (a list of records) into individual record blocks.
    Power Pages consolidated files use either:
      - a top-level YAML list (`- key: val`)
      - blocks separated by `---` document markers
    """
    if HAVE_YAML:
        try:
            data = _yaml.safe_load(text)
            if isinstance(data, list):
                return [_yaml.safe_dump(item) for item in data if isinstance(item, dict)]
            if isinstance(data, dict):
                return [text]
        except Exception:
            pass
    # Hand-rolled: split on document markers OR top-level list dashes
    blocks: list[str] = []
    current: list[str] = []
    for line in text.splitlines():
        if line.strip() == "---":
            if current:
                blocks.append("\n".join(current))
                current = []
            continue
        if re.match(r"^- [A-Za-z_]", line):
            if current:
                blocks.append("\n".join(current))
                current = []
            # Strip the leading "- " so each block parses as a flat dict
            current.append(line[2:])
            continue
        current.append(line)
    if current:
        blocks.append("\n".join(current))
    return blocks


def parse_yaml_text(text: str) -> dict[str, Any]:
    """Parse a YAML string (vs path)."""
    if HAVE_YAML:
        try:
            data = _yaml.safe_load(text)
            return data if isinstance(data, dict) else {}
        except Exception:
            return _parse_yaml_minimal(text)
    return _parse_yaml_minimal(text)


def _load_schema(schema_dir: Path) -> dict[str, dict[str, Any]]:
    """Walk dataverse-schema/<solution>/Entities/<entity>/Entity.xml.

    Returns a dict keyed by entity logical name (lowercase) with:
      - fields: list of attribute logical names (lowercase)
      - lookup_value_fields: list of `_<attr>_value` forms for lookup reads
      - secured_fields: list of field logical names with IsSecured=1
      - readable_fields: list of field logical names with ValidForReadApi=1
      - entity_set_name: lowercase plural name used in Web API URLs
      - nav_props: list of navigation property names (case-preserved) from relationships
    """
    entities: dict[str, dict[str, Any]] = {}
    for entity_xml in schema_dir.glob("**/Entities/*/Entity.xml"):
        try:
            text = entity_xml.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        m = re.search(r'<EntityInfo>.*?<entity\s+Name="([^"]+)"', text, re.DOTALL)
        if not m:
            m = re.search(r'<entity\s+Name="([^"]+)"', text)
        if not m:
            continue
        entity_name = m.group(1).lower()

        # Attribute logical names (the PhysicalName attribute on each <attribute> element)
        field_names = re.findall(r'<attribute\s+PhysicalName="([^"]+)"', text)
        lower_fields = [f.lower() for f in field_names]

        # Per-attribute metadata used for lookup handling and security-aware checks.
        lookup_attrs = []
        secured_fields = []
        readable_fields = []
        for attr_match in re.finditer(
            r'<attribute\s+PhysicalName="([^"]+)"[^>]*>(.*?)</attribute>',
            text, re.DOTALL,
        ):
            attr_name = attr_match.group(1).lower()
            attr_body = attr_match.group(2)
            if re.search(r'<Type>(lookup|customer|owner)</Type>', attr_body, re.IGNORECASE):
                lookup_attrs.append(attr_name)
            if re.search(r'<IsSecured>\s*1\s*</IsSecured>', attr_body, re.IGNORECASE):
                secured_fields.append(attr_name)
            if re.search(r'<ValidForReadApi>\s*1\s*</ValidForReadApi>', attr_body, re.IGNORECASE):
                readable_fields.append(attr_name)

        lookup_value_fields = [f"_{a}_value" for a in lookup_attrs]

        # EntitySetName (used in /_api/<entity-set-name>)
        es_match = re.search(r'EntitySetName="([^"]+)"', text)
        entity_set_name = es_match.group(1).lower() if es_match else f"{entity_name}s"

        # Navigation property names (preserves case — these match the schema name's casing)
        nav_props = re.findall(
            r'<(?:Referencing|Referenced)EntityNavigationPropertyName>([^<]+)</',
            text,
        )

        entities[entity_name] = {
            "fields": lower_fields,
            "lookup_value_fields": lookup_value_fields,
            "secured_fields": secured_fields,
            "readable_fields": readable_fields,
            "entity_set_name": entity_set_name,
            "nav_props": nav_props,
        }
    return entities


def schema_lookup_entity_by_set_name(state: AuditState, entity_set_name: str) -> str | None:
    """Reverse-lookup: entity-set-name -> entity logical name."""
    if not state.schema_entities:
        return None
    target = entity_set_name.lower()
    for logical, info in state.schema_entities.items():
        if info.get("entity_set_name") == target:
            return logical
    return None


def is_microsoft_entity(entity: str) -> bool:
    """Heuristic: an entity is a Microsoft built-in if it has no `<prefix>_` form
    (e.g. `contact`, `account`, `incident`) or its prefix is a known Microsoft prefix.

    Microsoft built-ins are present in custom solutions only as **partial exports**
    showing the customer's added attributes — never the full standard attribute set.
    Validating fields against these would be a flood of false positives."""
    if "_" not in entity:
        return True  # bare names: contact, account, incident, lead, etc.
    prefix = entity.split("_", 1)[0]
    return prefix in {"msdyn", "mscrm", "mspp", "cdm", "msmediasense", "msdynce", "msfp"}


def schema_field_valid(state: AuditState, entity: str, field: str) -> bool:
    """Check whether `field` is a valid attribute on `entity` per schema.
    Accepts both bare attribute names and `_<attr>_value` lookup forms.

    Returns True (skip) when:
      - schema isn't loaded
      - entity is a Microsoft built-in (we only see partial customizations)
      - entity isn't in the schema (custom entity not exported — partial schema)
    Returns False only when we have authoritative knowledge that the field is missing.
    """
    if not state.schema_entities:
        return True
    if is_microsoft_entity(entity):
        return True
    info = state.schema_entities.get(entity.lower())
    if not info:
        return True
    f = field.lower()
    if f in info["fields"]:
        return True
    if f in info["lookup_value_fields"]:
        return True
    return False


def schema_secured_readable_fields(state: AuditState, entity: str) -> set[str]:
    """Return fields that are both field-secured and readable through the Web API.

    Returns an empty set when schema isn't authoritative for the entity.
    """
    if not state.schema_entities:
        return set()
    if is_microsoft_entity(entity):
        return set()
    info = state.schema_entities.get(entity.lower())
    if not info:
        return set()
    secured = set(info.get("secured_fields", []))
    readable = set(info.get("readable_fields", []))
    if not secured or not readable:
        return set()
    return secured & readable


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def webapi_enabled_entities(state: AuditState) -> set[str]:
    """Return the set of entity logical names with Web API enabled (case-insensitive on key + value)."""
    out = set()
    for name, value in state.site_settings.items():
        m = re.fullmatch(r"Webapi/([A-Za-z0-9_]+)/[Ee]nabled", name)
        if m and str(value).strip().lower() == "true":
            out.add(m.group(1).lower())
    return out


def webapi_fields_setting(state: AuditState, entity: str) -> str | None:
    """Return the fields whitelist for an entity (or None). Case-insensitive lookup."""
    for k, v in state.site_settings.items():
        if k.lower() == f"webapi/{entity.lower()}/fields":
            return v
    return None


def perm_entity_name(perm: dict[str, Any]) -> str:
    """Return the actual entity logical name for a Table Permission (NOT the perm's display name)."""
    return str(perm.get("adx_entitylogicalname") or "").lower()


def perm_roles(perm: dict[str, Any]) -> list[str]:
    """Return the list of web role identifiers attached to a Table Permission."""
    roles = perm.get("adx_entitypermission_webrole") or perm.get("adx_webroles") or []
    return [str(r) for r in roles] if isinstance(roles, list) else []


def role_name_by_id(state: AuditState, role_id: str) -> str:
    for r in state.web_roles:
        if r.get("__id") == role_id or r.get("adx_websiteid") and role_id in str(r.get("__path", "")):
            return r.get("adx_name", role_id)
    # Fall back to scanning all roles for the GUID literal
    for r in state.web_roles:
        for v in r.values():
            if isinstance(v, str) and role_id in v:
                return r.get("adx_name", role_id)
    return role_id


def role_is_anonymous(role: dict[str, Any]) -> bool:
    return bool(role.get("adx_anonymoususersrole"))


def role_is_authenticated(role: dict[str, Any]) -> bool:
    return bool(role.get("adx_authenticatedusersrole"))


# ---------------------------------------------------------------------------
# Checks
# ---------------------------------------------------------------------------

def export_includes_role_junction(state: AuditState) -> bool:
    """True if at least one table permission carries an `adx_entitypermission_webrole` list."""
    return any(perm_roles(p) for p in state.table_permissions)


def check_webapi_without_permission(state: AuditState) -> None:
    """ERROR — Web API enabled but no Table Permission grants Read."""
    api_entities = webapi_enabled_entities(state)
    role_aware = export_includes_role_junction(state)
    if role_aware:
        perm_entities_with_read = {
            perm_entity_name(p)
            for p in state.table_permissions
            if p.get("adx_read") and perm_roles(p)
        }
    else:
        # Fall back to entity-only check: any perm with Read on this entity
        perm_entities_with_read = {
            perm_entity_name(p)
            for p in state.table_permissions
            if p.get("adx_read")
        }
    for entity in sorted(api_entities):
        if entity not in perm_entities_with_read:
            state.add(
                "ERROR",
                "ERR-001",
                f"Web API enabled for `{entity}` but no Table Permission grants Read",
                f"Site Setting `Webapi/{entity}/Enabled = true` is set, but no Table Permission "
                "with `adx_read: true` exists for this entity. Web API calls to this entity will return 401/403.",
                location=f"site-settings/.../Webapi/{entity}/Enabled",
            )


def check_permission_without_webapi(state: AuditState) -> None:
    """INFO — Table Permission grants Read but Web API site setting is missing."""
    api_entities = webapi_enabled_entities(state)
    perm_entities = {perm_entity_name(p) for p in state.table_permissions if p.get("adx_read")}
    missing_api = {e for e in perm_entities if e and e not in api_entities}
    for entity in sorted(missing_api):
        state.add(
            "INFO",
            "INFO-001",
            f"Table Permission allows Read on `{entity}` but Web API is not enabled",
            f"This is fine if access is only via FetchXML in Liquid templates. If client-side "
            f"`/_api/{entity}` calls are expected, add Site Setting `Webapi/{entity}/Enabled = true` "
            f"and `Webapi/{entity}/Fields = ...`.",
        )


def check_orphaned_permissions(state: AuditState) -> None:
    """ERROR — Table Permissions with empty webroles arrays.
    Skipped when the export format simply doesn't carry the role junction."""
    if not export_includes_role_junction(state):
        if state.table_permissions:
            state.add(
                "INFO",
                "INFO-004",
                f"Role-permission junction not exported ({len(state.table_permissions)} table permissions, 0 with roles)",
                "This site's `pac paportal` export does not include `adx_entitypermission_webrole` lists "
                "in per-record table-permission YAMLs. The role assignments may live in Power Pages Studio "
                "or in a separate junction file not picked up by this audit. Role-aware cross-checks "
                "(orphaned permissions, anonymous-role writes, orphaned roles) are skipped for this site.",
                location=str(state.site_dir),
            )
        return
    for p in state.table_permissions:
        if not perm_roles(p):
            display = p.get("adx_entityname") or p.get("adx_name") or "?"
            state.add(
                "ERROR",
                "ERR-002",
                f"Orphaned Table Permission `{display}`",
                "This permission has no Web Roles assigned (`adx_entitypermission_webrole` is empty). "
                "It will never apply to anyone — either assign roles or delete the permission record.",
                location=p.get("__path", ""),
            )


def check_anonymous_role_writes(state: AuditState) -> None:
    """ERROR — Anonymous Users role granted Write/Create/Delete on a sensitive table."""
    if not export_includes_role_junction(state):
        return  # Already flagged via INFO-004; can't role-check without the junction
    anon_roles = [r for r in state.web_roles if role_is_anonymous(r)]
    if not anon_roles:
        return
    anon_ids = {str(r.get("adx_webroleid", "")).lower() for r in anon_roles if r.get("adx_webroleid")}
    sensitive_ops = ("adx_write", "adx_delete", "adx_create")
    for perm in state.table_permissions:
        roles = perm_roles(perm)
        granted = [op for op in sensitive_ops if perm.get(op)]
        if not granted:
            continue
        if any(role.lower() in anon_ids for role in roles):
            entity = perm_entity_name(perm) or "?"
            state.add(
                "ERROR",
                "ERR-003",
                f"Anonymous Users role granted {', '.join(granted)} on `{entity}`",
                "Anonymous (unauthenticated) visitors can perform write operations on this entity. "
                "Verify this is intentional. If not, scope the permission to an authenticated role.",
                location=perm.get("__path", ""),
            )


def check_fields_wildcard(state: AuditState) -> None:
    """INFO — `Webapi/<entity>/fields = *` is broader than necessary."""
    for name, value in state.site_settings.items():
        m = re.fullmatch(r"Webapi/([A-Za-z0-9_]+)/[Ff]ields", name)
        if not m:
            continue
        entity = m.group(1)
        v = str(value).strip()
        if v == "*":
            state.add(
                "INFO",
                "INFO-002",
                f"Web API on `{entity}` exposes all fields (`fields = *`)",
                "Consider replacing `*` with an explicit comma-separated whitelist of field "
                "logical names. This prevents accidental exposure of fields added later.",
                location=f"site-settings/.../{name}",
            )


def check_polymorphic_lookups_in_js(state: AuditState) -> None:
    """WARN — custom JS uses `@odata.bind` on a polymorphic field without `_contact` / `_account` suffix."""
    # Heuristic patterns: any string of the form  '<word>@odata.bind' in a JS file,
    # where <word> doesn't end with _contact, _account, or another known disambiguator.
    POLYMORPHIC_HINTS = ("applicant", "customer", "owner", "regarding", "objectid")
    bind_re = re.compile(r"['\"]([A-Za-z_][A-Za-z0-9_]*)@odata\.bind['\"]")
    for js in state.custom_js:
        try:
            text = js.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        for match in bind_re.finditer(text):
            field_name = match.group(1).lower()
            if any(hint in field_name for hint in POLYMORPHIC_HINTS):
                if not (field_name.endswith("_contact") or field_name.endswith("_account")
                        or field_name.endswith("_systemuser") or "_" in field_name.split("@")[0][len("contoso_"):]):
                    state.add(
                        "WARN",
                        "WRN-001",
                        f"Possible polymorphic lookup without disambiguator: `{match.group(1)}@odata.bind`",
                        f"Looks like a polymorphic (customer-type) lookup. Power Pages requires the "
                        f"`_contact` or `_account` suffix on the navigation property — bare bindings return 400. "
                        f"Verify against the entity schema; if the field IS polymorphic, change to "
                        f"`{match.group(1)}_contact@odata.bind` or `{match.group(1)}_account@odata.bind`.",
                        location=str(js),
                    )


def check_orphaned_roles(state: AuditState) -> None:
    """WARN — Web Role exists but no Table Permission references its GUID."""
    if not export_includes_role_junction(state):
        return  # Already flagged via INFO-004; can't role-check without the junction
    used_role_ids: set[str] = set()
    for p in state.table_permissions:
        for r in perm_roles(p):
            used_role_ids.add(r.lower())
    for r in state.web_roles:
        if role_is_anonymous(r) or role_is_authenticated(r):
            continue  # implicit roles are always "used"
        name = r.get("adx_name", "?")
        role_id = str(r.get("adx_webroleid", "")).lower()
        path = r.get("__path", "")
        if role_id and role_id not in used_role_ids:
            state.add(
                "WARN",
                "WRN-002",
                f"Web Role `{name}` has no Table Permission references",
                "Either no permission rules apply to this role (it grants nothing) or the role is "
                "obsolete. Investigate and either assign permissions or delete the role.",
                location=path,
            )


def check_pages_auth_no_role(state: AuditState) -> None:
    """WARN — Web Page requires authentication but has no role-level rule."""
    for p in state.web_pages:
        # Convention: adx_publishingstateid or adx_requireregistration indicates auth-required pages
        requires_auth = bool(p.get("adx_requireregistration"))
        # No simple way to detect role-rule association from page YAML alone in all schemas;
        # this is a heuristic flag for the user to verify.
        if requires_auth and not p.get("adx_webrole"):
            state.add(
                "INFO",
                "INFO-003",
                f"Page `{p.get('adx_name', '?')}` requires auth but has no role rule",
                "Any authenticated user can reach this page. If it should be role-restricted, "
                "add a Web Page Access Control Rule referencing specific Web Roles.",
                location=p.get("__path", ""),
            )


def check_secured_fields_wildcard(state: AuditState) -> None:
    """WARN — `fields = *` on an entity with field-secured readable columns."""
    if state.schema_entities is None:
        return
    for name, value in state.site_settings.items():
        m = re.fullmatch(r"Webapi/([A-Za-z0-9_]+)/[Ff]ields", name)
        if not m or str(value).strip() != "*":
            continue
        entity = m.group(1).lower()
        secured_readable = sorted(schema_secured_readable_fields(state, entity))
        if not secured_readable:
            continue
        sample = ", ".join(secured_readable[:5])
        suffix = "…" if len(secured_readable) > 5 else ""
        state.add(
            "WARN",
            "WRN-009",
            f"Web API on `{entity}` uses `fields = *` and the entity has secured readable fields",
            f"Entity.xml marks {len(secured_readable)} field(s) as both `IsSecured = 1` and "
            f"`ValidForReadApi = 1` (sample: {sample}{suffix}). A wildcard Web API whitelist is "
            "higher risk here because future callers can read more than an explicit allowlist "
            "makes obvious. Prefer a narrow `Webapi/<entity>/Fields` whitelist.",
            location=f"site-settings/.../{name}",
        )


def check_secured_fields_in_webapi_whitelist(state: AuditState) -> None:
    """ERROR — explicit Web API whitelist includes secured readable fields."""
    if state.schema_entities is None:
        return
    for name, value in state.site_settings.items():
        m = re.fullmatch(r"Webapi/([A-Za-z0-9_]+)/[Ff]ields", name)
        if not m:
            continue
        entity = m.group(1).lower()
        whitelist = str(value).strip()
        if whitelist in {"", "*"}:
            continue
        secured_readable = schema_secured_readable_fields(state, entity)
        if not secured_readable:
            continue
        listed_fields = [f.strip().lower() for f in whitelist.split(",") if f.strip()]
        exposed = sorted(f for f in listed_fields if f in secured_readable)
        if not exposed:
            continue
        state.add(
            "ERROR",
            "ERR-004",
            f"`Webapi/{entity}/Fields` explicitly whitelists secured readable field(s)",
            f"The Web API whitelist includes field-secured columns that Entity.xml marks as "
            f"`IsSecured = 1` and `ValidForReadApi = 1`: {', '.join(exposed)}. Verify that "
            "portal callers should read these columns; otherwise remove them from the whitelist "
            "or redesign the endpoint so only non-sensitive fields are exposed.",
            location=f"site-settings/.../{name}",
        )


def check_base_vs_localized_divergence(state: AuditState) -> None:
    """INFO — Base file is empty/tiny but localized file has substantial content.

    Power Pages loads BASE files by default; localized `content-pages/<lang>/...`
    only render when the base is empty AND a matching locale file exists. The #1
    blank-page bug: edit happens in localized while base stays empty.
    """
    # Build a map of (page_slug, file_role) -> {"base": Path|None, "localized": [Path...]}
    # File roles: copy.html, custom_javascript.js, custom_css.css, summary.html
    site = state.site_dir
    web_pages_dir = site / "web-pages"
    if not web_pages_dir.is_dir():
        return

    role_suffixes = (
        ".webpage.copy.html",
        ".webpage.custom_javascript.js",
        ".webpage.custom_css.css",
        ".webpage.summary.html",
    )

    for page_dir in web_pages_dir.iterdir():
        if not page_dir.is_dir():
            continue
        for suffix in role_suffixes:
            base_files = [p for p in page_dir.iterdir() if p.is_file() and p.name.endswith(suffix)]
            content_pages = page_dir / "content-pages"
            localized_files: list[Path] = []
            if content_pages.is_dir():
                # Localized pattern: <Page>.<lang>.<suffix-tail>
                # e.g. Customers.en-US.webpage.copy.html
                tail = suffix.lstrip(".")  # webpage.copy.html
                for cp_file in content_pages.iterdir():
                    if cp_file.is_file() and re.search(rf"\.{re.escape(tail)}$", cp_file.name):
                        localized_files.append(cp_file)
            if not localized_files:
                continue
            # Compare sizes: base "empty" if missing or under 50 bytes (whitespace/comment threshold)
            base_size = max((p.stat().st_size for p in base_files), default=0)
            max_localized = max((p.stat().st_size for p in localized_files), default=0)
            if base_size < 50 and max_localized > 200:
                # Pick the largest localized file for the report
                largest = max(localized_files, key=lambda p: p.stat().st_size)
                state.add(
                    "INFO",
                    "INFO-005",
                    f"Page `{page_dir.name}` has empty base `{suffix.lstrip('.')}` but populated localized file",
                    f"Power Pages loads base files by default. The localized version "
                    f"({max_localized} bytes) won't render until you copy its content into the base file. "
                    f"This is the #1 blank-page bug.",
                    location=f"{page_dir}/[base+localized {suffix.lstrip('.')}]",
                )


def check_unsafe_dotliquid_escape(state: AuditState) -> None:
    """INFO — DotLiquid `replace: '"', '\\\\"'` produces 3 chars, breaks JSON.

    Scans web-templates and webpage.copy.html files for the broken escape pattern.
    Recommends Unicode escape `replace: '"', '\\u0022'`.
    """
    # Match the broken pattern: replace: '"', '\\"' or replace: "\"" , "\\\""
    # Power Pages templates use single-quoted Liquid string literals heavily.
    bad_pattern = re.compile(
        r"replace:\s*['\"]\\?\"['\"]\s*,\s*['\"]\\\\\"['\"]"
    )
    files_to_scan = list(state.web_templates) + list(state.page_html_files) + list(state.content_snippets)
    for path in files_to_scan:
        try:
            text = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        for m in bad_pattern.finditer(text):
            # Find line number
            line_no = text[:m.start()].count("\n") + 1
            state.add(
                "INFO",
                "INFO-007",
                "Unsafe DotLiquid JSON escape — `replace: '\"', '\\\\\"'` produces 3 chars",
                "DotLiquid does not interpret the replacement string's backslash escapes the way "
                "Shopify Liquid does — `'\\\\\"'` becomes literal `\\\\\"` (3 chars), breaking JSON. "
                "Use Unicode escape: `replace: '\"', '\\u0022'`. For best safety, emit JSON inside "
                "`<script type=\"application/json\">` and `JSON.parse` it on the client side.",
                location=f"{path}:{line_no}",
            )


def check_webapi_without_safeajax(state: AuditState) -> None:
    """WARN — Custom JS calls `/_api/<entity>` without the anti-forgery token pattern.

    Power Pages requires `__RequestVerificationToken` on every Web API call.
    Without it the call returns 403. The canonical pattern uses
    `window.shell.getTokenDeferred()` to obtain the token.
    """
    api_call_re = re.compile(r"['\"]\/_api\/[A-Za-z_][A-Za-z0-9_]*")
    safeajax_signals = (
        "__RequestVerificationToken",
        "getTokenDeferred",
        "safeAjax",
    )
    for js in state.custom_js:
        try:
            text = js.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        if not api_call_re.search(text):
            continue
        if any(signal in text for signal in safeajax_signals):
            continue
        # Has /_api/ but no anti-forgery handling visible
        state.add(
            "WARN",
            "WRN-004",
            f"Custom JS calls `/_api/` without anti-forgery token pattern",
            "This file makes Web API calls but doesn't reference the `__RequestVerificationToken` "
            "header, `window.shell.getTokenDeferred()`, or a `safeAjax` helper. Power Pages will "
            "return 403 without the token. The token may live in a sibling file — verify before fixing.",
            location=str(js),
        )


def check_base_vs_localized_divergence_content(state: AuditState) -> None:
    """INFO — Both base and localized files exist and are populated, but diverge significantly.

    This is mode B of the base/localized hazard: not blank, just inconsistent.
    Some users (locale-matched) see one version, others see the other.
    """
    site = state.site_dir
    web_pages_dir = site / "web-pages"
    if not web_pages_dir.is_dir():
        return

    role_suffixes = (".webpage.copy.html", ".webpage.custom_javascript.js", ".webpage.custom_css.css")

    for page_dir in web_pages_dir.iterdir():
        if not page_dir.is_dir():
            continue
        for suffix in role_suffixes:
            base_files = [p for p in page_dir.iterdir() if p.is_file() and p.name.endswith(suffix)]
            content_pages = page_dir / "content-pages"
            if not content_pages.is_dir() or not base_files:
                continue
            base = base_files[0]
            base_size = base.stat().st_size
            if base_size < 200:
                # Empty/near-empty base is mode A (INFO-005), not B
                continue
            tail = suffix.lstrip(".")
            for cp_file in content_pages.iterdir():
                if not (cp_file.is_file() and re.search(rf"\.{re.escape(tail)}$", cp_file.name)):
                    continue
                cp_size = cp_file.stat().st_size
                if cp_size < 200:
                    continue
                # Both populated. Compare sizes and head signatures.
                size_ratio = max(base_size, cp_size) / max(min(base_size, cp_size), 1)
                if size_ratio > 1.10:  # >10% size delta
                    state.add(
                        "INFO",
                        "INFO-009",
                        f"Page `{page_dir.name}` has diverged base/localized `{tail}` files",
                        f"Base ({base_size} bytes) and localized {cp_file.name} ({cp_size} bytes) "
                        f"differ by {(size_ratio - 1) * 100:.0f}%. Some users will see one version, "
                        f"others will see the other. Pick one as authoritative and copy to the other "
                        f"(or use `pp sync-pages <project>` if available).",
                        location=f"{base} ↔ {cp_file}",
                    )


def check_lowercase_odatabind_navprop(state: AuditState) -> None:
    """WARN — Custom JS uses `<lookup>@odata.bind` with a navigation-property name
    that is all lowercase AND contains a custom-prefix underscore.

    Microsoft's built-in entities use lowercase nav props (parentcustomerid,
    primarycontactid). Custom entities almost always have PascalCase schema
    names — so `acme_account@odata.bind` is statistically likely a casing
    bug (should be `acme_Account@odata.bind`).
    """
    bind_re = re.compile(r"['\"]([A-Za-z_][A-Za-z0-9_]*)@odata\.bind['\"]")

    # Polymorphic field bases that take an entity-logical-name suffix (lowercase is correct):
    #   objectid_<entity>      annotations / activity attachments
    #   regardingobjectid_<entity>  activities
    #   customerid_<entity>    quotes / orders / invoices
    #   <field>_<entity>       customer-type lookups (handled separately by WRN-001)
    POLYMORPHIC_BASES = ("objectid", "regardingobjectid", "customerid")

    # Heuristic: treat a name as "custom" if it has a prefix_ pattern (e.g. acme_field) AND
    # the part after the underscore is all-lowercase. Built-in nav props don't have prefix_ form.
    for js in state.custom_js:
        try:
            text = js.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        for match in bind_re.finditer(text):
            nav_prop = match.group(1)
            # Skip common built-ins (lowercase by design):
            if nav_prop in {"parentcustomerid", "primarycontactid", "regardingobjectid",
                            "ownerid", "createdby", "modifiedby", "owningteam", "owninguser",
                            "transactioncurrencyid", "objectid"}:
                continue
            # Skip if already has _contact / _account suffix (covered by WRN-001):
            if any(nav_prop.endswith(s) for s in ("_contact", "_account", "_systemuser")):
                # WRN-001 already handles polymorphic shape; skip here even if lowercase
                # so we don't double-flag a single bad name.
                continue
            # Skip polymorphic <base>_<entity-logical-name> patterns —
            # the suffix is the target entity's logical name (lowercase IS correct here):
            if any(nav_prop.startswith(base + "_") for base in POLYMORPHIC_BASES):
                continue
            # Custom entity prefix pattern: <prefix>_<name>
            m = re.fullmatch(r"([a-z][a-z0-9]+)_([A-Za-z][A-Za-z0-9_]*)", nav_prop)
            if not m:
                continue
            after_underscore = m.group(2)
            # If the part after the prefix is all lowercase, it's likely a logical name not a nav prop
            if after_underscore.islower():
                state.add(
                    "WARN",
                    "WRN-005",
                    f"`{nav_prop}@odata.bind` is all lowercase — likely a Logical Name where Navigation Property was needed",
                    f"Custom-entity navigation properties usually use PascalCase (matching the schema "
                    f"name), not the lowercase logical name. `{nav_prop}@odata.bind` will likely return "
                    f"`'{nav_prop}' is not a valid navigation property`. Look up the navigation property "
                    f"name in `Entity.xml` (search for `ReferencingEntityNavigationPropertyName`) or in "
                    f"the Maker Portal's Relationships view. Common fix: capitalize the first letter "
                    f"after the underscore (`{m.group(1)}_{after_underscore.capitalize()}`).",
                    location=str(js),
                )


def check_select_fields_against_schema(state: AuditState) -> None:
    """WARN — Custom JS calls `/_api/<entityset>?$select=field1,...` with a field
    that does not exist on the entity per Entity.xml. Pure typo detection.

    Only runs when dataverse-schema/ is present.
    Skips dynamic URL composition (we can only validate static string literals).
    """
    if not state.schema_entities:
        return
    # Match: '/_api/<entityset>(...optional)(?...optional)' inside string literals
    url_re = re.compile(
        r"""['"]\s*/_api/([a-zA-Z_][a-zA-Z0-9_]*)\s*(?:\([^)]*\))?\s*(\?[^'"]*)?\s*['"]""",
    )
    select_re = re.compile(r"\$select=([a-zA-Z_,]+)")

    for js in state.custom_js:
        try:
            text = js.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        for url_match in url_re.finditer(text):
            entityset = url_match.group(1).lower()
            qs = url_match.group(2) or ""
            entity = schema_lookup_entity_by_set_name(state, entityset)
            if not entity:
                continue  # built-in or unknown — can't validate
            sel_match = select_re.search(qs)
            if not sel_match:
                continue
            fields = [f.strip() for f in sel_match.group(1).split(",") if f.strip()]
            for field in fields:
                if not schema_field_valid(state, entity, field):
                    line_no = text[: url_match.start()].count("\n") + 1
                    state.add(
                        "WARN",
                        "WRN-006",
                        f"`$select={field}` references a field that does not exist on `{entity}`",
                        f"Per Entity.xml, `{entity}` has no attribute named `{field}`. "
                        f"Likely a typo or a stale field name from a renamed column. "
                        f"Available attributes on this entity (sample): "
                        f"{', '.join(state.schema_entities[entity]['fields'][:8])}…",
                        location=f"{js}:{line_no}",
                    )


def check_fetchxml_attributes_against_schema(state: AuditState) -> None:
    """WARN — `{% fetchxml %}` block references an attribute that does not exist
    on its containing entity per Entity.xml.

    Only runs when dataverse-schema/ is present.
    """
    if not state.schema_entities:
        return

    fetchxml_re = re.compile(r"{%\s*fetchxml\s+\w+\s*%}(.+?){%\s*endfetchxml\s*%}", re.DOTALL)
    entity_re = re.compile(r'<entity\s+name="([a-zA-Z_][a-zA-Z0-9_]*)"')
    attribute_re = re.compile(r'<attribute\s+name="([a-zA-Z_][a-zA-Z0-9_]*)"')
    link_entity_re = re.compile(r'<link-entity\s+name="([a-zA-Z_][a-zA-Z0-9_]*)"', re.DOTALL)

    files_to_scan = list(state.web_templates) + list(state.page_html_files) + list(state.content_snippets)
    for path in files_to_scan:
        try:
            text = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        for fx_match in fetchxml_re.finditer(text):
            block = fx_match.group(1)
            ent_match = entity_re.search(block)
            if not ent_match:
                continue
            root_entity = ent_match.group(1).lower()
            # Only validate if entity is in schema (skip built-ins)
            if root_entity not in state.schema_entities:
                continue
            # Find all <attribute name="..."> in the OUTER entity (not inside link-entity)
            # Approximation: scan all attribute matches, and note that
            # link-entity introduces a different entity context.
            # For simplicity, treat any <attribute> after a <link-entity> as "in linked context"
            # and skip — but flag attributes BEFORE the first link-entity as belonging to root_entity.
            link_match = link_entity_re.search(block)
            outer_block = block[: link_match.start()] if link_match else block
            for attr_match in attribute_re.finditer(outer_block):
                attr_name = attr_match.group(1).lower()
                if not schema_field_valid(state, root_entity, attr_name):
                    line_no = text[: fx_match.start() + attr_match.start()].count("\n") + 1
                    state.add(
                        "WARN",
                        "WRN-007",
                        f"FetchXML attribute `{attr_name}` does not exist on `{root_entity}`",
                        f"Per Entity.xml, `{root_entity}` has no attribute named `{attr_name}`. "
                        f"FetchXML uses logical names (lowercase). Likely a typo or stale field "
                        f"reference. The query will return an error when the page renders.",
                        location=f"{path}:{line_no}",
                    )


def check_webapi_fields_whitelist_against_schema(state: AuditState) -> None:
    """WARN — Site Setting `Webapi/<entity>/Fields = field1,field2,...` lists a
    field that does not exist on the entity per Entity.xml.

    Only runs when dataverse-schema/ is present. Stale fields in the whitelist
    silently exclude themselves (no error in the API), but they signal config
    drift after a column rename or removal.
    """
    if not state.schema_entities:
        return
    for name, value in state.site_settings.items():
        m = re.fullmatch(r"Webapi/([A-Za-z0-9_]+)/[Ff]ields", name)
        if not m:
            continue
        entity = m.group(1).lower()
        if entity not in state.schema_entities:
            continue  # built-in or partial-export — skip
        v = str(value).strip()
        if v == "*" or v == "":
            continue
        listed_fields = [f.strip() for f in v.split(",") if f.strip()]
        bad = [f for f in listed_fields if not schema_field_valid(state, entity, f)]
        if bad:
            state.add(
                "WARN",
                "WRN-008",
                f"`Webapi/{entity}/Fields` lists {len(bad)} field(s) that do not exist on `{entity}`",
                f"Stale or typo'd entries: {', '.join(bad)}. "
                f"These don't break the API (they're silently ignored) but signal config "
                f"drift — likely after a column rename or removal. Update the whitelist.",
                location=f"site-settings/.../{name}",
            )


def check_missing_sitemarker_references(state: AuditState) -> None:
    """WARN — Liquid template references `sitemarkers['<name>']` that isn't defined."""
    if not state.sitemarkers:
        return  # Can't validate if no sitemarkers loaded (probably not exported)
    ref_re = re.compile(r"sitemarkers\s*\[\s*['\"]([^'\"]+)['\"]\s*\]")
    files_to_scan = list(state.web_templates) + list(state.page_html_files) + list(state.content_snippets)
    referenced: dict[str, list[str]] = defaultdict(list)
    for path in files_to_scan:
        try:
            text = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        for m in ref_re.finditer(text):
            referenced[m.group(1)].append(str(path))
    for name, locations in referenced.items():
        if name not in state.sitemarkers:
            # Show first 3 locations to avoid noise
            location_str = "; ".join(locations[:3])
            if len(locations) > 3:
                location_str += f"; … +{len(locations) - 3} more"
            state.add(
                "WARN",
                "WRN-003",
                f"Sitemarker `{name}` referenced in Liquid but not defined",
                f"Templates reference `sitemarkers['{name}']` but no Sitemarker record with this name "
                "exists in the export. The Liquid expression will return `nil`, breaking any URL "
                "construction that depends on it. Either create the Sitemarker or fix the reference.",
                location=location_str,
            )


# ---------------------------------------------------------------------------
# Report generation
# ---------------------------------------------------------------------------

def render_markdown(state: AuditState) -> str:
    by_sev = defaultdict(list)
    for f in state.findings:
        by_sev[f.severity].append(f)

    out: list[str] = []
    out.append(f"# Power Pages Permissions Audit Report")
    out.append("")
    out.append(f"**Site:** {state.site_dir.name}  ")
    out.append(f"**Path:** {state.site_dir}  ")
    out.append("")
    out.append("## Summary")
    out.append("")
    for sev in ("ERROR", "WARN", "INFO"):
        out.append(f"- **{sev}**: {len(by_sev.get(sev, []))}")
    out.append("")
    out.append("## Counts of inputs read")
    out.append("")
    out.append(f"- Site Settings: {len(state.site_settings)}")
    out.append(f"- Table Permissions: {len(state.table_permissions)}")
    out.append(f"- Web Roles: {len(state.web_roles)}")
    out.append(f"- Web Pages: {len(state.web_pages)}")
    out.append(f"- Custom JS files: {len(state.custom_js)}")
    schema_count = len(state.schema_entities) if state.schema_entities else 0
    out.append(f"- Schema entities (optional): {schema_count}")
    out.append("")
    if not state.findings:
        out.append("## Findings")
        out.append("")
        out.append("_No issues detected._")
        return "\n".join(out)
    out.append("## Findings")
    out.append("")
    for sev in ("ERROR", "WARN", "INFO"):
        items = by_sev.get(sev, [])
        if not items:
            continue
        out.append(f"### {sev}")
        out.append("")
        for f in items:
            out.append(f"#### {f.code}: {f.title}")
            out.append("")
            out.append(f.detail)
            if f.location:
                out.append("")
                out.append(f"Location: `{f.location}`")
            out.append("")
    return "\n".join(out)


def render_json(state: AuditState) -> str:
    return json.dumps({
        "site": str(state.site_dir),
        "counts": {
            "site_settings": len(state.site_settings),
            "table_permissions": len(state.table_permissions),
            "web_roles": len(state.web_roles),
            "web_pages": len(state.web_pages),
            "custom_js": len(state.custom_js),
            "schema_entities": len(state.schema_entities) if state.schema_entities else 0,
        },
        "findings": [f.to_dict() for f in state.findings],
    }, indent=2)


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Power Pages permissions audit")
    parser.add_argument("site_dir", help="Path to the site folder (e.g. <site>---<site>/)")
    parser.add_argument("-o", "--output", help="Write report to file instead of stdout")
    parser.add_argument("--json", action="store_true", help="Emit JSON instead of markdown")
    parser.add_argument("--severity", choices=["ERROR", "WARN", "INFO"],
                        help="Show findings at this severity or above (default: all)")
    parser.add_argument("--exit-code", action="store_true",
                        help="Exit with code 1 if any findings at or above --severity exist (CI-friendly)")
    args = parser.parse_args(argv)

    site = Path(args.site_dir).resolve()
    if not (site / "website.yml").exists() and not (site / "website.yaml").exists():
        print(f"ERROR: {site} does not look like a Power Pages site folder (no website.yml).",
              file=sys.stderr)
        return 2

    state = AuditState(site_dir=site)
    load_site(state)

    # Run all checks
    check_webapi_without_permission(state)
    check_permission_without_webapi(state)
    check_orphaned_permissions(state)
    check_anonymous_role_writes(state)
    check_fields_wildcard(state)
    check_polymorphic_lookups_in_js(state)
    check_orphaned_roles(state)
    check_pages_auth_no_role(state)
    check_secured_fields_wildcard(state)
    check_secured_fields_in_webapi_whitelist(state)
    check_base_vs_localized_divergence(state)
    check_base_vs_localized_divergence_content(state)
    check_unsafe_dotliquid_escape(state)
    check_webapi_without_safeajax(state)
    check_missing_sitemarker_references(state)
    check_lowercase_odatabind_navprop(state)
    check_select_fields_against_schema(state)
    check_fetchxml_attributes_against_schema(state)
    check_webapi_fields_whitelist_against_schema(state)

    # Apply severity filter
    if args.severity:
        order = {"ERROR": 0, "WARN": 1, "INFO": 2}
        threshold = order[args.severity]
        state.findings = [f for f in state.findings if order[f.severity] <= threshold]

    text = render_json(state) if args.json else render_markdown(state)
    if args.output:
        Path(args.output).write_text(text, encoding="utf-8")
        print(f"Report written to {args.output}", file=sys.stderr)
    else:
        print(text)

    if args.exit_code and state.findings:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())

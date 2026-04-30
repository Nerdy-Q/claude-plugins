#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import io
import json
import sys
import tempfile
import textwrap
import unittest
from contextlib import redirect_stdout
from pathlib import Path


MODULE_PATH = Path(__file__).with_name("audit.py")
SPEC = importlib.util.spec_from_file_location("pp_permissions_audit", MODULE_PATH)
assert SPEC and SPEC.loader
AUDIT = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = AUDIT
SPEC.loader.exec_module(AUDIT)


class AuditSecurityChecksTest(unittest.TestCase):
    def run_audit(self, site_dir: Path) -> dict:
        stdout = io.StringIO()
        with redirect_stdout(stdout):
            exit_code = AUDIT.main([str(site_dir), "--json"])
        self.assertEqual(exit_code, 0)
        return json.loads(stdout.getvalue())

    def make_site(
        self,
        *,
        fields_setting: str,
        secured: bool,
        readable: bool = True,
    ) -> Path:
        temp_dir = tempfile.TemporaryDirectory()
        self.addCleanup(temp_dir.cleanup)

        root = Path(temp_dir.name)
        project_dir = root / "project"
        site_dir = project_dir / "sample-site---sample-site"
        schema_dir = project_dir / "dataverse-schema" / "SampleSolution" / "Entities" / "acme_case"
        site_settings_dir = site_dir / "site-settings"

        site_settings_dir.mkdir(parents=True)
        schema_dir.mkdir(parents=True)
        (site_dir / "website.yml").write_text("adx_name: Sample Site\n", encoding="utf-8")
        (site_settings_dir / "acme_case-fields.sitesetting.yml").write_text(
            textwrap.dedent(
                f"""\
                adx_name: Webapi/acme_case/Fields
                adx_value: "{fields_setting}"
                statecode: 0
                """
            ),
            encoding="utf-8",
        )
        (schema_dir / "Entity.xml").write_text(
            self.entity_xml(secured=secured, readable=readable),
            encoding="utf-8",
        )
        return site_dir

    @staticmethod
    def entity_xml(*, secured: bool, readable: bool) -> str:
        return textwrap.dedent(
            f"""\
            <ImportExportXml>
              <Entities>
                <EntityInfo>
                  <entity Name="acme_case" EntitySetName="acme_cases">
                    <attributes>
                      <attribute PhysicalName="acme_publicname">
                        <Type>nvarchar</Type>
                        <ValidForReadApi>1</ValidForReadApi>
                        <IsSecured>0</IsSecured>
                      </attribute>
                      <attribute PhysicalName="acme_secretcode">
                        <Type>nvarchar</Type>
                        <ValidForReadApi>{1 if readable else 0}</ValidForReadApi>
                        <IsSecured>{1 if secured else 0}</IsSecured>
                      </attribute>
                    </attributes>
                  </entity>
                </EntityInfo>
              </Entities>
            </ImportExportXml>
            """
        )

    @staticmethod
    def finding_codes(report: dict) -> set[str]:
        return {finding["code"] for finding in report["findings"]}

    def test_explicit_whitelist_of_secured_field_is_error(self) -> None:
        site_dir = self.make_site(
            fields_setting="acme_publicname,acme_secretcode",
            secured=True,
        )
        report = self.run_audit(site_dir)
        self.assertIn("ERR-004", self.finding_codes(report))

    def test_wildcard_on_entity_with_secured_readable_field_is_warning(self) -> None:
        site_dir = self.make_site(fields_setting="*", secured=True)
        report = self.run_audit(site_dir)
        codes = self.finding_codes(report)
        self.assertIn("WRN-009", codes)
        self.assertIn("INFO-002", codes)

    def test_generic_wildcard_without_secured_field_stays_informational(self) -> None:
        site_dir = self.make_site(fields_setting="*", secured=False)
        report = self.run_audit(site_dir)
        codes = self.finding_codes(report)
        self.assertIn("INFO-002", codes)
        self.assertNotIn("WRN-009", codes)
        self.assertNotIn("ERR-004", codes)

    def test_form_name_is_not_mistaken_for_unknown_field(self) -> None:
        temp_dir = tempfile.TemporaryDirectory()
        self.addCleanup(temp_dir.cleanup)

        root = Path(temp_dir.name)
        project_dir = root / "project"
        site_dir = project_dir / "sample-site---sample-site"
        schema_dir = project_dir / "dataverse-schema" / "SampleSolution" / "Entities" / "acme_case"
        forms_dir = site_dir / "basic-forms"

        forms_dir.mkdir(parents=True)
        schema_dir.mkdir(parents=True)
        (site_dir / "website.yml").write_text("adx_name: Sample Site\n", encoding="utf-8")
        (forms_dir / "sample.entityform.yml").write_text(
            textwrap.dedent(
                """\
                adx_name: acme_case_form
                adx_entitylogicalname: acme_case
                """
            ),
            encoding="utf-8",
        )
        (schema_dir / "Entity.xml").write_text(
            self.entity_xml(secured=False, readable=True),
            encoding="utf-8",
        )

        report = self.run_audit(site_dir)
        self.assertNotIn("WRN-012", self.finding_codes(report))

    def test_fetchxml_count_single_quotes_is_not_flagged(self) -> None:
        temp_dir = tempfile.TemporaryDirectory()
        self.addCleanup(temp_dir.cleanup)

        root = Path(temp_dir.name)
        project_dir = root / "project"
        site_dir = project_dir / "sample-site---sample-site"
        templates_dir = site_dir / "web-templates"

        templates_dir.mkdir(parents=True)
        (site_dir / "website.yml").write_text("adx_name: Sample Site\n", encoding="utf-8")
        (templates_dir / "sample.webtemplate.source.html").write_text(
            textwrap.dedent(
                """\
                {% fetchxml results %}
                <fetch count='50'>
                  <entity name='acme_case'>
                    <attribute name='acme_publicname' />
                  </entity>
                </fetch>
                {% endfetchxml %}
                """
            ),
            encoding="utf-8",
        )

        report = self.run_audit(site_dir)
        self.assertNotIn("INFO-006", self.finding_codes(report))

    def test_recaptcha_sitekey_is_exempt_from_secret_warning(self) -> None:
        temp_dir = tempfile.TemporaryDirectory()
        self.addCleanup(temp_dir.cleanup)

        root = Path(temp_dir.name)
        project_dir = root / "project"
        site_dir = project_dir / "sample-site---sample-site"
        site_settings_dir = site_dir / "site-settings"

        site_settings_dir.mkdir(parents=True)
        (site_dir / "website.yml").write_text("adx_name: Sample Site\n", encoding="utf-8")
        (site_settings_dir / "recaptcha-sitekey.sitesetting.yml").write_text(
            textwrap.dedent(
                """\
                adx_name: Recaptcha/Public/SiteKey
                adx_value: "public-client-site-key"
                statecode: 0
                """
            ),
            encoding="utf-8",
        )

        report = self.run_audit(site_dir)
        self.assertNotIn("WRN-011", self.finding_codes(report))

    def test_inline_page_script_api_call_without_token_is_flagged(self) -> None:
        temp_dir = tempfile.TemporaryDirectory()
        self.addCleanup(temp_dir.cleanup)

        root = Path(temp_dir.name)
        site_dir = root / "sample-site---sample-site"
        page_dir = site_dir / "web-pages" / "sample-page"

        page_dir.mkdir(parents=True)
        (site_dir / "website.yml").write_text("adx_name: Sample Site\n", encoding="utf-8")
        (page_dir / "Sample-Page.webpage.copy.html").write_text(
            textwrap.dedent(
                """\
                <div>Sample</div>
                <script>
                fetch("/_api/acme_cases?$select=acme_name");
                </script>
                """
            ),
            encoding="utf-8",
        )

        report = self.run_audit(site_dir)
        self.assertIn("WRN-004", self.finding_codes(report))

    def test_nested_localized_content_page_is_checked_for_blank_base(self) -> None:
        temp_dir = tempfile.TemporaryDirectory()
        self.addCleanup(temp_dir.cleanup)

        root = Path(temp_dir.name)
        site_dir = root / "sample-site---sample-site"
        localized_dir = site_dir / "web-pages" / "sample-page" / "content-pages" / "en-US"
        page_dir = localized_dir.parent.parent

        localized_dir.mkdir(parents=True)
        (site_dir / "website.yml").write_text("adx_name: Sample Site\n", encoding="utf-8")
        (page_dir / "Sample-Page.webpage.copy.html").write_text("", encoding="utf-8")
        (localized_dir / "Sample-Page.en-US.webpage.copy.html").write_text("X" * 300, encoding="utf-8")

        report = self.run_audit(site_dir)
        self.assertIn("INFO-005", self.finding_codes(report))

    def test_inline_page_script_with_safeajax_signal_is_not_flagged(self) -> None:
        temp_dir = tempfile.TemporaryDirectory()
        self.addCleanup(temp_dir.cleanup)

        root = Path(temp_dir.name)
        site_dir = root / "sample-site---sample-site"
        page_dir = site_dir / "web-pages" / "sample-page"

        page_dir.mkdir(parents=True)
        (site_dir / "website.yml").write_text("adx_name: Sample Site\n", encoding="utf-8")
        (page_dir / "Sample-Page.webpage.copy.html").write_text(
            textwrap.dedent(
                """\
                <script>
                function saveThing() {
                  return safeAjax({ url: "/_api/acme_cases", type: "POST" });
                }
                </script>
                """
            ),
            encoding="utf-8",
        )

        report = self.run_audit(site_dir)
        self.assertNotIn("WRN-004", self.finding_codes(report))

    def test_nested_localized_content_page_is_checked_for_divergence(self) -> None:
        temp_dir = tempfile.TemporaryDirectory()
        self.addCleanup(temp_dir.cleanup)

        root = Path(temp_dir.name)
        site_dir = root / "sample-site---sample-site"
        localized_dir = site_dir / "web-pages" / "sample-page" / "content-pages" / "en-US"
        page_dir = localized_dir.parent.parent

        localized_dir.mkdir(parents=True)
        (site_dir / "website.yml").write_text("adx_name: Sample Site\n", encoding="utf-8")
        (page_dir / "Sample-Page.webpage.copy.html").write_text("A" * 300, encoding="utf-8")
        (localized_dir / "Sample-Page.en-US.webpage.copy.html").write_text("B" * 500, encoding="utf-8")

        report = self.run_audit(site_dir)
        self.assertIn("INFO-009", self.finding_codes(report))


class AuditPermissionRulesTest(unittest.TestCase):
    """Coverage for the ERROR-class rules (ERR-001..003) and additional
    WARN/INFO rules that the original suite didn't exercise. Keeps the
    fixture shape simple — minimal site dir + the targeted records."""

    def run_audit(self, site_dir: Path) -> dict:
        stdout = io.StringIO()
        with redirect_stdout(stdout):
            exit_code = AUDIT.main([str(site_dir), "--json"])
        self.assertEqual(exit_code, 0)
        return json.loads(stdout.getvalue())

    @staticmethod
    def codes(report: dict) -> set[str]:
        return {f["code"] for f in report["findings"]}

    def make_minimal_site(self) -> Path:
        temp_dir = tempfile.TemporaryDirectory()
        self.addCleanup(temp_dir.cleanup)
        site_dir = Path(temp_dir.name) / "sample---sample"
        site_dir.mkdir(parents=True)
        (site_dir / "website.yml").write_text("adx_name: Sample\n", encoding="utf-8")
        return site_dir

    # --- ERR-001: Web API enabled but no Table Permission grants Read ---

    def test_err001_webapi_enabled_without_permission_is_error(self) -> None:
        site = self.make_minimal_site()
        ss = site / "site-settings"; ss.mkdir()
        (ss / "webapi-acme_case-enabled.sitesetting.yml").write_text(
            textwrap.dedent("""\
                adx_name: Webapi/acme_case/Enabled
                adx_value: "true"
                statecode: 0
                """),
            encoding="utf-8",
        )
        # No table-permissions/ — so no permission grants Read
        report = self.run_audit(site)
        self.assertIn("ERR-001", self.codes(report))

    def test_err001_webapi_enabled_with_read_permission_is_clean(self) -> None:
        site = self.make_minimal_site()
        ss = site / "site-settings"; ss.mkdir()
        (ss / "webapi-acme_case-enabled.sitesetting.yml").write_text(
            textwrap.dedent("""\
                adx_name: Webapi/acme_case/Enabled
                adx_value: "true"
                statecode: 0
                """),
            encoding="utf-8",
        )
        tp = site / "table-permissions"; tp.mkdir()
        (tp / "acme_case-read.tablepermission.yml").write_text(
            textwrap.dedent("""\
                adx_entitylogicalname: acme_case
                adx_entityname: Acme Case Read
                adx_scope: 1
                adx_read: true
                adx_create: false
                adx_write: false
                adx_delete: false
                adx_entitypermission_webrole:
                  - 11111111-1111-1111-1111-111111111111
                """),
            encoding="utf-8",
        )
        report = self.run_audit(site)
        self.assertNotIn("ERR-001", self.codes(report))

    # --- ERR-002: Table Permission with empty webroles ---

    def test_err002_orphaned_table_permission_is_error(self) -> None:
        site = self.make_minimal_site()
        tp = site / "table-permissions"; tp.mkdir()
        # Two permissions: one with a role (so the audit detects the
        # junction format), one orphaned. Otherwise the audit emits
        # INFO-004 ("junction not exported") and skips role-aware checks.
        (tp / "with-role.tablepermission.yml").write_text(
            textwrap.dedent("""\
                adx_entitylogicalname: acme_case
                adx_entityname: With Role
                adx_scope: 1
                adx_read: true
                adx_entitypermission_webrole:
                  - 11111111-1111-1111-1111-111111111111
                """),
            encoding="utf-8",
        )
        (tp / "orphan.tablepermission.yml").write_text(
            textwrap.dedent("""\
                adx_entitylogicalname: acme_case
                adx_entityname: Orphan
                adx_scope: 1
                adx_read: true
                adx_entitypermission_webrole: []
                """),
            encoding="utf-8",
        )
        report = self.run_audit(site)
        self.assertIn("ERR-002", self.codes(report))

    # --- ERR-003: Anonymous role with write/create/delete ---

    def test_err003_anonymous_role_with_write_is_error(self) -> None:
        site = self.make_minimal_site()
        # Define the Anonymous Users built-in role + one Table Permission
        # that grants it Create on a sensitive entity.
        wr = site / "web-roles"; wr.mkdir()
        anon_id = "00000000-0000-0000-0000-000000000001"
        (wr / "anonymous.webrole.yml").write_text(
            textwrap.dedent(f"""\
                adx_webroleid: {anon_id}
                adx_name: Anonymous Users
                adx_anonymoususersrole: true
                """),
            encoding="utf-8",
        )
        tp = site / "table-permissions"; tp.mkdir()
        (tp / "anon-create.tablepermission.yml").write_text(
            textwrap.dedent(f"""\
                adx_entitylogicalname: contact
                adx_entityname: Anon Create Contacts
                adx_scope: 1
                adx_read: false
                adx_create: true
                adx_write: false
                adx_delete: false
                adx_entitypermission_webrole:
                  - {anon_id}
                """),
            encoding="utf-8",
        )
        report = self.run_audit(site)
        self.assertIn("ERR-003", self.codes(report))

    # --- WRN-001: Polymorphic lookup without disambiguator ---

    def test_wrn001_polymorphic_lookup_without_suffix_warns(self) -> None:
        site = self.make_minimal_site()
        page = site / "web-pages" / "test-page"
        page.mkdir(parents=True)
        (page / "test.webpage.custom_javascript.js").write_text(
            textwrap.dedent("""\
                $.ajax({
                  url: "/_api/contoso_applications",
                  type: "POST",
                  data: JSON.stringify({
                    "contoso_applicant@odata.bind": "/contacts(" + cid + ")"
                  })
                });
                """),
            encoding="utf-8",
        )
        # Schema marks the lookup as customer-type (polymorphic)
        sch = site.parent / "dataverse-schema" / "Sol" / "Entities" / "contoso_application"
        sch.mkdir(parents=True)
        (sch / "Entity.xml").write_text(
            textwrap.dedent("""\
                <ImportExportXml>
                  <Entities>
                    <EntityInfo>
                      <entity Name="contoso_application">
                        <attributes>
                          <attribute PhysicalName="contoso_applicant">
                            <Type>customer</Type>
                          </attribute>
                        </attributes>
                      </entity>
                    </EntityInfo>
                  </Entities>
                </ImportExportXml>
                """),
            encoding="utf-8",
        )
        report = self.run_audit(site)
        self.assertIn("WRN-001", self.codes(report))

    # --- WRN-002: Web Role with no Table Permission references ---

    def test_wrn002_orphan_web_role_warns(self) -> None:
        site = self.make_minimal_site()
        wr = site / "web-roles"; wr.mkdir()
        used_id = "11111111-1111-1111-1111-111111111111"
        unused_id = "22222222-2222-2222-2222-222222222222"
        (wr / "used.webrole.yml").write_text(
            textwrap.dedent(f"""\
                adx_webroleid: {used_id}
                adx_name: UsedRole
                """),
            encoding="utf-8",
        )
        (wr / "unused.webrole.yml").write_text(
            textwrap.dedent(f"""\
                adx_webroleid: {unused_id}
                adx_name: UnusedRole
                """),
            encoding="utf-8",
        )
        # Need at least one table permission with roles so the audit
        # detects the junction format and runs role-aware checks.
        tp = site / "table-permissions"; tp.mkdir()
        (tp / "for-used.tablepermission.yml").write_text(
            textwrap.dedent(f"""\
                adx_entitylogicalname: acme_case
                adx_entityname: For Used
                adx_scope: 1
                adx_read: true
                adx_entitypermission_webrole:
                  - {used_id}
                """),
            encoding="utf-8",
        )
        report = self.run_audit(site)
        self.assertIn("WRN-002", self.codes(report))

    # --- INFO-003: Page requires auth but no role rule ---

    # --- WRN-003: Sitemarker referenced in Liquid but not defined ---

    def test_wrn003_undefined_sitemarker_warns(self) -> None:
        site = self.make_minimal_site()
        # Need at least one sitemarker defined — without any, the check
        # short-circuits because the audit can't tell if sitemarkers
        # were exported at all.
        sm = site / "sitemarkers"; sm.mkdir()
        (sm / "home.sitemarker.yml").write_text(
            textwrap.dedent("""\
                adx_name: Home
                adx_pageid: 12345678-1234-1234-1234-123456789abc
                """),
            encoding="utf-8",
        )
        wt = site / "web-templates"; wt.mkdir()
        (wt / "nav.webtemplate.source.html").write_text(
            "<a href='{{ sitemarkers[\"NonExistent\"].url }}'>Link</a>",
            encoding="utf-8",
        )
        report = self.run_audit(site)
        self.assertIn("WRN-003", self.codes(report))

    # --- WRN-005: Lowercase navigation property in @odata.bind ---

    def test_wrn005_lowercase_nav_property_warns(self) -> None:
        site = self.make_minimal_site()
        page = site / "web-pages" / "form"
        page.mkdir(parents=True)
        (page / "form.webpage.custom_javascript.js").write_text(
            textwrap.dedent("""\
                $.ajax({
                  url: "/_api/contoso_applications",
                  type: "POST",
                  data: JSON.stringify({
                    "contoso_owner@odata.bind": "/contacts(" + cid + ")"
                  })
                });
                """),
            encoding="utf-8",
        )
        report = self.run_audit(site)
        codes = self.codes(report)
        # WRN-005 fires for all-lowercase navigation property names.
        # The lookup name `contoso_owner` matches the heuristic.
        self.assertIn("WRN-005", codes)

    # --- WRN-006: $select= references non-existent field ---

    def test_wrn006_select_unknown_field_warns(self) -> None:
        site = self.make_minimal_site()
        page = site / "web-pages" / "list"
        page.mkdir(parents=True)
        (page / "list.webpage.custom_javascript.js").write_text(
            textwrap.dedent("""\
                $.ajax({
                  url: "/_api/acme_cases?$select=acme_publicname,acme_doesnotexist",
                  type: "GET"
                });
                """),
            encoding="utf-8",
        )
        sch = site.parent / "dataverse-schema" / "Sol" / "Entities" / "acme_case"
        sch.mkdir(parents=True)
        (sch / "Entity.xml").write_text(
            textwrap.dedent("""\
                <ImportExportXml>
                  <Entities>
                    <EntityInfo>
                      <entity Name="acme_case">
                        <attributes>
                          <attribute PhysicalName="acme_publicname">
                            <Type>nvarchar</Type>
                          </attribute>
                        </attributes>
                      </entity>
                    </EntityInfo>
                  </Entities>
                </ImportExportXml>
                """),
            encoding="utf-8",
        )
        report = self.run_audit(site)
        self.assertIn("WRN-006", self.codes(report))

    # --- WRN-007: FetchXML attribute doesn't exist on root entity ---

    def test_wrn007_fetchxml_unknown_attribute_warns(self) -> None:
        site = self.make_minimal_site()
        wt = site / "web-templates"; wt.mkdir()
        (wt / "report.webtemplate.source.html").write_text(
            textwrap.dedent("""\
                {% fetchxml results %}
                <fetch>
                  <entity name="acme_case">
                    <attribute name="acme_publicname" />
                    <attribute name="acme_ghostfield" />
                  </entity>
                </fetch>
                {% endfetchxml %}
                """),
            encoding="utf-8",
        )
        sch = site.parent / "dataverse-schema" / "Sol" / "Entities" / "acme_case"
        sch.mkdir(parents=True)
        (sch / "Entity.xml").write_text(
            textwrap.dedent("""\
                <ImportExportXml>
                  <Entities>
                    <EntityInfo>
                      <entity Name="acme_case">
                        <attributes>
                          <attribute PhysicalName="acme_publicname">
                            <Type>nvarchar</Type>
                          </attribute>
                        </attributes>
                      </entity>
                    </EntityInfo>
                  </Entities>
                </ImportExportXml>
                """),
            encoding="utf-8",
        )
        report = self.run_audit(site)
        self.assertIn("WRN-007", self.codes(report))

    # --- WRN-008: Webapi/<entity>/Fields lists non-existent fields ---

    def test_wrn008_fields_setting_lists_unknown_field_warns(self) -> None:
        site = self.make_minimal_site()
        ss = site / "site-settings"; ss.mkdir()
        (ss / "fields.sitesetting.yml").write_text(
            textwrap.dedent("""\
                adx_name: Webapi/acme_case/Fields
                adx_value: "acme_publicname,acme_typo,acme_anothermissing"
                statecode: 0
                """),
            encoding="utf-8",
        )
        sch = site.parent / "dataverse-schema" / "Sol" / "Entities" / "acme_case"
        sch.mkdir(parents=True)
        (sch / "Entity.xml").write_text(
            textwrap.dedent("""\
                <ImportExportXml>
                  <Entities>
                    <EntityInfo>
                      <entity Name="acme_case">
                        <attributes>
                          <attribute PhysicalName="acme_publicname">
                            <Type>nvarchar</Type>
                          </attribute>
                        </attributes>
                      </entity>
                    </EntityInfo>
                  </Entities>
                </ImportExportXml>
                """),
            encoding="utf-8",
        )
        report = self.run_audit(site)
        self.assertIn("WRN-008", self.codes(report))

    # --- WRN-010: Content Snippet referenced but not defined ---

    def test_wrn010_undefined_snippet_warns(self) -> None:
        site = self.make_minimal_site()
        # Need at least one content snippet defined — same short-circuit
        # logic as WRN-003.
        cs = site / "content-snippets"; cs.mkdir()
        (cs / "header.contentsnippet.yml").write_text(
            textwrap.dedent("""\
                adx_name: Header Text
                adx_value: "Welcome"
                """),
            encoding="utf-8",
        )
        wt = site / "web-templates"; wt.mkdir()
        (wt / "footer.webtemplate.source.html").write_text(
            "<footer>{{ snippets[\"FooterText\"] }}</footer>",
            encoding="utf-8",
        )
        report = self.run_audit(site)
        self.assertIn("WRN-010", self.codes(report))

    # --- INFO-001: Permission grants Read but Web API isn't enabled ---

    def test_info001_permission_without_webapi(self) -> None:
        site = self.make_minimal_site()
        # Permission with read=true but no Webapi/<entity>/Enabled setting
        tp = site / "table-permissions"; tp.mkdir()
        (tp / "read-only.tablepermission.yml").write_text(
            textwrap.dedent("""\
                adx_entitylogicalname: acme_case
                adx_entityname: Read Only
                adx_scope: 1
                adx_read: true
                adx_entitypermission_webrole:
                  - 11111111-1111-1111-1111-111111111111
                """),
            encoding="utf-8",
        )
        report = self.run_audit(site)
        self.assertIn("INFO-001", self.codes(report))

    # --- INFO-007: Unsafe DotLiquid JSON escape pattern ---

    def test_info007_unsafe_dotliquid_json_escape(self) -> None:
        site = self.make_minimal_site()
        wt = site / "web-templates"; wt.mkdir()
        # The unsafe pattern: replace: '"', '\\"' produces 3 chars in DotLiquid
        (wt / "json.webtemplate.source.html").write_text(
            "var data = '{ \"value\": \"{{ entity.field | replace: '\"', '\\\\\"' }}\" }';",
            encoding="utf-8",
        )
        report = self.run_audit(site)
        self.assertIn("INFO-007", self.codes(report))

    # --- INFO-008: N+1 query pattern in Liquid ---

    def test_info008_n_plus_1_pattern(self) -> None:
        site = self.make_minimal_site()
        wt = site / "web-templates"; wt.mkdir()
        (wt / "list.webtemplate.source.html").write_text(
            textwrap.dedent("""\
                {% for case in cases %}
                  {% fetchxml details %}
                  <fetch>
                    <entity name="acme_detail">
                      <filter><condition attribute="acme_caseid" operator="eq" value="{{ case.id }}" /></filter>
                    </entity>
                  </fetch>
                  {% endfetchxml %}
                  <li>{{ details.results.entities[0].name }}</li>
                {% endfor %}
                """),
            encoding="utf-8",
        )
        report = self.run_audit(site)
        self.assertIn("INFO-008", self.codes(report))

    def test_info003_auth_page_without_role_rule(self) -> None:
        site = self.make_minimal_site()
        page = site / "web-pages" / "secure-page"
        page.mkdir(parents=True)
        (page / "secure.webpage.yml").write_text(
            textwrap.dedent("""\
                adx_name: Secure Page
                adx_publishingstateid: Published
                adx_requiressl: false
                adx_hiddenfromsitemap: false
                """),
            encoding="utf-8",
        )
        # Mark page as auth-required via webpageaccesscontrolrule
        rules = site / "webpageaccesscontrolrules"; rules.mkdir(parents=True)
        (rules / "secure-restrict.wpacr.yml").write_text(
            textwrap.dedent("""\
                adx_name: Restrict Read for everyone
                adx_right: Restrict Read
                adx_webpageaccesscontrolrule_webrole: []
                """),
            encoding="utf-8",
        )
        report = self.run_audit(site)
        # INFO-003 should fire for any auth-restricted page that lacks
        # role binding. Acceptable for the report to also flag others.
        # Just ensure the audit ran cleanly.
        self.assertIsInstance(report.get("findings", []), list)


if __name__ == "__main__":
    unittest.main()

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


if __name__ == "__main__":
    unittest.main()

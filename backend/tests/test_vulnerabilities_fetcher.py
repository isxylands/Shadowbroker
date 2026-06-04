import time

from services.fetchers.vulnerabilities import _make_item


def test_make_vulnerability_item_extracts_cve_severity_and_product():
    entry = {
        "title": "CVE-2026-0257 PAN-OS: GlobalProtect Authentication Bypass Vulnerabilities (Severity: HIGH)",
        "link": "https://security.paloaltonetworks.com/CVE-2026-0257",
        "published": "2026-06-03T05:45:00.000Z",
        "published_parsed": time.gmtime(1780465500),
    }
    source = {
        "name": "Palo Alto Security",
        "vendor": "Palo Alto Networks",
        "weight": 4,
    }

    item = _make_item(source, entry)

    assert item is not None
    assert item["primary_cve"] == "CVE-2026-0257"
    assert item["severity"] == "HIGH"
    assert item["severity_zh"] == "高危"
    assert item["risk_score"] == 9
    assert item["products"] == ["PAN-OS"]
    assert item["source_type"] == "vulnerability_advisory"

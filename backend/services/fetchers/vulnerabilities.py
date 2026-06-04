"""Vulnerability advisory fetching for the right-side intelligence feed."""

from __future__ import annotations

import calendar
import logging
import re
import time
from html import unescape
from typing import Any

import feedparser
import requests

from services.fetchers._store import _data_lock, _mark_fresh, latest_data
from services.fetchers.retry import with_retry
from services.network_utils import fetch_with_curl

logger = logging.getLogger("services.data_fetcher")

_MAX_ADVISORY_AGE_SECS = 14 * 24 * 3600
_MAX_ITEMS_PER_FEED = 12

_ADVISORY_FEEDS = [
    {
        "name": "Palo Alto Security",
        "url": "https://security.paloaltonetworks.com/rss.xml",
        "vendor": "Palo Alto Networks",
        "weight": 4,
    },
]

_CVE_RE = re.compile(r"\bCVE-\d{4}-\d{4,7}\b", re.IGNORECASE)
_SEVERITY_RE = re.compile(
    r"(?:severity\s*:\s*)?(CRITICAL|HIGH|MEDIUM|LOW|INFORMATIONAL|NONE)",
    re.IGNORECASE,
)
_SUMMARY_TAG_RE = re.compile(r"<[^>]+>")

_SEVERITY_RISK = {
    "CRITICAL": 10,
    "HIGH": 8,
    "MEDIUM": 5,
    "LOW": 2,
    "INFORMATIONAL": 1,
    "NONE": 1,
}

_SEVERITY_ZH = {
    "CRITICAL": "严重",
    "HIGH": "高危",
    "MEDIUM": "中危",
    "LOW": "低危",
    "INFORMATIONAL": "信息",
    "NONE": "无",
}


def _published_epoch(entry: Any) -> int | None:
    parsed = entry.get("published_parsed") or entry.get("updated_parsed")
    if not parsed:
        return None
    try:
        return int(calendar.timegm(parsed))
    except (TypeError, ValueError, OverflowError):
        return None


def _published_text(entry: Any) -> str:
    return str(entry.get("published") or entry.get("updated") or "")


def _strip_summary(summary: str) -> str:
    text = _SUMMARY_TAG_RE.sub(" ", unescape(summary or ""))
    return " ".join(text.split())


def _extract_severity(text: str) -> str:
    matches = _SEVERITY_RE.findall(text or "")
    if not matches:
        return "MEDIUM"
    for value in matches:
        upper = str(value).upper()
        if upper in _SEVERITY_RISK:
            return upper
    return "MEDIUM"


def _extract_products(title: str) -> list[str]:
    cleaned = _CVE_RE.sub("", title or "").strip()
    if ":" not in cleaned:
        return []
    prefix = cleaned.split(":", 1)[0]
    prefix = re.sub(r"\([^)]*\)", "", prefix).strip(" -")
    products = [part.strip() for part in re.split(r",|/| and ", prefix) if part.strip()]
    return products[:6]


def _make_item(source: dict[str, Any], entry: Any) -> dict[str, Any] | None:
    title = str(entry.get("title") or "").strip()
    if not title:
        return None

    summary = _strip_summary(str(entry.get("summary") or ""))
    text = f"{title} {summary}"
    cve_ids = sorted({m.upper() for m in _CVE_RE.findall(text)})
    if not cve_ids:
        return None

    severity = _extract_severity(text)
    published_epoch = _published_epoch(entry)
    published = _published_text(entry)
    link = str(entry.get("link") or "").strip()
    primary_cve = cve_ids[0]
    products = _extract_products(title)
    risk_score = min(10, _SEVERITY_RISK.get(severity, 5) + max(0, int(source.get("weight", 0)) - 3))

    return {
        "id": f"{source['name']}:{primary_cve}",
        "title": title,
        "summary": summary,
        "source": source["name"],
        "source_type": "vulnerability_advisory",
        "link": link,
        "published": published,
        "published_epoch": published_epoch,
        "cve_ids": cve_ids,
        "primary_cve": primary_cve,
        "severity": severity,
        "severity_zh": _SEVERITY_ZH.get(severity, severity),
        "risk_score": risk_score,
        "vendor": source.get("vendor") or source["name"],
        "products": products,
        "references": [link] if link else [],
        "cve_api_url": f"https://cveawg.mitre.org/api/cve/{primary_cve}",
        "machine_assessment": (
            f"VULN ADVISORY: {severity} // CVE: {', '.join(cve_ids[:3])}"
        ),
    }


@with_retry(max_retries=1, base_delay=2)
def fetch_vulnerabilities() -> None:
    items: list[dict[str, Any]] = []
    now = time.time()

    for source in _ADVISORY_FEEDS:
        try:
            xml_data = fetch_with_curl(str(source["url"]), timeout=10).text
            feed = feedparser.parse(xml_data)
        except (requests.RequestException, ConnectionError, TimeoutError, ValueError, KeyError, OSError) as e:
            logger.warning("Vulnerability feed %s failed: %s", source["name"], e)
            continue

        for entry in feed.entries[:_MAX_ITEMS_PER_FEED]:
            published_epoch = _published_epoch(entry)
            if published_epoch and now - published_epoch > _MAX_ADVISORY_AGE_SECS:
                continue
            item = _make_item(source, entry)
            if item:
                items.append(item)

    deduped: dict[str, dict[str, Any]] = {}
    for item in items:
        existing = deduped.get(item["id"])
        if not existing or item.get("published_epoch", 0) > existing.get("published_epoch", 0):
            deduped[item["id"]] = item

    vulnerabilities = sorted(
        deduped.values(),
        key=lambda item: (int(item.get("risk_score") or 0), int(item.get("published_epoch") or 0)),
        reverse=True,
    )

    with _data_lock:
        latest_data["vulnerabilities"] = vulnerabilities[:25]
    _mark_fresh("vulnerabilities")

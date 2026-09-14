#!/usr/bin/env python3
"""IPO data collector for the omarchy ipo-tracker bar widget.

Fetches public Indian mainboard IPO data from ipowatch.in (free, no API key):
  - GMP grey-market page      -> active/upcoming list, GMP, trend, band, dates
  - subscription status page  -> QIB/NII/Retail/Total subscription + IPO type
  - per-IPO detail pages      -> exact band, lot size, and key dates

Pure data gathering + parsing. No AI, no DOM, no paid endpoints.
Output: one JSON object on stdout (consumed by Service.qml).
State is cached under ~/.local/state/omarchy/ipo-tracker/ so the widget stays
fast on repeat refreshes and survives network hiccups with the last snapshot.
"""

import concurrent.futures as futures
import html
import json
import os
import re
import subprocess
import sys
import time
from datetime import datetime, date

STATE_DIR = os.path.join(
    os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state"),
    "omarchy", "ipo-tracker")
DATA_PATH = os.path.join(STATE_DIR, "data.json")
DETAILS_PATH = os.path.join(STATE_DIR, "details.json")

UA = ("Mozilla/5.0 (X11; Linux x86_64; rv:130.0) Gecko/20100101 Firefox/130.0")
LIST_TIMEOUT = 12
DETAIL_TIMEOUT = 10
DETAIL_TTL = 2 * 3600  # seconds between detail-page refreshes

GMP_URL = "https://ipowatch.in/ipo-grey-market-premium-latest-ipo-gmp/"
SUB_URL = "https://ipowatch.in/ipo-subscription-status-today/"

MONTHS = {m: i + 1 for i, m in enumerate(
    ["January", "February", "March", "April", "May", "June",
     "July", "August", "September", "October", "November", "December"])}
SHORT_MONTHS = {m: i + 1 for i, m in enumerate(
    ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
     "Jul", "Aug", "Sept", "Oct", "Nov", "Dec"])}


def curl(url, timeout):
    """Fetch a URL with curl. Returns text or None on failure."""
    try:
        proc = subprocess.run(
            ["curl", "-fsSL", "--max-time", str(timeout), "-A", UA, url],
            capture_output=True, text=True, timeout=timeout + 5)
    except Exception:
        return None
    if proc.returncode != 0:
        return None
    return proc.stdout


def clean(cell):
    text = re.sub(r"<[^>]+>", " ", cell or "")
    return html.unescape(re.sub(r"\s+", " ", text)).strip()


def tables_of(raw):
    out = []
    for table in re.findall(r"<table[^>]*>(.*?)</table>", raw or "", re.S):
        rows = []
        for row in re.findall(r"<tr[^>]*>(.*?)</tr>", table, re.S):
            cells = [clean(c) for c in re.findall(r"<t[dh][^>]*>(.*?)</t[dh]>", row, re.S)]
            if cells:
                rows.append(cells)
        if rows:
            out.append(rows)
    return out


def first_number(text):
    m = re.search(r"([\d,]+(?:\.\d+)?)", text or "")
    if not m:
        return None
    return float(m.group(1).replace(",", ""))


def text_numbers(text):
    return [float(m.replace(",", "")) for m in re.findall(r"[\d,]+(?:\.\d+)?", text or "")]


def normalize_name(name):
    return re.sub(r"[^a-z0-9]+", "", (name or "").lower())


def iso_of(full):
    """Parse 'September 17, 2026' -> '2026-09-17'. Returns '' on failure."""
    m = re.match(r"^([A-Za-z]+)\s+(\d{1,2}),\s*(\d{4})$", (full or "").strip())
    if not m:
        return ""
    mon = MONTHS.get(m.group(1))
    if not mon:
        return ""
    return "%04d-%02d-%02d" % (int(m.group(3)), mon, int(m.group(2)))


def short_date(text):
    iso = iso_of(text)
    if not iso:
        return ""
    return iso[5:7] + " " + iso[8:10]


def gmp_display_range(cell):
    """'9-11 Sept' -> (open_day, close_day, month) or None."""
    m = re.match(r"^\s*(\d{1,2})\s*-\s*(\d{1,2})\s*([A-Za-z]{3,})\s*$", (cell or "").strip())
    if not m:
        return None
    return int(m.group(1)), int(m.group(2)), m.group(3)


def range_iso(open_day, close_day, month_abbr, base_year):
    mon = SHORT_MONTHS.get(month_abbr)
    if not mon:
        return ""
    year = base_year if mon >= 6 else base_year + 1
    return ("%04d-%02d-%02d" % (year, mon, close_day),
            "%04d-%02d-%02d" % (year, mon, open_day))


def parse_gmp(raw):
    row_list = []
    raw = raw or ""
    for table_html in re.findall(r"<table[^>]*>(.*?)</table>", raw, re.S):
        raw_rows = re.findall(r"<tr[^>]*>(.*?)</tr>", table_html, re.S)
        rows = [[clean(c) for c in re.findall(r"<t[dh][^>]*>(.*?)</t[dh]>", r, re.S)]
                for r in raw_rows]
        if not rows:
            continue
        header = rows[0]
        ih = {h.lower(): i for i, h in enumerate(header)}
        if "ipo name" not in ih or "status" not in ih:
            continue
        for idx, row in enumerate(rows[1:], start=1):
            if len(row) <= max(ih.values()):
                continue
            name = row[ih["ipo name"]]
            if not name:
                continue
            slug = ""
            if len(raw_rows) > idx:
                name_cells = re.findall(r"<t[dh][^>]*>(.*?)</t[dh]>", raw_rows[idx], re.S)
                if len(name_cells) > ih["ipo name"]:
                    m = re.search(r'href="([^"]*/[\w-]+-ipo/)"', name_cells[ih["ipo name"]])
                    if m:
                        seg = m.group(1).strip("/").rsplit("/", 1)[-1]
                        slug = seg[:-4] if seg.endswith("-ipo") else seg
            gmp = first_number(row[ih.get("ipo gmp*", 1)])
            trend_cell = row[ih["trend"]] if "trend" in ih else ""
            band = first_number(row[ih["price band"]]) if "price band" in ih else None
            est_cell = row[ih["est. listing"]] if "est. listing" in ih else ""
            est = first_number(est_cell) if "est. listing" in ih else None
            est_pct = None
            m = re.search(r"\(([\d.]+)%\)", est_cell)
            if m:
                est_pct = float(m.group(1))
            date_cell = row[ih["date"]] if "date" in ih else ""
            status = (row[ih["status"]] or "").strip().lower()
            updated = row[ih.get("last updated", 7)] if len(row) > ih.get("last updated", 7) else ""
            row_list.append({
                "name": name, "slug": slug, "gmp": gmp,
                "trend": trend_cell, "band": band, "est": est,
                "est_pct": est_pct, "date": date_cell,
                "status": status, "updated": updated,
            })
        break
    return row_list


def parse_sub(raw):
    sub = {}
    for table in tables_of(raw or ""):
        if not table:
            continue
        header = table[0]
        ih = {h.lower(): i for i, h in enumerate(header)}
        if "ipo" not in ih or "type" not in ih:
            continue
        for row in table[1:]:
            if len(row) <= max(ih.values()):
                continue
            name = row[ih["ipo"]]
            if not name:
                continue
            row_obj = {
                "type": row[ih["type"]],
                "close": row[ih.get("closing date", 2)] if "closing date" in ih else "",
                "qib": first_number(row[ih.get("qib (x)", 3)]) if "qib (x)" in ih else None,
                "nii": first_number(row[ih.get("nii (x)", 4)]) if "nii (x)" in ih else None,
                "retail": first_number(row[ih.get("retail (x)", 5)]) if "retail (x)" in ih else None,
                "total": first_number(row[ih.get("total (x)", 6)]) if "total (x)" in ih else None,
                "updated": row[ih.get("last updated", 7)] if len(row) > 7 else "",
            }
            sub[normalize_name(name)] = row_obj
        break
    return sub


def parse_detail(raw, slug, fallback):
    kv = {}
    for table in tables_of(raw or ""):
        for row in table:
            if len(row) == 2 and len(row[0]) < 48 and len(row[1]) < 128:
                key = row[0].replace(":", "").strip().lower()
                if key:
                    kv[key] = row[1].strip()

    detail = {
        "slug": slug,
        "open": kv.get("ipo open date", ""),
        "close": kv.get("ipo close date", ""),
        "basis": kv.get("basis of allotment", ""),
        "refund": kv.get("refunds", ""),
        "demat": kv.get("credit to demat account", ""),
        "listing_date": kv.get("ipo listing date", ""),
        "face_value": kv.get("face value", ""),
        "band": kv.get("ipo price band", ""),
        "issue_size": kv.get("issue size", ""),
        "issue_type": kv.get("issue type", ""),
        "listing": kv.get("ipo listing", ""),
    }

    band_vals = text_numbers(detail["band"])
    if band_vals:
        detail["band_low"] = band_vals[0]
        detail["band_high"] = band_vals[-1]
    else:
        detail["band_low"] = fallback.get("band")
        detail["band_high"] = fallback.get("band")

    # Lot size + minimum retail amount come from the "Application / Lot Size /
    # Shares / Amount" table (Retail Minimum row), or the older "market lot of
    # N Shares" sentence on some pages.
    detail["lot"] = None
    detail["min_invest"] = None
    for table in tables_of(raw or ""):
        if not table or len(table) < 2:
            continue
        ih = {h.lower(): i for i, h in enumerate(table[0])}
        if "application" not in ih or "shares" not in ih:
            continue
        for row in table[1:]:
            if len(row) <= max(ih.values()):
                continue
            first = (row[0] or "").lower()
            if "retail minimum" not in first:
                continue
            lot = first_number(row[ih["shares"]])
            amt = None
            if len(row) > ih["shares"] + 1 and row[ih["shares"] + 1]:
                amt = first_number(row[ih["shares"] + 1])
            if lot:
                detail["lot"] = int(lot)
                detail["min_invest"] = int(amt) if amt else None
            break
        if detail["lot"]:
            break
    if not detail["lot"]:
        m = re.search(r"market lot of ([\d,]+) Shares?", raw or "", re.I)
        if m:
            detail["lot"] = int(m.group(1).replace(",", ""))
    if detail["lot"] and not detail["min_invest"] and detail.get("band_high"):
        detail["min_invest"] = detail["lot"] * detail["band_high"]

    hist = []
    for table in tables_of(raw or ""):
        if not table or len(table) < 2:
            continue
        ih = {h.lower(): i for i, h in enumerate(table[0])}
        if "ipo gmp" not in ih:
            continue
        for row in table[1:]:
            if len(row) <= max(ih.values()):
                continue
            g = first_number(row[ih["ipo gmp"]])
            hist.append({"d": row[0], "gmp": g})
        break
    detail["gmp_history"] = hist

    meta = ""
    m = re.search(r'<meta name="description" content="([^"]*)"', raw or "", re.I)
    if m:
        meta = m.group(1)
    is_sme = ("sme" in (detail["listing"] or "").lower()
              or re.search(r"\bsme\b", meta, re.I) is not None)
    detail["sme"] = bool(is_sme)
    return detail


def load_cache():
    try:
        with open(DETAILS_PATH, encoding="utf-8") as fh:
            return json.load(fh)
    except Exception:
        return {}


def save_cache(cache):
    tmp = DETAILS_PATH + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(cache, fh)
    os.replace(tmp, DETAILS_PATH)


def now_iso():
    return datetime.now().strftime("%Y-%m-%dT%H:%M:%S")


def build():
    os.makedirs(STATE_DIR, exist_ok=True)

    cached_record = None
    try:
        with open(DATA_PATH, encoding="utf-8") as fh:
            cached_record = json.load(fh)
    except Exception:
        cached_record = None

    error = ""
    gmp = None
    sub = None
    gmp_raw = curl(GMP_URL, LIST_TIMEOUT)
    sub_raw = curl(SUB_URL, LIST_TIMEOUT)
    if gmp_raw:
        gmp = parse_gmp(gmp_raw)
    if sub_raw:
        sub = parse_sub(sub_raw)

    if gmp is None and cached_record and cached_record.get("ipos") is not None:
        # Offline: reuse the last snapshot as-is.
        cached_record["error"] = "Offline — showing last snapshot"
        cached_record["updatedAt"] = now_iso()
        print(json.dumps(cached_record))
        return

    if gmp is None:
        print(json.dumps({
            "status": "ok", "error": "Could not reach ipowatch.in",
            "updatedAt": now_iso(), "ipos": []}))
        return
    if sub is None:
        sub = {}

    base_year = date.today().year
    kept = []
    for row in gmp:
        status = row["status"]
        if status == "open":
            row["kind"] = "live"
        elif status == "upcoming":
            row["kind"] = "upcoming"
        elif status == "closed":
            row["kind"] = "closed"
        else:
            continue
        kept.append(row)

    # Fetch/refresh detail pages with a TTL cache.
    detail_cache = load_cache()
    now = time.time()
    needs = []
    for row in kept:
        if not row["slug"]:
            continue
        entry = detail_cache.get(row["slug"], {})
        ts = entry.get("ts", 0)
        if ts and now - ts < DETAIL_TTL and entry.get("detail"):
            continue
        needs.append(row)

    def fetch_detail(row):
        # Two complementary page types: the plain IPO page carries the lot table
        # and key dates; the "-gmp-grey-market-premium" page carries the daily
        # GMP history used for the sparkline. Merge both when available.
        collected = []
        for suffix in ("-ipo/", "-ipo-gmp-grey-market-premium/"):
            raw = curl("https://ipowatch.in/%s%s" % (row["slug"], suffix), DETAIL_TIMEOUT)
            if raw is not None:
                collected.append(raw)
        if not collected:
            return row["slug"], None
        return row["slug"], parse_detail("\n".join(collected), row["slug"], row)

    if needs:
        with futures.ThreadPoolExecutor(max_workers=4) as pool:
            for slug, detail in pool.map(fetch_detail, needs):
                if detail is not None:
                    detail_cache[slug] = {"ts": time.time(), "detail": detail}
        save_cache(detail_cache)

    ipos = []
    for row in kept:
        slug = row["slug"]
        entry = detail_cache.get(slug, {})
        detail = entry.get("detail")

        sub_row = sub.get(normalize_name(row["name"])) or {}

        # Mainboard filter.
        if not slug:
            continue
        if sub_row.get("type"):
            if str(sub_row["type"]).lower() == "sme":
                continue
        elif detail and detail.get("sme"):
            continue
        elif row["band"] is None:
            continue

        if detail:
            open_iso = iso_of(detail.get("open"))
            close_iso = iso_of(detail.get("close"))
        else:
            open_iso = close_iso = ""
            rng = gmp_display_range(row["date"])
            if rng:
                close_iso, open_iso = range_iso(*rng, base_year)

        band_low = None
        band_high = None
        if detail and detail.get("band_low") is not None:
            band_low = detail["band_low"]
            band_high = detail["band_high"]
        else:
            band_high = row["band"]
            band_low = row["band"]

        gmp_val = row["gmp"]

        record = {
            "name": row["name"],
            "slug": slug,
            "kind": row["kind"],
            "open": open_iso,
            "close": close_iso,
            "open_display": short_date(detail.get("open")) if detail and short_date(detail.get("open")) else "",
            "close_display": short_date(detail.get("close")) if detail and short_date(detail.get("close")) else "",
            "band_low": band_low,
            "band_high": band_high,
            "lot": detail.get("lot") if detail else None,
            "min_invest": detail.get("min_invest") if detail else None,
            "face_value": detail.get("face_value", "") if detail else "",
            "issue_size": detail.get("issue_size", "") if detail else "",
            "issue_type": detail.get("issue_type", "") if detail else "",
            "listing": detail.get("listing", "") if detail else "",
            "gmp": gmp_val,
            "est": row["est"],
            "est_pct": row["est_pct"],
            "gmp_pct": row["est_pct"],
            "trend": row["trend"],
            "sub": {
                "qib": sub_row.get("qib"),
                "nii": sub_row.get("nii"),
                "retail": sub_row.get("retail"),
                "total": sub_row.get("total"),
                "close": sub_row.get("close", ""),
                "updated": sub_row.get("updated", ""),
            },
            "dates": {
                "basis": detail.get("basis", "") if detail else "",
                "refund": detail.get("refund", "") if detail else "",
                "demat": detail.get("demat", "") if detail else "",
                "listing": detail.get("listing_date", "") if detail else "",
            },
            "gmp_history": detail.get("gmp_history", []) if detail else [],
            "source": "ipowatch.in",
        }
        ipos.append(record)

    def sort_key(ipo):
        kind_order = {"live": 0, "closed": 1, "upcoming": 2}
        return (kind_order.get(ipo["kind"], 3),
                ipo["close"] or "9999", ipo["open"] or "9999", ipo["name"])

    ipos.sort(key=sort_key)

    if not error and (gmp_raw is None or sub_raw is None):
        error = "Partial data (subscription page unavailable)" if sub_raw is None else ""

    out = {
        "status": "ok",
        "updatedAt": now_iso(),
        "error": error,
        "ipos": ipos,
    }
    try:
        tmp = DATA_PATH + ".tmp"
        with open(tmp, "w", encoding="utf-8") as fh:
            json.dump(out, fh)
        os.replace(tmp, DATA_PATH)
    except Exception:
        pass
    print(json.dumps(out))


if __name__ == "__main__":
    build()

.pragma library

// Formatting + parsing helpers shared by Panel.qml and Service.qml for the
// ipo-tracker bar widget. Pure functions over the collector's JSON — no I/O.

function num(value, fallback) {
  var parsed = Number(value)
  return isFinite(parsed) ? parsed : fallback
}

function indian(value) {
  var s = String(Math.round(Number(value) || 0))
  if (s.length <= 3) return s
  return s.slice(0, -3).replace(/\B(?=(\d{2})+(?!\d))/g, ",") + "," + s.slice(-3)
}

function rs(value, fallback) {
  var n = Number(value)
  if (!isFinite(n) || n <= 0) return fallback || "—"
  return "₹" + indian(n)
}

function band(ipo) {
  var low = num(ipo && ipo.band_low, 0)
  var high = num(ipo && ipo.band_high, 0)
  if (low <= 0 || high <= 0) return "—"
  if (low === high) return "₹" + indian(low)
  return "₹" + indian(low) + "–" + indian(high)
}

function lotLabel(ipo) {
  var lot = num(ipo && ipo.lot, 0)
  return lot > 0 ? lot + " sh" : "—"
}

function minInvest(ipo) {
  return rs(ipo && ipo.min_invest)
}

function gmp(ipo) {
  var v = Number(ipo && ipo.gmp)
  return isFinite(v) && v > 0 ? "₹" + indian(v) : "—"
}

function gmpPct(ipo) {
  var pct = num(ipo && ipo.gmp_pct, null)
  if (pct === null) {
    var high = num(ipo && ipo.band_high, 0)
    var g = Number(ipo && ipo.gmp)
    if (g > 0 && high > 0) pct = 100 * g / high
  }
  if (pct === null || !isFinite(pct)) return ""
  var sign = pct >= 0 ? "+" : "−"
  return sign + Math.abs(pct).toFixed(1).replace(/\.0$/, "") + "%"
}

// Map the page's trend emoji onto a stable glyph the theme can color.
function trendGlyph(ipo) {
  var t = String(ipo && ipo.trend || "")
  if (t.indexOf("🔴") !== -1 || t.indexOf("▼") !== -1 || t.indexOf("↓") !== -1) return "▼"
  if (t.indexOf("🟢") !== -1 || t.indexOf("▲") !== -1 || t.indexOf("↑") !== -1) return "▲"
  if (t.indexOf("🟡") !== -1) return "◆"
  return Number(ipo && ipo.gmp) > 0 ? "▲" : "◆"
}

function isPositive(ipo) {
  return trendGlyph(ipo) === "▲"
}

// Static trend colors, independent of the active theme: up -> green,
// down -> red, neutral (no premium / flat) -> "" so callers can fall back
// to a theme dim tone.
var UP_COLOR = "#22c55e"
var DOWN_COLOR = "#ef4444"

function trendColor(ipo) {
  var g = Number(ipo && ipo.gmp)
  if (g > 0) return UP_COLOR
  if (g < 0) return DOWN_COLOR
  return ""
}

function shortName(name, max) {
  var s = String(name || "")
  max = max || 24
  return s.length > max ? s.slice(0, max - 1) + "…" : s
}

function dateLabel(iso) {
  var m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(iso || ""))
  if (!m) return ""
  return m[3] + "/" + m[2] + "/" + m[1]
}

function closeRange(ipo) {
  var a = dateLabel(ipo && ipo.open)
  var b = dateLabel(ipo && ipo.close)
  if (b) return a ? a + " – " + b : "by " + b
  return ""
}

function kindLabel(ipo) {
  if (ipo && ipo.kind === "live") return "LIVE"
  if (ipo && ipo.kind === "closed") return "CLOSED"
  return "UPCOMING"
}

function isLive(ipo) {
  return !!(ipo && ipo.kind === "live")
}

function liveOnly(ipos) {
  var out = []
  for (var i = 0; i < ipos.length; i++) if (isLive(ipos[i])) out.push(ipos[i])
  return out
}

function upcomingOnly(ipos) {
  var out = []
  for (var i = 0; i < ipos.length; i++) {
    if (ipos[i] && ipos[i].kind === "upcoming") out.push(ipos[i])
  }
  return out
}

function closedOnly(ipos) {
  var out = []
  for (var i = 0; i < ipos.length; i++) {
    if (ipos[i] && ipos[i].kind === "closed") out.push(ipos[i])
  }
  return out
}

// Bar-pill summary: the next IPO to open (else first live), name + GMP.
function nextIpo(ipos) {
  if (!ipos || !ipos.length) return null
  for (var i = 0; i < ipos.length; i++) {
    if (!isLive(ipos[i])) return ipos[i]
  }
  return ipos[0]
}

function hasSub(ipo) {
  var s = ipo && ipo.sub
  return !!(s && isFinite(Number(s.total)) && Number(s.total) > 0)
}

function subTotal(ipo) {
  return num(ipo && ipo.sub && ipo.sub.total, 0)
}

// Subcategory values used for the subscription bars, oldest→newest.
function subValues(ipo) {
  var s = (ipo && ipo.sub) || {}
  return [num(s.qib, 0), num(s.nii, 0), num(s.retail, 0), num(s.total, 0)]
}

function subMax(ipo) {
  var vals = subValues(ipo)
  var max = 0
  for (var i = 0; i < vals.length; i++) max = Math.max(max, vals[i])
  return max
}

// Day-by-day GMP history from the detail page (newest first) -> chronological.
function sparkOrder(history) {
  var list = (history && history.length > 0) ? history : []
  var order = []
  for (var i = list.length - 1; i >= 0; i--) {
    var g = Number(list[i] && list[i].gmp)
    if (isFinite(g) && g > 0) order.push(g)
  }
  return order
}

var SPARK_CHARS = "▁▂▃▄▅▆▇█"

function sparkline(history) {
  var series = sparkOrder(history)
  if (series.length < 2) return ""
  var min = series[0], max = series[0]
  for (var i = 1; i < series.length; i++) {
    if (series[i] < min) min = series[i]
    if (series[i] > max) max = series[i]
  }
  var span = max - min
  var out = ""
  for (var j = 0; j < series.length; j++) {
    var v = span > 0 ? (series[j] - min) / span : 0.5
    var idx = Math.min(7, Math.max(0, Math.round(v * 7)))
    out += SPARK_CHARS.charAt(idx)
  }
  return out
}

// Chronological, normalized day points for the per-day GMP graph, each with a
// hover label and day-over-day delta.
function sparkDays(history) {
  var list = (history && history.length > 0) ? history : []
  var chrono = []
  for (var i = list.length - 1; i >= 0; i--) {
    var entry = list[i] || {}
    var g = Number(entry.gmp)
    if (isFinite(g) && g > 0) chrono.push({ d: String(entry.d || ""), gmp: g })
  }
  if (!chrono.length) return []
  var min = chrono[0].gmp, max = chrono[0].gmp
  for (var j = 1; j < chrono.length; j++) {
    if (chrono[j].gmp < min) min = chrono[j].gmp
    if (chrono[j].gmp > max) max = chrono[j].gmp
  }
  var span = max - min
  var result = []
  for (var k = 0; k < chrono.length; k++) {
    var raw = span > 0 ? (chrono[k].gmp - min) / span : 0.5
    var prev = k > 0 ? chrono[k - 1].gmp : null
    result.push({
      d: chrono[k].d,
      gmp: chrono[k].gmp,
      norm: span > 0 ? 0.15 + 0.85 * raw : 0.75,
      delta: prev === null ? null : chrono[k].gmp - prev,
      label: dateLabel(String(chrono[k].d)) || String(chrono[k].d) || ""
    })
  }
  return result
}

// Numeric GMP % used for sorting ("GMP value (in percentage)").
function sortPct(ipo) {
  var pct = num(ipo && ipo.gmp_pct, null)
  if (pct === null) {
    var high = num(ipo && ipo.band_high, 0)
    var g = Number(ipo && ipo.gmp)
    if (g > 0 && high > 0) pct = 100 * g / high
  }
  return isFinite(pct) ? pct : -1
}

function closeTs(ipo) {
  var t = Date.parse(String(ipo && ipo.close || ""))
  return isFinite(t) ? t : Number.MAX_VALUE
}

function searchIpos(ipos, query) {
  var q = String(query || "").toLowerCase().trim()
  if (!q || !ipos) return ipos
  var out = []
  for (var i = 0; i < ipos.length; i++) {
    var name = String(ipos[i] && ipos[i].name || "")
    if (name.toLowerCase().indexOf(q) >= 0) out.push(ipos[i])
  }
  return out
}

// Circular sort modes handled by the bar widget: default keeps the collector
// order, "pct" sorts by GMP % (highest first), "close" by close date.
function sortIpos(list, mode) {
  var arr = Array.isArray(list) ? list.slice() : []
  if (mode === "pct") {
    arr.sort(function(a, b) { return sortPct(b) - sortPct(a) })
  } else if (mode === "close") {
    arr.sort(function(a, b) { return closeTs(a) - closeTs(b) })
  }
  return arr
}

function processIpos(ipos, query, mode) {
  return sortIpos(searchIpos(ipos, query), mode)
}

function sortModeLabel(mode) {
  if (mode === "pct") return "GMP %"
  if (mode === "close") return "Close date"
  return "Default"
}

function parseCollector(text) {
  try {
    var parsed = JSON.parse(String(text || ""))
    if (!parsed || typeof parsed !== "object" || parsed.status !== "ok") {
      return { ok: false, error: "Could not parse IPO data" }
    }
    if (!Array.isArray(parsed.ipos)) {
      return { ok: false, error: "Could not parse IPO data" }
    }
    return {
      ok: true,
      data: {
        ipos: parsed.ipos,
        updatedAt: String(parsed.updatedAt || ""),
        error: String(parsed.error || "")
      }
    }
  } catch (e) {
    return { ok: false, error: "Could not parse IPO data" }
  }
}

var exportsObject = {
  UP_COLOR: UP_COLOR,
  DOWN_COLOR: DOWN_COLOR,
  num: num,
  indian: indian,
  rs: rs,
  band: band,
  lotLabel: lotLabel,
  minInvest: minInvest,
  gmp: gmp,
  gmpPct: gmpPct,
  trendGlyph: trendGlyph,
  isPositive: isPositive,
  trendColor: trendColor,
  shortName: shortName,
  dateLabel: dateLabel,
  closeRange: closeRange,
  kindLabel: kindLabel,
  isLive: isLive,
  liveOnly: liveOnly,
  closedOnly: closedOnly,
  upcomingOnly: upcomingOnly,
  nextIpo: nextIpo,
  hasSub: hasSub,
  subTotal: subTotal,
  subValues: subValues,
  subMax: subMax,
  sparkOrder: sparkOrder,
  sparkline: sparkline,
  sparkDays: sparkDays,
  sortPct: sortPct,
  closeTs: closeTs,
  searchIpos: searchIpos,
  sortIpos: sortIpos,
  processIpos: processIpos,
  sortModeLabel: sortModeLabel,
  parseCollector: parseCollector
}

if (typeof module !== "undefined" && module.exports) module.exports = exportsObject
var PUMP_MODES = ["quiet", "balanced", "performance"]
var DISPLAY_MODES = ["temp", "fans", "pump"]
var LOGO_MODES = ["fixed", "pulse", "blinking", "shift", "alert"]
var LOGO_SPEEDS = ["slower", "normal", "faster"]
var LOGO_SWATCHES = ["ffffff", "00c8ff", "3b6cff", "7c3aed", "c026d3", "ef4444", "ff9000", "22c55e", "000000"]
var ALERT_COLORS = ["00ff00", "ffff00", "ff0000"]

function clamp(value, min, max) {
  var n = Number(value)
  if (!isFinite(n)) return min
  return Math.max(min, Math.min(max, n))
}

function clampIndex(index, length) {
  if (length <= 0) return 0
  return Math.max(0, Math.min(length - 1, index))
}

function clampDuty(value) {
  return Math.round(clamp(value, 0, 100))
}

function emptyStatus(error) {
  return {
    present: false,
    description: "",
    liquidTemp: null,
    fan1Rpm: null,
    fan2Rpm: null,
    pumpMode: "balanced",
    pumpRpm: null,
    fanDuty: null,
    fanAuto: true,
    firmware: "",
    logoMode: "",
    logoColors: [],
    logoSpeed: "normal",
    error: error || "No cooler found"
  }
}

function normalizeHex(value) {
  var s = String(value || "").trim().replace(/^#/, "").toLowerCase()
  if (s.length === 3 && /^[0-9a-f]{3}$/.test(s))
    s = s.charAt(0) + s.charAt(0) + s.charAt(1) + s.charAt(1) + s.charAt(2) + s.charAt(2)
  if (!/^[0-9a-f]{6}$/.test(s)) return ""
  return s
}

function normalizeHexList(values) {
  var list = []
  var source = Array.isArray(values) ? values : []
  for (var i = 0; i < source.length; i++) {
    var hex = normalizeHex(source[i])
    if (hex) list.push(hex)
  }
  return list
}

function normalizeLogoMode(value) {
  var mode = String(value || "").trim().toLowerCase()
  return LOGO_MODES.indexOf(mode) >= 0 ? mode : ""
}

function normalizeLogoSpeed(value) {
  var speed = String(value || "").trim().toLowerCase()
  return LOGO_SPEEDS.indexOf(speed) >= 0 ? speed : "normal"
}

function logoCss(hex) {
  var value = normalizeHex(hex)
  return value ? "#" + value : ""
}

function logoModeLabel(mode) {
  var name = normalizeLogoMode(mode)
  if (name === "blinking") return "Blink"
  if (!name) return "Logo"
  return name.charAt(0).toUpperCase() + name.slice(1)
}

function logoSpeedLabel(speed) {
  var name = normalizeLogoSpeed(speed)
  return name.charAt(0).toUpperCase() + name.slice(1)
}

function logoNeedsSpeed(mode) {
  var name = normalizeLogoMode(mode)
  return name === "pulse" || name === "blinking" || name === "shift"
}

function logoNeedsColors(mode) {
  return normalizeLogoMode(mode) !== "alert"
}

function logoColorsForMode(mode, colors) {
  var name = normalizeLogoMode(mode)
  var list = normalizeHexList(colors)
  if (name === "alert") return ALERT_COLORS.slice()
  if (!list.length) list = ["00c8ff"]
  if (name === "shift") {
    if (list.length < 2) list.push("ffffff")
    return list.slice(0, 4)
  }
  if (name === "fixed") return list.slice(0, 1)
  return list.slice(0, 4)
}

function asNumber(value) {
  if (value === null || value === undefined || value === "") return null
  var n = Number(value)
  return isFinite(n) ? n : null
}

function normalizePumpMode(value) {
  var mode = String(value || "").trim().toLowerCase()
  return PUMP_MODES.indexOf(mode) >= 0 ? mode : "balanced"
}

function parseHelperOutput(raw) {
  var data
  try {
    data = JSON.parse(String(raw || "").trim() || "{}")
  } catch (e) {
    return emptyStatus("Could not read cooler")
  }
  if (!data || typeof data !== "object") return emptyStatus("Could not read cooler")

  var duty = asNumber(data.fanDuty)
  if (duty !== null) duty = clampDuty(duty)
  var fanAuto = data.fanAuto === true || duty === null
  if (fanAuto) duty = null

  return {
    present: data.present === true,
    description: String(data.description || ""),
    liquidTemp: asNumber(data.liquidTemp),
    fan1Rpm: asNumber(data.fan1Rpm),
    fan2Rpm: asNumber(data.fan2Rpm),
    pumpMode: normalizePumpMode(data.pumpMode),
    pumpRpm: asNumber(data.pumpRpm),
    fanDuty: duty,
    fanAuto: fanAuto,
    firmware: String(data.firmware || ""),
    logoMode: normalizeLogoMode(data.logoMode),
    logoColors: normalizeHexList(data.logoColors),
    logoSpeed: normalizeLogoSpeed(data.logoSpeed),
    error: String(data.error || "")
  }
}

function withPumpMode(status, mode) {
  var next = parseHelperOutput(JSON.stringify(status || {}))
  next.pumpMode = normalizePumpMode(mode)
  next.error = ""
  return next
}

function withFanDuty(status, duty) {
  var next = parseHelperOutput(JSON.stringify(status || {}))
  next.fanDuty = clampDuty(duty)
  next.fanAuto = false
  next.error = ""
  return next
}

function withFanAuto(status) {
  var next = parseHelperOutput(JSON.stringify(status || {}))
  next.fanDuty = null
  next.fanAuto = true
  next.error = ""
  return next
}

function withLogo(status, mode, colors, speed) {
  var next = parseHelperOutput(JSON.stringify(status || {}))
  next.logoMode = normalizeLogoMode(mode)
  next.logoColors = logoColorsForMode(next.logoMode, colors)
  next.logoSpeed = normalizeLogoSpeed(speed)
  next.error = ""
  return next
}

function formatTemp(value, decimals) {
  if (asNumber(value) === null) return "—"
  var n = Number(value)
  return (decimals ? n.toFixed(1) : String(Math.round(n))) + "°"
}

function formatRpm(value) {
  if (asNumber(value) === null) return "—"
  return String(Math.round(Number(value))) + " rpm"
}

function formatRpmShort(value) {
  if (asNumber(value) === null) return "—"
  return String(Math.round(Number(value)))
}

function pumpLabel(mode) {
  var name = normalizePumpMode(mode)
  return name.charAt(0).toUpperCase() + name.slice(1)
}

function pumpIcon(mode) {
  var name = normalizePumpMode(mode)
  if (name === "quiet") return "󰒲"
  if (name === "performance") return "󰓅"
  return "󰈐"
}

function coolerIcon() {
  return "󰖌"
}

function fanIcon() {
  return "󰈐"
}

function pumpGlyph() {
  return "󰡏"
}

function nextDisplayMode(mode) {
  var current = String(mode || "temp")
  var index = DISPLAY_MODES.indexOf(current)
  if (index < 0) index = 0
  return DISPLAY_MODES[(index + 1) % DISPLAY_MODES.length]
}

function barText(status, displayMode, vertical) {
  var data = status || emptyStatus()
  if (vertical || !data.present) return coolerIcon()
  if (displayMode === "fans") return formatRpmShort(data.fan1Rpm) + " " + fanIcon()
  if (displayMode === "pump") return formatRpmShort(data.pumpRpm) + " " + pumpGlyph()
  return formatTemp(data.liquidTemp, false) + " " + coolerIcon()
}

function tempUrgent(value) {
  var n = asNumber(value)
  return n !== null && n >= 50
}

function sliderDuty(status) {
  var data = status || emptyStatus()
  if (data.fanAuto || data.fanDuty === null) return 40
  return clampDuty(data.fanDuty)
}

function helperPathFromUrl(url) {
  var value = String(url || "")
  if (value.indexOf("file://") === 0) {
    var path = value.substring(7)
    if (path.indexOf("localhost/") === 0) path = path.substring(9)
    try {
      return decodeURIComponent(path)
    } catch (e) {
      return path
    }
  }
  return value
}

if (typeof module !== "undefined") {
  module.exports = {
    PUMP_MODES: PUMP_MODES,
    DISPLAY_MODES: DISPLAY_MODES,
    LOGO_MODES: LOGO_MODES,
    LOGO_SPEEDS: LOGO_SPEEDS,
    LOGO_SWATCHES: LOGO_SWATCHES,
    ALERT_COLORS: ALERT_COLORS,
    clamp: clamp,
    clampIndex: clampIndex,
    clampDuty: clampDuty,
    emptyStatus: emptyStatus,
    normalizePumpMode: normalizePumpMode,
    parseHelperOutput: parseHelperOutput,
    withPumpMode: withPumpMode,
    withFanDuty: withFanDuty,
    withFanAuto: withFanAuto,
    withLogo: withLogo,
    normalizeHex: normalizeHex,
    normalizeHexList: normalizeHexList,
    normalizeLogoMode: normalizeLogoMode,
    normalizeLogoSpeed: normalizeLogoSpeed,
    logoCss: logoCss,
    logoModeLabel: logoModeLabel,
    logoSpeedLabel: logoSpeedLabel,
    logoNeedsSpeed: logoNeedsSpeed,
    logoNeedsColors: logoNeedsColors,
    logoColorsForMode: logoColorsForMode,
    formatTemp: formatTemp,
    formatRpm: formatRpm,
    formatRpmShort: formatRpmShort,
    pumpLabel: pumpLabel,
    pumpIcon: pumpIcon,
    coolerIcon: coolerIcon,
    nextDisplayMode: nextDisplayMode,
    barText: barText,
    tempUrgent: tempUrgent,
    sliderDuty: sliderDuty,
    helperPathFromUrl: helperPathFromUrl
  }
}

import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "hhammarstrand.cooler"
  ipcTarget: "hhammarstrand.cooler"
  manageIpc: false

  property var status: Model.emptyStatus()
  property int pumpIndex: 1
  property string focusSection: "pump"
  property int selectedIndex: 0
  property bool cursorActive: false
  property bool fanSetQueued: false
  property bool pendingFanAuto: false
  property int pendingFanDuty: 40
  property bool logoSetQueued: false
  property var pendingLogo: []
  property int logoModeIndex: 0
  property int logoColorIndex: 0
  property int logoSpeedIndex: 1
  property real wheelAccumulator: 0
  property int phraseIndex: 0

  readonly property bool vertical: bar ? bar.vertical : false
  readonly property var pumpModes: Model.PUMP_MODES
  readonly property var logoModes: Model.LOGO_MODES
  readonly property var logoSpeeds: Model.LOGO_SPEEDS
  readonly property string displayMode: setting("displayMode", "temp")
  readonly property bool present: status.present === true
  readonly property string activePump: status.pumpMode || "balanced"
  readonly property bool fanAuto: status.fanAuto === true
  readonly property int fanDuty: Model.sliderDuty(status)
  readonly property string activeLogoMode: status.logoMode || ""
  readonly property var activeLogoColors: status.logoColors || []
  readonly property string activeLogoSpeed: status.logoSpeed || "normal"
  readonly property var logoSwatches: Model.LOGO_SWATCHES
  readonly property string logoPreview: Model.logoCss(activeLogoColors.length ? activeLogoColors[0] : "")
  readonly property var visibleSections: {
    var list = ["pump", "fan"]
    if (!present) return list
    list.push("logoMode")
    list.push("logoColor")
    if (Model.logoNeedsSpeed(activeLogoMode)) list.push("logoSpeed")
    return list
  }
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property real openPanelIndicatorWidth: !vertical ? button.labelWidth : 0
  readonly property var activePhrases: present ? [
    "Moving coolant",
    "Spinning blades",
    "Chilling silicon",
    "Pushing water",
    "Keeping quiet"
  ] : []
  readonly property string heroStatusText: {
    if (!present) return status.error || "Not connected"
    if (opened && activePhrases.length > 0)
      return activePhrases[phraseIndex % activePhrases.length]
    return Model.pumpLabel(activePump) + (fanAuto ? " · Auto fans" : "")
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  readonly property string helper: Model.helperPathFromUrl(Qt.resolvedUrl("coolerctl"))

  function refresh() {
    if (!statusProc.running) statusProc.running = true
  }

  function applySaved() {
    if (actionProc.running) return
    runHelper(["apply"])
  }

  function runHelper(args) {
    var command = [helper]
    for (var i = 0; i < args.length; i++) command.push(args[i])
    actionProc.command = command
    if (!actionProc.running) actionProc.running = true
  }

  function applyStatus(raw) {
    var parsed = Model.parseHelperOutput(raw)
    if (!parsed.present && root.status.present && parsed.error === "Could not read cooler")
      return
    root.status = parsed
    var idx = pumpModes.indexOf(root.activePump)
    if (idx >= 0) pumpIndex = idx
    var modeIdx = logoModes.indexOf(parsed.logoMode)
    if (modeIdx >= 0) logoModeIndex = modeIdx
    var colorIdx = logoSwatches.indexOf((parsed.logoColors && parsed.logoColors[0]) || "")
    if (colorIdx >= 0) logoColorIndex = colorIdx
    var speedIdx = logoSpeeds.indexOf(parsed.logoSpeed)
    if (speedIdx >= 0) logoSpeedIndex = speedIdx
  }

  function setPump(mode) {
    var next = Model.normalizePumpMode(mode)
    if (!next || actionProc.running) return
    pumpIndex = Math.max(0, pumpModes.indexOf(next))
    status = Model.withPumpMode(status, next)
    runHelper(["set-pump", next])
  }

  function setFan(value) {
    var duty = Model.clampDuty(value)
    pendingFanDuty = duty
    status = Model.withFanDuty(status, duty)
    if (actionProc.running) {
      fanSetQueued = true
      return
    }
    fanSetQueued = false
    runHelper(["set-fan", String(duty)])
  }

  function previewFan(value) {
    status = Model.withFanDuty(status, value)
    fanDebounce.restart()
  }

  function restoreAutoFans() {
    fanDebounce.stop()
    fanSetQueued = false
    status = Model.withFanAuto(status)
    if (actionProc.running) {
      pendingFanAuto = true
      return
    }
    pendingFanAuto = false
    runHelper(["fan-auto"])
  }

  function setLogo(mode, colors, speed) {
    var nextMode = Model.normalizeLogoMode(mode) || "fixed"
    var nextColors = Model.logoColorsForMode(nextMode, colors)
    var nextSpeed = Model.normalizeLogoSpeed(speed)
    status = Model.withLogo(status, nextMode, nextColors, nextSpeed)
    pendingLogo = ["set-logo", nextMode, nextSpeed].concat(nextColors)
    if (actionProc.running) {
      logoSetQueued = true
      return
    }
    logoSetQueued = false
    runHelper(pendingLogo)
  }

  function pickLogoMode(mode) {
    setLogo(mode, activeLogoColors, activeLogoSpeed)
  }

  function pickLogoColor(hex, asSecondary) {
    var mode = activeLogoMode || "fixed"
    var colors
    if (mode === "shift" && asSecondary) {
      var primary = activeLogoColors.length ? activeLogoColors[0] : hex
      colors = [primary, hex]
    } else if (mode === "shift") {
      var second = activeLogoColors.length > 1 ? activeLogoColors[1] : "ffffff"
      colors = [hex, second === hex ? "ffffff" : second]
    } else {
      colors = [hex]
    }
    var idx = logoSwatches.indexOf(hex)
    if (idx >= 0) logoColorIndex = idx
    setLogo(mode, colors, activeLogoSpeed)
  }

  function pickLogoSpeed(speed) {
    var idx = logoSpeeds.indexOf(speed)
    if (idx >= 0) logoSpeedIndex = idx
    setLogo(activeLogoMode || "pulse", activeLogoColors, speed)
  }

  function ensureCursorVisible(item) {
    if (!item || !scrollArea) return
    var flick = scrollArea.contentItem
    if (!flick || flick.contentY === undefined) return
    var pt = item.mapToItem(flick.contentItem || flick, 0, 0)
    var top = pt.y
    var bottom = top + (item.height || 0)
    var viewTop = flick.contentY
    var viewBottom = viewTop + flick.height
    var margin = 6
    if (top < viewTop + margin) flick.contentY = Math.max(0, top - margin)
    else if (bottom > viewBottom - margin)
      flick.contentY = bottom + margin - flick.height
  }

  function cycleDisplayMode() {
    var entry = { id: root.moduleName }
    for (var key in root.settings) if (key !== "id") entry[key] = root.settings[key]
    entry.displayMode = Model.nextDisplayMode(root.displayMode)
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function moveCursor(delta) {
    var sections = visibleSections
    var sIdx = sections.indexOf(focusSection)
    if (sIdx < 0) {
      focusSection = "pump"
      selectedIndex = pumpIndex
      return
    }
    var next = sIdx + (delta > 0 ? 1 : -1)
    if (next < 0 || next >= sections.length) return
    focusSection = sections[next]
    if (focusSection === "pump") selectedIndex = pumpIndex
    else if (focusSection === "fan") selectedIndex = -1
    else if (focusSection === "logoMode") selectedIndex = logoModeIndex
    else if (focusSection === "logoColor") selectedIndex = logoColorIndex
    else if (focusSection === "logoSpeed") selectedIndex = logoSpeedIndex
  }

  function moveCursorH(delta) {
    if (focusSection === "pump") {
      pumpIndex = Model.clampIndex(pumpIndex + delta, pumpModes.length)
      selectedIndex = pumpIndex
    } else if (focusSection === "fan") {
      setFan(fanDuty + delta * 5)
    } else if (focusSection === "logoMode") {
      logoModeIndex = Model.clampIndex(logoModeIndex + delta, logoModes.length)
      selectedIndex = logoModeIndex
    } else if (focusSection === "logoColor") {
      logoColorIndex = Model.clampIndex(logoColorIndex + delta, logoSwatches.length)
      selectedIndex = logoColorIndex
    } else if (focusSection === "logoSpeed") {
      logoSpeedIndex = Model.clampIndex(logoSpeedIndex + delta, logoSpeeds.length)
      selectedIndex = logoSpeedIndex
    }
  }

  function activateCursor() {
    if (focusSection === "pump") setPump(pumpModes[pumpIndex])
    else if (focusSection === "logoMode") pickLogoMode(logoModes[logoModeIndex])
    else if (focusSection === "logoColor") pickLogoColor(logoSwatches[logoColorIndex], false)
    else if (focusSection === "logoSpeed") pickLogoSpeed(logoSpeeds[logoSpeedIndex])
  }

  IpcHandler {
    target: "hhammarstrand.cooler"

    function open() { root.open() }
    function close() { root.close() }
    function show() { root.open() }
    function hide() { root.close() }
    function toggle() { root.toggle() }
    function refresh() { root.broadcast("refresh") }
    function cycleDisplay() { root.cycleDisplayMode() }
  }

  Component.onCompleted: applySaved()

  onOpenedChanged: {
    if (opened) {
      refresh()
      var idx = pumpModes.indexOf(activePump)
      pumpIndex = idx >= 0 ? idx : 1
      focusSection = "pump"
      selectedIndex = pumpIndex
      cursorActive = false
    }
  }

  Timer {
    interval: 5000
    running: true
    repeat: true
    onTriggered: if (!actionProc.running && !fanDebounce.running) root.refresh()
  }

  Timer {
    id: fanDebounce
    interval: 180
    repeat: false
    onTriggered: root.setFan(root.fanDuty)
  }

  Timer {
    id: phraseTimer
    interval: 2800
    running: root.opened && root.present
    repeat: true
    triggeredOnStart: false
    onTriggered: phraseSwap.restart()
  }

  SequentialAnimation {
    id: phraseSwap
    PropertyAnimation {
      target: heroStatus
      property: "opacity"
      to: 0.0
      duration: 180
      easing.type: Easing.OutQuad
    }
    ScriptAction {
      script: {
        var n = root.activePhrases.length
        if (n > 0) root.phraseIndex = (root.phraseIndex + 1) % n
      }
    }
    PropertyAnimation {
      target: heroStatus
      property: "opacity"
      to: 1.0
      duration: 260
      easing.type: Easing.InQuad
    }
  }

  Process {
    id: statusProc
    command: [root.helper, "status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyStatus(text)
    }
  }

  Process {
    id: actionProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyStatus(text)
    }
    onRunningChanged: {
      if (running) return
      if (root.pendingFanAuto) {
        root.pendingFanAuto = false
        root.fanSetQueued = false
        root.runHelper(["fan-auto"])
      } else if (root.fanSetQueued) root.setFan(root.pendingFanDuty)
      else if (root.logoSetQueued) {
        root.logoSetQueued = false
        root.runHelper(root.pendingLogo)
      }
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: Model.barText(root.status, root.displayMode, root.vertical)
    fontFamily: Style.font.family
    fontSize: Style.bar.iconFont
    horizontalMargin: 8.75
    dimmed: !root.present
    tooltipText: ""
    onPressed: function(b) {
      if (b === Qt.RightButton) root.cycleDisplayMode()
      else if (b === Qt.MiddleButton) root.refresh()
      else root.toggle()
    }
    onWheelMoved: function(delta) {
      var wheel = Util.wheelSteps(root.wheelAccumulator, delta)
      root.wheelAccumulator = wheel.remainder
      if (wheel.steps === 0) return
      root.setFan(root.fanDuty + wheel.steps * 5)
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        if (dy !== 0) root.moveCursor(dy)
        else if (dx !== 0) root.moveCursorH(dx)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      ScrollView {
        id: scrollArea
        anchors.fill: parent
        // Only clip when the column actually scrolls. Otherwise nerd-font
        // glyphs that paint above their line box get beheaded against the
        // viewport, which is what cut "H100i Pro" and the temperature.
        clip: column.implicitHeight > height
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical.policy: column.implicitHeight > height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
        Binding {
          target: scrollArea.contentItem
          property: "interactive"
          value: column.implicitHeight > scrollArea.height
        }

      Column {
        id: column
        width: scrollArea.availableWidth
        spacing: Style.space(14)

        Item {
          width: 1
          height: Style.space(12)
        }

        Item {
          width: parent.width
          implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, heroTemp.implicitHeight)

          Text {
            id: heroIcon
            textFormat: Text.PlainText
            text: Model.coolerIcon()
            color: root.logoPreview !== "" ? root.logoPreview : root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.display
            topPadding: Math.ceil(font.pixelSize * 0.2)
            bottomPadding: Math.ceil(font.pixelSize * 0.08)
            anchors.left: parent.left
            anchors.top: parent.top
          }

          Column {
            id: heroLabels
            anchors.left: heroIcon.right
            anchors.leftMargin: Style.space(14)
            anchors.right: heroTemp.left
            anchors.rightMargin: Style.space(10)
            anchors.top: parent.top
            spacing: Style.space(2)

            Text {
              text: "H100i Pro"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              topPadding: Math.ceil(font.pixelSize * 0.2)
              elide: Text.ElideRight
              width: parent.width
            }

            Text {
              id: heroStatus
              textFormat: Text.PlainText
              text: root.heroStatusText.toUpperCase()
              color: Qt.darker(root.foreground, 1.4)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
              topPadding: Math.ceil(font.pixelSize * 0.15)
              elide: Text.ElideRight
              width: parent.width
            }
          }

          Text {
            id: heroTemp
            textFormat: Text.PlainText
            text: Model.formatTemp(root.status.liquidTemp, true)
            color: Model.tempUrgent(root.status.liquidTemp) ? root.urgent : root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.displayLarge
            font.bold: true
            topPadding: Math.ceil(font.pixelSize * 0.2)
            bottomPadding: Math.ceil(font.pixelSize * 0.08)
            anchors.right: parent.right
            anchors.top: parent.top
          }
        }

        Row {
          visible: root.present
          width: parent.width
          spacing: Style.space(20)

          Column {
            width: (parent.width - parent.spacing) / 2
            spacing: Style.spacing.labelGap
            InfoPair { label: "Fan 1"; value: Model.formatRpm(root.status.fan1Rpm) }
            InfoPair { label: "Fan 2"; value: Model.formatRpm(root.status.fan2Rpm) }
          }

          Column {
            width: (parent.width - parent.spacing) / 2
            spacing: Style.spacing.labelGap
            InfoPair { label: "Pump"; value: Model.formatRpm(root.status.pumpRpm) }
            InfoPair { label: "Mode"; value: Model.pumpLabel(root.activePump) }
          }
        }

        PanelSeparator {
          visible: root.present
          foreground: root.foreground
        }

        Column {
          visible: root.present
          width: parent.width
          spacing: Style.space(10)

          PanelSectionHeader {
            text: "PUMP MODE"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Row {
            id: pumpRow
            width: parent.width
            spacing: Style.space(6)

            readonly property real cellWidth: (width - spacing * (root.pumpModes.length - 1)) / root.pumpModes.length

            Repeater {
              model: root.pumpModes
              Button {
                required property var modelData
                required property int index
                width: pumpRow.cellWidth
                iconText: Model.pumpIcon(String(modelData))
                iconSize: Style.font.title
                text: Model.pumpLabel(String(modelData))
                fontSize: Style.font.bodySmall
                foreground: root.foreground
                fontFamily: root.fontFamily
                horizontalPadding: Style.spacing.controlPaddingX
                verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
                bordered: true
                active: root.activePump === modelData
                hasCursor: root.cursorActive && root.focusSection === "pump" && root.pumpIndex === index
                onClicked: root.setPump(modelData)
                onHovered: function(h) {
                  if (h) {
                    root.cursorActive = true
                    root.focusSection = "pump"
                    root.pumpIndex = index
                    root.selectedIndex = index
                  }
                }
              }
            }
          }
        }

        PanelSeparator {
          visible: root.present
          foreground: root.foreground
        }

        Column {
          visible: root.present
          width: parent.width
          spacing: Style.space(6)

          Item {
            width: parent.width
            implicitHeight: Math.max(fanHeader.implicitHeight, fanAutoButton.implicitHeight)

            PanelSectionHeader {
              id: fanHeader
              text: "FAN SPEED"
              foreground: root.foreground
              fontFamily: root.fontFamily
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
            }

            Row {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(8)

              Text {
                id: fanPercent
                visible: !root.fanAuto || fanSlider.dragging
                textFormat: Text.PlainText
                text: Math.round(fanSlider.dragging ? fanSlider.liveValue : root.fanDuty) + "%"
                color: Qt.darker(root.foreground, 1.4)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                anchors.verticalCenter: parent.verticalCenter
              }

              Button {
                id: fanAutoButton
                text: "Auto"
                fontSize: Style.font.bodySmall
                foreground: root.foreground
                fontFamily: root.fontFamily
                horizontalPadding: Style.spacing.controlPaddingX
                verticalPadding: Style.spacing.controlPaddingY
                bordered: true
                active: root.fanAuto
                onClicked: root.restoreAutoFans()
              }
            }
          }

          CursorSurface {
            id: fanRow
            width: parent.width
            height: fanSlider.implicitHeight + Style.spacing.controlGap
            hasCursor: root.cursorActive && root.focusSection === "fan" && root.selectedIndex === -1
            foreground: root.foreground
            outline: true

            PanelSlider {
              id: fanSlider
              bar: root.bar
              anchors.fill: parent
              anchors.leftMargin: Style.space(6)
              anchors.rightMargin: Style.space(6)
              minimum: 0
              maximum: 100
              step: 5
              value: root.fanDuty
              integer: true
              onMoved: function(v) { root.previewFan(v) }
              onReleased: function(v) {
                fanDebounce.stop()
                root.setFan(v)
              }
              onRightClicked: root.restoreAutoFans()
            }

            HoverHandler {
              onHoveredChanged: if (hovered) {
                root.cursorActive = true
                root.focusSection = "fan"
                root.selectedIndex = -1
              }
            }
          }
        }

        PanelSeparator {
          visible: root.present
          foreground: root.foreground
        }

        Column {
          visible: root.present
          width: parent.width
          spacing: Style.space(10)

          Item {
            width: parent.width
            implicitHeight: Math.max(logoHeader.implicitHeight, logoHint.implicitHeight)

            PanelSectionHeader {
              id: logoHeader
              text: "LOGO"
              foreground: root.foreground
              fontFamily: root.fontFamily
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              id: logoHint
              visible: root.activeLogoMode === "shift"
              text: "Left + right click two colors"
              color: Qt.darker(root.foreground, 1.4)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
            }
          }

          Row {
            id: logoModeRow
            width: parent.width
            spacing: Style.space(6)

            readonly property real cellWidth: (width - spacing * (root.logoModes.length - 1)) / root.logoModes.length

            Repeater {
              model: root.logoModes
              Button {
                required property var modelData
                required property int index
                width: logoModeRow.cellWidth
                text: Model.logoModeLabel(String(modelData))
                fontSize: Style.font.bodySmall
                foreground: root.foreground
                fontFamily: root.fontFamily
                horizontalPadding: Style.space(2)
                verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
                bordered: true
                active: root.activeLogoMode === modelData
                hasCursor: root.cursorActive && root.focusSection === "logoMode" && root.logoModeIndex === index
                onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(logoModeRow)
                onClicked: root.pickLogoMode(modelData)
                onHovered: function(h) {
                  if (h) {
                    root.cursorActive = true
                    root.focusSection = "logoMode"
                    root.logoModeIndex = index
                    root.selectedIndex = index
                  }
                }
              }
            }
          }

          Row {
            id: logoColorRow
            visible: Model.logoNeedsColors(root.activeLogoMode || "fixed")
            width: parent.width
            spacing: Style.space(8)

            Repeater {
              model: root.logoSwatches
              Item {
                required property var modelData
                required property int index
                width: Style.space(22)
                height: Style.space(22)

                Rectangle {
                  anchors.fill: parent
                  radius: width / 2
                  color: Model.logoCss(modelData)
                  border.width: {
                    if (root.activeLogoColors[0] === modelData) return 2
                    if (root.activeLogoMode === "shift" && root.activeLogoColors[1] === modelData) return 2
                    return 1
                  }
                  border.color: {
                    if (root.activeLogoColors[0] === modelData) return root.foreground
                    if (root.activeLogoMode === "shift" && root.activeLogoColors[1] === modelData)
                      return Qt.darker(root.foreground, 1.5)
                    return Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.35)
                  }
                }

                Rectangle {
                  visible: root.cursorActive && root.focusSection === "logoColor" && root.logoColorIndex === index
                  anchors.fill: parent
                  anchors.margins: -Style.space(3)
                  radius: width / 2
                  color: "transparent"
                  border.width: 1
                  border.color: root.foreground
                  onVisibleChanged: if (visible) root.ensureCursorVisible(logoColorRow)
                }

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  acceptedButtons: Qt.LeftButton | Qt.RightButton
                  cursorShape: Qt.PointingHandCursor
                  onClicked: function(mouse) {
                    root.pickLogoColor(modelData, mouse.button === Qt.RightButton)
                  }
                  onEntered: {
                    root.cursorActive = true
                    root.focusSection = "logoColor"
                    root.logoColorIndex = index
                    root.selectedIndex = index
                  }
                }
              }
            }
          }

          Row {
            id: logoSpeedRow
            visible: Model.logoNeedsSpeed(root.activeLogoMode)
            width: parent.width
            spacing: Style.space(6)

            readonly property real cellWidth: (width - spacing * (root.logoSpeeds.length - 1)) / root.logoSpeeds.length

            Repeater {
              model: root.logoSpeeds
              Button {
                required property var modelData
                required property int index
                width: logoSpeedRow.cellWidth
                text: Model.logoSpeedLabel(String(modelData))
                fontSize: Style.font.bodySmall
                foreground: root.foreground
                fontFamily: root.fontFamily
                horizontalPadding: Style.spacing.controlPaddingX
                verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
                bordered: true
                active: root.activeLogoSpeed === modelData
                hasCursor: root.cursorActive && root.focusSection === "logoSpeed" && root.logoSpeedIndex === index
                onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(logoSpeedRow)
                onClicked: root.pickLogoSpeed(modelData)
                onHovered: function(h) {
                  if (h) {
                    root.cursorActive = true
                    root.focusSection = "logoSpeed"
                    root.logoSpeedIndex = index
                    root.selectedIndex = index
                  }
                }
              }
            }
          }
        }

        Text {
          visible: !root.present
          width: parent.width
          text: root.status.error || "Connect the cooler USB header and reload the panel."
          wrapMode: Text.WordWrap
          color: Qt.darker(root.foreground, 1.4)
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
      }
      }
    }
  }

  component InfoPair: Row {
    property string label: ""
    property string value: ""

    width: parent.width
    spacing: Style.space(8)

    InfoLabel { text: label }
    Item {
      width: Math.max(0, parent.width - parent.children[0].implicitWidth - parent.children[2].implicitWidth - parent.spacing * 2)
      height: 1
    }
    InfoValue { text: value }
  }

  component InfoLabel: Text {
    textFormat: Text.PlainText
    color: root.foreground
    opacity: 0.6
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  component InfoValue: Text {
    textFormat: Text.PlainText
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
  }
}

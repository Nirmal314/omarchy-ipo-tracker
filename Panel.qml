import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "archer-nemo.ipo-tracker"
  ipcTarget: "archer-nemo.ipo-tracker"

  property double nowMs: Date.now()
  property string expandedIpoSlug: ""
  property string sortMode: "default"
  property string searchText: ""
  property string focusedSlug: ""

  readonly property color foreground: bar ? bar.barForeground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color accent: Color.accent
  readonly property color dim: Qt.darker(foreground, 1.35)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property var visibleIpos: Model.processIpos(service.ipos, searchText, sortMode)
  readonly property var liveIpos: Model.liveOnly(visibleIpos)
  readonly property var closedIpos: Model.closedOnly(visibleIpos)
  readonly property var upcomingIpos: Model.upcomingOnly(visibleIpos)
  // Navigation must follow the order the Repeaters actually render
  // (all live cards, then all closed cards, then all upcoming cards)
  // NOT the raw sorted list, which interleaves different kinds under pct/close sort.
  readonly property var renderedIpos: liveIpos.concat(closedIpos).concat(upcomingIpos)
  readonly property string sortLabel: Model.sortModeLabel(sortMode)

  onVisibleIposChanged: ensureFocus()

  function ensureFocus() {
    if (visibleIndex(focusedSlug) < 0) focusFirst()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function visibleIndex(slug) {
    for (var i = 0; i < renderedIpos.length; i++)
      if (renderedIpos[i].slug === slug) return i
    return -1
  }
  function focusFirst() { if (renderedIpos.length) focusedSlug = renderedIpos[0].slug }
  function focusLast() { if (renderedIpos.length) focusedSlug = renderedIpos[renderedIpos.length - 1].slug }
  function focusMove(dir) {
    if (!renderedIpos.length) return
    var idx = visibleIndex(focusedSlug)
    if (idx < 0) idx = dir > 0 ? -1 : renderedIpos.length
    idx = (idx + dir + renderedIpos.length) % renderedIpos.length
    focusedSlug = renderedIpos[idx].slug
  }
  function ensureCardVisible(card) {
    if (!card || !scroll || !scroll.contentItem) return
    var view = scroll.contentItem
    var insets = Style.space(8)
    if (root.renderedIpos.length && card.ipo && card.ipo.slug === root.renderedIpos[0].slug) {
      view.contentY = 0
      return
    }
    var y = card.mapToItem(body, 0, 0).y
    var cardH = card.height
    var usableH = view.height - insets * 2
    if (cardH >= usableH) {
      // Card (typically an expanded one) is taller than the viewport - pin to its
      // top so the header/focus ring stays visible instead of chasing the bottom edge.
      view.contentY = y - insets
    } else if (y < view.contentY + insets) {
      view.contentY = y - insets
    } else if (y + cardH > view.contentY + view.height - insets) {
      view.contentY = y + cardH - (view.height - insets)
    }
    view.contentY = Math.max(0, Math.min(view.contentY, view.contentHeight - view.height))
  }
  function cycleSort(direction) {
    var order = ["default", "pct", "close"]
    var idx = order.indexOf(sortMode)
    if (idx < 0) idx = 0
    idx = (idx + (direction || 1) + order.length) % order.length
    sortMode = order[idx]
    focusFirst()
  }
  function toggleFocused() {
    if (focusedSlug) expandedIpoSlug = expandedIpoSlug === focusedSlug ? "" : focusedSlug
  }
  function searchFocus() {
    searchInput.forceActiveFocus()
    Qt.callLater(function() {
      if (scroll && scroll.contentItem) scroll.contentItem.contentY = 0
      searchInput.selectAll()
    })
  }

  function searchClear() {
    searchText = ""
    root.ensureFocus()
  }
  function searchBlur() {
    searchInput.focus = false
    catcher.forceActiveFocus()
  }

  function refresh() {
    nowMs = Date.now()
    service.refresh()
  }

  onOpenedChanged: if (opened) {
    nowMs = Date.now()
    if (!service.lastUpdated || (Date.now() - service.lastUpdated.getTime()) > 120000) root.refresh()
    Qt.callLater(function() { catcher.forceActiveFocus(); root.focusFirst() })
  }

  Service {
    id: service
    settings: root.settings
  }

  Timer {
    interval: 30000
    repeat: true
    running: true
    onTriggered: root.nowMs = Date.now()
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: " "
    fixedWidth: vertical ? -1 : content.implicitWidth + Style.space(16)
    tooltipText: "Indian mainboard IPOs · " + service.ipos.length + " active · click for details · R or middle-click to refresh"
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton || buttonCode === Qt.MiddleButton) root.refresh()
      else root.toggle()
    }

    Row {
      id: content
      anchors.centerIn: parent
      spacing: Style.space(5)

      ChartLineIcon {
        anchors.verticalCenter: parent.verticalCenter
        iconSize: Style.font.icon
        color: root.foreground
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: catcher
    contentWidth: panel.fittedContentWidth(Style.space(640))
    contentHeight: panel.fittedContentHeight(body.implicitHeight, Style.space(820))

    PanelKeyCatcher {
      id: catcher
      anchors.fill: parent
      blocked: searchInput.activeFocus
      onCloseRequested: root.close()
      onTextKey: function(text) {
        if (text === "/") root.searchFocus()
        else if (text === "r" || text === "R") root.refresh()
        else if (text === "j") root.focusMove(1)
        else if (text === "k") root.focusMove(-1)
      }
      onTabRequested: function(direction) { root.cycleSort(direction) }
      onMoveRequested: function(dx, dy) { root.focusMove(dy !== 0 ? dy : dx) }
      onActivateRequested: root.toggleFocused()

      ScrollView {
        id: scroll
        anchors.fill: parent
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical.policy: body.implicitHeight > height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
        Binding {
          target: scroll.contentItem
          property: "interactive"
          value: body.implicitHeight > scroll.height
        }

        Column {
          id: body
          width: scroll.availableWidth
          spacing: Style.space(16)

          Text {
            width: parent.width
            text: "Updated " + (service.lastUpdated.getTime() > 0 ? Qt.formatTime(service.lastUpdated, "h:mm:ss AP") : "never")
              + " · Sort: " + root.sortLabel
              + " · " + (service.refreshing ? "Refreshing…" : "R refresh")
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }

          PanelHero {
            width: parent.width
            title: "IPO Tracker"
            meta: root.searchText
              ? visibleIpos.length + " of " + service.ipos.length + " IPOs · " + root.sortLabel + " sort"
              : service.ipos.length + " mainboard IPOs · "
                + liveIpos.length + " live · " + closedIpos.length + " closed · " + upcomingIpos.length + " upcoming"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          TextField {
            id: searchInput
            width: parent.width
            text: root.searchText
            foreground: root.foreground
            accent: root.accent
            placeholderText: "Search IPOs by name…"
            onTextChanged: {
              root.searchText = text
              root.ensureFocus()
            }
            Keys.onPressed: function(event) {
              var key = event.key
              if (key === Qt.Key_Escape) { event.accepted = true; root.close(); return }
              if (key === Qt.Key_Backspace) { event.accepted = true; root.searchClear(); return }
              if (key === Qt.Key_Tab || key === Qt.Key_Backtab) { event.accepted = true; root.cycleSort(); root.searchBlur(); return }
              if (key === Qt.Key_Return || key === Qt.Key_Enter) { event.accepted = true; root.toggleFocused(); root.searchBlur(); return }
              if (key === Qt.Key_Down) { event.accepted = true; root.focusMove(1); selectAll(); return }
              if (key === Qt.Key_Up) { event.accepted = true; root.focusMove(-1); selectAll(); return }
            }
          }

          Text {
            visible: service.lastError !== ""
            width: parent.width
            text: service.lastError
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Text {
            visible: service.refreshing && !service.ipos.length
            width: parent.width
            text: "Fetching latest IPO data…"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.italic: true
          }

          Text {
            visible: !service.refreshing && !service.ipos.length && service.lastError === ""
            width: parent.width
            text: "No active IPOs right now."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Text {
            visible: service.ipos.length > 0 && visibleIpos.length === 0
            width: parent.width
            text: "No mainboard IPO matches \"" + searchText + "\"."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          PanelSeparator {
            visible: service.ipos.length > 0
            width: parent.width
            foreground: root.foreground
          }

          Text {
            visible: service.ipos.length > 0
            width: parent.width
            text: "↑↓ / j k focus · ↵ toggles details · Tab cycles sort · / search · Esc closes · R refresh\nhover the graph for daily GMP. Prices in ₹."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          PanelSeparator {
            visible: service.ipos.length > 0
            width: parent.width
            foreground: root.foreground
          }

          PanelSectionHeader {
            visible: liveIpos.length > 0
            text: "NOW BIDDING (" + liveIpos.length + ")"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Repeater {
            model: liveIpos

            delegate: IpoCard {
              width: body.width
            }
          }

          PanelSectionHeader {
            visible: closedIpos.length > 0
            text: "CLOSED · LISTING PENDING (" + closedIpos.length + ")"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Repeater {
            model: closedIpos

            delegate: IpoCard {
              width: body.width
            }
          }

          PanelSectionHeader {
            visible: upcomingIpos.length > 0
            text: "UPCOMING (" + upcomingIpos.length + ")"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Repeater {
            model: upcomingIpos

            delegate: IpoCard {
              width: body.width
            }
          }

          PanelSeparator {
            visible: service.ipos.length > 0
            width: parent.width
            foreground: root.foreground
          }
        }
      }
    }
  }

  component IpoCard: Column {
    id: card
    required property var modelData
    readonly property var ipo: modelData || {}
    readonly property bool expanded: root.expandedIpoSlug === ipo.slug
    readonly property bool hovered: cardHover.hovered
    readonly property bool focused: root.focusedSlug === ipo.slug
    onFocusedChanged: if (focused) Qt.callLater(root.ensureCardVisible, card)
    onExpandedChanged: if (expanded) Qt.callLater(root.ensureCardVisible, card)
    spacing: Style.space(4)

    Rectangle {
      id: cardSurface
      width: parent.width
      implicitHeight: cardCol.implicitHeight + Style.space(16)
      radius: Math.max(4, Style.cornerRadius)
      color: expanded
        ? Style.hoverFillFor(root.foreground, root.accent)
        : (hovered ? Style.normalFillFor(root.foreground, root.accent)
                   : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04))
      border.width: focused ? 2 : 0
      border.color: root.accent

      Column {
        id: cardCol
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Style.space(16)
        anchors.rightMargin: Style.space(16)
        anchors.topMargin: Style.space(8)
        anchors.bottomMargin: Style.space(8)
        spacing: Style.space(6)

        RowLayout {
          width: parent.width

          Text {
            Layout.fillWidth: true
            textFormat: Text.PlainText
            text: (expanded ? "▾ " : "▸ ") + ipo.name
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.subtitle
            font.bold: true
            elide: Text.ElideRight
          }

          StatusPill {
            kind: ipo.kind
            foreground: root.foreground
            accent: root.accent
            dim: root.dim
            fontFamily: root.fontFamily
          }
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: Model.closeRange(ipo)
            + (modelData.listing ? " · list " + Model.dateLabel(ipo.dates ? ipo.dates.listing : "") : "")
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }

        RowLayout {
          width: parent.width
          spacing: Style.space(12)

          Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: Model.band(ipo) + "  ×  " + Model.lotLabel(ipo) + "  ≈  " + Model.minInvest(ipo)
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
          }

          Text {
            textFormat: Text.PlainText
            text: Model.gmp(ipo)
            color: Model.trendColor(ipo) || root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.bold: true
          }

          Text {
            textFormat: Text.PlainText
            text: Model.trendGlyph(ipo)
            color: Model.trendColor(ipo) || root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Text {
            textFormat: Text.PlainText
            visible: Model.gmpPct(ipo) !== ""
            text: Model.gmpPct(ipo)
            color: Model.trendColor(ipo) || root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Sparkline {
            visible: ipo.gmp_history && ipo.gmp_history.length > 1
            history: ipo.gmp_history
            stroke: Model.trendColor(ipo) || root.dim
            dim: root.dim
            fontFamily: root.fontFamily
          }
        }

        Column {
          visible: expanded
          width: parent.width
          spacing: Style.space(6)

          PanelSeparator {
            width: parent.width
            foreground: root.foreground
            strength: 0.2
          }

          Column {
            visible: Model.hasSub(ipo)
            width: parent.width
            spacing: Style.space(5)

            RowLayout {
              width: parent.width

              Text {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                text: "Subscription · Total " + Model.subTotal(ipo).toFixed(2) + "×"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: true
              }
              Text {
                textFormat: Text.PlainText
                text: ipo.sub && ipo.sub.updated ? "as of " + ipo.sub.updated : ""
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }

            SubBar {
              label: "QIB"
              value: Model.subValues(ipo)[0]
              max: Model.subMax(ipo)
              foreground: root.foreground
              accent: root.accent
              dim: root.dim
              fontFamily: root.fontFamily
            }
            SubBar {
              label: "NII"
              value: Model.subValues(ipo)[1]
              max: Model.subMax(ipo)
              foreground: root.foreground
              accent: root.accent
              dim: root.dim
              fontFamily: root.fontFamily
            }
            SubBar {
              label: "RETAIL"
              value: Model.subValues(ipo)[2]
              max: Model.subMax(ipo)
              foreground: root.foreground
              accent: root.accent
              dim: root.dim
              fontFamily: root.fontFamily
            }
            SubBar {
              label: "TOTAL"
              value: Model.subValues(ipo)[3]
              max: Model.subMax(ipo)
              foreground: root.foreground
              accent: root.accent
              dim: root.dim
              fontFamily: root.fontFamily
            }
          }

          Grid {
            columns: 2
            columnSpacing: Style.space(32)
            rowSpacing: Style.space(5)
            width: parent.width

            Text { textFormat: Text.PlainText; text: "Open"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
            Text { textFormat: Text.PlainText; text: Model.dateLabel(ipo.open); color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
            Text { textFormat: Text.PlainText; text: "Close"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
            Text { textFormat: Text.PlainText; text: Model.dateLabel(ipo.close); color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
            Text { visible: ipo.dates && ipo.dates.basis !== ""; textFormat: Text.PlainText; text: "Allotment"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
            Text { visible: ipo.dates && ipo.dates.basis !== ""; textFormat: Text.PlainText; text: ipo.dates ? ipo.dates.basis : ""; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
            Text { visible: ipo.dates && ipo.dates.refund !== ""; textFormat: Text.PlainText; text: "Refunds"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
            Text { visible: ipo.dates && ipo.dates.refund !== ""; textFormat: Text.PlainText; text: ipo.dates ? ipo.dates.refund : ""; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
            Text { visible: ipo.dates && ipo.dates.demat !== ""; textFormat: Text.PlainText; text: "Demat"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
            Text { visible: ipo.dates && ipo.dates.demat !== ""; textFormat: Text.PlainText; text: ipo.dates ? ipo.dates.demat : ""; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
            Text { textFormat: Text.PlainText; text: "Listing"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
            Text { textFormat: Text.PlainText; text: ipo.dates ? Model.dateLabel(ipo.dates.listing) : ""; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
          }

          RowLayout {
            width: parent.width
            spacing: Style.space(16)
            visible: ipo.face_value !== "" || ipo.issue_size !== "" || ipo.listing !== ""

            Text {
              textFormat: Text.PlainText
              Layout.fillWidth: true
              text: [ipo.face_value, ipo.issue_size, ipo.listing].filter(function(x) { return x !== "" }).join(" · ")
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }

        }
      }

      MouseArea {
        id: cardHover
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: root.focusedSlug = ipo.slug
        onClicked: root.expandedIpoSlug = card.expanded ? "" : ipo.slug
      }
    }
  }

  component Sparkline: Item {
    id: spark
    property var history: []
    property color stroke: Color.accent
    property color dim: Color.foreground
    property string fontFamily: Style.font.family

    readonly property var days: Model.sparkDays(history)
    readonly property real barW: Style.space(7)
    readonly property real barGap: Style.space(3)
    readonly property real pad: Style.space(4)
    readonly property real plotH: Style.space(24)
    readonly property real tipH: Style.space(22)

    property int hoverIndex: -1

    implicitHeight: tipH + plotH
    implicitWidth: days.length * (barW + barGap) - barGap + 2 * pad

    Rectangle {
      id: tipBox
      visible: spark.hoverIndex >= 0
      width: tipLabel.implicitWidth + Style.space(14)
      height: tipLabel.implicitHeight + Style.space(4)
      radius: Math.min(6, height / 2)
      color: Qt.rgba(spark.dim.r, spark.dim.g, spark.dim.b, 0.12)
      border.width: 1
      border.color: Qt.rgba(spark.stroke.r, spark.stroke.g, spark.stroke.b, 0.5)
      x: {
        var i = spark.hoverIndex
        if (i < 0) return 0
        var cx = spark.pad + i * (spark.barW + spark.barGap) + spark.barW / 2
        return Math.max(0, Math.min(spark.width - width, cx - width / 2))
      }
      y: 0

      Text {
        id: tipLabel
        anchors.centerIn: parent
        textFormat: Text.PlainText
        text: {
          var d = spark.days[spark.hoverIndex]
          if (!d) return ""
          var out = d.label + "  ₹" + d.gmp
          if (isFinite(d.delta) && d.delta !== 0)
            out += "  " + (d.delta > 0 ? "+" : "−") + Math.abs(d.delta).toFixed(0)
          return out
        }
        color: spark.stroke
        font.family: spark.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
      }
    }

    Item {
      id: plot
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.topMargin: spark.tipH
      height: spark.plotH

      Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 1
        color: Qt.rgba(spark.dim.r, spark.dim.g, spark.dim.b, 0.3)
      }

      Repeater {
        model: spark.days

        delegate: Item {
          required property int index
          required property var modelData
          width: spark.barW + spark.barGap
          height: plot.height
          x: index * (spark.barW + spark.barGap)

          MouseArea {
            id: dayHit
            anchors.fill: parent
            hoverEnabled: true
            onEntered: spark.hoverIndex = index
            onExited: if (spark.hoverIndex === index) spark.hoverIndex = -1
          }

          Rectangle {
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            width: spark.barW
            height: Math.max(Style.space(3), modelData.norm * (parent.height - Style.space(2)))
            radius: Math.min(3, width / 2)
            color: spark.hoverIndex === index ? Qt.lighter(spark.stroke, 1.3) : spark.stroke
            opacity: spark.hoverIndex === index ? 1 : 0.8
          }
        }
      }
    }
  }

  component StatusPill: Rectangle {
    property string kind: "upcoming"
    property color foreground: Color.foreground
    property color accent: Color.accent
    property color dim: Color.foreground
    property string fontFamily: Style.font.family

    readonly property bool live: kind === "live"
    readonly property bool closed: kind === "closed"
    width: pillText.implicitWidth + Style.space(10)
    height: pillText.implicitHeight + Style.space(4)
    radius: Math.min(8, height / 2)
    color: live ? Qt.rgba(accent.r, accent.g, accent.b, 0.22)
                : closed ? Qt.rgba(dim.r, dim.g, dim.b, 0.14)
                         : Qt.rgba(dim.r, dim.g, dim.b, 0.18)
    border.width: 1
    border.color: live ? Qt.rgba(accent.r, accent.g, accent.b, 0.55)
                       : Qt.rgba(dim.r, dim.g, dim.b, 0.4)

    Text {
      id: pillText
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: live ? "LIVE" : closed ? "CLOSED" : "UPCOMING"
      color: live ? accent : Qt.darker(dim, 1.15)
      font.family: fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
    }
  }

  component SubBar: RowLayout {
    id: subRow
    property string label: ""
    property real value: 0
    property real max: 1
    property color foreground: Color.foreground
    property color accent: Color.accent
    property color dim: Color.foreground
    property string fontFamily: Style.font.family

    width: parent ? parent.width : implicitWidth
    spacing: Style.space(10)

    Text {
      textFormat: Text.PlainText
      text: subRow.label
      color: subRow.dim
      font.family: subRow.fontFamily
      font.pixelSize: Style.font.caption
      Layout.preferredWidth: Style.space(48)
    }

    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: Style.space(8)
      radius: height / 2
      color: Qt.rgba(subRow.foreground.r, subRow.foreground.g, subRow.foreground.b, 0.14)

      Rectangle {
        width: subRow.max > 0 ? parent.width * Math.min(1, subRow.value / subRow.max) : 0
        height: parent.height
        radius: parent.radius
        color: subRow.value >= 1 ? subRow.accent : Qt.rgba(subRow.foreground.r, subRow.foreground.g, subRow.foreground.b, 0.7)

        Behavior on width { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
      }
    }

    Text {
      textFormat: Text.PlainText
      text: subRow.value.toFixed(2) + "×"
      color: subRow.value >= 1 ? subRow.accent : subRow.foreground
      font.family: subRow.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: subRow.value >= 1
    }
  }

  component LinkChip: Rectangle {
    id: chip
    property string text: ""
    property string url: ""
    property bool enabled: true
    property color foreground: Color.foreground
    property color accent: Color.accent
    property color dim: Color.foreground
    property string fontFamily: Style.font.family

    width: chipText.implicitWidth + Style.space(12)
    height: chipText.implicitHeight + Style.space(6)
    radius: Math.min(8, height / 2)
    color: chipMouse.containsMouse && enabled
      ? Qt.rgba(accent.r, accent.g, accent.b, 0.22)
      : Qt.rgba(dim.r, dim.g, dim.b, 0.12)
    border.width: 1
    border.color: chipMouse.containsMouse && enabled
      ? Qt.rgba(accent.r, accent.g, accent.b, 0.55)
      : Qt.rgba(dim.r, dim.g, dim.b, 0.3)

    Text {
      id: chipText
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: chip.text + " ↗"
      color: chip.enabled ? foreground : Qt.darker(dim, 1.2)
      font.family: fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
    }

    MouseArea {
      id: chipMouse
      anchors.fill: parent
      enabled: chip.enabled
      hoverEnabled: true
      cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: if (enabled) Util.execArgv(["xdg-open", chip.url])
    }
  }
}

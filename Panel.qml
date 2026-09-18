import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "ozdil.netradar"
  ipcTarget: "ozdil.netradar"
  manageIpc: false

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  property string iface: "wlan0"
  property string localIp: "127.0.0.1"
  property string gateway: "192.168.1.1"
  property int subnetMask: 24
  property int deviceCount: 0
  property var devices: []
  property var filteredDevices: []
  property string searchQuery: ""
  property bool isScanning: false
  property string copyNotice: ""
  readonly property string fontFamily: (root.bar && root.bar.fontFamily) ? root.bar.fontFamily : ((typeof Style !== "undefined" && Style.font && Style.font.family) ? Style.font.family : "JetBrainsMono Nerd Font, JetBrains Mono, monospace")

  function resolveEnginePath() {
    return Qt.resolvedUrl("netradar-engine").toString().replace(/^file:\/\//, "")
  }

  function isValidIp(ip) {
    return typeof ip === "string" && /^([0-9]{1,3}\.){3}[0-9]{1,3}$/.test(ip.trim())
  }

  function scan() {
    if (scanProc.running) return
    root.isScanning = true
    scanProc.command = [root.resolveEnginePath(), "--scan"]
    scanProc.running = true
  }

  function ping(ip) {
    if (!isValidIp(ip)) return
    pingProc.command = [root.resolveEnginePath(), "--ping", ip]
    pingProc.running = true
  }

  function openWeb(ip, port) {
    if (!isValidIp(ip) || typeof port !== "number" || port < 1 || port > 65535) return
    var proto = (port === 443) ? "https" : "http"
    var url = proto + "://" + ip + ((port === 80 || port === 443) ? "" : (":" + port))
    actionProc.command = ["xdg-open", url]
    actionProc.running = true
    root.copyNotice = "Tarayıcıda açılıyor: " + url
    copyNoticeTimer.restart()
  }

  function openSsh(ip) {
    if (!isValidIp(ip)) return
    actionProc.command = ["foot", "ssh", "--", ip]
    actionProc.running = true
    root.copyNotice = "SSH Başlatıldı: " + ip
    copyNoticeTimer.restart()
  }

  function copyText(txt, label) {
    copyProc.command = ["wl-copy", txt]
    copyProc.running = true
    root.copyNotice = label + " kopyalandı: " + txt
    copyNoticeTimer.restart()
  }

  function filterDevices() {
    var q = root.searchQuery.trim().toLowerCase()
    if (q === "") {
      root.filteredDevices = root.devices
      return
    }
    var list = []
    for (var i = 0; i < root.devices.length; i++) {
      var d = root.devices[i]
      var matchIp = (d.ip || "").toLowerCase().indexOf(q) !== -1
      var matchMac = (d.mac || "").toLowerCase().indexOf(q) !== -1
      var matchHost = (d.hostname || "").toLowerCase().indexOf(q) !== -1
      var matchVendor = (d.vendor || "").toLowerCase().indexOf(q) !== -1
      var matchAlias = (d.alias || "").toLowerCase().indexOf(q) !== -1
      if (matchIp || matchMac || matchHost || matchVendor || matchAlias) {
        list.push(d)
      }
    }
    root.filteredDevices = list
  }

  onSearchQueryChanged: filterDevices()

  // Scan Subprocess
  Process {
    id: scanProc
    running: false
    command: []
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").slice(0, 65536)
        if (!raw || raw.trim().length === 0) {
          root.isScanning = false
          return
        }
        try {
          var parsed = JSON.parse(raw)
          root.iface = parsed.interface || "wlan0"
          root.localIp = parsed.local_ip || "127.0.0.1"
          root.gateway = parsed.gateway || "192.168.1.1"
          root.subnetMask = parsed.subnet_mask || 24
          root.deviceCount = parsed.device_count || 0
          root.devices = parsed.devices || []
          root.filterDevices()
        } catch (err) {
          console.warn("NetRadar parse error:", err)
        }
        root.isScanning = false
      }
    }
  }

  // Ping Subprocess
  Process {
    id: pingProc
    running: false
    command: []
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").slice(0, 4096)
        if (!raw) return
        try {
          var res = JSON.parse(raw)
          if (res.ip && res.latency_ms !== null) {
            for (var i = 0; i < root.devices.length; i++) {
              if (root.devices[i].ip === res.ip) {
                root.devices[i].latency_ms = res.latency_ms
                break
              }
            }
            root.filterDevices()
          }
        } catch (e) {}
      }
    }
  }

  // Clipboard copy process
  Process {
    id: copyProc
    running: false
    command: []
  }

  Process {
    id: actionProc
    running: false
    command: []
  }

  Timer {
    id: copyNoticeTimer
    interval: 2500
    running: false
    onTriggered: root.copyNotice = ""
  }

  // Auto-scan on load and every 45s
  Timer {
    id: autoScanTimer
    interval: 45000
    running: true
    repeat: true
    onTriggered: root.scan()
  }

  Component.onCompleted: {
    root.scan()
  }

  Component.onDestruction: {
    if (scanProc.running) scanProc.running = false
    if (pingProc.running) pingProc.running = false
    if (copyProc.running) copyProc.running = false
    if (autoScanTimer.running) autoScanTimer.running = false
  }

  // Top Bar Icon Button
  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰈀"
    foreground: root.isScanning ? "#00e5ff" : (root.bar ? root.bar.foreground : Color.foreground)
    tooltipText: "NetRadar: " + root.deviceCount + " Cihaz Bağlı (" + root.iface + ")"
    onPressed: function(b) {
      root.toggle()
      if (root.opened) root.scan()
    }

    Rectangle {
      visible: root.deviceCount > 0
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.margins: 2
      width: Style.space(14)
      height: Style.space(14)
      radius: Style.space(7)
      color: "#00e5ff"

      Text {
        anchors.centerIn: parent
        textFormat: Text.PlainText
        text: root.deviceCount > 99 ? "99+" : root.deviceCount.toString()
        font.pixelSize: Style.font.micro
        font.bold: true
        color: "#0d0e15"
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    contentWidth: panel.fittedContentWidth(Style.space(440))
    contentHeight: panel.fittedContentHeight(panelCol.implicitHeight, Style.space(620))

    ScrollView {
      id: scrollArea
      anchors.fill: parent
      clip: true
      ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
      ScrollBar.vertical.policy: panelCol.implicitHeight > height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff

      Column {
        id: panelCol
        width: scrollArea.availableWidth
        spacing: Style.space(12)

        // Header
        RowLayout {
          width: parent.width
          spacing: Style.space(10)

          Text {
            textFormat: Text.PlainText
            text: "󰈀"
            color: "#00e5ff"
            font.family: root.fontFamily
            font.pixelSize: Style.font.display
          }

          Column {
            Layout.fillWidth: true
            spacing: Style.space(2)

            Text {
              textFormat: Text.PlainText
              text: "NetRadar"
              color: root.bar ? root.bar.foreground : Color.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
              font.bold: true
            }

            Text {
              textFormat: Text.PlainText
              text: root.deviceCount + " Cihaz • " + root.iface + " (" + root.localIp + "/" + root.subnetMask + ")"
              color: Color.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.subtext
            }
          }

          // Scan / Refresh Button
          Button {
            id: refreshBtn
            flat: true
            implicitWidth: Style.space(34)
            implicitHeight: Style.space(34)
            onClicked: root.scan()

            background: Rectangle {
              radius: Style.space(8)
              color: refreshBtn.hovered ? Color.m3surface : "transparent"
            }

            contentItem: Text {
              anchors.centerIn: parent
              textFormat: Text.PlainText
              text: ""
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
              color: root.isScanning ? "#00e5ff" : Color.muted
              rotation: root.isScanning ? spinAnim.currentAngle : 0

              NumberAnimation on rotation {
                id: spinAnim
                running: root.isScanning
                loops: Animation.Infinite
                from: 0
                to: 360
                duration: 1000
                property real currentAngle: 0
              }
            }
          }
        }

        // Gateway & Subnet Card
        Rectangle {
          width: parent.width
          implicitHeight: Style.space(42)
          radius: Style.space(8)
          color: Color.m3surface

          RowLayout {
            anchors.fill: parent
            anchors.margins: Style.space(10)
            spacing: Style.space(12)

            Text {
              textFormat: Text.PlainText
              text: "󰈀 Gateway: " + root.gateway
              color: "#00e5ff"
              font.pixelSize: Style.font.caption
              font.bold: true
            }

            Rectangle {
              implicitWidth: gwWebText.implicitWidth + Style.space(12)
              implicitHeight: Style.space(22)
              radius: Style.space(4)
              color: Qt.rgba(0, 0.9, 1, 0.2)
              border.color: "#00e5ff"
              border.width: 1

              RowLayout {
                anchors.centerIn: parent
                spacing: Style.space(4)
                Text {
                  textFormat: Text.PlainText
                  text: "󰖟"
                  font.pixelSize: Style.font.micro
                  color: "#00e5ff"
                }
                Text {
                  id: gwWebText
                  textFormat: Text.PlainText
                  text: "Web Aç"
                  font.bold: true
                  font.pixelSize: Style.font.micro
                  color: root.bar ? root.bar.foreground : Color.foreground
                }
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.openWeb(root.gateway, 80)
              }
            }

            Item { Layout.fillWidth: true }

            Text {
              textFormat: Text.PlainText
              text: "Yerel: " + root.localIp
              color: Color.muted
              font.pixelSize: Style.font.caption
            }
          }
        }

        // Search Input
        Rectangle {
          width: parent.width
          implicitHeight: Style.space(38)
          radius: Style.space(8)
          color: Color.m3surface
          border.color: searchInput.activeFocus ? "#00e5ff" : "transparent"
          border.width: 1

          RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Style.space(10)
            anchors.rightMargin: Style.space(10)
            spacing: Style.space(8)

            Text {
              textFormat: Text.PlainText
              text: ""
              color: Color.muted
              font.pixelSize: Style.font.subtext
            }

            TextField {
              id: searchInput
              Layout.fillWidth: true
              placeholderText: "IP, MAC, Hostname veya Üretici Ara..."
              placeholderTextColor: Color.muted
              color: root.bar ? root.bar.foreground : Color.foreground
              font.pixelSize: Style.font.subtext
              background: null
              onTextChanged: root.searchQuery = text
            }

            // Clear Button
            Text {
              visible: searchInput.text.length > 0
              textFormat: Text.PlainText
              text: ""
              color: Color.muted
              font.pixelSize: Style.font.subtext
              MouseArea {
                anchors.fill: parent
                onClicked: {
                  searchInput.text = ""
                  root.searchQuery = ""
                }
              }
            }
          }
        }

        // Copy Notice
        Rectangle {
          visible: root.copyNotice.length > 0
          width: parent.width
          implicitHeight: Style.space(30)
          radius: Style.space(6)
          color: "#a6da95"

          Text {
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: root.copyNotice
            color: "#0d0e15"
            font.bold: true
            font.pixelSize: Style.font.caption
          }
        }

        // Device List
        Repeater {
          model: root.filteredDevices

          delegate: Rectangle {
            id: card
            width: panelCol.width
            implicitHeight: cardCol.implicitHeight + Style.space(16)
            radius: Style.space(10)
            color: modelData.is_gateway ? Qt.rgba(0, 0.9, 1, 0.08) : (modelData.is_local ? Qt.rgba(0.65, 0.85, 0.58, 0.08) : Color.m3surface)
            border.color: modelData.is_gateway ? "#00e5ff" : (modelData.is_local ? "#a6da95" : "transparent")
            border.width: 1

            Column {
              id: cardCol
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.margins: Style.space(10)
              spacing: Style.space(8)

              // Top row: Category Icon + Title + Vendor + Status
              RowLayout {
                width: parent.width
                spacing: Style.space(8)

                // Category Icon
                Rectangle {
                  width: Style.space(32)
                  height: Style.space(32)
                  radius: Style.space(16)
                  color: modelData.is_gateway ? "#00e5ff" : (modelData.is_local ? "#a6da95" : Qt.rgba(1, 1, 1, 0.1))

                  Text {
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: modelData.icon || "󰛳"
                    font.pixelSize: Style.font.subtext
                    color: (modelData.is_gateway || modelData.is_local) ? "#0d0e15" : (root.bar ? root.bar.foreground : Color.foreground)
                  }
                }

                // Name & Vendor
                Column {
                  Layout.fillWidth: true
                  spacing: Style.space(2)

                  Text {
                    textFormat: Text.PlainText
                    text: (modelData.alias && modelData.alias.length > 0) ? modelData.alias : ((modelData.hostname && modelData.hostname.length > 0) ? modelData.hostname : modelData.ip)
                    font.pixelSize: Style.font.subtext
                    font.bold: true
                    color: root.bar ? root.bar.foreground : Color.foreground
                    elide: Text.ElideRight
                  }

                  Text {
                    textFormat: Text.PlainText
                    text: modelData.vendor || "Unknown Vendor"
                    font.pixelSize: Style.font.caption
                    color: Color.muted
                    elide: Text.ElideRight
                  }
                }

                // Latency Badge or Ping Button
                Rectangle {
                  visible: modelData.latency_ms !== null && modelData.latency_ms !== undefined
                  implicitWidth: latText.implicitWidth + Style.space(12)
                  implicitHeight: Style.space(22)
                  radius: Style.space(11)
                  color: Qt.rgba(0.65, 0.85, 0.58, 0.2)

                  Text {
                    id: latText
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: (modelData.latency_ms || 0).toFixed(1) + " ms"
                    font.pixelSize: Style.font.micro
                    font.bold: true
                    color: "#a6da95"
                  }
                }

                // Status Dot
                Rectangle {
                  width: Style.space(8)
                  height: Style.space(8)
                  radius: Style.space(4)
                  color: modelData.state === "REACHABLE" ? "#a6da95" : "#f5a97f"
                }
              }

              // Bottom row: IP pill & MAC pill (Click to copy)
              RowLayout {
                width: parent.width
                spacing: Style.space(8)

                // IP Pill Button
                Rectangle {
                  Layout.fillWidth: true
                  implicitHeight: Style.space(26)
                  radius: Style.space(6)
                  color: ipMouse.containsMouse ? Qt.rgba(0, 0.9, 1, 0.2) : Qt.rgba(1, 1, 1, 0.06)

                  RowLayout {
                    anchors.centerIn: parent
                    spacing: Style.space(4)
                    Text {
                      textFormat: Text.PlainText
                      text: "IP: " + modelData.ip
                      font.pixelSize: Style.font.caption
                      font.family: root.fontFamily
                      color: root.bar ? root.bar.foreground : Color.foreground
                    }
                    Text {
                      textFormat: Text.PlainText
                      text: ""
                      font.pixelSize: Style.font.micro
                      color: Color.muted
                    }
                  }

                  MouseArea {
                    id: ipMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.copyText(modelData.ip, "IP")
                  }
                }

                // MAC Pill Button
                Rectangle {
                  Layout.fillWidth: true
                  implicitHeight: Style.space(26)
                  radius: Style.space(6)
                  color: macMouse.containsMouse ? Qt.rgba(0, 0.9, 1, 0.2) : Qt.rgba(1, 1, 1, 0.06)

                  RowLayout {
                    anchors.centerIn: parent
                    spacing: Style.space(4)
                    Text {
                      textFormat: Text.PlainText
                      text: modelData.mac
                      font.pixelSize: Style.font.micro
                      font.family: root.fontFamily
                      color: Color.muted
                    }
                    Text {
                      textFormat: Text.PlainText
                      text: ""
                      font.pixelSize: Style.font.micro
                      color: Color.muted
                    }
                  }

                  MouseArea {
                    id: macMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.copyText(modelData.mac, "MAC")
                  }
                }
              }
            }
          }
        }

        // Empty Search Results
        Item {
          visible: root.filteredDevices.length === 0
          width: parent.width
          implicitHeight: Style.space(80)

          Text {
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: root.devices.length === 0 ? "Ağ taranıyor..." : "Aramayla eşleşen cihaz bulunamadı"
            color: Color.muted
            font.pixelSize: Style.font.subtext
          }
        }
      }
    }
  }
}

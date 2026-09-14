import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "theme"

Rectangle {
    id: root
    color: Theme.bgBase

    property string iface: "wlan0"
    property string localIp: "127.0.0.1"
    property string gateway: "192.168.1.1"
    property string gatewayMac: ""
    property bool arpSpoofWarning: false
    property int subnetMask: 24
    property int deviceCount: 0
    property int scanDurationMs: 0
    property var devices: []
    property var filteredDevices: []
    property string searchQuery: ""
    property string selectedCategory: "all"
    property bool isScanning: false
    property string copyNotice: ""

    // Editing Alias state
    property string editingMac: ""
    property string editingText: ""

    // Traffic tracking
    property real rxSpeedKb: 0
    property real txSpeedKb: 0
    property real lastRxBytes: 0
    property real lastTxBytes: 0
    property real lastTrafficTime: 0

    function resolveEnginePath() {
        return "/home/ozdil/.local/bin/netradar-engine"
    }

    function scan() {
        if (scanProc.running) return
        root.isScanning = true
        scanProc.command = [root.resolveEnginePath(), "--scan"]
        scanProc.running = true
    }

    function ping(ip) {
        pingProc.command = [root.resolveEnginePath(), "--ping", ip]
        pingProc.running = true
    }

    function probe(ip) {
        probeProc.command = [root.resolveEnginePath(), "--probe", ip]
        probeProc.running = true
    }

    function toggleTrust(mac, currentTrust) {
        var flag = currentTrust ? "--untrust" : "--trust"
        trustProc.command = [root.resolveEnginePath(), flag, mac]
        trustProc.running = true
    }

    function saveAlias(mac, alias) {
        aliasProc.command = [root.resolveEnginePath(), "--set-alias", mac, alias]
        aliasProc.running = true
        root.editingMac = ""
    }

    function openWeb(ip, port) {
        var proto = (port === 443) ? "https" : "http"
        var url = proto + "://" + ip + ((port === 80 || port === 443) ? "" : (":" + port))
        actionProc.command = ["xdg-open", url]
        actionProc.running = true
        root.copyNotice = "Tarayıcıda açılıyor: " + url
        noticeTimer.restart()
    }

    function openSsh(ip) {
        actionProc.command = ["foot", "ssh", ip]
        actionProc.running = true
        root.copyNotice = "SSH Terminali Başlatıldı: " + ip
        noticeTimer.restart()
    }

    function copyText(txt, label) {
        copyProc.command = ["wl-copy", txt]
        copyProc.running = true
        root.copyNotice = label + " kopyalandı: " + txt
        noticeTimer.restart()
    }

    function filterDevices() {
        var q = root.searchQuery.trim().toLowerCase()
        var cat = root.selectedCategory
        var list = []
        for (var i = 0; i < root.devices.length; i++) {
            var d = root.devices[i]
            var matchCat = (cat === "all") || (d.category === cat)
            if (!matchCat) continue

            if (q === "") {
                list.push(d)
                continue
            }

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
    onSelectedCategoryChanged: filterDevices()

    // Subprocesses
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
                    root.gatewayMac = parsed.gateway_mac || ""
                    root.arpSpoofWarning = Boolean(parsed.arp_spoof_warning)
                    root.subnetMask = parsed.subnet_mask || 24
                    root.deviceCount = parsed.device_count || 0
                    root.scanDurationMs = parsed.scan_duration_ms || 0
                    root.devices = parsed.devices || []
                    root.filterDevices()

                    // Update traffic speeds
                    if (parsed.traffic) {
                        var now = Date.now() / 1000.0
                        if (root.lastTrafficTime > 0) {
                            var dt = now - root.lastTrafficTime
                            if (dt > 0.5) {
                                root.rxSpeedKb = Math.max(0, (parsed.traffic.rx_bytes - root.lastRxBytes) / (dt * 1024.0))
                                root.txSpeedKb = Math.max(0, (parsed.traffic.tx_bytes - root.lastTxBytes) / (dt * 1024.0))
                            }
                        }
                        root.lastRxBytes = parsed.traffic.rx_bytes
                        root.lastTxBytes = parsed.traffic.tx_bytes
                        root.lastTrafficTime = now
                    }

                    // Alert on new unknown devices
                    if (parsed.new_devices_detected > 0) {
                        notifyProc.command = [
                            "notify-send",
                            "-u", "normal",
                            "-i", "network-wired",
                            "󰈀 NetRadar: Yeni Cihaz Algılandı",
                            parsed.new_devices_detected + " yeni cihaz ağa katıldı!"
                        ]
                        notifyProc.running = true
                    }
                } catch (err) {
                    console.warn("Parse error:", err)
                }
                root.isScanning = false
            }
        }
    }

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

    Process {
        id: probeProc
        running: false
        command: []
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var raw = String(text || "").slice(0, 4096)
                if (!raw) return
                try {
                    var res = JSON.parse(raw)
                    if (res.ip && res.services) {
                        for (var i = 0; i < root.devices.length; i++) {
                            if (root.devices[i].ip === res.ip) {
                                root.devices[i].services = res.services
                                break
                            }
                        }
                        root.filterDevices()
                        root.copyNotice = res.ip + ": " + res.services.length + " servis bulundu"
                        noticeTimer.restart()
                    }
                } catch (e) {}
            }
        }
    }

    Process {
        id: trustProc
        running: false
        command: []
        onExited: root.scan()
    }

    Process {
        id: aliasProc
        running: false
        command: []
        onExited: root.scan()
    }

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

    Process {
        id: notifyProc
        running: false
        command: []
    }

    Timer {
        id: noticeTimer
        interval: 3000
        running: false
        onTriggered: root.copyNotice = ""
    }

    Component.onCompleted: scan()

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 14

        // ARP Spoofing Warning Banner (Red Alert)
        Rectangle {
            visible: root.arpSpoofWarning
            Layout.fillWidth: true
            implicitHeight: 42
            radius: Theme.radiusMd
            color: "#ed8796"

            RowLayout {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 10
                Text {
                    textFormat: Text.PlainText
                    text: " GÜVENLİK UYARISI: Ağ Geçidi (Gateway) MAC adresi değişti! Olası ARP Zehirlenmesi / Sahte Yönlendirici!"
                    font.family: Theme.fontFamily
                    font.bold: true
                    font.pixelSize: 12
                    color: "#181926"
                }
            }
        }

        // Header Bar
        RowLayout {
            Layout.fillWidth: true
            spacing: 14

            Rectangle {
                width: 44
                height: 44
                radius: 12
                color: Qt.rgba(0, 0.9, 1, 0.15)
                border.color: Theme.accent
                border.width: 1

                Text {
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: "󰈀"
                    font.pixelSize: 22
                    color: Theme.accent
                }
            }

            Column {
                Layout.fillWidth: true
                spacing: 3

                RowLayout {
                    spacing: 8
                    Text {
                        textFormat: Text.PlainText
                        text: "NetRadar"
                        font.family: Theme.fontFamily
                        font.pixelSize: 18
                        font.bold: true
                        color: Theme.textMain
                    }

                    Rectangle {
                        implicitWidth: devBadge.implicitWidth + 12
                        implicitHeight: 20
                        radius: 10
                        color: Theme.accent

                        Text {
                            id: devBadge
                            anchors.centerIn: parent
                            textFormat: Text.PlainText
                            text: root.deviceCount + " Cihaz"
                            font.pixelSize: 11
                            font.bold: true
                            color: Theme.bgDark
                        }
                    }

                    // Traffic Speed Pill
                    Rectangle {
                        implicitWidth: speedText.implicitWidth + 14
                        implicitHeight: 20
                        radius: 10
                        color: Theme.bgSurface
                        border.color: Theme.border
                        border.width: 1

                        Text {
                            id: speedText
                            anchors.centerIn: parent
                            textFormat: Text.PlainText
                            text: "↓ " + root.rxSpeedKb.toFixed(1) + " KB/s  ↑ " + root.txSpeedKb.toFixed(1) + " KB/s"
                            font.pixelSize: 10
                            font.family: Theme.monoFont
                            color: Theme.accentGreen
                        }
                    }
                }

                Text {
                    textFormat: Text.PlainText
                    text: "Arayüz: " + root.iface + " (" + root.localIp + "/" + root.subnetMask + ") • Ağ Geçidi: " + root.gateway + " • Süre: " + root.scanDurationMs + " ms"
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    color: Theme.textMuted
                }
            }

            // Refresh / Scan Button
            Button {
                id: refreshBtn
                implicitWidth: 120
                implicitHeight: 38
                onClicked: root.scan()

                background: Rectangle {
                    radius: Theme.radiusMd
                    color: refreshBtn.hovered ? Theme.accentHover : Theme.accent
                }

                contentItem: RowLayout {
                    anchors.centerIn: parent
                    spacing: 6
                    Text {
                        textFormat: Text.PlainText
                        text: ""
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        color: Theme.bgDark
                        rotation: root.isScanning ? spinAnim.angle : 0

                        NumberAnimation on rotation {
                            id: spinAnim
                            running: root.isScanning
                            loops: Animation.Infinite
                            from: 0
                            to: 360
                            duration: 1000
                            property real angle: 0
                        }
                    }
                    Text {
                        textFormat: Text.PlainText
                        text: root.isScanning ? "Taranıyor..." : "Ağı Tara"
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        font.bold: true
                        color: Theme.bgDark
                    }
                }
            }
        }

        // Search & Filter Toolbar
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            // Search Bar
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 40
                radius: Theme.radiusMd
                color: Theme.bgSurface
                border.color: searchInput.activeFocus ? Theme.accent : Theme.border
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 8

                    Text {
                        textFormat: Text.PlainText
                        text: ""
                        font.family: Theme.fontFamily
                        color: Theme.textMuted
                        font.pixelSize: 13
                    }

                    TextField {
                        id: searchInput
                        Layout.fillWidth: true
                        placeholderText: "IP, MAC, Takma Ad, Hostname veya Üretici Ara..."
                        placeholderTextColor: Theme.textDim
                        color: Theme.textMain
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        background: null
                        onTextChanged: root.searchQuery = text
                    }

                    Text {
                        visible: searchInput.text.length > 0
                        textFormat: Text.PlainText
                        text: ""
                        font.family: Theme.fontFamily
                        color: Theme.textMuted
                        font.pixelSize: 12
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                searchInput.text = ""
                                root.searchQuery = ""
                            }
                        }
                    }
                }
            }

            // Category Filter Chips
            RowLayout {
                spacing: 6

                Repeater {
                    model: [
                        { id: "all", label: "Tümü" },
                        { id: "router", label: "Yönlendirici" },
                        { id: "pc", label: "Bilgisayar" },
                        { id: "phone", label: "Telefon" },
                        { id: "iot", label: "IoT" }
                    ]

                    delegate: Rectangle {
                        implicitWidth: chipText.implicitWidth + 16
                        implicitHeight: 36
                        radius: Theme.radiusSm
                        color: root.selectedCategory === modelData.id ? Theme.accent : (chipMouse.containsMouse ? Theme.bgCardHover : Theme.bgSurface)
                        border.color: root.selectedCategory === modelData.id ? Theme.accent : Theme.border
                        border.width: 1

                        Text {
                            id: chipText
                            anchors.centerIn: parent
                            textFormat: Text.PlainText
                            text: modelData.label
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            font.bold: root.selectedCategory === modelData.id
                            color: root.selectedCategory === modelData.id ? Theme.bgDark : Theme.textMain
                        }

                        MouseArea {
                            id: chipMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.selectedCategory = modelData.id
                        }
                    }
                }
            }
        }

        // Copy Notice Banner
        Rectangle {
            visible: root.copyNotice.length > 0
            Layout.fillWidth: true
            implicitHeight: 32
            radius: Theme.radiusSm
            color: Theme.accentGreen

            Text {
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: root.copyNotice
                color: Theme.bgDark
                font.bold: true
                font.pixelSize: 12
            }
        }

        // Device Cards Scroll Area
        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
            ScrollBar.vertical.policy: ScrollBar.AsNeeded

            ListView {
                id: deviceList
                width: parent.width
                spacing: 10
                model: root.filteredDevices

                delegate: Rectangle {
                    id: cardItem
                    width: deviceList.width
                    implicitHeight: cardLayout.implicitHeight + 24
                    radius: Theme.radiusMd
                    color: modelData.is_gateway ? Qt.rgba(0, 0.9, 1, 0.06) : (modelData.is_local ? Qt.rgba(0.65, 0.85, 0.58, 0.06) : (cardHover.containsMouse ? Theme.bgCardHover : Theme.bgCard))
                    border.color: modelData.is_gateway ? Theme.accent : (modelData.is_local ? Theme.accentGreen : (modelData.is_new ? Theme.accentOrange : Theme.border))
                    border.width: 1

                    MouseArea {
                        id: cardHover
                        anchors.fill: parent
                        hoverEnabled: true
                    }

                    ColumnLayout {
                        id: cardLayout
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 10

                        // Main Info Row
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 14

                            // Category Icon Avatar
                            Rectangle {
                                width: 44
                                height: 44
                                radius: 22
                                color: modelData.is_gateway ? Theme.accent : (modelData.is_local ? Theme.accentGreen : Qt.rgba(1, 1, 1, 0.08))

                                Text {
                                    anchors.centerIn: parent
                                    textFormat: Text.PlainText
                                    text: modelData.icon || "󰛳"
                                    font.pixelSize: 20
                                    color: (modelData.is_gateway || modelData.is_local) ? Theme.bgDark : Theme.textMain
                                }
                            }

                            // Hostname, Custom Nickname, Vendor, and Badges
                            Column {
                                Layout.fillWidth: true
                                spacing: 4

                                RowLayout {
                                    spacing: 8

                                    // Display name or Inline Edit Input
                                    Item {
                                        implicitWidth: root.editingMac === modelData.mac ? 220 : nameLabel.implicitWidth
                                        implicitHeight: 24

                                        Text {
                                            id: nameLabel
                                            visible: root.editingMac !== modelData.mac
                                            textFormat: Text.PlainText
                                            text: (modelData.alias && modelData.alias.length > 0) ? modelData.alias : ((modelData.hostname && modelData.hostname.length > 0) ? modelData.hostname : modelData.ip)
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 14
                                            font.bold: true
                                            color: Theme.textMain
                                            elide: Text.ElideRight
                                        }

                                        TextField {
                                            id: editInput
                                            visible: root.editingMac === modelData.mac
                                            anchors.fill: parent
                                            text: root.editingText
                                            color: Theme.textMain
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 13
                                            background: Rectangle {
                                                color: Theme.bgSurface
                                                border.color: Theme.accent
                                                border.width: 1
                                                radius: Theme.radiusSm
                                            }
                                            onAccepted: {
                                                root.saveAlias(modelData.mac, text)
                                            }
                                        }
                                    }

                                    // Inline Edit / Save Button
                                    Text {
                                        textFormat: Text.PlainText
                                        text: root.editingMac === modelData.mac ? "" : ""
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 12
                                        color: Theme.accent
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (root.editingMac === modelData.mac) {
                                                    root.saveAlias(modelData.mac, editInput.text)
                                                } else {
                                                    root.editingMac = modelData.mac
                                                    root.editingText = modelData.alias || modelData.hostname || ""
                                                }
                                            }
                                        }
                                    }

                                    // Role Badges
                                    Rectangle {
                                        visible: modelData.is_gateway
                                        implicitWidth: gwBadge.implicitWidth + 8
                                        implicitHeight: 18
                                        radius: 4
                                        color: Theme.accent

                                        Text {
                                            id: gwBadge
                                            anchors.centerIn: parent
                                            textFormat: Text.PlainText
                                            text: "AĞ GEÇİDİ"
                                            font.pixelSize: 9
                                            font.bold: true
                                            color: Theme.bgDark
                                        }
                                    }

                                    Rectangle {
                                        visible: modelData.is_local
                                        implicitWidth: hostBadge.implicitWidth + 8
                                        implicitHeight: 18
                                        radius: 4
                                        color: Theme.accentGreen

                                        Text {
                                            id: hostBadge
                                            anchors.centerIn: parent
                                            textFormat: Text.PlainText
                                            text: "BU BİLGİSAYAR"
                                            font.pixelSize: 9
                                            font.bold: true
                                            color: Theme.bgDark
                                        }
                                    }

                                    // New / Rogue Device Alert Badge
                                    Rectangle {
                                        visible: modelData.is_new
                                        implicitWidth: newBadge.implicitWidth + 8
                                        implicitHeight: 18
                                        radius: 4
                                        color: Theme.accentOrange

                                        Text {
                                            id: newBadge
                                            anchors.centerIn: parent
                                            textFormat: Text.PlainText
                                            text: "YENİ CİHAZ"
                                            font.pixelSize: 9
                                            font.bold: true
                                            color: Theme.bgDark
                                        }
                                    }
                                }

                                Text {
                                    textFormat: Text.PlainText
                                    text: modelData.vendor || "Bilinmeyen Üretici"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                    color: Theme.textMuted
                                }
                            }

                            // Trust Shield Toggle Button
                            Rectangle {
                                implicitWidth: 32
                                implicitHeight: 32
                                radius: Theme.radiusSm
                                color: modelData.is_trusted ? Qt.rgba(0.65, 0.85, 0.58, 0.15) : Theme.bgSurface
                                border.color: modelData.is_trusted ? Theme.accentGreen : Theme.border
                                border.width: 1

                                Text {
                                    anchors.centerIn: parent
                                    textFormat: Text.PlainText
                                    text: "󰒢"
                                    font.pixelSize: 16
                                    color: modelData.is_trusted ? Theme.accentGreen : Theme.textDim
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.toggleTrust(modelData.mac, modelData.is_trusted)
                                }
                            }

                            // IP Address Button (Click to copy)
                            Rectangle {
                                implicitWidth: ipText.implicitWidth + 24
                                implicitHeight: 32
                                radius: Theme.radiusSm
                                color: ipBtnMouse.containsMouse ? Qt.rgba(0, 0.9, 1, 0.15) : Theme.bgSurface
                                border.color: Theme.border
                                border.width: 1

                                RowLayout {
                                    anchors.centerIn: parent
                                    spacing: 6
                                    Text {
                                        id: ipText
                                        textFormat: Text.PlainText
                                        text: modelData.ip
                                        font.family: Theme.monoFont
                                        font.pixelSize: 12
                                        font.bold: true
                                        color: Theme.textMain
                                    }
                                    Text {
                                        textFormat: Text.PlainText
                                        text: ""
                                        font.pixelSize: 11
                                        color: Theme.textMuted
                                    }
                                }

                                MouseArea {
                                    id: ipBtnMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.copyText(modelData.ip, "IP")
                                }
                            }

                            // MAC Address Button (Click to copy)
                            Rectangle {
                                implicitWidth: macText.implicitWidth + 20
                                implicitHeight: 32
                                radius: Theme.radiusSm
                                color: macBtnMouse.containsMouse ? Qt.rgba(0, 0.9, 1, 0.15) : Theme.bgSurface
                                border.color: Theme.border
                                border.width: 1

                                RowLayout {
                                    anchors.centerIn: parent
                                    spacing: 6
                                    Text {
                                        id: macText
                                        textFormat: Text.PlainText
                                        text: modelData.mac
                                        font.family: Theme.monoFont
                                        font.pixelSize: 11
                                        color: Theme.textMuted
                                    }
                                    Text {
                                        textFormat: Text.PlainText
                                        text: ""
                                        font.pixelSize: 10
                                        color: Theme.textMuted
                                    }
                                }

                                MouseArea {
                                    id: macBtnMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.copyText(modelData.mac, "MAC")
                                }
                            }

                            // Ping / Latency Pill
                            Rectangle {
                                implicitWidth: 70
                                implicitHeight: 32
                                radius: Theme.radiusSm
                                color: modelData.latency_ms !== null ? Qt.rgba(0.65, 0.85, 0.58, 0.15) : Theme.bgSurface
                                border.color: modelData.latency_ms !== null ? Theme.accentGreen : Theme.border
                                border.width: 1

                                Text {
                                    anchors.centerIn: parent
                                    textFormat: Text.PlainText
                                    text: modelData.latency_ms !== null && modelData.latency_ms !== undefined ? (modelData.latency_ms.toFixed(1) + " ms") : "Ping"
                                    font.pixelSize: 11
                                    font.bold: true
                                    color: modelData.latency_ms !== null ? Theme.accentGreen : Theme.textMuted
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.ping(modelData.ip)
                                }
                            }

                            // Reachability Dot
                            Rectangle {
                                width: 10
                                height: 10
                                radius: 5
                                color: modelData.state === "REACHABLE" ? Theme.accentGreen : Theme.accentOrange
                            }
                        }

                        // Services & Direct Connect Action Bar
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            // Service scan on-demand button
                            Rectangle {
                                implicitWidth: probeText.implicitWidth + 14
                                implicitHeight: 26
                                radius: Theme.radiusSm
                                color: probeMouse.containsMouse ? Theme.bgCardHover : Theme.bgSurface
                                border.color: Theme.border
                                border.width: 1

                                RowLayout {
                                    anchors.centerIn: parent
                                    spacing: 4
                                    Text {
                                        textFormat: Text.PlainText
                                        text: "󰈀"
                                        font.pixelSize: 11
                                        color: Theme.accent
                                    }
                                    Text {
                                        id: probeText
                                        textFormat: Text.PlainText
                                        text: (modelData.services && modelData.services.length > 0) ? "Servisler" : "Portları Tara"
                                        font.pixelSize: 10
                                        font.bold: true
                                        color: Theme.textMain
                                    }
                                }

                                MouseArea {
                                    id: probeMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.probe(modelData.ip)
                                }
                            }

                            // Display detected service badges
                            Repeater {
                                model: modelData.services || []
                                delegate: Rectangle {
                                    implicitWidth: sText.implicitWidth + 10
                                    implicitHeight: 24
                                    radius: 4
                                    color: Qt.rgba(0, 0.9, 1, 0.12)
                                    border.color: Theme.accent
                                    border.width: 1

                                    Text {
                                        id: sText
                                        anchors.centerIn: parent
                                        textFormat: Text.PlainText
                                        text: modelData.port + " " + modelData.name
                                        font.pixelSize: 9
                                        font.bold: true
                                        color: Theme.accent
                                    }
                                }
                            }

                            // Direct Web Access button (if HTTP/HTTPS/WebUI open)
                            Button {
                                visible: {
                                    var s = modelData.services || []
                                    for (var i = 0; i < s.length; i++) {
                                        if (s[i].port === 80 || s[i].port === 443 || s[i].port === 8080) return true
                                    }
                                    return false
                                }
                                implicitWidth: 120
                                implicitHeight: 26
                                background: Rectangle {
                                    color: Qt.rgba(0, 0.9, 1, 0.2)
                                    border.color: Theme.accent
                                    radius: Theme.radiusSm
                                }
                                contentItem: RowLayout {
                                    anchors.centerIn: parent
                                    spacing: 4
                                    Text {
                                        textFormat: Text.PlainText
                                        text: "󰖟"
                                        font.pixelSize: 11
                                        color: Theme.accent
                                    }
                                    Text {
                                        textFormat: Text.PlainText
                                        text: "Web Arayüzü"
                                        font.bold: true
                                        font.pixelSize: 10
                                        color: Theme.textMain
                                    }
                                }
                                onClicked: {
                                    var port = 80
                                    var s = modelData.services || []
                                    for (var i = 0; i < s.length; i++) {
                                        if (s[i].port === 443) { port = 443; break }
                                        if (s[i].port === 80) { port = 80; break }
                                        if (s[i].port === 8080) { port = 8080; break }
                                    }
                                    root.openWeb(modelData.ip, port)
                                }
                            }

                            // Direct SSH Access button (if port 22 open)
                            Button {
                                visible: {
                                    var s = modelData.services || []
                                    for (var i = 0; i < s.length; i++) {
                                        if (s[i].port === 22) return true
                                    }
                                    return false
                                }
                                implicitWidth: 100
                                implicitHeight: 26
                                background: Rectangle {
                                    color: Qt.rgba(0.65, 0.85, 0.58, 0.2)
                                    border.color: Theme.accentGreen
                                    radius: Theme.radiusSm
                                }
                                contentItem: RowLayout {
                                    anchors.centerIn: parent
                                    spacing: 4
                                    Text {
                                        textFormat: Text.PlainText
                                        text: "󰞷"
                                        font.pixelSize: 11
                                        color: Theme.accentGreen
                                    }
                                    Text {
                                        textFormat: Text.PlainText
                                        text: "SSH Bağlan"
                                        font.bold: true
                                        font.pixelSize: 10
                                        color: Theme.textMain
                                    }
                                }
                                onClicked: root.openSsh(modelData.ip)
                            }
                        }
                    }
                }
            }
        }

        // Footer Bar
        RowLayout {
            Layout.fillWidth: true

            Text {
                textFormat: Text.PlainText
                text: "󰄬 Omarchy Linux Güvenlik Standartları (AGENTS.md) • Beyaz Şapka Savunmacı Radar"
                font.pixelSize: 11
                color: Theme.textDim
            }

            Item { Layout.fillWidth: true }

            Text {
                textFormat: Text.PlainText
                text: "NetRadar v1.2.0 (MIT)"
                font.pixelSize: 11
                color: Theme.textDim
            }
        }
    }
}

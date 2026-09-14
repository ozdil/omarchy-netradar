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
    property int subnetMask: 24
    property int deviceCount: 0
    property int scanDurationMs: 0
    property var devices: []
    property var filteredDevices: []
    property string searchQuery: ""
    property string selectedCategory: "all"
    property bool isScanning: false
    property string copyNotice: ""

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

    // Process Engine Bindings
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
                    root.scanDurationMs = parsed.scan_duration_ms || 0
                    root.devices = parsed.devices || []
                    root.filterDevices()
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
        id: copyProc
        running: false
        command: []
    }

    Timer {
        id: noticeTimer
        interval: 2500
        running: false
        onTriggered: root.copyNotice = ""
    }

    Component.onCompleted: scan()

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 16

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
                }

                Text {
                    textFormat: Text.PlainText
                    text: "Arayüz: " + root.iface + " (" + root.localIp + "/" + root.subnetMask + ") • Ağ Geçidi: " + root.gateway + " • Tarama: " + root.scanDurationMs + " ms"
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
                        placeholderText: "IP, MAC, Hostname veya Üretici Adı ile filtrele..."
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
                    border.color: modelData.is_gateway ? Theme.accent : (modelData.is_local ? Theme.accentGreen : Theme.border)
                    border.width: 1

                    MouseArea {
                        id: cardHover
                        anchors.fill: parent
                        hoverEnabled: true
                    }

                    RowLayout {
                        id: cardLayout
                        anchors.fill: parent
                        anchors.margins: 14
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

                        // Hostname & Vendor Information
                        Column {
                            Layout.fillWidth: true
                            spacing: 4

                            RowLayout {
                                spacing: 8
                                Text {
                                    textFormat: Text.PlainText
                                    text: (modelData.alias && modelData.alias.length > 0) ? modelData.alias : ((modelData.hostname && modelData.hostname.length > 0) ? modelData.hostname : modelData.ip)
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 14
                                    font.bold: true
                                    color: Theme.textMain
                                    elide: Text.ElideRight
                                }

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
                            }

                            Text {
                                textFormat: Text.PlainText
                                text: modelData.vendor || "Bilinmeyen Üretici"
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                color: Theme.textMuted
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
                }
            }
        }

        // Footer Bar
        RowLayout {
            Layout.fillWidth: true

            Text {
                textFormat: Text.PlainText
                text: "󰄬 Omarchy Linux Güvenlik Standartları (AGENTS.md) ile güçlendirilmiştir • Sıfır Yetki Yükseltme"
                font.pixelSize: 11
                color: Theme.textDim
            }

            Item { Layout.fillWidth: true }

            Text {
                textFormat: Text.PlainText
                text: "NetRadar v1.0.0 (MIT)"
                font.pixelSize: 11
                color: Theme.textDim
            }
        }
    }
}

import QtQuick
import Quickshell
import "theme"

ShellRoot {
    id: root

    FloatingWindow {
        id: win
        title: "NetRadar - Local Network Scanner & Device Radar"
        implicitWidth: 880
        implicitHeight: 640
        color: Theme.bgBase

        MainWindow {
            anchors.fill: parent
        }
    }
}

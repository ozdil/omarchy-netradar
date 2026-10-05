import QtQuick
import Quickshell
import Quickshell.Io
import "theme"

ShellRoot {
    id: root

    FloatingWindow {
        id: win
        title: "NetRadar - Local Network Scanner & Device Radar"
        implicitWidth: 960
        implicitHeight: 680
        visible: true
        color: Theme.bgBase

        MainWindow {
            id: mainWin
            anchors.fill: parent
        }
    }

    IpcHandler {
        target: "ozdil.netradar.window"

        function toggle(): bool {
            win.visible = !win.visible;
            return win.visible;
        }

        function show(): bool {
            win.visible = true;
            return true;
        }

        function hide(): bool {
            win.visible = false;
            return false;
        }

        function refresh(): string {
            mainWin.scan();
            return "OK";
        }
    }
}

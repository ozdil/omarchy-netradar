pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    readonly property string homeDir: Quickshell.env("HOME")
    readonly property string omarchyStateDir: homeDir + "/.local/state/omarchy/current"

    property string themeName: "default"
    property bool isDarkTheme: true

    // Dynamic Palette
    property color bgDark: "#0d0e15"
    property color bgBase: "#12131c"
    property color bgSurface: "#181926"
    property color bgCard: "#1f2030"
    property color bgCardHover: "#282a3f"
    property color border: "#2e3046"
    property color borderLight: "#3f4260"

    property color textMain: "#cad3f5"
    property color textMuted: "#8087a2"
    property color textDim: "#5b6078"

    property color accent: "#00e5ff"       // Radar Neon Cyan
    property color accentHover: "#33ebff"
    property color accentGreen: "#a6da95"  // Online / Reachable
    property color accentOrange: "#f5a97f" // Stale / Delay
    property color accentRed: "#ed8796"    // Rogue / Alert
    property color accentPurple: "#c6a0f6"
    property color accentYellow: "#eed49f"

    // Typography
    readonly property string fontFamily: "JetBrainsMono Nerd Font, JetBrains Mono, monospace"
    readonly property string monoFont: "JetBrainsMono Nerd Font, JetBrains Mono, monospace"
    readonly property string iconFont: "Font Awesome 7 Free Solid, Font Awesome 7 Free, JetBrainsMono Nerd Font, monospace"

    // Spacing
    readonly property int radiusSm: 6
    readonly property int radiusMd: 10
    readonly property int radiusLg: 14

    property string lastLoadedRaw: ""

    function loadColors(raw) {
        if (!raw || raw.trim().length === 0 || raw === lastLoadedRaw) return
        lastLoadedRaw = raw

        var dict = {}
        var lines = String(raw).split("\n")
        for (var i = 0; i < lines.length; i++) {
            var line = lines[i].trim()
            if (!line || line.charAt(0) === '#') continue
            var match = line.match(/^([A-Za-z0-9_-]+)\s*=\s*["']?([^"'\r\n]+?)["']?\s*(?:#.*)?$/)
            if (match) {
                dict[match[1].toLowerCase()] = match[2].trim()
            }
        }

        var mode = dict["mode"] || "dark"
        root.isDarkTheme = (mode !== "light")

        var base = dict["background"] || dict["bg"] || (root.isDarkTheme ? "#12131c" : "#f0f2f5")
        var fg = dict["foreground"] || dict["fg"] || (root.isDarkTheme ? "#cad3f5" : "#181926")
        var acc = dict["accent"] || dict["color4"] || dict["color6"] || "#00e5ff"
        var sel = dict["selection"] || dict["selection_background"] || ""
        var mut = dict["muted"] || dict["color8"] || ""

        root.bgBase = base

        if (root.isDarkTheme) {
            root.bgDark = dict["dark_background"] || Qt.darker(base, 1.3)
            root.bgSurface = dict["lighter_background"] || (sel ? sel : Qt.lighter(base, 1.35))
            root.bgCard = (sel && sel !== base) ? sel : Qt.lighter(base, 1.6)
            root.bgCardHover = Qt.lighter(root.bgCard, 1.2)
            root.border = mut ? mut : Qt.rgba(fg.r, fg.g, fg.b, 0.18)
            root.borderLight = Qt.rgba(acc.r, acc.g, acc.b, 0.4)
            root.textMain = dict["bright_foreground"] || fg
            root.textMuted = dict["light_foreground"] || mut || Qt.rgba(fg.r, fg.g, fg.b, 0.7)
            root.textDim = dict["dark_foreground"] || dict["color8"] || Qt.rgba(fg.r, fg.g, fg.b, 0.45)
        } else {
            root.bgDark = Qt.darker(base, 1.08)
            root.bgSurface = Qt.lighter(base, 1.03)
            root.bgCard = Qt.darker(base, 1.05)
            root.bgCardHover = Qt.darker(root.bgCard, 1.06)
            root.border = mut ? mut : Qt.rgba(fg.r, fg.g, fg.b, 0.18)
            root.borderLight = Qt.rgba(acc.r, acc.g, acc.b, 0.4)
            root.textMain = dict["bright_foreground"] || fg
            root.textMuted = dict["light_foreground"] || mut || Qt.rgba(fg.r, fg.g, fg.b, 0.7)
            root.textDim = Qt.rgba(fg.r, fg.g, fg.b, 0.45)
        }

        root.accent = acc
        root.accentHover = Qt.lighter(acc, 1.15)
        root.accentGreen = dict["bright_green"] || dict["green"] || "#a6da95"
        root.accentOrange = dict["orange"] || "#f5a97f"
        root.accentRed = dict["red"] || "#ed8796"
        root.accentPurple = dict["purple"] || "#c6a0f6"
        root.accentYellow = dict["yellow"] || "#eed49f"
    }

    property FileView colorsFile: FileView {
        id: colorsFile
        path: root.omarchyStateDir + "/theme/colors.toml"
        watchChanges: true
        printErrors: false
        onLoaded: root.loadColors(text())
        onFileChanged: reload()
    }

    property FileView themeNameFile: FileView {
        id: themeNameFile
        path: root.omarchyStateDir + "/theme.name"
        watchChanges: true
        printErrors: false
        onLoaded: {
            var n = text().trim()
            if (n.length > 0 && n !== root.themeName) {
                root.themeName = n
                root.lastLoadedRaw = ""
                colorsFile.reload()
            }
        }
        onFileChanged: {
            reload()
            root.lastLoadedRaw = ""
            colorsFile.reload()
        }
    }
}

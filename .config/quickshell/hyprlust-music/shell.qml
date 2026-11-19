// Hyprlust music popup — a Quickshell panel in the rice's own visual language.
//
// Sharp corners, a 2px border in the wallpaper accent, translucent background,
// Iosevka/JetBrains Nerd Font, flat elements. Not Material You: no 28px pills,
// no elevation shadows, no filled tonal surfaces.
//
// Toggled with `qs ipc call music toggle` (SUPER+SHIFT+I).
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Wayland
import QtQuick

ShellRoot {
    id: root

    // ---------------------------------------------------------------- palette
    // wallust writes these into shell-colors.json on every wallpaper change.
    // The values below are Hyprlust's shipped defaults so the panel still looks
    // right before wallust has ever run.
    property var pal: ({
        background: "#131318",
        foreground: "#e4e1e9",
        accent:     "#9ec9bd",
        muted:      "#7a7a8c",
        chip:       "#1e1e26"
    })

    FileView {
        id: palFile
        path: Quickshell.env("HOME") + "/.cache/hyprlust/colors.json"
        watchChanges: true
        onFileChanged: reloadPalette()
    }

    function reloadPalette() {
        try {
            const text = palFile.text()
            if (!text) return
            const j = JSON.parse(text)
            if (j && j.accent) root.pal = j
        } catch (e) { /* keep whatever we already have */ }
    }

    Component.onCompleted: reloadPalette()

    IpcHandler {
        target: "music"
        function toggle(): void { root.toggle() }
        function open(): void { root.open() }
        function close(): void { root.close() }
        function reload(): void { root.reloadPalette() }
    }

    readonly property color cBg:     pal.background
    readonly property color cFg:     pal.foreground
    readonly property color cAccent: pal.accent
    readonly property color cMuted:  pal.muted
    readonly property color cChip:   pal.chip

    // ------------------------------------------------------------- the player
    // One source of truth for "what is playing": the first MPRIS player that is
    // actually playing, else the first one that exists.
    readonly property var player: {
        const list = Mpris.players.values
        for (let i = 0; i < list.length; i++)
            if (list[i].isPlaying) return list[i]
        return list.length > 0 ? list[0] : null
    }

    readonly property bool hasPlayer: player !== null
    readonly property bool playing:   player ? player.isPlaying : false
    readonly property string title:   player ? (player.trackTitle || "Unknown") : ""
    readonly property string artist:  player ? (player.trackArtist || "") : ""
    readonly property string album:   player ? (player.trackAlbum || "") : ""
    readonly property string art:     player && player.trackArtUrl ? player.trackArtUrl : ""
    readonly property real  length:   player && player.length > 0 ? player.length : 0

    property real pos: 0
    readonly property real frac: length > 0 ? Math.max(0, Math.min(1, pos / length)) : 0

    onPlayerChanged: pos = player ? player.position : 0

    // MPRIS only pushes position changes occasionally, so poll while it plays.
    Timer {
        interval: 1000
        repeat: true
        triggeredOnStart: true
        running: root.panelOpen && root.playing
        onTriggered: {
            if (root.player) {
                root.player.positionChanged()
                root.pos = root.player.position
            }
        }
    }

    // ---------------------------------------------------------------- lyrics
    // LRCLIB is free and keyless. Synced lines when they exist, plain text when
    // they don't, and a quiet "no lyrics" note otherwise.
    property var    lines: []       // [[timeSeconds, text], ...]
    property string plain: ""
    property bool   loading: false
    property string songKey: ""

    readonly property string want: hasPlayer ? artist + "|" + title : ""
    onWantChanged: lyricsTimer.restart()

    Timer {
        id: lyricsTimer
        interval: 450
        onTriggered: root.fetchLyrics()
    }

    function fetchLyrics() {
        if (want === "" || want === songKey) return
        songKey = want
        lines = []
        plain = ""
        loading = true
        lyricProc.command = [
            Quickshell.env("HOME") + "/.local/bin/hyprlust-lyrics",
            artist, title, album, String(Math.round(length))
        ]
        lyricProc.running = true
    }

    Process {
        id: lyricProc
        stdout: StdioCollector {
            onStreamFinished: {
                root.loading = false
                try {
                    const j = JSON.parse(text)
                    root.lines = j.synced || []
                    root.plain = j.plain || ""
                } catch (e) {
                    root.lines = []
                    root.plain = ""
                }
            }
        }
    }

    readonly property int curLine: {
        const l = lines
        const t = pos + 0.25
        let k = -1
        for (let i = 0; i < l.length; i++) {
            if (l[i][0] <= t) k = i
            else break
        }
        return k
    }

    // ------------------------------------------------------------- visibility
    property bool panelOpen: false

    function open()  { panelOpen = true }
    function close() { panelOpen = false }
    function toggle() { panelOpen = !panelOpen }

    // ----------------------------------------------------------------- window
    LazyLoader {
        active: true

        PanelWindow {
            id: win
            visible: root.panelOpen

            // Open on the monitor you are looking at, not whichever one
            // Quickshell happened to attach to first. Hyprland and Quickshell
            // name monitors identically, so match on that.
            screen: {
                const mon = Hyprland.focusedMonitor
                if (!mon) return null
                const list = Quickshell.screens
                for (let i = 0; i < list.length; i++)
                    if (list[i].name === mon.name) return list[i]
                return null
            }

            // Full-screen transparent layer; the card inside is what you see, so
            // clicking the dimmed area can close the panel.
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "hyprlust-music"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            color: "transparent"

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            // Escape closes it, like every other popup in the rice.
            Item {
                anchors.fill: parent
                focus: root.panelOpen

                Keys.onEscapePressed: root.close()

                Rectangle {
                    anchors.fill: parent
                    color: Qt.rgba(0, 0, 0, 0.35)
                    opacity: root.panelOpen ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 160 } }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.close()
                    }
                }

                // ------------------------------------------------------ the card
                Rectangle {
                    id: card
                    width: 400
                    implicitHeight: body.implicitHeight + 40

                    anchors.centerIn: parent
                    radius: 6
                    color: Qt.rgba(root.cBg.r, root.cBg.g, root.cBg.b, 0.92)
                    border.width: 2
                    border.color: Qt.rgba(root.cAccent.r, root.cAccent.g, root.cAccent.b, 0.2)

                    // Slide + fade in, cheap and short — matches the 200ms the
                    // rest of the rice uses.
                    opacity: root.panelOpen ? 1 : 0
                    scale: root.panelOpen ? 1 : 0.97
                    Behavior on opacity { NumberAnimation { duration: 160 } }
                    Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

                    MouseArea { anchors.fill: parent }   // swallow clicks

                    Column {
                        id: body
                        anchors {
                            top: parent.top
                            left: parent.left
                            right: parent.right
                            margins: 20
                        }
                        spacing: 16

                        // ---------------------------------------------- header
                        Item {
                            width: parent.width
                            height: 104

                            // Cover art, sharp 6px corners like the rest of the rice.
                            Rectangle {
                                id: artFrame
                                width: 104
                                height: 104
                                radius: 6
                                color: root.cChip
                                clip: true

                                Image {
                                    id: cover
                                    anchors.fill: parent
                                    source: root.art
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    visible: root.art !== "" && status === Image.Ready
                                }

                                // Placeholder note when the player has no art.
                                Text {
                                    anchors.centerIn: parent
                                    visible: root.art === "" || cover.status !== Image.Ready
                                    text: ""
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 34
                                    color: root.cMuted
                                }
                            }

                            Column {
                                anchors.left: artFrame.right
                                anchors.leftMargin: 16
                                anchors.right: parent.right
                                anchors.verticalCenter: artFrame.verticalCenter
                                spacing: 6

                                // "Now playing" style label, upper case with the
                                // letter spacing the rice uses for group headers.
                                Text {
                                    text: root.hasPlayer ? "NOW PLAYING" : "NOTHING PLAYING"
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 10
                                    font.bold: true
                                    font.letterSpacing: 1.6
                                    color: root.cAccent
                                }

                                Text {
                                    width: parent.width
                                    text: root.hasPlayer ? root.title : "Start something in Spotify, Helium or mpv"
                                    color: root.cFg
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 17
                                    font.bold: true
                                    elide: Text.ElideRight
                                    maximumLineCount: 2
                                    wrapMode: Text.WordWrap
                                    lineHeight: 0.95
                                }

                                Text {
                                    width: parent.width
                                    text: root.hasPlayer
                                        ? root.artist + (root.album !== "" ? "  ·  " + root.album : "")
                                        : ""
                                    color: root.cMuted
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 12
                                    elide: Text.ElideRight
                                }
                            }
                        }

                        // ---------------------------------------------- lyrics
                        Rectangle {
                            width: parent.width
                            height: 108
                            radius: 6
                            color: root.cChip
                            clip: true
                            visible: root.hasPlayer

                            ListView {
                                id: lyricView
                                anchors.fill: parent
                                anchors.margins: 8
                                visible: root.lines.length > 0
                                model: root.lines
                                interactive: false
                                currentIndex: Math.max(0, root.curLine)
                                highlightRangeMode: ListView.StrictlyEnforceRange
                                preferredHighlightBegin: height / 2 - 12
                                preferredHighlightEnd: height / 2 + 12
                                highlightMoveDuration: 320

                                delegate: Text {
                                    required property var modelData
                                    required property int index

                                    width: lyricView.width
                                    horizontalAlignment: Text.AlignHCenter
                                    wrapMode: Text.WordWrap
                                    text: modelData[1] === "" ? "♪" : modelData[1]

                                    readonly property bool now: index === root.curLine

                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: now ? 14 : 11
                                    font.bold: now
                                    color: now ? root.cAccent : root.cFg
                                    opacity: now ? 1 : Math.max(0.18, 0.55 - Math.abs(index - root.curLine) * 0.18)

                                    Behavior on opacity { NumberAnimation { duration: 220 } }
                                    Behavior on font.pixelSize { NumberAnimation { duration: 220 } }
                                }
                            }

                            // Plain lyrics fall back to a still block.
                            Flickable {
                                anchors.fill: parent
                                anchors.margins: 12
                                visible: root.lines.length === 0 && root.plain !== ""
                                contentHeight: plainText.implicitHeight
                                clip: true
                                interactive: false

                                Text {
                                    id: plainText
                                    width: parent.width
                                    horizontalAlignment: Text.AlignHCenter
                                    wrapMode: Text.WordWrap
                                    text: root.plain
                                    color: root.cMuted
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 11
                                    lineHeight: 1.35
                                }
                            }

                            Text {
                                anchors.centerIn: parent
                                visible: root.lines.length === 0 && root.plain === ""
                                text: root.loading ? "looking for lyrics…" : "no lyrics for this one"
                                color: root.cMuted
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 11
                            }
                        }

                        // --------------------------------------------- progress
                        Item {
                            width: parent.width
                            height: 16
                            visible: root.hasPlayer

                            Text {
                                id: tElapsed
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.clock(root.pos)
                                color: root.cMuted
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 10
                            }

                            Text {
                                id: tTotal
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.clock(root.length)
                                color: root.cMuted
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 10
                            }

                            // Flat track with a 2px fill — no rounded pill, no glow.
                            Item {
                                id: track
                                anchors.left: tElapsed.right
                                anchors.leftMargin: 10
                                anchors.right: tTotal.left
                                anchors.rightMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                height: 12

                                readonly property bool hovered: trackArea.containsMouse

                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width
                                    height: 3
                                    radius: 1
                                    color: Qt.rgba(root.cAccent.r, root.cAccent.g, root.cAccent.b, 0.18)
                                }

                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: Math.max(0, parent.width * root.frac)
                                    height: 3
                                    radius: 1
                                    color: root.cAccent
                                }

                                MouseArea {
                                    id: trackArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: function(mouse) {
                                        if (root.length > 0)
                                            root.seekTo(mouse.x / width)
                                    }
                                }
                            }
                        }

                        // ---------------------------------------------- buttons
                        Row {
                            id: buttons
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: 10
                            visible: root.hasPlayer

                            // Flat square buttons with a 6px radius, matching the
                            // control-center widgets, not round Material pills.
                            component Btn: Rectangle {
                                id: btn
                                property string glyph: ""
                                property bool primary: false
                                signal hit()

                                width: primary ? 52 : 40
                                height: 36
                                radius: 6

                                readonly property bool hovered: btnArea.containsMouse

                                color: primary
                                    ? (hovered ? Qt.rgba(root.cAccent.r, root.cAccent.g, root.cAccent.b, 0.85)
                                               : root.cAccent)
                                    : (hovered ? Qt.rgba(root.cAccent.r, root.cAccent.g, root.cAccent.b, 0.22)
                                               : Qt.rgba(root.cAccent.r, root.cAccent.g, root.cAccent.b, 0.08))

                                Behavior on color { ColorAnimation { duration: 120 } }

                                Text {
                                    anchors.centerIn: parent
                                    text: btn.glyph
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: btn.primary ? 18 : 16
                                    color: btn.primary
                                        ? root.cBg
                                        : (btn.hovered ? root.cFg : root.cMuted)
                                }

                                MouseArea {
                                    id: btnArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: btn.hit()
                                }
                            }

                            Btn {
                                glyph: "󰒮"
                                onHit: root.prev()
                            }

                            Btn {
                                primary: true
                                glyph: root.playing ? "󰏤" : "󰐊"
                                onHit: root.togglePlaying()
                            }

                            Btn {
                                glyph: "󰒭"
                                onHit: root.next()
                            }
                        }
                    }
                }
            }
        }
    }

    // ------------------------------------------------------------- transport
    function togglePlaying() {
        if (player && player.canTogglePlaying) player.togglePlaying()
    }
    function next() {
        if (player && player.canGoNext) player.next()
    }
    function prev() {
        if (player && player.canGoPrevious) player.previous()
    }
    function seekTo(f) {
        if (player && player.canSeek && length > 0) {
            player.position = f * length
            pos = player.position
        }
    }
    function clock(sec) {
        const v = Math.max(0, Math.floor(sec))
        const m = Math.floor(v / 60)
        const s = v % 60
        return m + ":" + (s < 10 ? "0" + s : s)
    }
}

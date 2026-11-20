// Hyprlust music dock — a Quickshell panel that hangs off the bar.
//
// It is not a floating popup: the card is a layer-shell surface anchored to the
// top-right of the focused monitor, right under the waybar bar, so it reads as
// part of the bar rather than a window in the middle of the screen.
//
// Visual language matches the DarkShadow-style reference card:
//   • dark translucent card, radius 20, no visible border
//   • seal/scallop-shaped cover frame with a dark halo
//   • grey pill chip ("Youtube Music")
//   • bold title + "artist · album"
//   • rounded lyrics box with the current line bold and pinned at the top
//   • squiggle progress bar (played part wavy, rest a plain track)
//   • five round pill buttons with a wide light primary (pause/play)
//   • thin scrollbar under the buttons
//
// Opens/closes with `qs ipc call music toggle` (SUPER+SHIFT+I, or the bar icon),
// Escape, or a click anywhere outside the card. No dimmed backdrop.
//
// Toggled with `qs ipc call music toggle` (SUPER+SHIFT+I, or a click on the
// bar's mpris module).
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import Quickshell.Wayland
import QtQuick

ShellRoot {
    id: root

    // ---------------------------------------------------------------- palette
    // wallust writes these into ~/.cache/hyprlust/colors.json on every
    // wallpaper change. The values below are Hyprlust's shipped defaults so the
    // panel still looks right before wallust has ever run.
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
        onLoaded: reloadPalette()
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
        function open(): void  { root.open() }
        function close(): void { root.close() }
        function reload(): void { root.reloadPalette() }
    }

    readonly property color cBg:     pal.background
    readonly property color cFg:     pal.foreground
    readonly property color cAccent: pal.accent
    readonly property color cMuted:  pal.muted
    readonly property color cChip:   pal.chip

    // Where the bar sits. These mirror ~/.config/waybar/configs/[TOP] wallust_new;
    // change them if you resize the bar and the dock keeps hanging off its right
    // edge instead of drifting to the corner of the screen.
    readonly property int barWidth:     1200   // 0 = the bar spans the screen
    readonly property int barHeight:    34
    readonly property int barTopMargin: 5
    readonly property int barGap:       7      // space between bar and card

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

    // limusic is a YouTube Music client and reports itself as "Limusic"; show
    // the service people actually recognise.
    readonly property string source: {
        if (!player) return ""
        const n = player.identity || "Music"
        return n === "Limusic" ? "YouTube Music" : n
    }

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

    // -------------------------------------------------------------- the volume
    // Pipewire takes a moment to become ready; the bindings re-evaluate when it
    // does, so the volume row appears a second after login.
    readonly property var sink: Pipewire.ready ? Pipewire.defaultAudioSink : null
    readonly property bool hasSink: sink !== null && sink.audio !== undefined
    readonly property real volume: hasSink && sink.audio ? sink.audio.volume : 0
    readonly property bool muted:  hasSink && sink.audio ? sink.audio.muted : false

    function setVolume(v) {
        if (!hasSink) return
        sink.audio.muted = false
        sink.audio.volume = Math.max(0, Math.min(1, v))
    }
    function nudgeVolume(d) { setVolume(volume + d) }

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
    // Kept on screen for the length of the closing animation, then removed so
    // the surface cannot sit there invisibly.
    property bool shown: false
    // The outside-click catcher is only active while the panel is open.
    property bool catcherActive: false

    function open()  { panelOpen = true; shown = true; catcherActive = true }
    function close() { panelOpen = false; catcherActive = false; hideTimer.restart() }
    function toggle() { panelOpen ? close() : open() }

    Timer {
        id: hideTimer
        interval: 180
        onTriggered: if (!root.panelOpen) root.shown = false
    }

    // ------------------------------------------------------------- window
    // A layer-shell surface the size of the card, anchored to the top-right.
    PanelWindow {
        id: win
        visible: root.shown

        // Hang off the monitor you are looking at, not whichever one
        // Quickshell happened to attach to first. Hyprland and Quickshell name
        // monitors identically, so match on that.
        screen: {
            const mon = Hyprland.focusedMonitor
            if (!mon) return null
            const list = Quickshell.screens
            for (let i = 0; i < list.length; i++)
                if (list[i].name === mon.name) return list[i]
            return null
        }

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "hyprlust-music"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        WlrLayershell.exclusionMode: ExclusionMode.Ignore
        color: "transparent"

        implicitWidth: card.width
        implicitHeight: card.height

        anchors.top: true
        anchors.right: true

        // Right edge of the bar. The bar is fixed-center with width barWidth,
        // so its right edge sits (screen.width − barWidth)/2 from the right.
        margins.right: root.barWidth > 0 && win.screen
            ? Math.round((win.screen.width - root.barWidth) / 2) + 8
            : 8
        margins.top: root.barTopMargin + root.barHeight + root.barGap

        // Escape closes it, like every other dropdown in the rice.
        Item {
            anchors.fill: parent
            focus: root.panelOpen
            Keys.onEscapePressed: root.close()

            // Catches clicks outside the card to close the panel
            // (outside-click close). Sits behind the card so card clicks
            // never reach it.
            Rectangle {
                id: catcher
                visible: root.catcherActive
                color: "transparent"
                anchors.fill: parent
                MouseArea {
                    anchors.fill: parent
                    enabled: root.catcherActive
                    onClicked: root.close()
                }
            }

            // ------------------------------------------------------ the card
            Rectangle {
                id: card
                width: 384
                implicitHeight: body.implicitHeight + 40

                radius: 20
                color: Qt.rgba(root.cBg.r, root.cBg.g, root.cBg.b, 0.92)
                border.width: 0

                // Drops out of the bar: slides down 10px and fades.
                opacity: root.panelOpen ? 1 : 0
                y: root.panelOpen ? 0 : -10
                Behavior on opacity { NumberAnimation { duration: 180 } }
                Behavior on y { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                Column {
                    id: body
                    anchors { top: parent.top; left: parent.left; right: parent.right; margins: 20 }
                    spacing: 16

                    // ---------------------------------------------- header
                    Item {
                        width: parent.width
                        height: 104

                        // Seal / scalloped cover frame with cover art inside.
                        Item {
                            id: coverWrap
                            width: 104
                            height: 104

                            // Dark scalloped halo behind the cover.
                            Canvas {
                                id: sealHalo
                                anchors.fill: parent
                                renderStrategy: Canvas.Cooperative
                                onPaint: {
                                    const c = getContext("2d")
                                    c.reset()
                                    const w = width, h = height
                                    const cx = w / 2, cy = h / 2
                                    const r = 42
                                    const petals = 12
                                    c.fillStyle = "#0f0f14"
                                    c.beginPath()
                                    for (let i = 0; i < petals; i++) {
                                        const a = (i / petals) * Math.PI * 2
                                        const rx = cx + Math.cos(a) * r
                                        const ry = cy + Math.sin(a) * r
                                        if (i === 0) c.moveTo(rx, ry)
                                        else c.lineTo(rx, ry)
                                        // scallop bulge
                                        const ba = a + Math.PI / petals
                                        c.quadraticCurveTo(cx + Math.cos(ba) * (r + 10),
                                                            cy + Math.sin(ba) * (r + 10),
                                                            cx + Math.cos(a + Math.PI * 2 / petals) * r,
                                                            cy + Math.sin(a + Math.PI * 2 / petals) * r)
                                    }
                                    c.closePath()
                                    c.fill()
                                }
                                onWidthChanged: requestPaint()
                                onHeightChanged: requestPaint()
                            }

                            // Cover art, slight round corners.
                            Rectangle {
                                id: artFrame
                                anchors.centerIn: parent
                                width: 92
                                height: 92
                                radius: 10
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
                                Text {
                                    anchors.centerIn: parent
                                    visible: root.art === "" || cover.status !== Image.Ready
                                    text: "\uf001"
                                    font.family: "Symbols Nerd Font"
                                    font.pixelSize: 30
                                    color: root.cMuted
                                }
                            }
                        }

                        Column {
                            anchors.top: coverWrap.top
                            anchors.left: coverWrap.right
                            anchors.leftMargin: 14
                            anchors.right: parent.right
                            spacing: 5

                            // Player chip — grey pill with a bar-chart icon.
                            Row {
                                visible: root.hasPlayer
                                height: 24
                                spacing: 7

                                Rectangle {
                                    width: 14
                                    height: 14
                                    radius: 7
                                    color: root.cAccent

                                    Text {
                                        anchors.centerIn: parent
                                        text: "\uf075a"   // md-music
                                        font.family: "Symbols Nerd Font"
                                        font.pixelSize: 10
                                        color: root.cBg
                                    }
                                }
                                Text {
                                    text: root.source
                                    color: root.cFg
                                    font.family: "Inter"
                                    font.pixelSize: 11
                                    font.bold: true
                                    verticalAlignment: Text.AlignVCenter
                                }
                            }

                            Text {
                                width: parent.width
                                text: root.hasPlayer ? root.title : "Nothing playing"
                                color: root.cFg
                                font.family: "Inter"
                                font.pixelSize: 20
                                font.bold: true
                                elide: Text.ElideRight
                                wrapMode: Text.NoWrap
                                lineHeight: 1.05
                            }

                            Text {
                                width: parent.width
                                text: root.hasPlayer ? (root.artist + (root.album ? " · " + root.album : "")) : "Start something in Spotify or YouTube Music"
                                color: root.cMuted
                                font.family: "Inter"
                                font.pixelSize: 12
                                elide: Text.ElideRight
                                wrapMode: Text.NoWrap
                                lineHeight: 1.1
                            }
                        }
                    }

                    // ---------------------------------------------- lyrics
                    Rectangle {
                        id: lyricBox
                        width: parent.width
                        height: 108
                        radius: 12
                        color: root.cChip
                        clip: true
                        visible: root.hasPlayer

                        ListView {
                            id: lyricView
                            anchors.fill: parent
                            anchors.margins: 10
                            visible: root.lines.length > 0
                            model: root.lines
                            interactive: false
                            currentIndex: Math.max(0, root.curLine)
                            highlightRangeMode: ListView.StrictlyEnforceRange
                            preferredHighlightBegin: height / 2 - 14
                            preferredHighlightEnd: height / 2 + 14
                            highlightMoveDuration: 300
                            spacing: 2

                            delegate: Text {
                                required property var modelData
                                required property int index

                                width: lyricView.width
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.WordWrap
                                text: modelData[1] === "" ? "♪" : modelData[1]

                                readonly property bool now: index === root.curLine

                                font.family: "Inter"
                                font.pixelSize: now ? 14.5 : 11.5
                                font.bold: now
                                color: now ? root.cAccent : root.cFg
                                opacity: now ? 1 : Math.max(0.18, 0.6 - Math.abs(index - root.curLine) * 0.16)

                                Behavior on opacity { NumberAnimation { duration: 200 } }
                                Behavior on font.pixelSize { NumberAnimation { duration: 200 } }
                            }
                        }

                        // Plain lyrics fall back to a still block that scrolls
                        // itself with the song.
                        Flickable {
                            anchors.fill: parent
                            anchors.margins: 12
                            visible: root.lines.length === 0 && root.plain !== ""
                            contentHeight: plainText.implicitHeight
                            contentY: Math.max(0, (plainText.implicitHeight - height) * root.frac)
                            clip: true
                            interactive: false

                            Text {
                                id: plainText
                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.WordWrap
                                text: root.plain
                                color: root.cMuted
                                font.family: "Inter"
                                font.pixelSize: 12
                                lineHeight: 1.4
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: root.lines.length === 0 && root.plain === ""
                            text: root.loading ? "looking for lyrics…" : "no lyrics for this one"
                            color: root.cMuted
                            font.family: "Inter"
                            font.pixelSize: 12
                        }

                        // Fade edges so lines don't get cut by the frame.
                        Rectangle {
                            anchors.top: parent.top
                            width: parent.width
                            height: 24
                            gradient: Gradient {
                                GradientStop { position: 0; color: root.cChip }
                                GradientStop { position: 1; color: Qt.rgba(root.cChip.r, root.cChip.g, root.cChip.b, 0) }
                            }
                        }
                        Rectangle {
                            anchors.bottom: parent.bottom
                            width: parent.width
                            height: 24
                            gradient: Gradient {
                                GradientStop { position: 0; color: Qt.rgba(root.cChip.r, root.cChip.g, root.cChip.b, 0) }
                                GradientStop { position: 1; color: root.cChip }
                            }
                        }
                    }

                    // -------------------------------------------- progress
                    Item {
                        width: parent.width
                        height: 22
                        visible: root.hasPlayer

                        Text {
                            id: tElapsed
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.clock(root.pos)
                            color: root.cMuted
                            font.family: "Inter"
                            font.pixelSize: 11
                        }
                        Text {
                            id: tTotal
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.clock(root.length)
                            color: root.cMuted
                            font.family: "Inter"
                            font.pixelSize: 11
                        }

                        SeekBar {
                            anchors.left: tElapsed.right
                            anchors.leftMargin: 10
                            anchors.right: tTotal.left
                            anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            height: 22
                            frac: root.frac
                            moving: root.panelOpen && root.playing
                            onSeeked: function(f) { root.seekTo(f) }
                        }
                    }

                    // --------------------------------------------- buttons
                    Row {
                        id: buttons
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 10
                        visible: root.hasPlayer

                        // Round pill buttons; primary is wide and light.
                        component Btn: Rectangle {
                            id: btn
                            property string glyph: ""
                            property bool primary: false
                            property bool small: false
                            signal hit()

                            width: primary ? 200 : (small ? 48 : 52)
                            height: 46
                            radius: 23

                            readonly property bool hovered: btnArea.containsMouse

                            color: primary
                                ? (hovered ? Qt.rgba(0.88, 0.88, 0.9, 0.95)
                                           : Qt.rgba(0.82, 0.82, 0.86, 0.95))
                                : (hovered ? Qt.rgba(root.cAccent.r, root.cAccent.g, root.cAccent.b, 0.16)
                                           : Qt.rgba(root.cAccent.r, root.cAccent.g, root.cAccent.b, 0.09))

                            Behavior on color { ColorAnimation { duration: 130 } }

                            Text {
                                anchors.centerIn: parent
                                text: btn.glyph
                                font.family: "Symbols Nerd Font"
                                font.pixelSize: btn.primary ? 20 : 14
                                color: btn.primary
                                    ? "#1a1a1e"
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
                            glyph: "\uf075e"          // volume down
                            small: true
                            onHit: root.nudgeVolume(-0.05)
                        }
                        Btn {
                            glyph: "\uf04ae"          // previous
                            onHit: root.prev()
                        }
                        Btn {
                            primary: true
                            glyph: root.playing ? "\uf03e4" : "\uf040a"   // pause / play
                            onHit: root.togglePlaying()
                        }
                        Btn {
                            glyph: "\uf04ad"          // next
                            onHit: root.next()
                        }
                        Btn {
                            glyph: "\uf057e"          // volume up
                            small: true
                            onHit: root.nudgeVolume(0.05)
                        }
                    }

                    // Thin volume line under the buttons.
                    Item {
                        width: parent.width
                        height: 10
                        visible: root.hasSink

                        Rectangle {
                            anchors.centerIn: parent
                            width: 150
                            height: 3
                            radius: 1
                            color: Qt.rgba(root.cAccent.r, root.cAccent.g, root.cAccent.b, 0.18)

                            Rectangle {
                                width: Math.max(2, parent.width * (root.muted ? 0 : root.volume))
                                height: 3
                                radius: 1
                                color: root.muted ? root.cMuted : root.cAccent

                                Behavior on width { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                            }

                            MouseArea {
                                anchors.fill: parent
                                anchors.topMargin: -6
                                anchors.bottomMargin: -6
                                cursorShape: Qt.PointingHandCursor
                                onClicked: function(mouse) { root.setVolume(mouse.x / width) }
                            }
                        }
                    }
                }
            }
        }
    }

    // A wavy seek line: the part already played is a slow wave while the song
    // plays (it settles at the ends), the rest is a calm track with a tick at
    // the end, and the playhead is a short upright bar. Click or drag to seek.
    component SeekBar: Item {
        id: bar
        property real frac: 0
        property bool moving: false
        signal seeked(real f)

        property real phase: 0
        property real dragging: -1
        readonly property real shown: dragging >= 0 ? dragging : frac

        NumberAnimation on phase {
            from: 0
            to: Math.PI * 2
            duration: 2400
            loops: Animation.Infinite
            running: bar.moving && bar.dragging < 0
        }

        onPhaseChanged: canvas.requestPaint()
        onShownChanged: canvas.requestPaint()
        onWidthChanged: canvas.requestPaint()
        onHeightChanged: canvas.requestPaint()

        Canvas {
            id: canvas
            anchors.fill: parent
            renderStrategy: Canvas.Cooperative
            onPaint: {
                const c = getContext("2d")
                c.reset()

                const w = width
                const mid = height / 2
                const accent = root.cAccent
                const f = Math.max(0, Math.min(1, bar.shown))
                const head = Math.max(2, (w - 4) * f) + 2
                const gap = 7

                c.lineCap = "round"

                // the rest of the song
                if (head + gap + 4 < w - 2) {
                    c.strokeStyle = Qt.rgba(accent.r, accent.g, accent.b, 0.18)
                    c.lineWidth = 3
                    c.beginPath()
                    c.moveTo(head + gap, mid)
                    c.lineTo(w - 3, mid)
                    c.stroke()

                    c.fillStyle = Qt.rgba(accent.r, accent.g, accent.b, 0.55)
                    c.beginPath()
                    c.arc(w - 2, mid, 1.5, 0, Math.PI * 2)
                    c.fill()
                }

                // the part already played — squiggle / wave
                const amp = 2.6 * Math.sin(Math.PI * f)
                c.strokeStyle = accent
                c.lineWidth = 3
                c.beginPath()
                for (let x = 2; x <= head - gap; x += 2) {
                    const y = mid + amp * Math.sin(x / 16 * Math.PI * 2 - bar.phase)
                    if (x === 2) c.moveTo(x, y)
                    else c.lineTo(x, y)
                }
                c.stroke()

                // the playhead
                c.lineWidth = 3
                c.beginPath()
                c.moveTo(head, mid - 7)
                c.lineTo(head, mid + 7)
                c.stroke()
            }
        }

        MouseArea {
            anchors.fill: parent
            anchors.topMargin: -6
            anchors.bottomMargin: -6
            cursorShape: Qt.PointingHandCursor

            function at(x) { return Math.max(0, Math.min(1, (x - 2) / Math.max(1, width - 4))) }

            onPressed: function(mouse) {
                bar.dragging = at(mouse.x)
                canvas.requestPaint()
            }
            onPositionChanged: function(mouse) {
                if (bar.dragging < 0) return
                bar.dragging = at(mouse.x)
                canvas.requestPaint()
            }
            onReleased: function(mouse) {
                const f = bar.dragging
                bar.dragging = -1
                if (f >= 0) bar.seeked(f)
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

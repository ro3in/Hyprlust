#!/bin/bash
# Waybar music module: music note when idle, compact 4-bar cava visualizer when playing.
# Click: toggle the Hyprlust music dock panel.
#
#   on-click:  qs ipc -c hyprlust-music call music toggle

CONFIG="/tmp/hyprlust_music_cava_config"

# Toggle the panel on click
if [[ "$1" = "toggle" ]]; then
    qs ipc -c hyprlust-music call music toggle 2>/dev/null || true
    exit 0
fi

cat > "$CONFIG" <<'EOF'
[general]
bars = 4
framerate = 30

[input]
method = pulse
source = auto

[output]
method = raw
raw_target = /dev/stdout
data_format = ascii
ascii_max_range = 7
EOF

cava_pid=""
cleanup() {
    if [[ -n "$cava_pid" ]]; then
        kill "$cava_pid" 2>/dev/null || true
        wait "$cava_pid" 2>/dev/null || true
        cava_pid=""
    fi
}
trap cleanup EXIT
trap 'cleanup; exit 0' INT TERM

is_playing() {
    playerctl -a status 2>/dev/null | grep -qx 'Playing'
}

json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/ }"
    printf '%s' "$s"
}

pango_escape() {
    local s="$1"
    s="${s//&/&amp;}"
    s="${s//</&lt;}"
    s="${s//>/&gt;}"
    printf '%s' "$s"
}

get_tooltip() {
    local meta
    meta="$(playerctl metadata --format '{{title}} — {{artist}}' 2>/dev/null || true)"
    meta="${meta% — }"
    if [[ -n "$meta" ]]; then
        json_escape "$(pango_escape "$meta")"
    else
        printf 'Music panel'
    fi
}

emit_idle() {
    printf '{"text": "", "class": "music-idle", "alt": "idle", "tooltip": "Music panel"}\n'
}

emit_idle
state="idle"

while true; do
    if is_playing; then
        state="playing"
        coproc CAVA { exec cava -p "$CONFIG" 2>/dev/null; }
        cava_pid="$CAVA_PID"
        last_check=$SECONDS
        tip="$(get_tooltip)"

        while true; do
            if IFS= read -t 1 -r -u "${CAVA[0]}" line; then
                line="${line//;/}"
                [[ -n "$line" ]] || continue
                line="${line//0/▁}"
                line="${line//1/▂}"
                line="${line//2/▃}"
                line="${line//3/▄}"
                line="${line//4/▅}"
                line="${line//5/▆}"
                line="${line//6/▇}"
                line="${line//7/█}"
                printf '{"text": " <span letter_spacing=\x271800\x27 font_size=\x27small\x27>%s</span>", "class": "music-viz", "alt": "playing", "tooltip": "%s"}\n' "$line" "$tip"
                if (( SECONDS - last_check >= 1 )); then
                    last_check=$SECONDS
                    is_playing || break
                    tip="$(get_tooltip)"
                fi
            else
                rc=$?
                if (( rc <= 128 )); then
                    break
                fi
                last_check=$SECONDS
                is_playing || break
                tip="$(get_tooltip)"
            fi
        done

        cleanup
        if ! is_playing; then
            emit_idle
            state="idle"
        else
            if [[ "$state" != "idle" ]]; then
                emit_idle
                state="idle"
            fi
            sleep 1
        fi
    else
        if [[ "$state" != "idle" ]]; then
            emit_idle
            state="idle"
        fi
        sleep 0.5
    fi
done

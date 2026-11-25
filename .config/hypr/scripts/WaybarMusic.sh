#!/bin/bash
# Waybar music module: music note when idle, cava visualizer when playing.
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
bars = 8

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
trap cleanup EXIT INT TERM

is_playing() {
    playerctl -a status 2>/dev/null | grep -qx 'Playing'
}

emit_idle() {
    printf '{"text": "  ", "class": "music-idle", "alt": "idle", "tooltip": "Music panel"}\n'
}

emit_idle
state="idle"

while true; do
    if is_playing; then
        state="playing"
        coproc CAVA { exec cava -p "$CONFIG" 2>/dev/null; }
        cava_pid="$CAVA_PID"
        last_check=$SECONDS

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
                printf '{"text": " %s ", "class": "music-viz", "alt": "playing", "tooltip": "Music panel"}\n' "$line"
                if (( SECONDS - last_check >= 1 )); then
                    last_check=$SECONDS
                    is_playing || break
                fi
            else
                rc=$?
                if (( rc <= 128 )); then
                    break
                fi
                last_check=$SECONDS
                is_playing || break
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

#!/bin/bash
# Waybar music module: music note when idle, cava visualizer when playing.
# Click: toggle the Hyprlust music dock panel.
#
#   on-click:  qs ipc -c hyprlust-music call music toggle
#
# The script keeps a cava instance running in the background and re-reads it
# on every waybar tick, so the bars move with the music while playing.

CONFIG="/tmp/hyprlust_music_cava_config"

# Create cava config if missing
if [ ! -f "$CONFIG" ]; then
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
fi

# Translate cava's raw digits (0-7) into braille-style block bars
bar="▁▂▃▄▅▆▇█"
dict="s/;//g"
for ((i = 0; i < ${#bar}; i++)); do
    dict+=";s/$i/${bar:$i:1}/g"
done

# Toggle the panel on click
if [ "$1" = "toggle" ]; then
    qs ipc -c hyprlust-music call music toggle 2>/dev/null || true
    exit 0
fi

# Keep cava running in the background; its output feeds the visualizer.
cava -p "$CONFIG" 2>/dev/null | sed -u "$dict" | while IFS= read -r line; do
    # All zeros = nothing playing (cava still runs but outputs silence)
    case "$line" in
        *"0 0 0 0 0 0 0 0"*|*"0 0 0 0 0 0 0"*)
            echo "{\"text\": \"  \", \"class\": \"music-idle\", \"alt\": \"idle\"}"
            ;;
        *)
            echo "{\"text\": \" $line \", \"class\": \"music-viz\", \"alt\": \"playing\"}"
            ;;
    esac
done

#!/usr/bin/env bash
#
# install.sh — Arch Linux installer for the Hyprlust dotfiles (fish edition)
#
# Upstream:  https://github.com/NischalDawadi/Hyprlust   (zsh)
# This fork: https://github.com/ro3in/Hyprlust            (fish)
#
# Usage:
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/ro3in/Hyprlust/master/install.sh)"
#
# Or, after cloning:
#   ./install.sh            # full install
#   ./install.sh --dry-run  # show what would happen, change nothing
#
# What this does NOT do: repartition, install a bootloader, or create users.
# Run it on an Arch/Arch-based system that already boots and has a user.

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
# Your fork of Hyprlust. It holds the whole config tree, the fish config and
# this installer, so a single clone is all that is needed.
REPO_URL="${REPO_URL:-https://github.com/ro3in/Hyprlust.git}"

REPO_DIR="${REPO_DIR:-$HOME/Hyprlust}"   # where the dotfiles get cloned
BACKUP_DIR="$HOME/.config-backup-$(date +%Y%m%d-%H%M%S)"

DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------
if [[ -t 1 ]]; then
    C_OK=$'\033[0;32m'; C_WARN=$'\033[1;33m'; C_INFO=$'\033[0;34m'
    C_ERR=$'\033[0;31m'; C_OFF=$'\033[0m'
else
    C_OK=""; C_WARN=""; C_INFO=""; C_ERR=""; C_OFF=""
fi

info() { printf '%s[INFO]%s %s\n' "$C_INFO" "$C_OFF" "$*"; }
ok()   { printf '%s[ OK ]%s %s\n' "$C_OK" "$C_OFF" "$*"; }
warn() { printf '%s[WARN]%s %s\n' "$C_WARN" "$C_OFF" "$*" >&2; }
die()  { printf '%s[FAIL]%s %s\n' "$C_ERR" "$C_OFF" "$*" >&2; exit 1; }

run() {
    if (( DRY_RUN )); then
        printf '  + %s\n' "$*"
    else
        "$@"
    fi
}

# Make sure a directory is on PATH for fish sessions.
ensure_path_line() {
    local dir="$1"
    local conf="$HOME/.config/fish/config.fish"
    [[ -d "$dir" ]] || return 0
    grep -qsF "$dir" "$conf" && return 0
    (( DRY_RUN )) && { printf '  + add %s to fish PATH\n' "$dir"; return 0; }
    printf '\nfish_add_path --global %s\n' "$dir" >>"$conf"
}

# ---------------------------------------------------------------------------
# 1. Preflight
# ---------------------------------------------------------------------------
(( EUID == 0 )) && die "Run as your normal user, not root (the script calls sudo itself)."

command -v pacman >/dev/null || die "pacman not found — this installer is for Arch Linux only."
command -v sudo   >/dev/null || die "sudo not found — install sudo and add your user to the wheel group."

# Keep sudo alive for the whole run instead of re-prompting mid-install.
# A dry run changes nothing, so it must not ask for a password at all.
# The keepalive loop closes its inherited stdout/stderr; otherwise it holds the
# caller's pipe open and `curl | bash` appears to hang after the script ends.
if (( DRY_RUN )); then
    SUDO_KEEPALIVE_PID=""
else
    info "Requesting sudo privileges..."
    sudo -v || die "sudo authentication failed."
    (
        while kill -0 "$$" 2>/dev/null; do
            sudo -n true
            sleep 50
        done
    ) >/dev/null 2>&1 &
    SUDO_KEEPALIVE_PID=$!
fi
trap '[[ -n "${SUDO_KEEPALIVE_PID:-}" ]] && kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true' EXIT

info "Arch-based system detected: $(. /etc/os-release && printf '%s' "${PRETTY_NAME:-unknown}")"
(( DRY_RUN )) && warn "DRY RUN — nothing will be installed or modified."

# ---------------------------------------------------------------------------
# 1b. GPU detection
# ---------------------------------------------------------------------------
# Hyprland needs different drivers and environment variables per vendor, and
# the wrong env vars actively break rendering (e.g. GBM_BACKEND=nvidia-drm on
# an AMD box). Detect what is actually present so this script is portable.
GPU_VENDORS=()   # subset of: nvidia amd intel
GPU_PRIMARY=""   # the GPU driving the display, if determinable

_detect_gpu() {
    local vga=""
    if command -v lspci >/dev/null 2>&1; then
        vga="$(lspci -nn 2>/dev/null | grep -Ei 'vga compatible|3d controller|display controller' || true)"
    fi

    # Fall back to DRM sysfs if lspci is unavailable (minimal installs).
    if [[ -z "$vga" ]] && [[ -d /sys/class/drm ]]; then
        for c in /sys/class/drm/card*/device/vendor; do
            [[ -r "$c" ]] || continue
            case "$(cat "$c")" in
                0x10de) vga+=$'\n''nvidia' ;;
                0x1002) vga+=$'\n''amd' ;;
                0x8086) vga+=$'\n''intel' ;;
            esac
        done
    fi

    local lower; lower="$(printf '%s' "$vga" | tr '[:upper:]' '[:lower:]')"
    [[ "$lower" == *nvidia* ]] && GPU_VENDORS+=(nvidia)
    # 1002 = AMD/ATI, and "advanced micro devices" catches the full name.
    [[ "$lower" == *amd* || "$lower" == *"advanced micro devices"* || "$lower" == *"[1002:"* ]] && GPU_VENDORS+=(amd)
    [[ "$lower" == *intel* || "$lower" == *"[8086:"* ]] && GPU_VENDORS+=(intel)

    # Pick the primary: the one Hyprland will render on. NVIDIA discrete is
    # usually primary on desktops; on laptops the iGPU often is. This is a
    # hint for choosing driver packages, never load-bearing.
    if [[ " ${GPU_VENDORS[*]} " == *" nvidia "* ]]; then
        GPU_PRIMARY="nvidia"
    elif [[ " ${GPU_VENDORS[*]} " == *" amd "* ]]; then
        GPU_PRIMARY="amd"
    elif [[ " ${GPU_VENDORS[*]} " == *" intel "* ]]; then
        GPU_PRIMARY="intel"
    fi
}

_detect_gpu

if (( ${#GPU_VENDORS[@]} == 0 )); then
    info "No physical GPU identified (VM or virtual display) — will use Mesa software rendering."
elif (( ${#GPU_VENDORS[@]} > 1 )); then
    info "GPUs detected: ${GPU_VENDORS[*]} (hybrid). Primary guess: ${GPU_PRIMARY:-unknown}"
else
    info "GPU detected: ${GPU_VENDORS[0]}"
fi

# ---------------------------------------------------------------------------
# 2. Packages
# ---------------------------------------------------------------------------
# Official repos only. Everything here is required by Hyprlust's configs:
# the hyprland.conf sources, waybar's custom modules, and the Keybinds.
PACMAN_PKGS=(
    # --- Hyprland core ---
    hyprland hyprland-protocols hyprpm hyprlock hypridle hyprpicker
    hyprpolkitagent hyprsunset
    xdg-desktop-portal-hyprland xdg-desktop-portal-gtk xdg-utils
    polkit polkit-gnome qt5-wayland qt6-wayland

    # --- Bar, launcher, notifications, wallpaper ---
    waybar rofi kitty swaync awww swaybg
    # NOTE: awww is the renamed successor of swww and PROVIDES/REPLACES it.

    # --- Screenshots & clipboard ---
    grim slurp swappy wl-clipboard cliphist

    # --- Audio / media / brightness ---
    # NOTE: pipewire-jack CONFLICTS WITH jack2. With --noconfirm pacman answers
    # "no" to the "remove jack2?" prompt and aborts the ENTIRE transaction, so
    # nothing gets installed. Handle the swap explicitly instead (see below).
    pipewire pipewire-alsa pipewire-pulse wireplumber
    pamixer pavucontrol playerctl brightnessctl
    mpd mpc rmpc cava

    # --- Networking & Bluetooth ---
    networkmanager network-manager-applet bluez bluez-utils blueman

    # --- File manager, archives, images ---
    thunar thunar-archive-plugin file-roller tumbler gvfs
    imagemagick ffmpeg

    # --- Fonts (waybar/kitty reference these by name) ---
    ttf-jetbrains-mono-nerd ttf-firacode-nerd ttf-iosevka-nerd
    otf-font-awesome ttf-nerd-fonts-symbols inter-font
    noto-fonts noto-fonts-emoji

    # --- Theming ---
    nwg-look qt5ct qt6ct kvantum kvantum-qt5
    materia-gtk-theme papirus-icon-theme gnome-themes-extra
    dconf

    # --- Shell & CLI (fish instead of zsh) ---
    fish fisher starship fastfetch btop eza zoxide fzf bat
    yazi neovim mpv zathura jq python python-pyquery python-requests
    rsync curl wget unzip git base-devel
)

# AUR packages. Optional: the desktop still works without them, but you lose
# pyprland's dropdown terminal, wallust recolouring, and the GTK shell.
AUR_PKGS=(
    pyprland              # SUPER+SHIFT+Return dropdown terminal
    wallust               # recolours kitty/waybar/swaync from the wallpaper
    wlogout               # power menu (CTRL+ALT+P)
    sptlrx                # spotify lyrics in the bar
    bibata-cursor-theme-bin
    tela-circle-icon-theme-git
    iio-hyprland-git      # autorotate on tablets/laptops
)

info "Installing packages from the official repos..."

# pipewire-jack conflicts with jack2, which is commonly already installed
# (cava, ffmpeg, mpv, waybar and others pull it in). Under --noconfirm pacman
# answers "no" to the "remove jack2?" prompt and aborts the ENTIRE
# transaction, so nothing gets installed at all. Rather than ripping out the
# user's audio stack, keep whichever JACK provider is already present and only
# add pipewire-jack on systems that have none.
if pacman -Qq jack2 >/dev/null 2>&1 || pacman -Qq jack >/dev/null 2>&1; then
    info "A JACK provider is already installed — keeping it, skipping pipewire-jack."
else
    PACMAN_PKGS+=(pipewire-jack)
fi

# Split the transaction so one bad package cannot sink the whole install.
# Anything that fails is collected and reported at the end instead of
# silently killing the script under 'set -e'.

# ---------------------------------------------------------------------------
# Personal apps from apps.list
# ---------------------------------------------------------------------------
# apps.list lives in the repo, so it is only readable after the clone. Read it
# here if the repo is already on disk (a re-run), otherwise it is read again
# after the clone step below. Lines look like:
#     kitty            # repo package
#     aur:vm-curator   # AUR only
read_apps_list() {
    local list="$REPO_DIR/apps.list"
    if [[ ! -f "$list" ]]; then
        # First run: the repo is cloned later in the script, so pull just this
        # one small file now. If that fails we simply skip the personal apps
        # rather than aborting the whole install.
        local url="${REPO_URL%.git}/raw/master/apps.list"
        if command -v curl >/dev/null 2>&1; then
            curl -fsSL --max-time 15 "$url" -o "${TMPDIR:-/tmp}/hyprlust-apps.list" 2>/dev/null \
                && list="${TMPDIR:-/tmp}/hyprlust-apps.list"
        fi
    fi
    [[ -f "$list" ]] || return 0
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%%#*}"                 # strip trailing comments
        line="${line//[[:space:]]/}"       # strip all whitespace
        [[ -z "$line" ]] && continue
        if [[ "$line" == aur:* ]]; then
            EXTRA_AUR_PKGS+=("${line#aur:}")
        else
            EXTRA_PACMAN_PKGS+=("$line")
        fi
    done < "$list"
}

EXTRA_PACMAN_PKGS=()
EXTRA_AUR_PKGS=()
read_apps_list

if (( ${#EXTRA_PACMAN_PKGS[@]} > 0 )); then
    info "Adding ${#EXTRA_PACMAN_PKGS[@]} app(s) from apps.list to the repo packages."
    # De-duplicate: Hyprlust's own list wins, extras only add to it.
    for pkg in "${EXTRA_PACMAN_PKGS[@]}"; do
        [[ " ${PACMAN_PKGS[*]} " == *" $pkg "* ]] || PACMAN_PKGS+=("$pkg")
    done
fi
if (( ${#EXTRA_AUR_PKGS[@]} > 0 )); then
    info "Adding ${#EXTRA_AUR_PKGS[@]} AUR app(s) from apps.list."
    for pkg in "${EXTRA_AUR_PKGS[@]}"; do
        [[ " ${AUR_PKGS[*]} " == *" $pkg "* ]] || AUR_PKGS+=("$pkg")
    done
fi

FAILED_PKGS=()
if (( DRY_RUN )); then
    run sudo pacman -Syu --needed --noconfirm "${PACMAN_PKGS[@]}"
else
    if ! sudo pacman -Syu --needed --noconfirm "${PACMAN_PKGS[@]}"; then
        warn "Bulk install failed — retrying package by package to isolate problems..."
        for pkg in "${PACMAN_PKGS[@]}"; do
            sudo pacman -S --needed --noconfirm "$pkg" >/dev/null 2>&1 \
                || FAILED_PKGS+=("$pkg")
        done
    fi
fi

if (( ${#FAILED_PKGS[@]} > 0 )); then
    warn "These packages could not be installed:"
    printf '        %s\n' "${FAILED_PKGS[@]}"
    warn "The desktop may be missing features. Re-run this script after fixing them."
fi
ok "Official packages installed."

# --- AUR helper -------------------------------------------------------------
AUR_HELPER=""
if command -v paru >/dev/null; then
    AUR_HELPER="paru"
elif command -v yay >/dev/null; then
    AUR_HELPER="yay"
else
    info "No AUR helper found — building yay from source..."
    if (( DRY_RUN )); then
        printf '  + git clone https://aur.archlinux.org/yay-bin.git && makepkg -si\n'
        AUR_HELPER="yay"
    else
        _tmp="$(mktemp -d)"
        if git clone --depth=1 https://aur.archlinux.org/yay-bin.git "$_tmp/yay-bin" \
            && ( cd "$_tmp/yay-bin" && makepkg -si --noconfirm ); then
            AUR_HELPER="yay"
            ok "yay installed."
        else
            warn "Could not install yay. Skipping AUR packages."
        fi
        rm -rf "$_tmp"
    fi
fi

if [[ -n "$AUR_HELPER" ]]; then
    info "Installing AUR packages with $AUR_HELPER..."
    # Both helpers ask interactive questions even with --noconfirm: whether to
    # clean the build dir, show PKGBUILD diffs, and so on. Left unanswered they
    # block forever. Each helper needs its own flag names, and stdin is
    # redirected from /dev/null so a surprise prompt cannot hang the install.
    _aur_opts=()
    case "$AUR_HELPER" in
        yay)  _aur_opts=(--answerclean None --answerdiff None) ;;
        paru) _aur_opts=(--skipreview --batchinstall) ;;
    esac

    for pkg in "${AUR_PKGS[@]}"; do
        if run "$AUR_HELPER" -S --needed --noconfirm "${_aur_opts[@]}" "$pkg" < /dev/null; then
            :
        else
            warn "AUR package '$pkg' failed — continuing without it."
        fi
    done

    # wallust is a large Rust build (~260 crates) and is the one AUR package
    # most likely to be killed on a small VM. It only drives colour theming,
    # so the desktop is usable without it.
    if ! command -v wallust >/dev/null; then
        warn "wallust is missing — wallpaper-driven recolouring will not work."
        warn "Hyprlust ships a default palette, so colours still render."
        warn "Install it later with:  yay -S wallust"
    fi
fi

# ---------------------------------------------------------------------------
# 3. Fetch the dotfiles
# ---------------------------------------------------------------------------
clone_or_update() {
    local url="$1" dest="$2" label="$3"
    if [[ -d "$dest/.git" ]]; then
        info "Updating $label in $dest..."
        run git -C "$dest" pull --ff-only || warn "Could not update $label — using the local copy."
    elif [[ -e "$dest" ]]; then
        # A leftover non-git directory (older manual clone, partial download)
        # would otherwise abort the whole install. Move it aside and re-clone.
        warn "$dest exists but is not a git checkout — moving it aside."
        run mv "$dest" "${dest}.bak-$(date +%Y%m%d-%H%M%S)"
        info "Cloning $label into $dest..."
        run git clone --depth=1 "$url" "$dest"
    else
        info "Cloning $label into $dest..."
        run git clone --depth=1 "$url" "$dest"
    fi
}

clone_or_update "$REPO_URL" "$REPO_DIR" "Hyprlust (ro3in fork)"

if [[ ! -d "$REPO_DIR/.config/hypr" ]]; then
    die "$REPO_DIR does not look like a Hyprlust checkout (no .config/hypr)."
fi

# ---------------------------------------------------------------------------
# 4. Deploy the fish shell config
# ---------------------------------------------------------------------------
mkdir -p "$HOME/.config/fish"
FISH_CONFIG="$HOME/.config/fish/config.fish"

# Take the fork's config.fish if present, otherwise keep whatever is there.
FORK_FISH="$REPO_DIR/.config/fish/config.fish"
if [[ -f "$FORK_FISH" ]]; then
    if [[ -f "$FISH_CONFIG" ]] && ! cmp -s "$FORK_FISH" "$FISH_CONFIG"; then
        mkdir -p "$BACKUP_DIR/fish"
        run cp -a "$FISH_CONFIG" "$BACKUP_DIR/fish/config.fish"
        info "Backed up the existing fish config."
    fi
    run install -Dm644 "$FORK_FISH" "$FISH_CONFIG"
    ok "Deployed fish config from this fork."
elif [[ ! -f "$FISH_CONFIG" ]]; then
    # The fork was unreachable AND this machine has no fish config yet.
    # Write a minimal but usable one rather than leaving fish bare.
    warn "Fork unavailable and no existing fish config — writing a minimal one."
    if (( DRY_RUN )); then
        printf '  + write a minimal %s\n' "$FISH_CONFIG"
    else
        cat >"$FISH_CONFIG" <<'EOF'
# Minimal fish config written by install.sh (Hyprlust)
set -gx EDITOR nvim
fish_add_path --global $HOME/.local/bin $HOME/.cargo/bin $HOME/.bun/bin

if status is-interactive
    type -q starship && starship init fish | source
    type -q zoxide && zoxide init fish | source
    type -q fzf && fzf --fish 2>/dev/null | source
end
EOF
    fi
else
    info "Using the existing fish config at $FISH_CONFIG."
fi

# Starship must be initialised for fish. Only add it if it is really missing.
if ! grep -qs 'starship init fish' "$FISH_CONFIG"; then
    if (( DRY_RUN )); then
        printf '  + append starship init to %s\n' "$FISH_CONFIG"
    else
        cat >>"$FISH_CONFIG" <<'EOF'

# Added by install.sh (Hyprlust fish port)
if status is-interactive
    starship init fish | source
end
EOF
    fi
fi

# ---------------------------------------------------------------------------
# 5. Deploy the Hyprlust config tree
# ---------------------------------------------------------------------------
# Upstream is a full ~/.config dump, 128 MB of which ~92 MB is a spicetify
# cache and app databases. Copying all of it onto every machine is wasteful and
# drags along per-machine state (browser profiles, logs, .db files).
# Deploy only what actually themes the desktop.
CONFIG_ITEMS=(
    hypr waybar kitty rofi swaync wlogout
    gtk-2.0 gtk-3.0 gtk-4.0 Kvantum qt5ct qt6ct nwg-look
    btop fastfetch cava starship.toml
    # Optional extras — deployed only if you have the apps installed.
    mpd rmpc mpv nvim yazi zathura swappy wallust matugen
    # Personal app configs (bundled with the fork).
    micro qimgv easyeffects vm-curator
)

# pyprland reads ~/.config/pypr/config.toml and warns at startup about the
# legacy ~/.config/hypr/pyprland.toml location. Upstream ships the file under
# hypr/, so place it where the daemon actually looks.
deploy_pypr_config() {
    local src="$REPO_DIR/.config/hypr/pyprland.toml"
    local dest_dir="$HOME/.config/pypr"
    local dest="$dest_dir/config.toml"
    [[ -f "$src" ]] || return 0

    if (( DRY_RUN )); then
        printf '  + place pyprland config at ~/.config/pypr/config.toml\n'
        return 0
    fi
    mkdir -p "$dest_dir"
    if [[ -f "$dest" ]] && ! cmp -s "$src" "$dest"; then
        mkdir -p "$BACKUP_DIR/.config/pypr"
        run cp -a "$dest" "$BACKUP_DIR/.config/pypr/config.toml"
    fi
    run cp -a "$src" "$dest"
    ok "Placed pyprland config at ~/.config/pypr/config.toml."
}

backup_and_place() {
    local src="$1" dest="$2"
    if [[ -e "$dest" || -L "$dest" ]]; then
        mkdir -p "$BACKUP_DIR/$(dirname "${dest#"$HOME"/}")"
        run mv "$dest" "$BACKUP_DIR/${dest#"$HOME"/}"
    fi
    run cp -a "$src" "$dest"
    # Some configs carry a placeholder instead of a hardcoded home directory
    # (vm-curator, for one). Expand it to this machine's real $HOME.
    if [[ -d "$dest" ]] && ! (( DRY_RUN )); then
        if grep -rqI "__HOME__" "$dest" 2>/dev/null; then
            grep -rlI "__HOME__" "$dest" 2>/dev/null | while IFS= read -r f; do
                sed -i "s|__HOME__|$HOME|g" "$f"
            done
        fi
    fi
}

info "Deploying desktop configs (existing ones go to $BACKUP_DIR)..."
for item in "${CONFIG_ITEMS[@]}"; do
    src="$REPO_DIR/.config/$item"
    [[ -e "$src" ]] || continue
    backup_and_place "$src" "$HOME/.config/$item"
done
deploy_pypr_config

# ---------------------------------------------------------------------------
# 5b. Hyprland config format: .lua for 0.57+, .conf for older
# ---------------------------------------------------------------------------
# Hyprland 0.55 introduced Lua configs and 0.57 REMOVED the legacy hyprlang
# (.conf) loader entirely. Hyprlust ships .conf, so on a current Hyprland the
# whole tree is ignored and the compositor starts with an autogenerated
# default config. Ship both formats and let the installed version decide.
_hypr_ver="$(hyprland --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+' | head -1)"
_need_lua=0
if [[ -n "$_hypr_ver" ]]; then
    _maj="${_hypr_ver%%.*}"
    _min="${_hypr_ver#*.}"
    if (( _maj > 0 || _min >= 57 )); then
        _need_lua=1
    fi
fi

if (( _need_lua )); then
    info "Hyprland ${_hypr_ver} uses Lua configs — deploying them."
    if (( DRY_RUN )); then
        printf '  + copy .config/hypr-lua/* into ~/.config/hypr/\n'
        printf '  + back up the old hyprland.conf\n'
    else
        # Keep the old file for reference but out of the way; 0.57 ignores it
        # anyway, and leaving it invites confusion about which file is live.
        if [[ -f "$HOME/.config/hypr/hyprland.conf" ]] \
           && ! grep -q 'hyprlust-lua' "$HOME/.config/hypr/hyprland.conf" 2>/dev/null; then
            run mv "$HOME/.config/hypr/hyprland.conf" \
                   "$HOME/.config/hypr/hyprland.conf.legacy"
        fi
        _lua_src="$REPO_DIR/.config/hypr-lua"
        if [[ -d "$_lua_src" ]]; then
            # Copy over the deployed tree so hyprland.lua and its modules sit
            # side by side; package.path resolves from the config's own dir.
            while IFS= read -r -d '' f; do
                rel="${f#"$_lua_src"/}"
                mkdir -p "$HOME/.config/hypr/$(dirname "$rel")"
                run cp -a "$f" "$HOME/.config/hypr/$rel"
            done < <(find "$_lua_src" -name '*.lua' -print0)
            ok "Lua configs deployed ($(find "$_lua_src" -name '*.lua' | wc -l) files)."
        else
            warn "No .config/hypr-lua in the repo — Hyprland 0.57 will use its defaults."
        fi
    fi
else
    if [[ -n "$_hypr_ver" ]]; then
        info "Hyprland ${_hypr_ver} uses .conf configs — leaving them as-is."
    fi
fi

# Themes live at the repo root, not under .config/.
if [[ -d "$REPO_DIR/.themes" ]]; then
    mkdir -p "$HOME/.themes"
    for theme in "$REPO_DIR/.themes"/*; do
        [[ -e "$theme" ]] || continue
        backup_and_place "$theme" "$HOME/.themes/$(basename "$theme")"
    done
fi

# ---------------------------------------------------------------------------
# 6. Repair the repo's absolute symlinks
# ---------------------------------------------------------------------------
# Upstream ships waybar/config and waybar/style.css as symlinks to
# /home/hypr/..., which is a broken link on any other machine. Point them at
# the real files inside your own ~/.config instead.
repair_symlink() {
    local link="$1" target="$2"
    [[ -L "$link" ]] || return 0
    local current; current="$(readlink "$link")"
    [[ "$current" == /* ]] || return 0          # relative link, fine
    [[ -e "$link" ]] && return 0                 # absolute but valid here
    [[ -e "$target" ]] || { warn "Cannot repair $link — $target is missing."; return 0; }
    info "Repairing broken symlink: ${link#"$HOME"/} -> $(basename "$target")"
    run ln -sfn "$target" "$link"
}

repair_symlink "$HOME/.config/waybar/config" \
    "$HOME/.config/waybar/configs/[TOP] wallust_new"
repair_symlink "$HOME/.config/waybar/style.css" \
    "$HOME/.config/waybar/style/[Dark] Purpl.css"

# rofi's wallpaper preview is a symlink to a file that ships with neither repo.
if [[ -L "$HOME/.config/rofi/.current_wallpaper" && ! -e "$HOME/.config/rofi/.current_wallpaper" ]]; then
    run rm -f "$HOME/.config/rofi/.current_wallpaper"
fi

# ---------------------------------------------------------------------------
# 7. swww -> awww compatibility
# ---------------------------------------------------------------------------
# Hyprlust was written against swww. Upstream swww was renamed to awww, and the
# Arch package is now `awww`, which brings three breaking changes:
#   1. the binary is `awww`, not `swww`
#   2. `swww img -o OUT` became `awww img --output OUT`
#   3. the cache moved from ~/.cache/swww/OUT to ~/.cache/awww/<version>/OUT
# Hyprland's `exec` does not consult fish's PATH, so a wrapper script dropped
# in ~/.local/bin is not reliable. Patch the affected scripts in place.
# Every edit below is idempotent, so re-running the installer is safe.
if command -v awww >/dev/null && ! command -v swww >/dev/null; then
    info "Adapting Hyprlust scripts from swww to awww..."

    if (( DRY_RUN )); then
        printf '  + rewrite swww -> awww in ~/.config/hypr/{scripts,UserScripts}\n'
        printf "  + teach WallustSwww.sh about awww's versioned cache\n"
    else
        _patched=0
        while IFS= read -r -d '' f; do
            # `-o` is the short form of `--outputs` and works unchanged in
            # awww, so a plain rename is enough. Do NOT "expand" it to
            # `--output` — that flag does not exist and every wallpaper
            # command would fail with "unexpected argument '--output'".
            if grep -qE '\bswww\b|swww-daemon' "$f"; then
                sed -i \
                    -e 's/swww-daemon/awww-daemon/g' \
                    -e 's/\bswww\b/awww/g' \
                    "$f"
                _patched=$((_patched + 1))
            fi
        done < <(grep -rlZ --binary-files=without-match 'swww' \
                    "$HOME/.config/hypr/scripts" \
                    "$HOME/.config/hypr/UserScripts" \
                    "$HOME/.config/hypr/UserConfigs" \
                    "$HOME/.config/hypr/initial-boot.sh" 2>/dev/null || true)
        (( _patched > 0 )) && ok "Patched $_patched file(s) to use awww."

        # WallustSwww.sh hardcodes the old cache path. awww stores images under
        # ~/.cache/awww/<version>/<output>, so teach the script to descend into
        # the newest version directory. Runs after the rename above, which is
        # why it matches the already-rewritten awww path.
        WALLUST_SH="$HOME/.config/hypr/scripts/WallustSwww.sh"
        if [[ -f "$WALLUST_SH" ]]; then
            if ! grep -q 'hyprlust-install' "$WALLUST_SH"; then
                RESOLVER='cache_dir="$HOME/.cache/awww/"; _n="$(find "$HOME/.cache/awww" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort -V | tail -n 1)"; [ -n "$_n" ] && cache_dir="$_n/" # hyprlust-install'
                # sed treats & \ and the delimiter specially inside a
                # replacement, so escape all three.
                _repl=${RESOLVER//\\/\\\\}
                _repl=${_repl//&/\\&}
                _repl=${_repl//@/\\@}
                sed -i "s@^cache_dir=\"\$HOME/\.cache/awww/\"\$@${_repl}@" "$WALLUST_SH"
                ok "Taught WallustSwww.sh to find awww's cache directory."
            fi
        fi
    fi
fi

# The wallpaper daemon is started by initial-boot.sh (first login) and by
# Startup_Apps.conf. If the config still says `swww` while only `awww` is
# installed, nothing ever starts the daemon and Hyprland comes up with a black
# background. Verify here in case the patch above somehow missed it.
_STARTUP="$HOME/.config/hypr/UserConfigs/Startup_Apps.conf"
if command -v awww >/dev/null && ! command -v swww >/dev/null && [[ -f "$_STARTUP" ]]; then
    if grep -q '\bswww\b' "$_STARTUP"; then
        if (( DRY_RUN )); then
            printf '  + swww still referenced in Startup_Apps.conf; would rewrite to awww\n'
        else
            sed -i -e 's/swww-daemon/awww-daemon/g' \
                   -e 's/\bswww\b/awww/g' \
                   "$_STARTUP"
            ok "Rewrote remaining swww references in Startup_Apps.conf."
        fi
    fi
fi

# ags is deliberately not installed (Aylur's GTK Shell): upstream's
# "exec-once = ags &" is a leftover from an earlier bar setup, and the AUR
# package named `ags` is an unrelated adventure-game engine. Comment the line
# out so every login does not spawn a command that can never exist.
if [[ -f "$_STARTUP" ]] && grep -qE '^exec-once = ags &' "$_STARTUP"; then
    if (( DRY_RUN )); then
        printf '  + disable the leftover "exec-once = ags" line\n'
    else
        sed -i 's|^exec-once = ags &|#exec-once = ags \&  # hyprlust: not installed|' "$_STARTUP"
        ok "Disabled the leftover ags startup line."
    fi
fi

# ---------------------------------------------------------------------------
# 8. Wallpapers & directories
# ---------------------------------------------------------------------------
# Hyprlust hardcodes ~/Pictures/wallpapers (lowercase w).
mkdir -p "$HOME/Pictures/wallpapers" "$HOME/Pictures/Screenshots" "$HOME/Music"

WALL_SRC=""
for d in "$REPO_DIR/wallpapers" "$REPO_DIR/Wallpapers" "$REPO_DIR/Pictures/wallpapers"; do
    [[ -d "$d" ]] && { WALL_SRC="$d"; break; }
done

if [[ -n "$WALL_SRC" ]]; then
    info "Copying wallpapers from $WALL_SRC..."
    run cp -an "$WALL_SRC/." "$HOME/Pictures/wallpapers/"
    ok "Wallpapers copied to ~/Pictures/wallpapers"
else
    # Upstream keeps wallpapers in a separate repo; don't pull 450 MB silently.
    warn "No wallpapers bundled in the repo."
    warn "Grab them yourself if you want the wallpaper picker to work:"
    warn "  git clone --depth=1 https://github.com/NischalDawadi/Wallpapers \\"
    warn "      ~/Pictures/wallpapers"
fi

# ---------------------------------------------------------------------------
# 9. Fix hardcoded /home/hypr paths
# ---------------------------------------------------------------------------
# Several upstream configs hardcode the original author's home directory.
# Rewrite them to $HOME so keybinds and caches resolve on your machine.
info "Rewriting hardcoded /home/hypr paths to $HOME..."
if (( DRY_RUN )); then
    printf '  + grep -rl /home/hypr ~/.config and rewrite\n'
else
    while IFS= read -r -d '' f; do
        sed -i "s|/home/hypr|$HOME|g" "$f"
    done < <(grep -rlZ --binary-files=without-match '/home/hypr' "$HOME/.config" 2>/dev/null || true)
fi

# ---------------------------------------------------------------------------
# 10. Permissions
# ---------------------------------------------------------------------------
info "Making Hyprlust scripts executable..."
if (( DRY_RUN )); then
    printf '  + chmod +x ~/.config/hypr/{scripts,UserScripts}/*\n'
else
    find "$HOME/.config/hypr/scripts" "$HOME/.config/hypr/UserScripts" \
        -type f \( -name '*.sh' -o -name '*.py' \) -exec chmod +x {} + 2>/dev/null || true
    chmod +x "$HOME/.config/hypr/initial-boot.sh" 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# 11. Services
# ---------------------------------------------------------------------------
info "Enabling NetworkManager and Bluetooth..."
run sudo systemctl enable --now NetworkManager.service
run sudo systemctl enable --now bluetooth.service

# ---------------------------------------------------------------------------
# 12. GPU setup (NVIDIA / AMD / Intel)
# ---------------------------------------------------------------------------
# Hyprland runs on all three vendors but needs different drivers and env vars.
# Upstream ships NVIDIA's variables commented out and nothing for the others,
# so a plain install is broken differently on each. This section configures
# only the vendor(s) actually present — applying NVIDIA's GBM/GLX vars on an
# AMD machine would break rendering, and vice versa.

_has_vendor() {
    [[ " ${GPU_VENDORS[*]:-} " == *" $1 "* ]]
}

# Uncomment the FIRST occurrence of an upstream-provided "env = KEY," line.
# Only touches lines upstream already wrote; never invents values.
_enable_env_lines() {
    local conf="$1"; shift
    [[ -f "$conf" ]] || return 0
    local changed=0 v
    for v in "$@"; do
        # Skip if already enabled. Upstream repeats some keys (NVD_BACKEND
        # appears twice), so without this guard a second run would uncomment
        # the duplicate.
        grep -qE "^env = ${v}," "$conf" && continue
        if grep -qE "^#env = ${v}," "$conf"; then
            awk -v v="$v" '
                !done && $0 ~ "^#env = " v "," { sub("^#env = ", "env = "); done=1 }
                { print }
            ' "$conf" > "$conf.tmp" && mv "$conf.tmp" "$conf"
            changed=1
        fi
    done
    (( changed )) && ok "Enabled environment variables in ${conf#"$HOME"/}"
}

# Append an "env = KEY,VALUE" line only if KEY is not already defined.
_add_env_if_missing() {
    local conf="$1" key="${2%%,*}" pair="$2"
    [[ -f "$conf" ]] || return 1
    grep -qE "^env = ${key}," "$conf" && return 1
    printf 'env = %s\n' "$pair" >>"$conf"
    return 0
}

ENV_CONF="$HOME/.config/hypr/UserConfigs/ENVariables.conf"

# --- 12a. NVIDIA ------------------------------------------------------------
if _has_vendor nvidia; then
    info "Configuring NVIDIA..."

    if ! pacman -Qq nvidia-utils >/dev/null 2>&1; then
        warn "nvidia-utils is not installed."
        # The open module is correct for Turing (GTX 16xx / RTX 20xx) and newer.
        # Older cards (Maxwell/Pascal) still need the proprietary nvidia-dkms.
        nv_pkg="nvidia-open-dkms"
        if ! pacman -Si nvidia-open-dkms >/dev/null 2>&1; then
            nv_pkg="nvidia-dkms"
        fi
        info "Installing $nv_pkg nvidia-utils libva-nvidia-driver..."
        run sudo pacman -S --needed --noconfirm "$nv_pkg" nvidia-utils libva-nvidia-driver \
            || warn "NVIDIA driver install failed — install it before logging in."
    else
        _nvver="$(pacman -Q nvidia-utils 2>/dev/null | awk '{print $2}')"
        ok "NVIDIA driver present${_nvver:+ ($_nvver)}."
    fi

    # Hyprland cannot start without modeset. Check it rather than assume.
    if [[ "$(cat /sys/module/nvidia_drm/parameters/modeset 2>/dev/null)" != "Y" ]]; then
        warn "nvidia_drm modeset is OFF — Hyprland will not start."
        warn "Add to your kernel command line, then reboot:"
        warn "  nvidia_drm.modeset=1 nvidia_drm.fbdev=1"
    else
        ok "nvidia_drm modeset enabled."
    fi

    # On a hybrid AMD/Intel + NVIDIA laptop the iGPU usually drives the panel,
    # so NVIDIA's GBM/GLX vars would break compositing. Only apply them when
    # NVIDIA is the only GPU present.
    if (( ${#GPU_VENDORS[@]} == 1 )); then
        _enable_env_lines "$ENV_CONF" \
            WLR_NO_HARDWARE_CURSORS LIBVA_DRIVER_NAME __GLX_VENDOR_LIBRARY_NAME \
            GBM_BACKEND NVD_BACKEND
    else
        info "Hybrid graphics: leaving NVIDIA GBM/GLX vars off (iGPU drives the display)."
        info "For per-app offload use: __NV_PRIME_RENDER_OFFLOAD=1 <app>"
        # Hardware video decode still matters. Pick the driver for the GPU that
        # actually drives the panel: on an Intel hybrid that is iHD (handled in
        # the Intel block below), so only claim LIBVA here for AMD hybrids.
        # WLR_NO_HARDWARE_CURSORS is harmless everywhere on hybrid.
        if ! _has_vendor intel; then
            _enable_env_lines "$ENV_CONF" LIBVA_DRIVER_NAME
        fi
        _enable_env_lines "$ENV_CONF" WLR_NO_HARDWARE_CURSORS
    fi

    # Suspend/resume hooks prevent the classic wake-to-black-screen bug.
    if pacman -Qq nvidia-utils >/dev/null 2>&1; then
        run sudo systemctl enable --now nvidia-suspend.service \
                nvidia-hibernate.service nvidia-resume.service 2>/dev/null \
            || info "NVIDIA power services not present — skipping."
    fi
fi

# --- 12b. AMD ---------------------------------------------------------------
if _has_vendor amd; then
    info "Configuring AMD..."

    # mesa covers Radeon; vulkan-radeon is needed for Hyprland's renderer.
    _amd_pkgs=(mesa vulkan-radeon libva-mesa-driver mesa-vdpau)
    if ! pacman -Qq mesa >/dev/null 2>&1; then
        info "Installing AMD userspace drivers..."
        run sudo pacman -S --needed --noconfirm "${_amd_pkgs[@]}" \
            || warn "AMD driver install failed — install mesa manually."
    else
        ok "Mesa already present."
    fi

    # RADV is the default Vulkan driver; this makes it explicit and avoids
    # falling back to a software renderer on hybrid setups.
    if ! grep -qE '^env = (AMD_VULKAN_ICD|VK_ICD_FILENAMES),' "$ENV_CONF" 2>/dev/null; then
        if (( DRY_RUN )); then
            printf '  + add AMD Vulkan hint to ENVariables.conf\n'
        else
            _add_env_if_missing "$ENV_CONF" "AMD_VULKAN_ICD,RADV" && ok "Set AMD_VULKAN_ICD=RADV."
        fi
    fi

    ok "AMD setup done (no proprietary driver required)."
fi

# --- 12c. Intel -------------------------------------------------------------
if _has_vendor intel; then
    info "Configuring Intel..."

    _intel_pkgs=(mesa vulkan-intel intel-media-driver libva-intel-driver)
    if ! pacman -Qq mesa >/dev/null 2>&1; then
        info "Installing Intel userspace drivers..."
        run sudo pacman -S --needed --noconfirm "${_intel_pkgs[@]}" \
            || warn "Intel driver install failed — install mesa manually."
    else
        ok "Mesa already present."
    fi

    # Intel's VA-API driver must be selected explicitly on newer iGPUs, or
    # hardware video decode silently falls back to the CPU.
    if ! grep -qE '^env = LIBVA_DRIVER_NAME,' "$ENV_CONF" 2>/dev/null; then
        if (( DRY_RUN )); then
            printf '  + add LIBVA_DRIVER_NAME=iHD for Intel\n'
        else
            _add_env_if_missing "$ENV_CONF" "LIBVA_DRIVER_NAME,iHD" \
                && ok "Set LIBVA_DRIVER_NAME=iHD."
        fi
    fi

    ok "Intel setup done."
fi

# --- 12d. Session env shared by every vendor ---------------------------------
# Upstream never defines this, and without it apps guess at the session type.
if [[ -f "$ENV_CONF" ]] && ! grep -q 'hyprlust-gpu' "$ENV_CONF"; then
    if (( DRY_RUN )); then
        printf '  + ensure XDG_SESSION_TYPE=wayland in ENVariables.conf\n'
    else
        _add_env_if_missing "$ENV_CONF" "XDG_SESSION_TYPE,wayland" || true
        printf '# hyprlust-gpu (%s)\n' "${GPU_PRIMARY:-unknown}" >>"$ENV_CONF"
    fi
fi

# --- 12e. Unknown / virtual GPU (VMs) ----------------------------------------
# VMware SVGA, virtio-gpu, QXL and friends match no vendor above. Hyprland
# still runs there, but only through Mesa's software renderer, and Mesa is
# not otherwise pulled in — without this a fresh VM has no working GL at all.
if (( ${#GPU_VENDORS[@]} == 0 )); then
    if ! pacman -Qq mesa >/dev/null 2>&1; then
        info "Virtual/unknown GPU — installing Mesa for software rendering..."
        run sudo pacman -S --needed --noconfirm mesa libva-mesa-driver \
            || warn "Mesa install failed — install 'mesa' before starting Hyprland."
    else
        ok "Mesa present (software rendering available)."
    fi

    # No hardware GL in a VM, so Hyprland must be allowed to fall back.
    if [[ -f "$ENV_CONF" ]] && ! grep -qE '^env = WLR_RENDERER_ALLOW_SOFTWARE,' "$ENV_CONF"; then
        if (( DRY_RUN )); then
            printf '  + enable WLR_RENDERER_ALLOW_SOFTWARE in ENVariables.conf\n'
        else
            _add_env_if_missing "$ENV_CONF" "WLR_RENDERER_ALLOW_SOFTWARE,1" \
                && ok "Enabled software rendering."
        fi
    fi

    info "In a VM, expect a slow desktop — this is llvmpipe, not a GPU."
fi

# --- 12f. 32-bit graphics libs (Steam/Wine) ----------------------------------
# Optional, but without these 32-bit games render through llvmpipe.
if (( ${#GPU_VENDORS[@]} > 0 )) && ! pacman -Qq lib32-mesa >/dev/null 2>&1; then
    _lib32=()
    _has_vendor nvidia && _lib32+=(lib32-nvidia-utils)
    _has_vendor amd    && _lib32+=(lib32-vulkan-radeon)
    _has_vendor intel  && _lib32+=(lib32-vulkan-intel)
    if (( ${#_lib32[@]} > 0 )); then
        info "Installing 32-bit graphics libs (for Steam/Wine)..."
        run sudo pacman -S --needed --noconfirm lib32-mesa "${_lib32[@]}" \
            || info "32-bit libs skipped (multilib may be disabled — that's fine)."
    fi
fi

# ---------------------------------------------------------------------------
# 13. Default shell -> fish
# ---------------------------------------------------------------------------
FISH_BIN="$(command -v fish || true)"
if [[ -n "$FISH_BIN" ]]; then
    # /bin is usually a symlink to /usr/bin, so compare resolved paths —
    # otherwise "/bin/fish" != "/usr/bin/fish" triggers a pointless chsh.
    FISH_REAL="$(readlink -f "$FISH_BIN")"
    SHELL_REAL="$(readlink -f "${SHELL:-}" 2>/dev/null || printf '%s' "${SHELL:-}")"

    # Make sure fish is in /etc/shells or chsh refuses.
    grep -qxF "$FISH_BIN" /etc/shells 2>/dev/null \
        || run sudo sh -c "echo '$FISH_BIN' >> /etc/shells"

    if [[ "$SHELL_REAL" != "$FISH_REAL" ]]; then
        info "Current shell is ${SHELL:-unknown}."
        # Read from /dev/tty so the prompt still works when piped through curl.
        # Fall back to a non-interactive default if there is no terminal.
        reply=""
        if ( exec </dev/tty ) 2>/dev/null; then
            read -rp "Set fish as your default shell? [y/N] " reply </dev/tty || reply=""
        else
            info "No terminal available — defaulting to yes."
            reply="y"
        fi
        if [[ "$reply" =~ ^[Yy]$ ]]; then
            run chsh -s "$FISH_BIN"
            ok "Default shell set to $FISH_BIN (takes effect next login)."
        else
            info "Keeping ${SHELL:-your current shell}. Switch later with: chsh -s $FISH_BIN"
        fi
    else
        ok "Fish is already your default shell."
    fi

    # Fisher plugins: fish's equivalent of the zsh plugin dirs upstream ships.
    if command -v fisher >/dev/null; then
        info "Installing fish plugins (fisher)..."
        run fish -c 'fisher install jorgebucaran/fisher PatrickF1/fzf.fish jorgebucaran/nvm.fish' \
            || warn "Some fish plugins failed to install — run 'fisher update' later."
    fi
else
    warn "fish was not found after the package install — skipping shell switch."
fi

# ---------------------------------------------------------------------------
# 14. Summary
# ---------------------------------------------------------------------------
# Only keep a backup dir if something was actually put in it.
if [[ -d "$BACKUP_DIR" ]]; then
    if [[ -z "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]]; then
        rmdir "$BACKUP_DIR" 2>/dev/null || true
    else
        ok "Previous configs backed up to $BACKUP_DIR"
    fi
fi

echo
ok "Hyprlust (fish edition) installation complete."
cat <<EOF

  ${C_WARN}Before you log in:${C_OFF}
    1. Review ~/.config/hypr/UserConfigs/Monitors.conf and set your real
       monitor name and resolution. Left as-is, Hyprland guesses.
    2. Set a wallpaper so the first login is not black:
         awww-daemon & awww img ~/Pictures/wallpapers/<file>

  ${C_WARN}Next steps:${C_OFF}
    3. Log out, then pick "Hyprland" in your display manager.
       From a TTY: Hyprland
    4. Apply GTK/Qt themes with nwg-look and qt6ct.
    5. Super+Shift+H lists the actual keybinds.

  ${C_WARN}Not installed on purpose:${C_OFF}
    - spicetify, Seanime, Upscayl and their caches (100+ MB of app state)
    - ags (Aylur's GTK Shell): the upstream exec-once line for it is a
      leftover; the waybar bar is the active one. Remove that line if it
      spams your log.

EOF

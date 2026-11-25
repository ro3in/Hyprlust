# AGENTS.md — handoff notes for Hyprlust (fish edition)

Written for an AI agent (or a human) picking this repo up cold. Read this before
touching anything; most of it is knowledge that was expensive to acquire and is
easy to destroy by "cleaning up".

---

## 1. What this repo is

A **fork of [NischalDawadi/Hyprlust](https://github.com/NischalDawadi/Hyprlust)**
(Hyprland rice) with two additions:

1. **A one-command Arch installer** (`install.sh`) that deploys the desktop,
   detects the GPU, and adapts upstream's config to the local machine.
2. **zsh → fish**, plus a bespoke now-playing panel built in the rice's own
   visual language.

Upstream is a *dotfiles dump*. This fork is an *installer*. That distinction
drives every design decision: anything deployed must be reproducible from this
repo alone, and nothing user-specific may be committed.

Owner: `ro3in` on GitHub. Remote: `https://github.com/ro3in/Hyprlust.git`,
branch `master`.

```bash
git clone https://github.com/ro3in/Hyprlust.git
```

---

## 2. Ground rules

- **Never commit secrets.** `~/.config/opencode` on the owner's machine holds
  real API keys and is intentionally not bundled.
- **Never commit `~/.local/share` app state**, browser profiles, Spotify state,
  or wallpapers (separate 450 MB repo).
- **Do not "fix" the trailing comma** in `.config/waybar/modules` (~line 22).
  It is pre-existing upstream JSONC, waybar parses it fine, and strict `json`
  parsers complain. Changing it silently creates diff noise.
- **The bar config is JSONC but `config.jsonc` on disk may be a different file.**
  The installer symlinks `~/.config/waybar/config` →
  `.config/waybar/configs/[TOP] wallust_new` in the repo checkout. A machine
  where `~/.config/waybar/config` is missing will silently fall back to
  `config.jsonc` and the whole bar layout changes. `repair_symlink()` in
  `install.sh` (~line 676) exists for this.
- Keep `.conf` and `.lua` Hyprland trees **in step**. Hyprland 0.57+ ignores
  `.conf` entirely.
- The owner is a self-described beginner. Prefer explicit commands and short
  explanations over clever one-liners.

---

## 3. Repo map

```
install.sh                     the whole installer, 1129 lines, bash
apps.list                      extra packages, one per line, "aur:" prefix
INSTALL.md                     user-facing docs (install, GPU, Lua, music panel)
README.md                      short GitHub landing page
.config/
  hypr/                        .conf tree (Hyprland <= 0.56)
    scripts/WaybarMusic.sh     cava visualizer for the bar music module
    scripts/WaybarCava.sh      upstream's generic cava script (unused by this bar)
    UserConfigs/Startup_Apps.conf    autostarts `qs -n -c hyprlust-music &`
    UserConfigs/UserKeybinds.conf    SUPER+SHIFT+I toggles the panel
  hypr-lua/                    .lua tree (Hyprland 0.57+), same content
    UserConfigs/Startup_Apps.lua
    UserConfigs/UserKeybinds.lua
  quickshell/hyprlust-music/
    shell.qml                  the dock-attached now-playing panel (~750 lines)
  waybar/
    configs/[TOP] wallust_new  active bar layout  <- edit modules-* arrays here
    modules                    all module definitions (JSONC, includes ~)
    style/[Dark] Purpl.css     bar styling
.local/bin/
  hyprlust-lyrics              LRCLIB lookup, prints JSON
  hyprlust-palette             wallust CSS -> panel palette JSON
.themes/, .zsh/, .zshrc        upstream leftovers, kept for parity
```

Note the odd upstream filenames: `[TOP] wallust_new`, `[Dark] Purpl.css`.
Everywhere in `install.sh` they appear with **quoting**; do not unquote them.

---

## 4. Installer architecture (`install.sh`)

Single bash file, no external deps beyond Arch base + `sudo`. Key functions:

| Function | Line | Job |
|---|---|---|
| `info/warn/run` | 43–56 | logging; `run` respects `DRY_RUN` |
| `ensure_path_line` | 57 | idempotent shell-profile edits |
| `_detect_gpu` | 105 | `lspci` → `/sys/class/drm` fallback; returns vendor set |
| `read_apps_list` | 239 | parses `apps.list`, splits `aur:` |
| `clone_or_update` | 396 | fork-only clone; fetches `apps.list` alone on first run |
| `deploy_pypr_config` | 496 | pyprland |
| `deploy_music_panel` | 516 | QML dir, helper scripts, `WaybarMusic.sh`, wallust hook |
| `backup_and_place` | 584 | `~/.config` deploy with timestamped backup |
| `repair_symlink` | 676 | fixes upstream's `/home/hypr/...` symlinks |
| `_has_vendor` etc. | 851–890 | GPU env-var management |

Behavioural invariants:

- **Idempotent.** Safe to re-run; that is the normal update path.
- **`--dry-run`** must print what it *would* do and change nothing.
- **Backup** to `~/.config-backup-<YYYYmmdd-HHMMSS>/` before replacing files.
- **Fork-only clone**: it deploys *this* repo, not upstream's (upstream is only
  referenced for provenance).
- AUR work is **batched into a single helper invocation** — a full run in a VM
  took ~39 min and AUR rebuilds dominated it. Prefer `-bin` packages
  (`qimgv`, `vm-curator-bin`, `sptlrx-bin`).
- `yay` has **no `--cleanafter` flag**; do not re-add it.
- All 11 upstream scripts are patched `swww` → `awww` post-deploy. Keep the
  rename literal: `-o` is `--outputs` and still valid, but there is **no**
  `--output` flag.

Deployment is "copy the desktop configs, skip app caches". `~/.config` upstream
is 128 MB; only real config is deployed.

---

## 5. Hard-won constraints

### Hyprland

- **0.57 removed the legacy `.conf` loader.** Installer branches on
  `hyprland --version` and deploys `.lua` for 0.57+, `.conf` for ≤0.56
  (`hyprland.conf` is then renamed `hyprland.conf.legacy`).
- Lua sandbox quirks: no `HOME` global → `os.getenv("HOME")`;
  `require("configs.X")` not `require("_configs.X")`.
- Invalid/removed keys that already caused silent breakage:
  `xf86AudioPlayPause` (not a keysym), `$mainMod_L` (never defined, meant
  `Super_L`), `pseudotile`, `explicit_sync`, `explicit_sync_kms`, `vfr`,
  `workspace_swipe`, `workspace_swipe_fingers`.
- Verify with `Hyprland --verify-config`, which should print `config ok`.

### Waybar

- Active bar: `.config/waybar/configs/[TOP] wallust_new`
  — `height: 34`, `width: 1200`, `fixed-center: true`, `include:
  ["~/.config/waybar/modules"]`.
- Live geometry measured on a 1920×1080 output: bar at x=360, y=59,
  w=1200 → **right edge = 1560**. The music panel is positioned from this:
  `margins.right = (screen.width - 1200) / 2 + 8`.
- **This bar has no network module.** `modules-right` is
  `[custom/music, idle_inhibitor, group/demo, group/hub, custom/power]`;
  `group/demo` = `[tray, pulseaudio, mpris]`. `group/network` /
  `group/connection` exist in `modules` but are not instantiated here. Any
  instruction like "put X left of the network tab" therefore cannot be
  satisfied literally on this layout — resolve by asking, or by treating the
  audio/mpris group as the reference point.
- `custom/theme-switcher` has no definition (waybar logs a warning) and
  `UserScripts/Weather.py` is absent. Both are **pre-existing upstream
  breakage**, not this fork's bug.

### Quickshell (this is where most time was lost)

- Only `PanelWindow` children of `ShellRoot` create layer surfaces.
- Anchors to a sibling work only for `top`/`bottom`/`left`/`right`;
  `anchors.verticalCenter: someItem` fails.
- `font.pixelSize` must be an **integer**; fractional values fail.
- `pathSvg` needs an explicit `import QtQuick.Shapes`.
- `FileView` signals `onLoaded`, not `onFileChanged`.
- Test harness that lets you run the panel without touching `~/.config`:

  ```bash
  mkdir -p /tmp/opencode/qsconf/quickshell/hyprlust-music
  cp .config/quickshell/hyprlust-music/shell.qml \
     /tmp/opencode/qsconf/quickshell/hyprlust-music/shell.qml
  export XDG_CONFIG_HOME=/tmp/opencode/qsconf
  qs -c hyprlust-music &            # then IPC works by name
  qs ipc -c hyprlust-music call music toggle
  ```

- MPRIS: `position` is not pushed. Poll `player.positionChanged()` and then
  read `player.position`. Capability flags are `canTogglePlaying`,
  `canGoNext`, `canGoPrevious`, `canSeek`.
- Glyphs confirmed present in JetBrainsMono Nerd Font / Symbols Nerd Font:
  `md-volume_minus` U+F075E, `md-skip_previous` U+F04AE, `md-pause` U+F03E4,
  `md-play` U+F040A, `md-skip_next` U+F04AD, `md-volume_high` U+F057E,
  `md-music` U+F075A, `md-equalizer` U+F0EA2, `fa-music` U+F001.

### Music panel design contract

The owner rejected a Material You version by name. Do **not** reintroduce:

- pill-shaped/filled tonal buttons
- a light/filled primary button
- Material surfaces/elevation

Target look, derived from `~/.config/quickshell/rice-desktop/Card.qml`:

- radius **26**, fill `rgba(0.10, 0.10, 0.115, 0.46)`, 1px white at 0.10 alpha
- **JetBrainsMono Nerd Font** for icons and mono text, **Inter** / Google Sans
  Flex for UI text
- flat 44px transparent transport buttons, border + accent only on hover
- no dimmed backdrop; closes on outside click, `Escape`, the bar icon, or
  `SUPER+SHIFT+I`
- dock-attached dropdown, **not** a floating popup: anchored under the bar's
  right end, ~384 wide, starts **closed**

---

## 6. What is shipped and verified

- Full install completed end-to-end once (39m01s, VM, llvmpipe).
- Desktop deployed; backup at `~/.config-backup-20261120-023400`.
- 11 scripts patched `swww` → `awww`; Mesa/software rendering path works in VMs.
- Waybar symlink repair, `/home/hypr` path rewrite, GPU detection all exercised.
- Lua tree passes `Hyprland --verify-config`.
- Music panel: opens/closes via IPC, correct layer placement
  (`x=1168 y=46 384x392`), MPRIS + LRCLIB lyrics + Pipewire volume functional,
  closed by default.
- Native restyle landed and screenshots clean: no QML errors on load.

---

## 7. Open work (start here)

These are real defects, reproduced on this checkout. Fix in this order.

### 7.1 `WaybarMusic.sh` cannot run — no executable bit

```
-rw-r--r-- .config/hypr/scripts/WaybarMusic.sh
```

Waybar logs `Permission denied` on every tick and the module stays empty.
`install.sh` deploys with `install -Dm755`, so **installed** copies are fine,
but the repo file itself must be `chmod +x` so a plain `git clone` and any
in-place testing work:

```bash
git update-index --chmod=+x .config/hypr/scripts/WaybarMusic.sh
```

### 7.2 `"interval": 0.1` fights the script

`custom/music` is defined as:

```jsonc
"exec": "~/.config/hypr/scripts/WaybarMusic.sh",
"format": "{}",
"interval": 0.1,
```

Waybar **kills and re-runs** `exec` each interval, so a long-running `cava`
pipe is torn down 10×/s and never emits. Correct pattern (see
`WaybarCava.sh`): omit `interval` entirely and let the script stream JSON lines
forever, or set `"interval": "once"` and drive updates with `RTMIN+<n>` signals.

The script also never detects "no player": cava outputs silence as `0`s, and
the match patterns (`*"0 0 0 0 0 0 0 0"*`) are fragile — an all-zero frame with
8 bars and no trailing separator may not match. Prefer checking
`playerctl status 2>/dev/null` for the idle glyph and only rendering bars when
`Playing`.

### 7.3 Workspace 5 icon is wrong

`.config/waybar/modules`, `hyprland/workspaces#4` → `format-icons`:

```jsonc
"5": "",     // U+F04B  fa-play  <- wrong, and missing the trailing space
```

Wanted: a **music** glyph matching the others' rhythm. Siblings 1–4 are
`"\uf120 "`, `"\uf269 "`, `"\uf07c "`, `"\uf2c6 "` (glyph + one space).
Use `"5": "\uf001 "` (`fa-music`) — verified present in the fonts.

`persistent-workspaces` already contains `"5": []`, so once the icon is right
the fifth icon renders.

### 7.4 Bar placement not confirmed

`custom/music` is currently **first** in `modules-right`, i.e. the leftmost
item of the right group — not "left of the network tab", because this layout
has no network module (see §5). Decide the real reference point, place the
module there, `pkill waybar; waybar &`, and confirm with a screenshot rather
than by reading the config.

### 7.5 Styling for the new module is missing

`custom/music` emits `class: "music-viz"` and `class: "music-idle"`, and
`.config/waybar/style/[Dark] Purpl.css` has **no** rules for either. Add them
in the bar's existing idiom (mono font, no pill background, accent on hover).

### 7.6 Docs drift

`INSTALL.md` §Music panel documents the panel and its files but not
`WaybarMusic.sh`, the visualizer, workspace 5, or the `Permission denied`
gotcha. Update once 7.1–7.5 are settled.

---

## 8. Test recipes

**Waybar config without touching the live bar:**

```bash
mkdir -p /tmp/opencode/wbcheck
cp ".config/waybar/configs/[TOP] wallust_new" /tmp/opencode/wbcheck/config
sed -i 's#~/.config/waybar/modules#'"$PWD"'/.config/waybar/modules#' \
        /tmp/opencode/wbcheck/config
timeout 8 waybar -c /tmp/opencode/wbcheck/config 2>&1 | grep -v '\[info\]'
```

`Permission denied` / `No such file` lines from *other* modules are expected
noise on a machine that is not the target.

**Music panel:**

```bash
export XDG_CONFIG_HOME=/tmp/opencode/qsconf
qs -c hyprlust-music >/tmp/opencode/qs.log 2>&1 &
sleep 3
qs ipc -c hyprlust-music call music toggle
hyprctl -j layers | python3 -m json.tool | grep -A6 music
grim -g "1130,30 440x420" /tmp/opencode/panel.png
```

Check `qs.log` for `error`, `failed`, `cannot assign`, `ReferenceError`
(ignore `textinput` warnings). A clean load prints nothing.

**JSON sanity** (remember §2, the modules file is JSONC):

```bash
python3 - <<'EOF'
import json, re
s = open('.config/waybar/modules').read()
t = re.sub(r'/\*.*?\*/', '', s, flags=re.S)
t = re.sub(r'//[^\n]*', '', t)
try: json.loads(t); print('VALID')
except Exception as e: print('BROKEN:', e)   # trailing comma expected, nothing else
EOF
```

**Lua config:** `Hyprland --verify-config` → must print `config ok`.

---

## 9. Release loop

There is no CI. The update path is:

```bash
git add -A
git commit -m "<what changed>"
git push origin master          # owner's credentials; no credential helper set

# on the target machine
bash -c "$(curl -fsSL https://raw.githubusercontent.com/ro3in/Hyprlust/master/install.sh)"
pkill waybar; waybar &
```

Always `-- --dry-run` first when changing package lists or deploy paths.

The owner's real machine is **CachyOS, GTX 1650**; the 39-minute verification
run was a GPU-less VM using `llvmpipe`. Behaviour that depends on a GPU
(hyprland blur, animations, `awww` transitions) has not been verified on real
hardware.

---

## 10. Known gaps that are *intentional*

- No wallpapers bundled (link in `README.md`).
- `spicetify`, `Seanime`, `Upscayl` not installed (large app state).
- `ags` disabled — upstream's `exec-once` line is a leftover; waybar is the bar
  actually used.
- No bootloader / kernel / LUKS / disk setup. This is not a bootstrapper.
- Browser profiles and `~/.config/opencode` are per-machine, never deployed.

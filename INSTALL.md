# dotfiles — Hyprlust, fish edition

Arch Linux installer + fish shell config for
[NischalDawadi/Hyprlust](https://github.com/NischalDawadi/Hyprlust), converted
from zsh to fish.

## Install

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/ro3in/Hyprlust/master/install.sh)"
```

Preview what it will do without changing anything:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/ro3in/Hyprlust/master/install.sh)" -- --dry-run
```

## What it does

1. Checks you are a normal user on an Arch-based system with `sudo`.
2. Installs the official-repo packages Hyprlust actually needs.
3. Installs your own app list from [`apps.list`](apps.list).
4. Installs an AUR helper (yay) if you have neither yay nor paru, then the
   optional AUR packages (pyprland, wallust, wlogout, …).
5. Clones upstream Hyprlust and this repo.
6. Deploys `config.fish` plus the desktop configs, backing up anything it
   replaces to `~/.config-backup-<timestamp>/`.
7. Installs the [music panel](#music-panel) and its helper scripts.
8. Repairs the broken absolute symlinks upstream ships.
9. Adapts Hyprlust's `swww` calls to `awww`.
10. Rewrites hardcoded `/home/hypr` paths to your `$HOME`.
11. Detects your GPU and installs/verifies the matching drivers (NVIDIA, AMD,
    or Intel), including hybrid setups.
12. Enables NetworkManager and Bluetooth, offers to switch your shell to fish.

## Your own apps: `apps.list`

Everything you want on **every** machine lives in one editable file at the repo
root: [`apps.list`](apps.list). Delete the lines you don't want, add the ones
you do, then run the installer.

```
kitty                 # from the official repos
aur:vm-curator        # AUR only — prefix with "aur:"
```

- `#` starts a comment, blank lines are ignored.
- Names are plain package names, one per line.
- **Do not** add kernels, GPU drivers, bootloader or LUKS packages. The
  installer detects the GPU itself, and boot/disk setup differs per machine.
- Anything already in Hyprlust's own list is not installed twice.

The list is read on a first run too: the installer fetches just that one small
file from the repo when the checkout isn't on disk yet.

### Bundled app configs

These configs are deployed to `~/.config/` along with the desktop:

| App | Config |
|---|---|
| `micro` | `micro/` (catppuccin + syntax files) |
| `qimgv` | `qimgv/` |
| `easyeffects` | `easyeffects/` (EQ / effects chains) |
| `vm-curator` | `vm-curator/` (`__HOME__` is expanded on install) |

Deliberately **not** bundled: browser profiles (`helium`, `chrome`, `firefox`),
`~/.config/opencode` (holds API keys), Spotify/Spicetify state, and any
`~/.local/share` app data. Those are per-machine state, not configuration.

## Music panel

`SUPER + SHIFT + I` opens a now-playing popup:

- cover art, title, artist and album of whatever is playing
- synced lyrics from [LRCLIB](https://lrclib.net) (free, no key; falls back to
  plain text, then to "no lyrics for this one")
- draggable progress bar and play/pause/previous/next
- colours taken from the current wallpaper, refreshed on every change

It controls **any** MPRIS player — Spotify, Helium, Firefox, mpv, VLC — so it
does not depend on MPD being set up.

It is a small [Quickshell](https://quickshell.org) config, deliberately built in
the rice's own visual language: 6px corners, a 2px wallpaper-accent border,
translucent background, mono font, flat buttons. Nothing Material You.

| File | Purpose |
|---|---|
| `~/.config/quickshell/hyprlust-music/shell.qml` | the panel |
| `~/.local/bin/hyprlust-lyrics` | LRCLIB lookup, prints JSON |
| `~/.local/bin/hyprlust-palette` | turns wallust's CSS into the panel's palette |
| `~/.cache/hyprlust/colors.json` | generated palette (rewritten per wallpaper) |

`hyprlust-palette` is appended to `WallustSwww.sh` on install, so the panel
follows wallpaper changes like the rest of the desktop.

If the panel does not appear, check that it is running and that its target is
registered:

```fish
qs list --all
qs ipc -c hyprlust-music show
```


## Differences from upstream

| | upstream Hyprlust | this fork |
|---|---|---|
| Shell | zsh + oh-my-zsh | **fish** (native syntax, fisher plugins) |
| Wallpaper daemon | `swww` | `awww` (swww's successor), scripts patched |
| Config deployment | copies all 128 MB of `~/.config` | only desktop configs, no app caches |
| Broken symlinks | `waybar/config` → `/home/hypr/...` | repaired to real in-repo files |
| Hardcoded paths | `/home/hypr` | rewritten to `$HOME` |
| Animations | slow slides (~7s windows, 10s fade) | **DarkShadow's**: fast pop-in windows (2.5s), fading layers |
| Window rules | upstream's set | upstream + DarkShadow's float/centre utilities |

### Animations and window rules

The animation block in `UserConfigs/UserSettings` was replaced with the values
from DarkShadow's Shell, so this rice moves the way that setup did: windows pop
in quickly at 2.5s with a `quick` curve, layers fade, workspaces slide.

Window rules carried over from DarkShadow:

- ignore maximize requests from every app
- XWayland drag fix
- float + centre for `zenity`, `gsimplecal`, `nmtui`, Overskride and Waypaper
- `hyprland-run` parks at the bottom of the screen
- no animation on the screenshot selection layer
- blur for the on-screen display (`swayosd`)
- waybar tooltips blurred with a 0.2 alpha floor

Both config trees are kept in step: `UserConfigs/UserSettings.conf` and
`.config/hypr-lua/UserConfigs/UserSettings.lua`, likewise the `WindowRules`
pair.

## Requirements

- Arch Linux or an Arch-based distro (EndeavourOS, CachyOS, …)
- A regular user with sudo
- An existing booting system — this is not a bootstrapper

## Notes

- **Hyprland 0.57+**: handled. Hyprland 0.55 introduced Lua configs and **0.57
  removed the legacy `.conf` loader entirely**, so Hyprlust's original
  `hyprland.conf` tree is ignored on a current install and the compositor falls
  back to an autogenerated default — no waybar, no keybinds, no theme. This fork
  ships a converted Lua tree (`.config/hypr-lua/`) and the installer picks the
  right format by reading `hyprland --version`:

  | Hyprland | Deployed |
  |---|---|
  | 0.57+ | `.lua` tree; old `hyprland.conf` moved to `hyprland.conf.legacy` |
  | ≤ 0.56 | the original `.conf` tree, unchanged |

  The conversion used [hyprlang2lua](https://github.com/EIonTusk/hyprlang2lua)
  and was then verified with `Hyprland --verify-config`, which reports
  `config ok`. Real problems found and fixed on the way:

  - `HOME` is not a global in Hyprland's Lua sandbox → `os.getenv("HOME")`
  - `require("_configs.Settings")` → `require("configs.Settings")`, since
    `package.path` starts at the top-level config's own directory
  - `xf86AudioPlayPause` is not a valid keysym — upstream's bind never worked
  - `$mainMod_L` was never defined upstream; the intent was `Super_L`
  - settings removed in 0.57 dropped: `pseudotile`, `explicit_sync`,
    `explicit_sync_kms`, `vfr`, `workspace_swipe`, `workspace_swipe_fingers`
  - upstream's duplicate `(copy 1)` / `(copy 2)` configs are not deployed,
    since loading them would double-apply window rules

- **GPU support**: automatic, for all three vendors. The installer detects your
  GPU(s) from `lspci` (falling back to `/sys/class/drm` in VMs) and configures
  only the vendor actually present:

  | GPU | What happens |
  |---|---|
  | **NVIDIA** | Verifies `nvidia-utils`, checks `nvidia_drm.modeset=1`, uncomments the GBM/GLX/`NVD_BACKEND` vars, enables the suspend/resume services |
  | **AMD** | Installs `mesa vulkan-radeon libva-mesa-driver mesa-vdpau`, sets `AMD_VULKAN_ICD=RADV` |
  | **Intel** | Installs `mesa vulkan-intel intel-media-driver`, sets `LIBVA_DRIVER_NAME=iHD` |

  Hybrid laptops (AMD or Intel iGPU + NVIDIA discrete) are detected and handled
  differently on purpose: the iGPU drives the panel, so the installer **does
  not** apply NVIDIA's `GBM_BACKEND`/`__GLX_VENDOR_LIBRARY_NAME` variables —
  doing so breaks compositing. Per-app offload stays available via
  `__NV_PRIME_RENDER_OFFLOAD=1 <app>`. On Intel hybrids `LIBVA_DRIVER_NAME=iHD`
  wins over `nvidia`, since the iGPU does the video decode.

  If `nvidia_drm.modeset` is off, it prints the exact kernel parameter to add
  rather than letting you reboot into a black screen.

  32-bit graphics libraries (Steam/Wine) are installed when the `multilib` repo
  is enabled, and silently skipped when it is not.

- **VMs**: works, but slowly. VMware SVGA, virtio-gpu and QXL match no physical
  vendor, so the installer falls back to Mesa's software renderer (`llvmpipe`):
  it installs `mesa` + `libva-mesa-driver` if missing and enables
  `WLR_RENDERER_ALLOW_SOFTWARE=1`. Expect a usable but sluggish desktop — this
  is CPU rendering, not a GPU. For a smoother test, give the VM several cores
  and enable 3D acceleration / virtio-gpu with `venus` if your hypervisor
  supports it.
- **Wallpapers** live in a separate 450 MB repo and are not downloaded
  automatically. `git clone --depth=1 https://github.com/NischalDawadi/Wallpapers ~/Pictures/wallpapers`
- **Monitor config**: edit `~/.config/hypr/UserConfigs/Monitors.conf` before
  your first login.
- Not installed on purpose: spicetify, Seanime, Upscayl (app state, ~100 MB),
  and `ags` (a leftover `exec-once` line upstream; the waybar bar is the one
  actually used).

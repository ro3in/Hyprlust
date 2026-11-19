-- /* ---- 💫 https://github.com/JaKooLit 💫 ---- */  #
-- Personal app launchers, mirrored from Roland's DarkShadow's Shell user.lua
-- (which is loaded last there and wins over everything else).
--
-- His old bats called DarkShadow-specific helpers; browser and app keys here
-- call the programs directly so they work on a fresh Hyprlust install.

local mainMod = "SUPER"
local scriptsDir = os.getenv("HOME") .. "/.config/hypr/scripts"
local UserScripts = os.getenv("HOME") .. "/.config/hypr/UserScripts"

-- ---------------------------------------------------------------------------
-- Apps (mirrors his user.lua)
-- ---------------------------------------------------------------------------
-- SUPER+B  Chrome with the same Wayland/VA-API flags he uses
hl.bind(mainMod .. " + B", hl.dsp.exec_cmd(
    "google-chrome-stable --ozone-platform=wayland " ..
    "--enable-features=AcceleratedVideoDecodeLinuxGL,AcceleratedVideoDecodeLinuxZeroCopyGL,VaapiOnNvidiaGPUs,VaapiIgnoreDriverChecks " ..
    "--disable-features=UseChromeOSDirectVideoDecoder"
))
-- SUPER+H  Helium browser (same as his helium-browser key)
hl.bind(mainMod .. " + H", hl.dsp.exec_cmd("helium-browser"))
-- SUPER+G  Chrome, as he had it in user.lua (gamebar moved to SUPER+SHIFT+G)
hl.bind(mainMod .. " + G", hl.dsp.exec_cmd(
    "google-chrome-stable --ozone-platform=wayland " ..
    "--enable-features=AcceleratedVideoDecodeLinuxGL,AcceleratedVideoDecodeLinuxZeroCopyGL,VaapiOnNvidiaGPUs,VaapiIgnoreDriverChecks " ..
    "--disable-features=UseChromeOSDirectVideoDecoder"
))
-- CTRL+SHIFT+Escape  system monitor (was missioncenter)
hl.bind("CTRL + SHIFT + Escape", hl.dsp.exec_cmd("missioncenter"))

-- ALT+TAB / ALT+SHIFT+TAB  window switcher. DarkShadow's rice-taskview is not
-- part of Hyprlust, so these cycle windows instead of opening its switcher.
hl.bind("ALT + tab", hl.dsp.window.cycle_next({ next = true }))
hl.bind("ALT + SHIFT + tab", hl.dsp.window.cycle_next({ next = false }))

-- SUPER+TAB  task overview. Hyprlust has no expo/taskview plugin (upstream's
-- version was ags, which is deliberately not installed), so this opens the
-- same window cycler instead of leaving the key dead.
hl.bind(mainMod .. " + tab", hl.dsp.window.cycle_next({ next = true }))

-- SUPER+F10/F11/F12  volume mute/down/up, as in his hyprland.lua
hl.bind("SUPER + F12", hl.dsp.exec_cmd(scriptsDir .. "/Volume.sh --inc"),    { locked = true })
hl.bind("SUPER + F11", hl.dsp.exec_cmd(scriptsDir .. "/Volume.sh --dec"),    { locked = true })
hl.bind("SUPER + F10", hl.dsp.exec_cmd(scriptsDir .. "/Volume.sh --toggle"), { locked = true })

-- ---------------------------------------------------------------------------
-- Hyprlust extras kept on keys he does not use
-- ---------------------------------------------------------------------------
-- SUPER+D is the launcher in Hyprlust; he used SUPER+R for rofi, so keep D too
-- (both open the same app launcher).
hl.bind(mainMod .. " + D", hl.dsp.exec_cmd("rofi -show drun -modi drun,filebrowser,window"))
-- SUPER+SHIFT+Return  pyprland dropdown terminal
hl.bind(mainMod .. " + SHIFT + Return", hl.dsp.exec_cmd("pypr toggle term"))
-- SUPER+Z  pypr zoom
hl.bind(mainMod .. " + Z", hl.dsp.exec_cmd("pypr zoom"))
-- SUPER+SHIFT+I  the Hyprlust music panel (Quickshell)
hl.bind(mainMod .. " + SHIFT + I", hl.dsp.exec_cmd("qs ipc -c hyprlust-music call music toggle"))
hl.bind(mainMod .. " + ALT + R", hl.dsp.exec_cmd(scriptsDir .. "/Refresh.sh"))
hl.bind(mainMod .. " + ALT + E", hl.dsp.exec_cmd(scriptsDir .. "/RofiEmoji.sh"))
-- SUPER+ALT+F  float every window. The old hyprlang `workspaceopt allfloat`
-- has no Lua equivalent (and `hyprctl dispatch workspaceopt ...` fails under
-- Lua configs, since dispatch now evaluates Lua), so use the dispatcher.
hl.bind(mainMod .. " + ALT + F", hl.dsp.window.float({ action = "all" }))

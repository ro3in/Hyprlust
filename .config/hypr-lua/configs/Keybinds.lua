-- /* ---- 💫 https://github.com/JaKooLit 💫 ---- */  #
-- Keybinds, mirrored from Roland's DarkShadow's Shell setup.
--
-- Every key below is one he actually uses today. Where his old key ran a
-- `rice-*` binary from DarkShadow's Shell (which Hyprlust does not ship), it is
-- wired to the Hyprlust script that does the same job, so the muscle memory
-- carries over on a fresh install.
--
-- Dropped because Hyprlust has no equivalent and the bind would be dead:
--   SUPER+A dashboard, SUPER+TAB taskview, SUPER+F infinite desktop,
--   SUPER+X tools, SUPER+ALT+D dashboard, SUPER+ALT+W widget editor,
--   SUPER+SHIFT+G gamebar, SUPER+B/D keys Hyprlust frees for its own use.

local mainMod = "SUPER"

-- Default
local scriptsDir = os.getenv("HOME") .. "/.config/hypr/scripts"
local configs = os.getenv("HOME") .. "/.config/hypr/configs"
-- User
local UserConfigs = os.getenv("HOME") .. "/.config/hypr/UserConfigs"
local UserScripts = os.getenv("HOME") .. "/.config/hypr/UserScripts"

-- ---------------------------------------------------------------------------
-- Terminal, launcher and session
-- ---------------------------------------------------------------------------
-- SUPER+Q closes a window, so the terminal opens on SUPER+Return and SUPER+T
-- (Roland's own override in DarkShadow's Shell was terminal=SUPER + T).
hl.bind(mainMod .. " + Return", hl.dsp.exec_cmd("kitty"))
hl.bind(mainMod .. " + T", hl.dsp.exec_cmd("kitty"))

-- rofi launcher. Roland used SUPER+R for the launcher and ALT+Space as a
-- second launcher; both keep working here.
hl.bind(mainMod .. " + R", hl.dsp.exec_cmd("rofi -show drun -modi drun,filebrowser,window"))
hl.bind("ALT + Space", hl.dsp.exec_cmd("rofi -show drun -modi drun,filebrowser,window"))

-- SUPER+L locks; the old rice-ctl power menu lives on CTRL+ALT+P (wlogout).
hl.bind(mainMod .. " + L", hl.dsp.exec_cmd(scriptsDir .. "/LockScreen.sh"))
hl.bind(mainMod .. " + M", hl.dsp.exec_cmd(scriptsDir .. "/Wlogout.sh"))
hl.bind("CTRL + ALT + P", hl.dsp.exec_cmd(scriptsDir .. "/Wlogout.sh"))
hl.bind("CTRL + ALT + L", hl.dsp.exec_cmd(scriptsDir .. "/LockScreen.sh"))

-- ---------------------------------------------------------------------------
-- Windows and focus
-- ---------------------------------------------------------------------------
hl.bind(mainMod .. " + Q", hl.dsp.window.close())
hl.bind(mainMod .. " + C", hl.dsp.window.close())
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd("thunar"))
hl.bind(mainMod .. " + P", hl.dsp.window.pseudo())
hl.bind(mainMod .. " + J", hl.dsp.layout("togglesplit"))
hl.bind(mainMod .. " + SHIFT + V", hl.dsp.window.float({ action = "toggle" }))

hl.bind(mainMod .. " + left",  hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + up",    hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + down",  hl.dsp.focus({ direction = "down" }))

hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }))
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Workspaces: SUPER+[0-9] focuses, SUPER+SHIFT+[0-9] moves the window.
for i = 1, 10 do
    local key = i % 10
    hl.bind(mainMod .. " + " .. key,         hl.dsp.focus({ workspace = i }))
    hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
end

hl.bind(mainMod .. " + S",         hl.dsp.workspace.toggle_special("magic"))
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.window.move({ workspace = "special:magic" }))

-- ---------------------------------------------------------------------------
-- Shell features (DarkShadow's Shell -> Hyprlust equivalents)
-- ---------------------------------------------------------------------------
-- SUPER+W  wallpaper picker (was the Quickshell hyprquickpaper menu)
hl.bind(mainMod .. " + W", hl.dsp.exec_cmd(UserScripts .. "/WallpaperSelect.sh"))
-- SUPER+V  clipboard history (was rice-clip; Hyprlust uses cliphist + rofi)
hl.bind(mainMod .. " + V", hl.dsp.exec_cmd(scriptsDir .. "/ClipManager.sh"))
-- SUPER+N  control center (was rice-cc; swaync ships with Hyprlust)
hl.bind(mainMod .. " + N", hl.dsp.exec_cmd("swaync-client -t -sw"))
-- SUPER+U  settings (was rice-settings; nwg-look is the GTK/theme tool)
hl.bind(mainMod .. " + U", hl.dsp.exec_cmd("nwg-look"))
-- SUPER+slash  every key on one sheet (was rice-keymap show)
hl.bind(mainMod .. " + slash", hl.dsp.exec_cmd(scriptsDir .. "/KeyHints.sh"))
-- SUPER+G  game mode (Roland's own override was gamebar on SUPER+SHIFT+G)
hl.bind(mainMod .. " + SHIFT + G", hl.dsp.exec_cmd(scriptsDir .. "/GameMode.sh"))

-- ---------------------------------------------------------------------------
-- Screenshots and recording
-- ---------------------------------------------------------------------------
hl.bind("Print",             hl.dsp.exec_cmd(scriptsDir .. "/ScreenShot.sh --area"))
hl.bind("SHIFT + Print",     hl.dsp.exec_cmd(scriptsDir .. "/ScreenShot.sh --now"))
hl.bind(mainMod .. " + Print", hl.dsp.exec_cmd(scriptsDir .. "/ScreenShot.sh --swappy"))
hl.bind(mainMod .. " + SHIFT + R", hl.dsp.exec_cmd(UserScripts .. "/recorder.sh"))

-- ---------------------------------------------------------------------------
-- Media, volume, brightness, microphone
-- ---------------------------------------------------------------------------
hl.bind("XF86AudioNext",  hl.dsp.exec_cmd(scriptsDir .. "/MediaCtrl.sh --nxt"),  { locked = true })
hl.bind("XF86AudioPrev",  hl.dsp.exec_cmd(scriptsDir .. "/MediaCtrl.sh --prv"),  { locked = true })
hl.bind("XF86AudioPlay",  hl.dsp.exec_cmd(scriptsDir .. "/MediaCtrl.sh --pause"), { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd(scriptsDir .. "/MediaCtrl.sh --pause"), { locked = true })

hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd(scriptsDir .. "/Volume.sh --inc"),        { locked = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd(scriptsDir .. "/Volume.sh --dec"),        { locked = true })
hl.bind("XF86AudioMute",        hl.dsp.exec_cmd(scriptsDir .. "/Volume.sh --toggle"),     { locked = true })
hl.bind("XF86AudioMicMute",     hl.dsp.exec_cmd(scriptsDir .. "/Volume.sh --toggle-mic"), { locked = true })
hl.bind("ALT + bracketright",   hl.dsp.exec_cmd(scriptsDir .. "/Volume.sh --inc"),        { locked = true })
hl.bind("ALT + bracketleft",    hl.dsp.exec_cmd(scriptsDir .. "/Volume.sh --dec"),        { locked = true })

hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd(scriptsDir .. "/Brightness.sh --inc"), { locked = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd(scriptsDir .. "/Brightness.sh --dec"), { locked = true })

# dmgbuild settings for the Codogotchi installer DMG.
#
# Builds the styled drag-to-install window (cloud background + "SIMPLY DRAG"
# arrow + enlarged, pinned icons) by writing the .DS_Store directly. This is
# AppleScript-free on purpose: Finder's `set background picture` property is
# broken on recent macOS (returns -10000), so the classic osascript dance no
# longer paints the background. dmgbuild sidesteps Finder entirely.
#
# Invoked as:
#   dmgbuild -s scripts/dmg-settings.py \
#     -D app=<path/to/Codogotchi.app> -D assets=<repo>/assets/dmg \
#     "Codogotchi" <out.dmg>

import os.path

app = defines["app"]
assets = defines["assets"]

# --- Contents ---------------------------------------------------------------
files = [app]
symlinks = {"Applications": "/Applications"}

# Mounted-disk icon (optional).
_volicon = os.path.join(assets, "VolumeIcon.icns")
if os.path.exists(_volicon):
    icon = _volicon

# --- Window + layout --------------------------------------------------------
# Geometry from the frame edges measured in the background art (1618x972 ->
# 805x488 logical). Frame centres: left x=201, right x=603 (each ~161x156).
# Icons sit high in each box so the Finder label drops onto the brushstroke
# "smudge" at logical y~298 (white label text in Dark Mode, matching the mockup).
# HiDPI TIFF (805x488 @1x + 1610x976 @2x) so Finder scales the art into the
# logical window instead of showing it 1:1 (which only reveals a corner).
background = os.path.join(assets, "background.tiff")

format = "UDZO"
# The DMG background is drawn top-anchored. package-dmg.sh extends it to ~520pt
# tall (cloud bleed below the boxes) so it always covers the content area no
# matter which Finder bars the viewer hides -- never a white strip. Outer height
# 546 = ~486 content (tab + path bars hidden... err, *shown* for the common
# case) + ~60pt chrome (32pt title + 28pt path bar). The boxes are pinned ~243pt
# from the top, so they read centred in the common case and drift at most ~15pt
# when the chrome differs. Width stays 805 to keep icon x-coordinates valid.
window_rect = ((200, 120), (805, 546))
icon_size = 116
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
arrange_by = None

icon_locations = {
    os.path.basename(app): (201, 219),  # Codogotchi.app -> left frame
    "Applications": (606, 219),         # Applications  -> right frame
}

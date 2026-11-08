# App icon

Board: `AppIcon` (canvas row "Design system"; its images in `../canvas/icon/`). Generator: `studio/tool/app_icon/` (`icon.py` mark and palettes, `compose.py` per-platform layouts, `build.py` writes the files). The board wins for how it looks; this spec says how it is made and where each file goes.

## The mark
- Five nodes on the wyrm's arc, the same mark as the log-in screen: centres and radii in a 220×130 box, `(20,85,14) (65,45,17) (115,30,20) (165,55,17) (200,100,14)`. The middle node is the head: a filled ball with a highlight. The other four are rings with the background showing through.
- A thin spine joins them (`SPINE` in `icon.py`), cut under every node by a mask so it never shows through a ring.
- **Small mark** (an icon ≤ 32 px, iOS ≤ 40 px): three nodes `(35,82,22) (110,42,30) (185,82,22)`, stroke 13 instead of 8.4, no spine. Five rings at 16 px merge into one smudge; three still read as an arc.
- One soft drop shadow under the mark (except monochrome layers).

## Variants
| Variant | Background | Mark | Status |
|---|---|---|---|
| `night` | `#171B1F` → `#0B0D0F`, ember glow at 42 % height | ember rings `#F6B072` → `#D9732B`, ember head | **chosen** (owner, 2026-11-08) |
| `ember` | `#F09A4E` → `#C9612A` | dark rings and head `#0E1113` | alternative |

Night matches the app's own background (`#0E1113`) and the log-in board. To switch, run `build.py ember`, commit the changed PNGs, and change the "chosen" tag on the board.

## Background
Computed in floating point with numpy (vertical gradient, Gaussian glow at (0.5, 0.42), a faint top highlight) and dithered before quantising to 8 bits. Never a plain SVG radial gradient: at 8 bits that bands visibly on a dark tile. The mark itself is SVG rendered by `rsvg-convert` and composited with Pillow.

## Per platform
| Platform | Shape | Mark | Files |
|---|---|---|---|
| macOS | Apple grid: tile 824 px at (100, 100) of 1024, corner radius 185.4, own shadow | centre (512, 560), width 620 (small: 640) | `macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_{16,32,64,128,256,512,1024}.png` |
| iOS | full-bleed square, opaque RGB (iOS cuts the corners; App Store refuses alpha) | centre (512, 548), width 780 (small: 760) | every slot of `ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json` |
| Android 8+ | adaptive icon, 108 dp layers | foreground: centre (512, 540) of 1024, width 50/108 of the layer, inside the 66 dp safe circle; monochrome = the same mark in white | `mipmap-*/ic_launcher_{background,foreground,monochrome}.png`, `mipmap-anydpi-v26/ic_launcher.xml` |
| Android ≤ 7 | rounded tile with a 40/1024 margin | as web install | `mipmap-*/ic_launcher.png` |
| Windows | rounded tile (corner 22.37 %), edge to edge at ≤ 32 px, a 24/1024 margin above | width 76 % of the tile (small: 78 %) | `windows/runner/resources/app_icon.ico`: 16, 20, 24, 32, 40, 48, 64, 256, each drawn at its size |
| Web | favicon: rounded tile 16 px (small mark); install: rounded tile with a 32/1024 margin; maskable: full bleed, mark width 600 inside the 80 % safe circle | — | `web/favicon.png`, `web/icons/Icon-{192,512}.png`, `web/icons/Icon-maskable-{192,512}.png` |
| Linux | rounded tile 512 px, 32/1024 margin | — | `linux/runner/resources/app_icon.png` |

Densities for Android: mdpi 1×, hdpi 1.5×, xhdpi 2×, xxhdpi 3×, xxxhdpi 4× (legacy 48 dp, layers 108 dp).

Web metadata: `web/manifest.json` name and short name "WYRM Studio", `background_color` and `theme_color` `#0E1113`; `web/index.html` title, `apple-mobile-web-app-title` and `theme-color` the same.

Linux: the PNG is for the `.desktop` entry of a package (deb, Flatpak, Snap). The GTK runner does not set a window icon; wiring it (`gtk_window_set_icon_from_file` in `my_application.cc`, the file installed next to the bundle's `data/`) is left until Studio is packaged for Linux.

## Regenerate
```sh
cd studio
python3 tool/app_icon/build.py            # night; or: build.py ember
git status app docs/design/icon           # the changed PNGs, commit them
```
Needs Python 3.10+, numpy, Pillow and `rsvg-convert` (macOS `brew install librsvg`, Debian/Ubuntu `apt install librsvg2-bin`). About 15 s. It also writes the 1024 px masters to `docs/design/icon/`.

Do not edit any of these PNGs by hand: the next run overwrites them. Change `icon.py` (mark, palettes) or `compose.py` (placement), run, look at the masters and at the AppIcon board, commit.

## Checklist
- [ ] `flutter run -d macos`: the dock shows the night tile, the same size as other apps' tiles (not full bleed).
- [ ] iOS simulator: home screen icon has no black corners or white edges; Xcode shows no "alpha channel" warning on archive.
- [ ] Android 13+: the launcher's mask (circle on Pixel) keeps all five nodes whole; themed icons on → the monochrome mark appears tinted.
- [ ] Windows: taskbar and Alt-Tab icons are sharp at 100 % and 150 % scaling.
- [ ] Web: the tab shows the small mark; "Install" uses the rounded tile; Lighthouse reports a maskable icon.

# Keel brand

## The idea

A ring cut by a line, with the charge filled up to just below it. The line is your limit: the level rises to it and stops, with clear air above. In the menu bar the mark is live, filled to the battery's real level with the line at your real limit.

- **Mark**: the app icon, the menu bar icon and anywhere square.
- **Lockup**: the mark beside the word `keel`, for the README, the banner and anywhere wide. The word's x-height sits on the mark's centre line.

## Colour

| Name | HEX | Use |
|---|---|---|
| Deep Water | `#0E2A3A` | icon tile, banner background, the mark and word on light |
| Surface | `#173B50` | top of the icon tile's gradient |
| Held Green | `#1F9A5A` | the level on light backgrounds |
| Held Green Light | `#3DD68C` | the level on Deep Water |
| Paper | `#F4F7F6` | the ring and word on dark, light backgrounds |
| Mist | `#9FB3BF` | secondary text on Deep Water |

In the app, green means held at the limit and amber means moving toward it, the same colours as the MagSafe light.

## Type

Schibsted Grotesk: Bold for the word, Medium and Regular for the banner text. All text in the brand files is outlined, so no font is needed to show them. The font is SIL Open Font License 1.1 (`fonts/OFL.txt`).

## Files

| File | Use |
|---|---|
| `keel-symbol.svg`, `-color.svg`, `-reversed.svg` | the mark in black, in colour on light, and on Deep Water |
| `keel-lockup.svg`, `-color.svg`, `-reversed.svg` | mark and word, same three versions |
| `keel-app-icon.svg` | app icon master (824 tile on the 1024 grid); the PNGs in `Keel/Resources/Assets.xcassets` are rendered from it |
| `banner.svg` | animated README header: the ring appears, the charge rises to the line and stops, the word follows. Still under reduced motion. |
| `banner-static.svg`, `banner.png` | still banner; the PNG (1280x640) is the GitHub social preview |
| `generate.py` | regenerates every SVG above (`python3 brand/generate.py`, needs fontTools) |

## Use

- Clear space: at least the ring's thickness around the mark, twice that around the lockup.
- Minimum size: mark 16 px; lockup 96 px wide.
- Don't recolour the level outside the palette, stretch the mark, or close the cut in the ring.

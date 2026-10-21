#!/usr/bin/env python3
"""Generates Keel's brand files: the mark, lockups, app icon master and the README banner.

The mark is a ring cut by the limit line, with the charge filled up to just below it. The word
is Schibsted Grotesk Bold, outlined so no font is needed (fonts/, SIL Open Font License 1.1).

  python3 brand/generate.py
Needs fontTools (pip install fonttools brotli). Writes into brand/.
"""
import math
import pathlib

from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

HERE = pathlib.Path(__file__).resolve().parent
FONT = HERE / "fonts/SchibstedGrotesk-normal-400-800.woff2"

DEEP_WATER = "#0E2A3A"
SURFACE = "#173B50"
HELD_GREEN = "#1F9A5A"
HELD_GREEN_LIGHT = "#3DD68C"
PAPER = "#F4F7F6"
MIST = "#9FB3BF"

# Mark geometry on a 256 grid.
C = 128
OUTER, INNER = 100, 82
LINE, GAP = 92, 12
LEVEL, LEVEL_GAP = 68, 6


def below(r, y):
  dy = y - C
  hx = math.sqrt(r * r - dy * dy)
  return f"M{C - hx:.2f} {y:.2f} H{C + hx:.2f} A{r} {r} 0 {1 if dy < 0 else 0} 1 {C - hx:.2f} {y:.2f} Z"


def above(r, y):
  dy = y - C
  hx = math.sqrt(r * r - dy * dy)
  return f"M{C + hx:.2f} {y:.2f} H{C - hx:.2f} A{r} {r} 0 {0 if dy < 0 else 1} 1 {C + hx:.2f} {y:.2f} Z"


TOP_ARC = f"{above(OUTER, LINE - GAP / 2)} {above(INNER, LINE - GAP / 2)}"
BOTTOM_ARC = f"{below(OUTER, LINE + GAP / 2)} {below(INNER, LINE + GAP / 2)}"
LEVEL_PATH = below(LEVEL, LINE + GAP / 2 + LEVEL_GAP)


def mark(ring, level, cls=("", "", "")):
  return (
    f'<path class="{cls[0]}" fill="{ring}" fill-rule="evenodd" d="{TOP_ARC}"/>'
    f'<path class="{cls[1]}" fill="{ring}" fill-rule="evenodd" d="{BOTTOM_ARC}"/>'
    f'<path class="{cls[2]}" fill="{level}" d="{LEVEL_PATH}"/>'
  )


def outline(text, weight, size, tracking=0.0):
  """The text as one SVG path at the given size, baseline at y=0. Returns (path, width)."""
  font = instancer.instantiateVariableFont(TTFont(FONT), {"wght": weight})
  glyphs, cmap, upm = font.getGlyphSet(), font.getBestCmap(), font["head"].unitsPerEm
  pen, x, scale = SVGPathPen(glyphs), 0.0, size / upm
  for ch in text:
    name = cmap[ord(ch)]
    glyphs[name].draw(TransformPen(pen, (scale, 0, 0, -scale, x * scale, 0)))
    x += font["hmtx"][name][0] + tracking * upm
  return pen.getCommands(), (x - tracking * upm) * scale


def svg(view_box, body, title="Keel", extra=""):
  return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{view_box}"><title>{title}</title>{extra}{body}</svg>\n'


def write(name, content):
  (HERE / name).write_text(content)


def main():
  write("keel-symbol.svg", svg("0 0 256 256", mark("#000", "#000")))
  write("keel-symbol-color.svg", svg("0 0 256 256", mark(DEEP_WATER, HELD_GREEN)))
  write("keel-symbol-reversed.svg", svg("0 0 256 256", mark(PAPER, HELD_GREEN_LIGHT)))

  # Lockup: the word's x-height centred on the mark, 44 units of air between them.
  word, word_width = outline("keel", 700, 150)
  width = 256 + 44 + word_width
  placed = f'<path fill="{{}}" d="{word}" transform="translate(300 183)"/>'
  for name, ring, level, ink in [
    ("keel-lockup.svg", "#000", "#000", "#000"),
    ("keel-lockup-color.svg", DEEP_WATER, HELD_GREEN, DEEP_WATER),
    ("keel-lockup-reversed.svg", PAPER, HELD_GREEN_LIGHT, PAPER),
  ]:
    write(name, svg(f"0 0 {width:.0f} 256", mark(ring, level) + placed.format(ink)))

  # App icon master: the macOS 824 tile on the 1024 grid.
  icon = (
    f'<defs><linearGradient id="tile" x1="0" y1="0" x2="0" y2="1">'
    f'<stop offset="0" stop-color="{SURFACE}"/><stop offset="1" stop-color="{DEEP_WATER}"/></linearGradient></defs>'
    f'<rect x="100" y="100" width="824" height="824" rx="185" fill="url(#tile)"/>'
    f'<g transform="translate(512 512) scale(2.25) translate(-128 -128)">{mark(PAPER, HELD_GREEN_LIGHT)}</g>'
  )
  write("keel-app-icon.svg", svg("0 0 1024 1024", icon, "Keel app icon"))

  write("banner.svg", banner(animated=True))
  write("banner-static.svg", banner(animated=False))


def banner(animated):
  """1280x640 README header. Animated: the ring draws in, the charge rises to the line and stops,
  the word and tagline follow. Reduced motion shows the finished frame."""
  word, _ = outline("keel", 700, 190)
  tagline_1, _ = outline("Stops your MacBook charging", 500, 42)
  tagline_2, _ = outline("where you choose.", 500, 42)
  detail, _ = outline("Open source. Swift and SwiftUI. Needs macOS 26.4 or later.", 400, 26)
  style = ""
  if animated:
    style = """<style>
.ring{transform-box:fill-box;transform-origin:center;animation:ring .7s cubic-bezier(.22,1,.36,1) .1s both}
.rise{animation:rise 1.4s cubic-bezier(.65,0,.35,1) .6s both}
.word{animation:fade .7s ease-out 1.6s both}.tag{animation:fade .7s ease-out 2s both}.detail{animation:fade .7s ease-out 2.3s both}
@keyframes ring{from{transform:scale(.85);opacity:0}}
@keyframes rise{from{transform:translateY(150px)}to{transform:translateY(0)}}
@keyframes fade{from{opacity:0;transform:translateY(8px)}}
@media (prefers-reduced-motion:reduce){.ring,.rise,.word,.tag,.detail{animation:none}}
</style>"""
  # The level rises inside a clip of its own final shape, so it never spills over the line.
  defs = f'<defs><clipPath id="level"><path d="{LEVEL_PATH}"/></clipPath></defs>'
  level = (
    f'<g clip-path="url(#level)"><rect class="rise" x="0" y="{LINE:.0f}" width="256" height="200" fill="{HELD_GREEN_LIGHT}"/></g>'
  )
  ring = (
    f'<path class="ring" fill="{PAPER}" fill-rule="evenodd" d="{TOP_ARC}"/>'
    f'<path class="ring" fill="{PAPER}" fill-rule="evenodd" d="{BOTTOM_ARC}"/>'
  )
  body = (
    f'<rect width="1280" height="640" fill="{DEEP_WATER}"/>{defs}'
    f'<g transform="translate(120 170) scale(1.17)">{ring}{level}</g>'
    f'<g class="word"><path fill="{PAPER}" d="{word}" transform="translate(500 315)"/></g>'
    f'<g class="tag"><path fill="{PAPER}" d="{tagline_1}" transform="translate(506 392)"/>'
    f'<path fill="{PAPER}" d="{tagline_2}" transform="translate(506 444)"/></g>'
    f'<g class="detail"><path fill="{MIST}" d="{detail}" transform="translate(506 506)"/></g>'
  )
  return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1280 640" width="1280" height="640"><title>Keel</title>{style}{body}</svg>\n'


if __name__ == "__main__":
  main()

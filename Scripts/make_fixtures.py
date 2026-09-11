#!/usr/bin/env python3
"""Renders the parity fixtures with the Python reference implementation.

The Swift tests compare their own output against these PNGs, so they are the
ground truth for the port. Run this only when the matrix below changes:

    cd ~/Developer/Github/FolderCrest/New-features
    ./.venv/bin/python "<this repo>/Scripts/make_fixtures.py"

The filename encodes the recipe; the Swift side parses it, so there is no
second place where the matrix has to be kept in step.
"""

import os
import sys

REFERENCE = os.path.expanduser("~/Developer/Github/FolderCrest/New-features")
OUTPUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                      "Folder CrestTests", "Fixtures")

sys.path.insert(0, REFERENCE)
os.chdir(REFERENCE)

from PIL import Image  # noqa: E402
from foldercrest.constants import (  # noqa: E402
    FolderStyle, IconGenerationMethod, SFFont, TintColour)
from foldercrest.imagetransformations import generate_folder_icon  # noqa: E402

# name -> keyword arguments for generate_folder_icon
CASES = {}

# One plain text engraving per style, the baseline case
for style in FolderStyle:
    CASES[f"text-A_{style.name}_scale1_off0-0_bold"] = dict(
        folder_style=style, generation_method=IconGenerationMethod.TEXT, text="A")

# Scale, offset and weight, all on the default style
for scale in (0.1, 1.0, 2.0):
    CASES[f"text-A_tahoe_scale{scale}_off0-0_bold"] = dict(
        folder_style=FolderStyle.tahoe, generation_method=IconGenerationMethod.TEXT,
        text="A", icon_scale=scale)

for offset in ((0.2, -0.1), (-0.27, 0.15)):
    name = f"text-A_tahoe_scale1_off{offset[0]}-{offset[1]}_bold"
    CASES[name] = dict(
        folder_style=FolderStyle.tahoe, generation_method=IconGenerationMethod.TEXT,
        text="A", icon_offset=offset)

for weight in (SFFont.ultralight, SFFont.black):
    CASES[f"text-A_tahoe_scale1_off0-0_{weight.name}"] = dict(
        folder_style=FolderStyle.tahoe, generation_method=IconGenerationMethod.TEXT,
        text="A", font_style=weight)

# A wider string, to catch anything that only works for a single glyph
CASES["text-Ag_tahoe_scale1_off0-0_bold"] = dict(
    folder_style=FolderStyle.tahoe, generation_method=IconGenerationMethod.TEXT,
    text="Ag")

# No icon at all: the plain folder with its shadow darkened
for style in FolderStyle:
    CASES[f"none_{style.name}_scale1_off0-0_bold"] = dict(
        folder_style=style, generation_method=IconGenerationMethod.NONE)

# Tint, on the plain folder and on an engraving
for tint in (TintColour.red, TintColour.white, TintColour.teal):
    CASES[f"none_tahoe_scale1_off0-0_bold_tint-{tint.name}"] = dict(
        folder_style=FolderStyle.tahoe, generation_method=IconGenerationMethod.NONE,
        tint_colour=tint.value)
    CASES[f"text-A_tahoe_scale1_off0-0_bold_tint-{tint.name}"] = dict(
        folder_style=FolderStyle.tahoe, generation_method=IconGenerationMethod.TEXT,
        text="A", tint_colour=tint.value)

# A dropped image, engraved and kept in its own colours. Deterministic content,
# generated the same way on both sides so no binary fixture input is needed.
def _test_image():
    image = Image.new("RGBA", (200, 160), (0, 0, 0, 0))
    pixels = image.load()
    for y in range(160):
        for x in range(200):
            if 20 <= x < 180 and 20 <= y < 140:
                pixels[x, y] = ((x * 7) % 256, (y * 11) % 256, (x + y) % 256, 255)
    return image


CASES["image_tahoe_scale1_off0-0_bold_engraved"] = dict(
    folder_style=FolderStyle.tahoe, generation_method=IconGenerationMethod.IMAGE,
    image=_test_image())
CASES["image_tahoe_scale1_off0-0_bold_original"] = dict(
    folder_style=FolderStyle.tahoe, generation_method=IconGenerationMethod.IMAGE,
    image=_test_image(), preserve_image_colours=True)
CASES["image_tahoe_scale1_off0-0_bold_original_tint-red"] = dict(
    folder_style=FolderStyle.tahoe, generation_method=IconGenerationMethod.IMAGE,
    image=_test_image(), preserve_image_colours=True, tint_colour=TintColour.red.value)

# Emoji keep their own colours
for emoji, label in (("\U0001f419", "octopus"), ("\U0001f4c1", "folder")):
    CASES[f"emoji-{label}_tahoe_scale1_off0-0_bold"] = dict(
        folder_style=FolderStyle.tahoe, generation_method=IconGenerationMethod.TEXT,
        text=emoji)


def main():
    os.makedirs(OUTPUT, exist_ok=True)
    for name, kwargs in sorted(CASES.items()):
        image = generate_folder_icon(**kwargs)
        path = os.path.join(OUTPUT, name + ".png")
        image.save(path)
        print(f"{name}.png  {image.size[0]}x{image.size[1]}")
    print(f"\n{len(CASES)} fixtures in {OUTPUT}")


if __name__ == "__main__":
    main()

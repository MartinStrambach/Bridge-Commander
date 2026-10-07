#!/usr/bin/env python3
# Write AppIconDebug.appiconset: the app icon with a red "DEBUG" ribbon across its top-right
# corner, which the Debug configuration uses (ASSETCATALOG_COMPILER_APPICON_NAME), so a debug
# build is told apart from the release app in the Dock and the app switcher.
#
#   scripts/make-debug-icon.py
#
# Rerun it after changing AppIcon.appiconset. Needs Pillow (`pip3 install Pillow`).

import json
import shutil
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ASSETS = Path(__file__).resolve().parent.parent / "BridgeCommander" / "Assets.xcassets"
SOURCE = ASSETS / "AppIcon.appiconset"
TARGET = ASSETS / "AppIconDebug.appiconset"
FONT = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"

SIZE = 1024
RIBBON_COLOR = (214, 40, 40, 255)
TEXT_COLOR = (255, 255, 255, 255)


def ribbon(size: int) -> Image.Image:
    """A diagonal band across the top-right corner, drawn on a transparent square."""
    # Drawn horizontally on a strip, then rotated 45° and placed so its centre line runs from
    # (size - offset, 0) to (size, offset). Kept well inside the corner, since macOS masks the
    # icon to a rounded square.
    offset = int(size * 0.42)
    thickness = int(size * 0.13)
    length = int(offset * 2 ** 0.5) + thickness * 2

    strip = Image.new("RGBA", (length, thickness), RIBBON_COLOR)
    draw = ImageDraw.Draw(strip)
    edge = max(1, thickness // 14)
    draw.rectangle((0, 0, length, edge), fill=(255, 255, 255, 110))
    draw.rectangle((0, thickness - edge, length, thickness), fill=(0, 0, 0, 90))

    font = ImageFont.truetype(FONT, int(thickness * 0.62))
    draw.text((length / 2, thickness / 2), "DEBUG", font=font, fill=TEXT_COLOR, anchor="mm")

    rotated = strip.rotate(-45, resample=Image.BICUBIC, expand=True)
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    centre = (size - offset / 2, offset / 2)
    layer.alpha_composite(
        rotated,
        (int(centre[0] - rotated.width / 2), int(centre[1] - rotated.height / 2)),
    )
    return layer


def main() -> None:
    contents = json.loads((SOURCE / "Contents.json").read_text())
    master = Image.open(SOURCE / "iTunesArtwork-1024.png").convert("RGBA").resize((SIZE, SIZE))
    master.alpha_composite(ribbon(SIZE))

    if TARGET.exists():
        shutil.rmtree(TARGET)
    TARGET.mkdir()

    for image in contents["images"]:
        points = int(image["size"].split("x")[0])
        pixels = points * int(image["scale"].rstrip("x"))
        filename = f"icon-{pixels}x{pixels}.png"
        image["filename"] = filename
        if not (TARGET / filename).exists():
            master.resize((pixels, pixels), Image.LANCZOS).save(TARGET / filename)

    (TARGET / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")


if __name__ == "__main__":
    main()

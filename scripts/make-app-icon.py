#!/usr/bin/env python3
"""Build the app icon set from the brand mark.

Source of truth is `docs/brand/papernest-instagram-profile.png`, which holds
the approved mark: the leaf-in-a-ring in brand purple on near-white. The icon
inverts that — a **white mark on brand purple** — which is how the approved
redesign board (docs/design/approved-2026-11-07/studio-board.png) draws it,
and which is the version that survives being shown against a white Home
screen or a white Dock.

Two shapes come out of this, because the platforms want different things:

* **iOS** takes a full-bleed 1024 square with **no alpha**. The system applies
  its own rounded mask; baking one in leaves dark corners behind the mask.
* **macOS** draws its own icon shape, so it takes a rounded rectangle inset
  inside a transparent canvas — roughly Apple's grid, where the body covers
  about four fifths of the canvas.

Regenerate with `python3 scripts/make-app-icon.py`. Nothing here is hand-
edited; if the brand mark changes, run it again.
"""

from __future__ import annotations

import json
import pathlib
import shutil
import subprocess
import sys
import tempfile

from PIL import Image, ImageDraw

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCE = ROOT / "docs" / "brand" / "papernest-instagram-profile.png"
CATALOGUE = ROOT / "Apps" / "Shared" / "Assets.xcassets"
ICON_SET = CATALOGUE / "AppIcon.appiconset"
# The development Mac app is assembled by hand from the Swift package
# (scripts/build-mac-app.sh), so it never compiles an asset catalogue. It
# carries this instead, referenced by CFBundleIconFile. Kept out of
# Apps/Mac/Resources so the Xcode target, which takes its icon from the
# catalogue, does not also copy it.
ICNS = ROOT / "Apps" / "Mac" / "PaperNest.icns"

# The sizes macOS wants drawn, as points. Both the catalogue and the .icns
# are built from these, at 1x and 2x, so the two can never drift apart.
MAC_POINTS = (16, 32, 128, 256, 512)

# The same mark again, this time for the app itself to draw in its UI — the
# welcome screen's brand lockup. Emitted as a **template** image: white
# pixels carrying only the mark's alpha, so SwiftUI tints it with
# `Theme.accent` and it follows light and dark mode instead of being a fixed
# purple. It comes out of this script rather than being drawn by hand so the
# lockup and the Home-screen icon cannot drift apart.
BRAND_CATALOGUE = ROOT / "Sources" / "PaperNestUI" / "Resources" / "Brand.xcassets"
BRAND_MARK_SET = BRAND_CATALOGUE / "BrandMark.imageset"
# Points at 1x. The lockup draws it near text size; this is generous enough
# to stay crisp if a later design uses it larger.
BRAND_MARK_POINTS = 48
# The mark again at its own size in the brand art, never scaled up, for the
# PaperNest watermark: the large branded preset draws it about 85 points
# across, which on a page printed at 300 dpi takes about 354 pixels, and the
# 144-pixel @3x rendition above printed soft. One universal image, so no
# device thins it away.
BRAND_MARK_LARGE_SET = BRAND_CATALOGUE / "BrandMarkLarge.imageset"

# Sampled from the brand mark rather than chosen: 107,115 of its pixels are
# exactly this purple.
BRAND = (117, 69, 248)
# A gentle top-to-bottom shift for depth, ±7% of the brand purple. Anything
# stronger stops reading as the brand colour.
TOP = (135, 92, 250)
BOTTOM = (104, 56, 232)

# The dark appearance. Apple's guidance (HIG "App icons", Appearances) is to
# use the light icon as the basis, pick complementary colours that reflect it,
# avoid excessively bright images, and keep a *colour* background, which
# "generally offer[s] the greatest contrast in dark icons" — so this is the
# same hue carried down, not a transparent tile.
TOP_DARK = (74, 42, 160)
BOTTOM_DARK = (44, 22, 104)
# Not pure white: at full brightness the mark glares against the darker field.
MARK_DARK = (232, 226, 252)

# Share of the canvas the mark covers. The source art floats in a lot of
# white; an icon wants the mark to carry the tile.
MARK_SCALE_IOS = 0.62
MARK_SCALE_MAC = 0.50
# macOS body as a share of the canvas, and its corner radius as a share of
# the body — Apple's macOS icon grid, near enough.
MAC_BODY = 0.80
MAC_CORNER = 0.235


def mark_alpha(source: Image.Image) -> Image.Image:
    """The mark as a mask: opaque where the art is purple, clear elsewhere.

    The art is two flat colours — the brand purple on a near-white field —
    with a thin anti-aliased seam between them. Each pixel is read as a
    position on the line from the background to the brand purple, so the
    background keys to exactly nothing, the mark keys to solid, and the
    seam keeps the soft edge that makes the mark look drawn rather than
    cut out.

    The background is sampled from a corner, not assumed: keying against a
    hard-coded white left the whole source square faintly opaque, which
    painted a pale box behind the mark on every tile.
    """
    rgba = source.convert("RGBA")
    width, height = rgba.size
    background = rgba.getpixel((0, 0))[:3]
    span = sum(abs(background[i] - BRAND[i]) for i in range(3))
    if span == 0:
        raise SystemExit("brand mark and its background are the same colour")
    alpha = Image.new("L", (width, height), 0)
    src = rgba.load()
    dst = alpha.load()
    for y in range(height):
        for x in range(width):
            r, g, b, a = src[x, y]
            if a == 0:
                continue
            # 0 at the background, 1 at the brand purple.
            distance = (abs(r - background[0]) + abs(g - background[1])
                        + abs(b - background[2])) / span
            dst[x, y] = max(0, min(255, int(round(distance * 255))))
    box = alpha.getbbox()
    if box is None:
        raise SystemExit("no mark found in the brand art")
    return alpha.crop(box)


def gradient(size: int, top: tuple[int, int, int] = TOP,
             bottom: tuple[int, int, int] = BOTTOM) -> Image.Image:
    canvas = Image.new("RGB", (size, size), top)
    draw = ImageDraw.Draw(canvas)
    for y in range(size):
        t = y / max(size - 1, 1)
        draw.line(
            [(0, y), (size, y)],
            fill=tuple(round(top[i] + (bottom[i] - top[i]) * t) for i in range(3)),
        )
    return canvas


def place_mark(canvas: Image.Image, mark: Image.Image, scale: float,
               color: tuple[int, int, int] = (255, 255, 255)) -> None:
    size = canvas.size[0]
    target = round(size * scale)
    ratio = target / max(mark.size)
    resized = mark.resize(
        (max(1, round(mark.size[0] * ratio)), max(1, round(mark.size[1] * ratio))),
        Image.LANCZOS,
    )
    ink = Image.new("RGBA", resized.size, (*color, 255))
    canvas.paste(
        ink,
        ((size - resized.size[0]) // 2, (size - resized.size[1]) // 2),
        resized,
    )


def ios_icon(mark: Image.Image, size: int = 1024) -> Image.Image:
    """Full bleed, no alpha: the system supplies the mask."""
    canvas = gradient(size).convert("RGBA")
    place_mark(canvas, mark, MARK_SCALE_IOS)
    return canvas.convert("RGB")


def ios_dark_icon(mark: Image.Image, size: int = 1024) -> Image.Image:
    """The dark appearance: same mark and framing, deeper field."""
    canvas = gradient(size, TOP_DARK, BOTTOM_DARK).convert("RGBA")
    place_mark(canvas, mark, MARK_SCALE_IOS, MARK_DARK)
    return canvas.convert("RGB")


def ios_tinted_icon(mark: Image.Image, size: int = 1024) -> Image.Image:
    """The tinted appearance: greyscale, which the system maps to the tint.

    Derived from the dark icon rather than drawn separately, so the mark sits
    in the same place at the same size across all three — the HIG asks for
    features to stay consistent between appearances.

    Converted back to RGB on purpose. A single-channel greyscale PNG is a
    different colour space from its light and dark siblings, and that
    mismatch is a reported cause of the tinted variant rendering wrongly.
    """
    return ios_dark_icon(mark, size).convert("L").convert("RGB")


def mac_icon(mark: Image.Image, size: int) -> Image.Image:
    """A rounded body inset in a transparent canvas, as macOS expects."""
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    body = round(size * MAC_BODY)
    # Drawn large and downsampled: PIL's rounded rectangle has no
    # anti-aliasing of its own, and a 16-point icon shows every jagged step.
    supersample = 4
    big = body * supersample
    shape = Image.new("L", (big, big), 0)
    ImageDraw.Draw(shape).rounded_rectangle(
        [0, 0, big - 1, big - 1], radius=round(big * MAC_CORNER), fill=255
    )
    shape = shape.resize((body, body), Image.LANCZOS)
    tile = gradient(body).convert("RGBA")
    tile.putalpha(shape)
    place_mark(tile, mark, MARK_SCALE_MAC / MAC_BODY)
    offset = (size - body) // 2
    canvas.paste(tile, (offset, offset), tile)
    return canvas


def write_icns(tiles: dict[tuple[int, int], Image.Image]) -> None:
    """Pack the macOS tiles into an .icns for the hand-built dev bundle.

    `iconutil` ships with the Command Line Tools, which is the floor this
    project builds against, and it wants a directory of exactly-named PNGs.
    """
    with tempfile.TemporaryDirectory() as scratch:
        iconset = pathlib.Path(scratch) / "PaperNest.iconset"
        iconset.mkdir()
        for (points, factor), image in tiles.items():
            suffix = "@2x" if factor == 2 else ""
            image.save(iconset / f"icon_{points}x{points}{suffix}.png")
        ICNS.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(
            ["iconutil", "--convert", "icns", "--output", str(ICNS), str(iconset)],
            check=True,
        )


def write_brand_mark(mark: Image.Image) -> None:
    """Emit the mark on its own, as a tintable template image.

    Carries alpha only — every opaque pixel is white — because a template
    image's colour comes from the view that draws it. Giving it the brand
    purple here instead would freeze it to the light appearance.
    """
    BRAND_MARK_SET.mkdir(parents=True, exist_ok=True)
    images: list[dict[str, str]] = []
    for factor in (1, 2, 3):
        pixels = BRAND_MARK_POINTS * factor
        ratio = pixels / max(mark.size)
        alpha = mark.resize(
            (max(1, round(mark.size[0] * ratio)), max(1, round(mark.size[1] * ratio))),
            Image.LANCZOS,
        )
        tile = Image.new("RGBA", alpha.size, (255, 255, 255, 255))
        tile.putalpha(alpha)
        name = f"brand-mark{'' if factor == 1 else f'@{factor}x'}.png"
        tile.save(BRAND_MARK_SET / name)
        images.append({"filename": name, "idiom": "universal", "scale": f"{factor}x"})
    (BRAND_MARK_SET / "Contents.json").write_text(
        json.dumps({
            "images": images,
            "info": {"author": "xcode", "version": 1},
            "properties": {"template-rendering-intent": "template"},
        }, indent=2) + "\n")
    (BRAND_CATALOGUE / "Contents.json").write_text(
        json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n")


def write_large_brand_mark(mark: Image.Image) -> None:
    """Emit the mark at its native size in the art, as a template image."""
    BRAND_MARK_LARGE_SET.mkdir(parents=True, exist_ok=True)
    tile = Image.new("RGBA", mark.size, (255, 255, 255, 255))
    tile.putalpha(mark)
    tile.save(BRAND_MARK_LARGE_SET / "brand-mark-large.png")
    (BRAND_MARK_LARGE_SET / "Contents.json").write_text(
        json.dumps({
            "images": [{"filename": "brand-mark-large.png", "idiom": "universal"}],
            "info": {"author": "xcode", "version": 1},
            "properties": {"template-rendering-intent": "template"},
        }, indent=2) + "\n")


def main() -> int:
    if not SOURCE.exists():
        print(f"brand mark missing: {SOURCE}", file=sys.stderr)
        return 1
    if shutil.which("iconutil") is None:
        print("iconutil not found; install the Xcode Command Line Tools", file=sys.stderr)
        return 1
    mark = mark_alpha(Image.open(SOURCE))
    ICON_SET.mkdir(parents=True, exist_ok=True)

    images: list[dict[str, object]] = []

    # iOS carries three appearances. The system generates any it is not given,
    # by segmenting the bitmap into foreground and background; supplying them
    # is how the colours stay ours rather than inferred.
    for name, image, appearance in (
        ("icon-ios-1024.png", ios_icon(mark), None),
        ("icon-ios-1024-dark.png", ios_dark_icon(mark), "dark"),
        ("icon-ios-1024-tinted.png", ios_tinted_icon(mark), "tinted"),
    ):
        image.save(ICON_SET / name)
        entry: dict[str, object] = {"filename": name, "idiom": "universal",
                                    "platform": "ios", "size": "1024x1024"}
        if appearance is not None:
            entry["appearances"] = [{"appearance": "luminosity", "value": appearance}]
        images.append(entry)

    # macOS wants every size drawn, not scaled by the system.
    tiles: dict[tuple[int, int], Image.Image] = {}
    for points in MAC_POINTS:
        for factor in (1, 2):
            name = f"icon-mac-{points}x{points}{'@2x' if factor == 2 else ''}.png"
            tile = mac_icon(mark, points * factor)
            tile.save(ICON_SET / name)
            tiles[(points, factor)] = tile
            images.append({"filename": name, "idiom": "mac",
                           "scale": f"{factor}x", "size": f"{points}x{points}"})

    (ICON_SET / "Contents.json").write_text(
        json.dumps({"images": images, "info": {"author": "xcode", "version": 1}},
                   indent=2) + "\n")
    (CATALOGUE / "Contents.json").write_text(
        json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n")
    write_icns(tiles)
    write_brand_mark(mark)
    write_large_brand_mark(mark)
    print(f"wrote {len(images)} images to {ICON_SET.relative_to(ROOT)}")
    print(f"wrote {ICNS.relative_to(ROOT)}")
    print(f"wrote {BRAND_MARK_SET.relative_to(ROOT)}")
    print(f"wrote {BRAND_MARK_LARGE_SET.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

"""Interactive region picker for the gray-card correction diagnostic tool.

Opens a photo in a matplotlib window. Click-and-drag one rectangle for the
gray-card region, then click-and-drag a second rectangle for the skin
region. Prints the exact --card/--skin arguments to paste into
tool/test_gray_card_correction.py.

CLI diagnostic only -- same category as tool/test_gray_card_correction.py
and tool/analyze_repeatability.py. No API/UI changes, no new dependencies
(matplotlib already ships transitively via ultralytics).

Usage:
    python tool/pick_regions.py PHOTO.jpg

    1. A window opens showing the photo. Click-and-drag to draw the FIRST
       rectangle over the gray card, then release the mouse.
    2. The window title updates to prompt for the SECOND rectangle. Click-
       and-drag over a patch of skin, then release the mouse.
    3. The window closes automatically and both rectangles are printed as
       ready-to-paste --card/--skin arguments, e.g.:

           python tool/test_gray_card_correction.py PHOTO.jpg \\
               --card 40,40,60,60 --skin 200,150,120,120

    Press "r" at any point to redraw the current rectangle, or close the
    window early to abort without printing anything.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import cv2
import matplotlib.pyplot as plt
from matplotlib.widgets import RectangleSelector


def _to_rect(x0: float, y0: float, x1: float, y1: float) -> tuple[int, int, int, int]:
    x = int(round(min(x0, x1)))
    y = int(round(min(y0, y1)))
    w = int(round(abs(x1 - x0)))
    h = int(round(abs(y1 - y0)))
    return x, y, w, h


def _format_rect(rect: tuple[int, int, int, int]) -> str:
    x, y, w, h = rect
    return f"{x},{y},{w},{h}"


def pick_two_regions(image_rgb) -> tuple[tuple[int, int, int, int] | None, tuple[int, int, int, int] | None]:
    """Shows [image_rgb] and lets the user drag two rectangles in order.

    Returns (card_rect, skin_rect) as (x, y, w, h) tuples, or None for
    whichever rectangle was never drawn before the window closed.
    """
    picked: list[tuple[int, int, int, int]] = []

    fig, ax = plt.subplots()
    ax.imshow(image_rgb)
    ax.set_title("Drag a rectangle over the GRAY CARD, then release")
    ax.axis("off")

    def _on_select(eclick, erelease) -> None:
        rect = _to_rect(eclick.xdata, eclick.ydata, erelease.xdata, erelease.ydata)
        if rect[2] <= 0 or rect[3] <= 0:
            return
        if len(picked) < 2:
            picked.append(rect)
        label = "GRAY CARD" if len(picked) == 1 else "SKIN region"
        print(f"Picked {label if len(picked) == 2 else 'card'} rect: {_format_rect(rect)}")
        if len(picked) == 1:
            ax.set_title("Now drag a rectangle over a SKIN region, then release")
            fig.canvas.draw_idle()
        elif len(picked) == 2:
            ax.set_title("Both regions picked -- closing window")
            fig.canvas.draw_idle()
            plt.close(fig)

    selector = RectangleSelector(
        ax,
        _on_select,
        useblit=True,
        button=[1],
        minspanx=3,
        minspany=3,
        spancoords="pixels",
        interactive=True,
    )
    # Keep a reference so the selector isn't garbage-collected mid-session.
    fig._region_selector = selector  # type: ignore[attr-defined]

    plt.show()

    card_rect = picked[0] if len(picked) >= 1 else None
    skin_rect = picked[1] if len(picked) >= 2 else None
    return card_rect, skin_rect


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("photo", type=Path, help="Path to the photo to open.")
    args = parser.parse_args()

    if not args.photo.exists():
        raise SystemExit(f"Photo not found: {args.photo}")

    image_bgr = cv2.imread(str(args.photo))
    if image_bgr is None:
        raise SystemExit(f"Failed to decode image: {args.photo}")
    image_rgb = cv2.cvtColor(image_bgr, cv2.COLOR_BGR2RGB)

    card_rect, skin_rect = pick_two_regions(image_rgb)

    if card_rect is None or skin_rect is None:
        print("Aborted: both a card and a skin rectangle are required.", file=sys.stderr)
        raise SystemExit(1)

    print()
    print("--card and --skin arguments:")
    print(
        f"python tool/test_gray_card_correction.py {args.photo} "
        f"--card {_format_rect(card_rect)} --skin {_format_rect(skin_rect)}"
    )


if __name__ == "__main__":
    main()

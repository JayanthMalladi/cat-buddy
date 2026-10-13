#!/usr/bin/env python3
"""Turn the repaired 640x640 sprite frames into the small frames the app ships.

Usage: python3 tools/prepare_sprites.py /path/to/sprites_repaired

For each animation it keeps a chosen frame range (skipping known glitches),
shifts the frames so every animation stands on the same ground line, crops
all of them to one shared rectangle, scales them down and saves palette PNGs
into Resources/Animations/<name>/. Needs Pillow.
"""
import os
import shutil
import sys

from PIL import Image

# Shared ground line (y in the 640 canvas) every animation is shifted to.
GROUND = 520
# Crop rectangle in the 640 canvas after the shift (left, top, right, bottom).
CROP = (0, 20, 610, 544)
SCALE = 0.7      # 610x524 -> 427x367 px, shown at half that in points (@2x)
STEP = 2         # keep every 2nd frame: 96 source frames at 24fps -> 12fps

# name: (source folder, measured ground line, source frame ranges to keep)
ANIMATIONS = {
    # Head pops down at 33->34 and up at 80->81, so loop the head-up part only.
    "resting": ("peaceful_resting_cat", 511, [(81, 95), (0, 33)]),
    "awake": ("awake_cat", 567, [(0, 95)]),
    "curious": ("head_tilt_cat", 558, [(0, 95)]),
    # Body jumps at 68->69, so stop before it.
    "happy": ("happy_cat", 511, [(0, 68)]),
    # Tail clips the canvas edge at 84-86, so stop before it.
    "stretching": ("stretching_cat", 535, [(0, 83)]),
    "walking": ("walking_cat", 505, [(0, 95)]),
    "yawning": ("yawning_cat", 558, [(0, 95)]),
    "sleeping": ("sleeping_cat", 510, [(0, 95)]),
}


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    src_root = sys.argv[1]
    out_root = os.path.join(os.path.dirname(__file__), "..", "Resources", "Animations")
    size = (round((CROP[2] - CROP[0]) * SCALE), round((CROP[3] - CROP[1]) * SCALE))
    for name, (folder, ground, ranges) in ANIMATIONS.items():
        out_dir = os.path.join(out_root, name)
        shutil.rmtree(out_dir, ignore_errors=True)
        os.makedirs(out_dir)
        indices = [i for a, b in ranges for i in range(a, b + 1)][::STEP]
        shift = GROUND - ground
        for n, i in enumerate(indices):
            frame = Image.open(os.path.join(src_root, folder, f"frame_{i:04d}.png")).convert("RGBA")
            canvas = Image.new("RGBA", frame.size, (0, 0, 0, 0))
            canvas.paste(frame, (0, shift))
            small = canvas.crop(CROP).resize(size, Image.LANCZOS)
            # The repaired art has hard edges, so keep the alpha binary.
            small.putalpha(small.getchannel("A").point(lambda v: 255 if v >= 128 else 0))
            small.quantize(256, method=Image.Quantize.FASTOCTREE).save(
                os.path.join(out_dir, f"frame_{n:03d}.png"), optimize=True)
        print(f"{name}: {len(indices)} frames, shift {shift:+d}px")


if __name__ == "__main__":
    main()

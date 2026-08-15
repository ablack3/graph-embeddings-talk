"""A dancing banana. In your terminal. Announcing what time it is.

    python3 examples/banana.py                 # dance (ctrl-c to stop)
    python3 examples/banana.py --loops 4       # dance, then stop
    python3 examples/banana.py --still         # print the frames, no animation
    python3 examples/banana.py --fps 8         # faster
    python3 examples/banana.py --no-color      # for a terminal that hates joy
    python3 examples/banana.py --ws            # ...also emit a Whitespace version

Standard library only. Uses ANSI escapes, so it wants a real terminal; --still
prints the frames plainly and works when piped.

There is no deeper point being made here.
"""

from __future__ import annotations

import argparse
import shutil
import sys
import time

# --- the banana ---------------------------------------------------------------
#
# Four poses. The body columns are identical in all four so the banana itself
# never jitters -- only the arms and legs move. Each pose is exactly 9 rows.

POSES = [
    # arms up, legs apart
    r"""
        .-.
    \  / o \  /
     \|  u  |/
      |     |
      |      \
       \      \
        \_____|
        /     \
       /       \
""",
    # arms out, legs together
    r"""
        .-.
       / o \
   ____|  u  |____
      |     |
      |      \
       \      \
        \_____|
          |  |
          |  |
""",
    # arms down, legs apart the other way
    r"""
        .-.
       / o \
      |  u  |
     /|     |\
    / |      \
   /   \      \
        \_____|
       /       \
      /         \
""",
    # arms out, legs together
    r"""
        .-.
       / o \
   ____|  u  |____
      |     |
      |      \
       \      \
        \_____|
          |  |
          |  |
""",
]

CAPTIONS = [
    "PEANUT BUTTER JELLY TIME!",
    "PEANUT BUTTER JELLY TIME!",
    "PEANUT BUTTER JELLY TIME!",
    "...WHERE HE AT?",
]

# Every pose is padded to this width before centring. Without it each pose gets
# centred on its own longest row, and the banana slides sideways whenever the
# arms change -- which looks like a bug, because it is one.
POSE_W = max(len(r) for p in POSES for r in p.strip("\n").split("\n"))

YELLOW, MAGENTA, CYAN, BOLD, RESET = (
    "\033[93m", "\033[95m", "\033[96m", "\033[1m", "\033[0m")
CLEAR, HIDE, SHOW = "\033[2J\033[H", "\033[?25l", "\033[?25h"


def frame(i: int, color: bool = True, width: int | None = None) -> str:
    """One rendered frame: banana, then caption, both centred."""
    width = width or shutil.get_terminal_size((72, 24)).columns
    body = POSES[i % len(POSES)].strip("\n").split("\n")
    caption = CAPTIONS[i % len(CAPTIONS)]

    pad = max(0, (width - POSE_W) // 2)
    out = ["", ""] + [" " * pad + r for r in body]

    # A one-column shimmy on the caption only -- the banana itself stays put.
    cap_pad = max(0, (width - len(caption)) // 2 + (i % 2))
    out += ["", " " * cap_pad + caption]

    text = "\n".join(out)
    if not color:
        return text

    banana = "\n".join(out[:-2])
    cap_line = out[-1]
    cap_col = MAGENTA if i % 2 == 0 else CYAN
    return f"{YELLOW}{banana}{RESET}\n\n{BOLD}{cap_col}{cap_line}{RESET}"


def dance(loops: int | None, fps: float, color: bool) -> None:
    delay = 1.0 / fps
    n = 0
    sys.stdout.write(HIDE)
    try:
        while loops is None or n < loops * len(POSES):
            sys.stdout.write(CLEAR + frame(n, color) + "\n")
            sys.stdout.flush()
            time.sleep(delay)
            n += 1
    except KeyboardInterrupt:
        pass
    finally:
        sys.stdout.write(SHOW + RESET + "\n")
        sys.stdout.flush()


def emit_whitespace(path: str, frames: int = 16, ticks: int = 150_000) -> None:
    """The same dance, as a Whitespace program, because we have the toolchain."""
    import pathlib
    sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent / "scripts"))
    from whitespace import Asm, run

    a = Asm()
    for i in range(frames):
        a.emit(CLEAR).emit(frame(i, color=False, width=52) + "\n")
        a.delay(ticks, f"b{i}")
    src = a.end().source()

    pathlib.Path(path).write_text(src)
    out = run(src)
    assert "PEANUT BUTTER JELLY TIME!" in out, "the banana is not dancing"
    print(f"wrote {path} -- {len(src):,} bytes, "
          f"{len(src.splitlines()):,} lines, {len(set(src))} distinct characters")
    print(f"verified: {out.count(CLEAR)} frames render, "
          f"{len(out):,} chars of output")


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--loops", type=int, default=None,
                   help="stop after this many full cycles (default: forever)")
    p.add_argument("--fps", type=float, default=4.0)
    p.add_argument("--still", action="store_true",
                   help="print every pose once, no clearing -- safe to pipe")
    p.add_argument("--no-color", dest="color", action="store_false")
    p.add_argument("--ws", metavar="PATH", nargs="?", const="examples/banana.ws",
                   help="also write a Whitespace version and verify it")
    a = p.parse_args()

    if a.ws:
        return emit_whitespace(a.ws)
    if a.still:
        for i in range(len(POSES)):
            print(f"--- pose {i + 1} ---")
            print(frame(i, a.color, width=52))
        return
    dance(a.loops, a.fps, a.color)


if __name__ == "__main__":
    main()

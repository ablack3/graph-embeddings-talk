"""Build a file that is two programs at once.

    python3 scripts/make-polyglot.py            # build + verify both halves
    python3 scripts/make-polyglot.py --run      # ...and play the animation

Output is examples/quarterly_report.py, which is simultaneously:

  * a Python script -- run it and you get an A/B test readout, the most
    load-bearing genre of corporate artefact there is; and

  * a Whitespace program -- feed the same bytes to a Whitespace interpreter
    and you get an ASCII animation of a cyclist meeting a Boston pedestrian.

Why this is possible, and it is almost too neat:

  * Whitespace ignores every character that is not space, tab or linefeed. So
    Python source code is invisible to it.
  * Python ignores lines that contain only whitespace. So a Whitespace program
    is invisible to it -- it reads as several thousand blank lines.

So the two languages are blind to each other in exactly complementary ways. Put
the Whitespace program first, terminate it with [LF][LF][LF], and put the Python
after the terminator where it is unreachable.

One real caveat: interpreters differ on what happens after the end-program
instruction. This repo's interpreter stops parsing there (see _parse in
whitespace.py), which is what makes the trailing Python harmless. An interpreter
that parses the whole file up front may object to the Python. If you hit that,
strip the file to its whitespace with:

    tr -cd ' \\t\\n' < examples/quarterly_report.py > animation.ws
"""

from __future__ import annotations

import pathlib
import subprocess
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from whitespace import Asm, run  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "examples" / "quarterly_report.py"

CLEAR = "\033[2J\033[H"
WIDTH = 34
PED = 27          # column the pedestrian stands in -- inside the lane, naturally
FRAMES = 16

# Whitespace has no sleep instruction, so each frame burns a countdown loop.
# This is a knob, not a duration: the wall-clock delay depends entirely on how
# fast your interpreter is. Tuned for the one in whitespace.py (~0.2 s/frame).
DELAY_TICKS = 150_000


# --- the Whitespace half: a cyclist meets a Boston pedestrian -----------------


def scene(bike: str, col: int, caption: str) -> str:
    lane = [" "] * WIDTH
    lane[PED] = "A"
    for k, ch in enumerate(bike):
        if 0 <= col + k < WIDTH and ch != " ":
            lane[col + k] = ch
    return (
        "      BOSTON BIKE LANE\n"
        "   +" + "-" * WIDTH + "+\n"
        "   |" + "".join(lane) + "|\n"
        "   +" + "-" * WIDTH + "+\n"
        f"   {caption}\n"
    )


def animation() -> str:
    a = Asm()
    sprite = "~o=o>"
    stopped = PED - len(sprite)      # nose just short of them, not through them

    for f in range(FRAMES):
        col = f + 1
        nose = col + len(sprite) - 1
        if nose < PED - 1:
            caption = "cruising"
        elif nose < PED:
            caption = "...they see me..."
        else:
            col, caption = stopped, "they freeze. eye contact."
        a.emit(CLEAR).emit(scene(sprite, col, caption))
        a.delay(DELAY_TICKS, f"f{f}")

    a.emit(CLEAR).emit(scene(sprite, stopped, "synchronous negotiation."))
    a.emit("\n   (this was the blank part of the file)\n\n")
    return a.end().source()


# --- the Python half: a quarterly A/B test readout ----------------------------

PYTHON = '''"""Q3 conversion experiment -- readout.

Two-proportion z-test on the checkout funnel, plus a 95% interval on the
lift. Standard library only, so it runs anywhere.

    python3 examples/quarterly_report.py

If you opened this file in an editor and scrolled past several thousand blank
lines to get here: those lines are not blank. They are a Whitespace program,
and they are an animation. See scripts/make-polyglot.py.
"""

from math import erf, sqrt

# control, treatment: (conversions, visitors)
ARMS = {"control": (1204, 24103), "treatment": (1319, 24044)}


def normal_cdf(z):
    return 0.5 * (1 + erf(z / sqrt(2)))


def two_proportion_z(c1, n1, c2, n2):
    """Pooled two-proportion z-test. Returns (z, two-sided p)."""
    p1, p2 = c1 / n1, c2 / n2
    pooled = (c1 + c2) / (n1 + n2)
    se = sqrt(pooled * (1 - pooled) * (1 / n1 + 1 / n2))
    z = (p2 - p1) / se
    return z, 2 * (1 - normal_cdf(abs(z)))


def lift_interval(c1, n1, c2, n2, zcrit=1.959964):
    """95% CI for the absolute difference in rates (unpooled SE)."""
    p1, p2 = c1 / n1, c2 / n2
    se = sqrt(p1 * (1 - p1) / n1 + p2 * (1 - p2) / n2)
    d = p2 - p1
    return d - zcrit * se, d + zcrit * se


def main():
    (c1, n1), (c2, n2) = ARMS["control"], ARMS["treatment"]
    p1, p2 = c1 / n1, c2 / n2
    z, p = two_proportion_z(c1, n1, c2, n2)
    lo, hi = lift_interval(c1, n1, c2, n2)

    print("Q3 CHECKOUT EXPERIMENT -- READOUT")
    print("=" * 52)
    print(f"{'arm':<12}{'visitors':>10}{'conv':>8}{'rate':>10}")
    print("-" * 52)
    for name, (c, n) in ARMS.items():
        print(f"{name:<12}{n:>10,}{c:>8,}{c / n:>9.2%}")
    print("-" * 52)
    print(f"{'absolute lift':<22}{p2 - p1:>+9.2%}")
    print(f"{'relative lift':<22}{(p2 - p1) / p1:>+9.2%}")
    print(f"{'95% CI (absolute)':<22}{f'[{lo:+.2%}, {hi:+.2%}]':>19}")
    print(f"{'z':<22}{z:>9.3f}")
    print(f"{'p (two-sided)':<22}{p:>9.4f}")
    print("=" * 52)

    if p < 0.05:
        print("Significant at the 5% level. The interval excludes zero.")
    else:
        print("Not significant at the 5% level. The interval covers zero.")
    print("Reminder: one test, one metric, pre-registered. Do not go fishing.")


if __name__ == "__main__":
    main()
'''


# --- assemble and verify ------------------------------------------------------


def main() -> None:
    ws = animation()
    assert set(ws) <= {" ", "\t", "\n"}, "the whitespace half is not pure whitespace"

    OUT.write_text(ws + PYTHON)
    lines = OUT.read_text().splitlines()
    blank = sum(1 for line in lines if line.strip() == "")
    print(f"wrote {OUT.relative_to(ROOT)}")
    print(f"  {OUT.stat().st_size:,} bytes, {len(lines):,} lines, "
          f"{blank:,} of them ({blank / len(lines):.1%}) look blank and are not")

    # 1. does it still run as Python?
    r = subprocess.run([sys.executable, str(OUT)], capture_output=True, text=True)
    assert r.returncode == 0, f"python half failed:\n{r.stderr}"
    assert "READOUT" in r.stdout and "p (two-sided)" in r.stdout
    print("  python half  : OK  ->", r.stdout.splitlines()[0])

    # 2. does the same file still run as Whitespace?
    frames = run(OUT.read_text())
    assert "BOSTON BIKE LANE" in frames
    assert "synchronous negotiation." in frames
    print(f"  whitespace   : OK  -> {frames.count(CLEAR)} frames, "
          f"{len(frames):,} chars of output")

    if "--run" in sys.argv:
        print("\nplaying (ctrl-c to stop)...\n")
        run(OUT.read_text(), out=sys.stdout)


if __name__ == "__main__":
    main()

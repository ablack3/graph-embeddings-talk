"""Turn the Riesz lecture script into audio via the ElevenLabs API.

    python3 scripts/make-audio.py --list                 # what voices can I use?
    python3 scripts/make-audio.py --list --search gwyn   # filter by name
    python3 scripts/make-audio.py --voice <VOICE_ID>     # render the ~15s clip
    python3 scripts/make-audio.py --voice <ID> --full    # the whole ~9min lecture

The key is read from the environment, never passed on the command line (it would
land in your shell history) and never committed:

    export ELEVENLABS_API_KEY=...        # or put it in .env, which is gitignored

Output goes to audio/, which is gitignored.

Note on voices: --list shows your own voices plus whatever the shared/licensed
library exposes to your account. Use a voice you actually have rights to. If you
want a specific person's voice, it has to be one they licensed to ElevenLabs --
that is what makes it legitimate, not the assumption that they wouldn't mind.
Stdlib only; no pip install.
"""

from __future__ import annotations

import argparse
import json
import os
import pathlib
import sys
import urllib.error
import urllib.parse
import urllib.request

API = "https://api.elevenlabs.io/v1"
ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "audio"

# The ~15 seconds actually played on the "How I actually study now" slide.
# Section 0 of slides/riesz-lecture.md, which is deliberately math-free so no
# TTS engine has to attempt LaTeX.
CLIP = (
    "It's Riesz. Frigyes Riesz, Hungarian, nineteen oh seven. "
    "Rhymes roughly with reece. Not Reitz. "
    "And be careful, because two different theorems carry his name. "
    "There's the one about representing functionals on continuous functions "
    "as integrals against a measure. That's not this one. "
    "This one is the Hilbert space version, and it is the one that quietly "
    "underwrites half of modern statistics."
)


def key() -> str:
    k = os.environ.get("ELEVENLABS_API_KEY")
    if not k:
        env = ROOT / ".env"
        if env.exists():
            for line in env.read_text().splitlines():
                if line.startswith("ELEVENLABS_API_KEY="):
                    k = line.split("=", 1)[1].strip().strip("\"'")
    if not k:
        sys.exit(
            "No ELEVENLABS_API_KEY found.\n"
            "  export ELEVENLABS_API_KEY=...   (or add it to .env)\n"
            "Do not paste the key into a chat window or into this file."
        )
    return k


def get(path: str, params: dict | None = None) -> dict:
    url = f"{API}{path}"
    if params:
        url += "?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(url, headers={"xi-api-key": key()})
    with urllib.request.urlopen(req) as r:
        return json.load(r)


def list_voices(search: str | None) -> None:
    rows = []
    try:
        for v in get("/voices").get("voices", []):
            rows.append((v.get("name", "?"), v.get("category", "?"), v.get("voice_id", "?")))
    except urllib.error.HTTPError as e:
        print(f"  /voices failed: {e.code} {e.reason}", file=sys.stderr)

    try:
        params = {"page_size": 100}
        if search:
            params["search"] = search
        for v in get("/shared-voices", params).get("voices", []):
            rows.append((v.get("name", "?"), f"shared/{v.get('category', '?')}",
                         v.get("voice_id", "?")))
    except urllib.error.HTTPError as e:
        print(f"  /shared-voices failed: {e.code} {e.reason}", file=sys.stderr)

    if search:
        rows = [r for r in rows if search.lower() in r[0].lower()]

    if not rows:
        print(f"No voices matched {search!r}." if search else "No voices found.")
        print(
            "\nIf you were looking for a specific person and they are not here,\n"
            "they have not licensed their voice to ElevenLabs. Pick a stock voice."
        )
        return

    print(f"{'name':32} {'category':22} voice_id")
    print("-" * 76)
    for name, cat, vid in sorted(rows):
        print(f"{name:32.32} {cat:22.22} {vid}")
    print("\nUse one you have rights to. Licensed 'iconic' voices carry usage terms;")
    print("read them before you put the clip in a recorded, published talk.")


def synth(voice_id: str, text: str, out: pathlib.Path, model: str) -> None:
    body = json.dumps({
        "text": text,
        "model_id": model,
        "voice_settings": {"stability": 0.5, "similarity_boost": 0.75},
    }).encode()
    req = urllib.request.Request(
        f"{API}/text-to-speech/{voice_id}",
        data=body,
        headers={"xi-api-key": key(), "Content-Type": "application/json",
                 "Accept": "audio/mpeg"},
    )
    try:
        with urllib.request.urlopen(req) as r:
            audio = r.read()
    except urllib.error.HTTPError as e:
        sys.exit(f"ElevenLabs returned {e.code}: {e.read().decode(errors='replace')[:400]}")

    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(audio)
    print(f"wrote {out.relative_to(ROOT)}  ({len(audio) / 1024:.0f} KB, "
          f"~{len(text.split()) / 150:.1f} min of speech)")


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--list", action="store_true", help="list available voices and exit")
    p.add_argument("--search", help="filter --list by name")
    p.add_argument("--voice", help="voice_id to synthesise with")
    p.add_argument("--full", action="store_true",
                   help="read a text file instead of the 15s clip")
    p.add_argument("--text-file", type=pathlib.Path,
                   help="plain text to read (use with --full)")
    p.add_argument("--model", default="eleven_multilingual_v2")
    p.add_argument("--out", type=pathlib.Path, default=OUT / "riesz-clip.mp3")
    a = p.parse_args()

    if a.list:
        return list_voices(a.search)
    if not a.voice:
        p.error("--voice is required (run --list to find one)")

    if a.full:
        if not a.text_file:
            p.error("--full needs --text-file: export the spoken parts of "
                    "slides/riesz-lecture.md to plain text first, converting the "
                    "equations to words as the production notes describe.")
        text = a.text_file.read_text()
    else:
        text = CLIP

    synth(a.voice, text, a.out, a.model)


if __name__ == "__main__":
    main()

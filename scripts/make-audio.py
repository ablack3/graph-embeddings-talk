"""Turn the Riesz lecture script into audio via the Speechify API.

    python3 scripts/make-audio.py --list                  # what voices can I use?
    python3 scripts/make-audio.py --list --search gwyn    # filter by name
    python3 scripts/make-audio.py --voice <VOICE_ID>      # render the ~15s clip
    python3 scripts/make-audio.py --voice <ID> --text-file notes.txt   # arbitrary text

Speechify, not ElevenLabs: the licensed Gwyneth Paltrow voice is a Speechify
partnership (see their homepage), so that is the service that has it.

The key is read from the environment, never passed on the command line (it would
land in your shell history) and never committed:

    export SPEECHIFY_API_KEY=...      # in ~/.zshenv, not ~/.zshrc -- see below
    # or put SPEECHIFY_API_KEY=... in .env, which is gitignored

~/.zshrc is only sourced by *interactive* shells, so a key exported there is
invisible to scripts and agents. ~/.zshenv is sourced by all zsh shells.

Output goes to audio/, which is gitignored.

A caveat worth checking before you build a bit around a specific voice: the
celebrity voices are marketed as a consumer-app feature, and it is not documented
whether they are exposed to the developer API. `--list` answers that against your
actual account rather than against anyone's assumption. If one is available,
skim the terms before putting it in a talk that gets recorded and posted.

API shape per docs.speechify.ai: POST /v1/audio/speech, GET /v1/voices.
Stdlib only; no pip install.
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import pathlib
import sys
import urllib.error
import urllib.parse
import urllib.request

API = "https://api.speechify.ai"
ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "audio"
DEFAULT_MODEL = "simba-3.2"
# Pin the API version so a server-side default roll cannot change output.
# Requests without this header get whatever "Latest" is that day.
API_VERSION = "2026-09-13"

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
    k = os.environ.get("SPEECHIFY_API_KEY")
    if not k:
        env = ROOT / ".env"
        if env.exists():
            for line in env.read_text().splitlines():
                if line.strip().startswith("SPEECHIFY_API_KEY="):
                    k = line.split("=", 1)[1].strip().strip("\"'")
    if not k:
        sys.exit(
            "No SPEECHIFY_API_KEY found.\n"
            "  export SPEECHIFY_API_KEY=...    (put it in ~/.zshenv, not ~/.zshrc:\n"
            "                                   .zshrc is interactive-shells-only)\n"
            "  or add SPEECHIFY_API_KEY=... to .env, which is gitignored.\n"
            "Do not paste the key into a chat window or into this file."
        )
    return k


def request(path: str, params: dict | None = None, body: dict | None = None) -> bytes:
    url = f"{API}{path}"
    if params:
        url += "?" + urllib.parse.urlencode(params)
    headers = {"Authorization": f"Bearer {key()}",
               "Speechify-Version": API_VERSION}
    data = None
    if body is not None:
        data = json.dumps(body).encode()
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=data, headers=headers)
    try:
        with urllib.request.urlopen(req) as r:
            return r.read()
    except urllib.error.HTTPError as e:
        detail = e.read().decode(errors="replace")[:500]
        hint = ""
        if e.code in (401, 403):
            hint = ("\nThat is an auth failure. Check the key is a Speechify key "
                    "(not the ElevenLabs one) and that it is still valid.")
        sys.exit(f"Speechify returned {e.code} {e.reason} for {path}:\n{detail}{hint}")


def list_voices(search: str | None, model: str) -> None:
    raw = json.loads(request("/v1/voices", {"model": model}))
    voices = raw if isinstance(raw, list) else raw.get("voices", raw.get("data", []))

    rows = []
    for v in voices:
        if not isinstance(v, dict):
            continue
        name = v.get("display_name") or v.get("name") or "?"
        vid = v.get("id") or v.get("voice_id") or "?"
        kind = v.get("type") or v.get("category") or v.get("gender") or ""
        tags = v.get("tags")
        if isinstance(tags, list):
            kind = (kind + " " + " ".join(str(t) for t in tags)).strip()
        rows.append((str(name), str(kind), str(vid)))

    if search:
        s = search.lower()
        rows = [r for r in rows if s in r[0].lower() or s in r[2].lower()]

    if not rows:
        print(f"No voices matched {search!r}." if search
              else "No voices returned for this account.")
        if search:
            print("\nRun without --search to see the full list. If a specific "
                  "person is\nnot in it, that voice is not exposed to the "
                  "developer API -- it is\napp-only. Pick a stock voice instead.")
        return

    print(f"{len(rows)} voice(s){' matching ' + repr(search) if search else ''}, "
          f"model={model}\n")
    print(f"{'name':30} {'tags':30} id")
    print("-" * 84)
    for name, kind, vid in sorted(rows):
        print(f"{name:30.30} {kind:30.30} {vid}")


def synth(voice_id: str, text: str, out: pathlib.Path, model: str, fmt: str) -> None:
    raw = request("/v1/audio/speech", body={
        "input": text,
        "voice_id": voice_id,
        "audio_format": fmt,
        "model": model,
    })

    # The endpoint returns JSON with base64 audio_data; tolerate raw bytes too.
    audio = raw
    if raw[:1] in (b"{", b"["):
        payload = json.loads(raw)
        b64 = payload.get("audio_data") or payload.get("audio") or payload.get("data")
        if not b64:
            sys.exit(f"No audio in response. Keys: {list(payload)[:10]}")
        audio = base64.b64decode(b64)

    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(audio)
    print(f"wrote {out.relative_to(ROOT)}  ({len(audio) / 1024:.0f} KB, "
          f"~{len(text.split()) / 150:.1f} min of speech)")


def main() -> None:
    p = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--list", action="store_true", help="list available voices and exit")
    p.add_argument("--search", help="filter --list by name or id")
    p.add_argument("--voice", help="voice id to synthesise with")
    p.add_argument("--text-file", type=pathlib.Path,
                   help="read this plain-text file instead of the built-in 15s clip")
    p.add_argument("--model", default=DEFAULT_MODEL)
    p.add_argument("--format", default="mp3", dest="fmt")
    p.add_argument("--out", type=pathlib.Path, default=OUT / "riesz-clip.mp3")
    a = p.parse_args()

    if a.list:
        return list_voices(a.search, a.model)
    if not a.voice:
        p.error("--voice is required (run --list to find one)")

    text = a.text_file.read_text() if a.text_file else CLIP
    synth(a.voice, text, a.out, a.model, a.fmt)


if __name__ == "__main__":
    main()

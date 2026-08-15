# Images for the deck

## The bike lane slide

The deck currently ships **hand-drawn SVG cross-sections** for Rotterdam vs.
Boston. They are inline in `lightning-talk.qmd` so the deck builds anywhere with
no assets and no licensing questions.

Real photographs are funnier. If you can get two, drop them here as
`img/rotterdam-bike-lane.jpg` and `img/boston-bike-lane.jpg` and replace each
```` ```{=html} ... ``` ```` SVG block on the "The bike lanes" slide with:

```markdown
![](img/rotterdam-bike-lane.jpg){width="100%"}
```

What to shoot, so the two photos actually make the argument:

| | Rotterdam | Boston |
|---|---|---|
| Frame | a protected lane at eye level | a painted lane at eye level |
| Must be visible | the raised kerb, the red asphalt, the separate footway | the paint stripe, moving traffic on one side, parked cars on the other |
| Bonus | someone cycling with a second person on the back rack | something parked in the lane — van, cones, police car |
| Avoid | wide aerial shots — the joke is the cross-section | anything at night; the paint has to read |

Shoot both at roughly the same focal length and from the same height. The gag is
that they are the *same photograph* of two different worlds.

### Licensing

Take them yourself, or use Wikimedia Commons / Openverse and put the
photographer and licence in small text under the image. Do not pull images off
Google Image search for a talk you are recording.

## The audio clip

The script is `riesz-lecture.md`; the generated audio is played from the
speaker's laptop and is not committed. Keep the clip to ~15 seconds and cue it
up before the talk starts — fumbling for it kills the joke.

Use your own voice or a stock/licensed synthetic one. Don't clone a named
celebrity: the talk gets recorded and posted, and an unlicensed voice likeness of
a real person is a genuine problem. The joke doesn't depend on it — the deck says
*"a synthetic voice that sounds suspiciously like a certain Oscar winner"*, which
lands on the contrast with "Riesz representation theorem" regardless of whose
voice it actually is.

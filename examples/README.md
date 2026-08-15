# Runnable examples

Five standalone scripts, in order of difficulty. Each one prints its results to
the console and writes a figure. Nothing is downloaded at runtime.

```bash
Rscript examples/01-hello-world.R
Rscript examples/02-four-families.R
Rscript examples/03-ontology-embedding.R
Rscript examples/04-drug-knowledge-graph.R
Rscript examples/05-deck-figures.R
```

Run them from the repository root. Script 01 needs nothing but base R; the rest
need `Matrix` and `igraph`, the same two packages the book uses.

| | Script | Needs | Runtime | Chapters |
|---|---|---|---|---|
| 1 | [01-hello-world.R](01-hello-world.R) | base R only | instant | 1–2 |
| 2 | [02-four-families.R](02-four-families.R) | Matrix, igraph | ~15 s | 2–7 |
| 3 | [03-ontology-embedding.R](03-ontology-embedding.R) | Matrix, igraph | ~5 s | 1, 4, 6 |
| 4 | [04-drug-knowledge-graph.R](04-drug-knowledge-graph.R) | Matrix, igraph | ~10 s | talk, part 2 |
| 5 | [05-deck-figures.R](05-deck-figures.R) | Matrix, igraph | ~15 s | the whole deck |

**04** is the *king − man + woman* demo on a drug knowledge graph: nearest
neighbours recover pharmacologic class, and analogies recover first-line
therapies. It ends with the systematic score over all 193 triples (45% top-1 vs
~12% chance), which is the number to quote rather than the two on the slide.

**quarterly_report.py** is not in the numbered sequence because it is a joke.
It is one file that is two programs. Run it with Python and you get an A/B test
readout; feed the same bytes to a Whitespace interpreter and you get an ASCII
animation. Whitespace ignores every visible character, and Python ignores
whitespace-only lines, so the two languages are blind to each other in exactly
complementary ways — 99% of that file's lines look blank and are not.

```bash
python3 examples/quarterly_report.py          # the businessy half
python3 scripts/make-polyglot.py --run        # the playful half
```

**05** is every computed thing in `slides/lightning-talk.qmd`, extracted from the
chunks into a script you can step through — the karate figures, the spectral
embedding, DeepWalk, the eigenvalue gap, the DeepWalk-vs-NetMF timing (measured
on your machine, not mine), and the Whitespace health check. Run it if you want
the deck's numbers without rendering the deck.

---

## 01 — Hello, world

Eight nodes, two triangles joined by a short path, no packages at all. Builds the
adjacency matrix by hand, shows why it is not enough, forms the Laplacian
`L = D - A`, and calls `eigen()`.

What you should see: the adjacency matrix scores node 1 against node 5 and node 8
identically (both zero) even though one is 3 hops away and the other 5. The
Fiedler vector fixes that. Across all 28 node pairs, the gap along that single
coordinate correlates **0.962** with hop distance.

The whole idea of the field is in that one number.

## 02 — The four families

Spectral, DeepWalk, NetMF and an untrained GCN on Zachary's karate club, at
matched dimension, scored the same way. Then link prediction on a random
geometric graph.

Three things to take away:

- **DeepWalk is not really a neural method.** Run its three stages by hand and
  compare the dot products SGD learned against the closed-form matrix NetMF
  writes down: the correlation goes 0.837 → 0.949 → 0.969 as you draw 5, 20 and
  80 walks per node. The gap was Monte Carlo error. NetMF gets there in one SVD,
  two orders of magnitude faster.
- Fitting the same matrix is not the same as producing the same embedding. The
  top-5 neighbour lists of DeepWalk and NetMF overlap only **0.63** — same
  target, different basis — while scoring identically downstream.
- **Run the heuristic baseline.** Counting mutual neighbours gets AUC 0.986 on
  link prediction. NetMF gets 0.989. If a pipeline cannot beat one line of code,
  it is not earning its complexity.

## 03 — A biomedical ontology

The example the talk is actually about. Chapter 1 claims that embedding a
clinical vocabulary "gives you a similarity between diagnoses that respects
clinical structure rather than string edit distance". This measures that claim on
the real Disease Ontology.

Parses OBO in twenty lines, builds the graph, embeds it with NetMF, then compares
the resulting neighbourhoods against edit distance on the same term names.

The result:

| query | edit distance says | the embedding says |
|---|---|---|
| pulmonary valve **disease** | pulmonary **artery** disease | pulmonary valve insufficiency |
| myocardial infarction | *(its own subtypes)* | *(its own subtypes)* |

Edit distance's top answer for *pulmonary valve disease* is *pulmonary artery
disease* — one word apart in the string, a different structure in the clinic,
five hops apart in the ontology. Over the whole vocabulary:

- the nearest neighbour returned by **edit distance** is 4+ hops away for
  **144 of 627 terms (23%)**
- for the **embedding** it is **14 of 627 (2%)**

Do not stop at the correlation between the two measures (0.53). They agree about
the easy 99% of pairs — most diseases are unrelated to most diseases — and
disagree exactly in the tail that retrieval touches.

The script closes with the hand-off to a transformer: the embedding is a
627 × 64 table keyed by DOID, and 260 of those terms carry an ICD-10-CM code, so
the row keys already line up with codes in the record.

### The data

`data/doid-cardiovascular.obo` — the 627 terms in the `is_a` subtree under
*cardiovascular system disease* (DOID:1287), extracted from Disease Ontology
release 2026-07-31. Provenance and the exact edits are in the file's own header
comments. Disease Ontology is CC0.

To refresh it against a newer release:

```bash
Rscript scripts/make-ontology-data.R
```

That is the only script in the repository that touches the network, and you never
need to run it — the excerpt is committed.

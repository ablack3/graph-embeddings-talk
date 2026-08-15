# Graph Embeddings in R

A Quarto book and a talk — *Graph Embeddings 101, or: How I Learned to Stop
Worrying and Love Claude Code* — on graph embeddings: what they are, the four
main algorithm families, how to implement each from scratch in base R, and how
to feed them into a transformer.

Every algorithm is implemented from scratch in `R/graphemb.R` using only base R
plus **Matrix** and **igraph**. Nothing is downloaded at runtime; every dataset
is generated or ships with igraph.

## Contents

| File | |
|---|---|
| `index.qmd` | Preface |
| `01-the-idea.qmd` | What an embedding is; the encoder–decoder framing; proximity vs. structural role |
| `02-spectral.qmd` | Laplacian eigenmaps, the eigengap, spectral clustering |
| `03-random-walks.qmd` | DeepWalk and node2vec; skip-gram with negative sampling written out and trained with hand-rolled SGD |
| `04-matrix-factorization.qmd` | NetMF — DeepWalk as an implicit matrix factorisation, verified numerically |
| `05-gnn.qmd` | GCN forward pass, over-smoothing, the inductive setting, GAT |
| `06-transformers.qmd` | Laplacian PE, RWSE, Graphormer-style attention bias; a worked demo where test accuracy goes 0.11 → 0.96 |
| `07-evaluation.qmd` | Link prediction, node classification, and five ways to fool yourself |
| `08-talk-script.qmd` | The 7-minute script, with timings and delivery notes |
| `slides/lightning-talk.qmd` | The deck |
| `R/graphemb.R` | All implementations |
| `examples/` | Three standalone scripts you can run without Quarto |

The slides `source()` the same `R/graphemb.R` as the book, so the numbers on the
slides and the numbers in the chapters cannot drift apart.

## Requirements

R ≥ 4.1 and [Quarto](https://quarto.org).

```r
install.packages(c("Matrix", "igraph"))
```

`ggplot2` is not required — all figures use base graphics.

## Examples

If you would rather run something than read something, start in
[`examples/`](examples/README.md). No Quarto required.

```bash
Rscript examples/01-hello-world.R        # 8 nodes, base R only, one call to eigen()
Rscript examples/02-four-families.R      # all four algorithm families, side by side
Rscript examples/03-ontology-embedding.R # 627 real diseases from the Disease Ontology
```

The third is the one worth your time: it takes chapter 1's claim that a graph
embedding "respects clinical structure rather than string edit distance" and
measures it. Edit distance sends you to a clinically distant concept for 23% of
the vocabulary; the embedding, for 2%.

## Build

```bash
quarto render                              # book → _book/
quarto render slides/lightning-talk.qmd    # deck → slides/lightning-talk.html
```

To check that every code chunk still runs without a full Quarto render:

```bash
Rscript scripts/verify-chunks.R            # all chapters + slides
Rscript scripts/verify-chunks.R 03-random-walks.qmd
```

That script uses knitr directly, so it evaluates chunks and inline `r ...`
expressions and honours `#| eval: false`. It does not check cross-references,
citations or layout — run `quarto render` for those.

## What's implemented

- **Spectral** — combinatorial / symmetric / random-walk Laplacians, eigenmaps
- **Random walks** — vectorised first-order walks via a CSR adjacency, biased
  second-order (node2vec) walks, windowed pair generation
- **Skip-gram with negative sampling** — minibatch SGD with scatter-add
  accumulation, the 3/4-power noise distribution, logit clamping
- **NetMF** — the closed-form matrix DeepWalk implicitly factorises
- **GCN** — renormalised adjacency, multi-layer forward pass
- **Transformer parts** — Laplacian positional encoding, RWSE, shortest-path
  attention bias, multi-head attention, layer norm, a full encoder block
- **Evaluation** — rank-based AUC, edge splitting, link prediction, k-NN
  accuracy

## A note on scale

Every example is small (34–300 nodes) and every implementation uses dense
matrices and interpreted loops, for readability. That is the wrong choice for a
real graph — `07-evaluation.qmd` says what to use instead.

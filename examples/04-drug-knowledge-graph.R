# 04 -- king - man + woman, for drugs -----------------------------------------
#
#   Rscript examples/04-drug-knowledge-graph.R
#
# This is the demo from Part 2 of the talk. The claim being tested is the one
# everybody has seen for words:
#
#     king - man + woman ~= queen
#
# and the question is whether the same arithmetic works on a graph -- whether
# "this drug, but for a different disease" is a *direction* in the embedding
# space.
#
# The graph (R/graphemb.R :: drug_kg) is 24 drugs joined to their molecular
# target, their pharmacologic class, and the conditions they treat. Crucially
# **no drug is joined directly to another drug**, so every similarity below has
# to travel through the structure. Nothing is downloaded.
#
# Read the caveats at the bottom before quoting any of this at anyone.
# -----------------------------------------------------------------------------

root <- if (file.exists("R/graphemb.R")) "." else ".."
source(file.path(root, "R", "graphemb.R"))

set.seed(1)


# 1. The graph ----------------------------------------------------------------

g <- drug_kg()
A <- as_adj_dense(g)

cat(sprintf("%d nodes, %d edges\n\n", vcount(g), ecount(g)))
print(table(type = V(g)$type))

stopifnot(
  # the constraint the whole demo rests on: no drug--drug edge
  !any(apply(as_edgelist(g), 1, function(e)
    all(V(g)$type[match(e, V(g)$name)] == "drug")))
)
cat("\nchecked: there are no drug-to-drug edges.\n")


# 2. Embed it -----------------------------------------------------------------
#
# DeepWalk: random walks as sentences, skip-gram with negative sampling. The
# graph is tiny, so we take more walks and more epochs than the karate club
# needs.

Z <- deepwalk(A, dim = 32, num_walks = 40, walk_length = 20, epochs = 20,
              seed = 1)
rownames(Z) <- V(g)$name


# 3. Does it know what a drug class is? ---------------------------------------
#
# Nothing in the graph says "these three drugs are alike". It says each of them
# points at ADRB1 and at the beta_blocker node. If the embedding recovers the
# class, it did so from structure alone.

cat("\n--- nearest to metoprolol -------------------------------------------\n")
print(round(nearest(Z, Z["metoprolol", ], k = 5, exclude = "metoprolol"), 3))

cat("\n--- nearest to omeprazole -------------------------------------------\n")
print(round(nearest(Z, Z["omeprazole", ], k = 5, exclude = "omeprazole"), 3))


# 4. The parallelogram --------------------------------------------------------

ask <- function(a, b, c) {
  cat(sprintf("\n--- %s - %s + %s\n    (%s is to %s as ??? is to %s)\n",
              a, b, c, a, b, c))
  print(round(analogy(Z, a, b, c, k = 5), 3))
}

ask("atorvastatin", "hyperlipidemia", "depression")      # expect an SSRI
ask("lisinopril",   "hypertension",   "type_2_diabetes") # expect metformin
ask("ibuprofen",    "osteoarthritis", "gerd")            # expect a PPI
ask("apixaban",     "F10",            "SLC6A4")          # swap the target


# 5. How often does it actually work? -----------------------------------------
#
# Four hand-picked analogies is anecdote. Here is every (drug, its indication,
# other indication) triple in the graph, scored by whether the top hit is a drug
# that really does treat the third term. This is the number to quote, not the
# four above.

spec_ind <- lapply(V(g)$name[V(g)$type == "drug"], function(d)
  intersect(names(neighbors(g, d)), V(g)$name[V(g)$type == "indication"]))
names(spec_ind) <- V(g)$name[V(g)$type == "drug"]
inds <- V(g)$name[V(g)$type == "indication"]

hits <- 0L; total <- 0L
for (d in names(spec_ind)) {
  for (b in spec_ind[[d]]) {
    for (cc in setdiff(inds, spec_ind[[d]])) {
      top <- names(analogy(Z, d, b, cc, k = 1))
      total <- total + 1L
      if (length(top) && top %in% names(spec_ind) && cc %in% spec_ind[[top]])
        hits <- hits + 1L
    }
  }
}
cat(sprintf(
  "\n\nTop-1 is a correct drug for the target indication in %d / %d triples (%.0f%%).\n",
  hits, total, 100 * hits / total))
cat(sprintf("Chance, if it picked a drug uniformly at random: about %.0f%%.\n",
            100 * 3 / 24))


# 6. Caveats, which are the point ---------------------------------------------
#
#   * This graph is clean by construction. I wrote it. Every class holds exactly
#     three interchangeable drugs -- precisely the parallel structure the
#     parallelogram needs. Real vocabularies (RxNorm, SNOMED, the OMOP concept
#     hierarchy) are not this tidy, and the analogy degrades fast when the
#     structure is ragged.
#
#   * 55 nodes means analogy() is choosing among ~50 candidates, and node type
#     rules out most of them before cosine similarity does any work.
#
#   * `analogy()` excludes its own three input terms, exactly as the original
#     word2vec evaluation code does. Without that exclusion the nearest vector
#     to "a - b + c" is very often just `a`. That exclusion is doing real work
#     here too -- comment it out and see.
#
#   * Drug repurposing by vector subtraction is a genuine research area and it
#     does not work this cleanly on real data.
#
# The defensible claim: the geometry is doing something real -- it recovered
# pharmacologic class from pure structure -- and analogies are a fast, cheap way
# to *inspect* what an embedding learned. Not to make clinical decisions with.

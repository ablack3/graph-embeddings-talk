# 05 -- Every computed thing in the talk --------------------------------------
#
#   Rscript examples/05-deck-figures.R
#
# The slides in slides/lightning-talk.qmd compute their numbers and figures at
# render time, inside code chunks. That is good for the deck (nothing can go
# stale) and bad for you (you cannot run it without rendering). So this script
# is the same code, in order, as a plain script you can step through.
#
# Section numbers below match the slides:
#
#   1  "Start from the top: what is a graph?"   the karate club
#   2  "What is an embedding?"                  spectral, 2D
#   3  "Now do it for a graph"                  DeepWalk + 5-NN accuracy
#   4  "The other route: factorise something"   the eigenvalue gap
#   5  "They're all the same algorithm"         DeepWalk vs NetMF, timed
#   6  "A drug knowledge graph"                 the Part 2 demo, in brief
#   7  "So we wrote it"                         the Whitespace health check
#
# Section 6 is deliberately short because examples/04-drug-knowledge-graph.R
# does that demo properly, including the all-193-triples evaluation. Run that
# one if the analogies are what you came for.
#
# Figures go to examples/figures/, which is gitignored.
# -----------------------------------------------------------------------------

root <- if (file.exists("R/graphemb.R")) "." else ".."
source(file.path(root, "R", "graphemb.R"))
FIG <- file.path(root, "examples", "figures")
dir.create(FIG, showWarnings = FALSE, recursive = TRUE)

set.seed(1)

# The palette the deck uses.
blue <- "#4C72B0"; orange <- "#DD8452"; green <- "#55A868"

fig <- function(name, width = 7, height = 5.5) {
  if (!interactive()) png(file.path(FIG, name), width = width, height = height,
                          units = "in", res = 150)
}
endfig <- function(name) {
  if (!interactive()) {
    invisible(dev.off())
    cat("  figure ->", file.path(FIG, name), "\n")
  }
}

rule <- function(x) cat("\n\n", strrep("-", 78), "\n", x, "\n\n", sep = "")


# 1. The karate club ----------------------------------------------------------
#
# 34 people, 78 friendships, one club that split in two. The labels are the
# faction each person actually joined; no algorithm below ever sees them.

rule("1. The graph")

g   <- karate_graph()
A   <- as_adj_dense(g)
lab <- V(g)$label
fac_col <- ifelse(lab == "Mr Hi", blue, orange)

cat(sprintf("%d nodes, %d edges, %.0f%% of the adjacency matrix is zero\n",
            vcount(g), ecount(g), 100 * mean(A == 0)))
print(table(faction = lab))

fig("05-karate.png", 6, 6)
set.seed(4)
par(mar = c(0, 0, 0, 0))
plot(g, layout = layout_with_fr(g), vertex.color = fac_col,
     vertex.label.color = "white", vertex.size = 16,
     vertex.label.cex = 0.75, edge.color = "grey75")
endfig("05-karate.png")


# 2. Spectral embedding -------------------------------------------------------
#
# Four lines: form the Laplacian, take the eigenvectors with the smallest
# eigenvalues, drop the trivial constant one. Axis 1 alone separates the
# factions -- the slide claims 33 of 34, and this is where that number is from.

rule("2. Spectral embedding, and the claim that axis 1 gets 33 of 34")

Z <- spectral_embedding(A, d = 2)

# Sign of an eigenvector is arbitrary, so score both orientations and keep the
# better one. That is what "33 of 34" means: the best split at zero on axis 1.
side  <- Z[, 1] > 0
acc1  <- max(mean(side == (lab == "Mr Hi")), mean(side != (lab == "Mr Hi")))
cat(sprintf("axis 1, thresholded at zero: %d of %d correct (%.0f%%)\n",
            round(acc1 * vcount(g)), vcount(g), 100 * acc1))

cat(sprintf(paste("node 9 is the honest one: it joined the officers despite being",
                  "better\nconnected to the instructor, and lands near the",
                  "middle. Axis-1 score %.4f\n"), Z[9, 1]))

fig("05-spectral.png", 6.5, 5)
par(mar = c(4, 4, 1, 1))
plot(Z[, 1], Z[, 2], type = "n", xlab = "dimension 1", ylab = "dimension 2")
abline(v = 0, col = "grey85", lty = 2)
text(Z[, 1], Z[, 2], labels = seq_len(nrow(Z)), cex = 0.9, col = fac_col)
endfig("05-spectral.png")


# 3. DeepWalk -----------------------------------------------------------------
#
# Random walks are sentences; nodes are words; run skip-gram with negative
# sampling on them. ~60 lines of base R and nothing in it is O(n^2).

rule("3. DeepWalk -- random walks as sentences")

walks <- random_walks(A, num_walks = 10, walk_length = 40)
pairs <- walks_to_pairs(walks, window = 5)
cat(sprintf("%d walks x %d steps -> %d training pairs\n",
            nrow(walks), ncol(walks), nrow(pairs)))

Z_dw <- deepwalk(A, dim = 32, epochs = 5, seed = 1)
cat(sprintf("5-NN accuracy in the embedding: %.2f\n",
            knn_accuracy(Z_dw, lab, 5)))

fig("05-deepwalk.png", 6, 5)
px <- prcomp(Z_dw)$x[, 1:2]
par(mar = c(4, 4, 2, 1))
plot(px, type = "n", xlab = "PC1", ylab = "PC2",
     main = sprintf("DeepWalk, 5-NN accuracy: %.2f", knn_accuracy(Z_dw, lab, 5)))
text(px[, 1], px[, 2], labels = seq_len(nrow(A)), cex = 0.85, col = fac_col)
endfig("05-deepwalk.png")


# 4. The eigenvalue gap -------------------------------------------------------
#
# Free bonus from the spectral route: the number of near-zero eigenvalues of the
# normalised Laplacian is the number of connected-ish communities. Nobody tells
# it three.

rule("4. Counting communities for free")

g3 <- sbm_graph(n_per = 40, k = 3, p_in = 0.14, p_out = 0.01, seed = 42)
ev <- sort(eigen(graph_laplacian(as_adj_dense(g3), "sym"), symmetric = TRUE)$values)
cat("smallest six eigenvalues of the normalised Laplacian:\n")
print(round(ev[1:6], 3))
cat(sprintf("\nlargest gap is after eigenvalue %d -> %d communities (truth: 3)\n",
            which.max(diff(ev[1:6])), which.max(diff(ev[1:6]))))

fig("05-eigengap.png", 6, 4)
par(mar = c(4, 4, 2, 1))
plot(ev[1:12], type = "b", pch = 19, col = blue,
     xlab = "index", ylab = "eigenvalue", main = "Three near zero, then a jump")
abline(v = 3.5, lty = 2, col = "grey60")
endfig("05-eigengap.png")


# 5. They're all the same algorithm -------------------------------------------
#
# Skip-gram provably converges to a factorisation of a PMI matrix (Levy &
# Goldberg 2014), and for random walks that matrix is closed form (Qiu et al.
# 2018). So compute it directly and take an SVD. Same answer, ~1000x faster --
# this is the timing table on the slide, and it is timed on your machine.

rule("5. DeepWalk vs NetMF -- sample it, or just factorise it")

t_dw <- system.time(Zd <- deepwalk(A, dim = 32, epochs = 5, seed = 1))[["elapsed"]]
t_nm <- system.time(Zn <- netmf(A, dim = 32))[["elapsed"]]

print(data.frame(
  method    = c("DeepWalk (sampled)", "NetMF (SVD)"),
  seconds   = signif(c(t_dw, t_nm), 3),
  `5NN_acc` = c(knn_accuracy(Zd, lab, 5), knn_accuracy(Zn, lab, 5)),
  check.names = FALSE
), row.names = FALSE)

cat(sprintf("\nspeedup: %.0fx\n", t_dw / max(t_nm, 1e-6)))
cat("\nWhich matrix each method factorises:\n")
print(data.frame(
  method     = c("Spectral", "DeepWalk / NetMF", "node2vec", "LINE"),
  factorises = c("I - D^-1/2 A D^-1/2", "log max(M, 1)",
                 "M with 2nd-order P", "M with T = 1"),
  check.names = FALSE
), row.names = FALSE)


# 6. The drug knowledge graph, in brief ---------------------------------------
#
# The headline numbers from Part 2. examples/04-drug-knowledge-graph.R does this
# properly, with the systematic evaluation over all 193 triples.

rule("6. Drug knowledge graph (see 04 for the full version)")

gk <- drug_kg()
set.seed(1)
Zk <- deepwalk(as_adj_dense(gk), dim = 32, num_walks = 40, walk_length = 20,
               epochs = 20, seed = 1)
rownames(Zk) <- V(gk)$name

cat(sprintf("%d nodes, %d edges, no drug-to-drug edge\n\n",
            vcount(gk), ecount(gk)))

cat("nearest to metoprolol:\n")
print(round(nearest(Zk, Zk["metoprolol", ], k = 5, exclude = "metoprolol"), 3))

cat("\natorvastatin - hyperlipidemia + depression:\n")
print(round(analogy(Zk, "atorvastatin", "hyperlipidemia", "depression", 5), 3))

cat("\nlisinopril - hypertension + type_2_diabetes:\n")
print(round(analogy(Zk, "lisinopril", "hypertension", "type_2_diabetes", 5), 3))

fig("05-drug-kg.png", 7, 6)
tcol <- c(drug = blue, target = green, class = orange,
          indication = "#8172B2", system = "#937860")
set.seed(11)
par(mar = c(0, 0, 0, 0))
plot(gk, layout = layout_with_fr(gk),
     vertex.color = tcol[V(gk)$type], vertex.frame.color = NA,
     vertex.size = ifelse(V(gk)$type == "drug", 6, 9),
     vertex.label = ifelse(V(gk)$type == "drug", NA, V(gk)$name),
     vertex.label.cex = 0.6, vertex.label.color = "black",
     vertex.label.dist = 0.8, edge.color = "grey80")
endfig("05-drug-kg.png")


# 7. The Whitespace health check ----------------------------------------------
#
# The closing joke, which is a real program. scripts/whitespace.py compiles and
# interprets it; this just reads the bytes the slide displays.

rule("7. The health check endpoint")

ws_path <- file.path(root, "examples", "healthcheck.ws")
if (file.exists(ws_path)) {
  raw <- readChar(ws_path, file.size(ws_path), useBytes = TRUE)
  cat(sprintf("%s is %d bytes, %d distinct characters\n",
              basename(ws_path), nchar(raw, type = "bytes"),
              length(unique(strsplit(raw, "")[[1]]))))
  cat("\nwhat every editor shows you:\n[", raw, "]\n", sep = "")
  cat("\nwhat is actually there:\n")
  cat(gsub("\n", "$\n", gsub("\t", "→", gsub(" ", "·", raw))))
  cat("\nrun `python3 scripts/whitespace.py` to compile and execute it.\n")
} else {
  cat("missing -- run: python3 scripts/whitespace.py --emit\n")
}

rule("Done. Figures are in examples/figures/.")

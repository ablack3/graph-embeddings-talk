# 02 -- The four families, side by side ---------------------------------------
#
#   Rscript examples/02-four-families.R
#
# Example 01 built an embedding out of one eigenvector. This runs all four
# algorithm families on the same graph, at the same dimension, scored the same
# way, so the differences between them are visible rather than asserted.
#
#   spectral   eigenvectors of the Laplacian            (chapter 2)
#   DeepWalk   random walks + skip-gram, trained by SGD (chapter 3)
#   NetMF      the matrix DeepWalk implicitly fits      (chapter 4)
#   GCN        message passing, here with no training   (chapter 5)
#
# Two sections: does the embedding know the communities, and does it predict
# missing edges. The second one has a punchline you should not skip.
# -----------------------------------------------------------------------------

root <- if (file.exists("R/graphemb.R")) "." else ".."
source(file.path(root, "R", "graphemb.R"))
FIG <- file.path(root, "examples", "figures")

set.seed(1)
DIM <- 32                    # matched across methods -- see trap 4 in chapter 7


# A. Do they recover the communities? -----------------------------------------
#
# Zachary's karate club: 34 members, 78 friendships, and a documented schism.
# No method below is shown the faction labels; they are only used to score.

g <- karate_graph()
A <- as_adj_dense(g)
lab <- V(g)$label

run <- function(expr) {
  t <- system.time(Z <- eval(expr))[["elapsed"]]
  list(Z = Z, seconds = t)
}

fits <- list(
  Spectral = run(quote(spectral_embedding(A, d = 8))),
  DeepWalk = run(quote(deepwalk(A, dim = DIM, epochs = 5, seed = 1))),
  NetMF    = run(quote(netmf(A, dim = DIM, T_window = 5))),
  `GCN (untrained)` = run(quote(
    gcn_forward(A, diag(nrow(A)), gcn_random_weights(c(nrow(A), 64, DIM), seed = 3))
  ))
)

cat("Karate club: 5-nearest-neighbour faction accuracy\n\n")
print(data.frame(
  method = names(fits),
  seconds = round(sapply(fits, `[[`, "seconds"), 3),
  knn_accuracy = round(sapply(fits, function(f) knn_accuracy(f$Z, lab, k = 5)), 3)
), row.names = FALSE)

cat("\nMajority-class baseline:",
    round(max(table(lab)) / length(lab), 3), "\n")


# B. DeepWalk is fitting a matrix you can write down --------------------------
#
# DeepWalk looks like a neural method. It is not. Skip-gram with negative
# sampling provably converges to a factorisation of a shifted PMI matrix, and
# for random walks that matrix has a closed form -- which is all NetMF is:
#
#   M = vol(G)/(bT) * (sum_{r=1..T} P^r) D^-1,     P = D^-1 A
#
# So run DeepWalk's three stages by hand, and compare the dot products it
# learned against the matrix NetMF writes down directly. Draw more walks and the
# gap shrinks, because the gap was Monte Carlo error all along.

n <- nrow(A)
K <- 5
M <- netmf_matrix(A, T_window = 5, b = 1, truncate = FALSE)

agree <- t(sapply(c(5, 20, 80), function(w) {
  walks <- random_walks(A, num_walks = w, walk_length = 40, seed = 1)
  # shrink = FALSE: word2vec's shrinking window targets a DIFFERENT matrix, so
  # leaving it on makes the two methods disagree forever. See chapter 4.
  P <- walks_to_pairs(walks, window = 5, shrink = FALSE, seed = 1)
  fit <- skipgram_sgns(P, n_nodes = n, dim = DIM, epochs = 5, neg = K, seed = 1)

  Cnt <- matrix(0, n, n)                       # observed co-occurrence counts
  tb <- table(P[, 1], P[, 2])
  Cnt[cbind(as.integer(rownames(tb))[row(tb)],
            as.integer(colnames(tb))[col(tb)])] <- as.vector(tb)

  scored <- Cnt > 20 & is.finite(M)            # pairs seen often enough to judge
  c(`walks/node` = w, pairs = nrow(P), scored = sum(scored),
    correlation = round(cor((fit$W %*% t(fit$C))[scored], (M - log(K))[scored]), 3))
}))

cat("\nSGD-learned dot products vs NetMF's closed form\n\n")
print(as.data.frame(agree), row.names = FALSE)

cat(sprintf("\nNetMF reaches the same target in one SVD: %.0fx faster than the\n",
            fits$DeepWalk$seconds / max(fits$NetMF$seconds, 1e-4)))
cat("sampled version here, and deterministic.\n")

# Worth being precise about what this does and does not show. The two methods
# fit the same MATRIX; they do not produce the same EMBEDDING. SGNS learns an
# asymmetric factorisation (a centre vector and a context vector per node) and
# its 32 dimensions need not span NetMF's 32. On retrieval they overlap only
# partially -- and score identically downstream.
topk <- function(Z, k = 5) {
  S <- cosine_sim(Z); diag(S) <- -Inf
  lapply(seq_len(nrow(Z)), function(i) order(S[i, ], decreasing = TRUE)[1:k])
}
overlap <- mapply(function(a, b) length(intersect(a, b)) / 5,
                  topk(fits$DeepWalk$Z), topk(fits$NetMF$Z))
cat(sprintf("\nMean overlap of top-5 neighbour lists: %.2f (same target, different basis)\n",
            mean(overlap)))


# C. Link prediction, and the baseline that spoils the party ------------------
#
# Node classification saturates on the karate club, so switch to a graph with
# real latent geometry: 300 points in the unit square, joined when close.
#
# The rule that makes this an honest test: hold the edges out BEFORE embedding.
# Embed the full graph and then "predict" edges the embedder already saw and you
# will report an AUC near 1.0 and be delighted with yourself.

gg <- geo_graph(n = 300, radius = 0.115, seed = 7)
sp <- edge_split(gg, frac = 0.15, seed = 3)
A_tr <- as_adj_dense(sp$g_train)

cat(sprintf("\nGeometric graph: %d nodes, %d edges, %d held out\n",
            vcount(gg), ecount(gg), nrow(sp$pos)))

# the baseline: count the friends two nodes have in common. One line, no
# hyperparameters, no training.
common_neighbours <- function(A, e) rowSums(A[e[, 1], ] * A[e[, 2], ])

lp <- data.frame(
  method = c("Common neighbours (no embedding)",
             "Spectral (d=16)", "NetMF (d=32)", "DeepWalk (d=32)"),
  auc = round(c(
    auc(c(common_neighbours(A_tr, sp$pos), common_neighbours(A_tr, sp$neg)),
        c(rep(1, nrow(sp$pos)), rep(0, nrow(sp$neg)))),
    link_pred_auc(spectral_embedding(A_tr, d = 16), sp$pos, sp$neg),
    link_pred_auc(netmf(A_tr, dim = DIM), sp$pos, sp$neg),
    link_pred_auc(deepwalk(A_tr, dim = DIM, num_walks = 5, walk_length = 30,
                           epochs = 5, seed = 2), sp$pos, sp$neg)
  ), 3)
)
cat("\nLink prediction AUC\n\n")
print(lp[order(-lp$auc), ], row.names = FALSE)

cat("\nIf your pipeline cannot beat 'count the mutual friends', the pipeline\n")
cat("is not earning its complexity. Run the baseline first, every time.\n")
cat("\n(DeepWalk trails here because it is deliberately under-sampled at 5\n")
cat("walks/node -- the Monte Carlo cost section B just measured. That variance\n")
cat("is real, which is why stochastic methods need a spread over seeds, not one\n")
cat("run. See chapter 7.)\n")


# D. Look at them -------------------------------------------------------------

dir.create(FIG, showWarnings = FALSE, recursive = TRUE)
if (!interactive()) png(file.path(FIG, "02-four-families.png"),
                        width = 1100, height = 900, res = 110)
par(mfrow = c(2, 2), mar = c(4, 4, 2.5, 1))
for (nmm in names(fits)) {
  px <- prcomp(fits[[nmm]]$Z)$x[, 1:2]              # project to 2D for the eye only
  plot(px, type = "n", xlab = "PC1", ylab = "PC2",
       main = sprintf("%s  (5-NN %.2f)", nmm, knn_accuracy(fits[[nmm]]$Z, lab, 5)))
  text(px[, 1], px[, 2], labels = seq_len(nrow(A)), cex = 0.75,
       col = ifelse(lab == "Mr Hi", "#4C72B0", "#DD8452"))
}
if (!interactive()) {
  invisible(dev.off())
  cat("\nfigure written to", file.path(FIG, "02-four-families.png"), "\n")
}

# graphemb.R -----------------------------------------------------------------
#
# A small, dependency-light reference implementation of the graph-embedding
# algorithms used throughout the book and the lightning talk.
#
# Everything here is base R + Matrix + igraph. Nothing is compiled, nothing is
# downloaded. The point is that you can read every line in an afternoon.
#
#   source("R/graphemb.R")
#
# Sections
#   0. small utilities
#   1. example graphs
#   2. spectral embeddings         (Laplacian eigenmaps)
#   3. random-walk embeddings      (DeepWalk / node2vec + skip-gram SGNS)
#   4. matrix factorisation        (NetMF: what DeepWalk is really doing)
#   5. graph neural networks       (GCN forward pass)
#   6. transformer ingredients     (Laplacian PE, RWSE, SPD bias, attention)
#   7. evaluation                  (link prediction AUC, kNN node classification)
# -----------------------------------------------------------------------------

suppressPackageStartupMessages({
  library(Matrix)
  library(igraph)
})


# 0. small utilities -----------------------------------------------------------

#' Row-wise L2 normalisation (rows of length 0 are left alone)
normalize_rows <- function(X) {
  nrm <- sqrt(rowSums(X^2))
  nrm[nrm == 0] <- 1
  X / nrm
}

#' Cosine similarity matrix between the rows of X
cosine_sim <- function(X) {
  Z <- normalize_rows(X)
  Z %*% t(Z)
}

#' Numerically stable row-wise softmax
softmax_rows <- function(S) {
  S <- S - apply(S, 1, max)
  E <- exp(S)
  E / rowSums(E)
}

sigmoid <- function(x) 1 / (1 + exp(-x))

relu <- function(x) pmax(x, 0)

#' Scatter-add: M[idx[i], ] <- M[idx[i], ] + vals[i, ], summing duplicate idx.
#' This is the vectorised replacement for a per-example SGD update loop.
scatter_add <- function(M, idx, vals) {
  agg <- rowsum(vals, group = idx, reorder = FALSE)
  ii  <- as.integer(rownames(agg))
  M[ii, ] <- M[ii, ] + agg
  M
}

#' Adjacency matrix of an igraph object, as a plain dense numeric matrix.
#' (These graphs are tiny; sparse storage is a distraction at this scale.)
as_adj_dense <- function(g) {
  as.matrix(igraph::as_adjacency_matrix(g, sparse = FALSE))
}

#' Sign-align the columns of B to those of A. Eigenvectors are only defined up
#' to sign, which makes comparing two runs confusing unless you fix a
#' convention. Used for plots and tests, never for the maths.
align_signs <- function(A, B) {
  s <- sign(colSums(A * B))
  s[s == 0] <- 1
  sweep(B, 2, s, `*`)
}


# 1. example graphs -----------------------------------------------------------

#' Zachary's karate club: 34 members, 78 friendships, and a famous schism.
#' The ground-truth split (Mr Hi vs Officer) is returned as `label`.
karate_graph <- function() {
  g <- igraph::make_graph("Zachary")
  igraph::V(g)$name <- as.character(seq_len(igraph::vcount(g)))
  # The canonical faction split (Zachary 1977, Table 3).
  hi <- c(1, 2, 3, 4, 5, 6, 7, 8, 11, 12, 13, 14, 17, 18, 20, 22)
  lab <- rep("Officer", igraph::vcount(g))
  lab[hi] <- "Mr Hi"
  igraph::V(g)$label <- lab
  g
}

#' A planted-partition (stochastic block model) graph: k communities, dense
#' inside, sparse between. The ground truth is known by construction, which
#' makes it the right test bed for "does my embedding recover structure?".
sbm_graph <- function(n_per = 40, k = 3, p_in = 0.14, p_out = 0.01, seed = 42) {
  set.seed(seed)
  P <- matrix(p_out, k, k)
  diag(P) <- p_in
  g <- igraph::sample_sbm(n_per * k, P, rep(n_per, k))
  igraph::V(g)$label <- as.character(rep(seq_len(k), each = n_per))
  igraph::V(g)$name  <- as.character(seq_len(igraph::vcount(g)))
  g
}

#' A random geometric graph: points dropped in the unit square, joined when
#' they are within `radius`. There is a real latent geometry here, so it is the
#' honest test of "did the embedding recover the structure that generated the
#' edges?" -- and, unlike an SBM, of whether link prediction is learnable at all.
#' The true coordinates come back as `x` and `y` vertex attributes.
geo_graph <- function(n = 300, radius = 0.115, seed = 7) {
  set.seed(seed)
  g <- igraph::sample_grg(n, radius, coords = TRUE)
  igraph::V(g)$name <- as.character(seq_len(igraph::vcount(g)))
  # keep the largest component so that distances are finite
  comp <- igraph::components(g)
  g <- igraph::induced_subgraph(g, which(comp$membership == which.max(comp$csize)))
  g
}

#' A barbell: two cliques joined by a path. The graph where "close together"
#' and "same structural role" disagree, which is the point of node2vec's q.
barbell_graph <- function(clique = 6, path = 5) {
  g <- igraph::make_full_graph(clique) + igraph::make_full_graph(clique)
  g <- g + igraph::make_ring(path, circular = FALSE)
  n <- clique
  p0 <- 2 * clique + 1
  g <- igraph::add_edges(g, c(1, p0, p0 + path - 1, n + 1))
  igraph::V(g)$name <- as.character(seq_len(igraph::vcount(g)))
  g
}


# 2. spectral embeddings ------------------------------------------------------

#' Graph Laplacians.
#'   comb : L   = D - A            (the quadratic form is sum_ij A_ij (f_i-f_j)^2)
#'   sym  : Lsym = I - D^-1/2 A D^-1/2
#'   rw   : Lrw  = I - D^-1 A      (generator of the lazy random walk)
graph_laplacian <- function(A, type = c("sym", "comb", "rw")) {
  type <- match.arg(type)
  d <- rowSums(A)
  n <- nrow(A)
  switch(type,
    comb = diag(d) - A,
    sym  = {
      dm <- ifelse(d > 0, 1 / sqrt(d), 0)
      diag(n) - (dm * A) * rep(dm, each = n)   # D^-1/2 A D^-1/2
    },
    rw   = {
      dm <- ifelse(d > 0, 1 / d, 0)
      diag(n) - dm * A                          # D^-1 A
    }
  )
}

#' Laplacian eigenmap embedding: the d eigenvectors of L with the smallest
#' non-trivial eigenvalues. These are the smoothest non-constant functions on
#' the graph -- the coordinates that change least along edges.
#'
#' @param A adjacency matrix
#' @param d number of dimensions
#' @param type Laplacian to use
#' @param drop_first drop the trivial constant eigenvector (eigenvalue 0)
spectral_embedding <- function(A, d = 2, type = c("sym", "comb", "rw"),
                               drop_first = TRUE) {
  type <- match.arg(type)
  L <- graph_laplacian(A, type)
  ev <- eigen(if (type == "rw") (L + t(L)) / 2 else L, symmetric = TRUE)
  # eigen() returns eigenvalues in decreasing order; we want the smallest.
  ord <- rev(seq_len(ncol(ev$vectors)))
  V <- ev$vectors[, ord, drop = FALSE]
  lam <- ev$values[ord]
  keep <- if (drop_first) seq(2, d + 1) else seq_len(d)
  Z <- V[, keep, drop = FALSE]
  if (type == "sym") {
    # map back from the symmetric to the random-walk eigenvectors
    dm <- ifelse(rowSums(A) > 0, 1 / sqrt(rowSums(A)), 0)
    Z <- Z * dm
  }
  colnames(Z) <- paste0("dim", seq_len(ncol(Z)))
  structure(Z, eigenvalues = lam[keep], class = c("graph_embedding", "matrix"))
}


# 3. random-walk embeddings ---------------------------------------------------

#' Compressed sparse row view of an adjacency matrix, so that a random-walk
#' step is a single vectorised gather instead of a loop over walkers.
build_csr <- function(A) {
  n <- nrow(A)
  e <- which(A > 0, arr.ind = TRUE)
  e <- e[order(e[, 1]), , drop = FALSE]
  deg <- tabulate(e[, 1], nbins = n)
  list(nbr = as.integer(e[, 2]),
       ptr = as.integer(c(0L, cumsum(deg))),
       deg = as.integer(deg),
       n   = n)
}

#' One uniform random-walk step for a whole vector of walkers at once.
#' Isolated nodes stay where they are.
walk_step <- function(csr, cur) {
  d  <- csr$deg[cur]
  ok <- d > 0
  out <- cur
  if (any(ok)) {
    off <- csr$ptr[cur[ok]] + 1L + floor(stats::runif(sum(ok)) * d[ok])
    out[ok] <- csr$nbr[off]
  }
  out
}

#' First-order (DeepWalk) random walks.
#'
#' @return integer matrix, one walk per row, `walk_length` columns
random_walks <- function(A, num_walks = 10, walk_length = 40, seed = 1) {
  set.seed(seed)
  csr <- build_csr(A)
  n <- csr$n
  starts <- rep(seq_len(n), times = num_walks)
  starts <- sample(starts)                       # shuffle, as in the paper
  W <- matrix(0L, nrow = length(starts), ncol = walk_length)
  W[, 1] <- starts
  for (t in 2:walk_length) W[, t] <- walk_step(csr, W[, t - 1])
  W
}

#' Second-order (node2vec) random walks.
#'
#' The unnormalised probability of stepping from `v` (arrived from `u`) to a
#' neighbour `x` is
#'   1/p  if x == u          (go back)
#'   1    if x ~ u           (stay in the neighbourhood: BFS-ish)
#'   1/q  otherwise          (move outward: DFS-ish)
#'
#' p small -> walks backtrack, stay local (homophily / community structure)
#' q small -> walks wander outward       (structural roles)
node2vec_walks <- function(A, num_walks = 10, walk_length = 40,
                           p = 1, q = 1, seed = 1) {
  set.seed(seed)
  n <- nrow(A)
  nbrs <- lapply(seq_len(n), function(i) which(A[i, ] > 0))
  starts <- sample(rep(seq_len(n), times = num_walks))
  W <- matrix(0L, nrow = length(starts), ncol = walk_length)
  W[, 1] <- starts
  for (r in seq_len(nrow(W))) {
    prev <- NA_integer_
    cur  <- W[r, 1]
    for (t in 2:walk_length) {
      cand <- nbrs[[cur]]
      if (length(cand) == 0L) { W[r, t] <- cur; next }
      if (is.na(prev)) {
        nxt <- cand[sample.int(length(cand), 1L)]
      } else {
        w <- rep(1 / q, length(cand))
        w[cand == prev]      <- 1 / p
        w[A[prev, cand] > 0] <- 1
        nxt <- cand[sample.int(length(cand), 1L, prob = w)]
      }
      W[r, t] <- nxt
      prev <- cur
      cur  <- nxt
    }
  }
  W
}

#' Turn walks into (centre, context) training pairs with a symmetric window.
#' Word2vec shrinks the window uniformly at random, which up-weights near
#' context; `shrink = TRUE` reproduces that.
walks_to_pairs <- function(W, window = 5, shrink = TRUE, seed = 1) {
  set.seed(seed)
  L <- ncol(W)
  out <- vector("list", 0)
  for (off in seq_len(window)) {
    keep <- if (shrink) {
      # a pair at distance `off` survives with probability (window-off+1)/window
      matrix(stats::runif(nrow(W) * (L - off)) <= (window - off + 1) / window,
             nrow(W), L - off)
    } else {
      matrix(TRUE, nrow(W), L - off)
    }
    a <- W[, seq_len(L - off), drop = FALSE][keep]
    b <- W[, seq_len(L - off) + off, drop = FALSE][keep]
    out[[length(out) + 1L]] <- cbind(a, b)
    out[[length(out) + 1L]] <- cbind(b, a)      # windows are symmetric
  }
  P <- do.call(rbind, out)
  P[P[, 1] != P[, 2], , drop = FALSE]
}

#' Skip-gram with negative sampling, trained by minibatch SGD.
#'
#' Objective, for a positive pair (u, v) and K sampled negatives v'_k:
#'
#'   L = -log sigma( w_u . c_v ) - sum_k log sigma( -w_u . c_{v'_k} )
#'
#' Every node gets two vectors: `W` when it is the centre, `C` when it is the
#' context. The embedding people use afterwards is `W` (or W + C).
#' Gradients are averaged over the minibatch, not summed. With only a few
#' hundred nodes a single batch touches the same node dozens of times, and
#' summing those updates blows the model up inside one epoch.
#'
#' Because of that averaging, `lr` is a *minibatch* step size: the per-example
#' rate is roughly `lr / batch`, so the default 2.0 at batch 1024 corresponds
#' to word2vec's per-example 0.002-ish. Raise `lr` if the reported loss is
#' still falling steeply at the last epoch.
skipgram_sgns <- function(pairs, n_nodes, dim = 32, epochs = 5, lr = 2,
                          neg = 5, batch = 1024, seed = 1, verbose = FALSE) {
  set.seed(seed)
  W <- matrix(stats::rnorm(n_nodes * dim, sd = 0.1), n_nodes, dim)
  C <- matrix(0, n_nodes, dim)

  # word2vec's noise distribution: unigram frequency raised to 3/4, expanded
  # once into a lookup table so that drawing negatives is a uniform gather.
  freq <- tabulate(pairs[, 2], nbins = n_nodes)
  pn <- freq^0.75
  if (sum(pn) == 0) pn <- rep(1, n_nodes)
  pn <- pn / sum(pn)
  tbl <- rep(seq_len(n_nodes), times = pmax(round(pn * 1e5), 1))
  n_tbl <- length(tbl)

  m <- nrow(pairs)
  loss_trace <- numeric(epochs)

  for (ep in seq_len(epochs)) {
    ord <- sample.int(m)
    lr_ep <- lr * (1 - (ep - 1) / epochs)        # linear decay, as in word2vec
    tot <- 0
    for (start in seq(1L, m, by = batch)) {
      idx <- ord[start:min(start + batch - 1L, m)]
      u <- pairs[idx, 1]; v <- pairs[idx, 2]
      B <- length(idx)

      Wu <- W[u, , drop = FALSE]
      Cv <- C[v, , drop = FALSE]

      # --- positive term ---
      # word2vec clamps the logit to +/-6 before the sigmoid; keep that, it is
      # what stops a runaway pair from dominating the update.
      sp <- pmax(pmin(rowSums(Wu * Cv), 6), -6)
      gp <- sigmoid(sp) - 1                       # dL/ds for label 1
      tot <- tot - sum(log(pmax(sigmoid(sp), 1e-10)))

      gW <- gp * Cv                               # accumulate dL/dW[u]
      dC <- gp * Wu                               # dL/dC[v]

      # --- negative terms ---
      Cupd <- vector("list", neg)
      vneg_all <- vector("list", neg)
      for (k in seq_len(neg)) {
        vk <- tbl[sample.int(n_tbl, B, replace = TRUE)]
        Ck <- C[vk, , drop = FALSE]
        sn <- pmax(pmin(rowSums(Wu * Ck), 6), -6)
        gn <- sigmoid(sn)                         # dL/ds for label 0
        tot <- tot - sum(log(pmax(sigmoid(-sn), 1e-10)))
        gW <- gW + gn * Ck
        Cupd[[k]] <- gn * Wu
        vneg_all[[k]] <- vk
      }

      # --- apply updates (duplicate indices are summed, not overwritten) ---
      step <- -lr_ep / B
      W <- scatter_add(W, u, step * gW)
      C <- scatter_add(C, v, step * dC)
      for (k in seq_len(neg)) {
        C <- scatter_add(C, vneg_all[[k]], step * Cupd[[k]])
      }
    }
    loss_trace[ep] <- tot / m
    if (verbose) message(sprintf("epoch %d  loss %.4f  lr %.4f", ep, loss_trace[ep], lr_ep))
  }
  list(W = W, C = C, loss = loss_trace)
}

#' DeepWalk = uniform random walks + skip-gram with negative sampling.
deepwalk <- function(A, dim = 32, num_walks = 10, walk_length = 40,
                     window = 5, epochs = 5, neg = 5, lr = 2, seed = 1) {
  W <- random_walks(A, num_walks, walk_length, seed = seed)
  P <- walks_to_pairs(W, window, seed = seed)
  fit <- skipgram_sgns(P, n_nodes = nrow(A), dim = dim, epochs = epochs,
                       neg = neg, lr = lr, seed = seed)
  structure(fit$W, loss = fit$loss, pairs = nrow(P),
            class = c("graph_embedding", "matrix"))
}

#' node2vec = biased second-order walks + the same skip-gram objective.
node2vec <- function(A, dim = 32, num_walks = 10, walk_length = 40,
                     window = 5, p = 1, q = 1, epochs = 5, neg = 5,
                     lr = 2, seed = 1) {
  W <- node2vec_walks(A, num_walks, walk_length, p = p, q = q, seed = seed)
  P <- walks_to_pairs(W, window, seed = seed)
  fit <- skipgram_sgns(P, n_nodes = nrow(A), dim = dim, epochs = epochs,
                       neg = neg, lr = lr, seed = seed)
  structure(fit$W, loss = fit$loss, pairs = nrow(P),
            class = c("graph_embedding", "matrix"))
}


# 4. matrix factorisation -----------------------------------------------------

#' The NetMF matrix: the thing DeepWalk is implicitly factorising.
#'
#'   M = vol(G) / (b*T) * ( sum_{r=1..T} P^r ) D^-1 ,   P = D^-1 A
#'   M' = log( max(M, 1) )
#'
#' Qiu et al. (2018) showed that DeepWalk's SGNS solution approximates a
#' low-rank factorisation of M'. So the "neural" method has a closed form.
#' @param truncate apply the `log max(., 1)` step. Set FALSE to get the raw
#'   `log M`, which is what the PMI theory of @sec-mf actually predicts;
#'   truncation is a downstream trick for suppressing noisy negative entries.
netmf_matrix <- function(A, T_window = 5, b = 1, truncate = TRUE) {
  d <- rowSums(A)
  vol <- sum(A)
  n <- nrow(A)
  dinv <- ifelse(d > 0, 1 / d, 0)
  P <- dinv * A                                    # D^-1 A, row-stochastic
  S <- matrix(0, n, n)
  Pr <- diag(n)
  for (r in seq_len(T_window)) {
    Pr <- Pr %*% P
    S <- S + Pr
  }
  M <- (vol / (b * T_window)) * (S * rep(dinv, each = n))   # ... %*% D^-1
  if (truncate) log(pmax(M, 1)) else log(M)
}

#' NetMF embedding: truncated SVD of the log-PMI matrix above.
netmf <- function(A, dim = 32, T_window = 5, b = 1) {
  Mp <- netmf_matrix(A, T_window, b)
  sv <- svd(Mp, nu = dim, nv = dim)
  Z <- sv$u %*% diag(sqrt(sv$d[seq_len(dim)]), dim, dim)
  colnames(Z) <- paste0("dim", seq_len(dim))
  structure(Z, singular_values = sv$d[seq_len(dim)],
            class = c("graph_embedding", "matrix"))
}


# 5. graph neural networks ----------------------------------------------------

#' Kipf & Welling's renormalised adjacency: Ahat = Dt^-1/2 (A + I) Dt^-1/2
gcn_normalize <- function(A) {
  n <- nrow(A)
  At <- A + diag(n)
  dt <- rowSums(At)
  dm <- 1 / sqrt(dt)
  (dm * At) * rep(dm, each = n)
}

#' Forward pass of an L-layer GCN:  H <- act( Ahat H W )
#'
#' @param A adjacency matrix
#' @param X node feature matrix (n x f); use diag(n) for a featureless graph
#' @param Ws list of weight matrices, one per layer
#' @param act activation applied to every layer but the last
gcn_forward <- function(A, X, Ws, act = relu) {
  Ahat <- gcn_normalize(A)
  H <- X
  for (l in seq_along(Ws)) {
    H <- Ahat %*% H %*% Ws[[l]]
    if (l < length(Ws)) H <- act(H)
  }
  H
}

#' Random (untrained) GCN weights -- enough to show that message passing alone
#' already smooths features over the graph.
gcn_random_weights <- function(dims, seed = 1) {
  set.seed(seed)
  lapply(seq_len(length(dims) - 1L), function(l) {
    fan_in <- dims[l]
    matrix(stats::rnorm(dims[l] * dims[l + 1], sd = sqrt(2 / fan_in)),
           dims[l], dims[l + 1])
  })
}


# 6. transformer ingredients --------------------------------------------------

#' Laplacian positional encoding (Dwivedi & Bresson): the k smallest
#' non-trivial eigenvectors of Lsym, one row per node.
#'
#' Eigenvectors are defined up to sign, so training-time sign flipping is the
#' standard augmentation; `sign_flip = TRUE` draws one random flip.
lap_pe <- function(A, k = 8, sign_flip = FALSE, seed = 1) {
  L <- graph_laplacian(A, "sym")
  ev <- eigen(L, symmetric = TRUE)
  ord <- rev(seq_len(ncol(ev$vectors)))
  V <- ev$vectors[, ord, drop = FALSE][, 2:(k + 1), drop = FALSE]
  if (sign_flip) {
    set.seed(seed)
    V <- sweep(V, 2, sample(c(-1, 1), k, replace = TRUE), `*`)
  }
  colnames(V) <- paste0("lap", seq_len(k))
  V
}

#' Random-walk structural encoding (RWSE, used by GraphGPS): for each node,
#' the return probabilities [P^1]_ii, ..., [P^K]_ii. Unlike Laplacian PE this
#' has no sign ambiguity and describes local structure (triangles, degree).
rwse <- function(A, ks = 1:8) {
  d <- rowSums(A)
  P <- ifelse(d > 0, 1 / d, 0) * A
  n <- nrow(A)
  out <- matrix(0, n, length(ks))
  Pk <- diag(n)
  mx <- max(ks)
  j <- 1L
  for (k in seq_len(mx)) {
    Pk <- Pk %*% P
    if (k %in% ks) { out[, j] <- diag(Pk); j <- j + 1L }
  }
  colnames(out) <- paste0("rw", ks)
  out
}

#' Graphormer's spatial encoding: a learnable scalar per shortest-path
#' distance, added to the attention logits before the softmax.
#'
#' @param g igraph object
#' @param b numeric vector of biases, indexed by distance 0, 1, ..., length(b)-2;
#'   the last element is used for "further than that / unreachable"
spd_bias <- function(g, b) {
  D <- igraph::distances(g)
  maxd <- length(b) - 1L
  D[is.infinite(D)] <- maxd
  D <- pmin(D, maxd)
  matrix(b[as.integer(D) + 1L], nrow(D), ncol(D))
}

#' Multi-head self-attention with an optional additive attention bias.
#'
#'   head_h = softmax( Q_h K_h^T / sqrt(d_h) + Bias ) V_h
#'
#' The bias term is the entire trick: it is where graph structure enters an
#' architecture that is otherwise completely blind to the order or the
#' connectivity of its inputs.
mha <- function(X, par, heads = 2, bias = NULL) {
  n <- nrow(X); d <- ncol(X)
  stopifnot(d %% heads == 0)
  dh <- d %/% heads
  Q <- X %*% par$Wq; K <- X %*% par$Wk; V <- X %*% par$Wv
  out  <- matrix(0, n, d)
  attn <- vector("list", heads)
  for (h in seq_len(heads)) {
    sl <- ((h - 1) * dh + 1):(h * dh)
    S <- Q[, sl, drop = FALSE] %*% t(K[, sl, drop = FALSE]) / sqrt(dh)
    if (!is.null(bias)) S <- S + bias
    Aw <- softmax_rows(S)
    attn[[h]] <- Aw
    out[, sl] <- Aw %*% V[, sl, drop = FALSE]
  }
  list(out = out %*% par$Wo, attn = attn)
}

#' Layer normalisation over the feature dimension.
layer_norm <- function(X, eps = 1e-5) {
  mu <- rowMeans(X)
  sd <- sqrt(rowMeans((X - mu)^2) + eps)
  (X - mu) / sd
}

#' One pre-norm transformer encoder block.
transformer_block <- function(X, par, heads = 2, bias = NULL) {
  a <- mha(layer_norm(X), par, heads, bias)
  X <- X + a$out
  H <- relu(layer_norm(X) %*% par$W1) %*% par$W2
  list(out = X + H, attn = a$attn)
}

#' Random parameters for one block, He-initialised.
transformer_params <- function(d, d_ff = 4 * d, seed = 1) {
  set.seed(seed)
  rm_ <- function(a, b) matrix(stats::rnorm(a * b, sd = sqrt(2 / a)), a, b)
  list(Wq = rm_(d, d), Wk = rm_(d, d), Wv = rm_(d, d), Wo = rm_(d, d),
       W1 = rm_(d, d_ff), W2 = rm_(d_ff, d))
}


#' Draw a pair of attention matrices side by side, ordered by a grouping.
#'
#' Two presentation choices, both necessary to see anything:
#'   - self-attention is removed and rows renormalised. With a distance bias the
#'     diagonal (distance 0) dwarfs everything else and washes the plot out.
#'   - a single colour scale, clipped at a high quantile of the *biased* matrix,
#'     so "flat" and "structured" are directly comparable.
plot_attention <- function(mats, group, titles = names(mats), clip = 0.98) {
  ord <- order(group)
  n <- length(group)
  prep <- function(M) {
    diag(M) <- 0
    M <- M / rowSums(M)
    M <- M[ord, ord]
    diag(M) <- NA
    M
  }
  mats <- lapply(mats, prep)
  hi <- stats::quantile(mats[[length(mats)]], clip, na.rm = TRUE)
  op <- graphics::par(mfrow = c(1, length(mats)), mar = c(2, 2, 2.5, 1))
  on.exit(graphics::par(op))
  for (i in seq_along(mats)) {
    M <- pmin(mats[[i]], hi)
    graphics::image(t(M[n:1, ]), col = grDevices::hcl.colors(64, "Blues", rev = TRUE),
                    axes = FALSE, main = titles[i], zlim = c(0, hi))
    graphics::box()
  }
  invisible(NULL)
}


# 7. evaluation ---------------------------------------------------------------

#' Area under the ROC curve, computed from ranks (no extra packages).
auc <- function(scores, labels) {
  r <- rank(scores)
  n1 <- sum(labels == 1); n0 <- sum(labels == 0)
  (sum(r[labels == 1]) - n1 * (n1 + 1) / 2) / (n1 * n0)
}

#' Link-prediction AUC: hold out edges, score every candidate pair by the dot
#' product of its endpoint embeddings, and ask whether held-out edges outrank
#' random non-edges.
link_pred_auc <- function(Z, pos, neg, score = function(a, b) rowSums(a * b)) {
  s_pos <- score(Z[pos[, 1], , drop = FALSE], Z[pos[, 2], , drop = FALSE])
  s_neg <- score(Z[neg[, 1], , drop = FALSE], Z[neg[, 2], , drop = FALSE])
  auc(c(s_pos, s_neg), c(rep(1, length(s_pos)), rep(0, length(s_neg))))
}

#' Split a graph's edges into a training graph and a held-out positive set,
#' plus an equally sized sample of non-edges as negatives.
edge_split <- function(g, frac = 0.15, seed = 1) {
  set.seed(seed)
  E <- igraph::as_edgelist(g, names = FALSE)
  n <- igraph::vcount(g)
  m <- nrow(E)
  hold <- sample.int(m, max(1L, floor(frac * m)))
  g_train <- igraph::delete_edges(g, igraph::E(g)[hold])
  A_full <- as_adj_dense(g)
  neg <- matrix(0L, 0, 2)
  while (nrow(neg) < length(hold)) {
    cand <- cbind(sample.int(n, length(hold) * 3, TRUE),
                  sample.int(n, length(hold) * 3, TRUE))
    cand <- cand[cand[, 1] != cand[, 2], , drop = FALSE]
    cand <- cand[A_full[cand] == 0, , drop = FALSE]
    neg <- rbind(neg, cand)
  }
  list(g_train = g_train, pos = E[hold, , drop = FALSE],
       neg = neg[seq_len(length(hold)), , drop = FALSE])
}

#' Leave-one-out kNN accuracy in embedding space -- a quick proxy for "does
#' this embedding know which community a node belongs to?".
knn_accuracy <- function(Z, labels, k = 5) {
  S <- cosine_sim(Z)
  diag(S) <- -Inf
  pred <- apply(S, 1, function(s) {
    nb <- order(s, decreasing = TRUE)[seq_len(k)]
    tb <- table(labels[nb])
    names(tb)[which.max(tb)]
  })
  mean(pred == labels)
}

# 01 -- Hello, world ----------------------------------------------------------
#
#   Rscript examples/01-hello-world.R
#
# The smallest honest graph embedding. Eight nodes, no packages -- not igraph,
# not Matrix, nothing. Base R only, so you can see that the whole idea is one
# call to eigen().
#
# The graph is a barbell: two triangles joined by a short path.
#
#        2               7
#       / \             / \
#      1---3---4---5---6---8
#
# Read the four sections in order. Each one answers the question the previous
# one raises.
# -----------------------------------------------------------------------------

FIG <- file.path("examples", "figures")


# 1. The graph, as a matrix ---------------------------------------------------

edges <- rbind(
  c(1, 2), c(1, 3), c(2, 3),      # triangle A
  c(3, 4), c(4, 5), c(5, 6),      # the bar
  c(6, 7), c(6, 8), c(7, 8)       # triangle B
)

n <- 8
A <- matrix(0, n, n)
A[edges] <- 1
A[edges[, 2:1]] <- 1              # undirected: make it symmetric

cat("adjacency matrix\n")
print(A)


# 2. Why the matrix is not enough ---------------------------------------------
#
# Node 1 is in triangle A. Node 5 sits on the bar, three hops away. Node 8 is in
# triangle B, five hops away at the far end.
#
# The adjacency matrix scores both pairs identically -- zero -- because it only
# records edges. But they are obviously not equally related.

hops <- function(A) {
  n <- nrow(A)
  D <- matrix(Inf, n, n)
  diag(D) <- 0
  reach <- diag(n)
  for (k in seq_len(n - 1)) {
    reach <- (reach %*% A) > 0             # reachable in exactly k steps
    D[reach & is.infinite(D)] <- k         # first time reached = shortest path
  }
  D
}
D <- hops(A)

cat("\n            A[i,j]   hops\n")
for (j in c(5, 8)) {
  cat(sprintf("node 1 -> node %d %5d %6d\n", j, A[1, j], D[1, j]))
}
cat("\nThe matrix says both are 0. The graph says one is nearly twice as far.\n")
cat("That gap is the whole problem an embedding solves.\n")


# 3. The Laplacian ------------------------------------------------------------
#
# Write down what we want: connected nodes should get similar coordinates. Given
# one coordinate per node, f, penalise every edge by the gap it has to stretch.
#
#   loss(f) = 1/2 * sum_ij A_ij (f_i - f_j)^2
#
# Expand the square and the whole sum collapses into a quadratic form in
# L = D - A, the graph Laplacian. That identity is why this field is linear
# algebra. Check it rather than believe it:

deg <- rowSums(A)
L <- diag(deg) - A

set.seed(1)
f <- rnorm(n)
cat(sprintf(
  "\nsum over edges = %.6f\nf' L f         = %.6f\n",
  0.5 * sum(outer(f, f, "-")^2 * A),
  as.numeric(t(f) %*% L %*% f)
))


# 4. The embedding is an eigenvector ------------------------------------------
#
# Minimising f'Lf with no constraint gives f = 0: perfectly smooth, perfectly
# useless. Constrain the scale and exclude the constant vector, and the answer
# is the eigenvectors of L with the SMALLEST eigenvalues -- the smoothest
# non-constant functions on the graph.

ev <- eigen(L, symmetric = TRUE)          # eigen() sorts DEcreasing...
ord <- rev(seq_len(n))                    # ...so reverse for smallest-first
vals <- ev$values[ord]
vecs <- ev$vectors[, ord]

cat("\neigenvalues (smallest first)\n")
print(round(vals, 4))

# The first is always 0, and its eigenvector is constant: it stretches no edge,
# so it costs nothing. It carries no information. Dropping it is the single most
# common bug in hand-rolled spectral code.
cat("\neigenvector 1 (the trivial one, constant):\n")
print(round(vecs[, 1], 4))

# Eigenvector 2 is the Fiedler vector. This is the embedding.
cat("\neigenvector 2 (the Fiedler vector -- THIS is the embedding):\n")
print(round(vecs[, 2], 4))

z <- vecs[, 2]

cat("\n")
print(data.frame(
  node = 1:n,
  part = c(rep("triangle A", 3), rep("bar", 2), rep("triangle B", 3)),
  fiedler = round(z, 3),
  side = ifelse(z < 0, "-", "+")
), row.names = FALSE)

# Two things happened at once, and only the first is usually advertised.
#
# The SIGN splits the graph into its two triangles -- that is spectral
# clustering, and it is why lambda_2 is called the algebraic connectivity.
#
# The VALUE is more interesting: it climbs monotonically from one end of the
# barbell to the other and flattens inside each triangle. The embedding
# reconstructed the left-to-right geometry of a picture it never saw.

cat(sprintf(
  paste0("\nDistance along the Fiedler coordinate, from node 1:\n",
         "  to node 5 (3 hops): %.3f\n",
         "  to node 8 (5 hops): %.3f\n"),
  abs(z[1] - z[5]), abs(z[1] - z[8])
))

off <- upper.tri(D)
cat(sprintf("\nAcross all %d node pairs, correlation between\n", sum(off)))
cat(sprintf("  |embedding gap|  and  hop distance:  %.3f\n",
            cor(abs(outer(z, z, "-"))[off], D[off])))
cat("\nThe geometry now knows what the adjacency matrix could not say.\n")


# 5. Look at it ---------------------------------------------------------------

col <- c(rep("#4C72B0", 3), rep("grey55", 2), rep("#DD8452", 3))

dir.create(FIG, showWarnings = FALSE, recursive = TRUE)
if (!interactive()) png(file.path(FIG, "01-hello-world.png"),
                        width = 1000, height = 420, res = 110)
par(mfrow = c(1, 2), mar = c(4, 4, 2.5, 1))

# the graph, drawn at hand-set coordinates
xy <- cbind(c(0, 0.5, 1, 1.7, 2.4, 3.1, 3.6, 4.1),
            c(0, 0.9, 0, 0,   0,   0,   0.9, 0))
plot(xy, type = "n", axes = FALSE, xlab = "", ylab = "", main = "the graph",
     xlim = c(-0.4, 4.5), ylim = c(-0.5, 1.3))
segments(xy[edges[, 1], 1], xy[edges[, 1], 2],
         xy[edges[, 2], 1], xy[edges[, 2], 2], col = "grey70")
points(xy, pch = 21, bg = col, cex = 3)
text(xy, labels = 1:n, col = "white", cex = 0.8)

# the embedding: one number per node, so it fits on a line
jit <- c(0.06, -0.06, 0, 0, 0, 0, 0.06, -0.06)     # separate the tied nodes
plot(z, jit, type = "n", ylim = c(-0.3, 0.3), yaxt = "n", ylab = "",
     xlab = "Fiedler coordinate", main = "the embedding")
abline(h = 0, col = "grey85")
abline(v = 0, lty = 2, col = "grey60")
points(z, jit, pch = 21, bg = col, cex = 3)
text(z, jit, labels = 1:n, col = "white", cex = 0.8)

if (!interactive()) {
  invisible(dev.off())
  cat("\nfigure written to", file.path(FIG, "01-hello-world.png"), "\n")
}

cat("\nThat is a graph embedding. Everything else is a better choice of matrix.\n")

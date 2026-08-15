# 03 -- Embedding a biomedical ontology ---------------------------------------
#
#   Rscript examples/03-ontology-embedding.R
#
# The karate club is a toy. This is the thing the talk is actually about.
#
# Clinical vocabularies -- SNOMED, ICD, the OMOP concept hierarchy, the OBO
# Foundry ontologies -- are graphs of concepts joined by "is a". Chapter 1 makes
# a specific promise about what embedding one buys you:
#
#   "Embedding it gives you a similarity between diagnoses that respects
#    clinical structure rather than string edit distance."
#
# That is a testable claim, and this script tests it on the real Disease
# Ontology. The answer is unambiguous, and the failure mode of string matching
# is worse than you would guess.
#
# Data: examples/data/doid-cardiovascular.obo -- the 627 terms under
# "cardiovascular system disease" in Disease Ontology release 2026-07-31.
# Nothing is downloaded here; see scripts/make-ontology-data.R for provenance.
# -----------------------------------------------------------------------------

root <- if (file.exists("R/graphemb.R")) "." else ".."
source(file.path(root, "R", "graphemb.R"))
source(file.path(root, "examples", "obo.R"))
FIG <- file.path(root, "examples", "figures")
OBO <- file.path(root, "examples", "data", "doid-cardiovascular.obo")

set.seed(1)


# 1. From a text file to a graph ----------------------------------------------
#
# The reader is twenty lines, because an is_a hierarchy needs only three tags.

print(parse_obo)

obo <- parse_obo(OBO, prefix = "DOID:")
g <- obo_graph(obo, directed = FALSE)
A <- as_adj_dense(g)
term <- V(g)$term

cat(sprintf(
  "\n%d terms, %d is_a edges, %d connected component(s)\n",
  vcount(g), ecount(g), components(g)$no
))
cat("\nA few terms:\n")
print(head(obo$terms[obo$terms$id %in% c("DOID:1287", "DOID:114", "DOID:3393",
                                         "DOID:5844", "DOID:10763"), ], 5),
      row.names = FALSE)

# Note the shape of this graph: 672 edges over 627 nodes. It is a hierarchy,
# barely more than a tree. There is no co-occurrence data here, no patient
# counts -- only the structure a curator wrote down.


# 2. Embed it -----------------------------------------------------------------
#
# NetMF: build the matrix DeepWalk implicitly factorises and take its SVD. At
# this size it is a closed form that runs in well under a second.

t0 <- system.time(Z <- netmf(A, dim = 64, T_window = 5))[["elapsed"]]
rownames(Z) <- V(g)$name                     # keep the DOIDs attached
cat(sprintf("\nNetMF d=64 on %d terms: %.2f seconds\n", nrow(Z), t0))

S <- cosine_sim(Z)
diag(S) <- -Inf


# 3. The control: string edit distance ----------------------------------------
#
# The honest comparison is not "embedding vs nothing", it is "embedding vs the
# cheap thing a reasonable person would try first". For text labels that is edit
# distance, normalised by length so long names are not penalised.

Sed <- adist(term, term, ignore.case = TRUE) / outer(nchar(term), nchar(term), pmax)
diag(Sed) <- Inf

neighbours <- function(query, k = 5) {
  i <- match(query, term)
  stopifnot(!is.na(i))
  data.frame(
    rank = seq_len(k),
    by_embedding = term[order(S[i, ], decreasing = TRUE)[seq_len(k)]],
    by_edit_distance = term[order(Sed[i, ])[seq_len(k)]]
  )
}

for (q in c("myocardial infarction", "pulmonary valve disease", "aortic aneurysm")) {
  cat("\n=== nearest to:", q, "===\n")
  print(neighbours(q), row.names = FALSE)
}

# Read the "pulmonary valve disease" block twice. Edit distance's top answer is
# "pulmonary artery disease" -- one letter of difference in the string, a
# different anatomical structure in the clinic, five hops away in the ontology.
# The embedding's top answers are pulmonary valve insufficiency, rheumatic
# pulmonary valve disease, pulmonary valve stenosis: the other VALVE diseases.
# It worked out which of the two words was load-bearing, from the graph alone,
# having never seen the text.


# 4. The two failure modes, side by side --------------------------------------
#
# String matching fails in both directions at once: it links things that only
# sound alike, and misses things that are clinically the same problem.

D <- distances(g)
pairs <- rbind(
  c("myocardial infarction",   "cerebral infarction"),
  c("pulmonary valve disease", "pulmonary artery disease"),
  c("renal hypertension",      "portal hypertension"),
  c("myocardial infarction",   "coronary artery disease"),
  c("myocardial infarction",   "intermediate coronary syndrome"),
  c("aortic aneurysm",         "Marfan syndrome")
)
cmp <- data.frame(
  term_a = pairs[, 1], term_b = pairs[, 2],
  edit_dist = NA_real_, cosine = NA_real_, hops = NA_integer_
)
for (r in seq_len(nrow(pairs))) {
  a <- match(pairs[r, 1], term); b <- match(pairs[r, 2], term)
  cmp$edit_dist[r] <- round(Sed[a, b], 2)
  cmp$cosine[r] <- round(S[a, b], 3)
  cmp$hops[r] <- D[a, b]
}
cat("\n=== where the two measures disagree ===\n")
print(cmp, row.names = FALSE)

cat("\nRows 1-3: the strings nearly match, the ontology says 5-6 hops apart.\n")
cat("Rows 4-6: the strings share almost nothing, the ontology says 1-2 hops.\n")
cat("\n(The exact zeros are real. After NetMF's log-max truncation these pairs\n")
cat("have no above-chance random-walk co-occurrence at all within a 5-step\n")
cat("window -- they are further apart than the method looks.)\n")

# Now resist the temptation to summarise that with a correlation. Averaged over
# every pair the two measures look loosely related, because both agree that most
# disease pairs are unrelated -- which is the easy 99%.
off <- upper.tri(Sed)
cat(sprintf("\nOver all %s term pairs, correlation between string similarity\n",
            format(sum(off), big.mark = ",")))
cat(sprintf("and embedding cosine: %.3f  <- do not stop here\n", cor(-Sed[off], S[off])))

# The disagreement is in the tail, and the tail is the entire thing retrieval
# touches. So ask the question a pipeline actually asks: take each term's single
# nearest neighbour, and see how far away the ontology says that neighbour is.
top1_ed <- apply(Sed, 1, which.min)
top1_emb <- apply(S, 1, which.max)
hops_ed <- D[cbind(seq_along(term), top1_ed)]
hops_emb <- D[cbind(seq_along(term), top1_emb)]

cat("\nHops to the single nearest neighbour each measure returns:\n\n")
print(rbind(`edit distance` = table(factor(pmin(hops_ed, 6), 1:6, labels = c(1:5, "6+"))),
            `embedding`     = table(factor(pmin(hops_emb, 6), 1:6, labels = c(1:5, "6+")))))

cat(sprintf(
  paste0("\nNeighbour 4+ hops away -- a false friend:\n",
         "  edit distance  %3d of %d terms (%.0f%%)\n",
         "  embedding      %3d of %d terms (%.0f%%)\n"),
  sum(hops_ed >= 4), length(term), 100 * mean(hops_ed >= 4),
  sum(hops_emb >= 4), length(term), 100 * mean(hops_emb >= 4)
))
cat("\nThat is the claim from chapter 1, measured: string matching sends you to\n")
cat("a clinically distant concept for roughly a quarter of this vocabulary.\n")


# 5. Does it recover structure it was not given? ------------------------------
#
# The nearest-neighbour lists above are qualitative. The quantitative version:
# label each disease by which top-level branch of the ontology it descends from,
# then ask whether the embedding separates those branches.
#
# Terms under more than one branch are dropped rather than arbitrarily assigned
# -- they are genuinely both, and scoring them either way would be a choice made
# to flatter the result.

gd <- obo_graph(obo, directed = TRUE)                 # child -> parent
branches <- names(neighbors(gd, "DOID:1287", mode = "in"))
member <- sapply(branches, function(b)
  V(g)$name %in% names(subcomponent(gd, b, mode = "in")))
n_branch <- rowSums(member)
clean <- n_branch == 1
branch <- rep(NA_character_, nrow(member))
branch[clean] <- obo$terms$name[match(branches[max.col(member[clean, ])], obo$terms$id)]

cat(sprintf("\n%d terms sit in exactly one top-level branch (%d in several, %d in none)\n",
            sum(clean), sum(n_branch > 1), sum(n_branch == 0)))
print(sort(table(branch[clean]), decreasing = TRUE))

cat(sprintf(
  "\n5-NN branch accuracy: %.3f   (majority-class baseline %.3f)\n",
  knn_accuracy(Z[clean, ], branch[clean], k = 5),
  max(table(branch[clean])) / sum(clean)
))
cat("\nThe embedding never saw the branch labels. It is a near-tree, so this is\n")
cat("an easy test -- but the baseline is the number that makes it meaningful.\n")


# 6. The hand-off to a transformer --------------------------------------------
#
# This is option 1 from chapter 6, and it is the highest-value, lowest-effort
# way to put a graph into a sequence model. Patient records are sequences of
# codes; the codes are nodes in this graph. Instead of a randomly initialised
# embedding table that has to learn from co-occurrence that these two codes are
# related -- for a million codes, most of them rare -- you initialise from Z and
# the relatedness is there at step zero.
#
# The vectors are keyed by DOID, and DOID carries the crosswalk:

icd <- obo$xrefs[startsWith(obo$xrefs[, 2], "ICD10CM:"), , drop = FALSE]
demo <- c("DOID:5844", "DOID:3393", "DOID:10763", "DOID:6000")

cat(sprintf("\n=== an embedding table: %d rows x %d dimensions ===\n",
            nrow(Z), ncol(Z)))
print(data.frame(
  doid = demo,
  term = obo$terms$name[match(demo, obo$terms$id)],
  icd10cm = sapply(demo, function(d)
    paste(sub("ICD10CM:", "", icd[icd[, 1] == d, 2]), collapse = ",")),
  nearest_neighbour = term[apply(S[match(demo, rownames(Z)), ], 1, which.max)]
), row.names = FALSE)

cat(sprintf("\n%d of %d terms carry an ICD-10-CM code, so the row keys line up\n",
            length(unique(icd[, 1])), nrow(obo$terms)))
cat("with codes already in the record. In torch the hand-off is one line:\n")
cat("  emb$weight <- nn_parameter(torch_tensor(Z))\n")


# 7. Look at it ---------------------------------------------------------------
#
# Do not try to scatter-plot this embedding in 2D. In a sparse near-tree almost
# every pair of terms is near-orthogonal, so any 2D projection piles 75% of the
# points on the origin. That is a true property of the data, not a bad plot.
#
# Show the similarity matrices instead, on a set small enough to label. Two
# groups: the coronary family around myocardial infarction, and six terms whose
# NAMES look like they belong but whose position in the ontology says otherwise.
#
# These six are hand-picked illustrations. The unbiased version of the claim is
# the 23%-vs-2% false-friend rate in section 4, measured over all 627 terms.
# ("myocardial stunning" is the near miss worth knowing about: it reads like a
# false friend, but DOID puts it one hop from MI, so it is not one.)

family <- c("myocardial infarction", "acute myocardial infarction",
            "septal myocardial infarction", "coronary artery disease",
            "intermediate coronary syndrome", "coronary thrombosis",
            "coronary stenosis")
lookalikes <- c("cerebral infarction", "myocarditis", "pulmonary artery disease",
                "pulmonary valve disease", "renal hypertension",
                "portal hypertension")
sel <- match(c(family, lookalikes), term)
nf <- length(family)

cat(sprintf(
  paste0("\n=== the coronary family vs six lookalikes ===\n",
         "                          within family   family vs lookalike\n",
         "  embedding cosine  %14.3f %21.3f\n",
         "  string similarity %14.3f %21.3f\n"),
  mean(S[sel[1:nf], sel[1:nf]][upper.tri(diag(nf))]),
  mean(S[sel[1:nf], sel[-(1:nf)]]),
  1 - mean(Sed[sel[1:nf], sel[1:nf]][upper.tri(diag(nf))]),
  1 - mean(Sed[sel[1:nf], sel[-(1:nf)]])
))
cat("\nThe embedding holds the family at 0.52 and drops the lookalikes to zero.\n")
cat("Edit distance scores the two groups the same to one decimal place: it\n")
cat("cannot see the distinction at all.\n")

dir.create(FIG, showWarnings = FALSE, recursive = TRUE)

heat <- function(M, title) {
  diag(M) <- NA                                   # self-similarity is 1 by fiat
  k <- nrow(M)
  image(seq_len(k), seq_len(k), t(M[k:1, ]), zlim = c(0, 1), axes = FALSE,
        xlab = "", ylab = "", main = title,
        col = hcl.colors(64, "Blues", rev = TRUE))
  axis(1, seq_len(k), term[sel], las = 2, cex.axis = 0.6, tick = FALSE)
  axis(2, seq_len(k), rev(term[sel]), las = 2, cex.axis = 0.6, tick = FALSE)
  abline(v = nf + 0.5, h = k - nf + 0.5, col = "#C44E52", lwd = 2)
  box(col = "grey60")
}

if (!interactive()) png(file.path(FIG, "03-string-vs-embedding.png"),
                        width = 1250, height = 580, res = 110)
par(mfrow = c(1, 2), mar = c(9.5, 11, 2.5, 1))
heat(1 - Sed[sel, sel], "string similarity")
heat(S[sel, sel], "embedding cosine similarity")
if (!interactive()) invisible(dev.off())

if (!interactive()) png(file.path(FIG, "03-false-friends.png"),
                        width = 850, height = 520, res = 110)
par(mfrow = c(1, 1), mar = c(4.5, 4.5, 2.5, 1))
h <- rbind(`edit distance` = table(factor(pmin(hops_ed, 6), 1:6)),
           `embedding`     = table(factor(pmin(hops_emb, 6), 1:6)))
bp <- barplot(h, beside = TRUE, col = c("#DD8452", "#4C72B0"),
              names.arg = c(1:5, "6+"), border = NA,
              xlab = "hops in the ontology to the neighbour it returns",
              ylab = "number of terms",
              main = "where each measure sends you")
legend("topright", legend = rownames(h), fill = c("#DD8452", "#4C72B0"),
       border = NA, bty = "n", cex = 0.8)
abline(v = mean(bp[, 3:4]), lty = 2, col = "grey50")
text(mean(bp[, 3:4]), max(h) * 0.7, "false friends ->", pos = 4,
     cex = 0.75, col = "grey30")
if (!interactive()) invisible(dev.off())

if (!interactive()) {
  cat("\nfigures written to\n  ", file.path(FIG, "03-string-vs-embedding.png"),
      "\n  ", file.path(FIG, "03-false-friends.png"), "\n")
}


# 8. What this does not do ----------------------------------------------------
#
# The embedding can only be as good as the hierarchy. Three honest limits:
#
#   - DOID's is_a graph is shallow in places. "congestive heart failure" and
#     "cardiac arrest" are siblings under heart disease, so the embedding calls
#     them close. A cardiologist would not.
#   - is_a is the only relation in this file. No "treated by", no shared
#     anatomy, no co-occurrence in real patients. Adding edge types is usually
#     worth more than changing the embedding algorithm.
#   - The vocabulary a clinical model needs is SNOMED-sized (hundreds of
#     thousands of concepts), where the dense n-by-n NetMF matrix in section 2
#     is impossible. Use sparse spectral (RSpectra) or sampled walks there --
#     chapter 7 has the size thresholds.


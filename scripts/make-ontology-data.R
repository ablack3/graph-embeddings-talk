# Regenerate examples/data/doid-cardiovascular.obo from the Disease Ontology.
#
#   Rscript scripts/make-ontology-data.R
#
# This is the ONLY script in the repository that touches the network, and it is
# not needed to run anything: the excerpt it produces is committed. Run it to
# refresh against a newer Disease Ontology release, or to convince yourself the
# committed file really is an excerpt of the real thing.
#
# What it does: download doid.obo, take the full subtree under
# DOID:1287 "cardiovascular system disease", and re-emit those terms in valid
# OBO with a provenance header. Only tags the examples use are kept, so the
# excerpt is ~1/40th the size of the source.

suppressPackageStartupMessages(library(igraph))
source("examples/obo.R")

SOURCE_URL <- "https://purl.obolibrary.org/obo/doid.obo"
ROOT <- "DOID:1287"                                # cardiovascular system disease
OUT <- "examples/data/doid-cardiovascular.obo"
KEEP_XREF <- c("ICD10CM:", "SNOMEDCT_US", "UMLS_CUI:", "MESH:")

src <- file.path(tempdir(), "doid.obo")
if (!file.exists(src)) {
  message("downloading ", SOURCE_URL)
  utils::download.file(SOURCE_URL, src, quiet = TRUE)
}
raw <- readLines(src, warn = FALSE)
release <- sub("^data-version: ", "", grep("^data-version: ", raw, value = TRUE)[1])

message("parsing ", length(raw), " lines")
obo <- parse_obo(src, prefix = "DOID:")
message("  ", nrow(obo$terms), " live terms, ", nrow(obo$edges), " is_a edges")

# Everything that reaches ROOT by following is_a upwards. `mode = "in"` because
# the edges point child -> parent, so descendants are the in-component.
g <- graph_from_edgelist(obo$edges, directed = TRUE)
keep <- names(subcomponent(g, ROOT, mode = "in"))
message("  ", length(keep), " terms under ", ROOT)

# Re-emit the selected stanzas, keeping only the tags the examples read. is_a
# lines pointing outside the excerpt are dropped, so the file stays closed under
# its own hierarchy -- noted in the header because it is a real edit, not a
# lossless subset.
hdr <- grep("^\\[", raw)
from <- hdr + 1L
to <- c(hdr[-1] - 1L, length(raw))

out <- c(
  "format-version: 1.2",
  paste0("data-version: ", release),
  "ontology: doid/cardiovascular-excerpt",
  "!",
  "! EXCERPT -- not the full Disease Ontology.",
  "!",
  paste0("! Source:      ", SOURCE_URL),
  paste0("! Release:     ", release),
  paste0("! Extracted:   the ", length(keep), " terms in the is_a subtree rooted at"),
  paste0("!              ", ROOT, " (cardiovascular system disease), inclusive."),
  "! Edits:       obsolete terms dropped; is_a links to parents outside the",
  "!              subtree dropped; only id/name/synonym/xref/is_a tags kept;",
  "!              xrefs limited to ICD10CM, SNOMED CT, UMLS and MeSH.",
  paste0("! Rebuild:     Rscript scripts/make-ontology-data.R"),
  "!",
  "! Disease Ontology is CC0. Schriml et al., Nucleic Acids Res (2022).",
  "!",
  ""
)

n_terms <- 0L
for (k in which(raw[hdr] == "[Term]")) {
  st <- raw[from[k]:to[k]]
  if (any(st == "is_obsolete: true")) next
  id <- sub("^id: ", "", st[startsWith(st, "id: ")][1])
  if (is.na(id) || !id %in% keep) next

  is_a <- st[startsWith(st, "is_a: ")]
  is_a <- is_a[sub(" *!.*$", "", sub("^is_a: ", "", is_a)) %in% keep]
  xref <- st[startsWith(st, "xref: ")]
  xref <- xref[grepl(paste(KEEP_XREF, collapse = "|"), xref, fixed = FALSE)]

  out <- c(out, "[Term]",
           st[startsWith(st, "id: ")],
           st[startsWith(st, "name: ")],
           st[startsWith(st, "synonym: ")],
           xref, is_a, "")
  n_terms <- n_terms + 1L
}

dir.create(dirname(OUT), showWarnings = FALSE, recursive = TRUE)
writeLines(out, OUT)

chk <- parse_obo(OUT, prefix = "DOID:")
message(sprintf("wrote %s\n  %d terms, %d is_a edges, %.0f KB",
                OUT, nrow(chk$terms), nrow(chk$edges), file.size(OUT) / 1024))
stopifnot(n_terms == nrow(chk$terms), setequal(chk$terms$id, keep))
message("round-trip check passed")

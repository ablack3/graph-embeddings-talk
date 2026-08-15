# obo.R -----------------------------------------------------------------------
#
# A minimal reader for OBO-format ontologies -- the plain-text format used by
# the OBO Foundry (Disease Ontology, HPO, GO, Uberon, ChEBI, ...).
#
# OBO is a file of stanzas. One term looks like this:
#
#   [Term]
#   id: DOID:5844
#   name: myocardial infarction
#   synonym: "heart attack" EXACT []
#   xref: ICD10CM:I21
#   is_a: DOID:3393 ! coronary artery disease
#
# Everything needed to build a graph is in three of those tags: `id` and `name`
# give the nodes, and each `is_a` line gives one edge. This reader ignores every
# other tag, which is why it is twenty lines instead of a package. For real work
# on large ontologies use `ontologyIndex` or `rols`.
# -----------------------------------------------------------------------------

#' Read the terms and is_a edges out of an OBO file.
#'
#' @param path path to a .obo file
#' @param prefix keep only terms whose id starts with this (e.g. "DOID:"), which
#'   drops cross-ontology imports
#' @return list with `terms` (data.frame of id, name), `edges` (character matrix
#'   of child, parent) and `xrefs` (character matrix of id, xref)
parse_obo <- function(path, prefix = "") {
  ln <- readLines(path, warn = FALSE)

  # Stanzas are delimited by their own headers: [Term], [Typedef], [Instance].
  # Cut the file at every header, then keep the [Term] blocks.
  hdr <- grep("^\\[", ln)
  from <- hdr + 1L
  to <- c(hdr[-1] - 1L, length(ln))
  is_term <- which(ln[hdr] == "[Term]")

  ids <- character(0); names_ <- character(0)
  edges <- list(); xrefs <- list()

  for (k in is_term) {
    st <- ln[from[k]:to[k]]
    if (any(st == "is_obsolete: true")) next          # obsolete terms are tombstones

    id <- sub("^id: ", "", st[startsWith(st, "id: ")][1])
    if (is.na(id) || !startsWith(id, prefix)) next

    ids <- c(ids, id)
    names_ <- c(names_, sub("^name: ", "", st[startsWith(st, "name: ")][1]))

    # "is_a: DOID:3393 ! coronary artery disease" -> "DOID:3393"
    par <- sub(" *!.*$", "", sub("^is_a: ", "", st[startsWith(st, "is_a: ")]))
    par <- par[startsWith(par, prefix)]
    if (length(par)) edges[[length(edges) + 1L]] <- cbind(id, par)

    # "xref: ICD10CM:I21" -> the code this term is known by elsewhere
    xr <- sub("^xref: ", "", st[startsWith(st, "xref: ")])
    if (length(xr)) xrefs[[length(xrefs) + 1L]] <- cbind(id, xr)
  }

  list(
    terms = data.frame(id = ids, name = names_, stringsAsFactors = FALSE),
    edges = do.call(rbind, edges),
    xrefs = do.call(rbind, xrefs)
  )
}

#' Turn a parsed OBO into an igraph object.
#'
#' The is_a relation is directed (child -> parent), but for *similarity* we want
#' it undirected: two sibling diseases are related whether you walk up or down.
#' Direction still matters for anything ancestor-shaped, which is why
#' `directed = TRUE` is available.
#'
#' Vertex names are the term ids; the human-readable label is the `term`
#' attribute.
obo_graph <- function(obo, directed = FALSE) {
  known <- obo$terms$id
  e <- obo$edges[obo$edges[, 1] %in% known & obo$edges[, 2] %in% known, , drop = FALSE]
  g <- igraph::graph_from_edgelist(e, directed = directed)
  g <- igraph::simplify(g)
  igraph::V(g)$term <- obo$terms$name[match(igraph::V(g)$name, obo$terms$id)]
  g
}

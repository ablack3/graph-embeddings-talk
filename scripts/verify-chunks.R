# Execute every R chunk in every .qmd, so we know the book's code runs.
#
#   Rscript scripts/verify-chunks.R              # all chapters + slides
#   Rscript scripts/verify-chunks.R 03-random-walks.qmd
#
# This is knitr, not Quarto: it evaluates chunks and inline `r ...` expressions
# and honours `#| eval: false`, which is all we need to catch broken code. It
# does not check cross-references, citations or layout -- run `quarto render`
# for that.

files <- commandArgs(trailingOnly = TRUE)
if (!length(files)) {
  files <- c(sort(Sys.glob("*.qmd")), sort(Sys.glob("slides/*.qmd")))
}

outdir <- file.path(tempdir(), "verify")
dir.create(outdir, showWarnings = FALSE, recursive = TRUE)

ok <- TRUE
for (f in files) {
  cat(sprintf("\n=== %-28s ", f))
  t0 <- Sys.time()
  res <- tryCatch({
    local({
      knitr::opts_chunk$set(dev = "png", fig.path = file.path(outdir, "fig-"))
      knitr::knit(f, output = file.path(outdir, paste0(basename(f), ".md")),
                  quiet = TRUE, envir = new.env())
    })
    "OK"
  }, error = function(e) paste("FAIL:", conditionMessage(e)))
  el <- round(as.numeric(difftime(Sys.time(), t0, units = "secs")), 1)
  cat(sprintf("%6.1fs  %s", el, res))
  if (!identical(res, "OK")) ok <- FALSE
}

cat("\n\n", if (ok) "All chunks executed." else "SOME CHUNKS FAILED.", "\n")
quit(status = if (ok) 0L else 1L)

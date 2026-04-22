#!/usr/bin/env Rscript
## =============================================================================
## Smoke-test entry point: SS_MOAB_noBlanks_HYD_vs_DEH-4.csv
## =============================================================================
##
## Mirror of `run_HR.R` — same pipeline, different input CSV, separate output
## directory. Runs against the SS sample CSV and writes to `out_SS/`.
##
## Invoke either way:
##   Rscript example/run_SS.R          # from a shell
##   source("example/run_SS.R")        # from inside an R session
## =============================================================================

# -----------------------------------------------------------------------------
# .script_dir() — locate this file's directory at runtime.
#
# Mirror of the helper in `run_HR.R`. Has to be redefined here (not pulled
# from `_pipeline.R`) because we need it *before* we can source the shared
# pipeline module — chicken-and-egg. See `run_HR.R` for the full rationale.
# -----------------------------------------------------------------------------
.script_dir <- function() {
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", a[grep("^--file=", a)])
  if (length(f)) return(dirname(normalizePath(f[1], mustWork = TRUE)))
  of <- tryCatch(sys.frame(1)$ofile, error = function(e) NULL)
  if (!is.null(of)) return(dirname(normalizePath(of, mustWork = TRUE)))
  getwd()
}

# Resolve our directory; load the shared pipeline; run.
here <- .script_dir()
source(file.path(here, "_pipeline.R"))

# `tag = "SS"` prefixes console output so HR vs SS runs are distinguishable
# when both logs land in the same place (e.g. CI output, run_all.sh).
run_pipeline(
  csv_path = file.path(here, "SS_MOAB_noBlanks_HYD_vs_DEH-4.csv"),
  out_dir  = file.path(here, "out_SS"),
  tag      = "SS"
)

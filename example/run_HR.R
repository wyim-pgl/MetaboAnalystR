#!/usr/bin/env Rscript
## =============================================================================
## Smoke-test entry point: HR_MOAB_noBlanks_HYD_vs_DEH-4.csv
## =============================================================================
##
## Runs the standard MetaboAnalystR two-group statistical pipeline (defined
## in `_pipeline.R`) against the HR sample CSV and writes everything to
## `out_HR/` next to this script.
##
## Invoke either way:
##   Rscript example/run_HR.R          # from a shell
##   source("example/run_HR.R")        # from inside an R session
## Both paths are handled by `.script_dir()` below.
## =============================================================================

# -----------------------------------------------------------------------------
# .script_dir() — locate this very file's directory at runtime.
#
# Why the gymnastics: R doesn't expose `__file__` like Python. We have to
# reconstruct it from one of two channels depending on how the script was
# launched:
#
#   1. `Rscript path/to/run_HR.R`      → `--file=path/to/run_HR.R` shows up
#                                         in `commandArgs(trailingOnly = FALSE)`.
#   2. `source("path/to/run_HR.R")`    → R sets `sys.frame(1)$ofile` to the
#                                         sourced filename instead.
#
# Fall through to `getwd()` if neither channel is populated (e.g. someone
# pasted the file into a REPL line by line). The duplicate of this helper in
# `run_SS.R` is intentional: we need it *before* we can `source(_pipeline.R)`,
# so it cannot live in the sourced file (chicken-and-egg).
# -----------------------------------------------------------------------------
.script_dir <- function() {
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", a[grep("^--file=", a)])
  if (length(f)) return(dirname(normalizePath(f[1], mustWork = TRUE)))
  of <- tryCatch(sys.frame(1)$ofile, error = function(e) NULL)
  if (!is.null(of)) return(dirname(normalizePath(of, mustWork = TRUE)))
  getwd()
}

# Resolve the directory that holds this file + the input CSV + `_pipeline.R`.
here <- .script_dir()

# Pull in `run_pipeline()` from the shared module sitting next to us.
source(file.path(here, "_pipeline.R"))

# Run the pipeline. `tag = "HR"` just prefixes the per-stage console messages
# so output from `run_HR.R` and `run_SS.R` interleaved in the same log can be
# told apart.
run_pipeline(
  csv_path = file.path(here, "HR_MOAB_noBlanks_HYD_vs_DEH-4.csv"),
  out_dir  = file.path(here, "out_HR"),
  tag      = "HR"
)

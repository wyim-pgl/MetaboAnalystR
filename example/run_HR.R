#!/usr/bin/env Rscript
## Run the standard 2-group stats pipeline on example/HR_MOAB_noBlanks_HYD_vs_DEH-4.csv

.script_dir <- function() {
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", a[grep("^--file=", a)])
  if (length(f)) return(dirname(normalizePath(f[1], mustWork = TRUE)))
  of <- tryCatch(sys.frame(1)$ofile, error = function(e) NULL)
  if (!is.null(of)) return(dirname(normalizePath(of, mustWork = TRUE)))
  getwd()
}
here <- .script_dir()
source(file.path(here, "_pipeline.R"))

run_pipeline(
  csv_path = file.path(here, "HR_MOAB_noBlanks_HYD_vs_DEH-4.csv"),
  out_dir  = file.path(here, "out_HR"),
  tag      = "HR"
)

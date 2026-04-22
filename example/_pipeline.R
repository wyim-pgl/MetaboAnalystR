## =============================================================================
## MetaboAnalystR — shared two-group statistical workflow (smoke-test pipeline)
## =============================================================================
##
## This file defines a single function, `run_pipeline()`, that walks an
## intensity CSV through the standard MetaboAnalyst "stat" workflow:
##
##   InitDataObjects → Read.TextData → SanityCheckData → ImputeMissingVar
##     → PreparePrenormData → Normalization → FC.Anal → Ttests.Anal
##     → Volcano.Anal → PCA.Anal → PLSR.Anal → SaveTransformedData
##
## It is sourced by `run_HR.R` and `run_SS.R`; both pass a different CSV and
## output directory but otherwise reuse the exact same parameters. The CSV
## format expected here is the standard MetaboAnalyst "peak-table, columns
## are samples, discrete two-group classes" layout:
##
##   row 1: sample IDs (header)
##   row 2: class label per sample (e.g. HYD, DEH)
##   row 3+: features (rows), one intensity per sample column
##
## Side-effects to be aware of (these are MetaboAnalystR's contract, not ours):
##   * Almost every stage writes a `.qs` file (data_orig.qs, data_proc.qs,
##     prenorm.qs, row_norm.qs, complete_norm.qs, …) into the **current
##     working directory**. PNG plots also land in CWD. That is why we
##     `setwd(out_dir)` before calling any of these functions.
##   * `mSetObj` is the entire pipeline state. Every stage takes it and
##     returns an updated copy — we must `mSet <- SomeFunc(mSet, …)` each
##     time, never call them as bare statements.
##   * The package also touches a couple of `.GlobalEnv` symbols
##     (`default.dpi`, `rpath`, `metaboanalyst_env`) for compatibility with
##     the web-server runtime — that's expected and harmless here.
## =============================================================================

run_pipeline <- function(csv_path, out_dir, tag = "run") {

  # --- Pre-flight ------------------------------------------------------------
  # Validate the input early — MetaboAnalystR's own error messages from
  # Read.TextData() can be confusing if the CSV is missing entirely.
  stopifnot(file.exists(csv_path))

  # Make sure the output directory exists. recursive = TRUE so callers can
  # pass nested paths like "results/run42/out".
  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

  # Capture the absolute path of the CSV *before* we change directory below.
  # MetaboAnalystR resolves the CSV path relative to CWD, so a relative path
  # would break once we setwd() into out_dir.
  csv_abs <- normalizePath(csv_path, mustWork = TRUE)

  # We are about to change CWD to `out_dir` so that all the .qs / .png side
  # effects land there. Register an `on.exit` handler **first** so even if a
  # stage throws, we restore the caller's original working directory.
  orig_wd <- getwd(); on.exit(setwd(orig_wd), add = TRUE)
  setwd(out_dir)

  # MetaboAnalystR is heavy at load (Bioconductor + plotting + Rcpp + …).
  # Suppress its package-startup chatter so the per-stage [tag] messages we
  # emit below stay readable in the terminal.
  suppressPackageStartupMessages(library(MetaboAnalystR))

  # --- 1. Initialize state + ingest data -------------------------------------
  # InitDataObjects(data.type, anal.type, paired)
  #   data.type = "pktable"  → peak-table (rows = features, cols = samples)
  #   anal.type = "stat"     → general statistical analysis (FC / t-test / PCA …)
  #   paired    = FALSE      → unpaired two-group comparison
  message("[", tag, "] InitDataObjects / Read.TextData")
  mSet <- InitDataObjects("pktable", "stat", FALSE)

  # Read.TextData(mSet, csv, format, lbl.type)
  #   format   = "colu"  → columns are samples ("col-unpaired")
  #   lbl.type = "disc"  → discrete (categorical) class labels
  mSet <- Read.TextData(mSet, csv_abs, "colu", "disc")

  # --- 2. Sanity checks ------------------------------------------------------
  # Verifies sample counts, label balance, missing-value % per feature, etc.
  # Populates mSet$msgSet$check.msg with its findings. Returns 0 on hard
  # failures (which propagate as integer mSet — guarded against in our
  # FilterVariable fork, but stat workflow rarely trips it).
  message("[", tag, "] SanityCheckData")
  mSet <- SanityCheckData(mSet)

  # --- 3. Missing-value imputation ------------------------------------------
  # method = "lod" → fill NAs with 1/5 of each feature's smallest positive
  # observed value (a standard "below limit of detection" surrogate).
  # Other choices: "min", "mean", "median", "knn", "rf", "bpca", "ppca", "svd".
  message("[", tag, "] ImputeMissingVar (LoD)")
  mSet <- ImputeMissingVar(mSet, method = "lod")

  # --- 4. Normalization -----------------------------------------------------
  # PreparePrenormData() persists the cleaned intensity matrix as
  # `prenorm.qs` in CWD; Normalization() then applies row/transform/scale
  # operations and writes `row_norm.qs` + `complete_norm.qs`.
  #
  # Normalization(mSet, rowNorm, transNorm, scaleNorm, ref, ratio, ratioNum)
  #   rowNorm   = "NULL"       → no per-sample normalization
  #   transNorm = "LogNorm"    → log10(x) transform (variance stabilization)
  #   scaleNorm = "ParetoNorm" → mean-center + divide by sqrt(SD)
  #   ref       = NULL         → no reference sample/feature (used by some norms)
  #   ratio     = FALSE        → don't compute compound ratios
  #   ratioNum  = 20           → only used when ratio = TRUE
  message("[", tag, "] PreparePrenormData + Normalization (LogNorm + ParetoNorm)")
  mSet <- PreparePrenormData(mSet)
  mSet <- Normalization(mSet, "NULL", "LogNorm", "ParetoNorm",
                        ref = NULL, ratio = FALSE, ratioNum = 20)

  # Normalization summary plots — boxplots / density of pre vs post.
  # Args after imgName: (format, dpi, width). width = NA → use package default.
  PlotNormSummary(mSet,      "norm_0_",  "png", 72, width = NA)
  PlotSampleNormSummary(mSet,"snorm_0_", "png", 72, width = NA)

  # --- 5. Univariate: fold change -------------------------------------------
  # FC.Anal(mSet, fc.thresh, cmp.type, paired)
  #   fc.thresh = 2.0   → flag features with |log2 FC| ≥ log2(2)
  #   cmp.type  = 0     → group1 / group2 (sign uses factor level order)
  #   paired    = FALSE → unpaired
  # Writes `fold_change.csv`.
  message("[", tag, "] Fold change")
  mSet <- FC.Anal(mSet, fc.thresh = 2.0, cmp.type = 0, paired = FALSE)
  PlotFC(mSet, "fc_0_", "png", 72, width = NA)

  # --- 6. Univariate: t-tests -----------------------------------------------
  # Ttests.Anal(mSet, nonpar, threshp, paired, equal.var, pvalType)
  #   nonpar    = FALSE  → use Welch/Student t-test (FALSE = parametric)
  #   threshp   = 0.05   → threshold for "significant" tagging in output table
  #   paired    = FALSE  → unpaired
  #   equal.var = TRUE   → assume equal variances (Student); FALSE = Welch
  #   pvalType  = "fdr"  → adjust p-values via Benjamini-Hochberg FDR
  # Writes `t_test.csv`.
  message("[", tag, "] t-tests")
  mSet <- Ttests.Anal(mSet, nonpar = FALSE, threshp = 0.05, paired = FALSE,
                      equal.var = TRUE, pvalType = "fdr")
  PlotTT(mSet, "tt_0_", "png", 72, width = NA)

  # --- 7. Volcano plot (FC × p-value combined) ------------------------------
  # Volcano.Anal(mSet, paired, fcthresh, cmpType, nonpar, threshp, equal.var,
  #              pval.type)
  #   pval.type = "raw" → use raw p (set "fdr" to threshold on adjusted p)
  message("[", tag, "] Volcano")
  mSet <- Volcano.Anal(mSet, paired = FALSE, fcthresh = 2.0, cmpType = 0,
                       nonpar = FALSE, threshp = 0.1, equal.var = TRUE,
                       pval.type = "raw")
  # PlotVolcano(mSet, imgName, plotLbl, plotTheme, format, dpi, width, labelNum)
  #   plotLbl   = 1    → annotate top features with names
  #   plotTheme = 0    → default ggplot theme (1 = bw)
  #   labelNum  = 10   → label up to 10 hits
  PlotVolcano(mSet, "volcano_0_", plotLbl = 1, plotTheme = 0,
              format = "png", dpi = 72, width = NA, labelNum = 10)

  # --- 8. PCA --------------------------------------------------------------
  # Heavy compute: PCA.Anal off-loads to an Rserve subprocess on port 6311
  # via run_func_via_rsclient (R/general_misc_utils.R). Output stored as
  # mSet$analSet$pca, also persisted to disk for the web-server flow.
  message("[", tag, "] PCA")
  mSet <- PCA.Anal(mSet)

  # Pair-plot matrix of the first `pc.num` PCs (shows score-vs-score for all
  # combinations — useful to spot which axes separate the groups).
  PlotPCAPairSummary(mSet, "pca_pair_0_",   "png", 72, width = NA, pc.num = 5)

  # Scree (variance explained per PC) — same `scree.num` count as above.
  PlotPCAScree(     mSet, "pca_scree_0_",  "png", 72, width = NA, scree.num = 5)

  # 2D scores plot. Trailing positionals are:
  #   pcx = 1, pcy = 2     → axes plotted (PC1 vs PC2)
  #   reg = 0.95           → confidence-ellipse coverage (95 %)
  #   show = 1             → label samples (0 = points only)
  #   grey.scale = 0       → colour (1 = monochrome for B&W publication)
  PlotPCA2DScore(   mSet, "pca_score2d_0_","png", 72, width = NA, 1, 2, 0.95, 1, 0)

  # Loadings (variable contributions to PC1/PC2).
  PlotPCALoading(   mSet, "pca_loading_0_","png", 72, width = NA, 1, 2)

  # Biplot = scores + loadings overlaid; helps relate samples to features.
  PlotPCABiplot(    mSet, "pca_biplot_0_", "png", 72, width = NA, 1, 2)

  # --- 9. PLS-DA -----------------------------------------------------------
  # PLSR.Anal(mSet, reg = TRUE) → supervised projection using the class
  # labels as the response. Also off-loaded to the Rserve subprocess.
  #   reg = TRUE → regression mode (response is dummy-coded class). Set
  #                FALSE for genuine multivariate regression on numeric Y.
  message("[", tag, "] PLS-DA")
  mSet <- PLSR.Anal(mSet, reg = TRUE)

  # Same plot family as PCA, with PLS-specific axes (latent variables).
  PlotPLSPairSummary(mSet, "pls_pair_0_",   "png", 72, width = NA, pc.num = 5)
  PlotPLS2DScore(    mSet, "pls_score2d_0_","png", 72, width = NA, 1, 2, 0.95, 1, 0)
  PlotPLSLoading(    mSet, "pls_loading_0_","png", 72, width = NA, 1, 2)

  # --- 10. Persist transformed matrices for downstream consumers -----------
  # Writes `data_normalized.csv` and the per-stage CSV exports
  # (fold_change.csv, t_test.csv, volcano.csv, pca_*.csv, plsda_*.csv …).
  message("[", tag, "] SaveTransformedData")
  SaveTransformedData(mSet)

  message("[", tag, "] DONE — outputs in ", normalizePath(out_dir))

  # Return the final mSet invisibly so callers can poke at it
  # (`mSet$analSet$pca`, `mSet$dataSet$norm`, etc.) without having it
  # auto-print at the REPL.
  invisible(mSet)
}

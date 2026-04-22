## Shared MetaboAnalystR 2-group peak-table pipeline.
## Called from run_HR.R / run_SS.R. Writes all outputs under out_dir/.

run_pipeline <- function(csv_path, out_dir, tag = "run") {
  stopifnot(file.exists(csv_path))
  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
  csv_abs <- normalizePath(csv_path, mustWork = TRUE)
  orig_wd <- getwd(); on.exit(setwd(orig_wd), add = TRUE)
  setwd(out_dir)

  suppressPackageStartupMessages(library(MetaboAnalystR))

  message("[", tag, "] InitDataObjects / Read.TextData")
  mSet <- InitDataObjects("pktable", "stat", FALSE)
  mSet <- Read.TextData(mSet, csv_abs, "colu", "disc")

  message("[", tag, "] SanityCheckData")
  mSet <- SanityCheckData(mSet)

  message("[", tag, "] ImputeMissingVar (LoD)")
  mSet <- ImputeMissingVar(mSet, method = "lod")

  message("[", tag, "] PreparePrenormData + Normalization (LogNorm + ParetoNorm)")
  mSet <- PreparePrenormData(mSet)
  mSet <- Normalization(mSet, "NULL", "LogNorm", "ParetoNorm",
                        ref = NULL, ratio = FALSE, ratioNum = 20)
  PlotNormSummary(mSet,      "norm_0_",  "png", 72, width = NA)
  PlotSampleNormSummary(mSet,"snorm_0_", "png", 72, width = NA)

  message("[", tag, "] Fold change")
  mSet <- FC.Anal(mSet, fc.thresh = 2.0, cmp.type = 0, paired = FALSE)
  PlotFC(mSet, "fc_0_", "png", 72, width = NA)

  message("[", tag, "] t-tests")
  mSet <- Ttests.Anal(mSet, nonpar = FALSE, threshp = 0.05, paired = FALSE,
                      equal.var = TRUE, pvalType = "fdr")
  PlotTT(mSet, "tt_0_", "png", 72, width = NA)

  message("[", tag, "] Volcano")
  mSet <- Volcano.Anal(mSet, paired = FALSE, fcthresh = 2.0, cmpType = 0,
                       nonpar = FALSE, threshp = 0.1, equal.var = TRUE,
                       pval.type = "raw")
  PlotVolcano(mSet, "volcano_0_", plotLbl = 1, plotTheme = 0,
              format = "png", dpi = 72, width = NA, labelNum = 10)

  message("[", tag, "] PCA")
  mSet <- PCA.Anal(mSet)
  PlotPCAPairSummary(mSet, "pca_pair_0_",   "png", 72, width = NA, pc.num = 5)
  PlotPCAScree(     mSet, "pca_scree_0_",  "png", 72, width = NA, scree.num = 5)
  PlotPCA2DScore(   mSet, "pca_score2d_0_","png", 72, width = NA, 1, 2, 0.95, 1, 0)
  PlotPCALoading(   mSet, "pca_loading_0_","png", 72, width = NA, 1, 2)
  PlotPCABiplot(    mSet, "pca_biplot_0_", "png", 72, width = NA, 1, 2)

  message("[", tag, "] PLS-DA")
  mSet <- PLSR.Anal(mSet, reg = TRUE)
  PlotPLSPairSummary(mSet, "pls_pair_0_",   "png", 72, width = NA, pc.num = 5)
  PlotPLS2DScore(    mSet, "pls_score2d_0_","png", 72, width = NA, 1, 2, 0.95, 1, 0)
  PlotPLSLoading(    mSet, "pls_loading_0_","png", 72, width = NA, 1, 2)

  message("[", tag, "] SaveTransformedData")
  SaveTransformedData(mSet)

  message("[", tag, "] DONE — outputs in ", normalizePath(out_dir))
  invisible(mSet)
}

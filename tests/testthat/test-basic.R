context("Testing MetaboAnalystR - Basic Functionality")

library(MetaboAnalystR)

test_that("Uploading CSV Files Works", {
  
  mSet <- InitDataObjects("conc", "stat", FALSE)
  mSet <- Read.TextData(mSet, test_path("testdata/human_cachexia.csv"), "rowu", "disc")
  
  expect_equal(length(mSet), 6)
  expect_match(mSet$dataSet$type, "conc")
  expect_match(mSet$dataSet$cls.type, "disc")
  expect_match(mSet$dataSet$format, "rowu")
  expect_equal(length(mSet$dataSet$cmpd), 63)
  expect_match(mSet$analSet$type, "stat")
  expect_false(mSet$dataSet$paired)
  
})

test_that("Sanity Check Works", {
  
  mSet <- InitDataObjects("conc", "stat", FALSE)
  mSet <- Read.TextData(mSet, test_path("testdata/human_cachexia.csv"), "rowu", "disc")
  mSet <- SanityCheckData(mSet)
  
  expect_equal(length(mSet$dataSet), 24)
  expect_equal(mSet$dataSet$small.smpl.size, 0)
  expect_equal(mSet$dataSet$cls.num, 2)
  
})

test_that("Replace Min Works", {
  
  mSet <- InitDataObjects("conc", "stat", FALSE)
  mSet <- Read.TextData(mSet, test_path("testdata/human_cachexia.csv"), "rowu", "disc")
  mSet <- SanityCheckData(mSet)
  mSet <- ImputeMissingVar(mSet, method = "lod")
  
  # qs2 is the forward path; ov_qs_save writes qs2 format under the .qs name
  # when qs2 is available, so use qs2::qs_read to read back. ov_qs_read is
  # internal to MetaboAnalystR.
  proc <- qs2::qs_read("data_proc.qs")
  expect_equal(length(mSet$dataSet), 25)
  expect_equal(nrow(proc), 77)
  expect_equal(ncol(proc), 63)
  expect_match(mSet$msgSet$replace.msg,
               "Missing variables were replaced by", fixed = TRUE)
})

test_that("Normalization Works", {
  
  mSet <- InitDataObjects("conc", "stat", FALSE)
  mSet <- Read.TextData(mSet, test_path("testdata/human_cachexia.csv"), "rowu", "disc")
  mSet <- SanityCheckData(mSet)
  mSet <- ImputeMissingVar(mSet, method = "lod")
  mSet <- PreparePrenormData(mSet)
  mSet <- Normalization(mSet, "QuantileNorm", "LogNorm", "MeanCenter", ref=NULL, ratio=FALSE, ratioNum=20)  
  
  expect_equal(length(mSet$dataSet), 29)
  expect_equal(nrow(mSet$dataSet$norm), 77)
  expect_equal(ncol(mSet$dataSet$norm), 63)
  expect_match(mSet$dataSet$rownorm.method, "Quantile Normalization")
  expect_match(mSet$dataSet$trans.method, "Log10 Normalization")
  expect_match(mSet$dataSet$scale.method, "Mean Centering")
  expect_false(mSet$dataSet$combined.method)
  
})



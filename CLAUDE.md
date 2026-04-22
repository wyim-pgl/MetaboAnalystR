# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

R package `MetaboAnalystR` (v4.3.0, MIT) — the R engine behind the MetaboAnalyst web server. ~98 files under `R/`, 490 exports in `NAMESPACE`, native code under `src/` built via Rcpp + OpenMP. The package is kept **in sync with the web server**, so a lot of code has two modes: local R session vs. running inside the web stack (see dual-mode note below).

Authoritative install + dev-env guide lives in `install.md` (R 4.5.3 + required CRAN/Bioc pins). Don't duplicate it — update it.

## Common commands

Dev env is a micromamba env called `r453` (R 4.5.3). Prefix R invocations with:
```bash
export MAMBA_ROOT_PREFIX=$HOME/micromamba
~/.local/bin/micromamba run -n r453 <cmd>
```

- **Build + install from source**: `R CMD INSTALL --no-multiarch .`
- **Build tarball**: `R CMD build .` → `MetaboAnalystR_4.3.0.tar.gz`
- **Regenerate Rcpp glue** (`src/Exports.cpp`, `R/RcppExports.R`) after changing `// [[Rcpp::export]]` sigs: `Rscript -e 'Rcpp::compileAttributes(".")'`
- **Regenerate man/ + NAMESPACE** after roxygen changes: `Rscript -e 'devtools::document(".")'`
- **Run all tests** (`tests/testthat/`): `Rscript -e 'devtools::test(".")'`. Tests pull CSVs from `metaboanalyst.ca` — network required.
- **Run a single test file**: `Rscript -e 'library(testthat); library(MetaboAnalystR); test_file("tests/testthat/test-basic.R")'`
- **End-to-end smoke on sample data**: `Rscript example/run_HR.R` / `example/run_SS.R` (or `example/run_all.sh`). Outputs to `example/out_HR/` and `example/out_SS/`.

## Architecture — the big picture

### 1. `mSetObj` is the whole state

Every analysis function takes `mSetObj` (or `mSetObj=NA`) and returns an updated one. Construction flow:
```
InitDataObjects(data.type, anal.type, paired) →
  Read.TextData / Read.TextDataTs / Read.TextDataDose →
    SanityCheckData → ImputeMissingVar → PreparePrenormData → Normalization →
      <analysis: FC.Anal, Ttests.Anal, PCA.Anal, PLSR.Anal, Volcano.Anal, …> →
        SaveTransformedData
```
`data.type` ∈ {`conc`, `pktable`, `specbin`, `nmrpeak`, `mspeak`, `msspec`, `list`}; `anal.type` ∈ {`stat`, `pathora`/`pathqea`, `msetora`/`msetssp`/`msetqea`, `mf`, `cmpdmap`, `smpmap`, `pathinteg`}.

### 2. Dual-mode: local vs `.on.public.web`

`R/rpackage_config.R` defines `.on.public.web <- FALSE`. Many functions pivot on this flag:
- **Local**: `.get.mSet(obj)` returns `obj`; `.set.mSet(obj)` returns `obj`. Callers must chain `mSet <- SomeFunc(mSet, …)`.
- **Web** (`.on.public.web=TRUE`): `.set.mSet` does `mSetObj <<- obj` into `.GlobalEnv`; `.get.mSet` reads it back. The heavy `<<-` / global-mutation pattern across the codebase (e.g. `pca.cex`, `rpath`, `default.dpi`, `moduleNms.vec`, `metaboanalyst_env`) exists for that mode — don't "clean it up" without testing both modes.

### 3. Persistence: `ov_qs_*` wrappers

Analyses serialize intermediate state as `.qs` files **into the current working directory** (`data_orig.qs`, `data_proc.qs`, `prenorm.qs`, `row_norm.qs`, `complete_norm.qs`, `preproc.qs`, …). Plot PNGs also land in CWD. So callers must `setwd()` to an output dir before a pipeline — that is what `example/_pipeline.R` does.

Use `ov_qs_save(obj, file, …)` / `ov_qs_read(file, …)` / `ov_qs_exists(file)` — never `qs::qread`/`qs::qsave` or `qs2::qs_read`/`qs2::qs_save` directly. The wrappers (defined in `R/general_misc_utils.R` at package scope) try `qs2` first and fall back to legacy `qs`, and transparently handle `.qs` ↔ `.qs2` filename mismatches.

### 4. RSclient subprocess execution

Several analyses (PCA.Anal, PLSR.Anal, `.calculateDistSig`, some enrichment, heatmap dist) off-load heavy compute to an Rserve fork on port 6311 via `run_func_via_rsclient(func, args, timeout_sec)` in `R/general_misc_utils.R`. Arguments are shipped through bridge `.qs` files; the result is read back from another bridge file. Rserve auto-starts on first use (`bind error #98` on repeat runs is harmless).

**The subprocess is a fresh R session** — it does not inherit helpers from the master session. `run_func_via_rsclient` therefore ships `ov_qs_read`/`ov_qs_save`/`ov_qs_exists` to the subprocess via `.inject_qs_helpers(conn)` (same file), which `RS.assign`s the *same* package-level function objects after resetting their environment to `globalenv()`. Single source of truth — don't re-define the wrappers anywhere else.

### 5. Module layout (prefix in `R/`)

| Prefix | What lives there |
|---|---|
| `general_*` | init, IO (`Read.TextData*`), sanity, normalization, annotation |
| `stats_*` | univariates (FC/t/Volcano), chemometrics (PCA/PLS-DA/OPLS-DA), clustering, 3D plots, sig features |
| `enrich_*` | MSEA (ORA/QEA/SSP), pathway analysis, KEGG, name matching, integration |
| `dose_response_*` | dose-response curve fitting + DE |
| `multifac_*` | multi-factor ASCA, covariate adjustment, metadata, meta-block |
| `mgwas_*` | metabolite-GWAS / Mendelian randomization / two-sample / transcriptomics |
| `meta_*` | meta-analysis across studies |
| `peaks_*` / `spectra_*` / `tandem_*` | LC-MS peak picking / MS/MS (most heavy lifting delegates to the `OptiLCMS` package from GitHub) |
| `networks_*`, `power_*`, `biomarker_*` | network analysis, sample-size/power, ROC/biomarker |
| `util*`, `sweave_*`, `generic_*` | cross-cutting helpers + Sweave report generation |
| `rpackage_config.R` | `.on.public.web` flag |

### 6. Native code (`src/`)

- `src/Exports.cpp` — auto-generated from `Rcpp::compileAttributes()`; don't hand-edit.
- `src/cpp/` — `melt.cpp` (data.frame melt), `decorana.cpp` (DECORANA).
- `src/c/` — `mzROI.c`, `xcms_binners.c` (XCMS-derived ROI/binning), `fastmatch.c`, `nncgc.c`, `util.c`, `Internal_utils_batch.c`.
- `src/Makevars` groups them as BATCH / UTILS / XCMS / INIT object sets; OpenMP (`SHLIB_OPENMP_CXXFLAGS`) + LAPACK/BLAS/Fortran.

## Gotchas

- **`DESCRIPTION` Imports alignment**: `qs`, `qs2`, `ggrepel`, `RSclient`, `factoextra`, `vegan`, `pls` are runtime-required and now live in `Imports`. The `NAMESPACE` uses `importFrom(qs, qread, qsave)` (narrowed from blanket `import(qs)`). Mirror any change to this set in `install.md` step 4 and in `example/_pipeline.R`.
- **`qs` CRAN archive + gcc ≥ 13**: `qs` was archived and fails to build against modern `stringfish`. The fix is to pin `stringfish 0.15.8` + `qs 0.25.5` (see `install.md` step 5). `qs2` is the forward path, which is why `ov_qs_*` wrappers prefer it.
- **`InitDataObjects` default-arg trap**: the parameter is `default.dpi = 72`. Historically this was `default.dpi = default.dpi` (self-reference) which tripped "promise already under evaluation" — don't re-introduce that.
- **Plot / analysis side effects land in CWD**: any script that runs more than one analysis should `setwd()` to a per-run output directory. Reference implementation: `example/_pipeline.R`.
- **`NAMESPACE` is hand-maintained in places** (e.g. `import(qs)`). If you change imports, regenerate via `devtools::document()` and review the diff — don't blindly overwrite.
- **Tests hit the network**: `tests/testthat/` downloads CSVs from `metaboanalyst.ca`. Offline CI will fail those — prefer `example/run_HR.R` / `run_SS.R` against the CSVs under `example/` for deterministic smoke coverage.

# MetaboAnalystR Installation

Installation guide for **MetaboAnalystR 4.3.0** on **R 4.5.3** using pure CRAN / Bioconductor sources (no conda binaries).

Tested target: Linux / RStudio host with system libraries for Cairo, cURL, XML, SSL, etc.

---

## 1. System prerequisites

### Debian / Ubuntu (or RStudio Server Linux)

```bash
sudo apt update
sudo apt install -y \
    build-essential gfortran pkg-config \
    libcurl4-openssl-dev libssl-dev libxml2-dev \
    libcairo2-dev libxt-dev libx11-dev libfreetype6-dev libfontconfig1-dev \
    libharfbuzz-dev libfribidi-dev \
    libpng-dev libjpeg-dev libtiff5-dev \
    libgit2-dev libsqlite3-dev libicu-dev \
    zlib1g-dev libbz2-dev liblzma-dev
```

### macOS (Homebrew)

**Turnkey option** — a single script that walks through all of steps 1–7 below (`brew` system libs + R + RStudio + CRAN/Bioc deps + `qs` pin + clone + install + smoke test):

```bash
git clone https://github.com/wyim-pgl/MetaboAnalystR.git && \
  bash MetaboAnalystR/example/bootstrap_macos_brew.sh
```

Or step-by-step (recommended if you already have parts of the stack). Install Xcode Command Line Tools and Homebrew first, then:

```bash
# Core toolchain + system libs that CRAN/Bioc sources need at build time
brew install gcc gfortran pkg-config \
    cairo freetype fontconfig harfbuzz fribidi \
    libpng jpeg libtiff \
    curl openssl libxml2 icu4c libgit2 sqlite3

# R itself (official binary; includes Tcl/Tk + base packages)
brew install --cask r

# Optional but recommended — RStudio Desktop
brew install --cask rstudio
```

R installs to `/opt/homebrew/bin/R` on Apple Silicon and `/usr/local/bin/R` on Intel. Verify:

```bash
R --version        # -> R version 4.5.3 (2026-03-11) or newer
Rscript --version
```

### Verify version

R **≥ 4.5.3** must be on `PATH`. On any platform:

```bash
R --version    # should report 4.5.3+
```

### Using RStudio

Most people work through **RStudio Desktop** (or RStudio Server on Linux). After cloning the repo (step 6) you can either:

- Open the bundled project file: **`File → Open Project… → MetaboAnalystR.Rproj`**. RStudio sets the working directory to the repo root and loads the devtools environment.
- Or just open any script under `R/` or `example/`; RStudio's built-in Build pane recognizes an R package and exposes *Install* / *Document* / *Check* / *Test* actions that correspond to the shell commands in the sections below.

Steps 2–5 below (dependencies + `qs` pin) work identically inside the RStudio **Console** — paste the R blocks there. Step 6 (`R CMD INSTALL`) can be replaced by RStudio's *Build → Install Package* button, or by `devtools::install_local(".")` from the console.

---

## 2. Bootstrap R package managers

Launch R and run:

```r
options(repos = c(CRAN = "https://cloud.r-project.org"))

install.packages(c("BiocManager", "remotes", "devtools"))
BiocManager::install(version = "3.22", ask = FALSE, update = FALSE)   # matches R 4.5.x
```

---

## 3. Install Bioconductor dependencies

```r
BiocManager::install(
  c("RBGL", "BiocParallel", "edgeR", "fgsea",
    "impute", "pcaMethods", "siggenes"),
  ask = FALSE, update = FALSE
)
```

---

## 4. Install CRAN dependencies

All packages below are declared in `DESCRIPTION` Imports and are required at install time. `ggplot2 ≥ 3.4.0` is assumed (needed for `linewidth=` on line-class geoms) — any recent CRAN install satisfies this.

```r
cran_pkgs <- c(
  "RColorBrewer", "RSQLite", "Cairo", "Rcpp", "ggplot2", "Rserve",
  "rlang", "jsonlite", "plyr", "purrr", "data.table", "vctrs",
  "pROC", "caret", "crmn", "dplyr", "glasso", "gplots", "igraph",
  "plotly", "scales", "tibble", "lattice", "MASS",
  "qs2",         # primary .qs backend used by ov_qs_* wrappers
  "ggrepel",     # volcano / loading label repulsion
  "RSclient",    # PCA / PLS-DA / PERMANOVA run in an Rserve subprocess
  "factoextra",  # PCA variable contributions (get_pca_var)
  "vegan",       # PERMANOVA for score-plot group separation
  "pls"          # PLS-DA backend for PLSR.Anal
)
install.packages(cran_pkgs)
```

> `qs` is in Imports too but needs a pinned install because of a gcc/stringfish compatibility issue — see step 5.

---

## 5. Pin `qs` (and its `stringfish` peer)

`qs ≥ 0.27` was archived on CRAN and fails to compile against gcc ≥ 13 / current `stringfish`. MetaboAnalystR's `NAMESPACE` only pulls `qread` and `qsave` via `importFrom(qs, …)`, and the `ov_qs_*` wrappers (in `R/general_misc_utils.R`) prefer `qs2` and fall back to `qs` — but since `qs` is in `DESCRIPTION` Imports it must be installed for `R CMD INSTALL` to succeed. Pin both to a compatible pair:

```r
devtools::install_version("stringfish", version = "0.15.8", upgrade = "never")
devtools::install_version("qs",         version = "0.25.5", upgrade = "never")
```

> Order matters: `qs 0.25.5` calls `stringfish::check_if_native_is_ascii`, which was removed in `stringfish ≥ 0.16`. Install `stringfish 0.15.8` first (and before any later step pulls a newer version).

---

## 6. Install MetaboAnalystR from source

Clone the repo (this fork contains the refactor patches — `ov_qs_*`, `default.dpi`, `linewidth=`, aligned `DESCRIPTION` Imports):

```bash
git clone https://github.com/wyim-pgl/MetaboAnalystR.git
cd MetaboAnalystR
```

Then, from the shell at the repo root:

```bash
R CMD INSTALL --no-multiarch .
```

Or from inside R, pointed at the same folder:

```r
devtools::install_local(".", upgrade = "never", dependencies = FALSE)
```

Alternatively, install directly from GitHub without cloning — deps from steps 2–5 must be in place first:

```r
remotes::install_github("wyim-pgl/MetaboAnalystR",
                       upgrade = "never", dependencies = FALSE)
```

---

## 7. Verify

```r
library(MetaboAnalystR)
packageVersion("MetaboAnalystR")   # 4.3.0
R.version.string                   # R version 4.5.3 ...
```

End-to-end smoke test against the CSVs under `example/`:

```bash
Rscript example/run_HR.R   # example/HR_MOAB_noBlanks_HYD_vs_DEH-4.csv
Rscript example/run_SS.R   # example/SS_MOAB_noBlanks_HYD_vs_DEH-4.csv
# or both:
bash example/run_all.sh
```

Outputs land in `example/out_HR/` and `example/out_SS/` (normalization / FC / t-test / Volcano / PCA / PLS-DA plots + CSVs).

---

## 8. Optional Suggests

These are only needed for specific features (LC–MS processing, enrichment plots, pathway graphics, etc.). Install on demand:

```r
# Bioconductor
BiocManager::install(c(
  "graph", "globaltest", "GlobalAncova", "Rgraphviz", "preprocessCore",
  "genefilter", "sva", "limma", "KEGGgraph", "ctc", "MSnbase"
), ask = FALSE, update = FALSE)

# CRAN
install.packages(c(
  "htmltools", "ellipse", "scatterplot3d", "randomForest",
  "caTools", "e1071", "som", "RJSONIO", "rjson", "ROCR", "pheatmap",
  "fitdistrplus", "lars", "Hmisc", "magrittr", "xtable", "metap",
  "entropy", "rsm", "httr", "knitr", "rmarkdown", "testthat",
  "visNetwork", "ggraph", "car", "gdata", "huge",
  "ppcor", "progress", "iheatmapr", "arrow"
))

# GitHub-only
remotes::install_github("xia-lab/OptiLCMS")
```

---

## Troubleshooting

- **`there is no package called 'qs'` during `R CMD INSTALL` or lazy-load** — step 5 was skipped or failed. `qs` is in `DESCRIPTION` Imports so its absence blocks install. Re-run step 5 (both `stringfish 0.15.8` *and* `qs 0.25.5`).
- **`Cairo` build error about `cairo-ft backend`** — missing system `libcairo2-dev` / `libfreetype6-dev` / `libfontconfig1-dev`; install those and retry.
- **`qs` build error `check_if_native_is_ascii`** — `stringfish` is too new. Install `stringfish 0.15.8` first, then `qs 0.25.5` per step 5.
- **`RBGL` or other Bioc builds fail** — confirm Bioc release matches R: on R 4.5.x use Bioconductor 3.22 (`BiocManager::install(version = "3.22")`).
- **`could not find function "ov_qs_save"` / `"ov_qs_read"`** — you are on an older checkout. Pull the latest — the wrappers are defined in `R/general_misc_utils.R` at package scope.
- **`promise already under evaluation` in `InitDataObjects`** — same as above; `default.dpi=default.dpi` was patched to `default.dpi=72`.
- **`ExportResultMatArrow failed: there is no package called 'arrow'`** — non-fatal warning; Arrow export is an optional side-effect. Install `arrow` (needs system `libarrow-dev` or pre-built RSPM binary) to silence.
- **`command failed ... Rserve ... bind error #98`** — Rserve auto-starts on port 6311 and complains if it's already running from a previous session. Harmless unless you see downstream RSclient failures — in that case kill stale `Rserve` processes (`pkill -f Rserve`) and retry.

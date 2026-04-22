#!/usr/bin/env bash
# Turnkey MetaboAnalystR bootstrap for macOS via Homebrew.
#
# Walks through the install.md sequence end-to-end: system prereqs (brew),
# R base + RStudio Desktop, CRAN/Bioc deps, qs pin, package install,
# and a smoke-test run against example/HR_MOAB_noBlanks_HYD_vs_DEH-4.csv.
#
# Usage:
#   bash example/bootstrap_macos_brew.sh               # default: clones to ~/src
#   MA_CLONE_DIR=/tmp/ma bash example/bootstrap_macos_brew.sh
#   MA_SKIP_CLONE=1 bash example/bootstrap_macos_brew.sh   # run from an existing checkout (cwd)
set -euo pipefail

CLONE_DIR="${MA_CLONE_DIR:-$HOME/src/MetaboAnalystR}"
REPO_URL="${MA_REPO_URL:-https://github.com/wyim-pgl/MetaboAnalystR.git}"
SKIP_CLONE="${MA_SKIP_CLONE:-0}"

log() { printf '\033[1;36m[bootstrap]\033[0m %s\n' "$*"; }

if ! [[ "$OSTYPE" == darwin* ]]; then
  echo "This script is macOS-only. Use install.md section 1 for Linux." >&2
  exit 1
fi

if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew not found. Install from https://brew.sh first." >&2
  exit 1
fi

# --------------------------------------------------------------------
# 1. System libraries that CRAN/Bioc sources need at build time
# --------------------------------------------------------------------
log "Installing system libraries via Homebrew"
brew install \
  gcc gfortran pkg-config \
  cairo freetype fontconfig harfbuzz fribidi \
  libpng jpeg libtiff \
  curl openssl libxml2 icu4c libgit2 sqlite

log "Installing R base + RStudio Desktop"
brew install --cask r
brew install --cask rstudio || log "RStudio install skipped (already installed or declined)"

# --------------------------------------------------------------------
# 2-5. R package managers, Bioconductor, CRAN deps, qs pin
# --------------------------------------------------------------------
log "Running R bootstrap (package managers + Bioc 3.22 + CRAN + qs pin)"
Rscript --vanilla - <<'RBOOT'
options(repos = c(CRAN = "https://cloud.r-project.org"))

if (!requireNamespace("BiocManager", quietly = TRUE)) install.packages("BiocManager")
if (!requireNamespace("remotes",     quietly = TRUE)) install.packages("remotes")
if (!requireNamespace("devtools",    quietly = TRUE)) install.packages("devtools")

BiocManager::install(version = "3.22", ask = FALSE, update = FALSE)

BiocManager::install(
  c("RBGL", "BiocParallel", "edgeR", "fgsea",
    "impute", "pcaMethods", "siggenes"),
  ask = FALSE, update = FALSE
)

install.packages(c(
  "RColorBrewer", "RSQLite", "Cairo", "Rcpp", "ggplot2", "Rserve",
  "rlang", "jsonlite", "plyr", "purrr", "data.table", "vctrs",
  "pROC", "caret", "crmn", "dplyr", "glasso", "gplots", "igraph",
  "plotly", "scales", "tibble", "lattice", "MASS",
  "qs2", "ggrepel", "RSclient", "factoextra", "vegan", "pls"
))

# qs + stringfish pin (must install stringfish first)
devtools::install_version("stringfish", version = "0.15.8", upgrade = "never")
devtools::install_version("qs",         version = "0.25.5", upgrade = "never")
RBOOT

# --------------------------------------------------------------------
# 6. Clone + install the package
# --------------------------------------------------------------------
if [[ "$SKIP_CLONE" == "1" ]]; then
  REPO_DIR="$(pwd)"
  log "Using existing checkout: $REPO_DIR"
else
  if [[ -d "$CLONE_DIR/.git" ]]; then
    log "Updating existing clone at $CLONE_DIR"
    git -C "$CLONE_DIR" pull --ff-only
  else
    log "Cloning $REPO_URL -> $CLONE_DIR"
    mkdir -p "$(dirname "$CLONE_DIR")"
    git clone "$REPO_URL" "$CLONE_DIR"
  fi
  REPO_DIR="$CLONE_DIR"
fi

log "R CMD INSTALL $REPO_DIR"
R CMD INSTALL --no-multiarch "$REPO_DIR"

# --------------------------------------------------------------------
# 7. Smoke test
# --------------------------------------------------------------------
log "Running smoke test: example/run_HR.R"
Rscript "$REPO_DIR/example/run_HR.R"

log "DONE"
log "Package installed; outputs under $REPO_DIR/example/out_HR/"
log "Open RStudio and File > Open Project... > $REPO_DIR/MetaboAnalystR.Rproj to continue."

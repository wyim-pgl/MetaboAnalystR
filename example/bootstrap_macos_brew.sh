#!/usr/bin/env bash
# =============================================================================
# Turnkey MetaboAnalystR bootstrap for macOS via Homebrew
# =============================================================================
#
# What this does
#   Walks through the install.md sequence end-to-end on a clean macOS box:
#     1. Verifies prereqs (macOS, Homebrew).
#     2. Installs system C/Fortran libraries that R source-builds need.
#     3. Installs R base + RStudio Desktop via Homebrew Cask.
#     4. Bootstraps R package managers (BiocManager, remotes, devtools).
#     5. Installs Bioconductor 3.22 deps that MetaboAnalystR needs.
#     6. Installs the CRAN runtime stack.
#     7. Pins `stringfish 0.15.8` + `qs 0.25.5` (see "Why the qs pin" below).
#     8. Clones (or reuses) the package source.
#     9. Builds + installs MetaboAnalystR from source via R CMD INSTALL.
#    10. Runs the HR smoke test as an end-to-end sanity check.
#
# Why the qs pin
#   The original `qs` package was archived on CRAN. Its native code does not
#   compile against the modern `stringfish` API on gcc ≥ 13. The combination
#   that does still build — and that the codebase's `ov_qs_*` wrappers know
#   how to fall back to — is `stringfish 0.15.8` + `qs 0.25.5`. The forward
#   path is `qs2`, which we also install (the wrappers prefer qs2 when
#   present and only fall back to qs for legacy `.qs` files).
#
# Usage
#   bash example/bootstrap_macos_brew.sh                          # clones to ~/src/MetaboAnalystR
#   MA_CLONE_DIR=/tmp/ma bash example/bootstrap_macos_brew.sh     # custom clone dir
#   MA_REPO_URL=...      bash example/bootstrap_macos_brew.sh     # custom fork
#   MA_SKIP_CLONE=1      bash example/bootstrap_macos_brew.sh     # use existing checkout (cwd)
#
# Notes
#   * Idempotent — safe to re-run; existing brew/CRAN/Bioc packages are skipped.
#   * Does not modify the active R user library path; uses whatever R picks up.
#   * If you've previously installed R from CRAN's `.pkg`, brew will install
#     a *second* copy and the one on PATH wins. Set R_HOME explicitly if you
#     want to force a specific R installation.
# =============================================================================
set -euo pipefail

# --- Config (env-overridable) ------------------------------------------------
CLONE_DIR="${MA_CLONE_DIR:-$HOME/src/MetaboAnalystR}"        # where to git-clone the repo
REPO_URL="${MA_REPO_URL:-https://github.com/wyim-pgl/MetaboAnalystR.git}"
SKIP_CLONE="${MA_SKIP_CLONE:-0}"                              # "1" → run from CWD, no clone

# Coloured `[bootstrap]` log prefix so the script's own messages stand out
# from `brew`, `R CMD INSTALL`, and Bioc package-install chatter.
log() { printf '\033[1;36m[bootstrap]\033[0m %s\n' "$*"; }

# --- Prereq checks -----------------------------------------------------------
# Refuse to run on Linux: Homebrew on Linux exists but lacks the `--cask`
# entries we rely on for R + RStudio. Linux users should follow install.md
# section 1 (apt / dnf / pacman) instead.
if ! [[ "$OSTYPE" == darwin* ]]; then
  echo "This script is macOS-only. Use install.md section 1 for Linux." >&2
  exit 1
fi

# Homebrew itself isn't bootstrapped here — we don't want to silently install
# `brew` for the user. They should make that decision themselves.
if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew not found. Install from https://brew.sh first." >&2
  exit 1
fi

# --------------------------------------------------------------------
# Step 1 — System libraries that CRAN/Bioc source builds need
# --------------------------------------------------------------------
# These are non-R native dependencies; R can't install them with
# install.packages(). Most are linker-time deps for common CRAN packages:
#
#   gcc gfortran      — compilers (Fortran needed by lapack-based pkgs)
#   pkg-config        — used by configure scripts to find headers/libs
#   cairo + freetype  — Cairo / ggplot2 PNG/PDF backends, font rendering
#   harfbuzz fribidi  — text shaping / bidi for systemfonts/textshaping
#   libpng jpeg tiff  — raster graphics formats
#   curl openssl      — `httr`, `RCurl`, secure downloads
#   libxml2 icu4c     — XML parsing, Unicode collation
#   libgit2 sqlite    — `gert`/`git2r`, `RSQLite`
log "Installing system libraries via Homebrew"
brew install \
  gcc gfortran pkg-config \
  cairo freetype fontconfig harfbuzz fribidi \
  libpng jpeg libtiff \
  curl openssl libxml2 icu4c libgit2 sqlite

# R + RStudio via Homebrew Cask. RStudio failure is non-fatal because the
# user may have it installed via the official `.dmg` already.
log "Installing R base + RStudio Desktop"
brew install --cask r
brew install --cask rstudio || log "RStudio install skipped (already installed or declined)"

# --------------------------------------------------------------------
# Steps 2-5 — R package managers, Bioconductor, CRAN deps, qs pin
# --------------------------------------------------------------------
# We use a single Rscript heredoc so all R-side bootstrap runs in one process
# (faster than re-launching R per call) and is easy to skip/replay.
log "Running R bootstrap (package managers + Bioc 3.22 + CRAN + qs pin)"
Rscript --vanilla - <<'RBOOT'
# Pin a fast/known mirror so install.packages() doesn't prompt interactively.
options(repos = c(CRAN = "https://cloud.r-project.org"))

# --- Step 2: package managers --------------------------------------------
# BiocManager   → installs Bioconductor packages aware of Bioc release pinning
# remotes       → install_github / install_version (lightweight)
# devtools      → richer dev workflow (install_version, build, check, …)
if (!requireNamespace("BiocManager", quietly = TRUE)) install.packages("BiocManager")
if (!requireNamespace("remotes",     quietly = TRUE)) install.packages("remotes")
if (!requireNamespace("devtools",    quietly = TRUE)) install.packages("devtools")

# --- Step 3: pin Bioconductor release to 3.22 ----------------------------
# MetaboAnalystR's Bioc dependency versions are known to work against 3.22;
# `update = FALSE` avoids dragging in updates the user didn't ask for.
BiocManager::install(version = "3.22", ask = FALSE, update = FALSE)

# --- Step 4: Bioconductor packages MetaboAnalystR depends on -------------
#   RBGL          → Boost graph library bindings (used by network analyses)
#   BiocParallel  → parallel-apply harness used in heavy stats
#   edgeR         → DE / count-based stats (meta-analysis pathways)
#   fgsea         → fast GSEA enrichment
#   impute        → KNN missing-value imputation
#   pcaMethods    → PCA variants (BPCA, PPCA, NIPALS) used as alternates
#   siggenes      → SAM / EBAM significance analysis (sigfeatures module)
BiocManager::install(
  c("RBGL", "BiocParallel", "edgeR", "fgsea",
    "impute", "pcaMethods", "siggenes"),
  ask = FALSE, update = FALSE
)

# --- Step 5: CRAN runtime stack ------------------------------------------
# Mirrors DESCRIPTION's Imports field (minus the Bioc subset above and minus
# qs, which is pinned separately below). qs2 / RSclient / factoextra / vegan
# / pls were promoted to Imports by this fork.
install.packages(c(
  "RColorBrewer", "RSQLite", "Cairo", "Rcpp", "ggplot2", "Rserve",
  "rlang", "jsonlite", "plyr", "purrr", "data.table", "vctrs",
  "pROC", "caret", "crmn", "dplyr", "glasso", "gplots", "igraph",
  "plotly", "scales", "tibble", "lattice", "MASS",
  "qs2", "ggrepel", "RSclient", "factoextra", "vegan", "pls"
))

# --- Step 6: qs + stringfish pin -----------------------------------------
# Order matters: `stringfish` is a build-time dep of `qs`, so install the
# 0.15.8 pin first; otherwise devtools::install_version will pull whatever
# stringfish is current and the qs 0.25.5 build will fail.
# `upgrade = "never"` keeps install_version from quietly bumping the pin's
# transitive deps and re-introducing the same build break we're avoiding.
devtools::install_version("stringfish", version = "0.15.8", upgrade = "never")
devtools::install_version("qs",         version = "0.25.5", upgrade = "never")
RBOOT

# --------------------------------------------------------------------
# Step 6 (shell side) — Clone or reuse the repo, then install
# --------------------------------------------------------------------
if [[ "$SKIP_CLONE" == "1" ]]; then
  # Caller is invoking us from inside an existing checkout (e.g. CI, dev box).
  REPO_DIR="$(pwd)"
  log "Using existing checkout: $REPO_DIR"
else
  if [[ -d "$CLONE_DIR/.git" ]]; then
    # Update an existing clone in place. Fast-forward only — refuse to merge
    # local commits the user might have on top.
    log "Updating existing clone at $CLONE_DIR"
    git -C "$CLONE_DIR" pull --ff-only
  else
    # Fresh clone. mkdir -p the parent first so the user can pass
    # MA_CLONE_DIR=/somewhere/that/doesnt/exist/yet.
    log "Cloning $REPO_URL -> $CLONE_DIR"
    mkdir -p "$(dirname "$CLONE_DIR")"
    git clone "$REPO_URL" "$CLONE_DIR"
  fi
  REPO_DIR="$CLONE_DIR"
fi

# `--no-multiarch`: macOS R historically built i386 + x86_64 side by side;
# we only need the native arch and skipping the dual build saves time.
log "R CMD INSTALL $REPO_DIR"
R CMD INSTALL --no-multiarch "$REPO_DIR"

# --------------------------------------------------------------------
# Step 7 — Smoke test
# --------------------------------------------------------------------
# Runs the HR pipeline (Init → Read → Sanity → Impute → Norm → FC → t →
# Volcano → PCA → PLS-DA → Save). Outputs land in REPO_DIR/example/out_HR/.
# A green run also exercises the Rserve subprocess (PCA + PLS-DA), which
# verifies the ov_qs_* helper injection — the path most likely to break
# after a packaging change.
log "Running smoke test: example/run_HR.R"
Rscript "$REPO_DIR/example/run_HR.R"

log "DONE"
log "Package installed; outputs under $REPO_DIR/example/out_HR/"
log "Open RStudio and File > Open Project... > $REPO_DIR/MetaboAnalystR.Rproj to continue."

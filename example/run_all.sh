#!/usr/bin/env bash
# =============================================================================
# Run both example smoke-test pipelines (HR + SS) back-to-back.
#
# What this is for
#   A one-shot "does the package still work end-to-end?" check after a build,
#   refactor, or fresh install. Each runner exercises:
#     Read.TextData → SanityCheck → ImputeMissingVar → Normalization →
#     FC → t-test → Volcano → PCA (RSclient subprocess) → PLS-DA → Save.
#   The PCA + PLS-DA stages also exercise the Rserve subprocess fork, so a
#   green run here also verifies the `ov_qs_*` helper injection path.
#
# Pre-reqs
#   * MetaboAnalystR is installed in the active R library path.
#   * The R binary on PATH can find that library — typically by activating
#     the micromamba env first:
#         export MAMBA_ROOT_PREFIX=$HOME/micromamba
#         micromamba activate r453
#     …or by overriding R_BIN below to point at a specific Rscript.
#
# Usage
#   bash example/run_all.sh                       # default Rscript on PATH
#   R_BIN=/opt/r453/bin/Rscript bash example/run_all.sh
#
# Exit behaviour
#   set -euo pipefail makes us bail on the first error: HR runner failure
#   means SS will not be attempted. That is intentional — we want a clear
#   signal of which stage broke first.
# =============================================================================
set -euo pipefail

# `HERE` resolves to the absolute path of the directory holding *this* script,
# regardless of where the user invoked it from. Lets us refer to sibling
# scripts (`run_HR.R`, `run_SS.R`) without depending on the caller's CWD.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Allow the caller to point at a non-default Rscript (e.g. a specific R
# version inside a conda/micromamba env, or a custom build path).
R_BIN="${R_BIN:-Rscript}"

# Each runner is self-contained: it locates its own input CSV via
# .script_dir(), creates its own out_*/ directory, restores CWD on exit,
# and prints `[HR] DONE` / `[SS] DONE` on success.
"$R_BIN" "$HERE/run_HR.R"
"$R_BIN" "$HERE/run_SS.R"

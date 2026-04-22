#!/usr/bin/env bash
# Run both CSV pipelines. Activate the micromamba r453 env first, or set R_BIN.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
R_BIN="${R_BIN:-Rscript}"

"$R_BIN" "$HERE/run_HR.R"
"$R_BIN" "$HERE/run_SS.R"

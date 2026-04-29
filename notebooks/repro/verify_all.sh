#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

mkdir -p /tmp/empty_jupyter_config
export JUPYTER_CONFIG_DIR=/tmp/empty_jupyter_config
export XDG_CONFIG_HOME=/tmp/empty_jupyter_config

notebooks=(
  01_exp1_repro.ipynb
  02_exp2_repro.ipynb
  03_exp3_repro.ipynb
  04_exp4_repro.ipynb
)

for nb in "${notebooks[@]}"; do
  echo "=== ${nb} ==="
  conda run -n rlab jupyter nbconvert \
    --to notebook \
    --execute \
    --ExecutePreprocessor.timeout=7200 \
    --ExecutePreprocessor.kernel_name=ir \
    "${nb}" \
    --output "${nb%.ipynb}_executed.ipynb"
done

echo
echo "All four repro notebooks executed."
echo "Review the final summary cell in each executed notebook for PASS/FAIL status."

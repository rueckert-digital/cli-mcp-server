#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

PYTHON_BIN="${PYTHON_BIN:-python3}"
VENV_DIR="${VENV_DIR:-${REPO_DIR}/.venv}"

echo "Repo: ${REPO_DIR}"
echo "Python: ${PYTHON_BIN}"
echo "Virtualenv: ${VENV_DIR}"

"${PYTHON_BIN}" -m venv "${VENV_DIR}"
# shellcheck disable=SC1091
source "${VENV_DIR}/bin/activate"

python -m pip install --quiet -U pip
python -m pip install --quiet .
python -m pip install --quiet build
python -m build --quiet

echo
echo "Build complete. CLI available at: ${VENV_DIR}/bin/cli-mcp-server"

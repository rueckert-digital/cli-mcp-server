#!/bin/bash

trap 'rc=$?; if [[ $rc -ne 124 ]]; then echo "❌ Error on line $LINENO (rc=$rc)" >&2; fi' ERR
set -Ee

export PYTHONUNBUFFERED=1

if [[ -f ".env" ]]; then
  echo "Sourcing .env ..."
  set -a
  source .env
  set +a
fi

# prerequisites
echo "Prerequisites ..."
python -m venv .venv
source .venv/bin/activate
python -m pip install --quiet -U pip
python -m pip install --quiet .

# unittest
echo "Run unit tests ..."
python -m unittest discover --quiet -v


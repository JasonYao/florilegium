#!/usr/bin/env bash

set -euo pipefail

compile_case() {
  local case_number="$1"
  local output="build/region-cases/${case_number}"
  local arguments
  arguments=(
    -interaction=nonstopmode
    -halt-on-error
    "-output-directory=${output}"
    "-jobname=regions-${case_number}"
    "\def\regionfirstcase{${case_number}}\def\regionlastcase{${case_number}}\def\regiontimingfile{${output}/region-times.tsv}\input{tests/regions.tex}"
  )
  mkdir -p "${output}"
  if [[ -n "${RUN:-}" ]]; then
    "${RUN}" lualatex "${arguments[@]}"
  else
    lualatex "${arguments[@]}"
  fi
}

if [[ "${1:-}" == "--case" ]]; then
  compile_case "$2"
  exit
fi

jobs="${REGION_JOBS:-4}"
if [[ ! "${jobs}" =~ ^[1-9][0-9]*$ ]]; then
  echo "REGION_JOBS must be a positive integer." >&2
  exit 2
fi

mkdir -p build/region-cases
rm -f build/region-times.tsv
printf '%s\n' {1..7} | xargs -P "${jobs}" -n 1 "$0" --case

pdfs=()
for case_number in {1..7}; do
  pdfs+=("build/region-cases/${case_number}/regions-${case_number}.pdf")
done
if [[ -n "${RUN:-}" ]]; then
  "${RUN}" pdfunite "${pdfs[@]}" regions.pdf
else
  pdfunite "${pdfs[@]}" regions.pdf
fi
for case_number in {1..7}; do
  cat "build/region-cases/${case_number}/region-times.tsv"
done > build/region-times.tsv

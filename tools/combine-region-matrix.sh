#!/usr/bin/env bash

set -euo pipefail

input_dir="${1:-build/region-cases}"
output_pdf="${2:-regions.pdf}"
output_times="${3:-build/region-times.tsv}"

pdfs=()
for case_number in {1..7}; do
  pdfs+=("${input_dir}/regions-${case_number}.pdf")
done
pdfunite "${pdfs[@]}" "${output_pdf}"

for case_number in {1..7}; do
  cat "${input_dir}/region-times-${case_number}.tsv"
done > "${output_times}"

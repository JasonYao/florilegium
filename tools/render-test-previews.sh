#!/usr/bin/env bash

set -euo pipefail

mkdir -p build test-previews
: > build/preview-times.tsv

render_preview() {
  local name="$1" pdf="$2" page="$3" started ended elapsed
  started="$(date +%s%N)"
  if [[ -n "${RUN:-}" ]]; then
    "${RUN}" pdftoppm -f "${page}" -l "${page}" -singlefile -png -scale-to 900 \
      "${pdf}" "test-previews/${name}"
  else
    pdftoppm -f "${page}" -l "${page}" -singlefile -png -scale-to 900 \
      "${pdf}" "test-previews/${name}"
  fi
  ended="$(date +%s%N)"
  elapsed="$(awk -v start="${started}" -v end="${ended}" \
    'BEGIN { printf "%.3f", (end - start) / 1000000000 }')"
  printf '%s\t%s\n' "${name}" "${elapsed}" >> build/preview-times.tsv
}

for pdf in florilegium.pdf florilegium-grow.pdf showcase.pdf spread.pdf \
           specimen.pdf specimen-geometric.pdf ornaments.pdf; do
  render_preview "${pdf%.pdf}" "${pdf}" 1
done

region_cases=(single-rectangle disjoint-rectangles overlapping-rectangles \
              single-polygon multiple-polygons complex-polygon complex-smooth-polygon)
levels=(low medium high)
page=1
for case in "${region_cases[@]}"; do
  for density in "${levels[@]}"; do
    for intensity in "${levels[@]}"; do
      render_preview "regions-${case}-${density}-${intensity}" "regions.pdf" "${page}"
      page=$((page + 1))
    done
  done
done

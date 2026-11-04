#!/usr/bin/env bash

set -euo pipefail

pulls="$(gh api --method GET "repos/${REPOSITORY}/pulls" \
  -f state=open -f "head=${OWNER}:${BRANCH}" -f per_page=100)"
pull_number="$(jq -r \
  --arg repository "${REPOSITORY}" \
  --arg branch "${BRANCH}" \
  '[.[] | select(.head.ref == $branch and .head.repo != null and .head.repo.full_name == $repository)][0].number // empty' \
  <<< "${pulls}")"

if [[ -z "${pull_number}" ]]; then
  echo "No open pull request found for ${BRANCH}; skipping test-results comment."
  exit 0
fi

function upload_attachment() {
  local file_name="$1"
  local response
  local status

  if ! response="$(curl --silent --show-error \
    --request POST \
    --header "Authorization: token ${GITHUB_UPLOAD_TOKEN}" \
    --header "Accept: application/vnd.github+json" \
    --header "X-GitHub-Api-Version: 2022-11-28" \
    --header "Content-Type: application/octet-stream" \
    --data-binary "@${file_name}" \
    --write-out $'\n%{http_code}' \
    "https://uploads.github.com/user-attachments/assets?name=${file_name##*/}&content_type=image/png&repository_id=${GITHUB_REPOSITORY_ID}")"; then
    echo "Could not upload preview ${file_name}." >&2
    return 1
  fi

  status="${response##*$'\n'}"
  response="${response%$'\n'*}"
  if [[ "${status}" != 201 ]]; then
    echo "Could not upload preview ${file_name} (HTTP ${status})." >&2
    return 1
  fi

  jq -er '.url' <<< "${response}"
}

commenter="$(gh api user --jq .login)"
if [[ -n "${TEST_ARTIFACT_URL:-}" ]]; then
  artifact_link="[Download all generated PDFs and previews](${TEST_ARTIFACT_URL})"
else
  artifact_link="[Workflow run and available artifacts](${RUN_URL})"
fi

declare -A preview_urls page_times preview_times case_times
region_cases=(single-rectangle disjoint-rectangles overlapping-rectangles \
              single-polygon multiple-polygons complex-polygon complex-smooth-polygon)
density_names=(low medium high)
intensity_names=(low medium high)
region_time_total=0

if [[ -f "${TEST_RESULTS_DIR}/build/region-times.tsv" ]]; then
  while IFS=$'\t' read -r page duration; do
    [[ -n "${page}" && -n "${duration}" ]] || continue
    page_times["${page}"]="${duration}"
    case_index=$(( (page - 1) / 9 ))
    case_name="${region_cases[$case_index]}"
    previous="${case_times[$case_name]:-0}"
    case_times["${case_name}"]="$(awk -v a="$previous" -v b="$duration" 'BEGIN { printf "%.3f", a + b }')"
    region_time_total="$(awk -v a="$region_time_total" -v b="$duration" 'BEGIN { printf "%.3f", a + b }')"
  done < "${TEST_RESULTS_DIR}/build/region-times.tsv"
fi

default_preview_total=0
if [[ -f "${TEST_RESULTS_DIR}/build/preview-times.tsv" ]]; then
  while IFS=$'\t' read -r name duration; do
    [[ -n "${name}" && -n "${duration}" ]] || continue
    preview_times["${name}"]="${duration}"
    if [[ "${name}" != regions-* ]]; then
      default_preview_total="$(awk -v a="$default_preview_total" -v b="$duration" 'BEGIN { printf "%.3f", a + b }')"
    fi
  done < "${TEST_RESULTS_DIR}/build/preview-times.tsv"
fi

for name in florilegium florilegium-grow showcase spread specimen specimen-geometric ornaments; do
  preview="${TEST_RESULTS_DIR}/test-previews/${name}.png"
  if [[ -f "${preview}" ]]; then
    preview_urls["default-${name}"]="$(upload_attachment "${preview}")" || preview_urls["default-${name}"]=
  fi
done

for case in "${region_cases[@]}"; do
  for density in "${density_names[@]}"; do
    for intensity in "${intensity_names[@]}"; do
      name="regions-${case}-${density}-${intensity}"
      preview="${TEST_RESULTS_DIR}/test-previews/${name}.png"
      if [[ -f "${preview}" ]]; then
        preview_urls["${name}"]="$(upload_attachment "${preview}")" || preview_urls["${name}"]=
      fi
    done
  done
done

table="## [Custom] Section 1: Regions — ${region_time_total}s garden generation"
for i in "${!region_cases[@]}"; do
  case="${region_cases[$i]}"
  case_title="${case//-/ }"
  case_title="${case_title^}"
  case_total="${case_times[$case]:-0.000}"
  table+=$'\n\n'"<details>"$'\n'"<summary>Case $((i + 1)): ${case_title} — ${case_total}s garden generation</summary>"
  table+=$'\n\n| | Low intensity | Medium intensity | High intensity |'
  table+=$'\n| --- | --- | --- | --- |'
  for density in "${density_names[@]}"; do
    row="| ${density^} density |"
    density_index=0
    for level in "${density_names[@]}"; do
      [[ "$level" == "$density" ]] && break
      density_index=$((density_index + 1))
    done
    for intensity in "${intensity_names[@]}"; do
      name="regions-${case}-${density}-${intensity}"
      url="${preview_urls[$name]:-}"
      intensity_index=0
      for level in "${intensity_names[@]}"; do
        [[ "$level" == "$intensity" ]] && break
        intensity_index=$((intensity_index + 1))
      done
      if [[ -n "${url}" ]]; then
        image_page=$((i * 9 + density_index * 3 + intensity_index + 1))
        duration="${page_times[$image_page]:-unknown}"
        cell="<img src=\"${url}\" width=\"180\" alt=\"${density} density, ${intensity} intensity\" title=\"Garden generated in ${duration}s\">"
      else
        cell="Preview unavailable"
      fi
      row+=" ${cell} |"
    done
    table+=$'\n'"${row}"
  done
  table+=$'\n\n'"</details>"
done

table+=$'\n\n'"## [Default] Section 2: Original — ${default_preview_total}s preview rendering"
table+=$'\n\n<details>'$'\n''<summary>Default document previews</summary>'
table+=$'\n\n| PDF output | Inline preview |'
table+=$'\n| --- | --- |'
default_count=0
for name in florilegium florilegium-grow showcase spread specimen specimen-geometric ornaments; do
  url="${preview_urls[default-${name}]:-}"
  if [[ -n "${url}" ]]; then
    duration="${preview_times[$name]:-unknown}"
    table+=$'\n'"| ${name}.pdf | <img src=\"${url}\" width=\"240\" alt=\"${name}\" title=\"Preview generated in ${duration}s\"> |"
    default_count=$((default_count + 1))
  fi
done
if (( default_count == 0 )); then
  table+=$'\n| No default PDF previews were produced. | — |'
fi
table+=$'\n\n</details>'

body="$(printf '<!-- florilegium-test-results -->\n### Automated test results\n\n- Lua: <code>%s</code>\n- PDFs: <code>%s</code>\n- %s\n\n%s\n\n[Workflow run](%s)' \
  "${LUA_RESULT}" "${PDF_RESULT}" "${artifact_link}" "${table}" "${RUN_URL}")"
comment_id="$(gh api --method GET \
  "repos/${REPOSITORY}/issues/${pull_number}/comments" -f per_page=100 |
  jq -r --arg commenter "${commenter}" \
    '[.[] | select(.user.login == $commenter and ((.body // "") | startswith("<!-- florilegium-test-results -->")))] | .[-1].id // empty')"

if [[ -n "${comment_id}" ]]; then
  gh api --method PATCH \
    "repos/${REPOSITORY}/issues/comments/${comment_id}" -f body="${body}" > /dev/null
else
  gh api --method POST \
    "repos/${REPOSITORY}/issues/${pull_number}/comments" -f body="${body}" > /dev/null
fi

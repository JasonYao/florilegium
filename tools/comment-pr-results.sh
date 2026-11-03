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

declare -A preview_urls=()
for name in florilegium florilegium-grow showcase spread specimen specimen-geometric ornaments; do
  preview="${TEST_RESULTS_DIR}/test-previews/${name}.png"
  if [[ -f "${preview}" ]]; then
    preview_urls["default-${name}"]="$(upload_attachment "${preview}")" || preview_urls["default-${name}"]=
  fi
done

region_cases=(single-rectangle disjoint-rectangles overlapping-rectangles \
              single-polygon disjoint-polygons overlapping-polygons)
density_names=(low medium high)
intensity_names=(low medium high)
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

table='## [Custom] Section 1: Regions'
for i in "${!region_cases[@]}"; do
  case="${region_cases[$i]}"
  case_title="${case//-/ }"
  case_title="${case_title^}"
  table+=$'\n\n'"### Case $((i + 1)): ${case_title}"
  table+=$'\n\n| Density \\ Intensity | Low | Medium | High |'
  table+=$'\n| --- | --- | --- | --- |'
  for density in "${density_names[@]}"; do
    row="| ${density^} |"
    for intensity in "${intensity_names[@]}"; do
      name="regions-${case}-${density}-${intensity}"
      url="${preview_urls[$name]:-}"
      if [[ -n "${url}" ]]; then
        cell="<img src=\"${url}\" width=\"180\" alt=\"${density} density, ${intensity} intensity\">"
      else
        cell="Preview unavailable"
      fi
      row+=" ${cell} |"
    done
    table+=$'\n'"${row}"
  done
done

table+=$'\n\n## [Default] Section 2: Original'
table+=$'\n\n| PDF output | Inline preview |'
table+=$'\n| --- | --- |'
default_count=0
for name in florilegium florilegium-grow showcase spread specimen specimen-geometric ornaments; do
  url="${preview_urls[default-${name}]:-}"
  if [[ -n "${url}" ]]; then
    table+=$'\n'"| ${name}.pdf | <img src=\"${url}\" width=\"240\" alt=\"${name}\"> |"
    default_count=$((default_count + 1))
  fi
done
if (( default_count == 0 )); then
  table+=$'\n| No default PDF previews were produced. | — |'
fi

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

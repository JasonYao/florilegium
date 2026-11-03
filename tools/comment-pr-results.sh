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

table='| PDF output | Inline preview |'
table+=$'\n| --- | --- |'
preview_count=0
for name in florilegium florilegium-grow showcase spread specimen specimen-geometric ornaments; do
  preview="${TEST_RESULTS_DIR}/test-previews/${name}.png"
  if [[ -f "${preview}" ]]; then
    if preview_url="$(upload_attachment "${preview}")"; then
      image="![${name}](${preview_url})"
    else
      image="Preview upload failed"
    fi
    table+=$'\n'"| ${name}.pdf | ${image} |"
    preview_count=$((preview_count + 1))
  fi
done
for name in single-rectangle disjoint-rectangles overlapping-rectangles \
            single-polygon disjoint-polygons overlapping-polygons; do
  preview="${TEST_RESULTS_DIR}/test-previews/regions-${name}.png"
  if [[ -f "${preview}" ]]; then
    if preview_url="$(upload_attachment "${preview}")"; then
      image="![regions-${name}](${preview_url})"
    else
      image="Preview upload failed"
    fi
    table+=$'\n'"| regions.pdf — ${name} | ${image} |"
    preview_count=$((preview_count + 1))
  fi
done
if (( preview_count == 0 )); then
  table+=$'\n| No PDF previews were produced. | — |'
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

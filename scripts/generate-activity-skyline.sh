#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${GITHUB_TOKEN:-}" ]]; then
  echo "GITHUB_TOKEN is required" >&2
  exit 1
fi

OWNER="${GITHUB_REPOSITORY_OWNER:-${OWNER:-}}"
if [[ -z "$OWNER" ]]; then
  echo "GITHUB_REPOSITORY_OWNER (or OWNER) must be provided" >&2
  exit 1
fi

README_PATH=".github/profile/README.md"
if [[ ! -f "$README_PATH" ]]; then
  echo "README not found at $README_PATH" >&2
  exit 1
fi

API_URL="https://api.github.com"
AUTH_HEADER="Authorization: Bearer $GITHUB_TOKEN"
API_VERSION_HEADER="X-GitHub-Api-Version: 2022-11-28"
ACCEPT_DEFAULT="Accept: application/vnd.github+json"
ACCEPT_COMMITS="Accept: application/vnd.github.cloak-preview+json"

urlencode() {
  local raw="$1"
  printf '%s' "$raw" | jq -sRr @uri
}

search_count() {
  local path="$1"
  local accept_header="$2"
  local response
  response=$(curl -fsSL \
    -H "$AUTH_HEADER" \
    -H "$accept_header" \
    -H "$API_VERSION_HEADER" \
    "$API_URL$path")
  printf '%s' "$response" | jq -r '.total_count'
}

block_bar() {
  local count="$1"
  local unit=2
  local blocks=$(( (count + unit - 1) / unit ))
  if (( blocks > 0 )); then
    local bar=""
    for _ in $(seq 1 "$blocks"); do
      bar+="▇"
    done
    printf '%s' "$bar"
  else
    printf '-'
  fi
}

months_output=""

current_month_start=$(date -u +%Y-%m-01)

for offset in $(seq 11 -1 0); do
  month_start=$(date -u -d "$current_month_start -$offset month" +%Y-%m-01)
  month_end=$(date -u -d "$month_start +1 month -1 day" +%Y-%m-%d)
  month_label=$(date -u -d "$month_start" +%Y-%m)

  commit_query=$(urlencode "author:$OWNER author-date:$month_start..$month_end")
  pr_query=$(urlencode "author:$OWNER type:pr created:$month_start..$month_end")
  issue_query=$(urlencode "author:$OWNER type:issue created:$month_start..$month_end")

  commit_count=$(search_count "/search/commits?q=$commit_query&per_page=1" "$ACCEPT_COMMITS") || commit_count=0
  pr_count=$(search_count "/search/issues?q=$pr_query&per_page=1" "$ACCEPT_DEFAULT") || pr_count=0
  issue_count=$(search_count "/search/issues?q=$issue_query&per_page=1" "$ACCEPT_DEFAULT") || issue_count=0

  months_output+=$'\n'
  months_output+=$"📅 $month_label\n"
  months_output+="$(block_bar "$commit_count") $commit_count commits\n"
  months_output+="$(block_bar "$pr_count") $pr_count PRs\n"
  months_output+="$(block_bar "$issue_count") $issue_count issues\n"
  months_output+=$'\n'

done

months_output="${months_output%$'\n'}"

replacement=$'<!-- skyline:start -->\n\n'
replacement+="${months_output}"$'\n\n'
replacement+=$'<!-- skyline:end -->'

escaped_replacement=$(printf '%s' "$replacement" | sed 's/[&/]/\\&/g')

perl -0pi -e "s/<!-- skyline:start -->.*?<!-- skyline:end -->/${escaped_replacement}/s" "$README_PATH"

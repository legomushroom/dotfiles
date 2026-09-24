#!/usr/bin/env bash
# Poll for new review activity on one or more PRs, then report every place a
# finding can hide, plus CI and mergeability.
#
# Usage: watch-reviews.sh <owner/repo> <pr> [pr...]
#   REVIEWER   reviewer login to track   (default copilot-pull-request-reviewer[bot])
#   MINUTES    how long to poll          (default 25)
#   INTERVAL   seconds between polls     (default 60)
#
# Exits as soon as any PR gains a review or an unresolved thread, so the caller
# can act. Prints the report either way.
set -uo pipefail

export GH_PAGER=cat NO_COLOR=1

REPO=${1:?usage: watch-reviews.sh <owner/repo> <pr> [pr...]}
shift
PRS=("$@")
[ ${#PRS[@]} -gt 0 ] || { echo "usage: watch-reviews.sh <owner/repo> <pr> [pr...]" >&2; exit 2; }

REVIEWER=${REVIEWER:-'copilot-pull-request-reviewer[bot]'}
MINUTES=${MINUTES:-25}
INTERVAL=${INTERVAL:-60}
OWNER=${REPO%%/*}
NAME=${REPO##*/}

# --paginate matters: without it this saturates at the first page of 30 and a
# busy PR can never appear to gain a review.
review_count() {
  gh api "repos/$REPO/pulls/$1/reviews" --paginate --jq '.[].id' 2>/dev/null | wc -l | tr -d ' '
}

unresolved_count() {
  gh api graphql -f query="
    query(\$owner:String!,\$name:String!,\$pr:Int!){
      repository(owner:\$owner,name:\$name){
        pullRequest(number:\$pr){
          reviewThreads(last:100){nodes{isResolved}}}}}" \
    -f owner="$OWNER" -f name="$NAME" -F pr="$1" \
    --jq '[.data.repository.pullRequest.reviewThreads.nodes[]|select(.isResolved==false)]|length' 2>/dev/null
}

# Indexed arrays, parallel to PRS: macOS ships bash 3.2, which has no
# associative arrays, and a silently empty baseline makes every poll look like
# new activity.
BASE_REVIEWS=()
BASE_THREADS=()
for pr in "${PRS[@]}"; do
  BASE_REVIEWS+=("$(review_count "$pr")")
  BASE_THREADS+=("$(unresolved_count "$pr")")
done

printf 'baseline:'
for i in "${!PRS[@]}"; do
  printf ' %s=%s/%s' "${PRS[$i]}" "${BASE_REVIEWS[$i]}" "${BASE_THREADS[$i]}"
done
printf ' (reviews/unresolved)\n'

for ((minute = 1; minute <= MINUTES; minute++)); do
  sleep "$INTERVAL"
  changed=""
  line="minute $minute:"
  for i in "${!PRS[@]}"; do
    pr=${PRS[$i]}
    reviews=$(review_count "$pr")
    threads=$(unresolved_count "$pr")
    line="$line | $pr reviews=$reviews unresolved=$threads"
    if [ "${reviews:-0}" -gt "${BASE_REVIEWS[$i]:-0}" ] || [ "${threads:-0}" -gt "${BASE_THREADS[$i]:-0}" ]; then
      changed="yes"
    fi
  done
  echo "$line"
  if [ -n "$changed" ]; then
    echo "NEW_ACTIVITY after $minute minute(s)"
    break
  fi
done

for pr in "${PRS[@]}"; do
  echo
  echo "########## PR $pr ##########"

  head=$(gh pr view "$pr" --repo "$REPO" --json headRefOid --jq '.headRefOid[0:8]')
  # Newest review across all pages, not the last of page one.
  latest=$(gh api "repos/$REPO/pulls/$pr/reviews" --paginate \
    --jq ".[]|select(.user.login==\"$REVIEWER\")|\"\(.id) \(.commit_id[0:8]) \(.state)\"" | tail -1)
  rid=${latest%% *}
  rest=${latest#* }
  seen=${rest%% *}
  state=${rest##* }

  echo "head=$head lastReviewed=${seen:-none} state=${state:-none} review=${rid:-none}"
  if [ -n "$seen" ] && [ "$head" = "$seen" ]; then
    echo "REVIEW_COVERS_HEAD"
  else
    echo "REVIEW_IS_STALE (its findings may already be fixed; check the threads)"
  fi

  # The body carries "Previously missed" findings that create no thread.
  echo "--- review body ---"
  if [ -n "$rid" ]; then
    gh api "repos/$REPO/pulls/$pr/reviews/$rid" --jq '.body' \
      | sed 's/<[^>]*>//g' | sed 's/&nbsp;/ /g' | grep -vE '^[[:space:]]*$'
  fi

  echo "--- open threads ---"
  gh api graphql -f query="
    query(\$owner:String!,\$name:String!,\$pr:Int!){
      repository(owner:\$owner,name:\$name){
        pullRequest(number:\$pr){
          reviewThreads(last:100){nodes{isResolved comments(first:1){nodes{databaseId path line body}}}}}}}" \
    -f owner="$OWNER" -f name="$NAME" -F pr="$pr" \
    --jq '.data.repository.pullRequest.reviewThreads.nodes[]
          |select(.isResolved==false)|.comments.nodes[0]
          |"--- THREAD \(.databaseId) \(.path):\(.line)\n\(.body)\n"'

  echo "--- conflicts and CI ---"
  gh pr view "$pr" --repo "$REPO" --json mergeable,mergeStateStatus \
    --jq '"mergeable=\(.mergeable) state=\(.mergeStateStatus)"'
  gh pr checks "$pr" --repo "$REPO" 2>&1 \
    | awk -F'\t' '{c[$2]++} END {printf "checks pass=%d fail=%d pending=%d\n", c["pass"], c["fail"], c["pending"]}'
  gh pr checks "$pr" --repo "$REPO" 2>&1 \
    | awk -F'\t' '$2=="fail" {print "FAILING: "$1"\t"$4}'
done

echo
echo CYCLE_COMPLETE

#!/usr/bin/env bash
# Reply to a review thread from a file, then resolve it. The body goes through a
# file because shell quoting mangles multi-line markdown.
#
# Usage: reply-and-resolve.sh <owner/repo> <pr> <comment-id> <body-file>
#        reply-and-resolve.sh <owner/repo> <pr> --resolve-all
#
# <comment-id> is the databaseId of the thread's first comment, which is what
# watch-reviews.sh prints as "--- THREAD <id> ...".
set -euo pipefail

export GH_PAGER=cat NO_COLOR=1

REPO=${1:?usage: reply-and-resolve.sh <owner/repo> <pr> <comment-id> <body-file>}
PR=${2:?missing pr number}
OWNER=${REPO%%/*}
NAME=${REPO##*/}

resolve_thread() {
  gh api graphql -f query='mutation($t:ID!){resolveReviewThread(input:{threadId:$t}){thread{isResolved}}}' \
    -f t="$1" --jq '.data.resolveReviewThread.thread.isResolved'
}

# Thread node id for a given first-comment databaseId, or every unresolved one.
thread_ids() {
  local want=${1:-}
  gh api graphql -f query="
    query(\$owner:String!,\$name:String!,\$pr:Int!){
      repository(owner:\$owner,name:\$name){
        pullRequest(number:\$pr){
          reviewThreads(last:100){nodes{id isResolved comments(first:1){nodes{databaseId}}}}}}}" \
    -f owner="$OWNER" -f name="$NAME" -F pr="$PR" \
    --jq ".data.repository.pullRequest.reviewThreads.nodes[]
          |select(.isResolved==false)
          |select(${want:+.comments.nodes[0].databaseId==$want}${want:+ and }true)
          |.id"
}

if [ "${3:-}" = "--resolve-all" ]; then
  thread_ids | while read -r tid; do resolve_thread "$tid"; done
  exit 0
fi

COMMENT_ID=${3:?missing comment id}
BODY_FILE=${4:?missing body file}
[ -f "$BODY_FILE" ] || { echo "no such body file: $BODY_FILE" >&2; exit 2; }

payload=$(mktemp)
trap 'rm -f "$payload"' EXIT
jq -Rs '{body:.}' "$BODY_FILE" > "$payload"

gh api -X POST "repos/$REPO/pulls/$PR/comments/$COMMENT_ID/replies" --input "$payload" --jq '.id'

tid=$(thread_ids "$COMMENT_ID" | head -1)
if [ -n "$tid" ]; then
  resolve_thread "$tid"
else
  echo "no unresolved thread found for comment $COMMENT_ID" >&2
fi

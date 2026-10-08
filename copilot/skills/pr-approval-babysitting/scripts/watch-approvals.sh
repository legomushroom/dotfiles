#!/usr/bin/env bash
# Keep your PR approvals alive until the PR merges. When a push, rebase or base
# change dismisses or outdates your approval, re-approve the new head on your
# behalf, unless what changed since you approved needs your eyes (see guard).
# Also alerts when a PR you approved gets merge conflicts, and when they clear.
#
# Usage: watch-approvals.sh [--mine] [<pr>...]
#   <pr>    owner/repo#123 or https://github.com/owner/repo/pull/123
#   --mine  also watch every open PR you have reviewed, re-discovered each poll
#
#   INTERVAL       seconds between polls                     (default 180)
#   HOURS          stop after this many hours, 0 = never     (default 0)
#   ONCE=1         one pass, then exit
#   DRY_RUN=1      decide and log, never approve (uses log.dry / status.dry)
#   SENSITIVE      ERE; a change to a matching path always holds
#   ALLOW_AUTHORS  comma-separated logins trusted to push to any PR
#   NOTIFY=0       no notifications at all (dry runs never notify)
#   SLACK_WEBHOOK_URL  Slack webhook taking {"text": ...}; else read from
#                  ~/.config/pr-approval-babysitting/slack-webhook-url
#   STATE_DIR      log and state  (default ~/.local/state/pr-approval-babysitting)
#
# Holds and conflict changes notify on the desktop and, when a webhook is
# configured, in Slack. On macOS, terminal-notifier (when installed) makes a
# click open the PR; otherwise osascript, or notify-send on Linux.
#
# Explicit PRs are dropped once merged or closed, and with only explicit PRs
# the script exits when all are done. With --mine it runs until HOURS or killed.
# Only status changes are logged, so a quiet log means nothing happened.
set -uo pipefail

export GH_PAGER=cat NO_COLOR=1 LC_ALL=C

INTERVAL=${INTERVAL:-180}
HOURS=${HOURS:-0}
ONCE=${ONCE:-}
DRY_RUN=${DRY_RUN:-}
SENSITIVE=${SENSITIVE:-'^\.github/(workflows|actions)/|(^|/)CODEOWNERS$|(^|/)\.gitmodules$'}
ALLOW_AUTHORS=${ALLOW_AUTHORS:-}
NOTIFY=${NOTIFY:-1}
SLACK_WEBHOOK_URL=${SLACK_WEBHOOK_URL:-}
SLACK_WEBHOOK_FILE=${XDG_CONFIG_HOME:-$HOME/.config}/pr-approval-babysitting/slack-webhook-url
STATE_DIR=${STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/pr-approval-babysitting}
LOG_FILE=$STATE_DIR/log
STATUS_FILE=$STATE_DIR/status
ME=
QUIET_UNAPPROVED=
LOCKED=
SLEEP_PID=

PR_QUERY='query($o:String!,$r:String!,$n:Int!,$me:String!){
  repository(owner:$o,name:$r){pullRequest(number:$n){
    state isDraft headRefOid baseRefOid reviewDecision mergeable title
    author{login} assignees(first:20){nodes{login}}
    reviews(author:$me,last:100){nodes{databaseId state commit{oid}}}
    timelineItems(last:100,itemTypes:[REVIEW_DISMISSED_EVENT]){nodes{...on ReviewDismissedEvent{
      actor{login} previousReviewState dismissalMessage
      pullRequestCommit{commit{oid}} review{databaseId}}}}}}}'

# Only the GraphQL dismissal event tells a stale-push dismissal (it names the
# commit) and GitHub's own base-change messages apart from a person dismissing
# the review on purpose. REST just says DISMISSED for all of them.
#
# Fields are joined with \037, not tabs: read collapses runs of IFS whitespace,
# so an empty tab-separated field would shift every field after it.
PR_JQ='.data.repository.pullRequest as $p
  | ([$p.reviews.nodes[] | select(.state == "APPROVED" or .state == "CHANGES_REQUESTED" or .state == "DISMISSED")] | last) as $mine
  | ([$p.timelineItems.nodes[] | select($mine != null and .review.databaseId == $mine.databaseId)] | last) as $d
  | [ $p.state, ($p.isDraft | tostring), $p.headRefOid, $p.baseRefOid,
      ($p.reviewDecision // "NONE"), ($p.mergeable // "UNKNOWN"), ($p.author.login // "ghost"),
      ([$p.assignees.nodes[].login] | join(",")),
      ($mine.state // "NONE"), ($mine.commit.oid // ""),
      (if $d == null then ""
       elif $d.pullRequestCommit != null then "push"
       elif ($d.dismissalMessage == "The base branch was changed."
             or $d.dismissalMessage == "The merge-base changed after approval.") then "base-change"
       else "manual" end),
      ($d.previousReviewState // ""), ($d.actor.login // ""),
      (($p.title // "") | gsub("[\n\r\u001f]"; " ")),
      (($d.dismissalMessage // "") | gsub("[\n\r\u001f]"; " "))
    ] | join("\u001f")'

COMMITS_QUERY='query($o:String!,$r:String!,$n:Int!){
  repository(owner:$o,name:$r){pullRequest(number:$n){
    commits(last:100){nodes{commit{oid parents{totalCount} author{email user{login}}}}}}}}'

usage() { sed -n '2,/^set -uo/p' "$0" | sed '$d; s/^# \{0,1\}//'; }

log() {
  local line
  line="$(date '+%Y-%m-%d %H:%M:%S') $*"
  echo "$line"
  echo "$line" >>"$LOG_FILE"
}

pr_url() { echo "https://github.com/${1%#*}/pull/${1##*#}"; }

normalize_ref() {
  local p n
  case $1 in
    https://github.com/*/*/pull/[0-9]*)
      p=${1#https://github.com/}
      n=$(echo "$p" | cut -d/ -f4)
      echo "$(echo "$p" | cut -d/ -f1-2)#${n%%[!0-9]*}" ;;
    */*#[0-9]*) echo "$1" ;;
    *) return 1 ;;
  esac
}

slack() { # text
  local text out
  [ -n "$SLACK_WEBHOOK_URL" ] || return 0
  # Slack renders mrkdwn, so escape its three control characters or a PR title
  # could pose as a link; then escape for the JSON string.
  text=$(printf '%s' "$1" | tr '\001-\037' ' ' |
    sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/\\/\\\\/g' -e 's/"/\\"/g')
  # The webhook URL is a secret: hand it to curl through a config on stdin
  # rather than argv, where anyone on the machine could read it from ps.
  out=$(printf 'url = "%s"\n' "$SLACK_WEBHOOK_URL" |
    curl -fsS -m 15 -K - -H 'Content-Type: application/json' --data-binary "{\"text\":\"$text\"}" 2>&1) ||
    log "ERROR Slack notification failed: ${out:0:200}"
  return 0
}

notify() { # title body click-url group
  local out desktop=
  [ "$NOTIFY" = 1 ] && [ -z "$DRY_RUN" ] || return 0
  # terminal-notifier opens the URL on click; osascript notifications belong to
  # Script Editor, so clicking one opens that instead. The body carries
  # PR-controlled text, so pass it as an argument rather than splicing it into
  # the AppleScript source.
  if command -v terminal-notifier >/dev/null 2>&1; then
    if out=$(terminal-notifier -title "$1" -message "$2" -open "$3" -group "pr-approval-babysitting:$4" 2>&1); then
      desktop=1
    else
      log "ERROR terminal-notifier failed, falling back: ${out:0:200}"
    fi
  fi
  if [ -z "$desktop" ] && command -v osascript >/dev/null 2>&1; then
    osascript -e 'on run argv' -e 'display notification (item 2 of argv) with title (item 1 of argv)' -e 'end run' "$1" "$2" >/dev/null 2>&1
  elif [ -z "$desktop" ] && command -v notify-send >/dev/null 2>&1; then
    notify-send "$1" "$2" >/dev/null 2>&1
  fi
  slack "$1: $2"
}

last_status() {
  awk -F'\t' -v r="$1" '$1 == r { s = $2 } END { print s }' "$STATUS_FILE" 2>/dev/null
}

set_status() { # key status
  { awk -F'\t' -v r="$1" '$1 != r' "$STATUS_FILE" 2>/dev/null; printf '%s\t%s\n' "$1" "$2"; } >"$STATUS_FILE.$$"
  mv "$STATUS_FILE.$$" "$STATUS_FILE"
}

# Conflicts are tracked apart from the approval status, since a PR can be both
# approved and conflicting. GitHub computes mergeability lazily and answers
# UNKNOWN until it has, which is no news either way.
track_conflict() { # ref mergeable title
  local key="$1!conflict" last
  case $2 in CONFLICTING | MERGEABLE) ;; *) return 0 ;; esac
  last=$(last_status "$key")
  [ "$last" = "$2" ] && return 0
  set_status "$key" "$2"
  if [ "$2" = CONFLICTING ]; then
    log "CONFLICT $(pr_url "$1") has merge conflicts: $3"
    notify "Merge conflict" "$3 $(pr_url "$1")" "$(pr_url "$1")" "conflict:$1"
  elif [ -n "$last" ]; then
    log "RESOLVED $(pr_url "$1") merge conflicts are resolved: $3"
    notify "Merge conflict resolved" "$3 $(pr_url "$1")" "$(pr_url "$1")" "conflict:$1"
  fi
  return 0
}

# Record a PR's status and log it only when it changes.
report() { # ref status message
  local ref=$1 status=$2 msg=$3 last url
  last=$(last_status "$ref")
  [ "$last" = "$status" ] && return 0
  set_status "$ref" "$status"
  # Our own approval landing is not news; neither is a discovered PR you only
  # commented on.
  [ "$last" = "APPROVED:${status#VALID:}" ] && return 0
  [ -n "$QUIET_UNAPPROVED" ] && [ "$status" = WAIT:unapproved ] && return 0
  log "${status%%:*} $(pr_url "$ref") $msg"
  case $status in
    HOLD*)
      # A hold ends with the link to exactly what changed since the approval,
      # which is what a click should open; the PR itself otherwise.
      url=${msg##* review }
      case $url in "$(pr_url "$ref")/files/"*) ;; *) url=$(pr_url "$ref") ;; esac
      notify "PR approval held" "$ref: $msg" "$url" "hold:$ref" ;;
  esac
  return 0
}

# A PR's own change as of <commit>: its diff from the merge-base with the base
# branch, so whatever a merge or rebase brought in from the base cancels out.
# Hunk line numbers are dropped so a merge that only shifts lines is not a
# change; context lines are kept so moving the same added line elsewhere is.
# Prints "<path>\t<signature>" per file, or TRUNCATED once GitHub stops listing
# files and the result can no longer be trusted.
pr_diff() { # repo base commit
  gh api "repos/$1/compare/$2...$3" --jq '
    if (.files | length) >= 300 then "TRUNCATED"
    else .files[] | "\(.filename)\t\(.status):\(if .patch then (.patch | gsub("(?m)^@@ -[0-9,]+ \\+[0-9,]+ @@"; "@@")) else "blob:" + .sha end | @json)"
    end'
}

# Decide whether what changed since your approval can be re-approved unseen.
# Prints "OK <why>" or "HOLD <why>".
guard() { # repo pr base approved head author assignees pusher
  local repo=$1 n=$2 base=$3 approved=$4 head=$5 author=$6 assignees=$7 pusher=$8
  local old new changed hits allowed commits foreign

  old=$(pr_diff "$repo" "$base" "$approved" 2>&1) || { echo "HOLD cannot diff your approved commit: ${old:0:200}"; return; }
  new=$(pr_diff "$repo" "$base" "$head" 2>&1) || { echo "HOLD cannot diff the head: ${new:0:200}"; return; }
  if [ "$old" = TRUNCATED ] || [ "$new" = TRUNCATED ]; then
    echo "HOLD the diff is over 300 files, too large to check"
    return
  fi

  changed=$(comm -3 <(printf '%s\n' "$old" | sort) <(printf '%s\n' "$new" | sort) |
    awk -F'\t' '{ print ($1 == "" ? $2 : $1) }' | sort -u | grep -v '^$')
  if [ -z "$changed" ]; then
    echo "OK the PR's own diff is unchanged (merge or rebase only)"
    return
  fi

  hits=$(printf '%s\n' "$changed" | grep -E "$SENSITIVE" | paste -sd, -)
  if [ -n "$hits" ]; then
    echo "HOLD sensitive paths changed: $hits"
    return
  fi

  allowed=",$author,$ME,$assignees,${ALLOW_AUTHORS// /},"
  # Copilot coding agent opens PRs as copilot-swe-agent but commits as Copilot.
  [ "$author" = copilot-swe-agent ] && allowed="${allowed}Copilot,"

  # The pusher is what GitHub vouches for; a commit author is self-asserted.
  if [ -n "$pusher" ] && [[ $allowed != *",$pusher,"* ]]; then
    echo "HOLD pushed by $pusher, not the PR's author or assignees"
    return
  fi

  commits=$(gh api graphql -f query="$COMMITS_QUERY" -f o="${repo%/*}" -f r="${repo#*/}" -F n="$n" \
    --jq '.data.repository.pullRequest.commits.nodes[].commit
          | "\(.oid) \(.parents.totalCount) \(.author.user.login // ("unlinked:" + (.author.email // "unknown")))"' 2>&1) ||
    { echo "HOLD cannot list commits: ${commits:0:200}"; return; }
  # Commits after the approved one, or all of them once a rebase has dropped
  # it. Merges are skipped: what they bring in is already in the diff above.
  foreign=$(printf '%s\n' "$commits" | awk -v a="$approved" -v ok="$allowed" '
    { line[NR] = $0; if ($1 == a) start = NR }
    END { for (i = start + 1; i <= NR; i++) { split(line[i], f, " "); if (f[2] == 1 && index(ok, "," f[3] ",") == 0) print f[3] } }' |
    sort -u | paste -sd, -)
  if [ -n "$foreign" ]; then
    echo "HOLD commits authored by $foreign"
    return
  fi

  echo "OK $(printf '%s\n' "$changed" | wc -l | tr -d ' ') file(s) changed, none sensitive: $(printf '%s\n' "$changed" | head -5 | paste -sd, -)"
}

cleanup() {
  [ -n "$SLEEP_PID" ] && kill "$SLEEP_PID" 2>/dev/null
  [ -n "$LOCKED" ] && rm -rf "$STATE_DIR/mine.lock"
  return 0
}

approve() { # repo pr head
  gh api -X POST "repos/$1/pulls/$2/reviews" -f event=APPROVE -f commit_id="$3" --jq .state 2>&1
}

# Returns 10 once the PR is merged or closed, so the caller can drop it.
evaluate() { # ref
  local ref=$1 repo=${1%#*} n=${1##*#} info
  local state draft head base decision mergeable author assignees mine approved dkind dprev pusher title dmsg
  local why verdict result

  info=$(gh api graphql -f query="$PR_QUERY" -f o="${repo%/*}" -f r="${repo#*/}" -F n="$n" -f me="$ME" --jq "$PR_JQ" 2>&1) ||
    { report "$ref" ERROR "${info//$'\n'/ }"; return 0; }
  IFS=$'\037' read -r state draft head base decision mergeable author assignees mine approved dkind dprev pusher title dmsg <<<"$info"

  case $state in
    MERGED) report "$ref" DONE "merged"; return 10 ;;
    CLOSED) report "$ref" DONE "closed without merging"; return 10 ;;
  esac
  if [ "$author" = "$ME" ]; then
    report "$ref" SKIP:own "your own PR"
    return 0
  fi
  # Conflicts only matter on PRs you approved, including ones whose approval
  # was dismissed since, not ones you merely commented on or blocked.
  if [ "$mine" = APPROVED ] || { [ "$mine" = DISMISSED ] && [ "$dprev" = APPROVED ]; }; then
    track_conflict "$ref" "$mergeable" "$title"
  fi

  case $mine in
    NONE)
      report "$ref" WAIT:unapproved "you have not approved it"
      return 0 ;;
    CHANGES_REQUESTED)
      report "$ref" SKIP:changes "your latest review requests changes"
      return 0 ;;
    APPROVED)
      if [ "$approved" = "$head" ]; then
        report "$ref" "VALID:$head" "your approval covers ${head:0:8}"
        return 0
      fi
      # Without a rule that dismisses or outdates it, your approval keeps
      # counting after a push. Only act when the PR is waiting on a review.
      case $decision in
        APPROVED | NONE)
          report "$ref" "VALID:$head" "your approval on ${approved:0:8} still counts (review decision: $decision)"
          return 0 ;;
      esac
      why="your approval on ${approved:0:8} does not count for ${head:0:8} (review decision: $decision)"
      pusher= ;;
    DISMISSED)
      case $dkind in
        "")
          report "$ref" "HOLD:dismissed:$approved" "your approval on ${approved:0:8} was dismissed and the dismissal is not in the timeline"
          return 0 ;;
        manual)
          report "$ref" "HOLD:dismissed:$approved" "$pusher dismissed your review by hand: $dmsg"
          return 0 ;;
      esac
      if [ "$dprev" != APPROVED ]; then
        report "$ref" SKIP:changes "your dismissed review was not an approval"
        return 0
      fi
      why="a $dkind by $pusher dismissed your approval on ${approved:0:8}" ;;
    *)
      report "$ref" ERROR "unexpected review state $mine"
      return 0 ;;
  esac

  if [ "$draft" = true ]; then
    report "$ref" WAIT:draft "back in draft; re-approving once it is ready"
    return 0
  fi
  case $(last_status "$ref") in "HOLD:$head" | "APPROVED:$head") return 0 ;; esac

  verdict=$(guard "$repo" "$n" "$base" "$approved" "$head" "$author" "$assignees" "$pusher")
  case $verdict in
    HOLD*)
      report "$ref" "HOLD:$head" "$why; ${verdict#HOLD }; review $(pr_url "$ref")/files/$approved..$head"
      return 0 ;;
  esac
  if [ -n "$DRY_RUN" ]; then
    report "$ref" "WOULD_APPROVE:$head" "$why; ${verdict#OK }"
    return 0
  fi
  # Pinned to the head that was checked: a push landing meanwhile leaves this
  # approval stale for the next poll instead of approving unseen code.
  result=$(approve "$repo" "$n" "$head")
  if [ "$result" = APPROVED ]; then
    report "$ref" "APPROVED:$head" "re-approved ${head:0:8}: $why; ${verdict#OK }"
  else
    report "$ref" ERROR "approving ${head:0:8} failed: ${result//$'\n'/ }"
  fi
  return 0
}

main() {
  local mine= a ref url urls rc pid deadline=0
  local refs=() keep=()

  for a in "$@"; do
    case $a in
      --mine) mine=1 ;;
      -h | --help) usage; return 0 ;;
      *)
        ref=$(normalize_ref "$a") || { echo "not a PR reference: $a" >&2; return 2; }
        refs+=("$ref") ;;
    esac
  done
  if [ -z "$mine" ] && [ ${#refs[@]} -eq 0 ]; then
    usage >&2
    return 2
  fi

  mkdir -p "$STATE_DIR"
  if [ -n "$DRY_RUN" ]; then
    LOG_FILE=$LOG_FILE.dry
    STATUS_FILE=$STATUS_FILE.dry
    : >"$STATUS_FILE"
  fi
  ME=$(gh api user --jq .login) || { echo "gh is not authenticated" >&2; return 1; }
  if [ -z "$SLACK_WEBHOOK_URL" ] && [ -r "$SLACK_WEBHOOK_FILE" ]; then
    SLACK_WEBHOOK_URL=$(head -1 "$SLACK_WEBHOOK_FILE" | tr -d '[:space:]')
  fi

  # Two --mine watchers would race each other to approve the same head.
  if [ -n "$mine" ] && [ -z "$DRY_RUN" ]; then
    if ! mkdir "$STATE_DIR/mine.lock" 2>/dev/null; then
      pid=$(cat "$STATE_DIR/mine.lock/pid" 2>/dev/null)
      if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        echo "a --mine watcher is already running (pid $pid)" >&2
        return 1
      fi
      rm -rf "$STATE_DIR/mine.lock"
      mkdir "$STATE_DIR/mine.lock"
    fi
    echo $$ >"$STATE_DIR/mine.lock/pid"
    LOCKED=1
  fi
  # Exit through the EXIT trap on a signal; bash skips it when killed outright.
  trap cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM

  [ "$HOURS" -gt 0 ] && deadline=$(($(date +%s) + HOURS * 3600))
  local channels=none
  if [ "$NOTIFY" = 1 ] && [ -z "$DRY_RUN" ]; then
    channels=desktop
    [ -n "$SLACK_WEBHOOK_URL" ] && channels="desktop+slack"
  fi
  log "START as $ME${mine:+, every open PR you reviewed}${refs[0]+, ${refs[*]}}${DRY_RUN:+ (dry run)}; polling every ${INTERVAL}s; notifying: $channels"

  while :; do
    keep=()
    for ref in ${refs[@]+"${refs[@]}"}; do
      evaluate "$ref"
      rc=$?
      [ "$rc" -eq 10 ] || keep+=("$ref")
    done
    refs=(${keep[@]+"${keep[@]}"})

    if [ -n "$mine" ]; then
      if urls=$(gh search prs --reviewed-by=@me --state=open --limit 200 --json url --jq '.[].url' -- -author:@me 2>&1); then
        QUIET_UNAPPROVED=1
        for url in $urls; do
          ref=$(normalize_ref "$url") || continue
          case " ${refs[*]-} " in *" $ref "*) continue ;; esac
          evaluate "$ref"
        done
        QUIET_UNAPPROVED=
      else
        log "ERROR search failed: ${urls//$'\n'/ }"
      fi
    fi

    if [ -z "$mine" ] && [ ${#refs[@]} -eq 0 ]; then
      log "STOP every watched PR is merged or closed"
      return 0
    fi
    [ -n "$ONCE" ] && return 0
    if [ "$deadline" -gt 0 ] && [ "$(date +%s)" -ge "$deadline" ]; then
      log "STOP ran for $HOURS hour(s)"
      return 0
    fi
    # Backgrounded so a signal is handled now, not after the sleep finishes.
    sleep "$INTERVAL" &
    SLEEP_PID=$!
    wait "$SLEEP_PID"
    SLEEP_PID=
  done
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi

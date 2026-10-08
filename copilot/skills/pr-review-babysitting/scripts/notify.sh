#!/usr/bin/env bash
# Tell the user a PR's review loop has stopped: a desktop notification that
# opens the PR when clicked (terminal-notifier; plain osascript or notify-send
# otherwise) and, when a webhook is configured, Slack.
#
# Usage: notify.sh <owner/repo> <pr> <done|stopped|needs-you> <summary>
#   NOTIFY=0           send nothing
#   SLACK_WEBHOOK_URL  Slack webhook taking {"text": ...}; else the first line of
#                      ~/.config/pr-review-babysitting/slack-webhook-url, then of
#                      ~/.config/pr-approval-babysitting/slack-webhook-url, so
#                      one setup covers both skills
#
# Never fails the caller: a notification that cannot be sent is reported on
# stderr and the exit status stays 0, so the loop's own report still happens.
set -uo pipefail

usage="usage: notify.sh <owner/repo> <pr> <done|stopped|needs-you> <summary>"
[ $# -eq 4 ] || { echo "$usage" >&2; exit 2; }
REPO=$1 PR=$2 OUTCOME=$3 SUMMARY=$4

case $OUTCOME in
  done) title="PR review done" ;;
  stopped) title="PR review stopped" ;;
  needs-you) title="PR review needs you" ;;
  *) echo "$usage" >&2; exit 2 ;;
esac

[ "${NOTIFY:-1}" = 1 ] || { echo "NOTIFY=0, nothing sent"; exit 0; }

body="$REPO#$PR: $SUMMARY"
url="https://github.com/$REPO/pull/$PR"
sent=""

# terminal-notifier opens the PR on click. osascript notifications belong to
# Script Editor, so clicking one opens that instead, but it needs no install
# and still gets through when terminal-notifier's notifications are turned off.
# The summary can carry PR text, so it goes in as an argument rather than being
# spliced into the AppleScript source.
if command -v terminal-notifier >/dev/null 2>&1; then
  if out=$(terminal-notifier -title "$title" -message "$body" -open "$url" \
    -group "pr-review-babysitting:$REPO#$PR" 2>&1); then
    sent=desktop
  else
    echo "terminal-notifier failed, falling back: $out" >&2
  fi
fi
if [ -z "$sent" ] && command -v osascript >/dev/null 2>&1; then
  if osascript -e 'on run argv' -e 'display notification (item 2 of argv) with title (item 1 of argv)' -e 'end run' \
    "$title" "$body" >/dev/null 2>&1; then
    sent=desktop
  else
    echo "desktop notification failed" >&2
  fi
elif [ -z "$sent" ] && command -v notify-send >/dev/null 2>&1; then
  if notify-send "$title" "$body" >/dev/null 2>&1; then sent=desktop; else echo "desktop notification failed" >&2; fi
fi

webhook=${SLACK_WEBHOOK_URL:-}
config=${XDG_CONFIG_HOME:-$HOME/.config}
for f in "$config/pr-review-babysitting/slack-webhook-url" "$config/pr-approval-babysitting/slack-webhook-url"; do
  if [ -z "$webhook" ] && [ -r "$f" ]; then
    webhook=$(head -1 "$f" | tr -d '[:space:]')
  fi
done

if [ -n "$webhook" ]; then
  # Slack renders mrkdwn, so escape its three control characters or a PR title
  # could pose as a link; then escape for the JSON string.
  text=$(printf '%s: %s %s' "$title" "$body" "$url" | tr '\001-\037' ' ' |
    sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/\\/\\\\/g' -e 's/"/\\"/g')
  # The webhook URL is a secret: hand it to curl through a config on stdin
  # rather than argv, where anyone on the machine could read it from ps.
  if out=$(printf 'url = "%s"\n' "$webhook" |
    curl -fsS -m 15 -K - -H 'Content-Type: application/json' --data-binary "{\"text\":\"$text\"}" 2>&1); then
    sent=${sent:+$sent+}slack
  else
    echo "Slack notification failed: ${out:0:200}" >&2
  fi
fi

echo "NOTIFIED via ${sent:-nothing}"
exit 0

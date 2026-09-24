---
name: pr-review-babysitting
description: 'Drive automated PR review to completion: wait for a reviewer bot, read findings from every place they hide, verify each claim before fixing, fix, reply, resolve, re-request, repeat until clean. Also watches CI and merge conflicts each cycle. USE FOR: babysitting Copilot/bot review on one PR or a whole PR stack; "address the review feedback in a loop"; "wait for review and fix what comes back"; long unattended review-remediation cycles. DO NOT USE FOR: a single already-known review comment (just fix it); human code review conversations needing judgement calls; writing the PR itself.'
argument-hint: '<owner/repo> <pr> [pr...] — base-to-head order for a stack'
---

# PR review babysitting

Run automated review to completion without a human in the loop. One cycle is:
wait for a review → read findings → verify each claim → fix → reply → resolve →
re-request → wait again. Stop when a PR reports no findings and no open threads.

The work is mostly discipline. The failure modes below are not hypothetical;
each one silently produced a wrong "nothing to do" in practice.

## The loop

1. **Snapshot baselines.** Review counts per PR, paginated. See pitfall 1.
2. **Watch** with [watch-reviews.sh](./scripts/watch-reviews.sh). It breaks early
   on a new review or a new unresolved thread and then prints, per PR: head vs
   last-reviewed commit, the full review body, open threads, mergeability, CI
   counts and any failing check URLs.
3. **Read all three places a finding hides** (pitfall 2).
4. **Verify before fixing** (pitfall 4). Reviewer bots are often right and
   sometimes wrong; both need evidence.
5. **Fix at the right PR in the stack** (pitfall 6), run the full test suite and
   the linter, compare against a known warning baseline.
6. **Reply and resolve** each thread with
   [reply-and-resolve.sh](./scripts/reply-and-resolve.sh) (pitfall 7).
7. **Re-request review**, re-snapshot baselines, go to 2.

```bash
gh api -X POST "repos/$REPO/pulls/$PR/requested_reviewers" \
  -f "reviewers[]=copilot-pull-request-reviewer[bot]"
```

## Stop condition

A PR is done when its latest review covers the current head, reports no
findings, and has zero unresolved threads. For the tip of a stack, prefer two
consecutive clean rounds, since a fix on a lower PR can reopen the tip. Stop
re-requesting once clean rather than burning cycles.

Tell the user what was found and fixed. Do not post change-summary comments on
the PR itself.

## Pitfalls

### 1. Paginate every review query

`gh api repos/O/R/pulls/N/reviews` returns **only the first 30**. Two distinct
bugs come from this:

- Counting reviews to detect new ones saturates at 30, so a PR past 30 reviews
  can never appear to gain one. The watcher goes blind permanently.
- Taking `[-1]` yields the last review *on page one*, not the newest. A PR can
  report a stale review for many cycles while real findings sit unread.

Always `--paginate`, and select the newest by taking the last streamed element:

```bash
gh api "repos/$REPO/pulls/$PR/reviews" --paginate \
  --jq '.[]|select(.user.login=="copilot-pull-request-reviewer[bot]")
        |"\(.id) \(.commit_id[0:8]) \(.state)"' | tail -1
```

### 2. Findings hide in three places

| Where | How to read it |
|---|---|
| Unresolved review threads | GraphQL `reviewThreads`, filter `isResolved == false` |
| The review body's **Open** list | Each links a thread; usually also in threads |
| The review body's **"Previously missed"** section | **No thread exists.** Only visible in the body text |

"Previously missed" items produce no thread, so a PR can show zero unresolved
threads and still have real findings. Never treat an empty thread list as done
without reading the body. Equally, an empty findings list is not a stop signal
on its own — check the body for missed items too.

When the body and the threads disagree, trust the threads: the body summary can
straddle two reviews and show already-resolved items as open.

### 3. A stale review's findings may already be fixed

Compare the review's `commit_id` to the PR head. If they differ, the review
predates your last push and its findings may be ones you already addressed.
Check before redoing work. Conversely, do not treat staleness as "nothing to
do" — confirm against the threads and the current file contents.

### 4. Verify every claim against the code

Do not fix on assertion alone, and do not dismiss on intuition alone.

- **To confirm a bug exists**, write the regression test first and watch it
  fail, or temporarily disable the guard and watch the new test fail. Restore
  immediately and confirm the mutation is gone (`grep` for it).
- **To refute a claim**, produce evidence: read the dependency's source, or
  write the end-to-end test the reviewer asked for and show the real behaviour.
  Then push back in the reply rather than making a change you believe is wrong.

A test that passes both with and without the fix proves nothing. If a proposed
regression test still passes when the guard is removed, the test is wrong — this
is itself a common and legitimate finding.

**Never `git checkout -- <file>` to undo a mutation-test edit.** It discards all
uncommitted work in that file. Revert the exact string instead.

### 5. Your own fixes cause the next findings

Late cycles tend to find consequences of earlier fixes rather than original
defects. Expect it, and after changing anything load-bearing, check every other
consumer of it: docs that document it, scripts that grep for it, tests that
assert on it, equality/settlement logic that includes it.

A rename is the classic case: a demo script grepping the old event name kept
exiting zero because unrelated lines still matched, so it "passed" while
silently dropping everything it was meant to show.

### 6. Stacks: fix low, rebase up

Fix at the lowest PR that owns the code. Then, in base-to-head order:

```bash
git switch <lower> && git push --force-with-lease -q origin <lower>
git switch <upper> && git rebase <lower> && <run tests> \
  && git push --force-with-lease -q origin <upper>
```

Always `--force-with-lease`, never plain `--force`. Re-run the suite after each
rebase; a lower fix can change upper behaviour. Check `mergeable` and
`mergeStateStatus` every cycle — `BLOCKED` on a stacked PR is usually just
waiting on its base, while `DIRTY` is a real conflict.

### 7. Reply bodies go through files

Shell quoting mangles multi-line markdown. Write the body to a file and post it:

```bash
jq -Rs '{body:.}' reply.md > payload.json
gh api -X POST "repos/$REPO/pulls/$PR/comments/$COMMENT_ID/replies" --input payload.json
```

Keep replies short: verdict plus the one reason. The diff shows the fix; do not
restate it. Say so plainly when a finding was your own regression, and when you
disagree, say what evidence settles it.

### 8. Triage CI before assuming it is your fault

Read the failing job log before touching code. Infrastructure failures are
common and look alarming — artifact upload `ECONNRESET`, runner network errors,
flaky process/port/timing tests. Re-run the job:

```bash
gh run rerun --repo "$REPO" --job <job-id>
```

Confirm a suspected flake by running it in isolation. Only treat a failure as
real once the log shows your code failing.

### 9. Distrust the watcher itself

The tooling driving this loop reports "nothing to do", which is indistinguishable
from a broken watcher. Both pitfalls above were found only because a PR looked
quiet for suspiciously many cycles while real findings sat unread. If a PR
reports no activity for several rounds while its head keeps moving, verify the
watcher against the API by hand before believing it.

macOS ships bash 3.2, which has no associative arrays. `declare -A` fails there
with `invalid option`, leaving every baseline empty so the loop fires immediately
on the first poll and never actually waits. The scripts here use indexed arrays
for that reason; keep them bash-3.2 clean and run a short two-poll cycle against
unchanged PRs after editing to confirm the wait still happens.

## Scripts

- [watch-reviews.sh](./scripts/watch-reviews.sh) — poll for new review activity
  across any number of PRs, then report findings, CI and mergeability.
- [reply-and-resolve.sh](./scripts/reply-and-resolve.sh) — post a reply from a
  file to a review thread and resolve it.

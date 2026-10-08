---
name: pr-review-babysitting
description: 'Drive automated PR review to completion: wait for a reviewer bot, read findings from every place they hide, verify each claim before fixing, fix, reply, resolve, re-request, repeat until clean. Then, in local-review mode (on by default), have a local Claude subagent review the whole PR, fix what it finds that is in scope and blocking or should-fix, push, and go back through Copilot, until neither has anything worth fixing. Keeps fixes scoped to the PR''s goal. Also watches CI and merge conflicts each cycle. USE FOR: babysitting Copilot/bot review on one PR or a whole PR stack; "address the review feedback in a loop"; "wait for review and fix what comes back"; long unattended review-remediation cycles; "Copilot only" or "no local review" to turn the local pass off. DO NOT USE FOR: a single already-known review comment (just fix it); human code review conversations needing judgement calls; writing the PR itself.'
argument-hint: '<owner/repo> <pr> [pr...] [--no-local-review]; PRs in base-to-head order for a stack'
---

# PR review babysitting

Run automated review to completion without a human in the loop. Two reviewers, in strict priority order:

1. **Copilot**, always. One cycle is: wait for a review → read findings → verify each claim → fix → reply → resolve → re-request → wait again. Its findings always come first.
2. **Local review**, on by default. Once Copilot is clean on the current head, a local Claude subagent reviews the whole PR. What it finds that is worth fixing gets fixed and pushed, which sends the PR back through Copilot. Repeat until a local round finds nothing blocking or should-fix.

The work is mostly discipline. The failure modes below are not hypothetical;
each one silently produced a wrong "nothing to do" in practice.

## Modes

Local review is **on** unless the user turns it off: `--no-local-review` in the arguments, or asking for "Copilot only", "no local review" or "skip the local review". `--local-review` turns it back on. Say which mode is active when you start. With it off, everything about local rounds below is skipped.

## Stay on the PR's goal

Applies to every finding, from either reviewer. A PR that grows a second purpose during review is harder to review, riskier to merge, and no longer what was asked for.

Before the first cycle, record the PR's goal (title, description, linked issue), its head SHA as `START_HEAD`, and its file list (`gh pr diff N -R REPO --name-only`).

A finding is **in scope** when it is about the changed lines or a direct consequence of them: callers, tests, docs and scripts the change affects. Pre-existing problems in code the PR does not touch are out of scope unless the PR makes them reachable or worse. So are new features, refactors and "while you're here" cleanups, however good.

- In scope and verified: fix it.
- Out of scope: do not fix it. On a Copilot thread, reply that it is pre-existing or outside this PR and resolve. Either way, keep it as a follow-up for the final report.
- Before every push, read `git diff --stat $START_HEAD..HEAD`. Each file outside the original list needs a reason, namely that it consumes what changed. If review fixes start to rival the original change in size, or add behaviour the description does not mention, stop and ask the user instead of pushing.

## Findings ledger

Keep one row per finding, from either reviewer, in the session SQL database or a file in the session workspace, never in the repo: PR, source (`copilot` or `local`), round, severity, `path:line`, one-line summary, verdict (`fixed`, `declined`, `deferred` for out of scope, `nit`) and the reason. Each local round gets the settled rows so it does not re-raise them, and the final report is built from it.

## The loop

1. **Snapshot baselines.** Review counts per PR, paginated. See pitfall 1.
2. **Watch** with [watch-reviews.sh](./scripts/watch-reviews.sh). It breaks early
   on a new review or a new unresolved thread and then prints, per PR: head vs
   last-reviewed commit, the full review body, open threads, mergeability, CI
   counts and any failing check URLs.
3. **Read all three places a finding hides** (pitfall 2).
4. **Check scope, then verify** (pitfall 4). Out-of-scope findings get a reply, not a fix. Reviewer bots are often right and sometimes wrong; both need evidence.
5. **Fix at the right PR in the stack** (pitfall 6), run the full test suite and the linter, compare against a known warning baseline. Log every finding in the ledger.
6. **Reply and resolve** each thread with
   [reply-and-resolve.sh](./scripts/reply-and-resolve.sh) (pitfall 7).
7. **Push, then re-request only if nothing is in flight** (pitfall 10). Run the drift check and snapshot baselines before the push. Copilot usually starts a review by itself within a couple of minutes of a push, so run the watcher with `MINUTES=3` first, and request (command below) only if it reports `REVIEW_NOT_PENDING`, the review is still stale and no thread is unresolved. Go to 2.
8. **Copilot clean** (see stop condition): with local review on, run a [local round](#local-review-round); otherwise stop.

```bash
gh api -X POST "repos/$REPO/pulls/$PR/requested_reviewers" \
  -f "reviewers[]=copilot-pull-request-reviewer[bot]"
```

## Local review round

Start one only when Copilot is clean on the current head: its latest review covers head, the body has no findings, no thread is unresolved, `REVIEW_NOT_PENDING`, and CI has no real failures. Copilot findings always go first.

1. **Sync the checkout to the PR head**: clean worktree, `git rev-parse HEAD` equal to the PR's `headRefOid`. The reviewer reads local files, so a stale checkout reviews the wrong code.
2. **Fill the prompt** from [local-review-prompt.md](./local-review-prompt.md): the goal, repo path, `BASE_SHA` (`git merge-base origin/<base> HEAD`), `HEAD_SHA`, the head the previous local round saw, and the ledger's settled rows.
3. **Spawn the reviewer** with the task tool:
   - `agent_type: "code-review"`. If it is unavailable, use `general-purpose`. Either way the prompt's read-only line stays, since the agent may still have edit tools.
   - `model`: the most capable Claude in the tool's model list, `claude-opus-5.5` as of Oct 2026. Take the newest Opus if the list has moved on, and tell the user if you had to fall back.
   - `context_tier: "long_context"` (1M) and `reasoning_effort: "xhigh"`.
   - `mode: "sync"`. For a stack, one reviewer per PR against its own base, in parallel.
4. **Triage every finding yourself.** The reviewer's severity is input, not a verdict.
   - **blocking**: wrong or unsafe to merge. Correctness, security, data loss, broken build or tests, a regression, or the PR misses its own goal.
   - **should-fix**: a real defect with a concrete way to fail, a behaviour change with no test, docs the change made wrong.
   - **nit**: everything else. Log it, do not fix it.

   Then apply scope and verify (pitfall 4) exactly as for Copilot. A re-raise of a settled row without new evidence is not fresh.
5. **Nothing fresh, in scope, verified and at least should-fix?** The local loop is done; go to the stop condition.
6. **Otherwise fix**, run the suite and linter, and make one new commit for the round whose message says what changed and why, not "address review". Local findings have no threads, so post nothing on the PR about them.
7. **Back to Copilot** at loop step 7, which runs the drift check and pushes. When Copilot is clean again, run the next local round.

## Stop condition

A PR is Copilot-clean when its latest review covers the current head, reports no
findings, and has zero unresolved threads. For the tip of a stack, prefer two
consecutive clean rounds, since a fix on a lower PR can reopen the tip. Stop
re-requesting once clean rather than burning cycles.

- **Local review off**: stop when Copilot-clean.
- **Local review on**: stop when Copilot-clean and the latest local round produced nothing fresh that is in scope, verified, and blocking or should-fix. Nits never keep the loop going. The rest is a judgement call: a round of only re-raises, fixes that undo earlier fixes, or should-fix items you would not hold a merge for all mean stop.
- **Soft cap**: after four local rounds, stop and hand back to the user with the trend rather than start a fifth. Should-fix findings that late usually mean the loop is churning on its own fixes or the PR is doing too much.

Then tell the user, per PR: what each reviewer found and what was fixed, what was declined and why, out-of-scope follow-ups worth their own PR, how many nits were skipped, and why it stopped. Do not post change-summary comments on the PR itself.

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

### 10. A pending Copilot review is invisible to REST

While Copilot is reviewing, REST `pulls/N/requested_reviewers` and `gh pr view --json reviewRequests` both leave it out, so "nobody is requested" looks true and a re-request starts a duplicate run. Only GraphQL `reviewRequests` shows it, as a `Bot` node whose login has no `[bot]` suffix; the issue timeline also has the `review_requested` event. The watcher reads the GraphQL one and prints `REVIEW_PENDING`, `REVIEW_NOT_PENDING`, or `REVIEW_REQUEST_UNKNOWN` when the query fails. Treat unknown as pending until you have checked by hand.

## Scripts

- [watch-reviews.sh](./scripts/watch-reviews.sh) — poll for new review activity
  across any number of PRs, then report findings, pending review, CI and mergeability.
- [reply-and-resolve.sh](./scripts/reply-and-resolve.sh) — post a reply from a
  file to a review thread and resolve it.
- [local-review-prompt.md](./local-review-prompt.md): the prompt for the local review subagent.

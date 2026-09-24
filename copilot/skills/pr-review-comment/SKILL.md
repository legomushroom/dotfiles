---
name: pr-review-comment
description: Turn a raw PR review finding into a short, human-sounding, paste-able GitHub review comment anchored to a specific file and line. Use when the user asks to write, phrase, shorten, or soften a code review comment, or asks where to leave it.
user-invocable: true
---

# PR Review Comment

Convert an internal review finding into a comment the user can paste straight into
the GitHub review UI, plus the exact anchor (file and line) it belongs on.

The output is written **in the user's voice**, not yours. It is a peer talking to
another peer, not a tool reporting a defect.

## Output shape

Always emit exactly two parts, in this order:

1. **The anchor** - one line: `**Line N** (`code fragment`), `path/to/file.ts``.
   Use the line number in the **head/new** version of the file, since that is what
   the GitHub review UI expects. Quote a short code fragment so the user can
   confirm they are on the right line before pasting.

2. **The comment body** - separated by a `---` rule so it is visually obvious
   where the paste-able text begins and ends. Nothing after it.

Never add a preamble, a sign-off, or an explanation of what you did.

## Plain characters only

Write the comment body in plain ASCII. Typographic characters look
machine-generated and are the fastest way to make a comment read as not
human-written.

Never use:

- Em dash or en dash. Use a plain hyphen `-`, a comma, or two sentences.
- Arrows of any kind. Write "becomes", "then", or "leads to" instead.
- Curly or smart quotes and apostrophes. Use `'` and `"`.
- Ellipsis as a single character. Use three periods if you need one at all.
- Emoji, check marks, crosses, bullets like the middle dot, or any other
  decorative symbol.
- Non-breaking spaces or other invisible whitespace.

The one exception is a numeric range inside an anchor, where `1623-1628` with a
plain hyphen is fine. Code fences keep whatever the code actually contains;
this rule is about prose.

## Voice rules

- **Lead with an open question that already contains the finding.** "Is failing
  closed here intended, given the caller falls back on outage?" presupposes the
  consequence and invites a constraint you may not know. "What happens when X?"
  is a setup line, and it forces you to answer yourself over the next three
  sentences. The question should be answerable with "because X constrains it",
  not with a description of the code.
- **Be laconic.** Two to four sentences. The worked examples below are the
  target length, not the ceiling. Every sentence must carry new information.
- **Assume the author knows their own code.** Citing an anchor should compress a
  trace, not expand it. Naming `waker.go:247-251` is the citation; describing
  what those lines do is narration. Every sentence must tell the author
  something they cannot get by reading the anchored lines. If deleting a
  sentence leaves the finding intact, it was narration.
  - Bad: "`waker.go:247` swallows the error and degrades the route to
    `NotOwned`, which then falls through to `ResumeAppPrincipalForWake`."
  - Good: "`waker.go:247-251` falls back here specifically so wake survives
    that outage."
- **One finding per comment.** Never close with a second, weaker observation
  such as a naming, wording, or error-type nit. It dilutes the primary point and
  hands the author something easy to fix instead of the real thing. Drop it, or
  leave it as its own comment on its own line.
- **Hedge observations, not facts.** Use "it looks like" or "seems to" for
  inferred behavior; use plain statements for things you can point at in the code.
- **Cite concrete anchors** such as `file.ts:1913`, a function name, or a config
  value. Specifics are what make a comment actionable and hard to wave away.
- **No severity labels or headers** in the body. Those belong in a review
  summary, not an inline comment.
- **Strip first-person investigation.** Anything that reveals *how you know*,
  such as "I ran this locally", "my repro showed", or "I verified", must come
  out. The author cares about the behavior, not your process. Rewrite the
  evidence as an observation about the code:
  - Bad: "I ran it locally: 1024 actions pinned in the buffer."
  - Good: "It looks like the buffer just fills to `MAX_PENDING_ENVELOPES`."

## Suggesting a fix

Close with a **question**, then a small code block, when a concrete direction exists.

- Keep it under about 8 lines. It is a sketch, not a patch.
- Use comments to mark where each fragment goes, such as `// set once ...` or `// here`.
- Prefer the shape the codebase already uses over an idiom you would pick.
- If you do not have a credible fix, end on the question alone. A speculative
  snippet is worse than none.

## Worked examples

### With a fix sketch

**Line 1624** (`!this.clientTools ||`), `src/lib/ahp/surface.ts`.

---

What drains this buffer when a surface never registers client tools?
`!this.clientTools` used to return early; now it defers, but
`drainDeferredClientToolActions` only runs behind an `activeClient`.
Non-tool-driven Slack jobs pass `clientTools: undefined` (`manager.ts:1913`), so
it looks like the buffer just fills to `MAX_PENDING_ENVELOPES` and warns per
action after.

Is there a settled-binding signal we could bail on instead? Something like:

```ts
// set once createSession/attachSession has resolved activeClient
this.clientToolBindingSettled = true;

// here
if (this.clientToolBindingSettled && !this.clientTools) {
  return;
}
```

### Without a fix sketch

This is where narration creeps in, because there is no snippet to fill the
space. Resist it. Two sentences after the question is a good outcome.

**Line 786** (`if value, ok := labels[sandboxDirectResumeRouteLabel]; ok {`), `internal/environment/sandbox/app_principal.go`.

---

Is failing closed on this label intended, given what the caller does with a
classification outage? `waker.go:247-251` degrades
`ErrSandboxResumeClassificationUnavailable` to `NotOwned` and falls back here
specifically so wake survives that outage. This check removes the fallback for
any sandbox already classified `app`, so those stop waking entirely until
classification recovers - and they are the ones with no supervisor topology to
get wrong.

## Choosing the anchor

- Anchor to the **narrowest line that causes the problem**, the specific
  condition rather than the enclosing function.
- When the issue spans a contiguous block, give the range such as `1623-1628`
  and note it can be left as a multi-line comment.
- When a second location is part of the story, mention it inline in the body,
  for example "or we got SessionActiveClientRemoved (line 1424)", rather than
  splitting into two comments.

## Follow-ups

Expect iteration: shorter, softer, question form, drop a phrase. Re-emit the
**whole** anchor and body each time so the result stays paste-able. Do not reply
with a diff of your previous wording.

Before returning, scan the body once for the banned characters above, then again
for content: delete any sentence describing what existing code does, and any
sentence raising a second finding. Two sentences left is a good outcome.

## Important

Don't post comments yourself and make sure the resulting comments are short,
clear, and laconic. If you tested something locally by running code - don't
reveal that fact in the review comment, but rather shape it in the form of open
question, e.g., "this can result" or "this seem to" work in practice.

---
name: opus-use-subagents
description: Drive work from Opus 5.5 with Codex (gpt-6.1-sol) on backend code and diff review, Grok 4.6 (via the Cursor CLI) as the other backend implementer, Sonnet and Opus 5.5 subagents on all frontend and UI work, and an Opus 5.5 architect subagent for planning, architecture, and checking anything complex or risky. Use when the user says "/opus-use-subagents", "opus drives", "ask an architect to plan this", or when working in an Opus session on a change that spans more than one subsystem.
---

# Opus drives, an Opus architect is on call

Opus decomposes the task, hands backend implementation to Codex (gpt-6.1-sol)
or Grok, hands all frontend and UI work to Claude subagents, has Codex review
the diffs, reviews them itself, runs the verification gate, and commits. A read-only
`architect-opus` subagent is consulted for the decisions that are worth a
separate, focused turn.

Every Claude agent here runs Opus 5.5, except `worker-sonnet`, which is for
contained frontend and light work.

If this session is not already on Opus 5.5, say so and ask the user to switch in
the model picker. A skill cannot re-price its own session.

## Who gets what

| Work | Agent |
|---|---|
| Backend implementation with a precise brief: server code, data, integrations, migrations, backend tests | Codex `gpt-6.1-sol` (see Codex below) |
| Backend implementation, second choice | `cursor-agent` with `cursor-grok-4.6-high-fast` or `cursor-grok-4.6-xhigh-fast` (see Grok below) |
| Reviewing any diff (a worker's, Grok's, or the whole branch before push) | Codex `gpt-6.1-sol`, read-only |
| **All frontend and UI**: pages, components, CSS, browser JS, copy on screen | `subagent_type: "worker-sonnet"` for clear, contained UI; `worker-opus` when it needs judgment or has a lot of interacting state. Never Codex. |
| Plan or architecture for a non-trivial change; reviewing a risky or complex design | `subagent_type: "architect-opus"` (or a higher rung — see Effort) |
| Fallback: backend, tricky logic, debugging when Codex and Grok miss | `subagent_type: "worker-opus"` |
| Reading the codebase to answer a question | `subagent_type: "Explore"` with `model: "opus"` |

The definitions live in `.claude/agents/` (project) or `~/.claude/agents/`
(user) and pin their own model and effort,
so pass `subagent_type` and leave `model` alone. The Opus agents pin
`claude-opus-5-5`; `worker-sonnet` uses the `sonnet` alias, so it follows the
latest Sonnet. `Explore` is built in and pins nothing, so pass `model: "opus"`.
The architects are read-only: they decide, the workers write.

Split by directory ownership. Launch independent agents in one message so they
run concurrently; give each a written contract (exact signatures, prop names,
routes, env var names) so the pieces meet.

## Codex (gpt-6.1-sol): backend and review

gpt-6.1-sol is strong on backend code and on code review **when the brief is
very clear**: exact files, behavior, contracts and tests. It does poorly on
frontend and UI work of any kind, so never give it components, CSS, browser JS,
layout or on-screen copy; those go to Sonnet or Opus. On a change that spans
both, split it: Codex takes the backend part, a Claude worker takes the UI.

Run it from Bash with `run_in_background: true` and
`dangerouslyDisableSandbox: true`:

```bash
cd /absolute/worktree && timeout 2400 codex exec -m gpt-6.1-sol \
  -c 'model_reasoning_effort="high"' --sandbox workspace-write --skip-git-repo-check \
  "$(cat "$TMPDIR/brief-<name>.md")" < /dev/null > "$TMPDIR/codex-<name>.log" 2>&1
```

- **`< /dev/null` is required.** Without it a background run waits on stdin
  forever ("Reading additional input from stdin...") and writes nothing.
- `timeout 2400` caps a run that wedges anyway. `--skip-git-repo-check` is
  needed outside a directory Codex already trusts.
- Liveness: a minute after launch the log should show `exec` lines (commands
  running). Only startup lines after about 3 minutes means it is wedged: kill it
  and relaunch. After any kill, check `git status`; partial edits stay behind.
- Effort: `high` by default; `medium` for small, fully specified edits;
  `xhigh` only when `high` already failed on the same problem.
- The final report is the tail of the log. It does not see this conversation,
  your skills or MCP tools; put everything in the brief.
- If a toolchain shim (version manager, wrapper script) fails inside Codex's
  sandbox, tell it the absolute path of the real binary.

**Review.** Run it read-only (`--sandbox read-only`) on a worker's diff, and on
the whole branch (`git diff origin/main`) before pushing. Brief: what the change
must do, then "Review for correctness, missing access checks, data integrity,
races between client state and late data, things that run every time that
should run once, and tests that assert the wrong thing. Report must-fix findings
as file:line with the concrete failure, separate from nits. Do not edit." Fix or
answer every must-fix finding before pushing.

## Grok (Cursor CLI): backend, second choice

Grok 4.6 through the Cursor CLI is the other backend implementer. It runs on the
Cursor subscription, so it spends none of the Claude limit. Use it for backend
work when Codex is busy with a parallel piece, rate-limited, or missed twice.
Like Codex, keep it off frontend and UI work.

| Rung | Model | Reach for it when |
|---|---|---|
| Grok high | `cursor-grok-4.6-high-fast` | Default Grok rung for backend, tests, docs. |
| Grok xhigh | `cursor-grok-4.6-xhigh-fast` | The work itself is hard. Takes the work that would go to `worker-opus-xhigh`. |

Grok is not a `subagent_type`; Claude Code subagents only run Claude models.
Run it from Bash with `run_in_background: true` and
`dangerouslyDisableSandbox: true` (it needs the network and `~/.cursor`):

```bash
cursor-agent -p --trust --force --model cursor-grok-4.6-high-fast \
  --workspace /absolute/worktree --output-format text \
  "$(cat "$TMPDIR/brief-<name>.md")" > "$TMPDIR/grok-<name>.md" 2>&1
```

- Write the brief (same shape as "The brief" below) to a file first. Launch
  several in one message for parallel work, one per ownership boundary.
- You are notified when the command exits. Read only the output file; it holds
  Grok's final report.
- For a read-only question, drop `--force` and add `--mode ask`. Prefer this to
  an Explore agent when the answer takes a lot of reading.
- Grok does not see this conversation, your skills or your MCP tools. Put
  everything it needs in the brief. For a follow-up, send a fresh brief with
  its last report attached.

Fall back to a Claude worker when:

- the work is frontend or UI (always a Claude worker, see the table above);
- the task needs this session's skills or MCP tools (browser checks,
  screenshots, project-specific MCP servers);
- Codex's or Grok's diff fails review twice on the same task;
- `cursor-agent` is logged out, rate-limited or erroring (`cursor-agent status`).

Review Codex's and Grok's diffs exactly as you would a Claude worker's.

## Effort

**`high` is the working floor for implementation; the architects floor at `medium`.**
Nothing here uses `max`. The unsuffixed name is always the default rung — start
there and move deliberately.

The one implementer below the floor is `worker-opus-medium`, and it is below it
for a reason rather than to save money: an architect already did the thinking,
so the agent is executing a decision rather than making one. Reach for it only
when the brief genuinely carries a settled plan. On a vague brief it is the
worst of both worlds, and it is built to stop and say so.

Escalate *to save calls*, not as a treat: one deeper call that settles the
question costs less than three cheap ones that keep bouncing.

| Agent | Effort | Reach for it when |
|---|---|---|
| `architect-opus` | `medium` | Default. A tractable decision with one likely shape. It will tell you if it needs a deeper pass. |
| `architect-opus-high` | `high` | The decision genuinely matters and has a couple of serious contenders. |
| `architect-opus-xhigh` | `xhigh` | Top rung. A wrong pick means reworking code that is already written, or a cheaper rung already missed. |
| `worker-opus-medium` | `medium` | An `architect-opus` rung has settled the design and the brief carries it. Executing a decision, not making one. |
| `worker-opus` | `high` | Default for backend, data, tricky logic, debugging. |
| `worker-opus-xhigh` | `xhigh` | The implementation itself is the hard part: intricate logic, concurrency, a subtle migration, a bug that already resisted a pass. |
| `worker-sonnet` | `high` | Clear, contained frontend and UI work; copy, docs, simple test edits, mechanical changes. UI that needs judgment goes to an Opus worker. |

The natural pairing: settle the design with an architect rung, then hand the
plan to `worker-opus-medium` rather than paying for `worker-opus` to think it
through a second time.

Start at `architect-opus` unless you already know the decision is contested;
it is built to hand back a one-line "this needs a deeper pass, here is why"
rather than guess, and that costs almost nothing.

If you find yourself about to open a second architect call on the same question,
that is the signal you should have opened the first one a rung higher.

## When to call the architect, and when not to

Call `architect-opus` before:

- a change that spans several subsystems and has more than one sane shape
- data-integrity, migration, or concurrency design
- a security or authorization boundary
- a second attempt, after the first approach failed
- a combined diff that is large, coupled, or touches money or user data

Do not call an architect for: ordinary implementation, routine review, a
straightforward bug, or anything the driver can settle by reading the code.

## Making each architect call count

1. **Gather first, then ask.** Send an Explore agent, collect the facts, and
   hand the architect a question with its context attached. Never a "go read the repo
   and tell me what you think" brief.
2. **One call per decision, not per file.** Bundle the open questions into a
   single brief.
3. **Ask for a decision and its reasoning**, not a document: the approach, what
   it rules out, the failure mode it is avoiding, and what would change the
   answer.
4. Use `SendMessage` to follow up with the same architect agent rather than opening
   a fresh one — its context is already paid for.

## The brief

Every agent gets the same shape:

1. Working directory (absolute), "work only here", "do not commit".
2. Repo rules to read first: AGENTS.md, CLAUDE.md, and any rules directory
   the repo keeps for the paths in scope.
3. File ownership: which directories this agent may touch and which another
   agent owns right now.
4. "Read first": the exact files that hold the pattern to copy.
5. Numbered requirements with the contract (types, signatures, routes, env var
   names).
6. Tests to add or extend, by file name.
7. Docs to touch if the change is user-visible.
8. Verify commands with "paste real output", plus any known typecheck gotcha.
9. Report format: files changed, decisions it was unsure about, the exact
   contract as implemented.

Keep the brief specific; a vague brief costs a 20-minute round trip.

## After the agents report

1. Read the report and skim the diff (`git status --short`, `git diff -- <key
   files>`). Look for hard-coded instance values, missing access checks,
   "one-off" steps that would run every time, and anything outside the
   ownership boundary. For a non-trivial diff, also run a read-only Codex
   review (see Codex above).
2. Run the verification gate yourself and gate the commit on every step: the
   linter on changed files, the affected tests, typecheck, build. Never push on
   a red step.
3. Commit with a plain message (what and why), push, and watch CI in the same
   chain.
4. If an agent's report says "pre-existing errors", assume stale build output
   or a duplicated dependency; rebuild and dedupe before believing it.

## Pitfalls

- Two agents editing the same file: the second one's work silently overwrites
  or half-applies. Split by directory.
- An agent adding a dependency can pull a second copy of a shared package. Run
  the repo's dedupe and rebuild before trusting a typecheck.
- Agents report "tests pass" for the files they ran. Run the affected suite
  yourself before pushing.
- A UI task that needs a backend contract can start before the backend exists;
  tell it the missing import is expected and to report only other errors.
- Commit signing blocks agents. Keep commits with the driver.

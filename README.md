# opus-use-subagents

A Claude Code skill for driving work from an Opus 5.5 session:

- **Codex (`gpt-6.1-sol`)** implements backend code from precise briefs and reviews diffs.
- **Grok 4.6** (via the Cursor CLI) is the second backend implementer.
- **Sonnet and Opus 5.5 subagents** take all frontend and UI work.
- **Read-only Opus 5.5 architect subagents** settle plans, architecture, and risky designs.

The driver decomposes the task, writes briefs, reviews every diff, runs the verification gate, and commits.

## Contents

| Path | What it is |
|---|---|
| `skills/opus-use-subagents/SKILL.md` | The skill |
| `agents/*.md` | The subagent definitions it calls (`architect-opus{,-high,-xhigh}`, `worker-opus{,-medium,-xhigh}`, `worker-sonnet`) |

## Install

User-wide (every project):

```bash
git clone https://github.com/better-futures-studio/opus-use-subagents.git
cd opus-use-subagents
./install.sh            # copies into ~/.claude/skills and ~/.claude/agents
```

Into one project instead:

```bash
./install.sh /path/to/project   # copies into <project>/.claude/skills and .claude/agents
```

Then run `/opus-use-subagents` in a Claude Code session on Opus 5.5.

## Requirements

- Claude Code with access to Opus 5.5 (`claude-opus-5-5`) and Sonnet.
- Optional: the [Codex CLI](https://github.com/openai/codex) logged in with access to `gpt-6.1-sol`.
- Optional: the Cursor CLI (`cursor-agent`) logged in, for Grok.

Without Codex or Grok, the skill falls back to the Claude workers.

## License

MIT

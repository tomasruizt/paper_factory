# Creating HTML traces of Claude Code sessions

This doc explains how to reconstruct an HTML transcript of a multi-day Claude
Code conversation that involved running and debugging the paper factory (or any
other multi-day workflow). The output is a self-contained `.html` file that
reads chat-style: user bubbles on the left, Claude bubbles on the right,
runtime/system context interleaved between them.

Example: `traces/weight_justifications_paper.html` (gitignored).

---

## Data sources

Claude Code saves every session as a JSON-lines file at:

```
~/.claude/projects/<encoded-cwd>/<session-uuid>.jsonl
```

The `<encoded-cwd>` is the working directory with `/` replaced by `-` and a
leading `-`. Two examples that matter for this repo:

| Encoded cwd                                                       | Actual cwd                                                    |
| ----------------------------------------------------------------- | ------------------------------------------------------------- |
| `-home-tomasruiz-code-paper-factory`                              | `/home/tomasruiz/code/paper_factory`                          |
| `-home-tomasruiz-code-paper-factory-ongoing-weight-justifications`| `/home/tomasruiz/code/paper_factory/ongoing/weight_justifications` |

Each `.jsonl` line is one event: user message, assistant message, tool call,
tool result, etc. The schema has `type` (`user`/`assistant`), `timestamp` (ISO
UTC), `message.role`, `message.content` (string or list of content blocks),
plus identifiers (`uuid`, `parentUuid`, `sessionId`).

**Two important distinctions:**

1. **User-facing sessions** are the ones where the user is typing into the
   `claude` CLI. These live under the cwd they were started from
   (usually the repo root).
2. **Worker sessions** are spawned by `claude -p` from inside `run_paper.sh`
   — they create transcripts under the *project subdirectory*'s encoded cwd
   (e.g. `…-ongoing-weight-justifications`). For a trace narrating *what the
   user did*, you only want the user-facing sessions. Ignore the worker
   transcripts.

A long-running conversation can span multiple resumed sessions across days.
The session UUID stays the same; the `.jsonl` simply grows. The first event's
timestamp is the true session-start time.

---

## Step-by-step recipe

### 1. Identify the relevant user-facing sessions

List sessions under the cwd you care about, sorted by modification time, then
peek at the first user message of each:

```bash
for f in ~/.claude/projects/<encoded-cwd>/*.jsonl; do
  basename=$(basename "$f" .jsonl)
  first_user_msg=$(python3 - "$f" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    for line in f:
        try: d = json.loads(line)
        except: continue
        if d.get("type") != "user": continue
        c = d.get("message", {}).get("content")
        text = c if isinstance(c, str) else next(
            (it.get("text","") for it in c if isinstance(it, dict) and it.get("type") == "text"),
            ""
        )
        if len(text.strip()) > 20:
            print(d.get("timestamp",""), "|", text[:200].replace("\n"," "))
            break
PY
)
  echo "$basename | $first_user_msg"
done
```

Discard sessions whose first prompt is off-topic. Keep the ones that are
clearly part of the story you're tracing.

### 2. Get the exact session start time

```bash
python3 - <<'PY'
import json
with open("<path-to-jsonl>") as f:
    for line in f:
        d = json.loads(line)
        if d.get("timestamp"):
            print(d["timestamp"])
            break
PY
```

The first event's `timestamp` (ISO UTC) is the session start. Convert to
local time for display — but keep UTC as a cross-reference, since users
often think in local time and `.jsonl`s are UTC.

### 3. List user prompts with timestamps

For a session that spans days, knowing exactly when each prompt was sent is
essential. The pattern that worked for `weight_justifications`:

```python
import json
with open("<path-to-jsonl>") as f:
    for line in f:
        try: d = json.loads(line)
        except: continue
        if d.get("type") != "user": continue
        c = d.get("message", {}).get("content")
        text = ""
        if isinstance(c, str): text = c
        elif isinstance(c, list):
            for it in c:
                if isinstance(it, dict) and it.get("type") == "text":
                    text = it.get("text", "")
                    break
        text = text.strip()
        if len(text) < 10: continue
        # Skip tool results and command-name wrappers
        if "<system-reminder>" in text and len(text) < 500: continue
        if "command-name" in text: continue
        print(d.get("timestamp", ""), "|", text[:160].replace("\n", " "))
```

This gives you the conversation's "skeleton" — every user turn with its UTC
timestamp.

### 4. Extract Claude's tool calls when narratively important

To find specific Bash commands Claude ran (e.g. the original
`./launch_agents.sh new` invocation), grep the jsonl for the command
substring. Each match line is a full event JSON — search for the `command`
field to read it back. Example:

```bash
grep -n "launch_agents.sh new" ~/.claude/projects/<encoded-cwd>/<session>.jsonl
```

The tool-use input lives under `message.content[].input.command`.

### 5. Correlate with the runner log

For paper factory runs, the user's session is alongside
`ongoing/<paper>/logs/runner.log`. Grep the runner log for the same time
range as the session events — that tells you what the harness was doing
while the session was idle, which becomes a "gap" block in the HTML.

### 6. Build the HTML

Use the layout from `traces/weight_justifications_paper.html` as a template:

- **Top-level group: session.** Each session is preceded by a session
  header showing session id, start time (local + UTC), and cwd.
- **Within a session:** chronological turns. For long sessions that span
  days, add day dividers between calendar boundaries.
- **`.turn.user`** — user bubble, left-aligned (`margin-right: auto`),
  blue left border.
- **`.turn.claude`** — Claude bubble, right-aligned (`margin-left: auto`),
  green right border, slightly off-white background to distinguish.
- **`.gap`** — full-width italic block describing what the runner/system
  was doing between user turns. Used liberally for sessions that span
  idle periods (overnight, multi-day).
- **`.who` header on each turn** — role label + timestamp. For Claude
  turns, `flex-direction: row-reverse` so the role label appears on the
  right side of the bubble.

The CSS is self-contained — no external assets. The whole trace is one
`.html` file, viewable by opening it in a browser.

### 7. Decide where to stop

Long sessions don't always have a natural endpoint. Ask the user — or
default to the last substantive exchange before the trace-creation request
itself. (Including the "now write me a trace" prompt in the trace is
recursive and confusing.)

---

## Common pitfalls

- **Timezone.** `.jsonl` timestamps are ISO UTC (`...Z`). Local-time
  events (runner log entries, file mtimes) are in the user's local
  timezone — for this machine, Europe/Berlin (CEST = UTC+2 in summer,
  CET = UTC+1 in winter). Always label which one a displayed time is in,
  or you will mislead the reader by an hour or two.
- **Multi-session conversations.** When a user comes back days later,
  Claude Code can either resume the prior session (same UUID, file
  grows) or create a new one. Both patterns appear in real
  conversations. The session-grouped structure handles both — just
  detect which jsonl files cover the period you care about.
- **Worker sessions are not user sessions.** Don't include
  `claude -p` worker transcripts (under
  `…-ongoing-<paper>/`) in a "what the user did" narrative. They
  represent harness-internal subprocess calls, not interactive
  turns. They can be useful if you want to trace what an *agent* did
  inside a particular step, but that's a different artifact.
- **Tool-result content is usually noise.** When iterating over user
  events, skip entries whose content is a `tool_result` (a list of
  content blocks with `type: tool_result`). Those are the responses
  Claude received from its own tool calls, not user input.
- **System reminders.** Many user events have content that's actually
  a `<system-reminder>` injected by the harness. Filter those out
  unless they're the actual point of a turn.
- **The file is gitignored.** `traces/` is in `.gitignore`. If you
  want to share a trace, copy or send the HTML file directly — don't
  expect it to land in git history. The documentation (this file) is
  tracked; the artifacts are not.

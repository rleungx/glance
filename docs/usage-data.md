# Usage data and reliability

Glance tracks **skills** across Claude Code, Codex, and OpenCode.
Antigravity and Devin CLI (including Fusion) support **global skill inventory only**;
they do not yet provide usage statistics. See [Antigravity support](antigravity.md)
and [Devin CLI support](devin-cli.md). Antigravity replaces the retired Gemini CLI source;
Gemini session files are not interpreted as Antigravity activity.
It shows **observed skill records**, not an audit of every assistant action. A tool
call is not proof of successful execution; a skill instruction block is not proof
that every instruction was followed. Success percentages use known outcomes and
show that denominator. Zero observations mean “Usage not observed”, not “never used”.

## Coverage and cleanup

EvidenceReportingRepository.loadUsage returns windowed counts, quality metadata,
and warnings together. Metadata includes scanned locations, files read, unreadable
files, skipped records, unmatched inventory records, duplicates, inferred event
identities, and first/last observed timestamps.

| State | Meaning | Cleanup suggestions |
| --- | --- | --- |
| unavailable | No readable history was discovered | Paused |
| partial | Read/parse failures, conflicting records, or inventory gaps | Paused |
| observed | Available records read; historical coverage unverified | Paused |
| verified | Authoritative complete coverage for a stated interval | Only within that interval, without reported loss |

None of the current local-log adapters claims verified coverage. Reading all
remaining files does not prove logs were never deleted, expired, or omitted.
Current adapters therefore display top lists but do not produce definitive
stale/removal recommendations. Event date bounds are not a verified coverage
interval. There is no UI override that treats unknown coverage as complete.

The 1/7/14/30-day selector affects top lists. All retained history remains available
for historical counts. Snapshots bind source and window; a failed new window does
not display an old window under its label. OpenCode window queries share one
read-only SQLite transaction.

## Source scope and event identity

- Claude reads ~/.claude/projects/**/*.jsonl, including subagents. Assistant tool
  blocks are parsed independently. Skill.input.skill activations are matched
  to the known inventory. Global skill scope is shown in Settings; activations
  outside that inventory are reported as unmatched.
- Codex reads active and archived sessions from CODEX_HOME (default ~/.codex).
  Structured user skill blocks are counted, not catalog/assistant mentions or
  ordinary tool calls. Inventory includes ~/.agents/skills and the Codex skills directory,
  including symlinked and built-in skills. Embedders may supply explicit extra
  skill roots. Arbitrary project/plugin roots are not assumed discovered; implicit
  skill reads remain outside the supported activation format.
- OpenCode reads skill tool records from its local SQLite database and installed
  skills from its skills directory; it does not need a running OpenCode server.
- Antigravity discovers direct `SKILL.md` definitions in its documented application
  and IDE global roots. Folder names are filesystem labels, not parsed frontmatter
  identifiers. It does not scan Gemini CLI history or infer CLI/SDK, project, or
  plugin skills. Counts, dates, usage ranks, and cleanup suggestions remain hidden.
  Definition files are not validated as enabled skills, and evidence stays unavailable.
- Devin CLI discovers direct `SKILL.md` definitions in its documented stable-channel
  global roots. Directory names are the invocation identifiers. Definitions with
  the same name in different files remain distinct; symlinked roots are deduplicated.
  No prompt content, session history, credentials, or agent configuration is read.
  This does not establish that Devin is installed or that a skill is enabled.
  Usage evidence stays unavailable; the UI hides counts, usage ranks, dates, time
  windows, and cleanup suggestions for this inventory-only source.

Native tool-call IDs are preferred for deduplication. Without an ID, a SHA-256
fingerprint of timestamp and relevant record content is used, and the inferred
identity count is exposed. This cannot prove whether identical ID-less records
are distinct actions. Conflicting records sharing an ID mark data as partial.
Duplicate copies are not blindly added to totals.

Claude transcript caches use file content, not just size and modification time.
Partial-parse diagnostics survive cache hits. Missing, invalid, and truncated data
are not treated as successful zero-usage observations. Future-dated transcript
events are excluded from current windows and reported as skipped records.

## Inspecting evidence and validation

Settings shows quality counters, observed date bounds, and scanned locations.
Hovering over a skill shows up to five local references (file and line/block,
or SQLite part.id), never transcript text or tool arguments. Support report
version 2 exports quality counters and dates, not these new paths or samples.

Regression tests cover missing history, malformed siblings, truncation,
unchanged-metadata rewrites, duplicate/distinct IDs, inventory discovery, source
selection migration, coverage-gated cleanup, and window-switch failures. Fixtures are
synthetic format examples, not a multi-version production accuracy benchmark.
Validating a specific assistant version still requires consented, sanitized real
records and hand-counted expected results. Glance does not read the developer's
private sessions to obtain test samples.

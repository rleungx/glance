# Antigravity support

Status: **global application and IDE skill inventory only**. The source is named
`Antigravity`, with ID `antigravity-local`. Devin CLI remains a separate source.

## Replacement of Gemini CLI

Antigravity replaces Gemini CLI in the source picker, package targets, and diagnostics.
On startup, a saved `gemini-local` selection is migrated to `antigravity-local`.
Other selections are unchanged. This migrates only the Glance preference, not files,
usage counts, or assistant settings.

The old Gemini command runner and transcript parser are removed.
`GLANCE_GEMINI_EXECUTABLE` is no longer used or included in support reports.
Glance never launches either agent or changes their configuration as part of discovery.

## Discovery scope

Glance inspects immediate child folders for a readable regular `SKILL.md` at:

| Product | Global root | Reference |
| --- | --- | --- |
| Antigravity application | `~/.gemini/config/skills` | [Application skills](https://antigravity.google/docs/skills) |
| Antigravity for IDEs | `~/.gemini/antigravity/skills` | [IDE skills](https://antigravity.google/docs/ide/skills/) |

These are distinct product locations, not inferred aliases or priority rules.
Each row shows its folder label and canonical definition path. Frontmatter and
instruction content are not read, validated, or executed. A folder label can differ
from the agent's frontmatter-defined skill name. Discovery does not establish that
Antigravity is installed, has loaded the definition, or has enabled it.

Same-name definitions in different files remain distinct. Canonical duplicate roots
are scanned once. Symlinks are resolved for file discovery only; this does not
certify the agent's own symlink-loading behavior. Different folder aliases remain
distinct labels even when they resolve to the same file.

Missing optional roots are normal. Broken links, invalid file types, and inaccessible
locations report an incomplete inventory rather than successful zero usage.
Refresh rescans the definitions. Finder reveal and copying a folder label are
available from each row's context menu.

## Not covered

- Workspace, plugin, remote, or legacy workflow discovery.
- CLI skill definitions: [CLI documentation](https://antigravity.google/docs/cli/plugins)
  describes a separate `~/.gemini/antigravity-cli/skills` location and Markdown command
  format. The application/IDE scanner does not claim coverage of this interface.
- SDK skills: [SDK documentation](https://antigravity.google/docs/sdk/tools/) accepts
  caller-supplied `LocalAgentConfig.skills_paths`. Those paths cannot be inferred
  from the application's global inventory. This integration is not a claim of
  support for the Artificial Analysis Antigravity SDK benchmark harness.
- Skill activation counts, outcomes, last-used dates, or cleanup recommendations.
- Gemini CLI sessions, shared `~/.agents/skills`, or arbitrary home-directory scans.

Usage evidence remains `unavailable`; internal zero-count placeholders are not
displayed as usage observations. The inventory-only UI hides usage ranks, counts,
time filters, and cleanup suggestions. No session history, credentials, or hooks
are read or installed.

## Validation and follow-up

Official paths were checked on 2026-09-15. Automated tests use synthetic temporary
files to cover scope isolation, duplicate names, symlinks, missing/invalid roots,
refreshes, preference migration, and unavailable usage evidence.

Actual-version compatibility and usage statistics still need consented, sanitized
records with a validated skill-activation schema. Ordinary file reads or Gemini
tool calls must not be relabeled as confirmed Antigravity activations.

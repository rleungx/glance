# Devin CLI support

Status: **global skill inventory only**, including users of Devin Fusion.
Fusion is a mode of Devin CLI, not a separate Glance source. The source is named
`Devin CLI`, with the stable ID `devin-local`.

## What Glance discovers

Glance inspects these documented global skill directories on macOS:

| Location | Scope |
| --- | --- |
| `$XDG_CONFIG_HOME/devin/skills` (default `~/.config/devin/skills`) | Devin CLI |
| `~/.agents/skills` | Shared agent skills |
| `~/.codeium/windsurf/skills` | Stable legacy Windsurf channel |

Only absolute `XDG_CONFIG_HOME` values are accepted; empty or relative values use
the default. Each immediate child directory containing a readable, regular
`SKILL.md` file is shown under its directory name (the slash-command identifier).
Glance does not parse or execute skill content or validate its YAML. A discovered
definition is not a claim that Devin will load it or that its configuration enables it.

Canonical file paths keep same-name definitions in different locations separate.
Repeated/symlinked roots are scanned once. Skill-directory/file symlinks are
resolved for discovery; this does not certify Devin's own symlink-loading behavior.
There is no recursive scan of a skill's references or of arbitrary projects.
Unreadable locations, broken links, and non-file definitions produce a warning
without discarding other readable definitions. Absent optional roots are normal.

The menu shows an alphabetical inventory, definition locations, and an explicit
“Skill inventory only” notice. The context menu can reveal a definition in Finder.
There are no activation counts, success rates, usage ranks, or time-range controls.
Refresh updates the inventory; it does not start Devin CLI.

## Not covered yet

- Project-specific `.agents/skills`, `.devin/skills`, or `.windsurf/skills`.
- Plugins, enterprise policy, enabled state, or the active precedence winner.
- Preview/insiders channels and cloud sessions.
- Invocation history, last-used time, outcomes, and cleanup recommendations.

The repository's internal zero-count placeholders are **not measured usage**.
They are paired with `inventoryOnly` diagnostics, `unavailable` usage evidence,
and `installedButUnused: false`. Definition discovery never upgrades usage
coverage, and no rolling-window snapshots are produced.

## Before enabling usage statistics

Official docs expose ATIF export (`devin --export <path>`) and lifecycle hooks
whose tool names include `skill`, but do not establish the complete activation
record schema needed by Glance. No native-session parser is guessed from other agents.

Obtain consented, sanitized examples from a pinned Devin CLI version covering
manual/automatic invocation, subagent skills, Fusion, resume/fork, and failed or
cancelled activations. Confirm event IDs, timestamps, skill identifiers, duplicate
handling, and what is absent from exports/hooks before implementing a reader.
Any opt-in capture must omit prompt bodies, arguments, credentials, and tool output.
Installing hooks or exporting a real session requires separate user action/approval.

## References

Checked on 2026-09-15:

- [Devin CLI and Fusion](https://devin.ai/cli)
- [Skills overview and directories](https://docs.devin.ai/cli/extensibility/skills/overview)
- [Skill identifiers and optional frontmatter](https://docs.devin.ai/cli/extensibility/skills/creating-skills)
- [Commands and ATIF export](https://docs.devin.ai/cli/reference/commands)
- [Lifecycle hooks and tool names](https://docs.devin.ai/cli/extensibility/hooks/lifecycle-hooks)

Automated tests use synthetic temporary directories only. They validate path
selection, missing/invalid roots, symbolic links, same-name definitions, scope
boundaries, source integration, and unavailable-usage/cleanup gating. They are
not a production compatibility test against an installed Devin CLI.

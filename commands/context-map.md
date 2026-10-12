---
description: Map what gets injected into this session - base layers, CLAUDE.md chain and rules, memory index, settings and plugin hooks, output style, skills - with sizes and firing counts from a debug log and registry status.
argument-hint: "[--log <claude --debug-file path>] [--unregistered]"
allowed-tools: Bash, Read
---

Run `sh "${CLAUDE_PLUGIN_ROOT}/scripts/context-map.sh" $ARGUMENTS` and show the resulting table
as-is.

Columns: `layer | id | event | class | size | registered | fires`. `size` carries its unit: `c` is
characters reported by the debug log, `b` is bytes read from a file, a bare number is a skill
count, `unmeasured` is a base layer no file shows. `fires` is how many distinct firings the log
recorded for that row (`-` without a log); a hook row's `size` is the total across those firings.

Then summarise in 3 lines:
1. Always-on size: for every `always`-class row with a measured `size`, add the `b` values and the
   `c` values separately (never mix the units); divide a hook row's `c` value by its `fires` for
   the per-firing cost. Name the `unmeasured` rows as not counted.
2. Per-prompt size: same, for `per-prompt`-class rows, per firing.
3. Unregistered injectors (rows with `registered = no`, or run `--unregistered` for the short list).
   Also flag any `log | unattributed` rows and an `auto-memory (OVER: ...)` id.

This never executes a hook. It reads settings, plugin manifests, CLAUDE.md and rules files, and (if
given `--log`) an existing debug log; it writes only private temp files that it removes. Sizes for
hook rows are only available with `--log <path>`, produced by running `claude --debug-file <path>`
first; without it those cells show `-`.

Caveat: a log captured with `claude -p` reports the `sdk-cli` entrypoint, so kit advisories that
stand down in an interactive session fire in it and inflate the always-on figure. Compare like with
like: a `-p` log against a `-p` log, an interactive log against an interactive log.

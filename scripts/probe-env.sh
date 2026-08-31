#!/usr/bin/env bash
# kit-scope: shared
# agent-tiers env probe (read-only).
# Reports how THIS environment configures the Lead and what sub-agents inherit, so the kit can
# self-configure per project instead of hard-coding facts verified under one GUI.
#
# What it CAN determine from Bash:
#   - the inherited model env, the effort-pin env, the Lead's live effort, settings.json effort, host.
# What it CANNOT (see commands/init.md):
#   - whether frontmatter `model:` actually overrides the inherited model - a sub-agent cannot reliably
#     introspect its own live model; only the GUI's agent/model panel is ground truth. That step is a
#     guided user confirmation, not an auto-probe.
set -u

echo "probed_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "host_term=${TERM_PROGRAM:-}"
# Best-effort GUI/host guess from the exec path + entrypoint (more reliable than TERM_PROGRAM under editor addons).
host_guess="unknown"
case "${CLAUDE_CODE_EXECPATH:-}" in
  *codemoss*) host_guess="codemoss" ;;
  *cursor*)   host_guess="cursor" ;;
  *Code*|*vscode*|*.vscode*) host_guess="vscode" ;;
  *jetbrains*|*JetBrains*) host_guess="jetbrains" ;;
esac
[ "$host_guess" = "unknown" ] && [ -n "${TERM_PROGRAM:-}" ] && host_guess="$TERM_PROGRAM"
echo "host_guess=${host_guess}"
# Known-host shortcut: CodeMoss resolution was verified empirically (2026-06-17/18). init.md uses this
# to pre-fill the recommended answer instead of asking the user to read the GUI model panel.
if [ "$host_guess" = "codemoss" ]; then
  echo "known_resolution=codemoss model-override=true effort-honored=true effort-pin=empty settings-effort=ignored advisor-ro=true (verified 2026-06-17/18 - re-confirm if drifted)"
fi
echo "entrypoint=${CLAUDE_CODE_ENTRYPOINT:-}"
echo "agent_sdk_version=${CLAUDE_AGENT_SDK_VERSION:-}"
echo "anthropic_model=${ANTHROPIC_MODEL:-}"        # model the GUI exports to sub-agents as the inherited default
echo "effort_env=${CLAUDE_CODE_EFFORT_LEVEL:-}"    # if NON-EMPTY this PINS sub-agent effort (frontmatter effort can't dial down)
echo "lead_effort=${CLAUDE_EFFORT:-}"              # OUTPUT-only: the current (Lead) turn's effort

settings="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"
if [ -f "$settings" ]; then
  eff=$(grep -o '"effortLevel"[[:space:]]*:[[:space:]]*"[^"]*"' "$settings" | head -1 | sed 's/.*"\([^"]*\)"[[:space:]]*$/\1/')
  echo "settings_effort=${eff:-}"
else
  echo "settings_effort="
fi

# Diagnostic dump of CLAUDE_*/ANTHROPIC_* env. Names are always printed; a value is redacted by variable
# NAME only (KEY/TOKEN/SECRET/PASSWORD substring) - a secret held in a differently-named CLAUDE_*/
# ANTHROPIC_* var still prints in full. The value itself is never shape-matched.
echo "--- claude/anthropic env (secrets redacted) ---"
while IFS='=' read -r k v; do
  case "$k" in
    *KEY*|*TOKEN*|*SECRET*|*PASSWORD*) echo "$k=<redacted>" ;;
    "") : ;;
    *) echo "$k=$v" ;;
  esac
done < <(env | grep -iE '^(CLAUDE|ANTHROPIC)_' | sort)

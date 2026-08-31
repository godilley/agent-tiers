# modeprobe fixtures (kit-local, export-ignored)

Throwaway PreToolUse / PermissionRequest / PermissionDenied recorder hooks used 2026-08-16 to answer the
cc-gui permission-mode brief. Paths inside settings*.json point at /tmp/modeprobe - copy this dir there
(or sed the paths) before use.

    cp -r ~/.claude/agent-tiers/scripts/fixtures/modeprobe /tmp/modeprobe
    claude -p --settings /tmp/modeprobe/settings.json --model haiku --permission-mode default \
      'Run exactly this bash command: echo MODEPROBE. Then say done.'
    jq -r '.permission_mode' /tmp/modeprobe/log.jsonl

- rec.sh          : appends every hook payload as one JSON line to /tmp/modeprobe/log.jsonl, tagged _ev
- denywrite.sh    : PreToolUse Write|Edit -> deny when content carries an AKIA-shaped key
- askprobe.sh     : PreToolUse Bash -> ask when the command contains ASKPROBE
- settings.json   : recorder on Bash + Write|Edit, denywrite, PermissionRequest/PermissionDenied recorders
- settings-ask.json: same plus askprobe

Findings these produced: docs/_local/BRIEF-ccgui-permission-questions-ANSWERS.md, this repo (private
notes, not bundled - same as this fixtures dir).

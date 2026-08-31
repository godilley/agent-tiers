#!/usr/bin/env sh
# kit-scope: local
# records every hook payload as one JSON line, tagged with the event name from argv
ev="$1"; shift
in="$(cat)"
printf '%s' "$in" | jq -c --arg ev "$ev" '. + {_ev:$ev}' >> /tmp/modeprobe/log.jsonl 2>/dev/null || printf '{"_ev":"%s","_raw":"unparsable"}\n' "$ev" >> /tmp/modeprobe/log.jsonl
exit 0

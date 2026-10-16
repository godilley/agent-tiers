#!/usr/bin/env sh
# kit-scope: shared
# Stop-event entry point for notify.sh (install/options.tsv is one id per event, id =
# scripts/<id>.sh, so the Notification-event `notify` row and this Stop-event row can't share one
# id - see install-flat.sh's ledger_set comment). All real logic (title/icon/tag parsing) lives in
# notify.sh, which branches on the payload's own hook_event_name. Self-check: notify.selfcheck.sh
# covers the Stop branch this wrapper triggers; there is nothing else in this file to test.
# Gates on its own id, then execs notify.sh, which gates again on id `notify`: so disabled_hooks listing
# `notify`, or a kit-root .state/off/notify marker, also silences the Stop pings.
[ "$(sh "$(dirname "$0")/kit-gate.sh" "$0" </dev/null 2>/dev/null)" = standdown ] && exit 0
exec sh "$(CDPATH= cd -- "$(dirname "$0")" && pwd)/notify.sh" "$@"

#!/usr/bin/env sh
# kit-scope: shared
# Stop-event entry point for notify.sh (install-flat.sh's HOOK_ROWS is one id per event, id =
# scripts/<id>.sh, so the Notification-event `notify` row and this Stop-event row can't share one
# id - see install-flat.sh's ledger_set comment). All real logic (title/icon/tag parsing) lives in
# notify.sh, which branches on the payload's own hook_event_name. Self-check: notify.selfcheck.sh
# covers the Stop branch this wrapper triggers; there is nothing else in this file to test.
exec sh "$(CDPATH= cd -- "$(dirname "$0")" && pwd)/notify.sh" "$@"

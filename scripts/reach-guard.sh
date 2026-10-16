#!/usr/bin/env sh
# kit-scope: shared
# agent-tiers PreToolUse(Bash|Write|Edit|MultiEdit|NotebookEdit|mcp__chrome-devtools__*|
# mcp__claudecodebrowser__*) guard: stops an agent reaching another machine or a logged-in account through
# Bash (ssh, scp/rsync/sftp/sshfs, mosh, cloud and infra CLIs, `gh api`) or a browser MCP server, and
# protects its own data and kill switches from agent writes.
#
# Browser arm (mcp__* tools): `mcp` rows give each tool a group and a role (observe, navigate, act,
# local); no row means act for the two built-in server prefixes and no output for any other server.
# browser_auto (chrome-devtools) tracks which host each pageId shows in .state/reach-guard/pages.<sid>
# (navigate_page url makes it unknown and leaves a pending `map` line that the PostToolUse hook
# reach-guard-grant.sh applies only on a successful navigation's `## Pages` response, so a declined ask
# or a failed navigation leaves it unknown; back/forward make it unknown; new_page and the response text
# are read by the PostToolUse hook). Decision: a local origin (local-origin rows, group
# local=yes) passes for every caller; a subagent is denied; an allowlist row `browser_auto <host-glob>
# read|all` allows (read covers observe and navigate, all covers act too); an attended Lead with a
# session grant for (host, observe|act) is allowed unlogged; act with group act=deny is denied; else ask
# (unattended: deny). An approved ask on a known host leaves a pending marker the PostToolUse hook turns
# into the grant. A page the guard cannot place (back/forward, no pageId, no map entry, an observed local
# host it did not judge itself, a scheme outside the local-origin rows) asks on every call and is never
# granted. browser_real (claudecodebrowser): every call asks (Lead) or is denied (subagent, unattended),
# no grant, no local pass, no allowlist. Kit data missing: every built-in browser call is an unknown page.
# Browser ceilings: the page map changes only through reach-guard's own judgement of an agent-supplied URL
# (navigate_page url, new_page); a response showing a different host makes the page unknown. A page that
# navigates itself without the call's response saying so (a meta refresh, a timer set by evaluate_script,
# a later script redirect) keeps its last entry, local included, until a listing response or a
# navigate_page re-places it, and sub-agents and unattended sessions can act on it meanwhile. A restart
# of the MCP server process reuses page ids without `Page ids have changed.`, so a stale entry holds until
# a listing re-observes the page. An ask approved by something other than a person (an auto-approving
# permission hook, a permission-prompt tool, an automatic approval mode) still leads to a grant.
# list_pages, select_page, close_page and emulate are local-role and run for sub-agents too (list_pages
# shows every open page's URL). Path-like arguments (key, or its array's key, matching path|dir|file)
# that name a protected path or a settings*.json file are denied for every caller (a relative one is
# judged against both the payload cwd and CLAUDE_PROJECT_DIR, and denied outright when it holds a `..`
# component, since the server resolves it against its own directory); a path built inside
# a script the browser runs is not seen. A call on the selected page with no pageId is unknown; a
# renamed or plugin-scoped server name matches no row and gets no output; with no session_id nothing is
# tracked or granted.
#
# Classes are data: kit default data/reach-classes.tsv, user layer and allowlist in
# ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/reach-guard/{classes,allow}.tsv (refused, with a breadcrumb, when
# the directory or a file is a symlink or not owned by the running uid). Bad rows are skipped, one
# breadcrumb per file content. Kit data missing, or guard-cmdpos.sh missing or stale: every command
# holding a class word (built-in v1 program list when the data is gone) is denied as unsure.
#
# Decision (per tool call, most restrictive segment wins; substitution bodies count as segments):
#   not reach, a `local` verb, group off ........... no output, no log
#   act or unsure, not allowlisted ................. deny, handing the exact command back as
#                                                    `RUN (one-off, you run it): ! <command>`
#   ro, not allowlisted or granted ................. ask (guard_ask_decision: subagent or unattended -> deny)
#   every segment an allowlisted or granted reach segment, no local write redirect -> allow (subagent ->
#   deny; an allow that used a session grant is logged why=grant)
#   allowlisted reach plus anything else ........... no output (normal permission flow)
#   write to a protected file or switch ............ deny, Lead included
# Allowlist rows: `<group> <target-glob> read|all`; read covers ro, all covers ro and act; unsure, a
# selector (flag or ENV= prefix), ssh -F/-J/-o HostName/Proxy*, or one uncovered host of a multi-host
# transfer is never covered. Ask and deny texts carry two fixed labels: `RUN (one-off, you run it): !
# <command>` hands the exact command back, and `POLICY CHANGE (persists, you run it): ! [mkdir -p <dir>;
# ]printf '<group>\t<target>\t<read|all>\n' >> <allow.tsv>` appends the allowlist row (only when the result
# is allowable, its target one shell-safe token and its group [A-Za-z0-9_-]+; browser_real names none; a
# % in the target is doubled for printf; the path is ~/.claude/reach-guard/allow.tsv when CLAUDE_CONFIG_DIR
# is unset, else that directory's single-quoted path; mkdir -p only while the directory is absent, joined
# with `;` so the line also works pasted with its leading `!`, which negates a command). When the user's
# directory or allow.tsv is refused (symlink, not owned, unreadable) the line is replaced by a sentence
# saying no row can be added. The POLICY CHANGE line is always the last thing in its text, so a copy to
# the end of the line is the command.
# Safe to name: an agent running that line is denied by the protected-path rule below (a path component
# exactly `reach-guard`), and the operator's own `!` command skips PreToolUse.
# Session grants (Bash, read-only): only for the attended Lead (no agent, not unattended, an id-shaped
# session_id). An ask whose uncovered read-only results name exactly one (group, target) pair, none
# never-allowable, both one shell-safe token ([A-Za-z0-9._:@%+,=~/-], no leading ~ or -), leaves
# `rgrant <group> <target> <program>` at .state/reach-guard/pending/<sid>.<tool_use_id>; the PostToolUse
# hook reach-guard-grant.sh turns it into a line of .state/reach-guard/rgrant.<sid>, so a declined ask
# grants nothing. With reach-guard-grant switched off (kill switch in <kit>/.state/off or <state>/off,
# or kit-gate.sh standing it down: disabled_hooks, a group switch) no marker is written and the ask says
# Yes covers this call only. A grant covers a read-only result whose group and target match it exactly
# (no glob); act, unsure and never-allowable results are never covered by one, and sub-agents and
# unattended sessions never read the file. Ceilings: an ask approved by something other than a person
# (an auto-approving permission hook, a permission-prompt tool, an automatic approval mode) still leads
# to a grant; a grant on an `@default` target trusts the exported environment the same way an @default
# allowlist row does; a flat install whose reach-guard-grant wiring is stale (no Bash in its matcher)
# still promises a grant it never writes, which fails safe (the next call asks again). Cap: every marker
# write (Bash and browser) first removes pending markers older than a day (find -mtime +0), since a
# declined ask never gets the PostToolUse that would remove its marker.
#
# Shapes: ssh/autossh read only when every flag is in `readopt`, the remote string is plain words
# ([A-Za-z0-9_./:=@%+,~ -], no metacharacter at all) and its first words match an `rverb ro` row;
# mosh, any transfer with a remote operand, and sftp/sshfs with any operand are act; cloud CLIs by
# `verb` rows; docker only with a remote daemon or a context change; `gh api` is ro for a GET with no
# body flag and only `readopt` flags, graphql is act. gh subcommands other than api are group gh_write,
# off by default. Command words: `argv` wrappers are walked through (an unknown wrapper option followed
# by a dash word is unsure when a class word is present); an opaque command word is unsure, except a
# plain parameter (a dollar sign and a bare name, braced or not) or a leading ~ path, which are unsure only beside a class word; an
# unknown command not on the `noexec` list whose first operand is a class program is unsure; a command
# holding a 0x1D or 0x1F byte and a class word is unsure.
#
# Protection: Edit/Write/MultiEdit/NotebookEdit into the user reach-guard dir, the kit data file, the kit
# (and state dir) .state/reach-guard/ or .state/off/reach-guard, and, in the kit this guard runs from only
# (a same-named file in a git worktree or any other directory is not protected on this route),
# scripts/reach-guard*.sh (one path component), scripts/kit-gate.sh, scripts/guard-cmdpos.sh,
# install/options.tsv and hooks/hooks.json (path resolved with readlink -f, or lexically when it does not
# exist yet; compared case-insensitively, since macOS APFS is); a settings*.json edit (the requested or
# the resolved basename, any case; an edit with an empty old_string reads as a whole new file, which the
# host only allows on an empty or absent one) whose result trips a stand-down test the
# file did not already trip, read the way kit-gate.sh reads options (arrays joined before the false/0
# test, disabled_hooks matched as a whole item): AGENT_TIERS_OFF=1; an env key AGENT_TIERS_*,
# CLAUDE_PLUGIN_*, LD_*, DYLD_*, CLAUDE_CONFIG_DIR, HOME or PATH added or changed; agent-tiers enabled,
# group_safety or an enabledPlugins agent-tiers@ entry false/0; reach-guard in disabled_hooks;
# disableAllHooks true; a truthy group_safety removed or nulled; a hooks command naming reach-guard
# removed, or any hooks entry whose command names reach-guard changed in its event, matcher or command
# (each such {event, matcher, command} present before must be present after; additions pass).
# Bash (names compared case-insensitively): a path component exactly `reach-guard`, `reach-classes`, a
# glob word matching either name, or `settings` with a stand-down key word, in any segment that is not a
# pure read (cat head tail less wc ls stat file diff cmp md5sum sha256sum grep, rg without --pre, git
# diff/status/blame without --output; no write redirect, no tee, no -i; less without -o, --log-file or a
# + command); any write onto a settings*.json destination (redirect, cp/mv/ln/install target, tee, dd
# of=, sed -i; the verb found anywhere in the segment, so launchers are covered), sent to the Edit tool
# instead; and, by basename only (the Bash arm knows no cwd), a write onto reach-guard*.sh, kit-gate.sh or
# options.tsv (or a glob word matching one) by the same destination rules, an rm, unlink, shred,
# truncate or mv of one, or a cp, ln or install of one into a directory-like destination. Naming,
# reading, running and `git add` of those files pass; a segment whose command word, walked through the
# argv wrapper rows, is a reader (the pure-read list without less, rg without --pre, git
# diff/status/blame/log/show/grep without --output or -O) is exempt from the word rules, never from a redirect.
# hooks.json and guard-cmdpos.sh have no Bash rule. A cd/pushd judges its own write redirects; a cd/pushd
# into a protected directory makes every later segment subject to the same test, a later write redirect
# with no command word included.
#
# Ceilings it cannot see (disclosed): scripts, task runners and interpreters that reach out (./deploy.sh,
# make, npm run, python with boto3 or paramiko), a script written by the Write tool and then run, aliases
# and functions defined outside the command; reach outside the classes (git push over ssh, curl with a
# token, WebFetch, other MCP servers); targets set by the exported environment (DOCKER_HOST, kubectl
# current context, AWS_PROFILE, GH_HOST exported earlier) - an @default allow row trusts them; an
# allowlisted ssh alias goes wherever the user ssh_config sends it; an act verb missing from the act rows
# followed by a resource named like a read verb reads as ro (an ask, not an allow); paths built at run
# time (variables, printf, base64) can still write the protected files; an opaque scp/rsync operand with
# no `:` is read as local; the Bash route does not judge a settings.json hooks edit made in place by an
# interpreter (python, node) that names no stand-down key word - only the Edit route checks hooks rows;
# an unknown launcher (no `wrapper` row) that takes an option value before its program (`x -o v ssh`)
# is not seen, since only its first operand is tested. Protected script names are still writable through
# git checkout/restore/apply, an interpreter (perl -i, python, node), another program's own output
# option (sort -o, less -o, curl -o) or program option (git grep -O<program>), rm or mv fed their operands by xargs from stdin, a string wrapper
# (bash -c), a path built at run time, a hard link made earlier, a glob with no literal text (rm
# scripts/*), a copy into an existing directory whose name holds a dot given with no trailing slash
# (cp x/kit-gate.sh dir.d), or the removal or move of a whole directory holding them; on a case-sensitive filesystem a
# differently cased name is denied too. A class program in another case (SSH) is read as that program
# only at a command-word position; the class-word text scan of string wrappers and heredocs matches
# lowercase only, so `bash -c 'SSH host'` is not seen. Slim arm: string wrappers (bash -c, sh -c, eval,
# trap, watch, su -c, env -S, flock -c) and stdin wrappers (xargs, parallel, find -exec) are not walked
# into - a class word in such a segment (read with quotes and backslashes removed) is unsure, and one
# whose text holds $'..', a \x or octal escape, or ${..} with an operator is unsure outright; a string
# built by a plain $var or a substitution printing a name is not seen. Any remote string holding a
# metacharacter is act. A PreToolUse hook that times out gives no decision; the 20,000-character cap
# bounds parse time.
#
# Logs (${AGENT_TIERS_GUARDS_LOG:-<kit>/.state/guards.log}) never carry command text or a gh query
# string: `<ts> reach-guard deny|ask|allow: <group>/<program> <verb-row> target=<t> level=<l> why=<code>
# [agent=<type>] [sid=<id>]`, browser `<dec>: <group>/<tool> <role> target=<host|@unknown>
# level=<observe|act> why=<code>` (only the host, never a URL, path, query or tool argument),
# `deny: protected-write route=<tool> file=<basename>`, `fail-open:`,
# `note:`. Fails open only for no jq and an unparseable payload.
# Self-check: reach-guard.selfcheck.sh
set -u
[ "$(sh "$(dirname "$0")/kit-gate.sh" "$0" </dev/null 2>/dev/null)" = standdown ] && exit 0
LC_ALL=C; export LC_ALL

SELFDIR="$(CDPATH= cd -P "$(dirname "$0")" 2>/dev/null && pwd -P || true)"
[ -n "$SELFDIR" ] || SELFDIR="$(dirname "$0")"
KIT="${SELFDIR%/*}"
BASE="$KIT"
LOG="${AGENT_TIERS_GUARDS_LOG:-$KIT/.state/guards.log}"
TAB="$(printf '\t')"
INPUT="$([ -t 0 ] || cat 2>/dev/null || true)"
SID=""
AGENT=""

rg_log() { # rg_log <text after "reach-guard ">: one line, [sid=] last
  { mkdir -p "${LOG%/*}" && printf '%s reach-guard %s [sid=%s]\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$1" "$SID" >> "$LOG"; } 2>/dev/null || true
}
clean() { printf '%s' "$1" | tr -cd 'A-Za-z0-9._:@/*-' | cut -c1-80; }
agl() { [ -n "$AGENT" ] && printf ' agent=%s' "$AGENT"; return 0; }
emit() { # emit <decision> <reason>
  jq -n --arg d "$1" --arg r "$2" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: $d, permissionDecisionReason: $r}}'
}
# shsafe <word>: one shell-safe token a grant or a policy line may carry (no glob, quote, space, leading ~ or -)
shsafe() { case "$1" in "" | [~-]* | *[!A-Za-z0-9._:@%+,=~/-]*) return 1 ;; esac; return 0; }
# policy <group> <target> <read|all>: the persistent allowlist command the user types (a printf append of one
# TAB row onto allow.tsv; the target is shell-safe, so only % needs doubling for the printf format)
policy() {
  if [ "$UREF" = 1 ]; then
    printf '%s' "No allowlist row can be added: the user's reach-guard directory or allow.tsv is refused (a symlink, not owned by this user, or unreadable)."
    return 0
  fi
  pt="$(printf '%s' "$2" | sed 's/%/%%/g')"
  if [ -n "${CLAUDE_CONFIG_DIR:-}" ]; then
    pq="'$(printf '%s' "$UDIR" | sed "s/'/'\\\\''/g")'"; pf="'$(printf '%s' "$UDIR/allow.tsv" | sed "s/'/'\\\\''/g")'"
  else
    pq="~/.claude/reach-guard"; pf="$pq/allow.tsv"
  fi
  pm=""; [ -d "$UDIR" ] || pm="mkdir -p $pq; "
  printf 'POLICY CHANGE (persists, you run it): ! %sprintf %s >> %s' "$pm" "'$1\\t$pt\\t$3\\n'" "$pf"
}
# pendw <lines>: write the pending marker <sid>.<tool_use_id> atomically; first drop markers older than a
# day (a declined ask never gets its PostToolUse, so its marker would stay forever)
pendw() {
  pd="$RD/pending"
  { mkdir -p "$pd" && { find "$pd" -type f -mtime +0 -exec rm -f {} + || :; } \
    && printf '%s\n' "$1" > "$pd/.$RSID.$TUID.$$" && mv "$pd/.$RSID.$TUID.$$" "$pd/$RSID.$TUID"; } 2>/dev/null
  pr=$?
  rm -f "$pd/.$RSID.$TUID.$$" 2>/dev/null
  return $pr
}
# grpok <group>: a group name safe to write into an allowlist row ([A-Za-z0-9_-]+)
grpok() { case "$1" in "" | *[!A-Za-z0-9_-]*) return 1 ;; esac; return 0; }
# grantoff: reach-guard-grant (the PostToolUse half that writes grants) is switched off, by marker or by
# kit-gate (disabled_hooks, a group switch)
grantoff() {
  [ -e "$KIT/.state/off/reach-guard-grant" ] || { [ -n "$STATE" ] && [ -e "$STATE/off/reach-guard-grant" ]; } \
    || [ "$(sh "$SELFDIR/kit-gate.sh" "$SELFDIR/reach-guard-grant.sh" </dev/null 2>/dev/null)" = standdown ]
}

if ! command -v jq >/dev/null 2>&1; then
  SID="$(printf '%s' "$INPUT" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([A-Za-z0-9._-]*\)".*/\1/p' | head -n 1)"
  rg_log "fail-open: jq not found"
  exit 0
fi
META="$(printf '%s' "$INPUT" | jq -r '[(.tool_name // "" | tostring), (.session_id // "" | tostring)] | @tsv' 2>/dev/null)" && [ -n "$META" ] || {
  rg_log "fail-open: unparseable payload"
  exit 0
}
TOOL="${META%%"$TAB"*}"
SID="$(printf '%s' "${META#*"$TAB"}" | tr -cd 'A-Za-z0-9._-')"
case "$TOOL" in Bash | Write | Edit | MultiEdit | NotebookEdit | mcp__*) ;; *) exit 0 ;; esac

LIBOK=0
if [ -f "$SELFDIR/guard-cmdpos.sh" ] && (. "$SELFDIR/guard-cmdpos.sh") >/dev/null 2>&1; then
  . "$SELFDIR/guard-cmdpos.sh" >/dev/null 2>&1
  LIBOK=1
  for f in guard_strip_heredocs guard_split_segments_qsafe guard_argv guard_caller_agent guard_ask_decision guard_ask_prefix guard_state_dir; do
    command -v "$f" >/dev/null 2>&1 || LIBOK=0
  done
  [ -n "$(guard_ask_prefix "" subagent 2>/dev/null)" ] || LIBOK=0
fi
if [ "$LIBOK" = 1 ]; then
  AGENT="$(guard_caller_agent "$INPUT")"
  STATE="$(guard_state_dir)"
else
  AGENT="$(printf '%s' "$INPUT" | jq -r 'if ((.agent_id // "") | tostring) != "" then ((.agent_type // "") | tostring) else "" end' 2>/dev/null | tr -cd 'A-Za-z0-9._-')"
  case "$AGENT" in main | MAIN) AGENT="" ;; esac
  [ -n "$AGENT" ] || AGENT="$(printf '%s' "$INPUT" | jq -r 'if ((.agent_id // "") | tostring) != "" then "subagent" else "" end' 2>/dev/null)"
  STATE="${AGENT_TIERS_STATE_DIR:-$KIT/.state}"
  case "$STATE" in */.state) ;; *) STATE="$STATE/.state" ;; esac
fi
SUBPFX=""
[ "$LIBOK" = 1 ] && SUBPFX="$(guard_ask_prefix "" subagent 2>/dev/null)"
[ -n "$SUBPFX" ] || SUBPFX="DELEGATED AGENT: this tool call came from a sub-agent, not the session Lead. Do not retry a variant or route around it with another tool; report this text verbatim to the Lead. "
UDIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/reach-guard"

# --- path resolution (protection) --------------------------------------------------------------------
lexnorm() { # collapse //, ., .. in an absolute path
  printf '%s\n' "$1" | awk '{
    n = split($0, a, "/"); k = 0
    for (i = 1; i <= n; i++) {
      if (a[i] == "" || a[i] == ".") continue
      if (a[i] == "..") { if (k > 0) k--; continue }
      o[++k] = a[i]
    }
    s = ""; for (i = 1; i <= k; i++) s = s "/" o[i]
    print (s == "" ? "/" : s)
  }'
}
resolve() { # resolve <path>: readlink -f of the longest existing prefix, the rest appended lexically
  p="$1"
  case "$p" in "~") p="$HOME" ;; "~/"*) p="$HOME/${p#"~/"}" ;; /*) ;; *) p="${CWD:-$(pwd)}/$p" ;; esac
  p="$(lexnorm "$p")"
  d="$p"; rest=""
  while [ "$d" != / ] && [ ! -e "$d" ] && [ ! -L "$d" ]; do rest="/${d##*/}$rest"; d="${d%/*}"; [ -n "$d" ] || d=/; done
  # ponytail: readlink -f is not in every old BSD userland; the fallback resolves the directory only.
  r="$(readlink -f "$d" 2>/dev/null)" || r=""
  if [ -z "$r" ]; then
    if [ -d "$d" ]; then r="$(CDPATH= cd -P "$d" 2>/dev/null && pwd -P)"; else r="$(CDPATH= cd -P "${d%/*}/" 2>/dev/null && pwd -P)/${d##*/}"; fi
  fi
  lexnorm "${r%/}$rest"
}

lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }
protected_hit() { # protected_hit <resolved path> -> prints the protected name it falls under (any case)
  ph_p="$(lower "$1")"
  for q in "$UDIR" "$KIT/.state/reach-guard" "$STATE/reach-guard" "$KIT/data/reach-classes.tsv" "$KIT/.state/off/reach-guard" "$STATE/off/reach-guard" "$KIT/.state/off/reach-guard-grant" "$STATE/off/reach-guard-grant" \
    "$KIT/scripts/kit-gate.sh" "$KIT/install/options.tsv" "$KIT/scripts/guard-cmdpos.sh" "$KIT/hooks/hooks.json" "$KIT/scripts"; do
    for qq in "$(lexnorm "$q")" "$(resolve "$q")"; do
      ph_q="$(lower "$qq")"
      if [ "$q" = "$KIT/scripts" ]; then # only scripts/reach-guard<anything without a slash>.sh
        case "$ph_p" in "$ph_q"/reach-guard*.sh) case "${ph_p#"$ph_q"/}" in */*) ;; *) printf '%s\n' "$qq/${1##*/}"; return 0 ;; esac ;; esac
        continue
      fi
      case "$ph_p" in "$ph_q" | "$ph_q"/*) printf '%s\n' "$qq"; return 0 ;; esac
    done
  done
  return 1
}
# setbase <path>: its basename is settings*.json, any case
setbase() { case "$(lower "${1##*/}")" in settings*.json) return 0 ;; esac; return 1; }

# settings stand-down test: prints "deny" when the post-edit file trips a test the pre-edit file did not
SETJQ='
def s: if . == null then "" elif type == "array" then map(tostring) | join(" ") else tostring end;
def off(v): (v | s) as $x | ($x == "false" or $x == "0");
def listed(x): (x | s) | test("(^|[^A-Za-z0-9_-])reach-guard(-grant)?($|[^A-Za-z0-9_-])");
def akeys(o): if (o | type) == "object"
  then (o | to_entries[] | select(.key == "agent-tiers" or (.key | startswith("agent-tiers@")))) else empty end;
def opts(v): if (v | type) == "object" and (v.options | type) == "object" then v.options else {} end;
def trips: [
  (if (.env | type) == "object" then
     ((if (.env.AGENT_TIERS_OFF | tostring) == "1" then "off" else empty end),
      (.env | to_entries[]
        | select(.key | test("^(AGENT_TIERS_|CLAUDE_PLUGIN_|LD_|DYLD_)|^(CLAUDE_CONFIG_DIR|HOME|PATH)$"))
        | "env:\(.key)=\(.value | tostring)"))
   else empty end),
  (akeys(.pluginConfigs) | .key as $k | opts(.value) as $o
     | (if off($o.enabled) then "en:\($k)" else empty end),
       (if off($o.group_safety) then "gs:\($k)" else empty end),
       (if listed($o.disabled_hooks) then "dh:\($k)" else empty end)),
  (akeys(.enabledPlugins) | select(off(.value)) | "ep:\(.key)"),
  (if .disableAllHooks == true then "dah" else empty end) ];
# rgrows: one "rg:<event> TAB <matcher> TAB <command> TAB <type> TAB <timeout> TAB <async>" per hooks
# entry whose command names reach-guard
def arr(x): x | if type == "array" then .[] else empty end;
def rgrows: if (.hooks | type) == "object" then
  (.hooks | to_entries[] | .key as $e | arr(.value) | select(type == "object")
   | ((.matcher // "") | tostring) as $m | arr(.hooks) | select(type == "object")
   | select((.command | type) == "string" and (.command | contains("reach-guard")))
   | "rg:\($e)\t\($m)\t\(.command)\t\(.type // "" | tostring)\t\(.timeout // "" | tostring)\t\(.async // "" | tostring)")
  else empty end;
def keeps: [
  (akeys(.pluginConfigs) | .key as $k | opts(.value) as $o
     | select($o.group_safety != null and (off($o.group_safety) | not)) | "gsp:\($k)"),
  (if ([(.hooks // empty) | .. | strings | select(test("reach-guard($|[^-])"))] | length) > 0 then "hk" else empty end),
  (if ([(.hooks // empty) | .. | strings | select(contains("reach-guard-grant"))] | length) > 0 then "hkg" else empty end),
  rgrows ];
# an empty old_string writes new_string as the whole file (the host allows it only on an empty or absent one)
def rep1($o; $n): if $o == "" then $n else split($o) as $p
  | if ($p | length) > 1 then $p[0] + $n + ($p[1:] | join($o)) else . end end;
def repall($o; $n): if $o == "" then $n else split($o) | join($n) end;
def ed($e): if ($e.replace_all // false) == true then repall($e.old_string // ""; $e.new_string // "")
  else rep1($e.old_string // ""; $e.new_string // "") end;
($cur) as $c
| (.tool_name) as $t | .tool_input as $i
| (if $t == "Write" then ($i.content // "")
   elif $t == "Edit" then ($c | ed($i))
   elif $t == "MultiEdit" then (reduce (($i.edits // [])[]) as $e ($c; ed($e)))
   else null end) as $post
| (try ($post | fromjson) catch null) as $pj
| (try ($c | fromjson) catch {}) as $pre
| if $pj == null or ($pj | type) != "object" then ""
  else (if ($pre | type) == "object" then $pre else {} end) as $pr
  | (($pj | trips) - ($pr | trips)) as $new
  | (($pr | keeps) - ($pj | keeps)) as $lost
  | if ($new | length) > 0 or ($lost | length) > 0 then "deny" else "" end end'

prot_file() {
  FP="$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' 2>/dev/null)"
  CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)"
  [ -n "$FP" ] || exit 0
  RP="$(resolve "$FP")"
  if protected_hit "$RP" >/dev/null; then
    rg_log "deny: protected-write route=$TOOL file=$(clean "${RP##*/}")$(agl)"
    emit deny "reach-guard: $FP is protected (reach-guard's allowlist, class data, state or kill switch, reach-guard's own scripts, kit-gate.sh, the install options file, the hooks wiring or the parser library). No agent writes it, the session Lead included: the user edits it by hand outside the agent session. Do not retry a variant or route around it with another tool."
    exit 0
  fi
  # the requested or the resolved basename (a settings.json symlinked to a differently named file);
  # the content is read from the resolved path
  if setbase "$FP" || setbase "$RP"; then
    SRC="$RP"; [ -f "$SRC" ] && [ -r "$SRC" ] || SRC=/dev/null
    v="$(printf '%s' "$INPUT" | jq -r --rawfile cur "$SRC" "$SETJQ" 2>/dev/null)"
    if [ "$v" = deny ]; then
      rg_log "deny: protected-write route=$TOOL file=$(clean "${RP##*/}")$(agl)"
      emit deny "reach-guard: this edit to $FP would stand the agent-tiers guards down (AGENT_TIERS_OFF; an env key for the kit, a plugin, the loader, CLAUDE_CONFIG_DIR, HOME or PATH; enabled, group_safety or the agent-tiers plugin turned off or removed; reach-guard in disabled_hooks, or a reach-guard hooks entry removed or changed in its event, matcher or command; or disableAllHooks). That is the user's change to make by hand outside the agent session. Do not retry a variant or route around it with another tool."
    fi
  fi
  exit 0
}

case "$TOOL" in Write | Edit | MultiEdit | NotebookEdit) prot_file ;; esac

# --- class data layers (browser and Bash arms) -----------------------------------------------------
marker_note() { # marker_note <marker-name> <note text>: one breadcrumb per marker
  md="$STATE/reach-guard"
  [ -n "$STATE" ] && [ -e "$md/$1" ] && return 0
  { [ -n "$STATE" ] && mkdir -p "$md" && : > "$md/$1"; } 2>/dev/null
  rg_log "note: $2"
}
sig() { printf '%s' "$1" | cksum | awk '{print $1}'; }

# user layer, refused when a symlink or not ours
KF="$KIT/data/reach-classes.tsv"
UCF=/dev/null; UAF=/dev/null; UREF=0
if [ -e "$UDIR" ] || [ -L "$UDIR" ]; then
  if [ -L "$UDIR" ] || [ ! -O "$UDIR" ] || [ ! -d "$UDIR" ]; then
    UREF=1
    marker_note "refused.$(sig "$(ls -ldn "$UDIR" 2>/dev/null)")" "refused user dir reach-guard (symlink or not owned by this uid); its classes and allowlist are ignored"
  else
    for uf in classes allow; do
      p="$UDIR/$uf.tsv"
      [ -e "$p" ] || [ -L "$p" ] || continue
      if [ -L "$p" ] || [ ! -O "$p" ] || [ ! -f "$p" ] || [ ! -r "$p" ]; then
        [ "$uf" = allow ] && UREF=1
        marker_note "refused.$(sig "$(ls -ldn "$p" 2>/dev/null)")" "refused user file $uf.tsv (symlink, not owned by this uid, or unreadable); ignored"
      elif [ "$uf" = classes ]; then UCF="$p"; else UAF="$p"; fi
    done
  fi
fi
DATAOK=0
[ -f "$KF" ] && [ -r "$KF" ] && DATAOK=1
badnote() { # badnote kit|user|allow: one breadcrumb per file content
  case "$1" in kit) bf="$KF" ;; user) bf="$UCF" ;; *) bf="$UAF" ;; esac
  [ -r "$bf" ] && marker_note "badrow.$(cksum < "$bf" | awk '{print $1}')" "skipped bad rows in ${bf##*/} (unknown kind, wrong field count, bad option or allow row without read/all scope)"
}

# AWKLIB: the row loader and glob matcher, shared by the Bash classifier and the browser lookup.
AWKLIB='
function trim(x) { sub(/^[ \t]+/, "", x); sub(/[ \t]+$/, "", x); return x }
# gopts(s): parse a group options column (`-` or a comma list); sets OPA, OPG, OPL, restrictive when absent
function gopts(s,   n, A, i) {
  OPA = "ask"; OPG = "none"; OPL = "no"
  if (s == "-") return 1
  n = split(s, A, ",")
  for (i = 1; i <= n; i++) {
    if (A[i] ~ /^act=(deny|ask)$/) OPA = substr(A[i], 5)
    else if (A[i] ~ /^grant=(none|observe|all)$/) OPG = substr(A[i], 7)
    else if (A[i] ~ /^local=(yes|no)$/) OPL = substr(A[i], 7)
    else return 0
  }
  return 1
}
function load(f, layer,   line, nf, F, i, k, ok, key, n, A, j, fl) {
  if (f == "" || f == "/dev/null") return
  while ((getline line < f) > 0) {
    sub(/\r$/, "", line)
    if (line ~ /^[ \t]*#/ || line ~ /^[ \t]*$/) continue
    nf = split(line, F, "\t"); for (i = 1; i <= nf; i++) F[i] = trim(F[i])
    k = F[1]; ok = 1
    if (k == "group") {
      if (nf != 5 || F[2] == "" || (F[3] != "on" && F[3] != "off") || !gopts(F[4])) ok = 0
      else if (!(F[2] in GON)) { GON[F[2]] = (F[3] == "on"); G_ACT[F[2]] = OPA; G_GR[F[2]] = OPG; G_LOC[F[2]] = OPL }
    } else if (k == "mcp") {
      if (nf != 4 || F[2] == "" || F[3] == "" || F[4] !~ /^(observe|navigate|act|local)$/) ok = 0
      else { NM++; M_G[NM] = F[2]; M_RE[NM] = glob2re(F[3]); M_R[NM] = F[4] }
    } else if (k == "local-origin") {
      if (nf != 2 || F[2] ~ /^(ip:|scheme:)?$/) ok = 0
      else if (F[2] ~ /^ip:/) { NLI++; LI_RE[NLI] = glob2re(tolower(substr(F[2], 4))) }
      else if (F[2] ~ /^scheme:/) LSCH[tolower(substr(F[2], 8))] = 1
      else { NLH++; LH_RE[NLH] = glob2re(tolower(F[2])) }
    } else if (k == "prog") {
      if (nf != 4 || F[2] == "" || F[3] !~ /^[A-Za-z0-9_-]+$/ || F[4] !~ /^(remote-shell|transfer|subcmd|docker-remote|gh-api|none)$/) ok = 0
      else { key = F[2] SUBSEP F[3]; if (!(key in PSEEN)) { PSEEN[key] = 1; if (F[4] != "none") { NPR++; PRG_G[NPR] = F[2]; PRG_P[NPR] = F[3]; PRG_S[NPR] = F[4] } } }
    } else if (k == "verb") {
      if ((nf != 4 && nf != 5) || F[2] == "" || F[4] == "" || F[3] !~ /^(local|ro|act)$/) ok = 0
      else { NV++; V_P[NV] = F[2]; V_L[NV] = F[3]; V_PATH[NV] = F[4]; V_C[NV] = (nf == 5 ? F[5] : "") }
    } else if (k == "rverb") {
      if ((nf != 3 && nf != 4) || F[3] == "" || F[2] !~ /^(local|ro|act)$/) ok = 0
      else { NRV++; RV_L[NRV] = F[2]; RV_PATH[NRV] = F[3]; RV_C[NRV] = (nf == 4 ? F[4] : "") }
    } else if (k == "optarg" || k == "readopt" || k == "target" || k == "selector") {
      if (nf != 3 || F[2] == "") ok = 0
      else if (k == "optarg") OA[F[2]] = OA[F[2]] " " F[3] " "
      else if (k == "readopt") {
        n = split(F[3], A, " "); fl = " "
        for (j = 1; j <= n; j++) fl = fl (substr(A[j], 1, 3) == "-o:" ? tolower(A[j]) : A[j]) " "
        RO[F[2]] = RO[F[2]] fl
      } else if (k == "target") { if (!(F[2] in TG)) TG[F[2]] = F[3] }
      else if (!(F[2] in SEL)) SEL[F[2]] = F[3]
    } else if (k == "wrapper") {
      if ((nf != 3 && nf != 4) || F[3] == "" || F[2] !~ /^(argv|string|stdin)$/) ok = 0
      else {
        NWR++; WR_K[NWR] = F[2]; n = split(F[3], A, " "); WR_W1[NWR] = A[1]; WR_W2[NWR] = (n > 1 ? A[2] : "")
        WRW[A[1]] = 1; WR_FL[NWR] = " "; WR_SKIP[NWR] = 0; WR_STR[NWR] = ""
        n = (nf == 4 ? split(F[4], A, " ") : 0)
        for (j = 1; j <= n; j++) {
          if (A[j] ~ /^skip=[0-9]+$/) WR_SKIP[NWR] = substr(A[j], 6) + 0
          else if (A[j] ~ /^str=/) WR_STR[NWR] = substr(A[j], 5)
          else WR_FL[NWR] = WR_FL[NWR] A[j] " "
        }
      }
    } else if (k == "noexec") {
      if (nf != 2 || F[2] == "") ok = 0
      else { n = split(F[2], A, " "); for (j = 1; j <= n; j++) NOEX[A[j]] = 1 }
    } else ok = 0
    if (!ok) BAD[layer] = 1
  }
  close(f)
}
function loadallow(f,   line, nf, F, i) {
  if (f == "" || f == "/dev/null") return
  while ((getline line < f) > 0) {
    sub(/\r$/, "", line)
    if (line ~ /^[ \t]*#/ || line ~ /^[ \t]*$/) continue
    nf = split(line, F, "\t"); for (i = 1; i <= nf; i++) F[i] = trim(F[i])
    if (nf != 3 || F[1] == "" || F[2] == "" || (F[3] != "read" && F[3] != "all")) { BAD["allow"] = 1; continue }
    NAL++; AL_G[NAL] = F[1]; AL_RE[NAL] = glob2re(F[2]); AL_S[NAL] = F[3]
  }
  close(f)
}
function glob2re(g,   r, i, c, n, j, cls) {
  if (g in GRE) return GRE[g]
  r = "^"; n = length(g)
  for (i = 1; i <= n; i++) {
    c = substr(g, i, 1)
    if (c == "*") r = r ".*"
    else if (c == "?") r = r "."
    else if (c == "[") {
      j = index(substr(g, i + 1), "]")
      if (j > 1) { cls = substr(g, i + 1, j - 1); if (substr(cls, 1, 1) == "!") cls = "^" substr(cls, 2); gsub(/\\/, "\\\\", cls); r = r "[" cls "]"; i += j }
      else r = r "[[]"
    }
    else if (c == "\\") r = r "\\\\"
    else if (c == "^") r = r "\\^"
    else if (index(".$+(){}|", c)) r = r "[" c "]"
    else r = r c
  }
  GRE[g] = r "$"
  return GRE[g]
}
'
# --- browser (MCP) arm --------------------------------------------------------------------------------
# BAWK: env RG_TOOL, RG_PAGES (page map or /dev/null), RG_PID, RG_NAVT, RG_URL, RG_INIT. Prints BAD lines,
# then OUT (no class, group off, role local) or RES <group> <role> <class> <act> <grant> <local> <target>
# <target-local 0|1> <page-local 0|1> <nav url|hist|newpage|-> <allow-scope read|all|->.
BAWK="$AWKLIB"'
# url2host: begin (reach-guard.sh and reach-guard-grant.sh carry identical copies; the selfchecks compare them)
# scheme marker `scheme:<name>` for a non-web scheme, the host for http(s)/ws(s), else @unknown; blob: is
# the host of its inner URL; file: only with an empty or localhost authority; devtools: with a query is unknown
function url2host(u,   i, sc, a, j) {
  i = index(u, ":")
  if (i < 2) return "@unknown"
  sc = tolower(substr(u, 1, i - 1))
  if (sc !~ /^[a-z][a-z0-9+.-]*$/) return "@unknown"
  a = substr(u, i + 1)
  if (sc == "blob") return url2host(a)
  if (sc == "file") return (!index(a, "\\") && (tolower(a) ~ /^\/\/(localhost)?\/([^\/]|$)/ || a ~ /^\/([^\/]|$)/)) ? "scheme:file" : "@unknown"
  if (sc == "devtools" && index(a, "?")) return "@unknown"
  if (sc != "http" && sc != "https" && sc != "ws" && sc != "wss") return "scheme:" sc
  if (substr(a, 1, 2) != "//") return "@unknown"
  a = substr(a, 3)
  if (match(a, /[\/?#\\]/)) a = substr(a, 1, RSTART - 1)
  while ((j = index(a, "@")) > 0) a = substr(a, j + 1)
  if (substr(a, 1, 1) == "[") { j = index(a, "]"); if (j < 3) return "@unknown"; a = substr(a, 2, j - 2) }
  else sub(/:.*/, "", a)
  a = tolower(a); sub(/\.$/, "", a)
  if (a == "" || a !~ /^[a-z0-9._%:-]+$/) return "@unknown"
  return a
}
# url2host: end
function norm(h) { return (h ~ /^scheme:/ && !(substr(h, 8) in LSCH)) ? "@unknown" : h }
function islocal(h,   i) {
  if (h == "@unknown") return 0
  if (h ~ /^scheme:/) return (substr(h, 8) in LSCH)
  if (h ~ /^[0-9.]+$/ || index(h, ":")) for (i = 1; i <= NLI; i++) if (h ~ LI_RE[i]) return 1
  for (i = 1; i <= NLH; i++) if (h ~ LH_RE[i]) return 1
  return 0
}
# mapped(p): the page map entry for page id p; a local host the guard did not judge itself is unknown
function mapped(p,   h) {
  if (p == "" || !(p in MH)) return "@unknown"
  h = norm(MH[p])
  return (MK[p] != "pre" && islocal(h)) ? "@unknown" : h
}
BEGIN {
  load(ENVIRON["RG_UCF"], "user"); load(ENVIRON["RG_KF"], "kit"); loadallow(ENVIRON["RG_UAF"])
  for (b in BAD) print "BAD\t" b
  t = ENVIRON["RG_TOOL"]; g = ""; r = ""
  for (i = 1; i <= NM; i++) if (t ~ M_RE[i]) { g = M_G[i]; r = M_R[i]; break }
  if (g == "") {
    if (index(t, "mcp__chrome-devtools__") == 1) { g = "browser_auto"; r = "act" }
    else if (index(t, "mcp__claudecodebrowser__") == 1) { g = "browser_real"; r = "act" }
  }
  if (g == "" || r == "local" || ((g in GON) && !GON[g])) { print "OUT"; exit }
  if (!(g in GON)) { G_ACT[g] = "ask"; G_GR[g] = "none"; G_LOC[g] = "no" }
  f = ENVIRON["RG_PAGES"]
  while ((getline l < f) > 0) if (split(l, A, "\t") == 3) { MH[A[1]] = A[2]; MK[A[1]] = A[3] }
  close(f)
  p = ENVIRON["RG_PID"]; c = (r == "act" ? "act" : "observe"); h = "@unknown"; nav = "-"
  if (g == "browser_auto" && index(t, "mcp__chrome-devtools__") == 1) {
    s = substr(t, 23)
    if (s == "navigate_page") {
      ty = ENVIRON["RG_NAVT"]; u = ENVIRON["RG_URL"]
      if (ty == "" && u != "") ty = "url"
      if (ENVIRON["RG_INIT"] == "true") c = "act"
      if (ty == "url") { h = norm(url2host(u)); nav = "url" }
      else if (ty == "reload") h = mapped(p)
      else nav = "hist"
    } else if (s == "new_page") { h = norm(url2host(ENVIRON["RG_URL"])); nav = "newpage" }
    else h = mapped(p)
  }
  sc = "-"
  if (h != "@unknown") for (i = 1; i <= NAL; i++) if (AL_G[i] == g && h ~ AL_RE[i]) { sc = AL_S[i]; if (sc == "all") break }
  pl = ((p in MH) && MK[p] == "pre" && islocal(norm(MH[p]))) ? 1 : 0
  printf "RES\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n", g, r, c, G_ACT[g], G_GR[g], G_LOC[g], h, islocal(h), pl, nav, sc
}'

browser() {
  # a path-like argument (key, or the key of its enclosing array, matching path|dir|file) naming a
  # protected path or a settings*.json file: deny for every caller and role, before the role lookup
  CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)"
  BPATHS="$(printf '%s' "$INPUT" | jq -r '(.tool_input // {}) | paths(type == "string") as $p
    | select((($p | map(strings) | last) // "") | test("path|dir|file"; "i")) | getpath($p)
    | if test("[\n\r]") then "@newline@" else . end' 2>/dev/null)"
  # a relative value: the MCP server resolves it against its own process directory, which this hook does
  # not know, so it is judged against both the payload cwd and CLAUDE_PROJECT_DIR, and a `..` component
  # (which could climb anywhere from an unknown base) cannot be placed at all
  while IFS= read -r bp; do
    [ -n "$bp" ] || continue
    bph=""; bwhy="that path is protected (reach-guard's allowlist, class data, state or kill switch, or a settings file)"
    if [ "$bp" = @newline@ ]; then bph="(a path holding a line break)"; bp="a path holding a line break"
    else
      case "$bp" in
        / | /* | "~" | "~/"*) bcands="$(resolve "$bp")" ;;
        .. | ../* | */.. | */../*)
          bph=relative-dotdot bcands=""
          bwhy="it is a relative path that climbs out of its directory, which reach-guard cannot place (the browser server resolves it against its own directory), so it is treated as possibly protected" ;;
        *) bcands="$(resolve "$bp")"
          [ -n "${CLAUDE_PROJECT_DIR:-}" ] && bcands="$bcands$NLC$(resolve "$CLAUDE_PROJECT_DIR/$bp")" ;;
      esac
      while IFS= read -r RP; do
        [ -n "$RP" ] && [ -z "$bph" ] || continue
        protected_hit "$RP" >/dev/null && bph="${RP##*/}"
        setbase "$RP" && bph="${RP##*/}"
      done <<EOF
$bcands
EOF
      [ -z "$bph" ] && setbase "$bp" && bph="${bp##*/}"
    fi
    if [ -n "$bph" ]; then
      rg_log "deny: protected-write route=$TOOL file=$(clean "$bph")$(agl)"
      emit deny "reach-guard: $TOOL names $bp as a file or directory argument, and $bwhy. No agent writes it through any tool, the session Lead included: the user does it by hand outside the agent session. Do not retry a variant or route around it with another tool."
      exit 0
    fi
  done <<EOF
$BPATHS
EOF
  BJ="$(printf '%s' "$INPUT" | jq -r '[(.tool_use_id // ""), (.session_id // ""),
    (.tool_input.pageId | if type == "number" and . >= 0 and . == floor then tostring else "" end),
    (.tool_input.type // ""), ((.tool_input.initScript // "") | tostring | length > 0)]
    | .[] | tostring | gsub("[\n\r]"; " ")' 2>/dev/null)"
  { IFS= read -r TUID; IFS= read -r RSID; IFS= read -r PID; IFS= read -r NAVT; IFS= read -r INIT; } <<EOF
$BJ
EOF
  URL="$(printf '%s' "$INPUT" | jq -r '.tool_input.url // "" | tostring' 2>/dev/null)"
  SIDOK=0; case "$RSID" in "" | *[!A-Za-z0-9._-]*) ;; *) [ -n "$STATE" ] && SIDOK=1 ;; esac
  TUOK=0; case "$TUID" in "" | *[!A-Za-z0-9_-]*) ;; *) TUOK=1 ;; esac
  case "$PID" in "" | *[!0-9]*) PID="" ;; esac
  RD="$STATE/reach-guard"; PAGES=/dev/null
  [ "$SIDOK" = 1 ] && PAGES="$RD/pages.$RSID"
  # ponytail: compaction can drop a line another hook appends between the awk and the mv (that page reads unknown)
  if [ -f "$PAGES" ] && [ "$(wc -l < "$PAGES" 2>/dev/null | tr -cd 0-9)" -gt 4000 ] 2>/dev/null; then
    awk -F '\t' '{ if (!($1 in L)) O[++n] = $1; L[$1] = $0 } END { for (i = 1; i <= n; i++) print L[O[i]] }' "$PAGES" > "$PAGES.$$" 2>/dev/null \
      && mv "$PAGES.$$" "$PAGES" 2>/dev/null
    rm -f "$PAGES.$$" 2>/dev/null
  fi
  UNATT=0
  if [ "$LIBOK" = 1 ]; then
    BD="$(guard_ask_decision "$SID" "$AGENT")"; BP="$(guard_ask_prefix "$SID" "$AGENT")"
    guard_unattended "$SID" && UNATT=1
  else
    [ -n "$SID" ] && [ -n "$STATE" ] && [ -f "$STATE/unattended.$SID" ] && UNATT=1
    BD=ask; BP=""
    if [ -n "$AGENT" ]; then BD=deny; BP="$SUBPFX"
    elif [ "$UNATT" = 1 ]; then BD=deny; BP="UNATTENDED MODE: this session is flagged unattended, so a question no human is present to answer is returned as a deny. "
    fi
  fi
  BG=""; BR=act; BC=act; BH=@unknown; BACT=ask; BGR=none; BLOC=no; BTL=0; BPL=0; BNAV=-; BSC=-
  if [ "$DATAOK" = 1 ]; then
    BO="$(RG_KF="$KF" RG_UCF="$UCF" RG_UAF="$UAF" RG_TOOL="$TOOL" RG_PAGES="$PAGES" RG_PID="$PID" RG_NAVT="$NAVT" RG_URL="$URL" RG_INIT="$INIT" awk "$BAWK" </dev/null 2>/dev/null)"
    while IFS= read -r line; do
      case "$line" in
        "BAD$TAB"*) badnote "${line#BAD"$TAB"}" ;;
        OUT) exit 0 ;;
        "RES$TAB"*) IFS="$TAB" read -r _ BG BR BC BACT BGR BLOC BH BTL BPL BNAV BSC <<EOF
$line
EOF
          ;;
      esac
    done <<EOF
$BO
EOF
    WHY=external
  fi
  if [ -z "$BG" ]; then # no kit data, or the lookup failed: unknown origin, no grant, no pending marker
    case "$TOOL" in
      mcp__chrome-devtools__*) BG=browser_auto ;;
      mcp__claudecodebrowser__*) BG=browser_real ;;
      *) exit 0 ;;
    esac
    [ "$DATAOK" = 1 ] || marker_note nodata "data/reach-classes.tsv missing or unreadable: every browser call reads as an unknown page"
    BR=act; BC=act; BH=@unknown; BACT=ask; BGR=none; BLOC=no; BTL=0; BNAV=-; BSC=-; WHY=nodata
  fi
  blog() { rg_log "$1: $(clean "$BG")/$(clean "$TOOL") $BR target=$(clean "$BH") level=$BC why=$2$(agl)"; }
  TAIL="Do not retry a variant or route around it with another tool."
  if [ "$BG" != browser_auto ]; then # the user's own browser: no origin tracking, no grant, no allowlist
    T1="reach-guard: $TOOL drives the user's own logged-in browser ($BG, $BC)."
    if [ -n "$AGENT" ]; then blog deny subagent; emit deny "$SUBPFX$T1 Sub-agents never drive it; report this to the Lead. $TAIL"
    elif [ "$BC" = act ] && [ "$BACT" = deny ]; then blog deny act-deny; emit deny "$T1 This group denies act calls. An MCP call has no ! form: the operator does it by hand in the browser. $TAIL"
    elif [ "$BD" = deny ]; then blog deny unattended; emit deny "$BP$T1 It needs the operator's yes on every call. $TAIL"
    else blog ask "${WHY:-external}"; emit ask "$T1 Approve only if an agent should do this; this asks on every call; this group has no allowlist. The host's \"don't ask again\" does not stop reach-guard asking."
    fi
    exit 0
  fi
  [ "$BH" = @unknown ] && [ "$WHY" = external ] && WHY=unknown
  PLACE="$BH"; [ "$BH" = @unknown ] && PLACE="a page the guard cannot place"
  GLINE=""
  letrun() { # the call may run: page map writes now, pending marker for the PostToolUse hook
    pl="$GLINE"
    mapw() { [ "$SIDOK" = 1 ] && [ -n "$PID" ] && { mkdir -p "$RD" && printf '%s\t%s\tpre\n' "$PID" "$1" >> "$PAGES"; } 2>/dev/null; }
    # a navigation never places the page here: an ask can be declined (no PostToolUse) and a navigation
    # can fail, so the page reads unknown until the PostToolUse hook sees a successful listing response
    case "$BNAV" in
      url)
        mapw @unknown
        [ -n "$PID" ] && [ "$BH" != @unknown ] && pl="$pl${pl:+$NLC}map$TAB$PID$TAB$BH" ;;
      hist) mapw @unknown ;;
      newpage) pl="$pl${pl:+$NLC}newpage$TAB$BH" ;;
    esac
    [ -n "$pl" ] && [ "$SIDOK" = 1 ] && [ "$TUOK" = 1 ] || return 0
    pendw "$pl"
    return 0
  }
  covers() { [ "$BGR" = all ] || { [ "$BGR" = observe ] && [ "$BC" = observe ]; }; }
  if [ "$BTL" = 1 ] && [ "$BLOC" = yes ]; then letrun; exit 0; fi
  if [ -n "$AGENT" ]; then
    blog deny subagent
    emit deny "${SUBPFX}reach-guard: sub-agents never drive a browser page outside this machine ($TOOL on $PLACE, $BC). Report this to the Lead. $TAIL"
    exit 0
  fi
  if [ "$BH" != @unknown ] && { [ "$BSC" = all ] || { [ "$BSC" = read ] && [ "$BC" = observe ]; }; }; then
    letrun; blog allow allowlist
    emit allow "reach-guard: $TOOL on $BH ($BC) is covered by the user's reach-guard allowlist."
    exit 0
  fi
  if [ "$UNATT" = 0 ] && [ "$BH" != @unknown ] && [ "$SIDOK" = 1 ] && covers \
    && grep -qxF "$BH$TAB$BC" "$RD/grant.$RSID" 2>/dev/null; then
    letrun
    emit allow "reach-guard: $TOOL on $BH ($BC) is covered by a grant approved earlier in this session."
    exit 0
  fi
  if [ "$BC" = act ] && [ "$BACT" = deny ]; then
    blog deny act-deny
    POL=""
    [ "$BH" != @unknown ] && shsafe "$BH" && grpok "$BG" && POL=" $(policy "$BG" "$BH" all)"
    emit deny "reach-guard: $TOOL on $PLACE is an act call, and the $BG group denies act calls on pages outside this machine. An MCP call has no ! form: the operator does it by hand in the browser. $TAIL$POL"
    exit 0
  fi
  T1="reach-guard: $TOOL on $PLACE is an $BC call on a page outside this machine."
  if [ "$BD" = deny ]; then
    blog deny unattended
    emit deny "$BP$T1 It needs the operator's yes. $TAIL"
    exit 0
  fi
  T2="This asks on every call."
  if [ "$BH" != @unknown ] && covers && [ "$SIDOK" = 1 ] && [ "$TUOK" = 1 ]; then
    GLINE="grant$TAB$BH$TAB$BC$TAB$TOOL"
    T2="Approving lets the rest of this session's $BC calls on $BH through without asking."
  fi
  POL="No allowlist row can cover a page the guard cannot place."
  if [ "$BH" != @unknown ]; then
    POL="No allowlist row can cover it."
    PL=read; [ "$BC" = act ] && PL=all
    shsafe "$BH" && grpok "$BG" && POL="$(policy "$BG" "$BH" "$PL")"
  fi
  letrun; blog ask "$WHY"
  emit ask "$T1 $T2 The host's \"don't ask again\" saves a rule for every site and does not stop reach-guard asking. $POL"
  exit 0
}
NLC="$(printf '\nx')"; NLC="${NLC%x}"
case "$TOOL" in mcp__*) browser ;; esac

# --- Bash ---------------------------------------------------------------------------------------------
CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)"
[ -n "$CMD" ] || exit 0

handback() { # handback <group> <program> <verb> <target> <level text>
  hb="reach-guard: $1/$2${3:+ $3} to ${4:-?} is $5. Not run by an agent. RUN (one-off, you run it): ! $CMD"
  case "$CMD" in *"
"*) hb="$hb
The command spans several lines: save it as a script and run that instead." ;; esac
  printf '%s\nDo not retry a variant or route around it with another tool.' "$hb"
}

# AWK: the classifier. Modes: coarse (stdin = raw command: class word and raw protection scan only) and
# cls (stdin = the token stream built below; env RG_CMD = raw command).
AWK="$AWKLIB"'
function hascw(t,   n, A, i) {
  n = split(t, A, /[^A-Za-z0-9_-]+/)
  for (i = 1; i <= n; i++) if (A[i] in CW) { CWW = A[i]; return 1 }
  return 0
}
function base(x) { sub(/\/+$/, "", x); sub(/.*\//, "", x); return x }
function stripver(x,   i) { i = index(substr(x, 2), "@"); if (i) x = substr(x, 1, i); return x }

# ---- protection ----
function protword(w,   n, C, i, c, re, lit) {
  if (index(tolower(w), "reach-classes")) return base(w)
  n = split(tolower(w), C, "/")
  for (i = 1; i <= n; i++) {
    c = C[i]
    if (c == "reach-guard" || c == "reach-guard-grant") return base(w)
    if (c ~ /[*?[]/) {
      lit = c; gsub(/\[[^]]*\]/, "", lit); gsub(/[*?[]/, "", lit)
      if (lit == "") continue
      re = glob2re(c)
      if ("reach-guard" ~ re || "reach-guard-grant" ~ re || "reach-classes.tsv" ~ re) return base(w)
    }
  }
  return ""
}
function settings_hit(t,   n, A, i) {
  if (!index(tolower(t), "settings")) return 0
  n = split(t, A, /[^A-Za-z0-9_]+/)
  for (i = 1; i <= n; i++) {
    if (A[i] ~ /^(AGENT_TIERS_OFF|CLAUDE_PLUGIN_ROOT|pluginConfigs|disabled_hooks|group_safety|enabled|disableAllHooks)$/) return 1
    if (A[i] ~ /^CLAUDE_PLUGIN_OPTION_/) return 1
  }
  return 0
}
function wredir(t, p,   op, tg) {
  op = p; sub(/ .*/, "", op); tg = p; sub(/^[^ ]* /, "", tg)
  if (op !~ />/) return 0
  if (op ~ />&$/ && t == "r" && tg ~ /^([0-9]+|-)$/) return 0
  if (t == "r" && tg == "/dev/null") return 0
  return 1
}
function cmdword(s,   i, t, p) {
  for (i = 1; i <= TN[s]; i++) {
    t = TT[s, i]; p = TP[s, i]
    if (t == "g" || t == "r" || t == "R") continue
    if (p ~ /^[A-Za-z_][A-Za-z0-9_]*=/) continue
    if (t == "o") { CWI = i; return "" }
    if (p in KW) continue
    CWI = i; return p
  }
  CWI = 0; return ""
}
function pureread(s, cw,   i, t, p, nx) {
  if (cw == "") return 0
  if (!(cw in PRL) && cw != "rg" && cw != "git") return 0
  nx = ""
  for (i = 1; i <= TN[s]; i++) {
    t = TT[s, i]; p = TP[s, i]
    if ((t == "r" || t == "R") && wredir(t, p)) return 0
    if (t != "w" && t != "o") continue
    if (p == "tee" || p == "-i") return 0
    # less -o / --log-file writes a log file; a + word runs a less command
    if (cw == "less" && (p ~ /^-[A-Za-z]*[oO]/ || p ~ /^--(log-file|LOG-FILE)/ || p ~ /^\+/)) return 0
    if (i > CWI && nx == "" && p !~ /^-/) nx = p
    if (cw == "rg" && p ~ /^--pre/) return 0
    if (cw == "git" && (p ~ /^--output/ || (p ~ /^--out/ && index("--output", p) == 1))) return 0
  }
  if (cw == "git" && nx !~ /^(diff|status|blame)$/) return 0
  return 1
}
function issetjson(w) { return tolower(base(w)) ~ /^settings.*\.json$/ }
# isprotname(w): the basename (any case) is reach-guard*.sh, kit-gate.sh or options.tsv, or a glob word
# with a literal residue that matches one of those names
function isprotname(w,   b, lit, re) {
  b = tolower(base(w))
  if (b ~ /^reach-guard.*\.sh$/ || b == "kit-gate.sh" || b == "options.tsv") return 1
  if (b !~ /[*?[]/) return 0
  lit = b; gsub(/\[[^]]*\]/, "", lit); gsub(/[*?[]/, "", lit)
  if (lit == "") return 0
  re = glob2re(b)
  return ("reach-guard.sh" ~ re || "reach-guard-grant.sh" ~ re || "reach-guard.selfcheck.sh" ~ re || "kit-gate.sh" ~ re || "options.tsv" ~ re)
}
function isk(w, nm) { return nm ? isprotname(w) : issetjson(w) }
# setw(s, nm, part): basename of a file this segment writes (redirect target, cp/mv/ln/install
# destination, tee operand, dd of=, sed -i operand); nm 0 = settings*.json, nm 1 = a protected script
# name (verb matched in any case); part "r" = redirects only, "w" = the verb words only, "" = both;
# every verb word in the segment is tried, not only the first (an earlier `dd` or `sed` operand, as in
# `env -u dd cp x settings.json`, must not hide the real verb); empty when none
function setw(s, nm, part,   i, t, p, vb, r) {
  for (i = 1; i <= TN[s]; i++) {
    t = TT[s, i]; p = TP[s, i]
    if (part != "w" && (t == "r" || t == "R") && wredir(t, p)) { sub(/^[^ ]* /, "", p); if (isk(p, nm)) return base(p) }
  }
  if (part == "r") return ""
  for (i = 1; i <= TN[s]; i++) {
    vb = tolower(base(TP[s, i]))
    if (TT[s, i] == "w" && vb ~ /^(cp|mv|ln|install|tee|dd|sed)$/ && (r = setw1(s, nm, i, vb)) != "") return r
  }
  return ""
}
# setw1(s, nm, a, c): the destination rules of setw for the verb word c at position a
function setw1(s, nm, a, c,   i, t, p, last, sedi, tdir) {
  last = ""; sedi = 0; tdir = 0
  for (i = a + 1; i <= TN[s]; i++) {
    t = TT[s, i]; p = TP[s, i]
    if (t != "w" && t != "o") continue
    if (p == ";" || p == "+") continue   # find -exec ... \; or +
    if (tdir) { tdir = 0; if (isk(p, nm)) return base(p); continue }
    if (c != "dd" && p ~ /^-/) {
      if (p == "-t" || p == "--target-directory") tdir = 1
      else if (p ~ /^--target-directory=/ && isk(substr(p, 20), nm)) return base(p)
      if (p ~ /^-[A-Za-z]*i/ || p ~ /^--in-place/) sedi = 1
      continue
    }
    if (c == "dd") { if (p ~ /^of=/ && isk(substr(p, 4), nm)) return base(p); continue }
    if ((c == "tee" || (c == "sed" && sedi)) && isk(p, nm)) return base(p)
    last = p
  }
  if (c ~ /^(cp|mv|ln|install)$/ && isk(last, nm)) return base(last)
  return ""
}
# namew(s): basename of a protected script name this segment removes or moves (an rm, unlink, shred,
# truncate or mv word anywhere, then a non-option operand) or copies into a directory-like destination
# (a cp, ln or install word anywhere, a non-last operand, a last operand ending in /, . or .. or with no
# dot in its basename, or -t/--target-directory); empty when none
function namew(s,   i, t, p, b, a, c, n, OP, tdir, tany, last, nm) {
  a = 0; c = 0
  for (i = 1; i <= TN[s]; i++) {
    if (TT[s, i] != "w") continue
    b = tolower(base(TP[s, i]))
    if (!a && b ~ /^(rm|unlink|shred|truncate|mv)$/) a = i
    if (!c && b ~ /^(cp|ln|install)$/) c = i
  }
  if (a) for (i = a + 1; i <= TN[s]; i++) {
    t = TT[s, i]; p = TP[s, i]
    if ((t == "w" || t == "o") && p !~ /^-/ && isprotname(p)) return base(p)
  }
  if (!c) return ""
  n = 0; tdir = 0; tany = 0
  for (i = c + 1; i <= TN[s]; i++) {
    t = TT[s, i]; p = TP[s, i]
    if (t != "w" && t != "o") continue
    if (p == ";" || p == "+") continue
    if (tdir) { tdir = 0; continue }
    if (p ~ /^-/) {
      # --target-directory and its unique prefixes (--t...), or a short cluster holding t
      if (p ~ /^--t/) { nm = p; sub(/=.*/, "", nm); if (index("--target-directory", nm) == 1) { tany = 1; if (nm == p) tdir = 1 } }
      else if (p ~ /^-[A-Za-z]*t$/) { tdir = 1; tany = 1 }
      else if (p ~ /^-[A-Za-z]*t/) tany = 1
      continue
    }
    n++; OP[n] = p
  }
  if (n == 0) return ""
  if (tany) { for (i = 1; i <= n; i++) if (isprotname(OP[i])) return base(OP[i]); return "" }
  last = OP[n]
  if (last ~ /\/$/ || base(last) == "." || base(last) == ".." || base(last) !~ /\./)
    for (i = 1; i < n; i++) if (isprotname(OP[i])) return base(OP[i])
  return ""
}
# rdrseg(s): the command word of the segment (CWI, set by cmdword), walked through the argv wrapper rows the
# way classify walks them, is a known reader: cat head tail wc ls stat file diff cmp md5sum sha256sum
# grep, rg with no --pre word, git diff/status/blame/log/show/grep with no --output or -O word. A string or stdin
# wrapper, an opaque or grouping word, or a failed walk is no reader. Leaves WT, WP, NW, NAS, ASG and
# possibly L, WHY, WHYT, PRG, GRP, CWW set; classify resets every one of them before reading it.
function rdrseg(s,   k, b, j, m, two, mstr, mstd, marg, strip, p, nx) {
  if (!CWI) return 0
  split("", WT); split("", WP); split("", ASG); NW = 0; NAS = 0
  for (k = CWI; k <= TN[s]; k++) { if (TT[s, k] == "r" || TT[s, k] == "R") continue; NW++; WT[NW] = TT[s, k]; WP[NW] = TP[s, k] }
  while (NW > 0 && WT[NW] == "g" && WP[NW] == ")") NW--
  k = 1; strip = 0
  while (1) {
    if (k > NW || WT[k] != "w") return 0
    b = base(WP[k]); if (strip) b = stripver(b)
    if (!(b in CW) && !(b in WRW) && !(b in NOEX) && ((tolower(b) in CW) || (tolower(b) in WRW))) b = tolower(b)
    two = 0; mstr = 0; mstd = 0; marg = 0
    for (j = 1; j <= NWR; j++) {
      if (WR_W1[j] != b) continue
      if (WR_W2[j] != "") {
        if (substr(WR_W2[j], 1, 1) == "-") {
          for (m = k + 1; m <= NW; m++) if (WP[m] == WR_W2[j]) break
          if (m > NW) continue
        } else if (!(WT[k + 1] == "w" && WP[k + 1] == WR_W2[j])) continue
      }
      if (WR_K[j] == "string") { if (!mstr && strpresent(j, k)) mstr = j }
      else if (WR_K[j] == "stdin") { if (!mstd) mstd = j }
      else if (WR_W2[j] != "") { if (!two) { marg = j; two = 1 } }
      else if (!two && !marg) marg = j
    }
    if (mstr || mstd) return 0
    if (!marg) break
    k = argv_walk(marg, k, s)
    if (k < 0 || k > NW) return 0
    strip = (b ~ /^(npx|bunx|yarn|pnpm)$/ || WR_W2[marg] == "dlx" || (b == "npm" && WR_W2[marg] == "exec") || (b == "bun" && WR_W2[marg] == "x"))
  }
  b = tolower(b)
  if (b == "less") return 0
  if (b in PRL) return 1
  if (b != "rg" && b != "git") return 0
  nx = ""
  for (m = k + 1; m <= NW; m++) {
    if (WT[m] != "w" && WT[m] != "o") continue
    p = WP[m]
    if (b == "rg" && p ~ /^--pre/) return 0
    if (b == "git") {
      sub(/=.*/, "", p)
      if (p ~ /^--out/ && (index("--output", p) == 1 || p ~ /^--output/)) return 0
      # git grep -O / --open-files-in-pager runs a program on the matching files
      if (p ~ /^-[^-]*O/ || p ~ /^--op/) return 0
      if (nx == "" && p !~ /^-/) nx = p
    }
  }
  return (b == "rg" || nx ~ /^(diff|status|blame|log|show|grep)$/)
}
# haswr(s): the segment holds a write redirect
function haswr(s,   i) {
  for (i = 1; i <= TN[s]; i++) if ((TT[s, i] == "r" || TT[s, i] == "R") && wredir(TT[s, i], TP[s, i])) return 1
  return 0
}
function prot_scan(   s, prev, carry, hit, i, t, w, cw, tw, sw) {
  prev = ""; carry = 0
  for (s = 1; s <= NS; s++) {
    if (SR[s] != prev) { carry = 0; prev = SR[s] }
    if (TN[s] == 0) continue
    hit = ""
    for (i = 1; i <= TN[s]; i++) {
      t = TT[s, i]; w = TP[s, i]
      if (t == "r" || t == "R") sub(/^[^ ]* /, "", w)
      else if (t != "w" && t != "o") continue
      if ((hit = protword(w)) != "") break
    }
    if (hit == "" && settings_hit(ST[s])) hit = "settings"
    cw = cmdword(s)
    if (cw == "cd" || cw == "pushd") {
      # the write redirects of the cd segment itself are judged before it is skipped
      for (i = 1; i <= TN[s]; i++) {
        t = TT[s, i]; w = TP[s, i]
        if ((t != "r" && t != "R") || !wredir(t, w)) continue
        sub(/^[^ ]* /, "", w)
        if (protword(w) != "") { print "PROT\t" protword(w); return 1 }
        if (issetjson(w)) { print "PROTS\t" base(w); return 1 }
        if (isprotname(w)) { print "PROT\t" base(w); return 1 }
      }
      if (carry && haswr(s)) { print "PROT\t(cwd)"; return 1 }
      tw = ""
      for (i = CWI + 1; i <= TN[s]; i++) if ((TT[s, i] == "w" || TT[s, i] == "o") && TP[s, i] !~ /^-/) { tw = TP[s, i]; break }
      if (hit != "" || tolower(tw) ~ /\.state\/off\/?$/) carry = 1
      continue
    }
    if (hit == "" && carry && (CWI > 0 || haswr(s))) hit = "(cwd)"
    if (hit != "" && !pureread(s, cw)) { print "PROT\t" hit; return 1 }
    if ((sw = setw(s, 0, "")) != "") { print "PROTS\t" sw; return 1 }
    if ((sw = setw(s, 1, "r")) != "") { print "PROT\t" sw; return 1 }
    if (((sw = setw(s, 1, "w")) != "" || (sw = namew(s)) != "") && !rdrseg(s)) { print "PROT\t" sw; return 1 }
  }
  return 0
}

# ---- classification ----
# segtext(s): the segment text with every substitution placeholder followed by its original body
function segtext(s,   t, x, id) {
  t = ST[s]; x = ST[s]
  while (match(t, /\$__RG[0-9]+_/)) {
    id = substr(t, RSTART + 5, RLENGTH - 6)
    if (id in BO) x = x " " BO[id]
    t = substr(t, RSTART + RLENGTH)
  }
  return x
}
function segcw(s) { return hascw(segtext(s)) }
# segcwn(s): the same test on a copy with quote characters and backslashes removed (s"s"h, s\sh)
function segcwn(s,   x) { x = segtext(s); gsub(/["\047\\]/, "", x); return hascw(x) }
function unsure_cw(s, why, whyt) {
  if (segcw(s)) { L = "unsure"; WHY = why; WHYT = whyt; PRG = CWW; GRP = CWG[CWW] }
}
function unsure_cwn(s, why, whyt) {
  if (segcwn(s)) { L = "unsure"; WHY = why; WHYT = whyt; PRG = CWW; GRP = CWG[CWW] }
}
function unsure_now(s, why, whyt) {
  L = "unsure"; WHY = why; WHYT = whyt
  if (segcwn(s)) { PRG = CWW; GRP = CWG[CWW] } else { PRG = "opaque"; GRP = "unknown" }
}
# hidden(x): text that spells a word the guard cannot read: ANSI-C $'..', a \x or octal escape, ${..} with an operator
function hidden(x) {
  return (index(x, "$\047") || x ~ /\\x[0-9A-Fa-f]/ || x ~ /\\[0-7]/ || x ~ /\$\{[^}]*[^A-Za-z0-9_}]/)
}
# opaque_cmd(s, p): an opaque word at command position. A plain parameter (a dollar sign and a bare name or digit, braced or not), a
# leading ~ path, and a path whose directory part holds only plain parameters and whose last component
# is literal ("$HOME/bin/tool") keep the class-word rule; anything else (substitution, $'..', ${..} with an operator,
# a glob) is unsure whatever its text.
function opaque_cmd(s, p) {
  if (p == "[" || p == "[[") return 0
  if (p !~ /\$__RG/ && (p ~ /^\$([A-Za-z_][A-Za-z0-9_]*|[0-9]|\{[A-Za-z_][A-Za-z0-9_]*\})$/ || p ~ /^~[^$`*?[{]*$/ || \
      (p ~ /^(\$([A-Za-z_][A-Za-z0-9_]*|\{[A-Za-z_][A-Za-z0-9_]*\})|[A-Za-z0-9_.~\/-])*\/[A-Za-z0-9_.-]+$/)))
    unsure_cw(s, "opaque-command", "the command word is a variable")
  else unsure_now(s, "opaque-command", "the command word is built at run time")
  return 1
}
function setl(l, why, whyt) { L = l; WHY = why; WHYT = whyt }
function isprogword(x) { x = base(stripver(x)); return (x in CW) || (x in WRW) }
function strpresent(j, k,   n, A, a, m, p, c) {
  n = split(WR_STR[j], A, ",")
  for (a = 1; a <= n; a++) {
    if (A[a] == "rest" || A[a] == "first") return 1
    for (m = k + 1; m <= NW; m++) {
      if (WT[m] != "w") continue
      p = WP[m]
      if (p == A[a]) return 1
      if (substr(A[a], 1, 2) == "--" && index(p, A[a] "=") == 1) return 1
      if (length(A[a]) == 2 && p ~ /^-[A-Za-z]+$/ && index(substr(p, 2), substr(A[a], 2, 1))) return 1
    }
  }
  return 0
}
function argv_walk(j, k, s,   skip, f, p, nm) {
  k += (WR_W2[j] != "" && substr(WR_W2[j], 1, 1) != "-") ? 2 : 1
  skip = WR_SKIP[j]; f = WR_FL[j]
  while (k <= NW) {
    if (WT[k] == "o" || WT[k] == "g") { if (skip > 0) { skip--; k++; continue } return k }
    p = WP[k]
    if (p ~ /^[A-Za-z_][A-Za-z0-9_]*=/) { NAS++; ASG[NAS] = p; k++; continue }
    if (p == "--") { k++; while (skip > 0 && k <= NW) { skip--; k++ } return k }
    if (p ~ /^-./) {
      nm = p; if (index(nm, "=")) nm = substr(nm, 1, index(nm, "=") - 1)
      if (index(f, " " nm " ")) { k += (nm == p && (substr(p, 1, 2) == "--" || length(p) == 2)) ? 2 : 1; continue }
      if (substr(p, 1, 2) != "--" && index(f, " " substr(p, 1, 2) " ")) { k++; continue }
      if (index(p, "=") && substr(p, 1, 2) == "--") { k++; continue }
      if (k + 1 <= NW && WT[k + 1] == "w" && WP[k + 1] !~ /^-/ && (isprogword(WP[k + 1]) || skip > 0)) { k++; continue }
      unsure_cw(s, "wrapper-option", "an option of " WR_W1[j] " this guard does not know")
      return -1
    }
    if (skip > 0) { skip--; k++; continue }
    return k
  }
  return k
}
function addflag(nm, v, vo) { NFN++; FN[NFN] = nm; FV[NFN] = v; FVO[NFN] = vo; FPOS[NFN] = NP }
function parse_args(prog, k,   m, t, p, oa, nm, v, vo, letters, li, fl, unl, endopt, took) {
  NP = 0; NFN = 0; NFT = 0; unl = 0; endopt = 0; oa = " " OA[prog] " "
  split("", POS); split("", POSO); split("", UB); split("", FN); split("", FV); split("", FVO); split("", FPOS); split("", FT)
  for (m = k + 1; m <= NW; m++) {
    t = WT[m]; p = WP[m]
    if (t == "g") continue
    if (!endopt && t == "w" && p == "--") { endopt = 1; continue }
    if (!endopt && t == "w" && p ~ /^-./) {
      if (substr(p, 1, 2) == "--") {
        nm = p; v = ""; vo = 0
        if (index(p, "=")) { nm = substr(p, 1, index(p, "=") - 1); v = substr(p, index(p, "=") + 1) }
        else if (index(oa, " " nm " ")) { m++; v = WP[m]; vo = (WT[m] == "o") }
        else unl = 1
        addflag(nm, v, vo); continue
      }
      nm = p; if (index(p, "=")) nm = substr(p, 1, index(p, "=") - 1)
      NFT++; FT[NFT] = nm
      if (nm != p && index(oa, " " nm " ")) { addflag(nm, substr(p, index(p, "=") + 1), 0); continue }
      if (index(oa, " " p " ")) { m++; addflag(p, WP[m], WT[m] == "o"); continue }
      if (length(p) > 2 && index(oa, " " substr(p, 1, 2) " ")) { addflag(substr(p, 1, 2), substr(p, 3), 0); continue }
      letters = substr(p, 2); took = 0
      for (li = 1; li <= length(letters); li++) {
        fl = "-" substr(letters, li, 1)
        if (index(oa, " " fl " ")) {
          v = substr(letters, li + 1); vo = 0
          if (v == "") { m++; v = WP[m]; vo = (WT[m] == "o") }
          addflag(fl, v, vo); took = 1; break
        }
        addflag(fl, "", 0)
      }
      if (!took) unl = 1
      continue
    }
    NP++; POS[NP] = p; POSO[NP] = (t == "o"); UB[NP] = unl
  }
}
function hasflag(f,   j) {
  if (substr(f, 1, 2) == "--") {
    for (j = 1; j <= NFN; j++) {
      if (FN[j] == f) return 1
      if (substr(FN[j], 1, 2) == "--" && length(FN[j]) >= 5 && index(f, FN[j]) == 1) return 1
    }
    return 0
  }
  if (length(f) == 2) { for (j = 1; j <= NFN; j++) if (FN[j] == f) return 1; return 0 }
  for (j = 1; j <= NFT; j++) if (FT[j] == f) return 1
  return 0
}
function condok(ai,   n, A, a, c, v, m) {
  if (CURC == "") return 1
  n = split(CURC, A, ",")
  for (a = 1; a <= n; a++) {
    c = A[a]; v = substr(c, index(c, "=") + 1)
    if (c ~ /^if=/) { if (!hasflag(v)) return 0 }
    else if (c ~ /^unless=/) { if (hasflag(v)) return 0 }
    else if (c ~ /^maxpos=/) { if (NP - ai + 1 > v + 0) return 0 }
    else if (c ~ /^pos=/) { for (m = ai; m <= NP; m++) if (POS[m] !~ glob2re(v)) return 0 }
  }
  return 1
}
function pm(pi, ai, aft,   k, r) {
  if (pi > PMN) return condok(ai) ? ai : -1
  if (PP[pi] == "$") return (ai == NP + 1) ? pm(pi + 1, ai, aft) : -1
  if (PP[pi] == "**") {
    for (k = ai; k <= NP + 1; k++) { r = pm(pi + 1, k, 1); if (r >= 0) return r }
    return -1
  }
  if (ai > NP) return -1
  if (aft && UB[ai]) return -1
  if (POS[ai] !~ glob2re(PP[pi])) return -1
  return pm(pi + 1, ai + 1, aft)
}
function match_rows(remote, prog,   j, n, r, m, lvl) {
  n = remote ? NRV : NV
  for (j = 1; j <= n; j++) {
    if (remote) { PMN = split(RV_PATH[j], PP, " "); CURC = RV_C[j]; lvl = RV_L[j]; VPL = RV_PATH[j] }
    else { if (V_P[j] != prog) continue; PMN = split(V_PATH[j], PP, " "); CURC = V_C[j]; lvl = V_L[j]; VPL = V_PATH[j] }
    r = pm(1, 1, 0)
    if (r < 0) continue
    VPR = ""
    for (m = 1; m < r && m <= 6; m++) VPR = VPR (m > 1 ? " " : "") POS[m]
    for (m = 1; m < r; m++) if (POSO[m]) return "unsure"
    return lvl
  }
  VPL = "-"; VPR = ""
  return ""
}
function flagval(name, globalonly,   j) {
  for (j = 1; j <= NFN; j++) if (FN[j] == name && (!globalonly || FPOS[j] == 0)) { FVOUT = FVO[j]; return FV[j] }
  return ""
}
function settarget(prog, globalonly,   n, A, a, v, j, found) {
  TGT = prog ":@default"
  n = split(TG[prog], A, " ")
  for (a = 1; a <= n; a++) {
    found = 0
    for (j = 1; j <= NFN; j++) if (FN[j] == A[a] && (!globalonly || FPOS[j] == 0)) { found = j; break }
    if (found) { TGT = prog ":" FV[found]; if (FVO[found]) NOALLOW = 1; break }
  }
  n = split(SEL[prog], A, " ")
  for (a = 1; a <= n; a++) {
    if (A[a] ~ /=$/) { for (j = 1; j <= NAS; j++) if (index(ASG[j], A[a]) == 1) NOALLOW = 1 }
    else for (j = 1; j <= NFN; j++) if (FN[j] == A[a]) NOALLOW = 1
  }
}
function cleanhost(h) { sub(/^ssh:\/\//, "", h); sub(/.*@/, "", h); sub(/[:\/].*/, "", h); return h }
function ssh_flag(prog, fl, v, vo,   key) {
  if (fl == "-F" || fl == "-J") { SSHUNS = "ssh " fl; return }
  if (fl == "-o") {
    if (vo) { SSHUNS = "an opaque -o value"; return }
    key = v; sub(/[ \t=].*/, "", key); key = tolower(key)
    if (key ~ /^(hostname|proxycommand|proxyjump|localcommand|permitlocalcommand)$/) { SSHUNS = "ssh -o " key; return }
    if (!index(RO[prog], " -o:" key " ")) SSHACT = "ssh -o " key
    return
  }
  if (!index(RO[prog], " " fl " ")) SSHACT = "ssh " fl
}
function shape_ssh(s, prog, k,   m, t, p, host, hosto, term, letters, li, c, fl, v, vo, oa, rs, A, n, lvl) {
  if (prog == "mosh") {
    for (m = k + 1; m <= NW; m++) if (WP[m] !~ /^-/) { TGT = cleanhost(WP[m]); break }
    setl("act", "mosh", "mosh opens a remote session"); return
  }
  oa = " " OA[prog] " "; SSHUNS = ""; SSHACT = ""; host = ""; hosto = 0; term = 0
  for (m = k + 1; m <= NW; m++) {
    t = WT[m]; p = WP[m]
    if (!term && t == "w" && p == "--") { term = 1; if (host != "") { m++; break } continue }
    if (!term && t == "w" && p ~ /^-./) {
      letters = substr(p, 2)
      for (li = 1; li <= length(letters); li++) {
        c = substr(letters, li, 1); fl = "-" c
        if (c == "V" || c == "G") { L = "local"; return }
        if (index(oa, " " fl " ")) {
          v = substr(letters, li + 1); vo = 0
          if (v == "") { m++; v = WP[m]; vo = (WT[m] == "o") }
          ssh_flag(prog, fl, v, vo); break
        }
        ssh_flag(prog, fl, "", 0)
      }
      continue
    }
    if (host != "") break
    host = p; hosto = (t == "o")
    if (term) { m++; break }
  }
  if (host == "") { setl("unsure", "no-host", "no destination host"); return }
  if (hosto) { setl("unsure", "opaque-host", "the host is built at run time"); return }
  TGT = cleanhost(host)
  if (SSHUNS != "") { setl("unsure", "ssh-option", SSHUNS " (never allowed)"); NOALLOW = 1; return }
  if (m > NW) { setl("unsure", "interactive", "no remote command (an interactive session, or commands from stdin)"); return }
  rs = ""
  for (n = m; n <= NW; n++) {
    if (WT[n] == "o") { setl("unsure", "opaque-remote", "the remote command holds a word built at run time"); return }
    rs = rs (n > m ? " " : "") WP[n]
  }
  if (SSHACT != "") { setl("act", "ssh-option", SSHACT " is not a read-shape flag"); return }
  if (rs !~ /^[A-Za-z0-9_.\/:=@%+,~ -]*$/) { setl("act", "remote-meta", "the remote command holds a shell metacharacter"); return }
  NW = split(rs, A, " ")
  for (n = 1; n <= NW; n++) { WT[n] = "w"; WP[n] = A[n] }
  parse_args("", 0)
  lvl = match_rows(1, "")
  if (lvl == "ro") setl("ro", "rverb-ro", "the remote command (" VPR ") matches the read-only row " VPL)
  else setl("act", "rverb-act", "the remote command is not on the read-only list")
}
function shape_transfer(s, prog, k,   m, t, p, oa, endopt, letters, li, fl, c, pre, h, nt, nop, fop, fopo) {
  oa = " " OA[prog] " "; endopt = 0; nt = 0; TGT = ""; nop = 0
  for (m = k + 1; m <= NW; m++) {
    t = WT[m]; p = WP[m]
    if (t == "g") continue
    if (!endopt && t == "w" && p == "--") { endopt = 1; continue }
    if (!endopt && t == "w" && p ~ /^-./) {
      if (substr(p, 1, 2) == "--") { if (!index(p, "=") && index(oa, " " p " ")) m++; continue }
      if (index(oa, " " p " ")) { m++; continue }
      letters = substr(p, 2)
      for (li = 1; li <= length(letters); li++) {
        fl = "-" substr(letters, li, 1)
        if (index(oa, " " fl " ")) { if (li == length(letters)) m++; break }
      }
      continue
    }
    nop++; if (nop == 1) { fop = p; fopo = (t == "o") }
    if (t == "o") { if (index(p, ":")) { setl("unsure", "opaque-operand", "a transfer operand is built at run time"); return } continue }
    h = ""
    if (p ~ /^rsync:\/\//) { h = substr(p, 9); sub(/\/.*/, "", h) }
    else if ((c = index(p, ":")) > 0) {
      pre = substr(p, 1, c - 1)
      if (pre !~ /\// && p !~ /^(\/|\.\/|\.\.\/|~)/) h = pre
      else continue
      if (h == "") h = "?"
    } else continue
    h = cleanhost(h); if (h == "") h = "?"
    nt++; TGT = TGT (nt > 1 ? " " : "") h
  }
  # sftp and sshfs reach out with any operand (a bare host included), not only host:path
  if (nt == 0 && nop > 0 && prog ~ /^(sftp|sshfs)$/) {
    if (fopo) { setl("unsure", "opaque-operand", "the " prog " host is built at run time"); return }
    TGT = cleanhost(fop); if (TGT == "") TGT = "?"
    nt = 1
  }
  if (nt == 0) return
  setl("act", "transfer-remote", "a transfer with a remote operand")
}
function shape_subcmd(s, prog, k,   lvl) {
  parse_args(prog, k)
  lvl = match_rows(0, prog)
  if (lvl == "local") { L = "local"; return }
  settarget(prog, 0)
  if (lvl == "") { setl("unsure", "no-verb-row", "no verb row matches"); return }
  if (lvl == "unsure") { setl("unsure", "opaque-verb", "a verb word is built at run time"); return }
  setl(lvl, "verb-" lvl, "verb row " VPL " is " lvl)
}
function shape_docker(s, prog, k,   j, trig, lvl) {
  parse_args(prog, k); trig = 0
  for (j = 1; j <= NFN; j++) if (FPOS[j] == 0 && FN[j] ~ /^(-H|--host|--context|-c)$/) trig = 1
  for (j = 1; j <= NAS; j++) if (ASG[j] ~ /^DOCKER_(HOST|CONTEXT)=/) trig = 1
  if (POS[1] == "context" && POS[2] ~ /^(use|create|update|rm|import)$/) trig = 1
  if (!trig) return
  lvl = match_rows(0, prog)
  if (lvl == "local") { L = "local"; return }
  settarget(prog, 1)
  if (lvl == "") { setl("unsure", "no-verb-row", "no verb row matches"); return }
  if (lvl == "unsure") { setl("unsure", "opaque-verb", "a verb word is built at run time"); return }
  setl(lvl, "verb-" lvl, "docker against a remote daemon, verb row " VPL " is " lvl)
}
function shape_ghapi(s,   ep, h, j, n, v) {
  VPL = "api"
  h = flagval("--hostname", 0); if (h == "") h = "github.com"
  settarget("gh", 0)
  if (NP < 2) { TGT = h; setl("unsure", "no-endpoint", "no endpoint"); return }
  if (POSO[2]) { TGT = h; setl("unsure", "opaque-endpoint", "the endpoint is built at run time"); return }
  ep = POS[2]; sub(/^\/+/, "", ep); sub(/\?.*/, "", ep)
  TGT = h "/" ep; VPR = "api " ep
  if (ep == "graphql") { setl("act", "graphql", "graphql is act in this guard"); return }
  for (j = 1; j <= NFN; j++) {
    n = FN[j]
    if (n == "-X" || n == "--method") { v = toupper(FV[j]); if (v != "GET" || FVO[j]) { setl("act", "gh-method", "method " v); return } }
    if (n ~ /^(-f|-F|--field|--raw-field|--input)$/) { setl("act", "gh-body", "a body flag makes it a POST"); return }
    if (!index(" " RO["gh"] " ", " " n " ")) { setl("act", "gh-flag", "flag " n " is not a read-shape flag"); return }
  }
  setl("ro", "gh-get", "a GET of " ep " with no body flag")
}
function classify(s,   n, i, t, p, k, j, b, strip, two, mstr, mstd, marg, m, op) {
  L = "none"; GRP = ""; PRG = ""; VPL = "-"; VPR = ""; TGT = ""; NOALLOW = 0; WHY = ""; WHYT = ""; ISCMD = 0; NAS = 0
  n = TN[s]; split("", WT); split("", WP); split("", ASG)
  for (i = 1; i <= n; i++) if (TT[s, i] == "u") { ISCMD = 1; unsure_cwn(s, "unbalanced", "an unbalanced quote or substitution"); return }
  i = 1
  while (i <= n) {
    t = TT[s, i]; p = TP[s, i]
    if (t == "g" || t == "r" || t == "R") { i++; continue }
    if (p ~ /^[A-Za-z_][A-Za-z0-9_]*=/) { NAS++; ASG[NAS] = p; i++; continue }
    if (t == "o" && opaque_cmd(s, p)) { ISCMD = 1; return }
    if (p in KW) { i++; continue }
    if (p == "for" || p == "select") { i++; while (i <= n && !(TT[s, i] == "w" && TP[s, i] == "do")) i++; i++; continue }
    if (p == "case") {
      i++; while (i <= n && !(TT[s, i] == "w" && TP[s, i] == "in")) i++; i++
      while (i <= n && !(TT[s, i] == "g" && TP[s, i] == ")")) i++; i++; continue
    }
    if (p == "function" || (TT[s, i + 1] == "g" && TP[s, i + 1] == "(" && TT[s, i + 2] == "g" && TP[s, i + 2] == ")")) {
      ISCMD = 1; unsure_cwn(s, "function-def", "a function definition"); return
    }
    if (HASCASE[SR[s]] && TT[s, i + 1] == "g" && TP[s, i + 1] == ")") { i += 2; continue }
    break
  }
  if (i > n) return
  ISCMD = 1
  NW = 0
  for (k = i; k <= n; k++) { if (TT[s, k] == "r" || TT[s, k] == "R") continue; NW++; WT[NW] = TT[s, k]; WP[NW] = TP[s, k] }
  while (NW > 0 && WT[NW] == "g" && WP[NW] == ")") NW--
  if (NW == 0) return
  k = 1; strip = 0
  while (1) {
    if (WT[k] == "g") { unsure_cw(s, "opaque-command", "a grouping word in command position"); return }
    if (WT[k] == "o" && opaque_cmd(s, WP[k])) return
    b = base(WP[k]); if (strip) b = stripver(b)
    # a case-insensitive filesystem runs SSH as ssh
    if (!(b in CW) && !(b in WRW) && !(b in NOEX) && ((tolower(b) in CW) || (tolower(b) in WRW))) b = tolower(b)
    if (b == "command" && (WP[k + 1] == "-v" || WP[k + 1] == "-V")) return
    two = 0; mstr = 0; mstd = 0; marg = 0
    for (j = 1; j <= NWR; j++) {
      if (WR_W1[j] != b) continue
      if (WR_W2[j] != "") {
        if (substr(WR_W2[j], 1, 1) == "-") {
          for (m = k + 1; m <= NW; m++) if (WP[m] == WR_W2[j]) break
          if (m > NW) continue
        } else if (!(WT[k + 1] == "w" && WP[k + 1] == WR_W2[j])) continue
      }
      if (WR_K[j] == "string") { if (!mstr && strpresent(j, k)) mstr = j }
      else if (WR_K[j] == "stdin") { if (!mstd) mstd = j }
      else if (WR_W2[j] != "") { if (!two) { marg = j; two = 1 } }
      else if (!two && !marg) marg = j
    }
    if (mstr || mstd) {
      if (hidden(segtext(s))) { unsure_now(s, "hidden-string", b " is given an escaped or expanded string this guard cannot read"); return }
      if (mstr) unsure_cwn(s, "string-wrapper", b " runs a command string this guard does not read into")
      else unsure_cwn(s, "stdin-wrapper", b " runs commands built from its input")
      return
    }
    if (!marg) break
    k = argv_walk(marg, k, s)
    if (k < 0 || k > NW) return
    strip = (b ~ /^(npx|bunx|yarn|pnpm)$/ || WR_W2[marg] == "dlx" || (b == "npm" && WR_W2[marg] == "exec") || (b == "bun" && WR_W2[marg] == "x"))
  }
  if (b ~ /^(bash|sh|zsh|dash|ksh)$/) {
    for (m = k + 1; m <= NW; m++) {
      if (WT[m] == "w" && (WP[m] == "-c" || WP[m] ~ /^-[A-Za-z]*c[A-Za-z]*$/)) { if (hidden(segtext(s))) unsure_now(s, "hidden-string", b " -c is given an escaped or expanded string"); else unsure_cwn(s, "string-wrapper", b " -c runs a command string this guard does not read into"); return }
    }
    for (m = k + 1; m <= NW; m++) if (WT[m] != "g" && WP[m] !~ /^[-+]/) return
    if (RAWCW) { L = "unsure"; WHY = "stdin-shell"; WHYT = "a shell reading commands from a pipe or heredoc"; PRG = RAWCWW; GRP = CWG[RAWCWW] }
    return
  }
  # a launcher this guard does not know, whose first positional is a class program: unsure
  if (!(b in CW) && !(b in WRW) && !(b in NOEX)) {
    for (m = k + 1; m <= NW; m++) if (WT[m] != "g" && WP[m] !~ /^-/) break
    if (m <= NW && WT[m] == "w" && (base(stripver(WP[m])) in CW)) {
      PRG = base(stripver(WP[m])); GRP = CWG[PRG]
      setl("unsure", "launcher", b " is not a known wrapper and its first operand is " PRG)
    }
    return
  }
  gapi = ""; gs = ""; ss = ""
  for (j = 1; j <= NPR; j++) {
    if (PRG_P[j] != b || !GON[PRG_G[j]]) continue
    if (PRG_S[j] == "gh-api") { if (gapi == "") gapi = PRG_G[j] }
    else if (gs == "") { gs = PRG_G[j]; ss = PRG_S[j] }
  }
  if (gapi == "" && gs == "") return
  PRG = b
  if (gapi != "") {
    parse_args(b, k)
    if (POS[1] == "api") { GRP = gapi; shape_ghapi(s); return }
  }
  if (gs == "") return
  GRP = gs
  if (ss == "remote-shell") shape_ssh(s, b, k)
  else if (ss == "transfer") shape_transfer(s, b, k)
  else if (ss == "docker-remote") shape_docker(s, b, k)
  else shape_subcmd(s, b, k)
}
# covered(r): every target allowlisted, or (ro only) an exact (group, target) session grant; XGU[r] = a grant was used
function covered(r,   n, A, a, j, ok) {
  XGU[r] = 0
  if (XL[r] != "ro" && XL[r] != "act") return 0
  if (XNA[r]) return 0
  n = split(XT[r], A, " ")
  if (n == 0) return 0
  for (a = 1; a <= n; a++) {
    ok = 0
    for (j = 1; j <= NAL; j++) if (AL_G[j] == XG[r] && A[a] ~ AL_RE[j] && (AL_S[j] == "all" || XL[r] == "ro")) { ok = 1; break }
    if (!ok && XL[r] == "ro" && ((XG[r] SUBSEP A[a]) in RGR)) { ok = 1; XGU[r] = 1 }
    if (!ok) { XUNC[r] = A[a]; return 0 }
  }
  return 1
}
# shsafe(x): one shell-safe token (same test as the shell-side shsafe)
function shsafe(x) { return x ~ /^[A-Za-z0-9._:@%+,=~\/-]+$/ && x !~ /^[~-]/ }
# fs(x): one DEC field, TAB, CR and LF made spaces
function fs(x) { gsub(/[\t\r\n]/, " ", x); return x }
function addres(l, g, p, vpl, vpr, tg, na, why, whyt) {
  NRES++; XL[NRES] = l; XG[NRES] = g; XP[NRES] = p; XVL[NRES] = vpl; XVR[NRES] = vpr; XT[NRES] = tg
  XNA[NRES] = na; XW[NRES] = why; XWT[NRES] = whyt; XUNC[NRES] = ""
}
function hd_rule(c,   n, LN, i, line, tag, body, dash, uq, seg, rest, cand) {
  n = split(c, LN, "\n"); tag = ""
  for (i = 1; i <= n; i++) {
    line = LN[i]
    if (tag != "") {
      cand = line; if (dash) sub(/^\t+/, "", cand)
      if (cand == tag) { if (uq && (index(body, "$(") || index(body, "`")) && hascw(body)) return 1; tag = "" }
      else body = body "\n" line
      continue
    }
    if (match(line, /<<-?[ \t]*([A-Za-z_][A-Za-z0-9_]*|\047[^\047]*\047|"[^"]*")/) && substr(line, RSTART + 2, 1) != "<" && (RSTART == 1 || substr(line, RSTART - 1, 1) != "<")) {
      seg = substr(line, RSTART, RLENGTH)
      dash = (seg ~ /^<<-/); rest = seg; sub(/^<<-?[ \t]*/, "", rest)
      uq = (rest !~ /^[\047"]/); gsub(/^[\047"]|[\047"]$/, "", rest); tag = rest; body = ""
    }
  }
  if (tag != "" && uq && (index(body, "$(") || index(body, "`")) && hascw(body)) return 1
  return 0
}
BEGIN {
  split("if then elif else fi do done while until time in esac ! { } ( )", A, " "); for (i in A) KW[A[i]] = 1
  split("cat head tail less wc ls stat file diff cmp md5sum sha256sum grep", A, " "); for (i in A) PRL[A[i]] = 1
  load(ENVIRON["RG_UCF"], "user"); load(ENVIRON["RG_KF"], "kit"); loadallow(ENVIRON["RG_UAF"])
  # session grants for read-only Bash reach: `<group> TAB <target>`, exact strings (RG_RGF is /dev/null unless attended Lead)
  f = ENVIRON["RG_RGF"]
  if (f != "" && f != "/dev/null") { while ((getline l < f) > 0) if (split(l, A, "\t") == 2 && A[1] != "" && A[2] != "") RGR[A[1] SUBSEP A[2]] = 1; close(f) }
  for (i = 1; i <= NPR; i++) if (GON[PRG_G[i]] && !(PRG_P[i] in CW)) { CW[PRG_P[i]] = 1; CWG[PRG_P[i]] = PRG_G[i] }
  if (builtin) {
    split("ssh autossh mosh scp rsync sftp sshfs", A, " "); for (i in A) { CW[A[i]] = 1; CWG[A[i]] = "remote_shell" }
    split("kubectl aws gcloud wrangler terraform docker", A, " "); for (i in A) { CW[A[i]] = 1; CWG[A[i]] = "cloud" }
    CW["gh"] = 1; CWG["gh"] = "gh_api"
  }
  for (b in BAD) print "BAD\t" b
  if (mode == "coarse") RS = "\032"
}
mode == "coarse" {
  n = split($0, A, /[ \t\n;&|<>()"\047`=]+/)
  for (i = 1; i <= n; i++) if (protword(A[i]) != "") { print "PROT\t" protword(A[i]); exit }
  if (settings_hit($0)) { print "PROT\tsettings"; exit }
  for (i = 1; i <= n; i++) if (issetjson(A[i]) && tolower($0) ~ />|(^|[^A-Za-z0-9_-])(cp|mv|ln|install|tee|dd|sed)([^A-Za-z0-9_-]|$)/) { print "PROTS\t" base(A[i]); exit }
  for (i = 1; i <= n; i++) if (isprotname(A[i]) && tolower($0) ~ />|(^|[^A-Za-z0-9_-])(cp|mv|ln|install|tee|dd|sed|rm|unlink|shred|truncate)([^A-Za-z0-9_-]|$)/) { print "PROT\t" base(A[i]); exit }
  if (hascw($0)) print "CW\t" CWW "\t" CWG[CWW]
  exit
}
/^R\t/ { CUR = substr($0, 3); next }
/^S\t/ { NS++; SR[NS] = CUR; ST[NS] = substr($0, 3); TN[NS] = 0; next }
/^B\t/ { p = substr($0, 3); j = index(p, "\t"); BO[substr(p, 1, j - 1)] = substr(p, j + 1); next }
/^C\t/ { p = substr($0, 3); j = index(p, "\t"); NCAP++; CAPT[NCAP] = substr(p, j + 1); next }
NS > 0 { TN[NS]++; TT[NS, TN[NS]] = substr($0, 1, 1); TP[NS, TN[NS]] = substr($0, 2); if (substr($0, 1, 1) == "w" && substr($0, 2) == "case") HASCASE[SR[NS]] = 1 }
END {
  if (mode != "cls") exit
  if (prot_scan()) exit
  RAWT = ENVIRON["RG_CMD"]; gsub(/["\047\\]/, "", RAWT)
  RAWCW = hascw(ENVIRON["RG_CMD"]) || hascw(RAWT); RAWCWW = CWW
  if (hd_rule(ENVIRON["RG_CMD"])) addres("unsure", CWG[CWW], CWW, "-", "", "", 1, "heredoc-subst", "a heredoc body runs a substitution next to a class word")
  OTHER = 0; WRX = 0
  for (s = 1; s <= NS; s++) {
    for (i = 1; i <= TN[s]; i++) if ((TT[s, i] == "r" || TT[s, i] == "R") && wredir(TT[s, i], TP[s, i])) WRX = 1
    classify(s)
    if (L == "ro" || L == "act" || L == "unsure") addres(L, GRP, PRG, VPL, VPR, TGT, NOALLOW || L == "unsure", WHY, WHYT)
    else if (ISCMD) OTHER = 1
  }
  for (i = 1; i <= NCAP; i++) if (hascw(CAPT[i])) addres("unsure", CWG[CWW], CWW, "-", "", "", 1, "depth-cap", "substitutions nested deeper than 3 levels")
  if (NRES == 0) exit
  dec = ""; d = 0
  for (r = 1; r <= NRES; r++) if ((XL[r] == "act" || XL[r] == "unsure") && !covered(r)) { dec = "deny"; d = r; break }
  if (!d) for (r = 1; r <= NRES; r++) if (XL[r] == "ro" && !covered(r)) { dec = "ask"; d = r; break }
  if (!d) { if (OTHER || WRX) dec = "none"; else dec = "allow"; d = 1 }
  tg = XUNC[d]; if (tg == "") { tg = XT[d]; sub(/ .*/, "", tg) }
  # gu: an allow that used a session grant; mg/mt: the one (group, target) an approved ask may grant;
  # pol: the deciding result may take an allowlist row (allowable, one shell-safe target)
  gu = 0; mg = "-"; mt = "-"; np = 0; okm = 1
  if (dec == "allow") for (r = 1; r <= NRES; r++) if (XGU[r]) gu = 1
  if (dec == "ask") {
    for (r = 1; r <= NRES; r++) {
      if (XL[r] != "ro" || covered(r)) continue
      if (XNA[r]) { okm = 0; break }
      n = split(XT[r], A, " ")
      if (n == 0) { okm = 0; break }
      for (a = 1; a <= n; a++) if (!((XG[r] SUBSEP A[a]) in MP)) { MP[XG[r] SUBSEP A[a]] = 1; np++; mg = XG[r]; mt = A[a] }
    }
    if (!okm || np != 1 || !shsafe(mg) || !shsafe(mt)) { mg = "-"; mt = "-" }
  }
  pol = (!XNA[d] && shsafe(XG[d]) && XG[d] ~ /^[A-Za-z0-9_-]+$/ && shsafe(tg) && XT[d] == tg) ? 1 : 0
  # a TAB, CR or LF inside a word (a quoted target or path) would shift the shell-side field split
  printf "DEC\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n", dec, XL[d], fs(XG[d] == "" ? "-" : XG[d]), fs(XP[d] == "" ? "-" : XP[d]), fs(XVL[d]), fs(XVR[d] == "" ? "-" : XVR[d]), fs(tg == "" ? "-" : tg), fs(XT[d] == "" ? "-" : XT[d]), gu, fs(mg), fs(mt), pol, fs(XW[d]), fs(XWT[d])
}'

# Substitution extraction: top-level $( ), backticks, <( ) and >( ) bodies become `$__RG<id>_` words,
# each body a record of its own (depth cap 3). Output: R <id> <text> / B <id> <original body> / C <id>
# <capped body>, newlines as GS and tabs as US inside a field.
SUBS='
BEGIN { RS = "\032"; SQ = "\047"; DQ = "\042" }
function enc(x) { gsub(/\n/, "\035", x); gsub(/\t/, "\037", x); return x }
function pclose(s, p,   n, d, q, ch) {
  n = length(s); d = 1; q = 0
  while (p <= n) {
    ch = substr(s, p, 1)
    if (q == 1) { if (ch == SQ) q = 0 }
    else if (ch == "\\") p++
    else if (q == 2) { if (ch == DQ) q = 0 }
    else if (ch == SQ) q = 1
    else if (ch == DQ) q = 2
    else if (ch == "(") d++
    else if (ch == ")") { d--; if (d == 0) return p }
    p++
  }
  return 0
}
function bqclose(s, p,   n, ch) {
  n = length(s)
  while (p <= n) { ch = substr(s, p, 1); if (ch == "\\") p++; else if (ch == "`") return p; p++ }
  return 0
}
function push(b) { NID++; Q[NID] = b; QD[NID] = CURD + 1; return NID }
function ext(s,   n, i, q, ch, out, e, id) {
  n = length(s); i = 1; q = 0; out = ""
  while (i <= n) {
    ch = substr(s, i, 1)
    if (q == 1) { out = out ch; if (ch == SQ) q = 0; i++; continue }
    if (ch == "\\") { out = out substr(s, i, 2); i += 2; continue }
    if ((ch == "$" || (q == 0 && (ch == "<" || ch == ">"))) && substr(s, i + 1, 1) == "(") {
      e = pclose(s, i + 2)
      if (e) { id = push(substr(s, i + 2, e - i - 2)); out = out "$__RG" id "_"; i = e + 1; continue }
    }
    if (ch == "`") {
      e = bqclose(s, i + 1)
      if (e) { id = push(substr(s, i + 1, e - i - 1)); out = out "$__RG" id "_"; i = e + 1; continue }
    }
    if (q == 2) { out = out ch; if (ch == DQ) q = 0; i++; continue }
    if (ch == SQ) q = 1; else if (ch == DQ) q = 2
    out = out ch; i++
  }
  return out
}
{
  NID = 0; Q[0] = $0; QD[0] = 0
  for (qi = 0; qi <= NID; qi++) {
    CURD = QD[qi]
    if (CURD > 3) { print "C\t" qi "\t" enc(Q[qi]); continue }
    if (qi > 0) print "B\t" qi "\t" enc(Q[qi])
    print "R\t" qi "\t" enc(ext(Q[qi]))
  }
}'

deny_setwrite() { # deny_setwrite <basename>: a Bash write onto a settings*.json file
  rg_log "deny: protected-write route=Bash file=$(clean "$1")$(agl)"
  emit deny "reach-guard: this command writes a settings file ($1) from Bash, where reach-guard cannot judge whether the new content stands the agent-tiers guards down. Edit settings files with the Edit tool instead, so the change can be judged before it lands. Do not retry a variant or route around it with another tool."
  exit 0
}

coarse() { # coarse <why-code> <why-text> <note|"">: protection raw scan, then class word -> unsure
  kf="$KF"; bi=0
  [ "$DATAOK" = 1 ] || { kf=/dev/null; bi=1; }
  out="$(printf '%s' "$CMD" | RG_KF="$kf" RG_UCF="$UCF" RG_UAF=/dev/null awk -v mode=coarse -v builtin="$bi" "$AWK" 2>/dev/null)"
  case "$out" in
    *"PROTS$TAB"*)
      f="${out##*PROTS"$TAB"}"; deny_setwrite "${f%%"
"*}" ;;
    *"PROT$TAB"*)
      f="${out##*PROT"$TAB"}"; f="${f%%"
"*}"
      rg_log "deny: protected-write route=Bash file=$(clean "$f")$(agl)"
      emit deny "reach-guard: this command touches reach-guard's own allowlist, class data, state or kill switch, reach-guard's own scripts, kit-gate.sh, the install options file, or a settings stand-down key ($f), outside a pure read. No agent changes those, the session Lead included: the user does it by hand outside the agent session. Do not retry a variant or route around it with another tool."
      exit 0 ;;
    *"CW$TAB"*)
      l="${out##*CW"$TAB"}"; l="${l%%"
"*}"
      w="${l%%"$TAB"*}"; g="${l#*"$TAB"}"
      [ -n "$3" ] && rg_log "note: $3"
      rg_log "deny: $(clean "$g")/$(clean "$w") - target=- level=unsure why=$1$(agl)"
      r="$(handback "$g" "$w" "" "" "unsure: $2")"
      [ -n "$AGENT" ] && r="$SUBPFX$r"
      emit deny "$r"
      exit 0 ;;
  esac
  exit 0
}

[ "$LIBOK" = 1 ] || coarse "fallback" "guard-cmdpos.sh is missing or stale, so the command cannot be parsed" "guard-cmdpos.sh missing or stale: class-word fallback"
[ "$DATAOK" = 1 ] || coarse "fallback" "the kit class data is missing, so the command cannot be classified" "data/reach-classes.tsv missing or unreadable: built-in program list fallback"
[ "${#CMD}" -le 20000 ] || coarse "length-cap" "the command is longer than 20,000 characters" ""
case "$CMD" in *"$(printf '\035')"* | *"$(printf '\037')"*) coarse "control-byte" "the command holds a 0x1D or 0x1F control byte" "" ;; esac

# session grants (read-only Bash reach): honoured only for the attended Lead with an id-shaped session_id
BJ="$(printf '%s' "$INPUT" | jq -r '[(.tool_use_id // ""), (.session_id // "")] | .[] | tostring | gsub("[\n\r]"; " ")' 2>/dev/null)"
{ IFS= read -r TUID; IFS= read -r RSID; } <<EOF
$BJ
EOF
SIDOK=0; case "$RSID" in "" | *[!A-Za-z0-9._-]*) ;; *) [ -n "$STATE" ] && SIDOK=1 ;; esac
TUOK=0; case "$TUID" in "" | *[!A-Za-z0-9_-]*) ;; *) TUOK=1 ;; esac
RD="$STATE/reach-guard"; RGF=/dev/null
[ "$SIDOK" = 1 ] && [ "$(guard_ask_decision "$SID" "$AGENT")" = ask ] && RGF="$RD/rgrant.$RSID"

C2="$(guard_strip_heredocs "$CMD")"
OUT="$(printf '%s' "$C2" | awk "$SUBS" 2>/dev/null | while IFS="$TAB" read -r k id rest; do
  case "$k" in
    (R)
      printf 'R\t%s\n' "$id"
      t="$(printf '%s' "$rest" | tr '\035\037' '\n\t')"
      guard_split_segments_qsafe "$t" | while IFS= read -r seg; do
        printf 'S\t%s\n' "$seg"
        guard_argv "$seg"
      done ;;
    (*) printf '%s\t%s\t%s\n' "$k" "$id" "$rest" ;;
  esac
done | RG_CMD="$CMD" RG_KF="$KF" RG_UCF="$UCF" RG_UAF="$UAF" RG_RGF="$RGF" awk -v mode=cls -v builtin=0 "$AWK" 2>/dev/null)"

DEC=""
while IFS= read -r line; do
  case "$line" in
    "BAD$TAB"*) badnote "${line#BAD"$TAB"}" ;;
    "PROTS$TAB"*) deny_setwrite "${line#PROTS"$TAB"}" ;;
    "PROT$TAB"*)
      f="${line#PROT"$TAB"}"
      rg_log "deny: protected-write route=Bash file=$(clean "$f")$(agl)"
      emit deny "reach-guard: this command writes to or acts on reach-guard's own allowlist, class data, state or kill switch, reach-guard's own scripts, kit-gate.sh, the install options file, or a settings stand-down key ($f), and it is not a pure read. No agent changes those, the session Lead included: the user does it by hand outside the agent session. Do not retry a variant or route around it with another tool."
      exit 0 ;;
    "DEC$TAB"*) DEC="${line#DEC"$TAB"}" ;;
  esac
done <<EOF
$OUT
EOF
[ -n "$DEC" ] || exit 0

IFS="$TAB" read -r D_DEC D_LVL D_GRP D_PRG D_VPL D_VPR D_TGT D_TGTS D_GU D_MG D_MT D_POL D_WHY D_WHYT <<EOF
$DEC
EOF
[ "$D_DEC" = none ] && exit 0
[ "$D_VPR" = - ] && D_VPR=""
[ "$D_TGTS" = - ] && D_TGTS=""

logdec() { rg_log "$1: $(clean "$D_GRP")/$(clean "$D_PRG") $(clean "$D_VPL") target=$(clean "$D_TGT") level=$D_LVL why=$(clean "$D_WHY")$(agl)"; }
case "$D_LVL" in
  act) LT="act ($D_WHYT)" ;;
  unsure) LT="unsure: $D_WHYT" ;;
  *) LT="read-only ($D_WHYT), which needs the operator's yes" ;;
esac

case "$D_DEC" in
  deny)
    r="$(handback "$D_GRP" "$D_PRG" "$D_VPR" "$D_TGTS" "$LT")"
    [ -n "$AGENT" ] && r="$SUBPFX$r"
    logdec deny; emit deny "$r" ;;
  ask)
    d="$(guard_ask_decision "$SID" "$AGENT")"
    if [ "$d" = deny ]; then
      r="$(guard_ask_prefix "$SID" "$AGENT")$(handback "$D_GRP" "$D_PRG" "$D_VPR" "$D_TGTS" "$LT")"
      logdec deny; emit deny "$r"
    else
      # an approved ask on exactly one shell-safe (group, target) leaves a pending rgrant line for
      # reach-guard-grant.sh (PostToolUse runs only when the call ran, so a declined ask grants nothing)
      YES="Yes covers this call only."
      if [ "$D_MG" != - ] && [ "$D_MT" != - ] && [ -z "$AGENT" ] && [ "$SIDOK" = 1 ] && [ "$TUOK" = 1 ] \
        && shsafe "$D_MG" && shsafe "$D_MT" && ! grantoff; then
        pendw "rgrant$TAB$D_MG$TAB$D_MT$TAB$(clean "$D_PRG")" \
          && YES="Yes lets the rest of this session's read-only $D_MG calls to $D_MT through without asking."
      fi
      POL="No allowlist row can cover it."
      [ "$D_POL" = 1 ] && shsafe "$D_GRP" && grpok "$D_GRP" && shsafe "$D_TGT" && POL="$(policy "$D_GRP" "$D_TGT" read)"
      logdec ask
      emit ask "reach-guard: $D_GRP/$D_PRG${D_VPR:+ $D_VPR} to ${D_TGTS:-?} reaches another machine or account. It counted as read-only because $D_WHYT. $YES The host's \"don't ask again\" does not stop reach-guard asking. $POL"
    fi ;;
  allow)
    if [ -n "$AGENT" ]; then
      logdec deny
      emit deny "$SUBPFX$(handback "$D_GRP" "$D_PRG" "$D_VPR" "$D_TGTS" "allowlisted for the Lead, but sub-agents never reach other machines or accounts")"
    elif [ "$D_GU" = 1 ]; then
      D_WHY=grant; logdec allow
      emit allow "reach-guard: $D_GRP/$D_PRG to ${D_TGTS:-?} is covered by a grant approved earlier in this session."
    else
      logdec allow
      emit allow "reach-guard: $D_GRP/$D_PRG to ${D_TGTS:-?} is covered by the user's reach-guard allowlist."
    fi ;;
esac
exit 0

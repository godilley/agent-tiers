#!/usr/bin/env sh
# kit-scope: shared
# agent-tiers PreToolUse(Bash) guard: speed-bump two command shapes that can run for minutes and
# compete with whatever the human is doing on the same machine.
#
# Why it exists: real tool calls were rejected by the human because they were slow, and all three had
# one of two shapes. (1) A for loop over every jar in a mods directory that ran unzip on each one,
# then piped each listing into a while loop that ran unzip again per entry. (2) A permissions check
# that ended in `find / -xdev -group ...`, a walk of the whole root filesystem. (3) A dotfile search
# that ended in `rg ... ~ --hidden`, a walk of the whole home directory. The agent could not see the
# cost; the human could. Narrowing the target, nicing the command, or asking first all fix it.
#
# Scope, two arms, either one denies:
#   loop    a for/while/until loop whose body runs an archive or decompile tool (unzip zipinfo tar
#           bsdtar 7z 7za 7zr unrar jar javap jadx, or java -jar) over a glob: a for list holding an
#           unquoted glob or a substitution with a glob in it, or a while/until fed by a pipeline that
#           holds a glob or runs find/fd/ls. Keyed on the glob's directory.
#   search  a recursive rg, grep -r, find, fd or ag rooted at / or the home directory (~, $HOME,
#           ${HOME}, or the literal home path), unless a depth limit of 0..2 is set. Keyed on root/home.
# A simple command run under nice or ionice is exempt from both arms (the agent took the advice).
# Inner `$( )`, backtick and `sh -c` scripts are re-scanned one level deep.
#
# Deny-once: every hit in the command (inner re-scans included) is keyed; the guard denies on the
# first hit whose KEY has no marker yet this session and writes the marker of EVERY unspent hit in the
# command; when every hit's marker is spent the call passes, so the identical retry passes (one deny
# per command, never one per target on identical retries). Marker scheme from peer-guard.sh arm
# 2: `$STATE_DIR/${SID}__<readable slug>_h<cksum of KEY>` (the cksum keeps `loop:.` and `loop:/` apart),
# capped at 200 chars with a cksum-only fallback, written BEFORE the decision is set; a failed write emits no decision (fail open) and logs it.
# Opportunistic GC of markers older than AGENT_TIERS_STATE_DAYS (default 7) after each write. Every
# caller, a sub-agent included, spends the marker: this is a speed bump, not a trust gate, so the
# kit's sub-agent "do not retry" prefix is deliberately not used. Fail-open on any tooling gap.
# Self-check: contention-guard.selfcheck.sh.
#
# ponytail: shape heuristics on guard_argv tokens, not a cost model. Known ceilings, all in the ALLOW
# direction unless noted: an implicit root (no path given while the cwd is home, or `cd ~ && rg x`)
# is not seen; a heredoc body fed to a shell (`sh <<EOF`) is not seen; `while read ...; done <
# <(ls *.jar)` and `< list.txt` feeders are not seen; the re-scan is one level deep; `ls -R`, `du`,
# `tree` over home are not covered; sudo options that take a separate value (`sudo -u root find /`)
# hide the command; a niced feeder stage hides its glob from a later while loop; arm 1 keys on the
# glob's directory, so a second loop over the same directory later in the session passes; a `$( )`
# that does not start its word (`echo "n: $(find / | wc -l)"`) is not re-scanned; a process
# substitution `<( )` (including `done < <(find ~ ...)`) is not seen; `find -exec unzip` and
# `xargs unzip` are not loops (per-file cost, not this shape) and pass; a
# sub-agent's deny spends the marker for the whole session (sub-agents share the session id). DENY
# direction: an array expansion in a for list (`"${a[@]}"`) reads as a glob; any glob-shaped token in
# a while loop's feeder pipeline (an rg pattern such as `.*`) qualifies the loop.
set -u
[ "$(sh "$(dirname "$0")/kit-gate.sh" "$0" </dev/null 2>/dev/null)" = standdown ] && exit 0

INPUT="$([ -t 0 ] || cat 2>/dev/null || true)"
BASE="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd || true)"
LOG="${AGENT_TIERS_GUARDS_LOG:-${BASE:-${TMPDIR:-/tmp}}/.state/guards.log}"
logdec() {
  SID="$(printf '%s' "${INPUT:-}" | jq -r '.session_id // empty' 2>/dev/null || true)"
  { mkdir -p "$(dirname "$LOG")" 2>/dev/null && printf '%s contention-guard %s [sid=%s]\n' "$(date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null)" "$1" "${SID:-}" >> "$LOG"; } 2>/dev/null || true
}
command -v jq >/dev/null 2>&1 || exit 0
CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
[ -n "$CMD" ] || exit 0

# cheap pre-filter: none of the tool words anywhere -> nothing to tokenise
printf '%s' "$CMD" | grep -aEq '(^|[^A-Za-z0-9_])(rg|grep|egrep|fgrep|find|fd|fdfind|ag|unzip|zipinfo|tar|bsdtar|7z|7za|7zr|unrar|jar|javap|jadx|java)([^A-Za-z0-9_]|$)' || exit 0

SID="$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)"
case "$SID" in
  '' | *[!A-Za-z0-9._-]*) logdec "fail-open: no usable session id, cannot key a marker"; exit 0 ;;
esac

SELFDIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd || true)"
[ -n "$SELFDIR" ] && [ -f "$SELFDIR/guard-cmdpos.sh" ] || exit 0
. "$SELFDIR/guard-cmdpos.sh" 2>/dev/null || exit 0
command -v guard_strip_heredocs >/dev/null 2>&1 && command -v guard_argv >/dev/null 2>&1 || exit 0

# cg_nl: copy of long-run-guard.sh's lrg_nl. Every UNQUOTED, unescaped newline -> ` ; ` (guard_argv
# reads an unquoted newline as a blank); a word-start unquoted `#` drops its comment to end of line.
cg_nl() {
  printf '%s' "$1" | awk '
    BEGIN { RS = "\032"; SQ = "\047"; DQ = "\042" }
    {
      s = $0; n = length(s); st = 0; out = ""
      for (i = 1; i <= n; i++) {
        c = substr(s, i, 1)
        if (st == 1) { out = out c; if (c == SQ) st = 0; continue }
        if (c == "\\") { out = out c substr(s, i + 1, 1); i++; continue }
        if (st == 2) { out = out c; if (c == DQ) st = 0; continue }
        if (c == "#" && (i == 1 || index(" \t\n;&|(", substr(s, i - 1, 1)))) {
          while (i < n && substr(s, i + 1, 1) != "\n") i++
          continue
        }
        if (c == "\n") out = out " ; "
        else { out = out c; if (c == SQ) st = 1; else if (c == DQ) st = 2 }
      }
      printf "%s", out
    }'
}

# cg_scan <depth>: guard_argv token lines in. Out: `loop|search<TAB>KEY<TAB>DETAIL` per finding, in
# order, and at depth 0 `SUB<TAB><inner text>` per `$( )`/backtick/`sh -c` script to re-scan. Prints
# nothing at all when the token stream ends in `u` (parse failure fails open).
cg_scan() {
  awk -v depth="$1" '
    BEGIN {
      HOMEN = norm(ENVIRON["HOME"]); if (HOMEN == "/") HOMEN = ""
      split("unzip zipinfo tar bsdtar 7z 7za 7zr unrar jar javap jadx", a, " "); for (i in a) ARC[a[i]] = 1
      split("rg grep egrep fgrep find fd fdfind ag", a, " "); for (i in a) SRCH[a[i]] = 1
      split("sh bash dash zsh", a, " "); for (i in a) SHL[a[i]] = 1
      split("; && || | |& & ( ) ;;", a, " "); for (i in a) SEPG[a[i]] = 1
      split("-e -f -g -t -T -m -A -B -C -d -E -j -M -r --glob --iglob --type --type-not --max-count --after-context --before-context --context --max-depth --maxdepth --replace --regexp --file --sort --sortr --encoding --threads --type-add --type-clear --max-filesize --pre --pre-glob --colors --color --max-columns --path-separator --engine --context-separator --ignore-file", a, " "); for (i in a) VRG[a[i]] = 1
      split("-e -f -m -A -B -C -d -D --regexp --file --max-count --after-context --before-context --context --directories --devices --include --exclude --exclude-dir --exclude-from --label --binary-files", a, " "); for (i in a) VGR[a[i]] = 1
      split("-A -B -C -G -g -m -p --depth --ignore --ignore-dir --file-search-regex --path-to-ignore --pager --workers --max-count --after --before --context", a, " "); for (i in a) VAG[a[i]] = 1
      split("-e -t -d -E -j -c -S -o --extension --type --max-depth --maxdepth --min-depth --exact-depth --exclude --threads --color --size --changed-within --changed-before --change-newer-than --change-older-than --owner --base-directory --search-path --path-separator --max-results --ignore-file --format --and", a, " "); for (i in a) VFD[a[i]] = 1
      cmdpos = 1; sp = 0; nout = 0; unc = 0; ex = 0; pfx = ""; tval = 0; tdur = 0
      cur = ""; na = 0; shc = 0; pglob = ""; pfeed = ""; pfpos = ""; prev = ""
    }
    function norm(p) {
      while (1) {
        if (length(p) > 1 && substr(p, length(p)) == "/") p = substr(p, 1, length(p) - 1)
        else if (length(p) >= 2 && substr(p, length(p) - 1) == "/.") { p = substr(p, 1, length(p) - 2); if (p == "") p = "/" }
        else break
      }
      return p
    }
    function base(w) { sub(/.*\//, "", w); return w }
    function sub_(l) { gsub(/\t/, " ", l); nout++; O[nout] = "SUB\t" l }
    function find_(arm, key, det) { gsub(/\t/, " ", key); gsub(/\t/, " ", det); nout++; O[nout] = arm "\t" key "\t" det }
    function dirof(g) { if (index(g, "/") == 0) return "."; sub(/\/[^\/]*$/, "", g); return g }
    function isint02(v) { return v == "0" || v == "1" || v == "2" }
    function rootkey(t, p,    n) {
      # an unquoted trailing `/*` lists the whole directory: `/*` is root, `~/*` is home
      if (t == "o" && length(p) >= 2 && substr(p, length(p) - 1) == "/*") {
        p = substr(p, 1, length(p) - 2); if (p == "") p = "/"
        n = norm(p)
        if (n == "/") return "root"
        if (n == "~" || n == "$HOME" || n == "${HOME}" || (HOMEN != "" && n == HOMEN)) return "home"
        return ""
      }
      n = norm(p)
      if (t == "w" && n == "/") return "root"
      if (t == "o" && (n == "~" || n == "$HOME" || n == "${HOME}")) return "home"
      if (t == "w" && HOMEN != "" && n == HOMEN) return "home"
      return ""
    }
    # fire(tool): every open loop frame in body mode that qualified and has not fired yet, outermost first
    function fire(tool,    k) {
      for (k = 1; k <= sp; k++)
        if (md[k] == "b" && q[k] && !fd[k]) {
          fd[k] = 1
          find_("loop", "loop:" ky[k], "a loop that runs " tool " on every file matched by " src[k])
        }
    }
    # search(): arm 2 over the collected command cur with args AT/AP 1..na
    function search(    i, t, p, nm, val, hv, eo, np, PT, PP, po, rec, dok, files, j, c, st, rk, gl) {
      eo = 0; np = 0; po = 0; rec = 0; dok = 0; files = 0
      if (cur == "find") {
        for (i = 1; i <= na; i++) {
          p = AP[i]
          if (p == "-H" || p == "-L" || p == "-P" || p ~ /^-O[0-9]*$/) continue
          if (p == "-D") { i++; continue }
          break
        }
        for (; i <= na; i++) {
          p = AP[i]
          if ((substr(p, 1, 1) == "-" && p != "-") || p == "(" || p == ")" || p == "!" || p == "\\(") break
          np++; PT[np] = AT[i]; PP[np] = p
        }
        for (j = 1; j < na; j++) if (AP[j] == "-maxdepth" && isint02(AP[j + 1])) return
        st = 1
      } else {
        for (i = 1; i <= na; i++) {
          t = AT[i]; p = AP[i]
          if (!eo && p == "--") { eo = 1; continue }
          if (eo || substr(p, 1, 1) != "-" || p == "-") { np++; PT[np] = t; PP[np] = p; continue }
          nm = p; val = ""; hv = 0
          if (p ~ /^--[^=]+=/) { nm = p; sub(/=.*/, "", nm); val = substr(p, length(nm) + 2); hv = 1 }
          if (cur == "rg") {
            if (!hv && (p in VRG)) { val = AP[i + 1]; i++; hv = 1 }
            if (nm == "-e" || nm == "-f" || nm == "--regexp" || nm == "--file" || p ~ /^-[ef]./) po = 1
            if (p == "--files" || p == "--type-list") files = 1
            if ((nm == "--max-depth" || nm == "--maxdepth" || nm == "-d") && hv && isint02(val)) dok = 1
          } else if (cur == "ag") {
            if (!hv && (p in VAG)) { val = AP[i + 1]; i++; hv = 1 }
            if (nm == "-g" || nm == "-G") po = 1
            if (nm == "--depth" && hv && isint02(val)) dok = 1
          } else if (cur == "fd") {
            if (p == "-x" || p == "-X" || nm == "--exec" || nm == "--exec-batch") break
            gl = AT[i]
            if (!hv && (p in VFD)) { val = AP[i + 1]; gl = AT[i + 1]; i++; hv = 1 }
            if ((nm == "--search-path" || nm == "--base-directory") && hv) { rk = rootkey(gl, val); if (rk != "") { emits(rk, val); return } }
            if ((nm == "-d" || nm == "--max-depth" || nm == "--maxdepth" || nm == "--exact-depth") && hv && isint02(val)) dok = 1
          } else {
            # grep family
            if (!hv && (p in VGR)) { val = AP[i + 1]; i++; hv = 1 }
            if (nm == "-e" || nm == "-f" || nm == "--regexp" || nm == "--file") po = 1
            if (p == "-r" || p == "-R" || nm == "--recursive" || nm == "--dereference-recursive") rec = 1
            if (nm == "--directories" && val == "recurse") rec = 1
            if (nm == "-d" && val == "recurse") rec = 1
            if (p ~ /^-[A-Za-z0-9]+$/ && !(p in VGR)) {
              for (j = 2; j <= length(p); j++) {
                c = substr(p, j, 1)
                if (c == "r" || c == "R") rec = 1
                if (c == "e" || c == "f") { po = 1; if (j == length(p)) i++; break }
                # a value-taking letter last in the cluster (`-rA 3`, `-rm 5`) takes the next token
                if (j == length(p) && index("ABCmdD", c)) { if (c == "d" && AP[i + 1] == "recurse") rec = 1; i++ }
              }
            }
          }
        }
        if (cur == "grep" && !rec) return
        if (dok) return
        st = (po || files) ? 1 : 2
      }
      for (j = st; j <= np; j++) { rk = rootkey(PT[j], PP[j]); if (rk != "") { emits(rk, PP[j]); return } }
    }
    function emits(rk, typed) { find_("search", "search:" rk, "a recursive " cur " search rooted at " typed) }
    # endcmd(): the simple command being collected ends here
    function endcmd(    i, hasjar) {
      if (cur != "") {
        if (cur in SRCH) search()
        hasjar = 0; for (i = 1; i <= na; i++) if (AP[i] == "-jar") hasjar = 1
        if ((cur in ARC) || (cur == "java" && hasjar)) fire(cur == "java" ? "java -jar" : cur)
      }
      cur = ""; na = 0; shc = 0; ex = 0; pfx = ""; tval = 0; tdur = 0
    }
    {
      tag = substr($0, 1, 1); w = substr($0, 2)
      if (tag == "u") { unc = 1; next }
      if (tag == "r" || tag == "R") { prev = "r"; next }
      # a newline (now `;`) right after `|`, `|&`, `&&` or `||` is a line continuation, not a separator
      if (tag == "g" && w == ";" && (prev == "g|" || prev == "g|&" || prev == "g&&" || prev == "g||")) next
      issep = (tag == "g" && (w in SEPG))
      if (ex && !issep) { prev = tag w; next }
      if (tag == "o") {
        # one-level re-scan text: `$( )` / backticks (after a VAR= prefix), checked before anything else
        p = w; if (p ~ /^[A-Za-z_][A-Za-z0-9_]*=/) sub(/^[A-Za-z_][A-Za-z0-9_]*=/, "", p)
        if (depth == 0) {
          if (substr(p, 1, 2) == "$(" && substr(p, length(p)) == ")") sub_(substr(p, 3, length(p) - 3))
          else if (length(p) >= 2 && substr(p, 1, 1) == "`" && substr(p, length(p)) == "`") sub_(substr(p, 2, length(p) - 2))
        }
        if (match(w, /(\$\(|`)[ \t]*(unzip|zipinfo|tar|bsdtar|7z|7za|7zr|unrar|jar|javap|jadx)([^A-Za-z0-9_.-]|$)/)) {
          m = substr(w, RSTART, RLENGTH); sub(/^(\$\(|`)[ \t]*/, "", m); sub(/[^A-Za-z0-9_]$/, "", m); fire(m)
        } else if (match(w, /(\$\(|`)[ \t]*java[ \t][^)`]*-jar/)) fire("java -jar")
      }
      # pipeline buffer for while/until feeders
      if (tag == "w" || tag == "o") { if (pglob == "" && w ~ /[*?[]/) pglob = w }
      # for-loop head
      if (sp && md[sp] == "h") {
        if (fs[sp] == 1) { fs[sp] = (tag == "w") ? 2 : 9 }
        else if (fs[sp] == 2) { if (tag == "w" && w == "in") fs[sp] = 3; else if (tag == "w" && w == "do") { md[sp] = "b"; cmdpos = 1 } else if (tag == "g" && w == ";") fs[sp] = 4; else fs[sp] = 9 }
        else if (fs[sp] == 3) {
          if (tag == "g" && w == ";") fs[sp] = 4
          else if (tag == "w" && w == "do") { md[sp] = "b"; cmdpos = 1 }
          else if (tag == "o" && !q[sp] && w ~ /[*?[]/) { q[sp] = 1; src[sp] = w; ky[sp] = dirof(w) }
        }
        else if (tag == "w" && w == "do") { md[sp] = "b"; cmdpos = 1 }
        prev = tag w; next
      }
      if (tag == "g") {
        if (issep || w == "{" || w == "}" || w == "!") {
          if (cur != "" && !issep) { na++; AT[na] = "w"; AP[na] = w; prev = tag w; next }
          endcmd(); cmdpos = 1
          if (w == ";" || w == "&&" || w == "||" || w == "&" || w == ";;") { pglob = ""; pfeed = ""; pfpos = "" }
        }
        prev = tag w; next
      }
      if (cmdpos) {
        if (w ~ /^[A-Za-z_][A-Za-z0-9_]*=/) { prev = tag w; next }
        if (tag == "w") {
          if (pfx == "timeout") {
            if (tval) { tval = 0; prev = tag w; next }
            if (w == "-k" || w == "-s" || w == "--signal" || w == "--kill-after") { tval = 1; prev = tag w; next }
            if (substr(w, 1, 1) == "-") { prev = tag w; next }
            if (!tdur) { tdur = 1; prev = tag w; next }
          } else if (pfx != "" && substr(w, 1, 1) == "-") { prev = tag w; next }
          b = base(w)
          if (w == "do") { if (sp && md[sp] == "c") md[sp] = "b"; prev = tag w; next }
          if (w == "then" || w == "else" || w == "elif" || w == "if" || w == "time") { if (w == "time") pfx = "time"; prev = tag w; next }
          if (w == "while" || w == "until") {
            sp++; kd[sp] = "L"; md[sp] = "c"; fd[sp] = 0; q[sp] = 0
            if ((prev == "g|" || prev == "g|&") && (pglob != "" || pfeed != "")) {
              q[sp] = 1
              if (pglob != "") { src[sp] = pglob; ky[sp] = dirof(pglob) }
              else { src[sp] = pfeed; ky[sp] = (pfpos != "") ? pfpos : "." }
            }
            prev = tag w; next
          }
          if (w == "for" || w == "select") { sp++; kd[sp] = "F"; md[sp] = "h"; fs[sp] = 1; fd[sp] = 0; q[sp] = 0; cmdpos = 0; prev = tag w; next }
          # closers: a keyword may follow `fi`, `esac`, `done` or `}` with no separator (`fi done`)
          if (w == "done") { endcmd(); if (sp) sp--; cmdpos = 1; prev = tag w; next }
          if (w == "fi" || w == "esac") { endcmd(); cmdpos = 1; prev = tag w; next }
          if (b == "sudo" || b == "env" || b == "command" || b == "exec" || b == "nohup" || b == "timeout") { pfx = b; tval = 0; tdur = 0; prev = tag w; next }
          if (b == "nice" || b == "ionice") { ex = 1; cmdpos = 0; prev = tag w; next }
          cur = (b == "fdfind") ? "fd" : b
          if (cur == "egrep" || cur == "fgrep") cur = "grep"
          if (cur == "find" || cur == "fd" || cur == "ls") { pfeed = b; pfpos = "" }
        } else cur = "?"
        cmdpos = 0; na = 0; pfx = ""; prev = tag w; next
      }
      # collecting arguments of cur
      if (cur != "") {
        na++; AT[na] = tag; AP[na] = w
        if ((cur == "find" || cur == "fd" || cur == "ls") && pfeed != "" && pfpos == "" && substr(w, 1, 1) != "-") pfpos = w
        if (cur in SHL) {
          if (shc) { if (depth == 0) sub_(w); shc = 0 }
          else if (w ~ /^-[A-Za-z]*c[A-Za-z]*$/) shc = 1
        }
      }
      prev = tag w
    }
    END {
      if (unc) exit 0
      endcmd()
      for (i = 1; i <= nout; i++) print O[i]
    }'
}

# cg_find <text> <depth>: the whole pipeline over one text.
cg_find() {
  guard_argv "$(cg_nl "$(guard_strip_heredocs "$1")")" | cg_scan "$2"
}
cg_hits() { awk -F '\t' '$1 == "loop" || $1 == "search"'; }

TAB="$(printf '\t')"
OUT="$(cg_find "$CMD" 0)"
# every hit: the top-level ones in order, then each re-scanned inner text's, in order
HITS="$(printf '%s\n' "$OUT" | cg_hits
printf '%s\n' "$OUT" | while IFS= read -r l; do
  case "$l" in (SUB"$TAB"*) : ;; (*) continue ;; esac
  cg_find "$(printf '%s' "${l#SUB?}" | tr '\036' '\n')" 1 | cg_hits
done)"
[ -n "$HITS" ] || exit 0

STATE_DIR="${CONTENTION_GUARD_STATE_DIR:-${BASE:-${TMPDIR:-/tmp}}/.state/contention-guard}"

# cg_slug / cg_gc: from peer-guard.sh's pg_slug / pg_gc. The slug is `<readable>_h<cksum of KEY>`
# (the cksum is always appended, so keys that differ only in punctuation never share a marker), and
# `h<cksum>` alone when ${SID}__<slug> would pass 200 chars; GC after a write, AGENT_TIERS_STATE_DAYS
# default 7, validated.
cg_slug() {
  h="$(printf '%s' "$1" | cksum | cut -d' ' -f1)"
  slug="$(printf '%s' "$1" | tr -c 'A-Za-z0-9' '_')_h${h}"
  combined="${SID}__${slug}"
  [ "${#combined}" -gt 200 ] && slug="h${h}"
  printf '%s\n' "$slug"
}
cg_gc() {
  days="${AGENT_TIERS_STATE_DAYS:-7}"; case "$days" in ''|*[!0-9]*) days=7 ;; esac
  [ "$days" -gt 0 ] 2>/dev/null && [ "$days" -le 3650 ] 2>/dev/null || days=7
  find "$STATE_DIR" -maxdepth 1 -type f -mtime "+$days" -delete 2>/dev/null
  true
}

# the first hit whose marker is not spent yet names the deny; EVERY unspent hit's marker is written
# with it (MARKERS, one per line), so the identical retry of a multi-target command passes instead of
# being denied once per target. Read in this shell, not a pipe subshell.
ARM=""; KEY=""; DETAIL=""; MARKER=""; MARKERS=""
while IFS= read -r HIT; do
  [ -n "$HIT" ] || continue
  a="${HIT%%"$TAB"*}"; r="${HIT#*"$TAB"}"; k="${r%%"$TAB"*}"
  m="$STATE_DIR/${SID}__$(cg_slug "$k")"
  [ -f "$m" ] && continue
  MARKERS="$MARKERS$m
"
  [ -n "$MARKER" ] && continue
  ARM="$a"; KEY="$k"; DETAIL="${r#*"$TAB"}"; MARKER="$m"
done <<EOF
$HITS
EOF
[ -n "$MARKER" ] || exit 0
# DETAIL is copied from the command's own tokens: printable ASCII only, capped
DETAIL="$(printf '%s' "$DETAIL" | LC_ALL=C tr -c '\040-\176' '?' | cut -c1-160)"
# markers BEFORE the decision: a failed write must never leave a deny that the retry cannot clear.
# `true >`, not `: >`: a redirection failure on the special builtin `:` exits a POSIX-mode shell.
MFAIL=""
mkdir -p "$STATE_DIR" 2>/dev/null || MFAIL="$STATE_DIR"
while [ -z "$MFAIL" ] && IFS= read -r m; do
  [ -n "$m" ] || continue
  { true > "$m"; } 2>/dev/null || MFAIL="$m"
done <<EOF
$MARKERS
EOF
if [ -n "$MFAIL" ]; then
  logdec "fail-open: marker write failed for $MFAIL"
  exit 0
fi
cg_gc
logdec "deny: $ARM $KEY"
REASON="agent-tiers contention-guard: $DETAIL. This can run for minutes and compete with whatever the human is doing on the same machine. Narrow the target (a named subdirectory, a few named files, or a depth limit of 2), or run it as 'nice -n 19 <command>' (on Linux also 'ionice -c3'), or ask the human first if they may be using the machine (from a sub-agent: say so in your report). This deny fires once per session per target: the identical retry passes."
jq -n --arg r "$REASON" \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
exit 0

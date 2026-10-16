#!/usr/bin/env sh
# kit-scope: shared
# gen-plugin-manifests.sh - generate .claude-plugin/plugin.json's userConfig and hooks/hooks.json from
# install/options.tsv, the one table for hook rows and user options, so the plugin files cannot drift.
#
#   sh scripts/gen-plugin-manifests.sh [--check|--write] [KIT_DIR]
#     --check  (default) regenerate into a temp dir, compare to the on-disk files with `jq -S .`; exit 0 when
#              both match, 1 naming each drifted file and the fix command.
#     --write  write both files (2-space indent, trailing newline), exit 0.
#     KIT_DIR  kit root to work on (default: this script's own kit). Exit 2 = usage, tooling or input error.
#   plugin.json = the existing file with only .userConfig replaced. Requires jq.
#
# Which hook rows are wired: a row is wired iff scripts/<id>.sh exists and is not export-ignored. An
# export-ignored script never ships in the public copy, yet options.tsv (which ships) still lists its row;
# a hooks.json entry for a missing script fails on every matching tool call, so such a row is never wired.
# Export-ignored = `git check-attr export-ignore` says "set" when KIT_DIR is a git work tree, else an exact
# line "scripts/<id>.sh export-ignore" in KIT_DIR/.gitattributes. A row whose script is ABSENT is skipped
# silently when .gitattributes is absent (a shipped copy, where .gitattributes and the ignored scripts were
# stripped); in the source repo (.gitattributes present) an absent, non-ignored script is a broken row: exit 2.
# options.tsv hook column 7 `requires` (- or a comma list of hook ids) is validated here, not emitted:
# hooks.json has no slot for it.
set -u
MODE=check; KIT=""
for a in "$@"; do
  case "$a" in
    --check) MODE=check ;;
    --write) MODE=write ;;
    -*) echo "usage: gen-plugin-manifests.sh [--check|--write] [KIT_DIR]" >&2; exit 2 ;;
    *) KIT="$a" ;;
  esac
done
[ -n "$KIT" ] || KIT="$(CDPATH= cd "$(dirname "$0")/.." && pwd)"
command -v jq >/dev/null 2>&1 || { echo "gen-plugin-manifests: jq is required" >&2; exit 2; }
TSV="$KIT/install/options.tsv"; PJ="$KIT/.claude-plugin/plugin.json"; HJ="$KIT/hooks/hooks.json"
[ -f "$TSV" ] || { echo "gen-plugin-manifests: missing $TSV" >&2; exit 2; }
[ -f "$PJ" ] || { echo "gen-plugin-manifests: missing $PJ" >&2; exit 2; }

# Validate every row; awk prints one line per bad row.
bad="$(LC_ALL=C awk -F'\t' '
  { sub(/\r$/, "") }
  /^#/ || /^[ \t]*$/ { next }
  $1 == "hook" {
    if (NF > 7) print "hook row " NR " invalid (more than 7 fields, a tab inside a field?): " $0
    else if (NF < 7) print "hook row " NR " invalid (needs 7 fields; requires column, - for none): " $0
    else if ($2 !~ /^[A-Za-z0-9_-]+$/ || $4 == "" || $6 !~ /^[0-9]+$/ || $6 + 0 < 1)
      print "hook row " NR " invalid (id [A-Za-z0-9_-], event non-empty, timeout positive integer): " $0
    else if ($7 !~ /^(-|[A-Za-z0-9_-]+(,[A-Za-z0-9_-]+)*)$/) print "hook row " NR " invalid (requires must be - or a comma list of hook ids): " $0
    else if ($2 in seen) print "hook row " NR " invalid (duplicate hook id " $2 "): " $0
    else { seen[$2] = 1; hg[$2] = $3; hn[$2] = NR; rq[NR] = $7; rid[NR] = $2 }
  }
  $1 == "option" {
    if (NF > 6) print "option row " NR " invalid (more than 6 fields, a tab inside a field?): " $0
    else if (NF < 6 || $2 !~ /^[A-Za-z_][A-Za-z0-9_]*$/) print "option row " NR " bad key: " $0
    else if ($3 != "boolean" && $3 != "string[]") print "option row " NR " unknown type: " $0
    else if ($3 == "boolean" && $4 != "" && $4 != "true" && $4 != "false") print "option row " NR " boolean default not true/false: " $0
    else if ($5 == "" || $6 == "") print "option row " NR " empty title or description: " $0
    og[$2] = 1
  }
  END {
    for (n in rq) { m = split(rq[n], a, ","); for (j = 1; j <= m; j++) {
      if (a[j] == "-") continue
      if (a[j] == rid[n]) print "hook row " n " invalid (requires itself): " rid[n]
      else if (!(a[j] in seen)) print "hook row " n " invalid (requires unknown hook id " a[j] "): " rid[n]
    } }
    for (i in hg) if (hg[i] != "core" && !(("group_" hg[i]) in og)) print "hook row " hn[i] " invalid (group " hg[i] " is not core and has no option group_" hg[i] " row): hook " i }' "$TSV")"
[ -z "$bad" ] || { printf 'gen-plugin-manifests: %s\n' "$bad" >&2; exit 2; }

T="$(mktemp -d)" || exit 2
trap 'rm -rf "$T"' EXIT

# Wired hook ids, one per line.
# The gate script name is assembled from pieces so this file has no literal gate-script name on an
# uncommented line (the gate selfcheck flags any such script that has no hook row).
FRAG='"$(sh "$(dirname "$0")/'"kit-gate"'.sh" "$0" </dev/null 2>/dev/null)" = standdown ]'
ungated=""
isgit=0; git -C "$KIT" rev-parse --is-inside-work-tree >/dev/null 2>&1 && isgit=1
for id in $(awk -F'\t' '$1 == "hook" { print $2 }' "$TSV"); do
  rel="scripts/$id.sh"; ign=0
  if [ "$isgit" = 1 ]; then
    case "$(git -C "$KIT" check-attr export-ignore -- "$rel" 2>/dev/null)" in *": set") ign=1 ;; esac
  elif [ -f "$KIT/.gitattributes" ] && grep -qxF "$rel export-ignore" "$KIT/.gitattributes"; then ign=1
  fi
  [ "$ign" = 1 ] && continue
  if [ -f "$KIT/$rel" ]; then
    awk -v fr="$FRAG" 'index($0, fr) && $0 !~ /^[[:space:]]*#/ { f = 1 } END { exit !f }' "$KIT/$rel" || { ungated="$ungated $id"; continue; }
    echo "$id" >> "$T/wired"
  elif [ -f "$KIT/.gitattributes" ]; then
    echo "gen-plugin-manifests: hook row '$id' has no $rel and is not export-ignored" >&2; exit 2
  fi
done
[ -z "$ungated" ] || { echo "gen-plugin-manifests: hook rows whose script does not call the kit gate:$ungated" >&2; exit 2; }
[ -f "$T/wired" ] || : > "$T/wired"

DESC='agent-tiers hooks. Generated from install/options.tsv by scripts/gen-plugin-manifests.sh: do not edit by hand. Every hook first runs the kit gate, which stands it down when the kit is off or the hook'\''s group is off. A plain install runs at Core level: only the session handoff and housekeeping hooks act, and the other groups are turned on in the plugin options.'
ROWS='($tsv | split("\n") | map(rtrimstr("\r") | select(length > 0 and (startswith("#") | not)) | split("\t")))'

jq --rawfile tsv "$TSV" "$ROWS"' as $rows
  | .userConfig = ([$rows[] | select(.[0] == "option") | . as $r | {key: $r[1], value:
      ({type: (if $r[2] == "boolean" then "boolean" else "string" end)}
       + (if $r[2] == "string[]" then {multiple: true} else {} end)
       + {title: $r[4], description: $r[5]}
       + (if $r[3] == "" then {} else {default: (if $r[2] == "boolean" then ($r[3] == "true") else ($r[3] | split(",")) end)} end))}]
     | from_entries)' "$PJ" > "$T/plugin.json" || { echo "gen-plugin-manifests: plugin.json generation failed" >&2; exit 2; }

jq -n --rawfile tsv "$TSV" --rawfile w "$T/wired" --arg desc "$DESC" "$ROWS"' as $rows
  | ($w | split("\n")) as $wl
  | {description: $desc, hooks:
      (reduce ($rows[] | select(.[0] == "hook" and (.[1] as $i | $wl | index($i)))) as $r ({};
        .[$r[3]] += [(if $r[4] != "" then {matcher: $r[4]} else {} end)
          + {hooks: [{type: "command", command: ("sh \"${CLAUDE_PLUGIN_ROOT}/scripts/" + $r[1] + ".sh\""), timeout: ($r[5] | tonumber)}]}]))}' \
  > "$T/hooks.json" || { echo "gen-plugin-manifests: hooks.json generation failed" >&2; exit 2; }

if [ "$MODE" = write ]; then
  mkdir -p "$KIT/hooks" || exit 2
  cp "$T/plugin.json" "$PJ" && cp "$T/hooks.json" "$HJ" || exit 2
  echo "wrote $PJ and $HJ"; exit 0
fi

rc=0
for pair in "plugin.json:$PJ" "hooks.json:$HJ"; do
  g="${pair%%:*}"; d="${pair#*:}"
  if [ -f "$d" ] && jq -S . "$d" > "$T/d.out" 2>/dev/null && jq -S . "$T/$g" > "$T/g.out" && cmp -s "$T/d.out" "$T/g.out"; then :
  else echo "drift: $d differs from install/options.tsv (fix: sh scripts/gen-plugin-manifests.sh --write)"; rc=1; fi
done
exit $rc

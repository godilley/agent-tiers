#!/usr/bin/env sh
# kit-scope: shared
# content-rules.sh - a shared ruleset for "does this prose carry derivable state, a commit sha, or an
# attributed quote", sourced (not executed standalone) by a consumer that needs to CHECK a doc rather
# than just state the rule in prose.
#
# Why one file: the checks below are the machine-checkable form of rules `doc-style` already states in
# prose (never record derivable state; no narrative/attributed wording) and the kit's own memory doctrine
# states for memory files specifically (`cards/MEMORY.md` MEMORY-2/MEMORY-3). Consumers: `memory-content-lint.sh`
# (a PostToolUse hook, this kit) sources it - the memory-only rules (shas, derivable counts, PR numbers,
# attribution, resume duplication) on a memory-file write, and `content_rules_repo_state` on ANY `.md`
# write; the sibling `doc-style` skill points doc audits at these functions instead of keeping its own copy
# of the patterns. No doc-audit SCRIPT sources this file yet, so the doc side is a pointer an auditing
# agent follows, not code.
#
# Each function takes a FILE PATH (plus a 2nd path for the duplication check, or a names-file path for the
# name-parameterised attribution check) and prints zero or more findings to stdout, one per line, as
# "<line-number>: <rule-id>: <matched text, trimmed>". Callers decide what to do with the findings (advise,
# count, fail a lint) - this file only detects.
#
# Library hygiene (sourced into a caller's shell, so it must not disturb it): NO top-level `set -u` - a
# consumer's own `set -u` state is theirs to keep. Every function body is a SUBSHELL (`name() ( ... )`),
# so a variable it assigns (`f`, `tmp`, `line`, `tok`, `name`, `names_file`, `mem`, `resume`, `rtmp`,
# `neutral`) never leaks into or clobbers a same-named variable in the calling shell, whether the function
# is called via command substitution (which already forks a subshell) or invoked directly (which would
# not). Self-check: content-rules.selfcheck.sh, case "library hygiene".
#
# Frontmatter: Claude Code writes YAML frontmatter (`name`, `description`, `metadata:` incl.
# `originSessionId`, `modified`) at the top of every memory file it creates (memory.md:411). A bare UUID's
# hex groups are 7-40 chars long, so an unguarded sha/derivable-count/attribution check fires on nearly
# every real memory file's OWN harness-written header, not on anything a Lead wrote. Every function below
# routes the file through `_content_rules_prep` first, which blanks ONLY id-bearing frontmatter lines (a
# YAML key ending in `id`/`Id`/`ID`, e.g. `originSessionId:`) - `name:` and `description:` stay scannable,
# since Claude (not the harness) writes those and a sha or a quote can land in either (real miss this
# closes: a `description:` line naming a commit). Blanked/kept lines keep the same LINE COUNT as the
# original so line numbers in a finding still match. If `mktemp` is unavailable, the affected rule is
# SKIPPED (a stderr note, no finding) rather than falling back to the raw, un-prepped file - scanning raw
# frontmatter would reintroduce the exact false-positive this file exists to remove.

# _content_rules_strip_id_lines FILE -> stdout, same line count as FILE: inside a leading YAML frontmatter
# block only (first line exactly `---`, up to the next line that is exactly `---`), a line whose key ends
# in `id`/`Id`/`ID` (`originSessionId:`, a hypothetical `sessionId:`/`agentId:`/`threadId:`) is blanked;
# every other frontmatter line (`name:`, `description:`, `type:`, `modified:`, the `metadata:` header
# itself) passes through untouched. A file with no frontmatter (first line is not `---`) passes through
# unchanged. Internal helper.
_content_rules_strip_id_lines() (
  awk '
    NR==1 && $0=="---" { infm=1; print; next }
    infm && $0=="---"  { infm=0; print; next }
    infm && $0 ~ /^[[:space:]]*[A-Za-z0-9_]*([Ii][Dd]):[[:space:]]/ { print ""; next }
    { print }
  ' "$1" 2>/dev/null
)

# _content_rules_prep FILE -> stdout: path to an id-line-blanked temp copy. Returns non-zero with EMPTY
# stdout (never the raw file) when `mktemp` or the strip pass fails - the caller must treat that as "skip
# this rule for this file", not "scan anyway".
_content_rules_prep() (
  tmp="$(mktemp 2>/dev/null)" || { printf 'content-rules: mktemp unavailable - skipping a rule for %s\n' "$1" >&2; exit 1; }
  if _content_rules_strip_id_lines "$1" > "$tmp" 2>/dev/null; then
    printf '%s' "$tmp"
  else
    rm -f "$tmp" 2>/dev/null || true
    printf 'content-rules: frontmatter pass failed - skipping a rule for %s\n' "$1" >&2
    exit 1
  fi
)

# _content_rules_neutralize_ids FILE -> stdout: a copy with a full UUID (8-4-4-4-12 lowercase hex) or an
# `agent-<hex>` token replaced by an equal-shaped placeholder that cannot itself match the sha pattern.
# Used ONLY as a detection pass inside content_rules_shas - the ORIGINAL line text is still what gets
# reported, so a real sha sitting next to a neutralised id on the same line is still caught and quoted
# verbatim. Same "skip, do not fall back to raw" contract as _content_rules_prep. Word edges are spelled
# out as character classes: `\b` in sed -E is GNU-only, and BSD sed (macOS) silently never matched it.
# The agent-id expression runs twice because each match consumes the edge character after it, so of two
# ids one space apart the first pass replaces only the first; the second pass gets every one it skipped.
_content_rules_neutralize_ids() (
  tmp="$(mktemp 2>/dev/null)" || { printf 'content-rules: mktemp unavailable - skipping id-neutralisation for %s\n' "$1" >&2; exit 1; }
  sed -E \
    -e 's/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/uuididuuididuuididuuididuuididuuidid/g' \
    -e 's/(^|[^[:alnum:]_])agent-[0-9a-f]{6,}([^[:alnum:]_]|$)/\1agentidagentidagentidagentidagentid\2/g' \
    -e 's/(^|[^[:alnum:]_])agent-[0-9a-f]{6,}([^[:alnum:]_]|$)/\1agentidagentidagentidagentidagentid\2/g' \
    "$1" > "$tmp" 2>/dev/null && { printf '%s' "$tmp"; exit 0; }
  rm -f "$tmp" 2>/dev/null || true
  printf 'content-rules: sed unavailable - skipping id-neutralisation for %s\n' "$1" >&2
  exit 1
)

# content_rules_shas FILE - a bare-looking git sha (7-40 hex chars) OR the kit's own "kit-git:<sha>"
# convention, outside id-bearing frontmatter. Requires at least one a-f LETTER and at least one DIGIT
# (excludes an all-digit run - a line/byte count, a year - and an all-letter dictionary word that happens
# to be hex-shaped, e.g. "facade", "deadbeef" - stated ceiling, not closed: a hex word that also contains
# a digit, e.g. "cafe123", still reads as sha-shaped, same as a real short sha would).
#
# Id-shaped tokens are EXCLUDED, not just relabelled: a full UUID (a session/transcript id shape) and an
# `agent-<hex>` token never produce a finding at all - a Lead cannot mistake either for "delete this sha"
# advice, because neither is reported. A BARE hex run that is not UUID- or agent-id-shaped (e.g. an 8-char
# token quoted after the word "session" with no surrounding UUID punctuation) CANNOT be told apart from a
# real short sha by shape alone, so it IS still reported - worded as "looks like a commit sha or an id",
# never as a instruction to remove it (see memory-content-lint.sh's finding text, which owns the wording
# shown to a Lead; this function only reports token + line).
content_rules_shas() (
  f="$(_content_rules_prep "$1")" || exit 0
  neutral="$(_content_rules_neutralize_ids "$f")" || { rm -f "$f" 2>/dev/null || true; exit 0; }
  grep -noE '\b[0-9a-f]{7,40}\b' "$neutral" 2>/dev/null | while IFS=: read -r ln tok; do
    case "$tok" in
      *[a-f]*[0-9]*|*[0-9]*[a-f]*)
        line="$(sed -n "${ln}p" "$f" 2>/dev/null)"
        printf '%s: sha:%s\n' "$ln" "$line"
        ;;
    esac
  done
  rm -f "$f" "$neutral" 2>/dev/null || true
)

# content_rules_derivable_counts FILE - a number immediately followed by a unit that a lookup command
# already knows better: files, lines, commits, rows, sessions, KB/MB/bytes, PRs, shas. Same posture as
# doc-style "Never record derivable state" - flags the SHAPE (digit + derivable unit), not every number in
# the file. Excludes a date fragment (`09-02`, `2026-09-02`): the digit run must NOT be immediately
# preceded by a hyphen with no space, which is exactly the shape a bare-digit day/month reads as
# ("...09-02 session" is a date, "- 12 files" is a count - the char before the digit differs: `-` glued to
# the digit vs `-` then a space).
content_rules_derivable_counts() (
  f="$(_content_rules_prep "$1")" || exit 0
  grep -nEi '(^|[^0-9-])[0-9]+[+]?[[:space:]]*(files?|lines?|commits?|rows?|sessions?|kb|mb|bytes?|prs?|shas?)\b' "$f" 2>/dev/null \
    | sed -E 's/^([0-9]+):(.*)$/\1: derivable-count:\2/'
  rm -f "$f" 2>/dev/null || true
)

# content_rules_pr_number FILE - MEMORY-2 names "a PR number" as derivable state; a bare `#42` is too
# noisy (a filed ISSUE number, e.g. `owner/repo#1269`, is not a PR and not derivable from this repo's own
# git). Narrowed to require the literal word "PR" immediately before the number.
content_rules_pr_number() (
  f="$(_content_rules_prep "$1")" || exit 0
  grep -nEi '\bPR[[:space:]#-]*[0-9]+\b' "$f" 2>/dev/null \
    | sed -E 's/^([0-9]+):(.*)$/\1: pr-number:\2/'
  rm -f "$f" 2>/dev/null || true
)

# content_rules_attribution FILE [NAMES_FILE] - a quoted string attributed to a person, or the narrative
# "X said/says" shape doc-style already bans in prose ("we discussed this and X said..."). The GENERIC
# half below carries no personal name (MAINT-10: a real name is personal-layer content, never shipped in
# the kit) and is intentionally narrow (said/says/told me/asked only) - widening it to more verbs against
# ANY capitalised word measurably false-positives (a script or a role name, not a person, e.g. "Reviewer
# caught"), so those verbs are NAME-PARAMETERISED instead: read from NAMES_FILE (default
# "${CONTENT_RULES_NAMES_FILE:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/agent-tiers/.state/attribution-names}",
# one plain name per line, `#`-prefixed lines skipped) - a machine-local, never-shipped file (absent by
# default -> generic patterns only, same MAINT-10 posture). Per listed name: "<Name>'s call", "<Name>
# caught|said|asked|wanted|decided", "per <Name>", and a quoted span (>=3 chars) sharing a line with the
# name - the last one catches a name followed by a colon or a verb phrase then a same-line quote (e.g.
# `Alex caught an asymmetry ("this is what I meant")`, a synthetic illustration of the real shape).
content_rules_attribution() (
  f="$(_content_rules_prep "$1")" || exit 0
  grep -nE '"[^"]{3,}"[[:space:]]*(-|--)?[[:space:]]*(said|says|told|asked)\b|\b[A-Z][a-z]+ (said|says|told me|asked)\b' "$f" 2>/dev/null \
    | sed -E 's/^([0-9]+):(.*)$/\1: attribution:\2/'

  names_file="${2:-${CONTENT_RULES_NAMES_FILE:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/agent-tiers/.state/attribution-names}}"
  if [ -f "$names_file" ]; then
    while IFS= read -r name || [ -n "$name" ]; do
      case "$name" in ''|'#'*) continue ;; esac
      # Names are plain-word content from a local, hand-kept file - no attempt to escape arbitrary regex
      # metacharacters (a name containing one is a fixture-authoring error, not an adversarial input).
      grep -nE "\\b${name}'s call\\b|\\b${name} (caught|said|asked|wanted|decided)\\b|\\bper ${name}\\b" "$f" 2>/dev/null \
        | sed -E "s/^([0-9]+):(.*)\$/\\1: attribution-name:\\2/"
      grep -nE "\\b${name}\\b" "$f" 2>/dev/null | grep -E '"[^"]{3,}"' \
        | sed -E "s/^([0-9]+):(.*)\$/\\1: attribution-quote:\\2/"
    done < "$names_file"
  fi
  rm -f "$f" 2>/dev/null || true
)

# content_rules_resume_duplication MEMORY_FILE RESUME_FILE - a non-trivial line (>= 20 chars after
# trimming, so a lone heading or blank line never matches) present verbatim in both. RESUME is transient
# working-state; a memory file that copies its lines is the exact "one canonical home per fact" violation
# `context-file-layout` SKILL.md's anti-bloat rule and `commands/gc.md`'s resume-extraction step both name.
# The memory-file side goes through the SAME id-line-blanking prep as every other rule here (RESUME_SESSION.md
# itself carries no frontmatter, so only the memory-side call matters in practice) - skipped, not raw-file
# fallback, if `mktemp` is unavailable, same contract as `_content_rules_prep`.
content_rules_resume_duplication() (
  mem="$1"; resume="$2"
  [ -f "$mem" ] && [ -f "$resume" ] || exit 0
  f="$(_content_rules_prep "$mem")" || exit 0
  rtmp="$(mktemp 2>/dev/null)" || { rm -f "$f" 2>/dev/null || true; printf 'content-rules: mktemp unavailable - skipping resume-duplication for %s\n' "$mem" >&2; exit 0; }
  awk '{ s=$0; gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); if (length(s) >= 20) print s }' "$resume" > "$rtmp" 2>/dev/null
  awk '{ s=$0; gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); if (length(s) >= 20) print s }' "$f" 2>/dev/null \
    | grep -Fxf "$rtmp" 2>/dev/null | sed 's/^/dup-resume-line: /'
  rm -f "$rtmp" "$f" 2>/dev/null || true
)

# content_rules_repo_state FILE - "repo state a git command answers": an unpushed/ahead/behind count, a
# clean-tree or uncommitted claim, or a sha written as CURRENT HEAD. Same posture as derivable_counts above
# but widened past memory files - a handoff/notes doc (RESUME_SESSION.md, docs/_local/*) records exactly
# this kind of state and goes stale the moment the next commit lands; the fix is to record the LOOKUP
# COMMAND, not its output (see this repo's own CLAUDE.md "Never record derivable state" doctrine). Caller
# decides memory-vs-any-.md scope (memory-content-lint.sh), this function only detects.
#
# Deliberately does NOT flag: a sha cited as dated HISTORY ("fixed in abc1234", "LANDED - kit commit
# `63776bd`") - that never goes stale, only a sha asserted as the CURRENT tip does, so the sha half of this
# rule only fires when the token sits next to a current-state marker (HEAD/unpushed/not pushed), not
# every bare sha-shaped token (that is content_rules_shas's job, with its own id-exclusion ceiling).
#
# Known residual false positive: rule TEXT that merely describes a clean tree in the abstract (e.g. "the
# preflight proves a clean tree") reads the same as a stale state claim to this regex - stated ceiling, not
# closed, same shape as content_rules_shas's hex-word ceiling above.
content_rules_repo_state() (
  f="$(_content_rules_prep "$1")" || exit 0

  # Phrase-shaped lines (a-f below): a derivable count/state a lookup command already knows, no
  # sha-shape check needed.
  #   a: "<N> commit(s)/change(s) unpushed/ahead/behind/not yet pushed"
  #   b: "<N> ahead|behind"
  #   c: "ahead|behind [of X] by <N>"
  #   d: bare "unpushed"
  #   e: "(working )?tree (is )?clean" / "clean (working )?tree"
  #   f: "uncommitted"
  phrase_lines="$(grep -noEi \
    '[0-9]+ (commits?|changes?) (unpushed|ahead|behind|not yet pushed)|[0-9]+ (ahead|behind)\b|(ahead|behind) (of [^ ]+ )?by [0-9]+|\bunpushed\b|(working )?tree (is )?clean\b|\bclean (working )?tree\b|\buncommitted\b' \
    "$f" 2>/dev/null | cut -d: -f1)"

  # Sha-shaped lines (g): a 7-40 lowercase-hex token (>=1 digit, >=1 a-f letter, same test as
  # content_rules_shas) sitting within ~3 non-alphanumeric chars of a current-state marker - HEAD (or "HEAD is at")
  # BEFORE the token, or "not pushed" on either side ("unpushed" already fires as a bare
  # word above, so it is not repeated here). A bare "at" is NOT a marker: "shipped
  # at 205731d" is dated history, the shape this rule must leave alone.
  sha_lines="$(
    { grep -noEi '\bHEAD( is)?( at)?[^A-Za-z0-9]{0,3}[0-9a-f]{7,40}\b' "$f" 2>/dev/null
      grep -noEi '\bnot pushed\b[^A-Za-z0-9]{0,3}[0-9a-f]{7,40}\b' "$f" 2>/dev/null
      grep -noEi '[0-9a-f]{7,40}\b[^A-Za-z0-9]{0,3}(not pushed|\(local, not pushed)' "$f" 2>/dev/null
    } | while IFS=: read -r ln match; do
          tok="$(printf '%s' "$match" | grep -oEi '[0-9a-f]{7,40}' | tail -1)"
          case "$tok" in
            (*[a-fA-F]*[0-9]*|*[0-9]*[a-fA-F]*) printf '%s\n' "$ln" ;;
          esac
        done
  )"

  { printf '%s\n' "$phrase_lines"; printf '%s\n' "$sha_lines"; } \
    | grep -E '^[0-9]+$' | sort -nu | while IFS= read -r ln; do
        line="$(sed -n "${ln}p" "$f" 2>/dev/null)"
        # Exclusions: a lookup command citing the state (not asserting it), a CLI flag, or a count
        # written with the literal placeholder "N" rather than a real number.
        printf '%s' "$line" | grep -Eq '`git |git -C |git log|git status|--uncommitted' && continue
        printf '%s' "$line" | grep -Eq '\bN (commit|unpushed|ahead|behind)' && continue
        printf '%s: repo-state:%s\n' "$ln" "$line"
      done
  rm -f "$f" 2>/dev/null || true
)

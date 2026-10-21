#!/usr/bin/env sh
# kit-scope: shared
# Self-check for docs-nav.sh. Runnable: `sh docs-nav.selfcheck.sh`.
set -u
HERE="$(CDPATH= cd "$(dirname "$0")" && pwd)"
NAV="$HERE/docs-nav.sh"
fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

# --- calibration fixture, byte-exact -----------------------------------------------------------
cat > "$T/want" <<'EOT'
| <img src="spacer.svg" width="27" height="1">[**README**](../../README.md)<img src="spacer.svg" width="27" height="1"> | <img src="spacer.svg" width="5" height="1">**Why delegate**<img src="spacer.svg" width="6" height="1"> | <img src="spacer.svg" width="9" height="1">[**Work shapes**](../usage.md#work-shapes)<img src="spacer.svg" width="9" height="1"> | <img src="spacer.svg" width="1" height="1">[**Choosing a level**](../usage.md#choosing-a-level)<img src="spacer.svg" width="1" height="1"> | <img src="spacer.svg" width="13" height="1">[**After install**](../usage.md#what-changes-after-install)<img src="spacer.svg" width="13" height="1"> | <img src="spacer.svg" width="26" height="1">[**Glossary**](../usage.md#glossary)<img src="spacer.svg" width="26" height="1"> |
|:-:|:-:|:-:|:-:|:-:|:-:|

<hr>
EOT
sh "$NAV" -w 120 -s spacer.svg 'Why delegate' 'README=../../README.md' 'Why delegate=' \
  'Work shapes=../usage.md#work-shapes' 'Choosing a level=../usage.md#choosing-a-level' \
  'After install=../usage.md#what-changes-after-install' 'Glossary=../usage.md#glossary' > "$T/got"
cmp -s "$T/want" "$T/got" && ok "calibration fixture byte-exact (4 lines)" || bad "calibration fixture differs"

# --- -w 200: README W=66, so 67+67 ------------------------------------------------------------
OUT="$(sh "$NAV" -w 200 -s s.svg README 'README=')"
case "$OUT" in
  *'width="67" height="1">**README**<img src="s.svg" width="67"'*) ok "-w 200 pads README 67+67" ;;
  *) bad "-w 200 padding: $OUT" ;;
esac

# --- current bold unlinked, others linked; '=' in link survives; default spacer ----------------
OUT="$(sh "$NAV" A 'A=' 'B=x?a=b')"
case "$OUT" in *'**A**<img'*) ok "current label bold" ;; *) bad "current bold: $OUT" ;; esac
case "$OUT" in *'[**A**]'*) bad "current label linked" ;; *) ok "current label unlinked" ;; esac
case "$OUT" in *'[**B**](x?a=b)'*) ok "other label linked, '=' in link survives" ;; *) bad "link with =: $OUT" ;; esac
case "$OUT" in *'src="assets/spacer.svg"'*) ok "default -s is assets/spacer.svg" ;; *) bad "default -s: $OUT" ;; esac

# --- default width 108: README pads 21/21 (fits the repo home page README box) ---------------------
OUT="$(sh "$NAV" README 'README=' 'Why delegate=u.md')"
case "$OUT" in *'width="21" height="1">**README**<img src="assets/spacer.svg" width="21"'*) ok "default -w 108: README pads 21/21" ;; *) bad "default width: $OUT" ;; esac

# --- error cases: exit 2, empty stdout --------------------------------------------------------
err() {
  name="$1"; shift
  o="$(sh "$NAV" "$@" 2>/dev/null)"; rc=$?
  [ "$rc" -eq 2 ] && [ -z "$o" ] && ok "error: $name" || bad "error: $name (rc=$rc out=$o)"
}
err "no args"
err "unknown option" -x A 'A='
err "bad -w (zero)" -w 0 A 'A='
err "bad -w (text)" -w abc A 'A='
err "pair with no =" A 'A=' B
err "empty label" A 'A=' '=x'
err "label with |" A 'A=' 'B|C=x'
err "non-current empty link" A 'A=' 'B='
err "current label matches none" Z 'A=' 'B=x'
err "label with newline" A 'A=' 'B
C=x'
err "link with newline" A 'A=' 'B=x
y.md'

# --- `--` ends options: a label may start with '-' --------------------------------------------
OUT="$(sh "$NAV" -- -a '-a=' 'B=x.md' 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && case "$OUT" in *'**-a**'*) true ;; *) false ;; esac && ok "-- allows a label starting with -" || bad "--: rc=$rc $OUT"

# --- non-ASCII label: no crash, numeric width ---------------------------------------------------
LBL="$(printf 'Caf\303\251')"
OUT="$(sh "$NAV" -w 120 "$LBL" "$LBL=" 2>&1)"; rc=$?
case "$OUT" in *'<img src="assets/spacer.svg" width="'[0-9]*'" height="1">'*) n=1 ;; *) n=0 ;; esac
[ "$rc" -eq 0 ] && [ "$n" -eq 1 ] && ok "non-ASCII label yields numeric width" || bad "non-ASCII: rc=$rc $OUT"
# C 642 + a 599 + f 387 + 2-byte char 600 = 2228 units -> 35.6 -> 36 px; pad 84 -> 42/42
case "$OUT" in *'width="42" height="1">**'"$LBL"'**<img src="assets/spacer.svg" width="42"'*) ok "non-ASCII exact pads 42/42" ;; *) bad "non-ASCII pads: $OUT" ;; esac

if [ "$fail" -eq 0 ]; then echo "ALL PASS"; else echo "SELF-CHECK FAILED"; exit 1; fi

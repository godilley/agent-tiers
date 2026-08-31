#!/usr/bin/env sh
# kit-scope: shared
# Self-check for security-gate.sh. Runnable: `sh security-gate.selfcheck.sh`.
set -u
DIR="$(CDPATH= cd "$(dirname "$0")" && pwd)"
GUARD="$DIR/security-gate.sh"
# decision/breadcrumb lines go to a SANDBOX log, never the real kit's .state/guards.log (opus reviewer, Wave D:
# in-place selfchecks had filled the live record with fixture noise)
SBLOG="$(mktemp -d)/guards.log"; export AGENT_TIERS_GUARDS_LOG="$SBLOG"
fail=0

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq absent (guard fails open by design)"; exit 0; }

check() { # $1=want $2=tool $3=field $4=text $5=pathfield(default file_path) $6=path(default app.py)
  want="$1"; tool="$2"; field="$3"; text="$4"; pathfield="${5:-file_path}"; path="${6:-app.py}"
  out="$(jq -n --arg t "$tool" --arg f "$field" --arg x "$text" --arg pf "$pathfield" --arg p "$path" \
    '{tool_name: $t, tool_input: ({($pf): $p} + {($f): $x})}' | sh "$GUARD" 2>/dev/null || true)"
  if printf '%s' "$out" | grep -aq '"permissionDecision": *"deny"'; then got=deny; else got=allow; fi
  if [ "$got" = "$want" ]; then printf 'ok   [%s] %s (%s)\n' "$got" "$text" "$path"; else
    printf 'FAIL want=%s got=%s : %s (%s)\n' "$want" "$got" "$text" "$path"; fail=1; fi
}

# should DENY - secrets/keys (curated provider shapes, expanded 2026-08-06 review)
check deny Write content 'STRIPE_KEY = "sk-abcdefghijklmnopqrstuvwx"'
check deny Write content 'token = "ghp_abcdefghijklmnopqrstuvwxyz012345"'
check deny Write content 'aws_key = "AKIAABCDEFGHIJKLMNOP"'
check deny Write content 'anthropic_key = "sk-ant-api03-abcdefghijklmnopqrstuvwx"'
check deny Write content 'openai_key = "sk-proj-abcdefghijklmnopqrstuvwx"'
check deny Write content 'google_key = "AIzaSyAbcdefghijklmnopqrstuvwxyz0123456"'
check deny Write content 'gh_pat = "github_pat_abcdefghijklmnopqrstuvwx"'
check deny Write content 'sts_key = "ASIAABCDEFGHIJKLMNOP"'
check deny Edit new_string 'password: "hunter2hunter2"'
check deny Write content '-----BEGIN RSA PRIVATE KEY-----'

# should DENY - injection shapes
check deny Write content 'query = "SELECT * FROM users WHERE id = " + user_id + " LIMIT 1"'
check deny Write content 'subprocess.run("ls " + user_input)'
check deny Write content 'eval("x = " + user_input)'
check deny Write content 'path = "../../../etc/passwd"'
check deny Write content 'key_path = "../../.ssh/id_rsa"'

# should ALLOW - the SQLi false positive round 1 caught (SQL keyword and concat operator on
# UNRELATED lines of the same file - must not co-trigger)
check allow Write content 'def select_user(id):
    return db.get(id)

x = "${BASE:-/tmp}" + suffix'
check allow Write content 'jq --arg c "$2" .[$1] | select(. == $c)'

# should ALLOW - the residual SQLi false positive round 2 caught (a SQL VERB word present, but no
# clause keyword on the same line - real code, not a query)
check allow Write content 'npm config --loglevel=warn delete prefix --userconfig="${NVM_NPM_BUILTIN_NPMRC}"'
check allow Write content 'git update-ref "$REF" "${commit}"'
check allow Write content 'delete cache["${key}"]'

# should ALLOW - other benign content
check allow Write content 'def add(a, b):\n    return a + b'
check allow Write content 'cursor.execute("SELECT * FROM users WHERE id = ?", (user_id,))'
check allow Write content 'STRIPE_KEY = os.environ["STRIPE_KEY"]'
check allow Write content 'ANTHROPIC_API_KEY = os.environ["ANTHROPIC_API_KEY"]'
check allow Write content '# see .env.example for the key format'
check allow Edit new_string 'x = 1 + 2'
check allow Write content "import from '../../../shared/utils'"   # deep relative import, not sensitive
check allow Write content 'from ..config import settings'

# should DENY - NotebookEdit uses its OWN field names (notebook_path/new_source, not file_path/content)
check deny NotebookEdit new_source 'sk-ant-api03-abcdefghijklmnopqrstuvwx' notebook_path
check allow NotebookEdit new_source 'print("hello world")' notebook_path

# regression (round 2, HIGH): the guard must not deny writing/editing its OWN (or any) test fixture
# containing an intentionally-fake key-shaped string - this exact selfcheck's own content would have
# been undeployable pre-fix.
check allow Write content 'check deny Write content "sk-abcdefghijklmnopqrstuvwx"' file_path /home/user/kit/scripts/security-gate.selfcheck.sh
check allow Write content 'FAKE_KEY = "AKIAABCDEFGHIJKLMNOP"' file_path /home/user/project/tests/fixtures.py
check allow Write content 'EXAMPLE_KEY = "sk-ant-api03-abcdefghijklmnopqrstuvwx"' file_path /home/user/project/.env.example
# but a NON-fixture path with the same content still denies - the exemption is path-scoped, not global
check deny Write content 'FAKE_KEY = "AKIAABCDEFGHIJKLMNOP"' file_path /home/user/project/src/config.py

# regression (round 3, MEDIUM): the `*fixture*` exemption was an unbound SUBSTRING, not a path
# segment - a real source file merely NAMED with "fixture" as part of its filename must NOT be exempt
check deny Write content 'FAKE_KEY = "AKIAABCDEFGHIJKLMNOP"' file_path /home/user/project/src/fixture_loader.py
check allow Write content 'FAKE_KEY = "AKIAABCDEFGHIJKLMNOP"' file_path /home/user/project/fixtures/keys.py

# regression (cold-review F5): `*/test*/*` globbed across `/`, exempting a whole repo whose checkout
# DIR starts with "test" - the same class round 3 closed for `fixture`. Segment must be exact.
check deny Write content 'FAKE_KEY = "AKIAABCDEFGHIJKLMNOP"' file_path /home/user/git/test-fixtures/config.py
check deny Write content 'FAKE_KEY = "AKIAABCDEFGHIJKLMNOP"' file_path /home/user/project/testing/keys.py
check allow Write content 'FAKE_KEY = "AKIAABCDEFGHIJKLMNOP"' file_path /home/user/project/tests/keys.py

# regression (round 3, MEDIUM): SQL verb+clause TOGETHER still false-denied ordinary English sharing
# a line with an f-string/interpolation - fixed by requiring uppercase SQL keywords
check allow Write content 'raise ValueError(f"cannot delete {n} rows from {table}")'
check allow Write content 'echo "removing ${n} entries; select from the cache first"'
# positive control: a real uppercase-written query still denies
check deny Write content 'q = "DELETE FROM sessions WHERE id = " + sid'

# regression (round 4, 2026-08-24): the f-string alt (`f["']`) had no left boundary - a real
# parameterized query using a PDO named placeholder ending in "f" false-denied on the string's own
# closing quote (`:f'`), same bug class as any word ending in "f" before a quote (`buf"`, `leaf'`)
check allow Edit new_string "\$writeSql = 'UPDATE repos SET originality = :o WHERE full_name = :f';"
check allow Write content 'msg = "UPDATE the changelog WHERE you shed a leaf"'
# positive control: a real f-string still denies (verb assembled - this file must not itself be
# SQL-shaped to the guard's own Write arm, same reason as the Bash SV trick above)
QV="SEL"; QV="${QV}ECT"
check deny Write content "q = ${QV} * FROM users WHERE id = f'{user_id}'"

# regression (round 3, LOW): an obvious placeholder value in docs/templates must not hard-deny with
# no override - the key-SHAPE checks are unaffected (a real key format doesn't collide with these words)
check allow Write content 'api_key = "your-api-key-here"'
check allow Write content 'password: "changeme123"'
check allow Write content 'token = "<YOUR_TOKEN>"'
# positive control: a real-looking (random) secret value still denies
check deny Edit new_string 'password: "hunter2hunter2"'

# --- Bash arm (T1.7, 2026-08-16): literal write payloads only ---------------------------------------
check_bash() { # $1=want $2=command $3=payload cwd (optional)
  out="$(jq -n --arg x "$2" --arg c "${3:-}" '{tool_name: "Bash", cwd: $c, tool_input: {command: $x}}' | sh "$GUARD" 2>/dev/null || true)"
  if printf '%s' "$out" | grep -aq '"permissionDecision": *"deny"'; then got=deny; else got=allow; fi
  if [ "$got" = "$1" ]; then printf 'ok   [%s] Bash: %.90s\n' "$got" "$2"; else
    printf 'FAIL want=%s got=%s : Bash: %s\n' "$1" "$got" "$2"; fail=1; fi
}
NL='
'
# A4 acceptance: a key shape redirected to disk denies; the same via Write already does; ls does not.
check_bash deny  "printf 'AKIAABCDEFGHIJKLMNOP' > /tmp/x.py"
check_bash deny  "echo 'token = \"ghp_abcdefghijklmnopqrstuvwxyz012345\"' >> ~/.config/app.env"
check_bash allow "ls -la"
check_bash allow "grep -r AKIAABCDEFGHIJKLMNOP . ; rg 'password = ' src"     # a SEARCH for the shape is not a write
check_bash allow "make 2>&1 | tail -20"                                        # no write shape (`>&` excluded; splitter also eats the `|`)
check_bash allow "printf 'AKIAABCDEFGHIJKLMNOP' > /dev/null"                   # /dev/* is not a write
# heredoc body, tee, sed -i, perl -pi (the shapes T1.7 named)
check_bash deny  "cat > /tmp/cfg.py <<'EOF'${NL}aws_key = \"AKIAABCDEFGHIJKLMNOP\"${NL}EOF"
check_bash deny  "printf '%s' 'sk-ant-api03-abcdefghijklmnopqrstuvwx' | tee /tmp/key.txt"
check_bash deny  "sed -i 's/PLACEHOLDER/AKIAABCDEFGHIJKLMNOP/' /tmp/config.py"
check_bash deny  "perl -pi -e 's/x/AKIAABCDEFGHIJKLMNOP/' /tmp/config.py"
check_bash deny  "python - <<'PY'${NL}import subprocess${NL}subprocess.run(f\"ls {user_input}\", shell=True)${NL}PY"   # eval/exec check reaches heredoc code
# fixture exemption reads the redirect target: same fake key into a fixtures/ path is allowed
check_bash allow "printf 'AKIAABCDEFGHIJKLMNOP' > /home/user/project/tests/fixtures/keys.py"
check_bash deny  "printf 'AKIAABCDEFGHIJKLMNOP' > /home/user/git/test-fixtures/config.py"   # segment-bound, same as Write
# a write with no guarded shape is fine
check_bash allow "echo 'hello' > /tmp/greeting.txt && cat /tmp/greeting.txt"
# opus reviewer, Wave B (2026-08-16) - the failure modes the first 16 missed:
check_bash deny  "printf 'password: \"hunter2hunter2\"' > /tmp/app.conf 2>/dev/null"      # /dev/ exclusion is redirect-scoped, f still counts
check_bash deny  "echo 'password: \"hunter2hunter2\"; x=1' > /tmp/a.conf"                # `;` inside the payload: whole command is scanned
check_bash deny  "sed -i 's/a;b/AKIAABCDEFGHIJKLMNOP/' /tmp/config.py"                     # same, tool leg
check_bash deny  "echo x > /home/user/project/tests/fixtures/f && printf 'AKIAABCDEFGHIJKLMNOP' > /home/user/project/src/config.py"   # a fixture write must not exempt a later real one
check_bash deny  "sed -n -i 's/x/AKIAABCDEFGHIJKLMNOP/' /tmp/config.py"                    # option token before -i
check_bash deny  "printf 'AKIAABCDEFGHIJKLMNOP' | (tee /tmp/k.txt)"                         # subshell-wrapped tee
# (the SQL verb is assembled here so this file is not itself SQL-shaped to the guard's Write arm)
SV="SEL"; SV="${SV}ECT"
check_bash allow "psql -c '$SV count(*) FROM orders WHERE id = \${ID}' > /tmp/out.csv"     # query PASSED to a client, output redirected: not a code write
check_bash allow "rg 'cout << x' src/ && git log --oneline | head"                          # `<<` that is not a heredoc: no write shape at all
# relative fixture target resolved against the payload cwd (the normal way a fixture is written from Bash)
check_bash allow "echo 'FAKE = \"AKIAABCDEFGHIJKLMNOP\"' > tests/keys.py" /home/user/project
check_bash deny  "echo 'FAKE = \"AKIAABCDEFGHIJKLMNOP\"' > src/keys.py" /home/user/project      # control: relative NON-fixture target still denies
# the code-shape tail has no fixture hatch; the secret tail does (opus reviewer: the hatch was offered by checks that ignore it)
out="$(jq -n --arg sv "$SV" '{tool_name:"Bash", tool_input:{command:("cat > /tmp/q.py <<EOF\nq = \"" + $sv + " * FROM t WHERE id = \" + x\nEOF")}}' | sh "$GUARD" 2>/dev/null || true)"
if printf '%s' "$out" | grep -aq 'no path-based exemption' && ! printf '%s' "$out" | grep -aq 'fixtures/ path'; then printf 'ok   [deny] Bash: SQL heredoc denies with the CODE tail (no fixture hatch)\n'
else printf 'FAIL SQL heredoc did not use the code tail: %.200s\n' "$out"; fail=1; fi
# regression (round 4 follow-up, 2026-08-24): the f-string boundary class must also cover `[f"`/
# `{f"` (list/dict literal f-strings) - narrowed too far on the first pass would silently drop real
# coverage. Call name assembled (like the SV trick above) so this file isn't itself flagged.
RUN="run"; PC="[f'ls {user_input}']"
check_bash deny "python - <<'PY'${NL}subprocess.${RUN}(${PC}, shell=True)${NL}PY"
# NOT a write-shaped command even though it contains the word: python one-liner writing generated content
# is a DISCLOSED ceiling (bypass set, entry 2) - pinned as allow so a future change is a conscious one.
check_bash allow "python3 -c 'open(\"/tmp/f\",\"w\").write(chr(65)*20)'"

# Wave D: every deny writes a decision line `<ts> security-gate deny: ... [sid=<id>]` to guards.log
FK="AKIA"; FK="${FK}ABCDEFGHIJKLMNOP"   # assembled: this line must not itself be key-shaped to leak-scan
out="$(jq -n --arg k "$FK" '{tool_name:"Write", session_id:"sess-xyz", tool_input:{file_path:"app.py", content:("aws_key = \"" + $k + "\"")}}' | sh "$GUARD" 2>/dev/null || true)"
grep -aqE '^[^ ]+ security-gate deny: Write .*\[sid=sess-xyz\]$' "$SBLOG" && printf 'ok   decision line written to guards.log with sid\n' || { printf 'FAIL no decision line in sandbox log\n'; fail=1; }
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "SELF-CHECK FAILED"; exit 1; }

#!/bin/sh
# Self-check for .githooks/pre-commit. Builds a throwaway git repo under a temp dir, copies the hook
# into it, and asserts staging behavior - never touches this repo's real index or hooks.
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
HOOK="$HERE/pre-commit"

fail=0
note() { printf '%s\n' "$1" >&2; fail=1; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

cd "$tmp" || exit 1
git init -q .
git config user.email user@example.com   # the address leak-scan.sh already allows (EMAIL_ALLOW), so this fixture does not flag the kit's own commit gate on every commit
git config user.name test
mkdir -p .githooks scripts
cp "$HOOK" .githooks/pre-commit
chmod +x .githooks/pre-commit
git config core.hooksPath .githooks

# a.py + passing selfcheck
cat > scripts/a.py <<'EOF'
print("a")
EOF
cat > scripts/a.selfcheck.py <<'EOF'
print("OK a")
EOF

# b.py + failing selfcheck
cat > scripts/b.py <<'EOF'
print("b")
EOF
cat > scripts/b.selfcheck.py <<'EOF'
import sys
print("FAIL b")
sys.exit(1)
EOF

# unrelated file, no sibling selfcheck
echo "hello" > unrelated.txt

# a selfcheck that prints SKIP (nonzero-exit-free but must still block)
cat > scripts/c.py <<'EOF'
print("c")
EOF
cat > scripts/c.selfcheck.py <<'EOF'
print("SKIP nothing to check here")
EOF

git add scripts/a.py scripts/a.selfcheck.py scripts/b.py scripts/b.selfcheck.py \
        scripts/c.py scripts/c.selfcheck.py unrelated.txt

# --- case 1: staging only a.py allows the commit ---
git reset -q
git add scripts/a.py scripts/a.selfcheck.py
if ! git commit -q -m "a only" >/tmp/pc_out_1 2>&1; then
    note "case1 FAILED: commit of passing a.py was blocked"
fi

# --- case 2: staging b.py blocks it, and names the failing selfcheck ---
git add scripts/b.py scripts/b.selfcheck.py
out2=$(git commit -q -m "b too" 2>&1)
rc2=$?
if [ "$rc2" -eq 0 ]; then
    note "case2 FAILED: commit with failing b.selfcheck.py was allowed"
fi
if ! printf '%s\n' "$out2" | grep -q "b.selfcheck.py"; then
    note "case2 FAILED: block message did not name b.selfcheck.py: $out2"
fi
git reset -q --hard HEAD

# --- case 3: staging an unrelated file allows it ---
git add unrelated.txt
if ! git commit -q -m "unrelated" >/tmp/pc_out_3 2>&1; then
    note "case3 FAILED: commit of unrelated.txt was blocked"
fi

# --- case 4: a selfcheck printing SKIP blocks ---
git add scripts/c.py scripts/c.selfcheck.py
out4=$(git commit -q -m "c" 2>&1)
rc4=$?
if [ "$rc4" -eq 0 ]; then
    note "case4 FAILED: commit with a SKIP-printing selfcheck was allowed"
fi
if ! printf '%s\n' "$out4" | grep -q "c.selfcheck.py"; then
    note "case4 FAILED: block message did not name c.selfcheck.py: $out4"
fi

if [ "$fail" -ne 0 ]; then
    echo "FAIL pre-commit hook selfcheck"
    exit 1
fi
echo "OK pre-commit hook: passing selfcheck allows, failing/SKIP selfcheck blocks and is named, unrelated files pass through"
exit 0

#!/bin/sh
# Seatbelt Keychain investigation - Run OUTSIDE jailrun sandbox
#
# This script must be executed outside any sandbox (not via jailrun)
# because sandbox-exec cannot be nested.
#
# Usage: sh tests/investigate_keychain_seatbelt.sh
#
# Output: structured scenario results to stdout
# Format: scenario_id:verdict:confidence:error_kind:evidence_summary
#
# NOTE: KC-02-S3 requires network access (curl to external HTTPS site)

set -e

if [ "${_CREDENTIAL_GUARD_SANDBOXED:-}" = "1" ]; then
  echo "ERROR: This script must run OUTSIDE jailrun sandbox." >&2
  echo "Run directly: sh tests/investigate_keychain_seatbelt.sh" >&2
  exit 1
fi

if ! command -v sandbox-exec >/dev/null 2>&1; then
  echo "KC-00:inconclusive:high:env_error:sandbox-exec not found"
  exit 1
fi

_tmpdir=$(mktemp -d)
_test_id="jailrun-inv-$$-$(date +%s)"
_test_items=""

_cleanup() {
  # Remove all test keychain items created during investigation
  for _item in $_test_items; do
    security delete-generic-password -s "$_item" -a "test" >/dev/null 2>&1 || true
  done
  rm -rf "$_tmpdir"
}
trap '_cleanup' EXIT

_keychains_dir="$HOME/Library/Keychains"
_login_db="$_keychains_dir/login.keychain-db"

echo "# Seatbelt Keychain Investigation Results" >&2
echo "# macOS: $(sw_vers -productVersion) ($(sw_vers -buildVersion))" >&2
echo "# Date: $(date -u +%Y-%m-%dT%H:%M:%SZ)" >&2
echo "# Keychains dir: $_keychains_dir" >&2
echo "" >&2

# === KC-01: keychain-access-* operations ===
echo "# KC-01: keychain-access-* operations" >&2

# S1: deny keychain-access-read-item
cat > "$_tmpdir/kc01s1.sb" <<'EOF'
(version 1)
(allow default)
(deny keychain-access-read-item)
EOF
if sandbox-exec -f "$_tmpdir/kc01s1.sb" /usr/bin/true 2>"$_tmpdir/kc01s1.err"; then
  echo "KC-01-S1:controllable:high:none:keychain-access-read-item accepted"
else
  _err=$(head -1 "$_tmpdir/kc01s1.err" | tr ':' '=' | head -c 200)
  echo "KC-01-S1:not_controllable:high:none:${_err}"
fi

# S2: deny keychain-access-modify-item
cat > "$_tmpdir/kc01s2.sb" <<'EOF'
(version 1)
(allow default)
(deny keychain-access-modify-item)
EOF
if sandbox-exec -f "$_tmpdir/kc01s2.sb" /usr/bin/true 2>"$_tmpdir/kc01s2.err"; then
  echo "KC-01-S2:controllable:high:none:keychain-access-modify-item accepted"
else
  _err=$(head -1 "$_tmpdir/kc01s2.err" | tr ':' '=' | head -c 200)
  echo "KC-01-S2:not_controllable:high:none:${_err}"
fi

# S3: deny keychain-access-add-item
cat > "$_tmpdir/kc01s3.sb" <<'EOF'
(version 1)
(allow default)
(deny keychain-access-add-item)
EOF
if sandbox-exec -f "$_tmpdir/kc01s3.sb" /usr/bin/true 2>"$_tmpdir/kc01s3.err"; then
  echo "KC-01-S3:controllable:high:none:keychain-access-add-item accepted"
else
  _err=$(head -1 "$_tmpdir/kc01s3.err" | tr ':' '=' | head -c 200)
  echo "KC-01-S3:not_controllable:high:none:${_err}"
fi

echo "" >&2

# === KC-02: File-level Keychain control ===
echo "# KC-02: File-level Keychain control" >&2

# S1: deny file-read* on login.keychain-db
# NOTE: Uses non-existent item name. This test verifies that SecurityServer
# can still search the keychain (returning "not found" rather than "denied").
# A more rigorous test would create a known item first, but the key signal is
# whether the error is "item not found" vs "operation denied by sandbox".
cat > "$_tmpdir/kc02s1.sb" <<SBEOF
(version 1)
(allow default)
(deny file-read*
  (literal "$_login_db"))
SBEOF
if sandbox-exec -f "$_tmpdir/kc02s1.sb" security find-generic-password -s "jailrun-nonexistent" 2>"$_tmpdir/kc02s1.err"; then
  echo "KC-02-S1:not_controllable:high:none:file-read deny on login.keychain-db had no effect"
elif grep -q "deny" "$_tmpdir/kc02s1.err" 2>/dev/null; then
  echo "KC-02-S1:controllable:high:none:file-read deny blocked keychain access"
else
  _err=$(head -1 "$_tmpdir/kc02s1.err" | tr ':' '=' | head -c 200)
  echo "KC-02-S1:partial:medium:none:${_err}"
fi

# S2: deny file-write* on login.keychain-db
_kc02_item="${_test_id}-kc02"
_test_items="$_test_items $_kc02_item"
cat > "$_tmpdir/kc02s2.sb" <<SBEOF
(version 1)
(allow default)
(deny file-write*
  (literal "$_login_db"))
SBEOF
if sandbox-exec -f "$_tmpdir/kc02s2.sb" security add-generic-password -s "$_kc02_item" -a "test" -w "test" 2>"$_tmpdir/kc02s2.err"; then
  echo "KC-02-S2:not_controllable:high:none:file-write deny on login.keychain-db had no effect"
else
  _err=$(head -1 "$_tmpdir/kc02s2.err" | tr ':' '=' | head -c 200)
  echo "KC-02-S2:controllable:high:none:file-write deny blocked write ${_err}"
fi

# S3: TLS with file-read deny on Keychains
# NOTE: This test requires network access (external HTTPS endpoint).
# It verifies that TLS certificate verification uses /Library/Keychains/System.keychain
# rather than ~/Library/Keychains.
cat > "$_tmpdir/kc02s3.sb" <<SBEOF
(version 1)
(allow default)
(deny file-read*
  (subpath "$_keychains_dir"))
SBEOF
if _out=$(sandbox-exec -f "$_tmpdir/kc02s3.sb" curl -s -o /dev/null -w "%{http_code}" https://www.google.com 2>"$_tmpdir/kc02s3.err"); then
  if [ "$_out" = "200" ]; then
    echo "KC-02-S3:not_controllable:high:none:TLS works even with Keychains dir file-read deny"
  else
    echo "KC-02-S3:partial:medium:none:curl returned HTTP ${_out}"
  fi
else
  _err=$(head -1 "$_tmpdir/kc02s3.err" | tr ':' '=' | head -c 200)
  echo "KC-02-S3:controllable:high:none:TLS broken by Keychains file-read deny ${_err}"
fi

echo "" >&2

# === KC-03: Write scope narrowing ===
echo "# KC-03: Write scope narrowing (subpath -> literal/regex)" >&2

# S1: allow only login.keychain-db literal write
_kc03_item="${_test_id}-kc03"
_test_items="$_test_items $_kc03_item"
cat > "$_tmpdir/kc03s1.sb" <<SBEOF
(version 1)
(allow default)
(deny file-write*
  (require-not
    (require-any
      (subpath "/tmp")
      (subpath "/private/tmp")
      (subpath "/private/var/folders")
      (literal "/dev/null")
      (literal "$_login_db")
      (literal "$_keychains_dir/metadata.keychain-db"))))
SBEOF
echo "KC-03-S1 profile: literal login.keychain-db + metadata.keychain-db" >&2
if sandbox-exec -f "$_tmpdir/kc03s1.sb" security add-generic-password -s "$_kc03_item" -a "test" -w "test" 2>"$_tmpdir/kc03s1.err"; then
  echo "KC-03-S1:controllable:high:none:literal write scope allows keychain add"
else
  _err=$(head -1 "$_tmpdir/kc03s1.err" | tr ':' '=' | head -c 200)
  echo "KC-03-S1:partial:medium:none:literal scope insufficient ${_err}"
fi

# S2: regex with open-ended prefix match (no $ anchor)
# NOTE: strict regex (-wal|-shm)?$ was tested and FAILED because SecurityServer
# writes to files beyond just -wal/-shm. Open-ended regex allows all files
# prefixed with login.keychain-db or metadata.keychain-db.
_kc03r_item="${_test_id}-kc03r"
_test_items="$_test_items $_kc03r_item"
_home_escaped=$(printf '%s' "$HOME" | sed 's/[][(){}.^$+*?|\\]/\\&/g')
cat > "$_tmpdir/kc03s2.sb" <<SBEOF
(version 1)
(allow default)
(deny file-write*
  (require-not
    (require-any
      (subpath "/tmp")
      (subpath "/private/tmp")
      (subpath "/private/var/folders")
      (literal "/dev/null")
      (regex #"^${_home_escaped}/Library/Keychains/(login|metadata)\\.keychain-db"))))
SBEOF
echo "KC-03-S2 profile: regex for login|metadata keychain-db (open-ended)" >&2
if sandbox-exec -f "$_tmpdir/kc03s2.sb" security add-generic-password -s "$_kc03r_item" -a "test" -w "test" 2>"$_tmpdir/kc03s2.err"; then
  echo "KC-03-S2:controllable:high:none:regex write scope allows keychain add"
else
  _err=$(head -1 "$_tmpdir/kc03s2.err" | tr ':' '=' | head -c 200)
  echo "KC-03-S2:partial:medium:none:regex scope insufficient ${_err}"
fi

echo "" >&2
echo "# Investigation complete" >&2

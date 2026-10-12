#!/usr/bin/env bash
# Tests scripts/check-scan-lib.sh (scan_answer) on its own, with the shared stub scanner.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/check-testlib.sh"
. "$HERE/check-scan-lib.sh"
W=$(mktemp -d "${TMPDIR:-/tmp}/sl.XXXXXX") || exit 2; trap 'rm -rf "$W"' EXIT
write_gitleaks_stub "$W"; STUB_SHA=$(sha256sum "$W/gitleaks" | cut -c1-64)
mkdir -p "$W/clean" "$W/leak"; echo "nothing here" > "$W/clean/a.md"; echo "key LEAKME" > "$W/leak/a.md"
GITLEAKS_BIN="$W/gitleaks" GITLEAKS_SHA256="$STUB_SHA" scan_answer "$W/clean"; [ $? = 0 ] && t PASS "clean text: 0" || t FAIL "clean text"
GITLEAKS_BIN="$W/gitleaks" GITLEAKS_SHA256="$STUB_SHA" scan_answer "$W/leak"; [ $? = 3 ] && t PASS "a secret: 3" || t FAIL "a secret"
GL_RC=2 GITLEAKS_BIN="$W/gitleaks" GITLEAKS_SHA256="$STUB_SHA" scan_answer "$W/clean"; [ $? = 2 ] && t PASS "a scanner error code is passed through" || t FAIL "error code"
out=$(GITLEAKS_BIN="$W/none" scan_answer "$W/clean" 2>&1); rc=$?; [ $rc = 1 ] && grep -q "no gitleaks at" <<<"$out" && t PASS "a missing scanner: 1 with the cause on stderr" || t FAIL "missing ($rc)"
out=$(GITLEAKS_BIN="$W/gitleaks" GITLEAKS_SHA256=0000000000000000000000000000000000000000000000000000000000000000 scan_answer "$W/clean" 2>&1); rc=$?
[ $rc = 1 ] && grep -q "has sha256 $STUB_SHA, expected 0000" <<<"$out" && t PASS "a wrong hash: 1 with both hashes on stderr" || t FAIL "wrong hash ($rc)"
out=$(GITLEAKS_BIN="$W/gitleaks" scan_answer "$W/clean" 2>&1); rc=$?; [ $rc = 1 ] && grep -q "expected $GITLEAKS_PINNED_SHA256" <<<"$out" && t PASS "with GITLEAKS_SHA256 unset the pinned constant is the only hash accepted" || t FAIL "pinned default ($rc)"
# The private copy: a stub that replaces the original on its first run; the scan still used the checked copy.
S3=$(mktemp -d "$W/swap.XXXXXX"); printf '#!/usr/bin/env bash\nprintf "#!/usr/bin/env bash\\nexit 0\\n" > "%s/gitleaks"; src=""; for a in "$@"; do case "$a" in --source=*) src=${a#--source=};; esac; done; grep -q LEAKME "$src"/* && exit 3; exit 0\n' "$S3" > "$S3/gitleaks"; chmod +x "$S3/gitleaks"
GITLEAKS_BIN="$S3/gitleaks" GITLEAKS_SHA256=$(sha256sum "$S3/gitleaks" | cut -c1-64) scan_answer "$W/leak"; [ $? = 3 ] && t PASS "the scan runs a private copy (a self-replacing original still scans)" || t FAIL "private copy"
# No work directory is left behind: a fresh TMPDIR for one clean scan and one refused scan must be empty afterwards.
T2=$(mktemp -d "$W/tmpdir.XXXXXX"); TMPDIR="$T2" GITLEAKS_BIN="$W/gitleaks" GITLEAKS_SHA256="$STUB_SHA" scan_answer "$W/clean" >/dev/null 2>&1
TMPDIR="$T2" GITLEAKS_BIN="$W/gitleaks" GITLEAKS_SHA256=0000000000000000000000000000000000000000000000000000000000000000 scan_answer "$W/clean" >/dev/null 2>&1
[ -z "$(ls -A "$T2")" ] && t PASS "no work directory is left behind (clean scan and refused hash)" || { t FAIL "work directory left behind: $(ls -A "$T2")"; }
# The failure paths of the private copy: an unreadable binary (it is executable, so the -x check passes) and an unwritable TMPDIR.
UNREAD=$(mktemp -d "$W/unread.XXXXXX"); cp "$W/gitleaks" "$UNREAD/gitleaks"; chmod 111 "$UNREAD/gitleaks"
if [ "$(id -u)" = 0 ]; then t PASS "unreadable binary: skipped (root reads everything)"; else
  GITLEAKS_BIN="$UNREAD/gitleaks" GITLEAKS_SHA256="$STUB_SHA" scan_answer "$W/clean" >/dev/null 2>&1; [ $? = 1 ] && t PASS "an unreadable binary cannot be copied: 1" || t FAIL "unreadable binary"; fi
RO=$(mktemp -d "$W/ro.XXXXXX"); chmod 500 "$RO"
if [ "$(id -u)" = 0 ]; then t PASS "unwritable TMPDIR: skipped (root writes everywhere)"; else
  TMPDIR="$RO" GITLEAKS_BIN="$W/gitleaks" GITLEAKS_SHA256="$STUB_SHA" scan_answer "$W/clean" >/dev/null 2>&1; [ $? = 1 ] && t PASS "an unwritable TMPDIR (no work directory): 1" || t FAIL "unwritable TMPDIR"; fi
chmod 700 "$RO"
# The pinned constant matches the real binary when it is installed (CI installs it at /tmp/gitleaks); skipped otherwise.
REAL="${GITLEAKS:-/tmp/gitleaks}"
if [ -x "$REAL" ]; then [ "$(sha256sum "$REAL" | cut -c1-64)" = "$GITLEAKS_PINNED_SHA256" ] && t PASS "the pinned constant is the installed gitleaks 8.18.4 binary's sha256" || t FAIL "GITLEAKS_PINNED_SHA256 does not match $REAL"
elif [ -n "${CI:-}" ]; then t FAIL "pinned constant vs real binary: no binary at $REAL under CI (install-gitleaks must run first)"
else t PASS "pinned constant vs real binary: skipped (no binary at $REAL; CI fails here)"; fi
summary

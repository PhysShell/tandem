#!/usr/bin/env bash
#
# Operator identity contract tests. Self-contained and safe: uses id/getent
# shims so it never depends on the runner's real user, and never builds or
# activates anything (the "correct identity" case stops at the verify-only gate).
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
ops="$root/deploy/ops"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
shim="$tmp/bin"
mkdir -p "$shim"

# id / getent shims driven by FAKE_UID / FAKE_USER / FAKE_HOME.
cat >"$shim/id" <<'SH'
#!/bin/sh
case "${1:-}" in
  -u)  echo "${FAKE_UID:-1000}" ;;
  -un) echo "${FAKE_USER:-nobody}" ;;
  -gn) echo "${FAKE_USER:-nobody}" ;;
  *)   echo "${FAKE_USER:-nobody}" ;;
esac
SH
cat >"$shim/getent" <<'SH'
#!/bin/sh
if [ "${1:-}" = passwd ]; then
  printf '%s:x:1000:1000::%s:/bin/bash\n' "$2" "${FAKE_HOME:-/home/$2}"
fi
SH
chmod +x "$shim"/*

fails=0
check() { # label expected_rc needle actual_rc out
  local label="$1" exp="$2" needle="$3" rc="$4" out="$5"
  if [ "$rc" = "$exp" ] && printf '%s' "$out" | grep -qi "$needle"; then
    echo "  ok   ${label} (rc=${rc})"
  else
    echo "  FAIL ${label} (rc=${rc}, expected ${exp}, needle '${needle}')"
    printf '%s\n' "$out" | sed 's/^/      | /'
    fails=$((fails + 1))
  fi
}

# Common production/staging identity env.
P_HM="tandem@tandem-vps"
P_USER="tandem"
P_HOME="/home/tandem"
S_HM="tandem-staging@tandem-vps"
S_USER="tandem-staging"
S_HOME="/home/tandem-staging"

echo "== operator identity contract =="

# 1. root -> FAIL (production deploy)
out="$(PATH="$shim:$PATH" env FAKE_UID=0 FAKE_USER=root \
  TANDEM_FLAKE="$root" TANDEM_HM_NAME="$P_HM" TANDEM_TARGET_USER="$P_USER" \
  TANDEM_TARGET_HOME="$P_HOME" HOME="$P_HOME" bash "$ops/deploy.sh" 2>&1)"
check "root -> deploy FAIL" 1 "root" $? "$out"

# 2. production deploy under wrong user -> FAIL (before activation)
out="$(PATH="$shim:$PATH" env FAKE_UID=1000 FAKE_USER=intruder \
  TANDEM_FLAKE="$root" TANDEM_HM_NAME="$P_HM" TANDEM_TARGET_USER="$P_USER" \
  TANDEM_TARGET_HOME="$P_HOME" HOME="$P_HOME" bash "$ops/deploy.sh" 2>&1)"
check "wrong-user -> deploy FAIL" 1 "identity mismatch" $? "$out"

# 3. production OUTPUT + staging USER -> FAIL (cannot mix)
out="$(PATH="$shim:$PATH" env FAKE_UID=1000 FAKE_USER="$S_USER" \
  TANDEM_FLAKE="$root" TANDEM_HM_NAME="$P_HM" TANDEM_TARGET_USER="$S_USER" \
  TANDEM_TARGET_HOME="$S_HOME" HOME="$S_HOME" bash "$ops/deploy.sh" 2>&1)"
check "prod-output+staging-user -> FAIL" 1 "output/user mismatch" $? "$out"

# 4. production rollback under wrong user -> FAIL
out="$(PATH="$shim:$PATH" env FAKE_UID=1000 FAKE_USER=intruder \
  TANDEM_FLAKE="$root" TANDEM_HM_NAME="$P_HM" TANDEM_TARGET_USER="$P_USER" \
  TANDEM_TARGET_HOME="$P_HOME" HOME="$P_HOME" bash "$ops/rollback.sh" 2>&1)"
check "wrong-user -> rollback FAIL" 1 "identity mismatch" $? "$out"

# 5. staging check under production user -> FAIL
out="$(PATH="$shim:$PATH" env FAKE_UID=1000 FAKE_USER="$P_USER" \
  TANDEM_FLAKE="$root" TANDEM_HM_NAME="$S_HM" TANDEM_TARGET_USER="$S_USER" \
  TANDEM_TARGET_HOME="$S_HOME" HOME="$S_HOME" bash "$ops/check.sh" 2>&1)"
check "staging-check as prod-user -> FAIL" 1 "identity mismatch" $? "$out"

# 6. home mismatch -> FAIL (right user, wrong resolved home)
out="$(PATH="$shim:$PATH" env FAKE_UID=1000 FAKE_USER="$P_USER" FAKE_HOME="/wrong/home" \
  TANDEM_FLAKE="$root" TANDEM_HM_NAME="$P_HM" TANDEM_TARGET_USER="$P_USER" \
  TANDEM_TARGET_HOME="$P_HOME" HOME="$P_HOME" bash "$ops/deploy.sh" 2>&1)"
check "home-mismatch -> deploy FAIL" 1 "home mismatch" $? "$out"

# 7. correct identity -> proceeds (verify-only gate, no build/activation)
for s in deploy check rollback; do
  out="$(PATH="$shim:$PATH" env FAKE_UID=1000 FAKE_USER="$P_USER" FAKE_HOME="$P_HOME" \
    TANDEM_VERIFY_IDENTITY_ONLY=1 \
    TANDEM_FLAKE="$root" TANDEM_HM_NAME="$P_HM" TANDEM_TARGET_USER="$P_USER" \
    TANDEM_TARGET_HOME="$P_HOME" HOME="$P_HOME" bash "$ops/$s.sh" 2>&1)"
  check "correct-identity -> ${s} proceeds" 0 "identity OK" $? "$out"
done
# staging correct identity too
out="$(PATH="$shim:$PATH" env FAKE_UID=1000 FAKE_USER="$S_USER" FAKE_HOME="$S_HOME" \
  TANDEM_VERIFY_IDENTITY_ONLY=1 \
  TANDEM_FLAKE="$root" TANDEM_HM_NAME="$S_HM" TANDEM_TARGET_USER="$S_USER" \
  TANDEM_TARGET_HOME="$S_HOME" HOME="$S_HOME" bash "$ops/check.sh" 2>&1)"
check "correct-identity -> check-staging proceeds" 0 "identity OK" $? "$out"

# 8. wrapper binding probe: production vs staging wrappers bake DIFFERENT
#    identities and DIFFERENT HM output names.
echo "== wrapper binding probe =="
if command -v nix >/dev/null 2>&1; then
  d="$( (cd "$root" && nix build --no-link --print-out-paths .#deploy 2>/dev/null) )/bin/deploy"
  cs="$( (cd "$root" && nix build --no-link --print-out-paths .#check-staging 2>/dev/null) )/bin/check-staging"
  ok=1
  grep -q 'TANDEM_TARGET_USER="tandem"' "$d" || ok=0
  grep -q 'TANDEM_HM_NAME="tandem@tandem-vps"' "$d" || ok=0
  grep -q 'TANDEM_TARGET_USER="tandem-staging"' "$cs" || ok=0
  grep -q 'TANDEM_HM_NAME="tandem-staging@tandem-vps"' "$cs" || ok=0
  if [ "$ok" = 1 ]; then
    echo "  ok   deploy binds (tandem, tandem@tandem-vps); check-staging binds (tandem-staging, tandem-staging@tandem-vps)"
  else
    echo "  FAIL wrapper identity binding not as expected"
    fails=$((fails + 1))
  fi
else
  echo "  SKIP nix unavailable — cannot build wrappers for the binding probe"
fi

echo "----------------------------------------"
if [ "$fails" -gt 0 ]; then
  echo "identity tests: ${fails} FAIL"
  exit 1
fi
echo "identity tests: all passed"
exit 0

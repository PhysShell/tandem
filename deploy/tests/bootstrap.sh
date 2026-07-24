#!/usr/bin/env bash
#
# Arch bootstrap guard tests. Safe: never mutates the host. The non-Arch case
# additionally shims every mutation command so that a regression is caught
# loudly instead of touching the machine.
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
bs="$root/deploy/arch/bootstrap.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

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

echo "== bootstrap guards =="

# A. No mode -> refuse to do anything, exit 2.
out="$(bash "$bs" 2>&1)"
check "no-mode refuses" 2 "no mode given" $? "$out"

# B. --apply as non-root -> exit 1 (runs unprivileged; safe, no mutation).
if [ "$(id -u)" -ne 0 ]; then
  out="$(bash "$bs" --apply --user tandem 2>&1)"
  check "--apply non-root refuses" 1 "must run as root" $? "$out"
else
  echo "  SKIP --apply non-root (test is running as root)"
fi

# C. --apply on a NON-Arch host -> FAIL before ANY mutation.
#    Shim id->root to pass the root gate and reach the precondition check; fake a
#    non-Arch os-release; shim every mutation command so a bug is caught, not run.
shim="$tmp/bin"
mkdir -p "$shim"
cat >"$shim/id" <<'SH'
#!/bin/sh
case "${1:-}" in -u) echo 0;; -un) echo root;; -gn) echo root;; *) echo root;; esac
SH
for m in pacman systemctl loginctl install; do
  cat >"$shim/$m" <<'SH'
#!/bin/sh
echo "MUTATION-REACHED: $0 $*" >&2
exit 97
SH
done
chmod +x "$shim"/*
printf 'ID=ubuntu\nNAME="Ubuntu"\n' >"$tmp/os-release"

out="$(PATH="$shim:$PATH" TANDEM_OS_RELEASE="$tmp/os-release" bash "$bs" --apply --user tandem 2>&1)"
rc=$?
if printf '%s' "$out" | grep -q "MUTATION-REACHED"; then
  echo "  FAIL non-Arch --apply reached a mutation command"
  printf '%s\n' "$out" | sed 's/^/      | /'
  fails=$((fails + 1))
else
  check "--apply non-Arch fails before mutation" 1 "not Arch" "$rc" "$out"
fi

# D. --check is read-only: it runs and mutates no tracked files.
before="$(cd "$root" && git status --porcelain)"
out="$(bash "$bs" --check --user tandem 2>&1)"
rc=$?
after="$(cd "$root" && git status --porcelain)"
if [ "$before" = "$after" ] && printf '%s' "$out" | grep -q '\[base system\]'; then
  echo "  ok   --check read-only (rc=${rc}, no tracked-file mutation)"
else
  echo "  FAIL --check read-only (rc=${rc})"
  fails=$((fails + 1))
fi

echo "----------------------------------------"
if [ "$fails" -gt 0 ]; then
  echo "bootstrap tests: ${fails} FAIL"
  exit 1
fi
echo "bootstrap tests: all passed"
exit 0

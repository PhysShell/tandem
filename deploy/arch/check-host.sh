#!/usr/bin/env bash
#
# tandem host check — read-only inspection of the Arch host foundation.
#
# Safe to run as a normal user and in CI: it NEVER mutates the host. Reports
# PASS / WARN / FAIL and exits non-zero only if a hard FAIL is present. On a
# non-Arch CI runner it is expected to FAIL several checks; that is fine — the
# purpose there is to prove the script runs read-only.
set -uo pipefail # NOT -e: run every check even if one command fails.

user="tandem"
while [ $# -gt 0 ]; do
  case "$1" in
  --user)
    user="${2:?--user needs a value}"
    shift 2
    ;;
  --user=*)
    user="${1#*=}"
    shift
    ;;
  -h | --help)
    echo "usage: check-host.sh [--user NAME]"
    exit 0
    ;;
  *)
    echo "check-host: unknown argument: $1" >&2
    exit 2
    ;;
  esac
done

fails=0
warns=0
pass() { printf '  PASS  %s\n' "$*"; }
warn() {
  printf '  WARN  %s\n' "$*"
  warns=$((warns + 1))
}
fail() {
  printf '  FAIL  %s\n' "$*"
  fails=$((fails + 1))
}
have() { command -v "$1" >/dev/null 2>&1; }
req_bin() { # binary label
  if have "$1"; then
    pass "$2 present ($(command -v "$1"))"
  else
    fail "$2 missing"
  fi
}

echo "tandem host check (read-only) — target user: ${user}"
echo

osr="${TANDEM_OS_RELEASE:-/etc/os-release}"
echo "[base system]"
if [ -r "$osr" ] && grep -qi '^ID=arch' "$osr"; then
  pass "Arch Linux"
else
  fail "not Arch Linux (this foundation targets Arch; refusing to treat as OK)"
fi
if have systemctl && [ -d /run/systemd/system ]; then
  pass "systemd is the init system"
else
  fail "systemd not detected"
fi
req_bin nix "nix"

echo
echo "[required packages]"
req_bin sshd "openssh (sshd)"
req_bin tailscale "tailscale"
req_bin mosh-server "mosh (mosh-server)"

echo
echo "[services]"
check_unit() { # unit
  local u="$1" en ac
  if ! have systemctl; then
    warn "${u}: cannot query (no systemctl)"
    return
  fi
  en="$(systemctl is-enabled "$u" 2>/dev/null || true)"
  ac="$(systemctl is-active "$u" 2>/dev/null || true)"
  if [ "$en" = "enabled" ] && [ "$ac" = "active" ]; then
    pass "${u} enabled + active"
  elif [ -z "$en" ] && [ -z "$ac" ]; then
    warn "${u} not known yet (install pending)"
  else
    warn "${u} enabled=${en:-?} active=${ac:-?} (bootstrap --apply fixes this)"
  fi
}
check_unit sshd
check_unit tailscaled

echo
echo "[target user: ${user}]"
home=""
if getent passwd "$user" >/dev/null 2>&1; then
  home="$(getent passwd "$user" | cut -d: -f6)"
  pass "user exists (home ${home})"
else
  fail "user '${user}' does not exist"
fi
if have loginctl; then
  linger="$(loginctl show-user "$user" -p Linger --value 2>/dev/null || true)"
  case "$linger" in
  yes) pass "lingering enabled for ${user}" ;;
  no) warn "lingering disabled for ${user} (bootstrap --apply enables it)" ;;
  *) warn "lingering state unknown for ${user}" ;;
  esac
else
  warn "loginctl unavailable; cannot check lingering"
fi

echo
echo "[required directories]"
if [ -n "$home" ]; then
  for d in "$home/.config" "$home/.local/state" "$home/.local/state/nix"; do
    if [ -d "$d" ]; then
      pass "exists: $d"
    else
      warn "missing (bootstrap --apply creates): $d"
    fi
  done
else
  warn "skipping directory checks (no resolvable home)"
fi

echo
echo "[public exposure — MANUAL review, never mutated]"
if have ss; then
  pub="$(ss -H -tln 2>/dev/null | awk '{print $4}' | while read -r la; do
    h="${la%:*}"
    h="${h#[}"
    h="${h%]}"
    case "$h" in 127.* | ::1 | "") continue ;; esac
    printf '%s\n' "$la"
  done)"
  if [ -z "$pub" ]; then
    pass "no non-loopback TCP listeners"
  else
    warn "non-loopback TCP listeners (bootstrap will NOT change your firewall):"
    printf '%s\n' "$pub" | sed 's/^/           /'
  fi
else
  warn "ss unavailable; cannot inspect listeners"
fi

echo
echo "----------------------------------------"
printf 'host check: %d FAIL, %d WARN\n' "$fails" "$warns"
if [ "$fails" -gt 0 ]; then
  exit 1
fi
exit 0

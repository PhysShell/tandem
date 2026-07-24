#!/usr/bin/env bash
#
# tandem check — read-only workstation diagnostics. Never mutates anything.
# Reports PASS / WARN / FAIL. Exit 0 unless at least one FAIL is present
# (WARN never fails). Missing *future* components (o7d, Cockpit) are NOT checked
# and must never be reported as a T1 failure.
#
# Enforces the operator identity contract first: it will only report for the
# user/output it is bound to (production via `nix run .#check`, staging via
# `nix run .#check-staging`). Running the staging check as the production user
# (or vice-versa), or as root, fails closed before any diagnostics.
set -uo pipefail # NOT -e: every check must run even if one command fails.

TANDEM_CMD="check"

script_dir="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=deploy/ops/identity.sh
. "$script_dir/identity.sh"

flake="${TANDEM_FLAKE:-}"
hm_name="${TANDEM_HM_NAME:-tandem@tandem-vps}"

# Identity gate before any reporting (refuses root / wrong user / wrong output).
require_identity

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

echo "tandem check — read-only workstation diagnostics"
echo "target home configuration: ${hm_name} (user $(id -un))"
echo

echo "[platform]"
if [ "$(uname -m)" = "x86_64" ] && [ "$(uname -s)" = "Linux" ]; then
  pass "architecture $(uname -sm)"
else
  fail "unsupported architecture $(uname -sm) (need x86_64 Linux)"
fi
if have nix; then
  pass "nix present ($(nix --version 2>/dev/null | head -n1))"
else
  fail "nix not found"
fi

echo
echo "[home-manager configuration]"
if [ -n "$flake" ] && have nix; then
  # Read-only: evaluate the derivation path, do not build.
  if drv="$(nix eval --raw \
    "${flake}#homeConfigurations.\"${hm_name}\".activationPackage.drvPath" 2>/dev/null)"; then
    pass "configuration evaluates (${drv})"
  else
    fail "configuration failed to evaluate"
  fi
else
  warn "skipped HM evaluation (TANDEM_FLAKE unset or nix missing)"
fi

echo
echo "[workstation tools]"
for pair in "o7:007 binary (o7)" "git:git" "tmux:tmux" "ssh:SSH client"; do
  cmd="${pair%%:*}"
  label="${pair#*:}"
  if have "$cmd"; then
    pass "${label} present ($(command -v "$cmd"))"
  else
    fail "${label} missing"
  fi
done
if have mosh || have mosh-client; then
  pass "mosh present"
else
  fail "mosh missing"
fi
if have o7; then
  if [ -x "$(command -v o7)" ]; then
    pass "o7 executable"
  else
    fail "o7 present but not executable"
  fi
fi

echo
echo "[tailscale]"
if have tailscale; then
  pass "tailscale CLI present"
else
  fail "tailscale CLI missing (host bootstrap installs it)"
fi
if have systemctl; then
  if systemctl is-active --quiet tailscaled 2>/dev/null; then
    pass "tailscaled active"
  elif systemctl list-unit-files 2>/dev/null | grep -q '^tailscaled'; then
    warn "tailscaled installed but not active"
  else
    warn "tailscaled unit not found (host bootstrap may be pending)"
  fi
else
  warn "systemd not accessible; cannot check tailscaled state"
fi

echo
echo "[user session persistence]"
if have loginctl; then
  linger="$(loginctl show-user "$(id -un)" -p Linger --value 2>/dev/null || true)"
  case "$linger" in
  yes) pass "user lingering enabled" ;;
  no) warn "user lingering disabled (enable so tmux/o7d survive logout)" ;;
  *) warn "could not determine lingering state" ;;
  esac
else
  warn "loginctl unavailable; cannot check lingering"
fi

echo
echo "[writable user directories]"
for d in "${XDG_CONFIG_HOME:-$HOME/.config}" "${XDG_STATE_HOME:-$HOME/.local/state}"; do
  if [ -d "$d" ] && [ -w "$d" ]; then
    pass "writable: $d"
  elif [ ! -e "$d" ]; then
    parent="$(dirname "$d")"
    if [ -w "$parent" ]; then
      warn "missing (created on first activation): $d"
    else
      fail "cannot create $d (parent not writable)"
    fi
  else
    fail "not writable: $d"
  fi
done

echo
echo "[public listeners]"
if have ss; then
  public=()
  while IFS= read -r la; do
    [ -n "$la" ] || continue
    port="${la##*:}"
    host="${la%:*}"
    host="${host#[}"
    host="${host%]}"
    case "$host" in
    127.* | ::1 | "") continue ;; # loopback / empty → not public
    esac
    [ "$port" = "22" ] && continue # sshd fallback is an expected public port
    public+=("$la")
  done < <(ss -H -tln 2>/dev/null | awk '{print $4}')
  if [ "${#public[@]}" -eq 0 ]; then
    pass "no unexpected public TCP listeners (ssh/22 allowed)"
  else
    warn "public TCP listeners — review as a MANUAL action: ${public[*]}"
  fi
else
  warn "ss unavailable; cannot check public listeners"
fi

echo
echo "----------------------------------------"
printf 'check summary: %d FAIL, %d WARN\n' "$fails" "$warns"
if [ "$fails" -gt 0 ]; then
  exit 1
fi
exit 0

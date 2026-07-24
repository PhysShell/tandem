#!/usr/bin/env bash
#
# Nix runtime + postcondition-propagation tests. Safe: every mutating command
# and host tool is shimmed, so nothing touches real users, groups, services,
# /etc/nix or the Nix store. Each case asserts BOTH the exit code and output.
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
bs="$root/deploy/arch/bootstrap.sh"
ch="$root/deploy/arch/check-host.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fails=0
# assert LABEL EXPECTED_RC ACTUAL_RC WANT NOTWANT OUTPUT
#   EXPECTED_RC may be a number or "nz" (nonzero). WANT/NOTWANT may be "".
assert() {
  local label="$1" exp="$2" rc="$3" want="$4" notwant="$5" out="$6" ok=1
  if [ "$exp" = "nz" ]; then
    [ "$rc" -ne 0 ] || ok=0
  else
    [ "$rc" = "$exp" ] || ok=0
  fi
  [ -z "$want" ] || printf '%s' "$out" | grep -qi -- "$want" || ok=0
  [ -z "$notwant" ] || ! printf '%s' "$out" | grep -qi -- "$notwant" || ok=0
  if [ "$ok" = 1 ]; then
    echo "  ok   ${label} (rc=${rc})"
  else
    echo "  FAIL ${label} (rc=${rc}, want-rc=${exp}, want='${want}', notwant='${notwant}')"
    printf '%s\n' "$out" | sed 's/^/      | /'
    fails=$((fails + 1))
  fi
}

# ---- fixtures -------------------------------------------------------------
unitdir="$tmp/units"
mkdir -p "$unitdir"
: >"$unitdir/nix-daemon.service" # packaged unit "present"
printf 'ID=arch\nNAME="Arch Linux"\n' >"$tmp/arch"
printf 'experimental-features = nix-command\n' >"$tmp/nc-only"
printf 'experimental-features = flakes\n' >"$tmp/fl-only"
printf 'experimental-features = nix-command flakes\n' >"$tmp/both"
missing="$tmp/nonexistent"

# Healthy host shim set. Runtime knobs (env): FAKE_NIXD=up|down (nix-daemon
# enabled/active state), FAKE_NIX_STORE_RC=0|1 (daemon connectivity rc),
# CALLLOG=<file> (records mutation commands).
shims="$tmp/bin"
mkdir -p "$shims"
cat >"$shims/id" <<'SH'
#!/bin/sh
case "${1:-}" in -u) echo 0;; -un) echo root;; -gn) echo root;; *) echo root;; esac
SH
cat >"$shims/systemctl" <<'SH'
#!/bin/sh
case "${1:-}" in
  is-enabled)
    case "$2" in
      nix-daemon.service) [ "${FAKE_NIXD:-up}" = up ] && { echo enabled; exit 0; } || { echo disabled; exit 1; } ;;
      nix-daemon.socket)  echo disabled; exit 1 ;;
      *) echo enabled; exit 0 ;;
    esac ;;
  is-active)
    case "$2" in
      nix-daemon.service) [ "${FAKE_NIXD:-up}" = up ] && { echo active; exit 0; } || { echo inactive; exit 1; } ;;
      nix-daemon.socket)  echo inactive; exit 1 ;;
      *) echo active; exit 0 ;;
    esac ;;
  enable|start|disable) echo "systemctl $*" >>"${CALLLOG:-/dev/null}"; exit 0 ;;
  *) exit 0 ;;
esac
SH
cat >"$shims/loginctl" <<'SH'
#!/bin/sh
case "${1:-}" in
  enable-linger|disable-linger) echo "loginctl $*" >>"${CALLLOG:-/dev/null}"; exit 0 ;;
  show-user) echo yes; exit 0 ;;
  *) exit 0 ;;
esac
SH
cat >"$shims/nix" <<'SH'
#!/bin/sh
case "$*" in
  *"store info"*) exit "${FAKE_NIX_STORE_RC:-0}" ;;
  *--version*) echo "nix (Nix) 2.34.8"; exit 0 ;;
  *) exit 0 ;;
esac
SH
for m in pacman install; do
  cat >"$shims/$m" <<SH
#!/bin/sh
echo "$m \$*" >>"\${CALLLOG:-/dev/null}"; exit 0
SH
done
for b in sshd tailscale mosh-server ss runuser; do
  printf '#!/bin/sh\nexit 0\n' >"$shims/$b"
done
chmod +x "$shims"/*

# run check-host with healthy shims; extra env passed as VAR=VAL args before --
runch() { # VAR=VAL... -- (captures into OUT/RC)
  local envs=()
  while [ "${1:-}" != "--" ] && [ "$#" -gt 0 ]; do
    envs+=("$1")
    shift
  done
  OUT="$(PATH="$shims:$PATH" env TANDEM_OS_RELEASE="$tmp/arch" \
    TANDEM_SYSTEMD_UNIT_DIR="$unitdir" "${envs[@]}" \
    bash "$ch" --user root 2>&1)"
  RC=$?
}
runapply() { # VAR=VAL... (captures into OUT/RC)
  OUT="$(PATH="$shims:$PATH" env TANDEM_OS_RELEASE="$tmp/arch" \
    TANDEM_SYSTEMD_UNIT_DIR="$unitdir" "$@" \
    bash "$bs" --apply --user root 2>&1)"
  RC=$?
}

echo "== check-host: nix runtime failures propagate =="

# daemon access failure -> nonzero exit
runch FAKE_NIXD=up FAKE_NIX_STORE_RC=1 TANDEM_NIX_CONF="$tmp/both" --
assert "daemon access failure -> nonzero" nz "$RC" "cannot reach the nix daemon" "" "$OUT"

# daemon down -> nonzero exit, and binary-present is still reported (present != usable)
runch FAKE_NIXD=down FAKE_NIX_STORE_RC=1 TANDEM_NIX_CONF="$tmp/both" --
assert "daemon down -> nonzero" nz "$RC" "nix daemon NOT enabled" "" "$OUT"
assert "daemon down still shows binary present" nz "$RC" "nix executable present" "" "$OUT"

# missing packaged unit -> nonzero exit
OUT="$(PATH="$shims:$PATH" env TANDEM_OS_RELEASE="$tmp/arch" \
  TANDEM_SYSTEMD_UNIT_DIR="$tmp/empty" FAKE_NIXD=up FAKE_NIX_STORE_RC=0 \
  bash "$ch" --user root 2>&1)"
RC=$?
assert "missing daemon unit -> nonzero" nz "$RC" "packaged nix daemon unit not found" "" "$OUT"

echo "== check-host: flakes detection requires BOTH features =="
runch FAKE_NIXD=up FAKE_NIX_STORE_RC=0 TANDEM_USER_NIX_CONF="$missing" TANDEM_NIX_CONF="$tmp/nc-only" --
assert "system nix-command only -> not PASS" 0 "$RC" "not yet persisted" "enabled system-wide" "$OUT"
runch FAKE_NIXD=up FAKE_NIX_STORE_RC=0 TANDEM_USER_NIX_CONF="$missing" TANDEM_NIX_CONF="$tmp/fl-only" --
assert "system flakes only -> not PASS" 0 "$RC" "not yet persisted" "enabled system-wide" "$OUT"
runch FAKE_NIXD=up FAKE_NIX_STORE_RC=0 TANDEM_USER_NIX_CONF="$missing" TANDEM_NIX_CONF="$tmp/both" --
assert "system both -> PASS" 0 "$RC" "enabled system-wide" "not yet persisted" "$OUT"
runch FAKE_NIXD=up FAKE_NIX_STORE_RC=0 TANDEM_USER_NIX_CONF="$tmp/both" TANDEM_NIX_CONF="$missing" --
assert "user both -> PASS" 0 "$RC" "persisted for 'root'" "not yet persisted" "$OUT"

echo "== bootstrap --apply: postcondition propagation (mutations shimmed) =="

# WARN-only postconditions (flakes not yet persisted) -> success + banner.
log1="$tmp/log1"
: >"$log1"
runapply FAKE_NIXD=up FAKE_NIX_STORE_RC=0 TANDEM_NIX_CONF="$missing" CALLLOG="$log1"
assert "WARN-only postconditions -> exit 0 + banner" 0 "$RC" "bootstrap --apply: done." "" "$OUT"
if grep -q 'systemctl enable --now nix-daemon.service' "$log1"; then
  echo "  ok   --apply enables nix-daemon.service"
else
  echo "  FAIL --apply did not enable nix-daemon.service"
  fails=$((fails + 1))
fi

# Idempotence: a second application issues the identical mutation sequence.
log2="$tmp/log2"
: >"$log2"
runapply FAKE_NIXD=up FAKE_NIX_STORE_RC=0 TANDEM_NIX_CONF="$missing" CALLLOG="$log2"
if diff -q "$log1" "$log2" >/dev/null 2>&1; then
  echo "  ok   second --apply is idempotent (identical mutation sequence)"
else
  echo "  FAIL second --apply diverged"
  diff "$log1" "$log2" | sed 's/^/      | /'
  fails=$((fails + 1))
fi

# Postcondition FAILURE (target user cannot reach the daemon) -> nonzero, and the
# success banner must NOT be printed.
runapply FAKE_NIXD=up FAKE_NIX_STORE_RC=1 TANDEM_NIX_CONF="$missing" CALLLOG="$tmp/log3"
assert "postcond daemon-access fail -> nonzero, no banner" nz "$RC" \
  "cannot reach the nix daemon" "bootstrap --apply: done." "$OUT"

echo "== bootstrap: no group required on current Arch =="
if grep -Eq 'groupadd|gpasswd|usermod[^\n]*-a?G' "$bs"; then
  echo "  FAIL bootstrap unexpectedly manipulates groups"
  fails=$((fails + 1))
else
  echo "  ok   no group manipulation (no nix-users group required)"
fi

echo "== both HM outputs persist flake features =="
if command -v nix >/dev/null 2>&1; then
  for cfg in "tandem@tandem-vps" "tandem-staging@tandem-vps"; do
    out="$( (cd "$root" && nix build --no-link --print-out-paths \
      ".#homeConfigurations.\"$cfg\".activationPackage" 2>/dev/null) )"
    f="$(find -L "$out" -path '*nix/nix.conf' 2>/dev/null | head -1)"
    if [ -n "$f" ] && grep -q 'experimental-features = nix-command flakes' "$f"; then
      echo "  ok   ${cfg} persists experimental-features"
    else
      echo "  FAIL ${cfg} does not persist experimental-features (${f:-not found})"
      fails=$((fails + 1))
    fi
  done
else
  echo "  SKIP nix unavailable — cannot verify feature persistence"
fi

echo "----------------------------------------"
if [ "$fails" -gt 0 ]; then
  echo "nix-runtime tests: ${fails} FAIL"
  exit 1
fi
echo "nix-runtime tests: all passed"
exit 0

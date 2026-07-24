#!/usr/bin/env bash
#
# Nix runtime (daemon + user access + flakes) tests. Safe: all mutating commands
# are shimmed, so nothing touches the real users, groups, services, /etc/nix or
# the Nix store. Uses TANDEM_SYSTEMD_UNIT_DIR / TANDEM_NIX_CONF override hooks and
# a fake systemd unit dir so the checks are deterministic on any host.
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
bs="$root/deploy/arch/bootstrap.sh"
ch="$root/deploy/arch/check-host.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
me="$(id -un)"

fails=0
grep_ok() { # label out needle...
  local label="$1" out="$2"
  shift 2
  local miss=0 n
  for n in "$@"; do printf '%s' "$out" | grep -qi "$n" || miss=1; done
  if [ "$miss" = 0 ]; then
    echo "  ok   ${label}"
  else
    echo "  FAIL ${label}"
    printf '%s\n' "$out" | sed 's/^/      | /'
    fails=$((fails + 1))
  fi
}

# A fake systemd unit dir that DOES contain the packaged unit (so "unit present"
# passes and we can isolate other failures).
unitdir="$tmp/units"
mkdir -p "$unitdir"
: >"$unitdir/nix-daemon.service"

echo "== nix runtime: host check =="

# Test 2: packaged daemon unit MISSING after install -> FAIL.
out="$(TANDEM_SYSTEMD_UNIT_DIR="$tmp/empty" bash "$ch" --user "$me" 2>&1)"
grep_ok "missing daemon unit -> FAIL" "$out" "packaged nix daemon unit not found"

# Test 7: binary present but daemon DOWN -> distinguishes present from usable.
scdown="$tmp/scdown"
mkdir -p "$scdown"
cat >"$scdown/systemctl" <<'SH'
#!/bin/sh
case "${1:-}" in
  is-enabled) echo disabled; exit 1 ;;
  is-active)  echo inactive; exit 1 ;;
  *) exit 0 ;;
esac
SH
chmod +x "$scdown/systemctl"
out="$(PATH="$scdown:$PATH" TANDEM_SYSTEMD_UNIT_DIR="$unitdir" bash "$ch" --user "$me" 2>&1)"
grep_ok "binary present but daemon down -> PASS binary + FAIL daemon" "$out" \
  "PASS  nix executable present" "nix daemon NOT enabled"

# Test 5: target-user daemon access failure is detected.
naccess="$tmp/naccess"
mkdir -p "$naccess"
cat >"$naccess/nix" <<'SH'
#!/bin/sh
case "$*" in
  *"store info"*) exit 1 ;;   # simulate no daemon connectivity
  *) exit 0 ;;
esac
SH
cat >"$naccess/systemctl" <<'SH'
#!/bin/sh
case "${1:-}" in is-enabled) echo enabled;; is-active) echo active;; esac
exit 0
SH
chmod +x "$naccess"/*
out="$(PATH="$naccess:$PATH" TANDEM_SYSTEMD_UNIT_DIR="$unitdir" bash "$ch" --user "$me" 2>&1)"
grep_ok "target-user access failure -> FAIL" "$out" "cannot reach the nix daemon"

echo "== nix runtime: bootstrap --apply (simulated Arch, all mutations shimmed) =="

# Simulated Arch host: fake os-release, shimmed id(root) + mutation commands that
# LOG to a call log instead of running. Target user 'root' exists everywhere.
mkshims() { # dest calllog
  local d="$1" log="$2"
  mkdir -p "$d"
  cat >"$d/id" <<'SH'
#!/bin/sh
case "${1:-}" in -u) echo 0;; -un) echo root;; -gn) echo root;; *) echo root;; esac
SH
  cat >"$d/systemctl" <<SH
#!/bin/sh
case "\${1:-}" in
  is-enabled)
    case "\$2" in nix-daemon.socket) echo disabled; exit 1;; *) echo enabled; exit 0;; esac ;;
  is-active) echo active; exit 0 ;;
  enable|start|disable) echo "systemctl \$*" >>"$log"; exit 0 ;;
  *) exit 0 ;;
esac
SH
  cat >"$d/loginctl" <<SH
#!/bin/sh
case "\${1:-}" in
  enable-linger|disable-linger) echo "loginctl \$*" >>"$log"; exit 0 ;;
  show-user) echo yes; exit 0 ;;
  *) exit 0 ;;
esac
SH
  cat >"$d/pacman" <<SH
#!/bin/sh
echo "pacman \$*" >>"$log"; exit 0
SH
  cat >"$d/install" <<SH
#!/bin/sh
echo "install \$*" >>"$log"; exit 0
SH
  chmod +x "$d"/*
}

printf 'ID=arch\nNAME="Arch Linux"\n' >"$tmp/arch-os-release"

run_apply() { # calllog -> stdout of --apply
  local log="$1" shims="$tmp/shims-$$-$RANDOM"
  mkshims "$shims" "$log"
  PATH="$shims:$PATH" TANDEM_OS_RELEASE="$tmp/arch-os-release" \
    TANDEM_SYSTEMD_UNIT_DIR="$unitdir" bash "$bs" --apply --user root 2>&1
}

log1="$tmp/log1"
: >"$log1"
out="$(run_apply "$log1")"
rc=$?
# Test 3: daemon enable uses the selected packaged unit.
if [ "$rc" -eq 0 ] && grep -q 'systemctl enable --now nix-daemon.service' "$log1"; then
  echo "  ok   --apply enables nix-daemon.service"
else
  echo "  FAIL --apply did not enable nix-daemon.service (rc=$rc)"
  printf '%s\n' "$out" | sed 's/^/      | /'
  fails=$((fails + 1))
fi

# Test 4: a second application is idempotent (same command sequence).
log2="$tmp/log2"
: >"$log2"
run_apply "$log2" >/dev/null 2>&1 || true
if diff -q "$log1" "$log2" >/dev/null 2>&1; then
  echo "  ok   second --apply is idempotent (identical mutation sequence)"
else
  echo "  FAIL second --apply diverged"
  diff "$log1" "$log2" | sed 's/^/      | /'
  fails=$((fails + 1))
fi

# Test 6 (group): NOT APPLICABLE — the current Arch 'nix' package creates no
# nix-users group and its daemon socket is 0666, so no group is required. Prove
# bootstrap adds no group at all (no groupadd / gpasswd / usermod -aG).
if grep -Eq 'groupadd|gpasswd|usermod[^\n]*-a?G' "$bs"; then
  echo "  FAIL bootstrap unexpectedly manipulates groups"
  fails=$((fails + 1))
else
  echo "  ok   no group manipulation (no nix-users group required on current Arch)"
fi

echo "== nix runtime: both HM outputs persist flake features =="
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

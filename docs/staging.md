# Staging activation

Validate the Home Manager configuration under a **throwaway second user**
(`tandem-staging`) before touching the real `tandem` home. Staging builds the **same
module set** as production — `home/tandem-vps.nix` and everything under `modules/` — just
with a different username and home directory. It is a second Home Manager output, not a
copy of the configuration:

```
homeConfigurations."tandem@tandem-vps"          # production
homeConfigurations."tandem-staging@tandem-vps"  # staging: identical modules, different user
```

`nix run .#deploy` deliberately targets **only** production and never creates or deletes
the staging user. The steps below are manual on purpose.

## Workflow

Commands assume you have the repo checked out on the VPS (or run against
`github:PhysShell/tandem`). Replace `tandem-staging` if you parameterised a different name.

### 1. Create the staging user (root)

```sh
sudo useradd --create-home --user-group tandem-staging
```

`--user-group` gives a matching primary group, which the ownership checks expect. tandem
does not do this for you — creating/removing users stays a deliberate root action.

### 2. Enable lingering (root)

```sh
sudo loginctl enable-linger tandem-staging
```

### 3. Build the activation package (any user — no activation yet)

```sh
nix build .#homeConfigurations."tandem-staging@tandem-vps".activationPackage
```

This is exactly what CI builds, so a green CI means this step will build.

### 4. Activate as the staging user

```sh
sudo -iu tandem-staging bash -lc '
  gen="$(nix build --no-link --print-out-paths \
    ".#homeConfigurations.\"tandem-staging@tandem-vps\".activationPackage")"
  "$gen/activate"
'
```

(Run from the directory holding the flake, or replace `.` with
`github:PhysShell/tandem`.) The first activation registers generation 1.

### 5. Run the read-only checks as the staging user

```sh
sudo -iu tandem-staging bash -lc 'cd /path/to/tandem && nix run .#check'
```

Expect `o7`, `git`, `tmux`, `mosh`, `ssh` present and the HM configuration evaluating.
`tailscale`/`tailscaled` findings depend on host bootstrap, not on the user config.

### 6. Activate again to test idempotence

```sh
sudo -iu tandem-staging bash -lc '
  gen="$(nix build --no-link --print-out-paths \
    ".#homeConfigurations.\"tandem-staging@tandem-vps\".activationPackage")"
  "$gen/activate"
'
```

A second activation of the same generation must be a no-op ("No change so reusing latest
profile generation") — nothing destructive, no conflicts.

### 7. Roll back

```sh
sudo -iu tandem-staging bash -lc 'cd /path/to/tandem && nix run .#rollback'
```

With only one generation this **fails closed** with a clear message (there is nothing to
roll back to) — which is the correct, safe behaviour. To exercise a real rollback, make a
trivial change to a module, activate again (generation 2), then roll back to 1.

### 8. Remove the staging user (optional, root)

```sh
sudo loginctl disable-linger tandem-staging
sudo userdel --remove tandem-staging
```

## Why staging

The production home is where you actually work from the phone. Staging lets you prove an
activation builds, activates, is idempotent, and rolls back — against a user you can safely
delete — before you run `nix run .#deploy` against the real `tandem` account.

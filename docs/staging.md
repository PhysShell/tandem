# Staging activation

Validate the Home Manager configuration under a **throwaway second user**
(`tandem-staging`) before touching the real `tandem` home. Staging builds the
**same module set** as production — `home/tandem-vps.nix` and everything under
`modules/` — just with a different username and home directory. It is a second
Home Manager output, not a copy of the configuration:

```
homeConfigurations."tandem@tandem-vps"          # production
homeConfigurations."tandem-staging@tandem-vps"  # staging: identical modules, different user
```

Each identity has its **own** operator commands whose Home Manager output and OS
user are bound together and cannot be mixed (see `deploy/ops/identity.sh`):

```
production:  nix run .#deploy         .#check         .#rollback          (user tandem)
staging:     nix run .#deploy-staging .#check-staging .#rollback-staging  (user tandem-staging)
```

`nix run .#deploy` targets **only** production and never creates or deletes the
staging user. The steps below are manual on purpose.

## Important: `sudo -i` changes the working directory

`sudo -iu tandem-staging` starts a **login** shell, so the working directory
becomes `/home/tandem-staging` — **not** your checkout. A bare `.#…` flake
reference would then resolve against the staging user's home, not the tandem
repo. Every example below therefore pins an absolute checkout path and `cd`s to
it *inside* the staging shell. Do not rely on `.` surviving `sudo -i`.

```sh
# Absolute path to your tandem checkout on the VPS (edit to match).
TANDEM_CHECKOUT=/home/tandem/tandem
```

## Workflow

### 1. Create the staging user (root)

```sh
sudo useradd --create-home --user-group tandem-staging
```

`--user-group` gives a matching primary group and `--create-home` creates
`/home/tandem-staging`, which the identity/ownership checks expect. tandem does
not do this for you — creating/removing users stays a deliberate root action.

### 2. Enable lingering (root)

```sh
sudo loginctl enable-linger tandem-staging
```

### 3. Build the activation package (any user — no activation yet)

Build with an explicit absolute path so it does not depend on the caller's cwd:

```sh
nix build --no-link --print-out-paths \
  "path:${TANDEM_CHECKOUT}#homeConfigurations.\"tandem-staging@tandem-vps\".activationPackage"
```

This is exactly what CI builds, so a green CI means this step will build.

### 4. Activate as the staging user

Use the staging wrapper, `cd`-ing to the checkout inside the login shell:

```sh
sudo -iu tandem-staging \
  env TANDEM_CHECKOUT="$TANDEM_CHECKOUT" \
  bash -lc '
    cd "$TANDEM_CHECKOUT"
    nix run .#deploy-staging
  '
```

`deploy-staging` enforces the identity contract (it must be run as
`tandem-staging` with home `/home/tandem-staging`), builds from the locked flake,
and activates — registering generation 1.

> Equivalent raw form (also correct), if you prefer to see the package first:
>
> ```sh
> sudo -iu tandem-staging \
>   env TANDEM_CHECKOUT="$TANDEM_CHECKOUT" \
>   bash -lc '
>     cd "$TANDEM_CHECKOUT"
>     gen="$(nix build --no-link --print-out-paths \
>       ".#homeConfigurations.\"tandem-staging@tandem-vps\".activationPackage")"
>     "$gen/activate"
>   '
> ```

### 5. Run the staging read-only checks

```sh
sudo -iu tandem-staging \
  env TANDEM_CHECKOUT="$TANDEM_CHECKOUT" \
  bash -lc 'cd "$TANDEM_CHECKOUT" && nix run .#check-staging'
```

`check-staging` evaluates the **staging** output and refuses to run as anyone but
`tandem-staging`. Expect `o7`, `git`, `tmux`, `mosh`, `ssh` present.
`tailscale`/`tailscaled` findings depend on host bootstrap, not the user config.

### 6. Activate again to test idempotence

```sh
sudo -iu tandem-staging \
  env TANDEM_CHECKOUT="$TANDEM_CHECKOUT" \
  bash -lc 'cd "$TANDEM_CHECKOUT" && nix run .#deploy-staging'
```

A second activation of the same generation must be a no-op ("No change so reusing
latest profile generation") — nothing destructive, no conflicts.

### 7. Roll back

```sh
sudo -iu tandem-staging \
  env TANDEM_CHECKOUT="$TANDEM_CHECKOUT" \
  bash -lc 'cd "$TANDEM_CHECKOUT" && nix run .#rollback-staging'
```

With only one generation this **fails closed** with a clear message (there is
nothing to roll back to) — the correct, safe behaviour. To exercise a real
rollback, make a trivial change to a module, activate again (generation 2), then
roll back to 1.

### 8. Remove the staging user (optional, root)

```sh
sudo loginctl disable-linger tandem-staging
sudo userdel --remove tandem-staging
```

## Why staging

The production home is where you actually work from the phone. Staging lets you
prove an activation builds, activates, is idempotent, and rolls back — against a
user you can safely delete — before you run `nix run .#deploy` against the real
`tandem` account. The identity contract guarantees a staging command can never
touch the production user, and vice-versa.

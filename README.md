# tandem

**Deployment and operations for a phone-first [007](https://github.com/PhysShell/007)
workstation, running on an existing Arch Linux VPS.**

`tandem` is *not* the product. It owns one thing: reproducibly standing up, operating,
validating and rolling back **one specific workstation instance** that runs a pinned
build of 007, driven from a phone.

## The boundary

```
007     = the product and runtime
tandem  = deployment and operations for a phone-first 007 installation
```

The product lives in **[`PhysShell/007`](https://github.com/PhysShell/007)** — `o7`,
`o7-ledger`, `o7-worker`, the future `o7d`, the event protocol, the Cockpit UI, and the
Claude/Codex adapters. `tandem` deploys 007; it does **not** re-implement any of it.

Concretely, `tandem` owns only:

- Arch host bootstrap (root-owned foundation);
- a standalone Home Manager configuration for the workstation user;
- a **pinned** 007 build (exact revision via `flake.lock`);
- terminal / mobile tooling (tmux, mosh client, SSH);
- activation, validation and rollback commands;
- operational documentation.

**Non-duplication rule.** `tandem` must not contain a second Cockpit implementation, a
second `o7d`, or a second application roadmap. If you are looking for the product design or
its build order, that is [007](https://github.com/PhysShell/007). The roadmap here is a
*deployment* roadmap — see [`ROADMAP.md`](ROADMAP.md).

## Target architecture

```
Pixel
├── Cockpit PWA             future primary control surface
└── Termux + mosh + tmux    current operational and recovery channel
          │
       Tailscale
          │
Arch VPS
├── Nix
├── Home Manager
├── pinned 007
├── future o7d
├── future Cockpit publication
└── persistent state/backups
```

Today the phone reaches the VPS over **Tailscale → mosh → tmux**; the Cockpit PWA and
`o7d` are future stages that this repository deploys but does **not** implement.

## Layout

| Path | What it is |
|------|------------|
| `flake.nix` / `flake.lock` | Inputs (nixpkgs, Home Manager, pinned **007**) and outputs (home configs, operator apps). |
| `home/tandem-vps.nix` | The workstation home: composes the modules, pins `home.stateVersion`. |
| `modules/workstation.nix` | Minimal user toolset (git, gh, jq, ripgrep, fd, bat, mosh, ssh) + `o7-revision` helper. |
| `modules/terminal.nix` | Conservative tmux for phone use (mouse mode, scrollback, no plugins/theme). |
| `modules/o7.nix` | Exposes the pinned `o7` binary through the profile. |
| `deploy/ops/*.sh` | Operator commands behind `nix run .#deploy` / `#check` / `#rollback`. |
| `deploy/arch/bootstrap.sh` | Root-owned Arch foundation; explicit `--check` / `--apply`. |
| `deploy/arch/check-host.sh` | Read-only host inspection (also CI-safe). |
| `docs/` | Phone runbook, staging workflow, secrets boundary. |

## Operator commands

All user-scoped; none of them touch root-owned Arch configuration.

```sh
nix run .#check      # read-only PASS/WARN/FAIL diagnostics
nix run .#deploy     # activate tandem@tandem-vps from the locked flake
nix run .#rollback   # roll the user Home Manager generation back one step
```

Host foundation (root, explicit mode — never mutates by default):

```sh
sudo ./deploy/arch/bootstrap.sh --check    # read-only
sudo ./deploy/arch/bootstrap.sh --apply    # idempotent minimal setup
```

## The pinned 007 revision

The deployed product is fixed by `flake.lock`. To see exactly which revision is (or will
be) installed:

```sh
# what the profile ships:
o7-revision
# or straight from the lock, without deploying:
nix flake metadata --json | jq -r '.locks.nodes.o7.locked.rev'
```

Upgrading 007 is a deliberate `nix flake update o7` + review + redeploy — never automatic.

## Status

Working access exists (phone → mosh → tmux → VPS). This repository turns that into a
reproducible, rollback-able deployment. See [`ROADMAP.md`](ROADMAP.md) for staged progress
and [`docs/phone-workflow.md`](docs/phone-workflow.md) to connect.

# Secrets boundary

One rule, no exceptions:

> **No SSH private keys, Claude/Codex OAuth data, Tailscale auth keys, backup passwords or
> environment dumps may enter Git or the Nix store.**

Anything committed to Git is permanent history; anything placed in the Nix store is
world-readable on the box and copied around by builds. Secrets belong in neither.

## Do not put secrets in

- **Nix string literals** — a string in a `.nix` file ends up in the store, in the clear.
- **Generated derivations** — build inputs and outputs are readable under `/nix/store`.
- **Flake inputs** — no auth-carrying URLs; the 007 input is a public, keyless
  `github:` reference.
- **Committed `.env` files** — never commit one; see `.gitignore`.
- **Command-line arguments** — visible in `ps`/`/proc` to any local user. The bootstrap
  never takes an auth key as an argument, and never will.

## What stays external and user-managed

- **SSH keys** — live in `~/.ssh` on each device. The phone key is generated on the phone
  (`docs/phone-workflow.md`); its **public** half is added to `authorized_keys` by hand.
  tandem never reads, writes, generates or copies keys.
- **Claude / Codex authentication** — subscription OAuth handled by those tools' own login
  flows (`claude` / `codex login`), stored in their own user config. tandem does not
  install, template, or relocate these credentials.
- **Tailscale** — `tailscale up` is run interactively by the operator. No auth key is
  embedded, accepted as an argument, or stored in this repo.

## What Home Manager *does* own

The **tools** (git, gh, jq, ripgrep, fd, bat, tmux, mosh, ssh, `o7`) and their
non-secret configuration. It deliberately does **not** manage `~/.gitconfig` identity or
`~/.ssh/config`, so it can never capture a credential into the store.

## Enforcement

- `.gitignore` blocks the concrete local secret/state paths this repo could produce
  (`.env*`, `*.pem`, `*.key`, `secrets/`, tailscale auth-key drops, local `result*`
  symlinks). It is intentionally small and specific — not a giant generic ignore file.
- CI greps the tree for committed key material as a tripwire (see `.github/workflows/`).
- If you ever need a real secret on the box (e.g. a backup password at T3), it goes in a
  file outside the repo with `600` perms, referenced by path — never inlined here.

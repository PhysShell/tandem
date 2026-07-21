# tandem

Phone-first control plane for coding agents.

`tandem` is the setup and (eventually) the software that lets me run Claude Code and
other coding agents on a VPS and drive them from a phone (Pixel 10a / GrapheneOS) —
so work continues away from the main computer, and **a dead UI never means a dead agent**.

It grows on top of two sibling repos:

- [`007`](https://github.com/PhysShell/007) — the cockpit / agent supervisor (lifecycle, recovery, delegation).
- [`Own.NET`](https://github.com/PhysShell/Own.NET) — contains `sandboy`, the syscall/filesystem/network sandbox that fences the agent process tree.

## Status

**Stage 0 — working access (DONE).** Arch VPS reachable from the phone with a
persistent, disconnect-proof session:

```
phone (Termux) ──mosh──► VPS ──► tmux ──► claude   (subscription OAuth, no API key)
```

Everything installed and hardened. See [`docs/phone-workflow.md`](docs/phone-workflow.md)
to connect, and [`ROADMAP.md`](ROADMAP.md) for what gets built next.

## Layout

- `flake.nix` — Nix dev shell (currently the GitHub CLI; grows into the full toolchain).
- `docs/` — operational docs (how to connect, VPS setup record).
- `ROADMAP.md` — the staged plan toward the 007 cockpit.

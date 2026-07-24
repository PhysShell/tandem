# Deployment roadmap

This is a **deployment and operations** roadmap for one phone-first 007 workstation. It is
deliberately *not* the 007 product roadmap — the product's build order (o7d, event
protocol, Cockpit, adapters, ledger) lives in
[`PhysShell/007`](https://github.com/PhysShell/007). Stages here describe *bringing a host
online and keeping it operable*, not building features.

Legend: ✅ done · 🚧 in progress · ⏳ planned

---

## T0 — Tailscale + mosh + tmux baseline 🚧

The phone can reach the VPS over a persistent, disconnect-proof session.

- ✅ mosh + tmux persistence proven (phone → VPS → tmux `main`, survives Wi-Fi↔cellular
  switches and app kills). This is the floor everything else stands on.
- 🚧 Tailscale as the transport. The runbook
  ([`docs/phone-workflow.md`](docs/phone-workflow.md)) is now Tailscale-first
  (`<tandem-vps-tailnet-name>` over MagicDNS), but **joining the tailnet
  (`tailscale up`) is a manual operator step and is not claimed as executed here.**

## T1 — Arch workstation foundation 🚧

*This repository.* Reproducible, rollback-able deployment of the workstation:

- Standalone Home Manager config (`tandem@tandem-vps`) with a minimal toolset;
- pinned 007 build exposed as `o7`;
- `nix run .#deploy` / `#check` / `#rollback`;
- root-owned Arch bootstrap with explicit `--check` / `--apply`;
- a staging user path for safe validation.

Delivered as code and validated by CI. **Field activation on the real VPS is a manual
acceptance step** (see [`docs/staging.md`](docs/staging.md)) and is not marked done until
executed on the box.

## T2 — pinned o7d deployment ⏳

When `o7d` exists in 007, deploy it as a **user** systemd service (linger already enabled
in T1), pinned the same way `o7` is. No o7d implementation happens here — tandem only gains
the deployment slot. Until then, persistence is tmux's job, not o7d's.

## T3 — persistent state and backup ⏳

A durable, backed-up state directory for the ledger and workstation state, with a
documented restore. T1 only *documents* the slot; no backup tooling is shipped yet.

## T4 — private Cockpit publication through Tailscale ⏳

Publish the (007-provided) Cockpit UI privately over the tailnet — Tailscale Serve to
tailnet peers only. **No Funnel, no public exposure.** tandem does not implement Cockpit.

## T5 — upgrade and rollback ⏳

Deliberate upgrade flow: `nix flake update`, review the revision delta, redeploy, and a
rehearsed rollback. T1 ships the rollback primitive (`nix run .#rollback`); T5 makes the
whole upgrade loop a routine.

## T6 — phone-first end-to-end acceptance ⏳

The full acceptance pass from the phone: reachability, mosh reconnect across network
switches, Termux force-stop and reconnect, VPS-reboot behavior, and the honest persistence
story (tmux today; o7d + ledger replay once T2 lands).

---

## Operating principles

- **UI death ≠ agent death — but reboot ≠ survival.** Today a phone/UI disconnect does
  not kill a process owned by tmux. A **host reboot kills everything** — no tmux or o7d
  process survives it. The stronger *disconnect* guarantee — a run owned by `o7d` with
  missed events replayed from the ledger, and an interrupted attempt recorded across a
  reboot for explicit recovery (not process survival) — belongs to 007 and lands here only
  at **T2+**. It is **not** implemented yet. See `docs/phone-workflow.md`.
- **Honest state.** Never report a stage as done because its code exists; a stage is done
  when it is demonstrated on the target. Field tests that were not run are reported as
  `NOT EXECUTED`, never invented.
- **Build lean.** 1 core / 2 GB. Favour the pinned daemon + thin tooling over anything
  heavy on the box. No decorative packages.
- **Deliberate upgrades.** 007 and Arch are upgraded on purpose, reviewed, and
  rollback-able — never automatically.

# Roadmap

Build order toward a phone-first cockpit for coding agents. Each stage is usable on its
own; we only move on when the previous one earns its keep. Distilled from the 007 /
Sandboy design notes.

Guiding principles:
- **UI death ≠ agent death.** The agent process outlives any client, tab, or phone.
- **Honest state.** Never show `running` for something that a reboot actually killed.
- **Deterministic veto.** The sandbox and an explicit policy have the final say over any
  model-side "auto" decision — allow can be overridden to deny, never the reverse.
- **Exact model.** No silent fallback model; a drift trips a kill switch.
- **Build lean.** The VPS is 1 core / 2 GB. Favor a small daemon + thin UI over a heavy
  Next.js build running on the box.

---

## S0 — Working access ✅ (done)

Phone → mosh → VPS → tmux → Claude Code, subscription OAuth, no API key. Key-only SSH,
persistent tmux session. This is the floor everything else stands on.

## S1 — Session registry (read-only)

Index every Claude/Codex session from `~/.claude/projects/**/*.jsonl` into a SQLite cache
(project, branch, model, first/last message, tokens, full-text search). Sources stay
read-only; scan is incremental (mtime-based). Deliver: search + list old runs by content.

## S2 — Persistent agent worker (the core shift)

Run Claude as a **long-lived Agent SDK worker per active session**, not a series of
one-shot `claude -p`. A small daemon (`o7d`) owns the workers; the UI only subscribes.
- Worker survives UI/phone death; reconnect replays missed events.
- **Live permission-mode switch** (plan / ask / acceptEdits / auto / bypass) without
  changing the session id. UI shows `requested` vs `effective` — never a lit button that
  lies about the underlying process.
- `bypass` is only *available* when sandbox attestation == enforced.

## S3 — Lifecycle + recovery

Explicit state machine: `idle · running · waiting · stalled · crashed · completed ·
needs-human`. Append-only event log with monotonic sequence numbers per conversation, so
the client resumes with `?after=<seq>` — no lost messages, no dupes across reconnects.
Recovery **intent**: before a risky step the agent records its own next instruction, not a
blind generic "continue".

## S4 — Workspace restore

Restore the whole workspace after a crash, not just a URL list: open chats + order,
drafts, selected agent, permission mode, model lock, scroll, open diff, last event cursor.
One "Restore all" button. Honest post-reboot status: `INTERRUPTED_BY_HOST_RESTART`, with
enough saved (session id, branch, worktree, last tool call) to resume as a new attempt.

## S5 — Sandbox + delegation

Fence the agent process tree with **sandboy** (syscall/filesystem/network boundary);
privileged tandem tools stay RPC calls into the daemon, never in-process functions with
host access. Delegation contract for child agents: commit the work, return branch/commit +
artifacts + a structured DONE/FAILED — evidence, not a claim.

## S6 — Cockpit UI

Thin mobile web/PWA over the daemon's event stream. Top bar: model (exact, locked),
permission mode, sandbox state, run status, rate-limit meters (`five_hour`, `seven_day`,
`opus`). At 80–90% of the 5-hour or Opus window, auto fan-out/delegation is disabled.

---

## Notes / open questions

- **Compute:** the cockpit UI may need to run off-box or be kept minimal; the 2 GB VPS is
  fine for the daemon + Claude workers but not a heavy JS build server.
- **Auth:** subscription OAuth (`claude setup-token` / login) is fine for single-owner use.
  It must **not** become a multi-user service on one OAuth token — that needs an API key.
- **Model policy:** disable `fallbackModel`; treat any fallback as a drift event.

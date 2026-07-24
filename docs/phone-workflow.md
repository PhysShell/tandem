# Working from the phone

Target: open a 007 session on the VPS from a Pixel (GrapheneOS), survive network switches
and app kills, and reconnect exactly where you left off.

```
Pixel (Termux) ──Tailscale──► mosh ──► tmux "main" ──► o7 / claude / codex
```

- **Tailscale** = the network. The VPS is reached by its **tailnet name**, not a public
  IP, so nothing here depends on a hard-coded address or an open public port.
- **mosh** = the connection. Survives Wi-Fi↔cellular switches, phone sleep and roaming,
  with instant local echo.
- **tmux** = the session on the server. Keeps work alive even if the phone/app dies.
  Reattach to find everything intact.

Throughout, `<tandem-vps-tailnet-name>` is the placeholder for your VPS's Tailscale
MagicDNS name (e.g. `tandem-vps` or `tandem-vps.tail1234.ts.net`). **Do not hard-code a
public IP as the canonical config** — use the tailnet name.

---

## One-time phone setup

1. Install **Termux** and **Tailscale** from **F-Droid** (the maintained builds).
2. Bring the phone onto the same tailnet as the VPS (open the Tailscale app, sign in).
   Confirm the VPS shows up and is reachable by name.
3. In Termux:
   ```sh
   pkg update && pkg install mosh openssh
   ```
4. Generate a **phone-specific** Ed25519 key (safer than copying a laptop key around):
   ```sh
   ssh-keygen -t ed25519 -f ~/.ssh/tandem-phone -C tandem-phone
   cat ~/.ssh/tandem-phone.pub    # add this line to tandem@VPS:~/.ssh/authorized_keys
   ```
   Adding the public key to the VPS is a manual step you do once, by hand. tandem never
   touches `authorized_keys` for you.
5. Termux `~/.ssh/config` so commands stay short — **tailnet name, not an IP**:
   ```
   Host tandem
       HostName <tandem-vps-tailnet-name>
       User tandem
       IdentityFile ~/.ssh/tandem-phone
   ```

## Daily use — one command

```sh
mosh tandem -- tmux new-session -A -s main
```

- `tmux new-session -A -s main` = attach the session named `main`, or create it if absent.
- Inside, run `o7` / `claude` / `codex` once. It keeps running in `main`.
- Phone died / closed Termux / changed networks? Run the **same command** again — you are
  back in `main` with the work right where it was.

Without the ssh-config alias, the full form is:
```sh
mosh --ssh="ssh -i ~/.ssh/tandem-phone" tandem@<tandem-vps-tailnet-name> -- tmux new-session -A -s main
```

If your mosh build needs an explicit UDP port, add `-p 60001` (and allow that UDP port to
the VPS **on the tailnet only** — never a public firewall opening).

## Plain-SSH fallback

If mosh ever misbehaves, plain SSH reaches the identical tmux session (you lose only
mosh's roaming/echo niceties):

```sh
ssh -t tandem tmux new-session -A -s main
```

## tmux on a touch keyboard

Prefix is **Ctrl-b** (Termux's extra-keys row has a Ctrl key). This matches
[`modules/terminal.nix`](../modules/terminal.nix).

| Do | Keys |
|---|---|
| Detach (leave session running) | `Ctrl-b` then `d` |
| New window | `Ctrl-b` then `c` |
| Next / previous window | `Ctrl-b` then `n` / `p` |
| Split panes | `Ctrl-b` then `\|` or `-` |
| Scroll back | touch-drag (mouse mode is on) |
| Reload config | `Ctrl-b` then `r` |

> The Home Manager tmux config is written to `~/.config/tmux/tmux.conf`. If an older
> hand-written `~/.tmux.conf` exists it takes precedence — remove or rename it so the
> managed config applies.

---

## Acceptance checks (phone field tests)

Run these from the phone; they are **manual** and are reported as `NOT EXECUTED` until
actually performed on real hardware.

1. **Reachability** — `mosh tandem -- true` connects over the tailnet by name.
2. **Wi-Fi ↔ mobile-data reconnect** — attach `main`, start a long-running command,
   toggle Wi-Fi off (fall back to mobile data) and back. mosh should re-establish and the
   session should still be running.
3. **Forced Termux shutdown** — force-stop Termux from Android app settings mid-session,
   reopen, re-run the daily command. You should land back in `main`, work intact.

## What persistence means today vs. later

**Today** (tmux):

> Phone/UI death does not kill a process **owned by tmux**. You reattach and it is still
> running. But if the **VPS itself reboots**, the tmux session is gone — you restart the
> work (e.g. `claude --resume` / re-launch `o7`).

**Future** (o7d, arrives at roadmap **T2**, not implemented here):

> Phone/UI death does not kill a run **owned by o7d**, and missed events **replay from the
> ledger** on reconnect — so a run survives even a host restart.

That future guarantee is **not implemented yet**. Do not rely on it; rely on tmux
persistence and the VPS-reboot caveat above.

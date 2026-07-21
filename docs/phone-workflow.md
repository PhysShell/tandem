# Working from the phone

Target: open Claude Code on the VPS from a Pixel 10a (GrapheneOS), survive network
switches and app kills, reconnect to exactly where you left off.

```
phone (Termux) ──mosh (udp/60001)──► VPS ──► tmux "main" ──► claude
```

- **mosh** = the connection. Survives WiFi↔cellular switches, phone sleep, roaming; instant local echo.
- **tmux** = the session on the server. Keeps `claude` alive even if the phone/app dies. Reattach to find everything intact.

## One-time phone setup

1. Install **Termux** from **F-Droid** (not Play Store — the F-Droid build is the maintained one).
2. In Termux:
   ```sh
   pkg update && pkg install mosh openssh
   ```
3. Get a key onto the phone. **Recommended:** generate a phone-specific key and have it
   added to the VPS (safer than copying the laptop key around):
   ```sh
   ssh-keygen -t ed25519 -f ~/.ssh/tandem-phone -C tandem-phone
   cat ~/.ssh/tandem-phone.pub      # send this line to be added to tandem@VPS
   ```
   (Alternatively copy the existing `test-vps` private key to `~/.ssh/` and `chmod 600` it.)
4. Optional `~/.ssh/config` in Termux so commands stay short:
   ```
   Host vps
       HostName 192.248.184.141
       User tandem
       IdentityFile ~/.ssh/tandem-phone
   ```

## Daily use — one command

```sh
mosh -p 60001 vps -- tmux new-session -A -s main
```

- `tmux new-session -A -s main` = attach the session named `main`, or create it if absent.
- Inside, run `claude` once. It keeps running in `main` forever.
- Phone died / closed Termux / changed networks? Run the **same command** again — you're back in `main` with `claude` right where it was.

Without the ssh config, the full form is:
```sh
mosh -p 60001 --ssh="ssh -i ~/.ssh/tandem-phone" tandem@192.248.184.141 -- tmux new-session -A -s main
```

## tmux on a touch keyboard

Prefix is **Ctrl-b** (Termux's extra-keys row has a Ctrl key).

| Do | Keys |
|---|---|
| Detach (leave session running) | `Ctrl-b` then `d` |
| New window | `Ctrl-b` then `c` |
| Next / previous window | `Ctrl-b` then `n` / `p` |
| Split panes | `Ctrl-b` then `\|` or `-` |
| Scroll back | just touch-drag (mouse mode is on) |
| Reload config | `Ctrl-b` then `r` |

Detaching is safe and normal — the agent keeps working. You only ever "lose" a session
if the VPS itself reboots (then `claude --resume` picks the conversation back up).

## Fallback (if mosh ever misbehaves)

Plain SSH still reaches the same tmux session:
```sh
ssh -t vps tmux new-session -A -s main
```
You lose mosh's roaming/echo niceties but the persistent session is identical.

{ ... }:
# Terminal environment tuned for driving the workstation from a phone over
# mosh. Conservative on purpose: no plugin manager, no theme framework, no
# dependency on a graphical terminal. This is the operational + recovery
# channel, so it must stay boring and reliable on a 2-GB box.
{
  programs.tmux = {
    enable = true;

    # Mouse mode on: touch-drag scrollback and pane select is the primary
    # interaction on a phone keyboard.
    mouse = true;

    # Reasonable scrollback for reviewing agent output after the fact, without
    # eating memory on a small VPS.
    historyLimit = 50000;

    # Keep the familiar Ctrl-b prefix (Termux's extra-keys row has Ctrl) and a
    # 1-based index that matches the phone runbook.
    prefix = "C-b";
    baseIndex = 1;

    # Snappier prefix on high-latency mobile links; no graphical terminal
    # assumptions.
    escapeTime = 10;
    terminal = "screen-256color";

    # Do NOT enable a plugin manager or status theme here. The persistent named
    # session workflow ("main") is provided by the operator command
    #   tmux new-session -A -s main
    # documented in docs/phone-workflow.md, not by a plugin.
    extraConfig = ''
      # Windows/panes start at 1 to match base-index and the phone runbook.
      setw -g pane-base-index 1

      # Intuitive, phone-friendly splits that keep the current working dir.
      bind | split-window -h -c "#{pane_current_path}"
      bind - split-window -v -c "#{pane_current_path}"

      # Reload config in place (Ctrl-b r) — matches the documented workflow.
      bind r source-file ~/.config/tmux/tmux.conf \; display "tmux.conf reloaded"

      # Renumber windows when one closes so the phone number-keys stay dense.
      set -g renumber-windows on

      # Keep the pane title/window name stable for reattach clarity.
      set -g allow-rename off
    '';
  };
}

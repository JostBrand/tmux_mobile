# tmux_mobile (working title)

Android client for remote tmux sessions, built on tmux **control mode** (`-CC`)
instead of raw terminal emulation. The app receives structured notifications
(panes, windows, sessions as objects) and can therefore do what plain
terminal apps can't:

- real per-pane scrollback (via `capture-pane -p -e -S -`)
- gesture-first navigation (swipe between panes/windows)
- a configurable on-screen keybar instead of raw keyboard input

The tmux session lives on the server: the app attaches/detaches at will and
can coexist with desktop clients.

## Status

**M1 (protocol spike) - done.** `lib/src/control_mode/control_mode_client.dart`
speaks the tmux control protocol over a byte stream. Verified against real
tmux 3.4:

- `%session-changed` / `%output` / `%begin`+`%end` command bracketing
  (incl. `%error` for failed commands)
- `send-keys`, `display-message -p`, `capture-pane` scrollback fetch

**M2 (transport + rendering) - done.**

- `lib/src/transport/ssh_tmux_transport.dart`: dartssh2 client, PTY session,
  key/password auth, `tmux -CC attach-session` over SSH (like iTerm2)
- `lib/src/render/pane_output_feeder.dart` + `pane_screen.dart`: `%output`
  lines feed an xterm Terminal; initial screen seeded via `capture-pane -p -e`
  (`refresh-client -C` only redraws on size change)
- `lib/src/ui/keybar.dart` + `session_screen.dart`: minimal keybar
  (Esc/Tab/arrows/Enter/C-c...) and swipe-to-switch-pane (app-side pane state,
  tmux does not notify control clients about active-pane changes)
- End-to-end integration test over a REAL sshd (non-root, 127.0.0.1:2222,
  started by the workspace startup script) with the workspace key

Up next (M3): connection profiles (host/user/key, known-hosts TOFU),
full gesture layer, scrollback UX (client-side cache + tmux copy-mode),
keybar configurability, design pass.

## Run tests

```sh
flutter test
```

- Local tmux integration tests spawn a real tmux server on a private socket
  (tmux must be installed - it is in the dev image).
- The SSH integration test needs the workspace sshd on 127.0.0.1:2222
  (started by the workspace startup script; skips when unreachable).

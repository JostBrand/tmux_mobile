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
speaks the tmux control protocol over a byte stream (local subprocess in
tests, SSH channel later via `dartssh2`). Verified against real tmux 3.4:

- `%session-changed` / `%output` / `%begin`+`%end` command bracketing
  (incl. `%error` for failed commands)
- `send-keys`, `display-message -p`, `capture-pane` scrollback fetch
- PTY requirement handled via the `script` wrapper in tests (the app will
  get a PTY from the SSH channel)

Up next (M2): SSH transport (dartssh2), pane/window rendering (xterm
package), gesture layer, minimal keybar.

## Run tests

```sh
flutter test
```

The integration tests spawn a real tmux server on a private socket - tmux
must be installed (it is in the dev image).

# tmux_mobile (working title)

Android client for remote tmux sessions, built on tmux **control mode** (`-CC`)
instead of raw terminal emulation. The app receives structured notifications
(panes, windows, sessions as objects) and can therefore do what plain
terminal apps can't:

- real per-pane scrollback (history sheet via `capture-pane -p -e -S -`)
- gesture-first navigation (swipe between panes)
- a configurable on-screen keybar with sticky Ctrl/Alt modifiers

The tmux session lives on the server: the app attaches/detaches at will and
can coexist with desktop clients.

## Status

**M1 (protocol spike) - done.** `lib/src/control_mode/control_mode_client.dart`
speaks the tmux control protocol over a byte stream. Verified against real
tmux 3.4: `%session-changed`/`%output`, `%begin`+`%end` command bracketing
(incl. `%error`), `send-keys`, `display-message -p`, `capture-pane`.

**M2 (transport + rendering) - done.**

- `SshTmuxTransport` (dartssh2): PTY session running `tmux -CC attach-session`
- `PaneOutputFeeder`: `%output` -> xterm Terminal; screen seeding via
  `capture-pane -p -e` (refresh-client only redraws on size change)
- End-to-end SSH test against a real sshd (non-root, 127.0.0.1:2222 in the
  workspace)

**M3 (profiles, scrollback, keybar, shell) - done.**

- Connection profiles (host/user/port/session, key auth via
  flutter_secure_storage, password prompt at connect time - never stored)
- Known-hosts: TOFU on first connect, reject on fingerprint mismatch
- History sheet: paginated server-side scrollback with overlap dedup,
  tap-to-copy
- Keybar with sticky Ctrl/Alt modifiers; per-pane terminals survive pane
  switches (no missed output)
- Home/profile-edit/connect screens, Material 3 dark theme

Up next (M4): F-Droid release pipeline (reproducible build, metadata),
notification/UX polish, %layout-change parsing for real pane layouts.

## Run tests

```sh
flutter test
```

- Local tmux integration tests spawn a real tmux server on a private socket.
- The SSH integration test needs the workspace sshd on 127.0.0.1:2222
  (skips when unreachable).

## Releases (self-hosted via Forgejo)

APKs are distributed as **Forgejo releases** on git.jostbrandstetter.com:

- `tool/release.sh` builds the split-per-abi release APKs and publishes
  them as a release (tag = the pubspec version) with the CI bot
  credentials (FORGEJO_CI_* from the workspace secret).
- The phone gets updates via **Obtainium**: add
  `https://git.jostbrandstetter.com/jost/tmux_mobile` as an app source
  (Forgejo release), then check/install updates with one tap.
- The GitHub repo is a push mirror (pushed by release.sh when the
  `github` remote exists).

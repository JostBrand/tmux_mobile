# Security Notes

Threat model: the app connects from a personal Android device to the
user's own (or trusted) tmux hosts over SSH. Adversaries considered:
network attackers (MITM), other apps on the device, device loss/theft.

## Implemented

- **Host keys (MITM protection)**: TOFU - the server key fingerprint is
  stored on first connect and every later connect must match; a mismatch
  rejects the connection (a changed key can mean an attack).
- **Secrets**: SSH private keys live in the Android Keystore via
  flutter_secure_storage (hardware-backed encryption). Passwords are
  prompted per connect and are never persisted - only cached in memory
  for the session lifetime (needed for auto-reconnect).
- **MFA/2FA**: keyboard-interactive auth is answered through the same
  password prompt (non-echo prompts), so TOTP/duo-style logins work.
- **No backup**: `android:allowBackup=false` - profiles/known-hosts are
  not silently restored onto a different device.
- **External intents require consent**: text arriving via
  PROCESS_TEXT/ACTION_SEND is NEVER sent into a live terminal
  automatically - a confirmation dialog (Send / Send+Enter / Discard)
  always sits between another app's input and the pane. This closes the
  "hostile app fires an intent to inject keystrokes" hole.
- **Screenshots**: optional FLAG_SECURE setting blocks screenshots and
  screen recording of terminal content (Settings -> Block screenshots).
- **No cleartext network**: the app speaks raw SSH only; no HTTP stack,
  so Android's cleartext policy is moot.
- **SSH algorithms**: dartssh2 defaults negotiate modern primitives
  (x25519 kex, ed25519/rsa-sha2 host keys, AEAD ciphers); SHA-1/CBC
  exist only as last-resort fallbacks for old servers.

## Accepted risks / tradeoffs

- **TOFU window**: the very first connect to a host trusts the presented
  key. Same tradeoff as every SSH client; verify the fingerprint out of
  band if the host matters.
- **flutter_secure_storage pinned at 9.2.4**: newer versions require
  compileSdk 37, which the workspace SDK cannot provide yet (see repo
  history). Evaluate the bump when the SDK moves.
- **Plaintext JSON profiles/known-hosts/settings** in app-private
  storage (no secrets inside; keys are Keystore-only). A rooted device
  can read anything anyway.
- **Old-server fallbacks**: SHA-1 kex/hostkey algorithms remain enabled
  for compatibility with ancient SSH servers. A per-profile
  "strict algorithms" toggle is a possible future hardening.
- **Notification content**: activity notifications contain pane ids only,
  no pane content.

## Do not add

- Pinning/verifying the tmux server itself: the connection is
  user-chosen; tmux commands from a hostile server can only affect that
  server (all server-derived strings are treated as data).

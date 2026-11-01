# TerminalKun2 development

- Speak Japanese to the user; write code comments in English. Project code is MIT licensed.
- This is a native iOS 17+ app. Use SwiftUI / UIKit, real SSH / SFTP, the bundled Japanese dictionary, and actual filesystem / HTTP operations. Do not introduce demo connections or a WebView terminal.
- Read `docs/feature-parity.md` and `docs/validation.md` before changing platform behavior. Do not describe the app-owned local command environment as a fork/exec shell, or Secure Enclave as external FIDO2.
- Use `bash scripts/dev.sh test`, `bash scripts/dev.sh build`, `bash scripts/dev.sh device`, and `bash scripts/ssh-ui-test.sh`. The latter creates and cleans up its own simulator and actual loopback SSH / PTY fixture.
- Preserve `Package.resolved`. New or updated dependencies, including transitive dependencies, must have been published for at least 24 hours and reviewed. Update audits only after reviewing source. Never silence audit failures by dropping checks.
- Vendor SSH modifications are documented in `Vendor/PATCHES.md`. Run the real OpenSSH integration test after protocol changes. Keep input and resize writes ordered, and require host validation before authentication.
- Keep UI state on MainActor. Complete modal transitions via their dismissal events. Stop keyboard repeats on geometry / language / application state changes.
- Keep private keys in device-only Keychain. Do not persist passwords, auto-execute generated commands, accept changed host keys, grant terminal clipboard reads, or let remote graphics open local files.
- Test fixtures, logs, application settings, SSH aliases, and private screenshots remain under ignored build or reference directories. Screenshots in docs must use only owned test data.
- Keep CI manual / opt-in. Record validation and material limitations in docs, and review correctness and security directly in the current Codex agent.

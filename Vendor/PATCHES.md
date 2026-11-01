# Reviewed SSH changes

The upstream licenses and notices remain in each directory. Project changes are MIT licensed.

- Citadel 0.12.1 (`ae8562f895de06ccb86fdb1cbb65fd99c8976e12`).
- swift-nio-ssh 0.3.7 (`d88989f3d3bb1dfb2a38ce4af598afbf7fc3095c`). The authoritative revision is also recorded in `docs/vendor-audit.json`.

Citadel's dependency on swift-nio-ssh is a local path so the exact reviewed protocol changes are used on the simulator, device, and command-line tests.

## RSA authentication

RSA public key blobs retain the `ssh-rsa` format. The authentication algorithm and signature use `rsa-sha2-256`, per RFC 8332. The NIOSSH user-authentication message and key-exchange algorithm checks distinguish the key format from the negotiated signature algorithm. Agent requests support the SHA-256 and SHA-512 flags; SHA-1 RSA agent signatures are rejected.

## SSH agent forwarding

The channel multiplexer accepts `auth-agent@openssh.com` and the PTY channel can request `auth-agent-req@openssh.com`. Agent channel initialization is supplied explicitly by the app. The app exposes only the selected connection key, compares key blobs, limits packet and buffer sizes and signing rate, and disables signing when the application leaves the foreground. There are no mutation, private-key export, filesystem, or arbitrary execution operations in the agent.

## Interactive host verification and fixture shutdown

The handshake timeout follows the configured authentication timeout (120 seconds by default), allowing time for the native fingerprint confirmation sheet. Server PTY output continuations are finished when a channel becomes inactive. The app handles Citadel's second close after normal PTY EOF without hiding other transport errors.

## Verification

`Tests/TerminalTransportTests` connects to an actual, temporary OpenSSH server. It exercises encrypted Ed25519 and RSA keys, strict host validation, Japanese input interleaved with resize events, SFTP file contents and quoted paths, and a nested OpenSSH connection using the forwarded agent. UI tests use a separate real PTY fixture on loopback. No server or fixture is shipped in the iPhone app.

`docs/vendor-audit.json` records the SHA-256 of every vendored file. `scripts/check-dependencies.py` checks those hashes and the upstream minimum release age before building.

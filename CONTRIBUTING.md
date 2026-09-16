# Contributing to NetRadar

Thank you for contributing to NetRadar. This project adheres to strict security, determinism, and quality standards established by the Omarchy Linux ecosystem.

## Security Architecture & Development Standards

All contributions must comply with the following architectural requirements:

1. Subprocess Isolation:
   - Subprocesses must execute in an isolated process group via `cmd.process_group(0)`.
   - The execution environment must be explicitly wiped and restricted (`PATH=/usr/bin:/bin`, `LC_ALL=C`).
   - File descriptors for piped output must use `O_NONBLOCK` and poll with monotonic deadlines (`Instant::now() >= deadline`).
   - Reading from subprocess pipes must be capped at 64 KiB (`MAX_BUFFER_CAP = 64 * 1024`).

2. Unconditional Process Reaping:
   - All spawned subprocesses must be governed by an RAII guard (`ProcessGroupGuard`).
   - On exit, cancellation, or drop, the process group must receive `SIGTERM`, a 10ms grace period, and then `SIGKILL` to prevent orphan or zombie processes.

3. Mode 0600 Storage and Symlink Defense:
   - Sensitive user states, aliases, and known hosts must be persisted with mode `0600` in directories with mode `0700`.
   - Writes must be atomic (writing to `.tmp_*`, followed by `sync_all()`, then `fs::rename`).
   - Symlinks, FIFOs, and special devices must be rejected using `fs::symlink_metadata`.
   - File reads must be bounded with a strict 1 MiB threshold using `take(MAX_REGISTRY_FILE_SIZE + 1)`.

4. Unprivileged Execution:
   - NetRadar operates without `sudo`, `pkexec`, or `setuid` binaries.
   - Network state is obtained via unprivileged Linux kernel interfaces (`/proc/net/arp`, `ip neigh`), POSIX reverse DNS (`libc::getnameinfo`), and safe ICMP/UDP probes.
   - Probing must strictly target private (RFC 1918), loopback, or link-local IPv4 addresses.

5. Dynamic UI String Safety:
   - All dynamic strings displayed in Quickshell/QML (IPs, MACs, hostnames, vendors, aliases) must explicitly declare `textFormat: Text.PlainText` to prevent HTML/XSS injection.

6. Zero Emojis Policy:
   - No unicode emojis are permitted in source code, docstrings, commit messages, CLI output, or documentation.

## Testing

Before submitting pull requests or packaging:
- Run `cargo test -- --nocapture` to ensure all unit and integration tests pass.
- Run `cargo clippy -- -D warnings` to verify zero lint warnings.

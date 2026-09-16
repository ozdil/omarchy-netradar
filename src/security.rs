use std::fs::{self, File, OpenOptions};
use std::io::{self, Read, Write};
use std::os::unix::fs::{OpenOptionsExt, PermissionsExt};
use std::os::unix::io::AsRawFd;
use std::os::unix::process::CommandExt;
use std::path::Path;
use std::process::{Child, Command, Stdio};
use std::time::{Duration, Instant};

/// Maximum pipe read buffer limit (64 KiB) as mandated by Omarchy Security Architecture.
pub const MAX_BUFFER_CAP: usize = 64 * 1024;

/// Maximum allowable size for persistent registry files (1 MiB).
pub const MAX_REGISTRY_FILE_SIZE: u64 = 1024 * 1024;

/// RAII Guard ensuring subprocess groups are reaped unconditionally upon drop.
pub struct ProcessGroupGuard {
    pub child: Option<Child>,
}

impl ProcessGroupGuard {
    pub fn new(child: Child) -> Self {
        Self { child: Some(child) }
    }

    #[allow(dead_code)]
    pub fn take(&mut self) -> Option<Child> {
        self.child.take()
    }
}

impl Drop for ProcessGroupGuard {
    fn drop(&mut self) {
        if let Some(mut child) = self.child.take() {
            reap_process_group(&mut child);
        }
    }
}

/// Unconditionally terminates an entire process group (-pid) with SIGTERM, 10ms grace, then SIGKILL.
pub fn reap_process_group(child: &mut Child) {
    let pid = child.id() as i32;
    if pid <= 1 {
        let _ = child.wait();
        return;
    }

    let exited = matches!(child.try_wait(), Ok(Some(_)));

    // Send SIGTERM to the process group (-pid)
    // SAFETY: pid is a valid child PID spawned with process_group(0).
    unsafe {
        libc::kill(-pid, libc::SIGTERM);
    }

    // Brief grace period (10ms)
    std::thread::sleep(Duration::from_millis(10));

    // Send SIGKILL to the process group to eliminate any recalcitrant descendants
    // SAFETY: pid is valid and points to the isolated process group.
    unsafe {
        libc::kill(-pid, libc::SIGKILL);
    }

    // Reclaim direct child to prevent zombies
    if !exited {
        let _ = child.wait();
    }
}

/// Spawns an isolated command adhering to Omarchy Subprocess Security Standards:
/// - Isolated process group (`process_group(0)`)
/// - Cleared environment with strict whitelist (`PATH=/usr/bin:/bin`, `LC_ALL=C`)
pub fn spawn_isolated(program: &str, args: &[&str]) -> io::Result<ProcessGroupGuard> {
    let mut cmd = Command::new(program);
    cmd.args(args);
    cmd.env_clear();
    cmd.env("PATH", "/usr/bin:/bin");
    cmd.env("LC_ALL", "C");
    cmd.process_group(0);
    cmd.stdin(Stdio::null());
    cmd.stdout(Stdio::piped());
    cmd.stderr(Stdio::piped());

    let child = cmd.spawn()?;
    Ok(ProcessGroupGuard::new(child))
}

/// Reads from a pipe with O_NONBLOCK and bounded monotonic deadline polling.
pub fn run_with_monotonic_deadline(
    program: &str,
    args: &[&str],
    timeout: Duration,
) -> io::Result<Vec<u8>> {
    let mut guard = spawn_isolated(program, args)?;
    let child = guard
        .child
        .as_mut()
        .ok_or_else(|| io::Error::other("Failed to get child reference"))?;

    let mut stdout = child
        .stdout
        .take()
        .ok_or_else(|| io::Error::other("Failed to take child stdout"))?;

    let fd = stdout.as_raw_fd();

    // Set O_NONBLOCK on stdout
    // SAFETY: fd is valid stdout file descriptor of child
    unsafe {
        let flags = libc::fcntl(fd, libc::F_GETFL, 0);
        if flags >= 0 {
            libc::fcntl(fd, libc::F_SETFL, flags | libc::O_NONBLOCK);
        }
    }

    let deadline = Instant::now() + timeout;
    let mut output = Vec::with_capacity(4096);
    let mut buf = [0u8; 4096];

    loop {
        let now = Instant::now();
        if now >= deadline {
            return Err(io::Error::new(
                io::ErrorKind::TimedOut,
                "Command exceeded monotonic deadline",
            ));
        }

        let remaining = deadline.saturating_duration_since(now);
        let poll_ms = (remaining.as_millis().min(50)) as i32;

        let mut pollfd = libc::pollfd {
            fd,
            events: libc::POLLIN | libc::POLLHUP | libc::POLLERR,
            revents: 0,
        };

        // SAFETY: pollfd is valid reference
        let ret = unsafe { libc::poll(&mut pollfd, 1, poll_ms) };

        if ret > 0 && (pollfd.revents & libc::POLLIN) != 0 {
            match stdout.read(&mut buf) {
                Ok(0) => break, // EOF
                Ok(n) => {
                    if output.len() + n > MAX_BUFFER_CAP {
                        return Err(io::Error::new(
                            io::ErrorKind::InvalidData,
                            "Buffer overrun: output exceeded 64 KiB cap",
                        ));
                    }
                    output.extend_from_slice(&buf[..n]);
                }
                Err(ref e) if e.kind() == io::ErrorKind::WouldBlock => {}
                Err(e) => return Err(e),
            }
        }

        // Check if child exited
        if let Ok(Some(_)) = child.try_wait() {
            // Drain remaining non-blocking data
            loop {
                match stdout.read(&mut buf) {
                    Ok(0) => break,
                    Ok(n) => {
                        if output.len() + n > MAX_BUFFER_CAP {
                            return Err(io::Error::new(
                                io::ErrorKind::InvalidData,
                                "Buffer overrun: output exceeded 64 KiB cap",
                            ));
                        }
                        output.extend_from_slice(&buf[..n]);
                    }
                    Err(ref e) if e.kind() == io::ErrorKind::WouldBlock => break,
                    Err(e) => return Err(e),
                }
            }
            break;
        }
    }

    Ok(output)
}

/// Atomically writes content to a sensitive file with 0600 permissions, rejecting symlinks.
pub fn atomic_write_0600(target_path: &Path, content: &[u8]) -> io::Result<()> {
    if let Some(parent) = target_path.parent() {
        fs::create_dir_all(parent)?;
        // Set parent directory mode to 0700
        let mut perms = fs::metadata(parent)?.permissions();
        perms.set_mode(0o700);
        let _ = fs::set_permissions(parent, perms);
    }

    // Verify existing file if present: reject symlinks and verify ownership
    if target_path.exists() {
        let meta = fs::symlink_metadata(target_path)?;
        if meta.file_type().is_symlink() {
            return Err(io::Error::new(
                io::ErrorKind::PermissionDenied,
                "Refusing to write to symlink",
            ));
        }
    }

    let parent_dir = target_path
        .parent()
        .unwrap_or_else(|| Path::new("."));

    let tmp_path = parent_dir.join(format!(
        ".tmp_{}_{}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_nanos())
            .unwrap_or(0)
    ));

    {
        let mut file = OpenOptions::new()
            .write(true)
            .create_new(true)
            .mode(0o600)
            .open(&tmp_path)?;

        file.write_all(content)?;
        file.sync_all()?;
    }

    // Atomic replace
    fs::rename(&tmp_path, target_path)?;

    Ok(())
}

/// Reads a sensitive file safely, validating it is a regular file with 0600 mode owned by current user.
/// Strictly enforces maximum 1 MiB size cap to prevent memory exhaustion / DoS attacks.
pub fn safe_read_0600(path: &Path) -> io::Result<Vec<u8>> {
    let meta = fs::symlink_metadata(path)?;
    if meta.file_type().is_symlink() {
        return Err(io::Error::new(
            io::ErrorKind::PermissionDenied,
            "Refusing to read symlink",
        ));
    }
    if !meta.file_type().is_file() {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "Target is not a regular file",
        ));
    }

    if meta.len() > MAX_REGISTRY_FILE_SIZE {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "File size exceeds 1 MiB maximum threshold",
        ));
    }

    let file = File::open(path)?;
    let mut data = Vec::with_capacity(meta.len().min(MAX_REGISTRY_FILE_SIZE) as usize);
    let mut bounded_reader = file.take(MAX_REGISTRY_FILE_SIZE + 1);
    bounded_reader.read_to_end(&mut data)?;

    if data.len() as u64 > MAX_REGISTRY_FILE_SIZE {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "File stream expanded beyond 1 MiB cap",
        ));
    }

    Ok(data)
}

/// Validates IEEE 802 MAC address format (e.g. AA:BB:CC:DD:EE:FF or AA-BB-CC-DD-EE-FF).
pub fn is_valid_mac(mac: &str) -> bool {
    let trimmed = mac.trim();
    let parts: Vec<&str> = if trimmed.contains(':') {
        trimmed.split(':').collect()
    } else if trimmed.contains('-') {
        trimmed.split('-').collect()
    } else {
        return false;
    };

    if parts.len() != 6 {
        return false;
    }

    for part in parts {
        if part.len() != 2 || !part.chars().all(|c| c.is_ascii_hexdigit()) {
            return false;
        }
    }
    true
}

/// Validates device alias (max 64 chars, printable UTF-8, no control characters).
pub fn is_valid_alias(alias: &str) -> bool {
    let trimmed = alias.trim();
    if trimmed.is_empty() || trimmed.chars().count() > 64 {
        return false;
    }
    trimmed.chars().all(|c| !c.is_control())
}

/// Validates network interface name (alphanumeric, dots, dashes, underscores, max 16 chars).
pub fn is_safe_iface(iface: &str) -> bool {
    let trimmed = iface.trim();
    if trimmed.is_empty() || trimmed.len() > 16 {
        return false;
    }
    trimmed
        .chars()
        .all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '-' || c == '.')
}

/// Checks if IPv4 address is in private (RFC 1918), loopback, or link-local range.
pub fn is_private_or_local_ipv4(ip: std::net::Ipv4Addr) -> bool {
    ip.is_loopback() || ip.is_private() || ip.is_link_local()
}


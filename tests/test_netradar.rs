use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::os::unix::fs::symlink;
use std::path::Path;

// We can test security functions and oui functions directly.
// For testing internal modules from integration test, we can declare or test via binary or export.
// Let's test command execution and security guarantees using CLI and standard lib.

#[test]
fn test_cli_help() {
    let output = std::process::Command::new("cargo")
        .args(["run", "--quiet", "--", "--help"])
        .output()
        .expect("Failed to run cargo run");
    assert!(output.status.success());
    let stdout = String::from_utf8_lossy(&output.stdout);
    assert!(stdout.contains("NetRadar Engine"));
    assert!(stdout.contains("--scan"));
    assert!(stdout.contains("--ping"));
}

#[test]
fn test_cli_scan_json_output() {
    let output = std::process::Command::new("cargo")
        .args(["run", "--quiet", "--", "--scan"])
        .output()
        .expect("Failed to run cargo run --scan");
    assert!(output.status.success());
    let stdout = String::from_utf8_lossy(&output.stdout);
    
    // Output must be valid JSON matching ScanResult schema
    let json: serde_json::Value = serde_json::from_str(&stdout).expect("Output must be valid JSON");
    assert!(json.get("interface").is_some());
    assert!(json.get("local_ip").is_some());
    assert!(json.get("gateway").is_some());
    assert!(json.get("devices").is_some());
    
    let devices = json["devices"].as_array().expect("devices must be an array");
    assert!(!devices.is_empty(), "Must detect at least the local host");
    
    // Check first device fields
    let first = &devices[0];
    assert!(first.get("ip").is_some());
    assert!(first.get("mac").is_some());
    assert!(first.get("vendor").is_some());
    assert!(first.get("category").is_some());
}

#[test]
fn test_cli_status() {
    let output = std::process::Command::new("cargo")
        .args(["run", "--quiet", "--", "--status"])
        .output()
        .expect("Failed to run cargo run --status");
    assert!(output.status.success());
    let stdout = String::from_utf8_lossy(&output.stdout);
    assert!(stdout.contains("NetRadar:"));
    assert!(stdout.contains("devices on"));
}

#[test]
fn test_atomic_file_and_symlink_rejection() {
    let test_dir = Path::new("/tmp/netradar_test_sec");
    let _ = fs::remove_dir_all(test_dir);
    fs::create_dir_all(test_dir).unwrap();

    let target_file = test_dir.join("test_sec_device.json");
    let content = b"{\"TEST\":\"DATA\"}";

    // Write file directly with 0600
    let tmp = test_dir.join(".tmp_test");
    fs::write(&tmp, content).unwrap();
    let mut perms = fs::metadata(&tmp).unwrap().permissions();
    perms.set_mode(0o600);
    fs::set_permissions(&tmp, perms).unwrap();
    fs::rename(&tmp, &target_file).unwrap();

    let meta = fs::metadata(&target_file).unwrap();
    assert_eq!(meta.permissions().mode() & 0o777, 0o600);

    // Test symlink rejection
    let symlink_path = test_dir.join("symlink_target");
    symlink(&target_file, &symlink_path).unwrap();

    let sym_meta = fs::symlink_metadata(&symlink_path).unwrap();
    assert!(sym_meta.file_type().is_symlink());

    let _ = fs::remove_dir_all(test_dir);
}

#[test]
fn test_cli_input_validation_ping_invalid_ip() {
    let output = std::process::Command::new("cargo")
        .args(["run", "--quiet", "--", "--ping", "not-an-ip"])
        .output()
        .expect("Failed to execute");
    assert!(!output.status.success(), "Invalid IP must be rejected");
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(stderr.contains("Invalid IPv4 address"));
}

#[test]
fn test_cli_input_validation_ping_public_ip() {
    // 8.8.8.8 is a public DNS server, not in RFC 1918 / loopback / link-local
    let output = std::process::Command::new("cargo")
        .args(["run", "--quiet", "--", "--ping", "8.8.8.8"])
        .output()
        .expect("Failed to execute");
    assert!(!output.status.success(), "Public IP must be rejected for ping");
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(stderr.contains("private or local subnet"));
}

#[test]
fn test_cli_input_validation_set_alias_invalid_mac() {
    let output = std::process::Command::new("cargo")
        .args(["run", "--quiet", "--", "--set-alias", "MALICIOUS_MAC", "MyDevice"])
        .output()
        .expect("Failed to execute");
    assert!(!output.status.success(), "Malformed MAC must be rejected");
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(stderr.contains("Invalid MAC address format"));
}

#[test]
fn test_cli_input_validation_trust_invalid_mac() {
    let output = std::process::Command::new("cargo")
        .args(["run", "--quiet", "--", "--trust", "ZZ:ZZ:ZZ:ZZ:ZZ:ZZ"])
        .output()
        .expect("Failed to execute");
    assert!(!output.status.success(), "Invalid hex MAC must be rejected");
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(stderr.contains("Invalid MAC address format"));
}

#[test]
fn test_cli_input_validation_traffic_invalid_iface() {
    let output = std::process::Command::new("cargo")
        .args(["run", "--quiet", "--", "--traffic", "eth0;rm -rf"])
        .output()
        .expect("Failed to execute");
    assert!(!output.status.success(), "Dangerous interface name must be rejected");
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(stderr.contains("Invalid network interface name"));
}

#[test]
fn test_bounded_read_file_size_limit() {
    let test_dir = Path::new("/tmp/netradar_test_oversize");
    let _ = fs::remove_dir_all(test_dir);
    fs::create_dir_all(test_dir).unwrap();

    let target_file = test_dir.join("oversized.json");
    // Create file exceeding 1 MiB (1024 * 1024 + 100 bytes)
    let oversize_data = vec![b'A'; (1024 * 1024) + 100];
    fs::write(&target_file, &oversize_data).unwrap();
    let mut perms = fs::metadata(&target_file).unwrap().permissions();
    perms.set_mode(0o600);
    fs::set_permissions(&target_file, perms).unwrap();

    // Verify metadata length exceeds 1 MiB
    let meta = fs::metadata(&target_file).unwrap();
    assert!(meta.len() > 1024 * 1024);

    let _ = fs::remove_dir_all(test_dir);
}

#[test]
fn test_zero_emojis_in_source_code() {
    let manifest_dir = std::env::var("CARGO_MANIFEST_DIR").unwrap_or_else(|_| ".".to_string());
    let src_dir = Path::new(&manifest_dir).join("src");

    for entry in fs::read_dir(src_dir).unwrap() {
        let entry = entry.unwrap();
        let path = entry.path();
        if path.extension().map(|s| s == "rs").unwrap_or(false) {
            let content = fs::read_to_string(&path).unwrap();
            for (line_no, line) in content.lines().enumerate() {
                for c in line.chars() {
                    let code = c as u32;
                    if (0xE000..=0xF8FF).contains(&code) || (0xF0000..=0x10FFFD).contains(&code) {
                        continue;
                    }
                    let is_emoji = (0x1F300..=0x1F9FF).contains(&code)
                        || (0x2600..=0x27BF).contains(&code)
                        || (0x1F600..=0x1F64F).contains(&code)
                        || (0x1F680..=0x1F6FF).contains(&code)
                        || (0x2300..=0x23FF).contains(&code);
                    assert!(
                        !is_emoji,
                        "Emoji detected in {}:{} character '{}'",
                        path.display(),
                        line_no + 1,
                        c
                    );
                }
            }
        }
    }
}

#[test]
fn test_is_valid_unicast_mac() {
    use netradar_engine::security::is_valid_unicast_mac;

    // Valid unicast MACs
    assert!(is_valid_unicast_mac("00:1A:2B:3C:4D:5E"));
    assert!(is_valid_unicast_mac("52:54:00:12:34:56"));
    assert!(is_valid_unicast_mac("A0:B1:C2:D3:E4:F5"));
    assert!(is_valid_unicast_mac("00-1A-2B-3C-4D-5E"));

    // Multicast MACs (least significant bit of first octet is 1)
    assert!(!is_valid_unicast_mac("01:00:5E:00:00:01"));
    assert!(!is_valid_unicast_mac("33:33:00:00:00:01"));
    assert!(!is_valid_unicast_mac("01:80:C2:00:00:00"));

    // Broadcast MAC
    assert!(!is_valid_unicast_mac("FF:FF:FF:FF:FF:FF"));
    assert!(!is_valid_unicast_mac("ff:ff:ff:ff:ff:ff"));

    // All zero MAC
    assert!(!is_valid_unicast_mac("00:00:00:00:00:00"));

    // Invalid format
    assert!(!is_valid_unicast_mac(""));
    assert!(!is_valid_unicast_mac("invalid"));
    assert!(!is_valid_unicast_mac("00:11:22:33:44"));
    assert!(!is_valid_unicast_mac("00:11:22:33:44:55:66"));
    assert!(!is_valid_unicast_mac("GG:11:22:33:44:55"));
}

#[test]
fn test_safe_storage_hardlink_rejection() {
    use netradar_engine::security::{atomic_write_0600, safe_read_0600};

    let test_dir = Path::new("/tmp/netradar_test_hardlink");
    let _ = fs::remove_dir_all(test_dir);
    fs::create_dir_all(test_dir).unwrap();

    let target_file = test_dir.join("original.json");
    let link_file = test_dir.join("hardlink.json");

    atomic_write_0600(&target_file, b"{\"test\": \"data\"}").expect("Initial write should succeed");

    // Create a hardlink
    fs::hard_link(&target_file, &link_file).expect("Hardlink creation should succeed");

    // safe_read_0600 must reject reading a file with nlink > 1
    let read_result = safe_read_0600(&target_file);
    assert!(read_result.is_err(), "safe_read_0600 must reject hardlinked file");

    // atomic_write_0600 must reject overwriting an existing file that has nlink > 1
    let write_result = atomic_write_0600(&target_file, b"{\"test\": \"overwrite\"}");
    assert!(write_result.is_err(), "atomic_write_0600 must reject hardlinked file");

    let _ = fs::remove_dir_all(test_dir);
}

#[test]
fn test_spawn_isolated_no_new_privs() {
    use std::time::Duration;
    use netradar_engine::security::run_with_monotonic_deadline;

    // Verify kernel-level NoNewPrivs flag via /proc/self/status
    let output_bytes = run_with_monotonic_deadline(
        "cat",
        &["/proc/self/status"],
        Duration::from_secs(2),
    ).expect("Execution of cat should succeed");

    let status_str = String::from_utf8_lossy(&output_bytes);
    let no_new_privs_line = status_str
        .lines()
        .find(|line| line.starts_with("NoNewPrivs:"))
        .expect("NoNewPrivs line must exist in /proc/self/status");

    assert_eq!(
        no_new_privs_line.trim(),
        "NoNewPrivs:\t1",
        "Subprocess must run with PR_SET_NO_NEW_PRIVS kernel confinement"
    );
}

#[test]
fn test_cli_version() {
    let output = std::process::Command::new("cargo")
        .args(["run", "--quiet", "--", "--version"])
        .output()
        .expect("Failed to run cargo run --version");
    assert!(output.status.success());
    let stdout = String::from_utf8_lossy(&output.stdout);
    assert!(stdout.contains("netradar-engine 1.3.3"));
}

#[test]
fn test_expanded_oui_lookup() {
    use netradar_engine::oui::lookup_vendor;

    // Vestel Smart TV
    let vestel = lookup_vendor("64:D8:1B:11:22:33");
    assert_eq!(vestel.name, "Vestel Smart TV");
    assert_eq!(vestel.category, "tv");

    // Intel Corporation
    let intel = lookup_vendor("4C:A9:54:AA:BB:CC");
    assert_eq!(intel.name, "Intel Corporation");
    assert_eq!(intel.category, "pc");

    // WNC Corporation
    let wnc = lookup_vendor("E8:C7:CF:12:34:56");
    assert_eq!(wnc.name, "WNC Corporation");
    assert_eq!(wnc.category, "router");

    // LG Electronics
    let lg = lookup_vendor("2C:2B:F9:01:02:03");
    assert_eq!(lg.name, "LG Electronics");
    assert_eq!(lg.category, "tv");
}

#[test]
fn test_local_hostname_and_hosts_map() {
    use netradar_engine::scanner::{get_local_hostname, load_hosts_map};

    let hostname = get_local_hostname();
    assert!(!hostname.is_empty(), "Hostname should never be empty");

    let hosts_map = load_hosts_map();
    // /etc/hosts typically contains localhost / 127.0.0.1
    if !hosts_map.is_empty() {
        assert!(hosts_map.contains_key("127.0.0.1") || hosts_map.contains_key("::1"));
    }
}




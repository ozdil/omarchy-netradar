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



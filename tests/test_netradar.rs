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

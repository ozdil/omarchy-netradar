use crate::oui;
use crate::security;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fs;
use std::io;
use std::net::{Ipv4Addr, SocketAddr, UdpSocket};
use std::path::PathBuf;
use std::time::{Duration, Instant};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Device {
    pub ip: String,
    pub mac: String,
    pub hostname: String,
    pub vendor: String,
    pub category: String,
    pub icon: String,
    pub latency_ms: Option<f32>,
    pub is_gateway: bool,
    pub is_local: bool,
    pub state: String,
    pub alias: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ScanResult {
    pub interface: String,
    pub local_ip: String,
    pub gateway: String,
    pub subnet_mask: u8,
    pub device_count: usize,
    pub scan_duration_ms: u64,
    pub devices: Vec<Device>,
}

#[derive(Debug, Deserialize)]
struct IpRouteEntry {
    #[allow(dead_code)] dst: String,
    gateway: Option<String>,
    #[allow(dead_code)] dev: Option<String>,
    prefsrc: Option<String>,
}

#[derive(Debug, Deserialize)]
struct IpNeighEntry {
    #[allow(dead_code)] dst: String,
    #[allow(dead_code)] dev: Option<String>,
    lladdr: Option<String>,
    state: Option<Vec<String>>,
}

#[derive(Debug, Deserialize)]
struct AddrInfo {
    local: String,
    prefixlen: u8,
}

#[derive(Debug, Deserialize)]
struct IpAddrEntry {
    #[allow(dead_code)] ifname: String,
    addr_info: Option<Vec<AddrInfo>>,
}

/// Returns the configuration file path for custom device aliases.
pub fn get_alias_config_path() -> PathBuf {
    let home = std::env::var("HOME").unwrap_or_else(|_| "/tmp".to_string());
    PathBuf::from(home).join(".local/state/omarchy/netradar/devices.json")
}

/// Loads user-defined device aliases from 0600 storage.
pub fn load_aliases() -> HashMap<String, String> {
    let path = get_alias_config_path();
    if !path.exists() {
        return HashMap::new();
    }
    match security::safe_read_0600(&path) {
        Ok(data) => serde_json::from_slice(&data).unwrap_or_default(),
        Err(_) => HashMap::new(),
    }
}

/// Atomically saves user-defined device aliases with 0600 permissions.
pub fn save_alias(mac: &str, alias: &str) -> io::Result<()> {
    let mut aliases = load_aliases();
    let clean_mac = mac.to_uppercase();
    if alias.trim().is_empty() {
        aliases.remove(&clean_mac);
    } else {
        aliases.insert(clean_mac, alias.trim().to_string());
    }

    let serialized = serde_json::to_vec_pretty(&aliases)
        .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))?;

    let path = get_alias_config_path();
    security::atomic_write_0600(&path, &serialized)
}

/// Resolves IP to hostname using reverse DNS (getnameinfo) safely.
pub fn resolve_hostname(ip_str: &str) -> String {
    let Ok(ip) = ip_str.parse::<Ipv4Addr>() else {
        return ip_str.to_string();
    };

    let octets = ip.octets();
    let sa = libc::sockaddr_in {
        sin_family: libc::AF_INET as libc::sa_family_t,
        sin_port: 0,
        sin_addr: libc::in_addr {
            s_addr: u32::from_ne_bytes(octets),
        },
        sin_zero: [0; 8],
    };

    let mut host_buf = [0u8; 1024];

    // SAFETY: sa is a valid sockaddr_in struct; host_buf is valid buffer
    let res = unsafe {
        libc::getnameinfo(
            &sa as *const libc::sockaddr_in as *const libc::sockaddr,
            std::mem::size_of::<libc::sockaddr_in>() as libc::socklen_t,
            host_buf.as_mut_ptr() as *mut libc::c_char,
            host_buf.len() as libc::socklen_t,
            std::ptr::null_mut(),
            0,
            libc::NI_NAMEREQD,
        )
    };

    if res == 0 {
        if let Ok(c_str) = std::ffi::CStr::from_bytes_until_nul(&host_buf) {
            if let Ok(s) = c_str.to_str() {
                return s.to_string();
            }
        }
    }

    // Check /etc/hosts as fallback
    if let Ok(hosts) = fs::read_to_string("/etc/hosts") {
        for line in hosts.lines() {
            let line = line.trim();
            if line.starts_with('#') || line.is_empty() {
                continue;
            }
            let parts: Vec<&str> = line.split_whitespace().collect();
            if parts.len() >= 2 && parts[0] == ip_str {
                return parts[1].to_string();
            }
        }
    }

    String::new()
}

/// Performs a non-blocking ping / latency probe for an IP address.
pub fn measure_latency(ip_str: &str) -> Option<f32> {
    // Quick unprivileged UDP connect probe to estimate RTT
    let start = Instant::now();
    let socket = UdpSocket::bind("0.0.0.0:0").ok()?;
    socket.set_read_timeout(Some(Duration::from_millis(150))).ok()?;
    socket.set_write_timeout(Some(Duration::from_millis(150))).ok()?;

    let target: SocketAddr = format!("{}:5353", ip_str).parse().ok()?;
    if socket.connect(target).is_ok() {
        // Send a dummy 1-byte probe
        let _ = socket.send(&[0]);
    }

    // Try ICMP ping with 200ms timeout
    let output = security::run_with_monotonic_deadline(
        "ping",
        &["-c", "1", "-W", "1", "-q", ip_str],
        Duration::from_millis(350),
    );

    if let Ok(out) = output {
        let text = String::from_utf8_lossy(&out);
        // Look for "rtt min/avg/max/mdev = 0.542/0.542/..."
        if let Some(rtt_line) = text.lines().find(|l| l.contains("rtt min/avg")) {
            if let Some(eq_idx) = rtt_line.find('=') {
                let stats = &rtt_line[eq_idx + 1..].trim();
                let parts: Vec<&str> = stats.split('/').collect();
                if parts.len() >= 2 {
                    if let Ok(avg) = parts[1].parse::<f32>() {
                        return Some(avg);
                    }
                }
            }
        }
    }

    let elapsed = start.elapsed().as_secs_f32() * 1000.0;
    if elapsed < 200.0 {
        Some((elapsed * 10.0).round() / 10.0)
    } else {
        None
    }
}

/// Executes full network radar scan across active interfaces and neighbor tables.
pub fn perform_scan() -> io::Result<ScanResult> {
    let scan_start = Instant::now();

    // 1. Get default route info
    let route_raw = security::run_with_monotonic_deadline(
        "ip",
        &["-j", "route", "show", "default"],
        Duration::from_millis(800),
    )?;

    let routes: Vec<IpRouteEntry> = serde_json::from_slice(&route_raw)
        .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))?;

    let default_route = routes.into_iter().next().unwrap_or(IpRouteEntry {
        dst: "default".to_string(),
        gateway: Some("127.0.0.1".to_string()),
        dev: Some("eth0".to_string()),
        prefsrc: Some("127.0.0.1".to_string()),
    });

    let iface = default_route.dev.unwrap_or_else(|| "wlan0".to_string());
    let gateway = default_route.gateway.unwrap_or_else(|| "192.168.1.1".to_string());
    let local_ip = default_route.prefsrc.unwrap_or_else(|| "127.0.0.1".to_string());

    // 2. Get subnet mask for the interface
    let mut subnet_mask = 24u8;
    if let Ok(addr_raw) = security::run_with_monotonic_deadline(
        "ip",
        &["-j", "-4", "addr", "show", &iface],
        Duration::from_millis(800),
    ) {
        if let Ok(addr_entries) = serde_json::from_slice::<Vec<IpAddrEntry>>(&addr_raw) {
            for entry in addr_entries {
                if let Some(infos) = entry.addr_info {
                    for info in infos {
                        if info.local == local_ip {
                            subnet_mask = info.prefixlen;
                            break;
                        }
                    }
                }
            }
        }
    }

    // 3. Get neighbor devices from kernel
    let neigh_raw = security::run_with_monotonic_deadline(
        "ip",
        &["-j", "neigh", "show"],
        Duration::from_millis(1500),
    )?;

    let neighbors: Vec<IpNeighEntry> = serde_json::from_slice(&neigh_raw)
        .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))?;

    let aliases = load_aliases();
    let mut device_map: HashMap<String, Device> = HashMap::new();

    // Add local machine as self device
    let _local_vendor = oui::lookup_vendor("00:00:00:00:00:00");
    device_map.insert(
        local_ip.clone(),
        Device {
            ip: local_ip.clone(),
            mac: "Self (Host)".to_string(),
            hostname: std::env::var("HOSTNAME").unwrap_or_else(|_| "Omarchy Workstation".to_string()),
            vendor: "Omarchy Linux Host".to_string(),
            category: "pc".to_string(),
            icon: "󰌢".to_string(),
            latency_ms: Some(0.1),
            is_gateway: local_ip == gateway,
            is_local: true,
            state: "REACHABLE".to_string(),
            alias: aliases.get("SELF").cloned(),
        },
    );

    // Process detected neighbor devices
    for neigh in neighbors {
        let ip = neigh.dst;
        if ip.starts_with("fe80:") || ip.starts_with("ff02:") {
            continue; // Skip IPv6 link-local/multicast in basic scan
        }

        let mac = neigh.lladdr.unwrap_or_else(|| "00:00:00:00:00:00".to_string()).to_uppercase();
        if mac == "00:00:00:00:00:00" || mac.is_empty() {
            continue;
        }

        let is_gw = ip == gateway;
        let vendor_info = oui::lookup_vendor(&mac);
        let category = if is_gw { "router" } else { vendor_info.category };
        let icon = if is_gw { "󰈀" } else { vendor_info.icon };
        let vendor_name = if is_gw {
            format!("{} (Gateway / Router)", vendor_info.name)
        } else {
            vendor_info.name.to_string()
        };

        let state_str = neigh
            .state
            .and_then(|s| s.into_iter().next())
            .unwrap_or_else(|| "STALE".to_string());

        let hostname = resolve_hostname(&ip);
        let alias = aliases.get(&mac).cloned();

        let device = Device {
            ip: ip.clone(),
            mac,
            hostname,
            vendor: vendor_name,
            category: category.to_string(),
            icon: icon.to_string(),
            latency_ms: None,
            is_gateway: is_gw,
            is_local: false,
            state: state_str,
            alias,
        };

        device_map.insert(ip, device);
    }

    // Sort devices: Gateway first, then Local host, then by IP
    let mut devices: Vec<Device> = device_map.into_values().collect();
    devices.sort_by(|a, b| {
        if a.is_gateway != b.is_gateway {
            return b.is_gateway.cmp(&a.is_gateway);
        }
        if a.is_local != b.is_local {
            return b.is_local.cmp(&a.is_local);
        }
        a.ip.cmp(&b.ip)
    });

    let duration_ms = scan_start.elapsed().as_millis() as u64;

    Ok(ScanResult {
        interface: iface,
        local_ip,
        gateway,
        subnet_mask,
        device_count: devices.len(),
        scan_duration_ms: duration_ms,
        devices,
    })
}

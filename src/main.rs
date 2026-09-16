use std::env;
use std::process;

mod oui;
mod scanner;
mod security;

fn print_usage() {
    println!("NetRadar Engine v1.2.0 - Omarchy Linux Network Scanner & Radar");
    println!("Usage:");
    println!("  netradar-engine [OPTIONS]");
    println!();
    println!("Options:");
    println!("  --scan                 Perform full network scan and output JSON (default)");
    println!("  --ping <ip>            Measure ping latency to target IP");
    println!("  --probe <ip>           Probe common benign services (HTTP, HTTPS, SSH, WebUI) on IP");
    println!("  --set-alias <mac> <alias> Set persistent nickname/alias for a device MAC");
    println!("  --trust <mac>          Mark device MAC as trusted (whitelist)");
    println!("  --untrust <mac>        Remove device MAC from trusted whitelist");
    println!("  --traffic [iface]      Get raw byte counters from /proc/net/dev");
    println!("  --status               Print human-readable single-line network status");
    println!("  --help, -h             Show this help message");
}

fn main() {
    let args: Vec<String> = env::args().collect();

    if args.len() > 1 {
        match args[1].as_str() {
            "--help" | "-h" => {
                print_usage();
                return;
            }
            "--ping" => {
                if args.len() < 3 {
                    eprintln!("Error: Missing IP address for --ping");
                    process::exit(1);
                }
                let ip = &args[2];
                let Ok(parsed_ip) = ip.parse::<std::net::Ipv4Addr>() else {
                    eprintln!("Error: Invalid IPv4 address for --ping");
                    process::exit(1);
                };
                if !security::is_private_or_local_ipv4(parsed_ip) {
                    eprintln!("Error: Target IP must be in private or local subnet");
                    process::exit(1);
                }
                let lat = scanner::measure_latency(ip);
                println!(
                    "{{\"ip\":\"{}\",\"latency_ms\":{}}}",
                    ip,
                    lat.map(|v| v.to_string()).unwrap_or_else(|| "null".to_string())
                );
                return;
            }
            "--probe" => {
                if args.len() < 3 {
                    eprintln!("Error: Missing IP address for --probe");
                    process::exit(1);
                }
                let ip = &args[2];
                let Ok(parsed_ip) = ip.parse::<std::net::Ipv4Addr>() else {
                    eprintln!("Error: Invalid IPv4 address for --probe");
                    process::exit(1);
                };
                if !security::is_private_or_local_ipv4(parsed_ip) {
                    eprintln!("Error: Target IP must be in private or local subnet");
                    process::exit(1);
                }
                let services = scanner::probe_services(ip);
                if let Ok(json) = serde_json::to_string(&services) {
                    println!("{{\"ip\":\"{}\",\"services\":{}}}", ip, json);
                } else {
                    println!("{{\"ip\":\"{}\",\"services\":[]}}", ip);
                }
                return;
            }
            "--set-alias" => {
                if args.len() < 4 {
                    eprintln!("Error: Missing MAC or alias. Usage: --set-alias <mac> <alias>");
                    process::exit(1);
                }
                let mac = &args[2];
                let alias = &args[3];
                if !security::is_valid_mac(mac) {
                    eprintln!("Error: Invalid MAC address format (expected AA:BB:CC:DD:EE:FF)");
                    process::exit(1);
                }
                if !alias.trim().is_empty() && !security::is_valid_alias(alias) {
                    eprintln!("Error: Invalid alias (maximum 64 characters, no control characters)");
                    process::exit(1);
                }
                if let Err(e) = scanner::save_alias(mac, alias) {
                    eprintln!("Failed to save alias: {}", e);
                    process::exit(1);
                }
                println!("{{\"success\":true,\"mac\":\"{}\",\"alias\":\"{}\"}}", mac, alias);
                return;
            }
            "--trust" => {
                if args.len() < 3 {
                    eprintln!("Error: Missing MAC for --trust");
                    process::exit(1);
                }
                let mac = &args[2];
                if !security::is_valid_mac(mac) {
                    eprintln!("Error: Invalid MAC address format");
                    process::exit(1);
                }
                if let Err(e) = scanner::set_trust(mac, true) {
                    eprintln!("Failed to set trust: {}", e);
                    process::exit(1);
                }
                println!("{{\"success\":true,\"mac\":\"{}\",\"is_trusted\":true}}", mac);
                return;
            }
            "--untrust" => {
                if args.len() < 3 {
                    eprintln!("Error: Missing MAC for --untrust");
                    process::exit(1);
                }
                let mac = &args[2];
                if !security::is_valid_mac(mac) {
                    eprintln!("Error: Invalid MAC address format");
                    process::exit(1);
                }
                if let Err(e) = scanner::set_trust(mac, false) {
                    eprintln!("Failed to remove trust: {}", e);
                    process::exit(1);
                }
                println!("{{\"success\":true,\"mac\":\"{}\",\"is_trusted\":false}}", mac);
                return;
            }
            "--traffic" => {
                let iface = args.get(2).map(|s| s.as_str()).unwrap_or("wlo1");
                if !security::is_safe_iface(iface) {
                    eprintln!("Error: Invalid network interface name");
                    process::exit(1);
                }
                let stats = scanner::read_traffic_stats(iface);
                if let Ok(json) = serde_json::to_string(&stats) {
                    println!("{}", json);
                } else {
                    println!("null");
                }
                return;
            }
            "--status" => {
                match scanner::perform_scan(false) {
                    Ok(res) => {
                        let spoof = if res.arp_spoof_warning { " [ARP SPOOFING ALERTI!]" } else { "" };
                        println!(
                            "󰈀 NetRadar: {} devices on {} ({}/{}) • GW: {}{}",
                            res.device_count, res.interface, res.local_ip, res.subnet_mask, res.gateway, spoof
                        );
                    }
                    Err(e) => {
                        eprintln!("Scan error: {}", e);
                        process::exit(1);
                    }
                }
                return;
            }
            "--scan" => {
                // fall through to scan logic
            }
            other => {
                eprintln!("Unknown option: {}", other);
                print_usage();
                process::exit(1);
            }
        }
    }

    match scanner::perform_scan(true) {
        Ok(result) => {
            if let Ok(json) = serde_json::to_string(&result) {
                println!("{}", json);
            } else {
                eprintln!("Failed to serialize scan result");
                process::exit(1);
            }
        }
        Err(e) => {
            eprintln!("{{\"error\":\"{}\"}}", e);
            process::exit(1);
        }
    }
}

use std::env;
use std::process;

mod oui;
mod scanner;
mod security;

fn print_usage() {
    println!("NetRadar Engine v1.0.0 - Omarchy Linux Network Scanner & Radar");
    println!("Usage:");
    println!("  netradar-engine [OPTIONS]");
    println!();
    println!("Options:");
    println!("  --scan                 Perform full network scan and output JSON (default)");
    println!("  --ping <ip>            Measure ping latency to target IP");
    println!("  --set-alias <mac> <alias> Set persistent nickname/alias for a device MAC");
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
                let lat = scanner::measure_latency(ip);
                println!(
                    "{{\"ip\":\"{}\",\"latency_ms\":{}}}",
                    ip,
                    lat.map(|v| v.to_string()).unwrap_or_else(|| "null".to_string())
                );
                return;
            }
            "--set-alias" => {
                if args.len() < 4 {
                    eprintln!("Error: Missing MAC or alias. Usage: --set-alias <mac> <alias>");
                    process::exit(1);
                }
                let mac = &args[2];
                let alias = &args[3];
                if let Err(e) = scanner::save_alias(mac, alias) {
                    eprintln!("Failed to save alias: {}", e);
                    process::exit(1);
                }
                println!("{{\"success\":true,\"mac\":\"{}\",\"alias\":\"{}\"}}", mac, alias);
                return;
            }
            "--status" => {
                match scanner::perform_scan() {
                    Ok(res) => {
                        println!(
                            "󰈀 NetRadar: {} devices on {} ({}/{}) • GW: {}",
                            res.device_count, res.interface, res.local_ip, res.subnet_mask, res.gateway
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

    match scanner::perform_scan() {
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

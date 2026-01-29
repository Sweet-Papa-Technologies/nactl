//! nactl - Network Admin Control CLI for Windows
//!
//! A comprehensive network administration tool for FoFo Lifeline.
//! Provides 11 commands for network diagnostics, Wi-Fi management,
//! DNS configuration, and network stack operations.

use clap::{Parser, Subcommand};
use std::process::ExitCode;

mod commands;
mod errors;
mod utils;

use commands::{dns, ping, proxy, stack, status, trace, wifi};
use errors::ExitCodes;
use utils::output::OutputFormat;

/// Network Admin Control - Windows CLI
#[derive(Parser)]
#[command(name = "nactl")]
#[command(author = "Sweet Papa Technologies LLC")]
#[command(version = "1.0.0")]
#[command(about = "Network administration and diagnostics tool", long_about = None)]
struct Cli {
    #[command(subcommand)]
    command: Commands,

    /// Force JSON output
    #[arg(short = 'j', long, global = true)]
    json: bool,

    /// Pretty-print JSON output
    #[arg(short = 'p', long, global = true)]
    pretty: bool,

    /// Specify network interface (e.g., "Wi-Fi", "Ethernet")
    #[arg(short = 'i', long, global = true)]
    interface: Option<String>,
}

#[derive(Subcommand)]
enum Commands {
    /// Get comprehensive network connection status
    Status,

    /// Test connectivity to a host
    Ping {
        /// Target host to ping
        host: String,

        /// Number of packets to send
        #[arg(short = 'c', long, default_value = "4")]
        count: u32,

        /// Timeout in milliseconds
        #[arg(short = 't', long, default_value = "1000")]
        timeout: u32,
    },

    /// Trace route to destination
    Trace {
        /// Target host to trace
        host: String,

        /// Maximum number of hops
        #[arg(short = 'm', long = "max-hops", default_value = "30")]
        max_hops: u32,

        /// Timeout in milliseconds (0 for no timeout)
        #[arg(short = 't', long, default_value = "60000")]
        timeout: u32,
    },

    /// DNS management commands
    Dns {
        #[command(subcommand)]
        action: DnsCommands,
    },

    /// Network stack operations
    Stack {
        #[command(subcommand)]
        action: StackCommands,
    },

    /// Wi-Fi management commands
    Wifi {
        #[command(subcommand)]
        action: WifiCommands,
    },

    /// Proxy configuration commands
    Proxy {
        #[command(subcommand)]
        action: ProxyCommands,
    },
}

#[derive(Subcommand)]
enum DnsCommands {
    /// Flush DNS resolver cache
    Flush,

    /// Set custom DNS servers
    Set {
        /// Primary DNS server
        primary: String,

        /// Secondary DNS server (optional)
        secondary: Option<String>,
    },

    /// Reset DNS to automatic (DHCP)
    Reset,
}

#[derive(Subcommand)]
enum StackCommands {
    /// Reset network stack
    Reset {
        /// Reset level: soft (default) or hard (requires reboot)
        #[arg(short = 'l', long, default_value = "soft")]
        level: String,
    },
}

#[derive(Subcommand)]
enum WifiCommands {
    /// Scan for available Wi-Fi networks
    Scan,

    /// Remove a saved Wi-Fi network profile
    Forget {
        /// SSID of the network to forget
        ssid: String,
    },
}

#[derive(Subcommand)]
enum ProxyCommands {
    /// Get current proxy configuration
    Get,

    /// Clear all proxy settings
    Clear,
}

fn main() -> ExitCode {
    let cli = Cli::parse();

    // Determine output format
    let format = if cli.json || !atty::is(atty::Stream::Stdout) {
        if cli.pretty {
            OutputFormat::PrettyJson
        } else {
            OutputFormat::Json
        }
    } else if cli.pretty {
        OutputFormat::PrettyJson
    } else {
        OutputFormat::Json // Default to JSON for programmatic use
    };

    let interface = cli.interface.as_deref();

    let result = match cli.command {
        Commands::Status => status::execute(format, interface),

        Commands::Ping {
            host,
            count,
            timeout,
        } => ping::execute(&host, count, timeout, format),

        Commands::Trace {
            host,
            max_hops,
            timeout,
        } => trace::execute(&host, max_hops, timeout, format),

        Commands::Dns { action } => match action {
            DnsCommands::Flush => dns::flush(format),
            DnsCommands::Set { primary, secondary } => {
                dns::set(&primary, secondary.as_deref(), format, interface)
            }
            DnsCommands::Reset => dns::reset(format, interface),
        },

        Commands::Stack { action } => match action {
            StackCommands::Reset { level } => stack::reset(&level, format, interface),
        },

        Commands::Wifi { action } => match action {
            WifiCommands::Scan => wifi::scan(format),
            WifiCommands::Forget { ssid } => wifi::forget(&ssid, format),
        },

        Commands::Proxy { action } => match action {
            ProxyCommands::Get => proxy::get(format),
            ProxyCommands::Clear => proxy::clear(format),
        },
    };

    match result {
        Ok(code) => ExitCode::from(code),
        Err(e) => {
            utils::output::print_error(&e);
            ExitCode::from(e.exit_code as u8)
        }
    }
}

/// Simple TTY detection module
mod atty {
    pub enum Stream {
        Stdout,
    }

    pub fn is(_stream: Stream) -> bool {
        // On Windows, check if stdout is a console
        #[cfg(windows)]
        {
            use windows::Win32::System::Console::{
                GetConsoleMode, GetStdHandle, CONSOLE_MODE, STD_OUTPUT_HANDLE,
            };

            unsafe {
                let handle = GetStdHandle(STD_OUTPUT_HANDLE);
                if let Ok(h) = handle {
                    let mut mode = CONSOLE_MODE::default();
                    GetConsoleMode(h, &mut mode).is_ok()
                } else {
                    false
                }
            }
        }

        #[cfg(not(windows))]
        {
            false
        }
    }
}

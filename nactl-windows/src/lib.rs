//! nactl - Network Admin Control Library
//!
//! This library provides the core functionality for the nactl CLI tool.
//! It can be used as a library for programmatic access to network operations.

pub mod commands;
pub mod errors;
pub mod utils;

pub use errors::{ExitCodes, NactlError};
pub use utils::output::OutputFormat;

//! Output formatting utilities

use crate::errors::NactlError;
use serde::Serialize;

/// Output format for CLI results
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum OutputFormat {
    /// Compact JSON output (default)
    Json,
    /// Pretty-printed JSON output
    PrettyJson,
}

/// Print output in the specified format
pub fn print_output<T: Serialize>(data: &T, format: OutputFormat) -> Result<(), NactlError> {
    let json = match format {
        OutputFormat::Json => serde_json::to_string(data)
            .map_err(|e| NactlError::general_error(format!("JSON serialization failed: {}", e)))?,
        OutputFormat::PrettyJson => serde_json::to_string_pretty(data)
            .map_err(|e| NactlError::general_error(format!("JSON serialization failed: {}", e)))?,
    };

    println!("{}", json);
    Ok(())
}

/// Print error output in JSON format
pub fn print_error(error: &NactlError) {
    let json = serde_json::json!({
        "success": false,
        "error": error.response
    });

    if let Ok(output) = serde_json::to_string(&json) {
        println!("{}", output);
    } else {
        // Fallback for serialization failure
        println!(
            "{{\"success\":false,\"error\":{{\"message\":\"{}\"}}}}",
            error.response.message
        );
    }
}

//! Error types and exit codes for nactl

use serde::Serialize;
use std::fmt;

/// Exit codes per specification
#[repr(u8)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ExitCodes {
    /// Operation completed successfully
    Success = 0,
    /// General error
    GeneralError = 1,
    /// Invalid arguments provided
    InvalidArguments = 2,
    /// Operation requires administrator privileges
    PermissionDenied = 3,
    /// Specified network interface not found
    InterfaceNotFound = 4,
    /// Operation timed out
    Timeout = 5,
    /// Feature not available on this platform
    NotAvailable = 6,
    /// Location services denied (macOS only, included for compatibility)
    LocationDenied = 7,
}

impl From<ExitCodes> for u8 {
    fn from(code: ExitCodes) -> Self {
        code as u8
    }
}

/// Error codes for JSON output
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum ErrorCode {
    GeneralError,
    InvalidArguments,
    PermissionDenied,
    InterfaceNotFound,
    Timeout,
    NotAvailable,
    CommandFailed,
    ParseError,
    NetworkError,
    InvalidInput,
}

/// Structured error for JSON output
#[derive(Debug, Clone, Serialize)]
pub struct ErrorResponse {
    pub code: ErrorCode,
    pub message: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub suggestion: Option<String>,
}

impl ErrorResponse {
    pub fn new(code: ErrorCode, message: impl Into<String>) -> Self {
        Self {
            code,
            message: message.into(),
            suggestion: None,
        }
    }

    pub fn with_suggestion(mut self, suggestion: impl Into<String>) -> Self {
        self.suggestion = Some(suggestion.into());
        self
    }
}

/// Main error type for nactl
#[derive(Debug)]
pub struct NactlError {
    pub exit_code: ExitCodes,
    pub response: ErrorResponse,
}

impl NactlError {
    pub fn new(exit_code: ExitCodes, code: ErrorCode, message: impl Into<String>) -> Self {
        Self {
            exit_code,
            response: ErrorResponse::new(code, message),
        }
    }

    pub fn with_suggestion(mut self, suggestion: impl Into<String>) -> Self {
        self.response.suggestion = Some(suggestion.into());
        self
    }

    pub fn general_error(message: impl Into<String>) -> Self {
        Self::new(ExitCodes::GeneralError, ErrorCode::GeneralError, message)
    }

    pub fn invalid_arguments(message: impl Into<String>) -> Self {
        Self::new(
            ExitCodes::InvalidArguments,
            ErrorCode::InvalidArguments,
            message,
        )
    }

    pub fn permission_denied(message: impl Into<String>) -> Self {
        Self::new(
            ExitCodes::PermissionDenied,
            ErrorCode::PermissionDenied,
            message,
        )
        .with_suggestion("Run with elevated permissions (Administrator)")
    }

    pub fn interface_not_found(interface: &str) -> Self {
        Self::new(
            ExitCodes::InterfaceNotFound,
            ErrorCode::InterfaceNotFound,
            format!("Network interface '{}' not found", interface),
        )
    }

    pub fn timeout(message: impl Into<String>) -> Self {
        Self::new(ExitCodes::Timeout, ErrorCode::Timeout, message)
    }

    pub fn not_available(message: impl Into<String>) -> Self {
        Self::new(ExitCodes::NotAvailable, ErrorCode::NotAvailable, message)
    }

    pub fn command_failed(message: impl Into<String>) -> Self {
        Self::new(ExitCodes::GeneralError, ErrorCode::CommandFailed, message)
    }

    pub fn parse_error(message: impl Into<String>) -> Self {
        Self::new(ExitCodes::GeneralError, ErrorCode::ParseError, message)
    }

    pub fn invalid_input(message: impl Into<String>) -> Self {
        Self::new(
            ExitCodes::InvalidArguments,
            ErrorCode::InvalidInput,
            message,
        )
    }
}

impl fmt::Display for NactlError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match serde_json::to_string(&serde_json::json!({
            "success": false,
            "error": self.response
        })) {
            Ok(json) => write!(f, "{}", json),
            Err(_) => write!(
                f,
                "{{\"success\":false,\"error\":{{\"message\":\"{}\"}}}}",
                self.response.message
            ),
        }
    }
}

impl std::error::Error for NactlError {}

/// Result type alias for nactl operations
pub type NactlResult<T> = Result<T, NactlError>;

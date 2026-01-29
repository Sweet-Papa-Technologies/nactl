//! Windows Registry operations for proxy settings

use crate::errors::NactlError;

#[cfg(windows)]
use winreg::enums::*;
#[cfg(windows)]
use winreg::RegKey;

const INTERNET_SETTINGS_PATH: &str = r"Software\Microsoft\Windows\CurrentVersion\Internet Settings";

/// Get proxy enabled status from registry
pub fn get_proxy_enabled() -> Result<bool, NactlError> {
    #[cfg(windows)]
    {
        let hkcu = RegKey::predef(HKEY_CURRENT_USER);
        let settings = hkcu
            .open_subkey(INTERNET_SETTINGS_PATH)
            .map_err(|e| NactlError::general_error(format!("Failed to open registry: {}", e)))?;

        let enabled: u32 = settings.get_value("ProxyEnable").unwrap_or(0);
        Ok(enabled != 0)
    }

    #[cfg(not(windows))]
    {
        Ok(false)
    }
}

/// Get proxy server string from registry
pub fn get_proxy_server() -> Result<Option<String>, NactlError> {
    #[cfg(windows)]
    {
        let hkcu = RegKey::predef(HKEY_CURRENT_USER);
        let settings = hkcu
            .open_subkey(INTERNET_SETTINGS_PATH)
            .map_err(|e| NactlError::general_error(format!("Failed to open registry: {}", e)))?;

        match settings.get_value::<String, _>("ProxyServer") {
            Ok(server) if !server.is_empty() => Ok(Some(server)),
            _ => Ok(None),
        }
    }

    #[cfg(not(windows))]
    {
        Ok(None)
    }
}

/// Get proxy override (bypass) list from registry
pub fn get_proxy_override() -> Result<Option<String>, NactlError> {
    #[cfg(windows)]
    {
        let hkcu = RegKey::predef(HKEY_CURRENT_USER);
        let settings = hkcu
            .open_subkey(INTERNET_SETTINGS_PATH)
            .map_err(|e| NactlError::general_error(format!("Failed to open registry: {}", e)))?;

        match settings.get_value::<String, _>("ProxyOverride") {
            Ok(override_list) if !override_list.is_empty() => Ok(Some(override_list)),
            _ => Ok(None),
        }
    }

    #[cfg(not(windows))]
    {
        Ok(None)
    }
}

/// Get auto-config URL from registry
pub fn get_auto_config_url() -> Result<Option<String>, NactlError> {
    #[cfg(windows)]
    {
        let hkcu = RegKey::predef(HKEY_CURRENT_USER);
        let settings = hkcu
            .open_subkey(INTERNET_SETTINGS_PATH)
            .map_err(|e| NactlError::general_error(format!("Failed to open registry: {}", e)))?;

        match settings.get_value::<String, _>("AutoConfigURL") {
            Ok(url) if !url.is_empty() => Ok(Some(url)),
            _ => Ok(None),
        }
    }

    #[cfg(not(windows))]
    {
        Ok(None)
    }
}

/// Set proxy enabled status
pub fn set_proxy_enabled(enabled: bool) -> Result<(), NactlError> {
    #[cfg(windows)]
    {
        let hkcu = RegKey::predef(HKEY_CURRENT_USER);
        let settings = hkcu
            .open_subkey_with_flags(INTERNET_SETTINGS_PATH, KEY_WRITE)
            .map_err(|e| NactlError::general_error(format!("Failed to open registry: {}", e)))?;

        let value: u32 = if enabled { 1 } else { 0 };
        settings
            .set_value("ProxyEnable", &value)
            .map_err(|e| NactlError::general_error(format!("Failed to write registry: {}", e)))?;

        // Notify the system of the change
        notify_internet_settings_change();

        Ok(())
    }

    #[cfg(not(windows))]
    {
        let _ = enabled;
        Ok(())
    }
}

/// Clear proxy server setting
pub fn clear_proxy_server() -> Result<(), NactlError> {
    #[cfg(windows)]
    {
        let hkcu = RegKey::predef(HKEY_CURRENT_USER);
        let settings = hkcu
            .open_subkey_with_flags(INTERNET_SETTINGS_PATH, KEY_WRITE)
            .map_err(|e| NactlError::general_error(format!("Failed to open registry: {}", e)))?;

        // Set to empty string instead of deleting (safer)
        let _ = settings.set_value("ProxyServer", &"");

        notify_internet_settings_change();
        Ok(())
    }

    #[cfg(not(windows))]
    {
        Ok(())
    }
}

/// Clear auto-config URL setting
pub fn clear_auto_config_url() -> Result<(), NactlError> {
    #[cfg(windows)]
    {
        let hkcu = RegKey::predef(HKEY_CURRENT_USER);
        let settings = hkcu
            .open_subkey_with_flags(INTERNET_SETTINGS_PATH, KEY_WRITE)
            .map_err(|e| NactlError::general_error(format!("Failed to open registry: {}", e)))?;

        let _ = settings.set_value("AutoConfigURL", &"");

        notify_internet_settings_change();
        Ok(())
    }

    #[cfg(not(windows))]
    {
        Ok(())
    }
}

/// Notify the system that Internet settings have changed
#[cfg(windows)]
fn notify_internet_settings_change() {
    use std::ptr;

    // Use InternetSetOption to notify of change
    // This requires calling wininet.dll
    // For simplicity, we'll skip this as registry changes are usually picked up

    // Alternative: broadcast WM_SETTINGCHANGE
    #[allow(non_snake_case)]
    unsafe {
        use windows::Win32::Foundation::HWND;
        use windows::Win32::UI::WindowsAndMessaging::{
            SendMessageTimeoutW, HWND_BROADCAST, SMTO_ABORTIFHUNG, WM_SETTINGCHANGE,
        };

        let _ = SendMessageTimeoutW(
            HWND_BROADCAST,
            WM_SETTINGCHANGE,
            windows::Win32::Foundation::WPARAM(0),
            windows::Win32::Foundation::LPARAM(ptr::null::<i32>() as isize),
            SMTO_ABORTIFHUNG,
            1000,
            None,
        );
    }
}

#[cfg(not(windows))]
fn notify_internet_settings_change() {}

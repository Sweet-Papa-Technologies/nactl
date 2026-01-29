//! Administrator privilege detection

/// Check if the current process is running with elevated (administrator) privileges
pub fn is_elevated() -> bool {
    #[cfg(windows)]
    {
        use std::mem;
        use std::ptr;
        use windows::Win32::Foundation::{CloseHandle, HANDLE};
        use windows::Win32::Security::{
            GetTokenInformation, TokenElevation, TOKEN_ELEVATION, TOKEN_QUERY,
        };
        use windows::Win32::System::Threading::{GetCurrentProcess, OpenProcessToken};

        unsafe {
            let mut token_handle = HANDLE::default();
            let process = GetCurrentProcess();

            if OpenProcessToken(process, TOKEN_QUERY, &mut token_handle).is_err() {
                return false;
            }

            let mut elevation = TOKEN_ELEVATION::default();
            let mut size = mem::size_of::<TOKEN_ELEVATION>() as u32;

            let result = GetTokenInformation(
                token_handle,
                TokenElevation,
                Some(&mut elevation as *mut _ as *mut _),
                size,
                &mut size,
            );

            let _ = CloseHandle(token_handle);

            result.is_ok() && elevation.TokenIsElevated != 0
        }
    }

    #[cfg(not(windows))]
    {
        // On non-Windows, check if running as root
        unsafe { libc::geteuid() == 0 }
    }
}

/// Get a message suggesting how to run as administrator
pub fn elevation_suggestion() -> &'static str {
    "Run this command from an elevated Command Prompt or PowerShell (Run as Administrator)"
}

@echo off
REM nactl Windows Test Script (Batch)
REM Runs safe commands automatically, echoes disruptive commands for manual testing

setlocal enabledelayedexpansion

set NACTL=target\debug\nactl.exe

REM Check if binary exists
if not exist "%NACTL%" (
    echo Error: nactl binary not found at %NACTL%
    echo Build first with: cargo build
    echo Or edit this script to set NACTL path
    exit /b 1
)

echo ========================================
echo   nactl Windows Test Suite
echo ========================================
echo.
echo Binary: %NACTL%
echo.

set PASSED=0
set FAILED=0

echo --- SAFE TESTS (Automatic) ---
echo.

REM Version and help
call :run_test "Version" "--version"
call :run_test "Help" "--help"

REM Status command
call :run_test "Status" "status"
call :run_test "Status (JSON)" "status --json"

REM Ping command
call :run_test "Ping google.com" "ping google.com --count 2"
call :run_test "Ping localhost" "ping 127.0.0.1 --count 1"

REM Trace command
call :run_test "Trace (short)" "trace google.com --max-hops 3"
call :run_test "Trace (with timeout)" "trace google.com --max-hops 3 --timeout 15000"

REM Wi-Fi scan
call :run_test "Wi-Fi Scan" "wifi scan"

REM Proxy get
call :run_test "Proxy Get" "proxy get"

echo.
echo --- DISRUPTIVE TESTS (Manual) ---
echo These commands may temporarily disrupt network connectivity.
echo Run manually as Administrator when ready.
echo.

echo Manual Test: DNS Flush
echo   NOTE: Clears DNS cache - safe but better with admin
echo   Command: %NACTL% dns flush
echo.

echo Manual Test: DNS Set Custom
echo   NOTE: Changes DNS servers - will affect name resolution
echo   Command: %NACTL% dns set 1.1.1.1 1.0.0.1
echo.

echo Manual Test: DNS Reset
echo   NOTE: Resets DNS to DHCP
echo   Command: %NACTL% dns reset
echo.

echo Manual Test: Wi-Fi Forget
echo   NOTE: Removes saved network - replace TestNetwork with actual SSID
echo   Command: %NACTL% wifi forget "TestNetwork"
echo.

echo Manual Test: Stack Reset (Soft)
echo   NOTE: Restarts network adapter - temporary connectivity loss
echo   Command: %NACTL% stack reset --level soft
echo.

echo Manual Test: Stack Reset (Hard)
echo   NOTE: Resets TCP/IP and Winsock - REQUIRES REBOOT
echo   Command: %NACTL% stack reset --level hard
echo.

echo Manual Test: Proxy Clear
echo   NOTE: Clears all proxy settings
echo   Command: %NACTL% proxy clear
echo.

echo ========================================
echo   Test Summary
echo ========================================
echo   Passed: %PASSED%
echo   Failed: %FAILED%
echo.

if %FAILED% EQU 0 (
    echo All automatic tests passed!
    exit /b 0
) else (
    echo Some tests failed. Check output above.
    exit /b 1
)

:run_test
set "test_name=%~1"
set "test_args=%~2"
echo Test: %test_name%
echo   Command: %NACTL% %test_args%
%NACTL% %test_args% > nul 2>&1
if %errorlevel% EQU 0 (
    echo   Result: PASSED
    set /a PASSED+=1
) else (
    echo   Result: FAILED (exit code: %errorlevel%)
    set /a FAILED+=1
)
echo.
exit /b 0

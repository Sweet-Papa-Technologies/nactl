# nactl Windows Test Script (PowerShell)
# Runs safe commands automatically, echoes disruptive commands for manual testing

param(
    [string]$NactlPath = ".\target\debug\nactl.exe"
)

# Colors
$Green = "Green"
$Red = "Red"
$Yellow = "Yellow"
$Blue = "Cyan"

# Check if binary exists
if (-not (Test-Path $NactlPath)) {
    Write-Host "Error: nactl binary not found at $NactlPath" -ForegroundColor $Red
    Write-Host "Build first with: cargo build"
    Write-Host "Or specify path: .\test_nactl.ps1 -NactlPath 'path\to\nactl.exe'"
    exit 1
}

Write-Host "========================================" -ForegroundColor $Blue
Write-Host "  nactl Windows Test Suite" -ForegroundColor $Blue
Write-Host "========================================" -ForegroundColor $Blue
Write-Host ""
Write-Host "Binary: $NactlPath" -ForegroundColor $Green
Write-Host ""

# Track test results
$script:Passed = 0
$script:Failed = 0

function Run-Test {
    param(
        [string]$Name,
        [string]$Args
    )

    Write-Host "Test: $Name" -ForegroundColor $Yellow
    Write-Host "  Command: $NactlPath $Args"

    try {
        $output = & $NactlPath $Args.Split(" ") 2>&1
        $exitCode = $LASTEXITCODE

        if ($exitCode -eq 0) {
            Write-Host "  Result: PASSED" -ForegroundColor $Green
            $script:Passed++
        } else {
            Write-Host "  Result: FAILED (exit code: $exitCode)" -ForegroundColor $Red
            $script:Failed++
        }
    } catch {
        Write-Host "  Result: FAILED (exception: $_)" -ForegroundColor $Red
        $script:Failed++
    }
    Write-Host ""
}

function Run-TestWithOutput {
    param(
        [string]$Name,
        [string]$Args
    )

    Write-Host "Test: $Name" -ForegroundColor $Yellow
    Write-Host "  Command: $NactlPath $Args"
    Write-Host "  Output:"

    try {
        $output = & $NactlPath $Args.Split(" ") 2>&1
        $exitCode = $LASTEXITCODE

        $output | ForEach-Object { Write-Host "    $_" }

        if ($exitCode -eq 0) {
            Write-Host "  Result: PASSED" -ForegroundColor $Green
            $script:Passed++
        } else {
            Write-Host "  Result: FAILED (exit code: $exitCode)" -ForegroundColor $Red
            $script:Failed++
        }
    } catch {
        Write-Host "  Result: FAILED (exception: $_)" -ForegroundColor $Red
        $script:Failed++
    }
    Write-Host ""
}

function Echo-ManualTest {
    param(
        [string]$Name,
        [string]$Args,
        [string]$Note
    )

    Write-Host "Manual Test: $Name" -ForegroundColor $Yellow
    Write-Host "  NOTE: $Note" -ForegroundColor $Red
    Write-Host "  Command to run (as Admin): $NactlPath $Args" -ForegroundColor $Green
    Write-Host ""
}

# ============================================
# SAFE TESTS - Run automatically
# ============================================

Write-Host "--- SAFE TESTS (Automatic) ---" -ForegroundColor $Blue
Write-Host ""

# Version and help
Run-Test "Version" "--version"
Run-Test "Help" "--help"

# Status command
Run-Test "Status (human)" "status"
Run-Test "Status (JSON)" "status --json"
Run-Test "Status (pretty JSON)" "status --json --pretty"

# Ping command
Run-Test "Ping google.com" "ping google.com --count 2"
Run-Test "Ping (JSON)" "ping 8.8.8.8 --count 2 --json"
Run-Test "Ping localhost" "ping 127.0.0.1 --count 1"

# Trace command (limited hops for speed)
Run-Test "Trace (short)" "trace google.com --max-hops 3"
Run-Test "Trace (JSON)" "trace 8.8.8.8 --max-hops 3 --json"

# Wi-Fi scan
Run-Test "Wi-Fi Scan" "wifi scan"
Run-Test "Wi-Fi Scan (JSON)" "wifi scan --json"

# Proxy get
Run-Test "Proxy Get" "proxy get"
Run-Test "Proxy Get (JSON)" "proxy get --json"

# DNS subcommands help
Run-Test "DNS Help" "dns --help"
Run-Test "Stack Help" "stack --help"
Run-Test "Wi-Fi Help" "wifi --help"
Run-Test "Proxy Help" "proxy --help"

# ============================================
# DISRUPTIVE TESTS - Echo for manual execution
# ============================================

Write-Host "--- DISRUPTIVE TESTS (Manual) ---" -ForegroundColor $Blue
Write-Host "These commands may temporarily disrupt network connectivity." -ForegroundColor $Red
Write-Host "Run manually as Administrator when ready." -ForegroundColor $Red
Write-Host ""

Echo-ManualTest "DNS Flush" "dns flush" "Clears DNS cache - safe but better with admin"
Echo-ManualTest "DNS Set Custom" "dns set 1.1.1.1 1.0.0.1" "Changes DNS servers - will affect name resolution"
Echo-ManualTest "DNS Reset" "dns reset" "Resets DNS to DHCP - run after DNS Set test"
Echo-ManualTest "Wi-Fi Forget" "wifi forget 'TestNetwork'" "Removes saved network - replace 'TestNetwork' with actual SSID"
Echo-ManualTest "Stack Reset (Soft)" "stack reset --level soft" "Restarts network adapter - temporary connectivity loss"
Echo-ManualTest "Stack Reset (Hard)" "stack reset --level hard" "Resets TCP/IP and Winsock - REQUIRES REBOOT"
Echo-ManualTest "Proxy Clear" "proxy clear" "Clears all proxy settings - only if proxies are configured"

# ============================================
# JSON Output Validation
# ============================================

Write-Host "--- JSON OUTPUT VALIDATION ---" -ForegroundColor $Blue
Write-Host ""

Write-Host "Test: Validate JSON output structure" -ForegroundColor $Yellow
try {
    $jsonOutput = & $NactlPath status --json 2>&1
    $parsed = $jsonOutput | ConvertFrom-Json

    if ($parsed.PSObject.Properties.Name -contains "success") {
        Write-Host "  JSON structure: VALID" -ForegroundColor $Green
        $script:Passed++
    } else {
        Write-Host "  JSON structure: INVALID (missing 'success' field)" -ForegroundColor $Red
        $script:Failed++
    }
} catch {
    Write-Host "  JSON structure: INVALID (parse error: $_)" -ForegroundColor $Red
    $script:Failed++
}
Write-Host ""

# ============================================
# Summary
# ============================================

Write-Host "========================================" -ForegroundColor $Blue
Write-Host "  Test Summary" -ForegroundColor $Blue
Write-Host "========================================" -ForegroundColor $Blue
Write-Host "  Passed: $($script:Passed)" -ForegroundColor $Green
Write-Host "  Failed: $($script:Failed)" -ForegroundColor $Red
Write-Host ""

if ($script:Failed -eq 0) {
    Write-Host "All automatic tests passed!" -ForegroundColor $Green
    exit 0
} else {
    Write-Host "Some tests failed. Check output above." -ForegroundColor $Red
    exit 1
}

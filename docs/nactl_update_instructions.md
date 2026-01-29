# nactl Update Instructions: Graceful Location Services Handling

## Context

macOS requires Location Services permission for WiFi scanning operations (listing nearby networks, getting SSID/BSSID, signal strength). Our `nactl` CLI tool cannot obtain this permission because:

1. CLI tools/daemons cannot appear in System Preferences > Location Services
2. Apple has deliberately blocked this path for background services
3. There is no workaround — this is an intentional Apple privacy restriction

**We are intentionally deferring full WiFi scanning support.** The goal now is to make `nactl` behave gracefully when Location Services is unavailable, using fallbacks where possible.

---

## Required Changes

### 1. Remove Location Services Prompting

**Current behavior (REMOVE):**
- Opening System Preferences to Location Services pane
- Prompting user to enable location for the app
- Any UI or user-facing guidance about enabling Location Services

**Why:** Opening the System Preferences pane is useless — the user won't find `nactl` or `fofo-agent` listed there because CLI tools/daemons don't appear in Location Services settings. This creates confusion.

**Find and remove:**
- Any calls to `open "x-apple.systempreferences:..."` or similar URL schemes
- Any calls to launch System Preferences/System Settings
- Any user-facing messages about enabling Location Services
- Any prompts asking the user to grant location permission

### 2. Implement Silent Logging for Permission State

**New behavior:**
When WiFi operations detect that Location Services permission is unavailable, the tool should:

1. Log at DEBUG or INFO level (not ERROR/WARNING) that permission is unavailable
2. Treat this as **expected behavior**, not an error condition
3. Proceed with fallback methods without user notification

**Example log messages (adjust to match existing logging style):**

```
[DEBUG] Location Services unavailable for WiFi operations - using fallback methods
[DEBUG] WiFi SSID access restricted - falling back to system_profiler
[INFO] Running in limited WiFi mode (Location Services not available)
```

**Do NOT log:**
- Error-level messages about missing permissions
- Warnings that suggest something is broken
- Messages that tell the user to enable anything

### 3. Implement Fallback Methods for WiFi Data

For each WiFi operation, implement fallbacks that work WITHOUT Location Services:

#### 3.1 Get Current Network SSID

**Primary method (requires Location Services):** CoreWLAN `ssid()` method

**Fallback method (use this):**
```bash
system_profiler SPAirPortDataType | awk '/Current Network/ {getline;$1=$1;print;exit}'
```

Or using PlistBuddy for more reliable parsing:
```bash
/usr/libexec/PlistBuddy -c 'Print :0:_items:0:spairport_airport_interfaces:0:spairport_current_network_information:_name' /dev/stdin <<< "$(system_profiler SPAirPortDataType -xml)"
```

**Expected result:** Returns current SSID or empty string if not connected

#### 3.2 Get WiFi Interface Status (Power On/Off)

**This should work without Location Services:**
- CoreWLAN `powerOn()` method typically works
- Fallback: `networksetup -getairportpower en0`

#### 3.3 Get IP Configuration

**This works without Location Services:**
- Standard network APIs
- `ifconfig en0`
- `ipconfig getifaddr en0`

#### 3.4 WiFi Scan (List Nearby Networks)

**Primary method (requires Location Services):** CoreWLAN `scanForNetworks()`

**Fallback behavior:**
- Return an empty array/list
- Set a flag or field indicating "scan unavailable"
- Do NOT return an error — this is expected

**Example response structure:**
```json
{
  "success": true,
  "scan_available": false,
  "networks": [],
  "message": "WiFi network scanning requires Location Services (not available)"
}
```

#### 3.5 Get Signal Strength (RSSI)

**Primary method (requires Location Services):** CoreWLAN `rssiValue()`

**Fallback behavior:**
- Return null/nil for RSSI
- Optionally try: `system_profiler SPAirPortDataType` may include signal info
- If unavailable, return null — do not fake a value

#### 3.6 Get BSSID (Access Point MAC)

**Primary method (requires Location Services):** CoreWLAN `bssid()`

**Fallback behavior:**
- Return null/nil
- This data is simply unavailable without Location Services

---

## Implementation Guidelines

### Error Handling Philosophy

```
BEFORE (wrong):
  if !hasLocationPermission {
      logError("Location Services required!")
      openSystemPreferences()
      return Error("Permission denied")
  }

AFTER (correct):
  if !hasLocationPermission {
      logDebug("Location Services unavailable - using fallbacks")
      return getFallbackData()
  }
```

### Response Structure

Ensure WiFi-related commands return a consistent structure that indicates capability:

```json
{
  "success": true,
  "interface": "en0",
  "power": true,
  "ssid": "MyNetwork",        // from fallback - may work
  "bssid": null,              // unavailable without permission
  "rssi": null,               // unavailable without permission  
  "scan_available": false,    // indicates scanning won't work
  "networks": [],             // empty when scan unavailable
  "limited_mode": true,       // flag indicating reduced functionality
  "limited_reason": "Location Services not available for CLI tools"
}
```

### Testing Checklist

After changes, verify:

- [ ] `nactl wifi status` returns current SSID (via fallback) without errors
- [ ] `nactl wifi status` does NOT open System Preferences
- [ ] `nactl wifi status` does NOT print warnings about permissions to stdout
- [ ] `nactl wifi scan` returns empty results gracefully (not an error)
- [ ] `nactl wifi power` correctly reports on/off state
- [ ] Log output (when verbose) shows debug-level permission messages only
- [ ] No user-facing prompts or dialogs appear

---

## Files Likely Needing Changes

Based on typical Rust/Swift CLI structure (adjust to actual codebase):

1. **WiFi module/handler** - Main logic for WiFi operations
2. **Permission checking code** - Remove or modify permission validation
3. **System Preferences launcher** - Remove entirely
4. **Error types/handling** - Change permission errors to fallback triggers
5. **Response serialization** - Add `limited_mode` / `scan_available` fields

---

## Summary

| Operation | Before | After |
|-----------|--------|-------|
| Missing Location permission | Error + open System Prefs | Silent log + use fallback |
| Get SSID | Fail if no permission | Use system_profiler fallback |
| WiFi scan | Fail if no permission | Return empty array, `scan_available: false` |
| Get RSSI/BSSID | Fail if no permission | Return null values |
| User messaging | "Please enable Location Services" | Nothing — silent operation |

The goal is **graceful degradation**: provide what we can, clearly indicate what's unavailable in the response structure, and never bother the user with prompts they can't act on.

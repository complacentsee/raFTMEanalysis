# RSLinxHook Monitor Mode Stress Test - 20 cycles, --monitor flag
#
# CONFIGURATION: edit the variables below for your testbench before running.
#
# $TARGET_IP    - IP of the primary Ethernet device to browse to
# $DRIVER_NAME  - RSLinx driver name (case-insensitive match)
# $QUERIES      - Ordered hashtable of query path -> expected result substring.
#                 Keys use $TARGET_IP so only the block below needs updating.
#
# Expected result format: "FOUND|<classname>" or "NOTFOUND"
# Backplane paths: "$TARGET_IP\Backplane\<slot>"
#
# PURPOSE: Validates the --monitor code path across N runs. Monitor mode skips
# DoEngineHotLoad and node-table/harmony-file changes, browsing the existing
# driver in-place. A full cold-start setup populates the node table first so
# the driver is present when monitor mode runs. Verify via hook_log.txt that
# no "hot-load" lines appear during the monitor-mode cycles.

# ---- TESTBENCH CONFIGURATION ----
$TARGET_IPS  = @("192.0.2.1", "192.0.2.2")   # replace with your device IPs
$DRIVER_NAME = "MyDriver"                    # replace with your RSLinx driver name

$QUERIES = [ordered]@{
    "192.0.2.1"               = "FOUND|<ip1-classname>"
    "192.0.2.1\Backplane\0"   = "FOUND|<ip1-slot0-classname>"
    "192.0.2.1\Backplane\1"   = "FOUND|<ip1-slot1-classname>"
    "192.0.2.1\Backplane\2"   = "FOUND|<ip1-slot2-classname>"
    "192.0.2.1\Backplane\3"   = "FOUND|<ip1-slot3-classname>"
    "192.0.2.1\Backplane\99"  = "NOTFOUND"
    "192.0.2.2"               = "FOUND|<ip2-classname>"
    "192.0.2.2\Backplane\0"   = "FOUND|<ip2-slot0-classname>"
    "192.0.2.2\Backplane\1"   = "FOUND|<ip2-slot1-classname>"
    "192.0.2.2\Backplane\2"   = "FOUND|<ip2-slot2-classname>"
    "192.0.2.2\Backplane\3"   = "FOUND|<ip2-slot3-classname>"
    "192.0.2.2\Backplane\99"  = "NOTFOUND"
}
# ---- END CONFIGURATION ----

$CYCLES      = 20
$BROWSE_EXE  = Join-Path $PSScriptRoot "RSLinxBrowse\Release\RSLinxBrowse.exe"
$HARMONY_HRC = "C:\Program Files (x86)\Rockwell Software\RSCommon\Harmony.hrc"
$HARMONY_RSH = "C:\Program Files (x86)\Rockwell Software\RSCommon\Harmony.rsh"
$NODE_TABLE  = "HKLM:\SOFTWARE\WOW6432Node\Rockwell Software\RSLinx\Drivers\AB_ETH\AB_ETH-1\Node Table"
$LOGDIR      = "C:\temp"
$LOGFILE     = "C:\temp\stress_monitor_results.txt"
$SVC_NAME    = "RSLinx"   # RSLinx Classic service name

$totalPass = 0
$totalFail = 0

function Log($msg) {
    $ts   = Get-Date -Format "HH:mm:ss"
    $line = "[$ts] $msg"
    Write-Host $line
    Add-Content $LOGFILE $line
}

function DeleteIfExists($path) {
    if (Test-Path $path) {
        Remove-Item $path -Force -ErrorAction SilentlyContinue
        if (Test-Path $path) { Log "      WARN: could not delete $path" }
        else                  { Log "      Deleted: $path" }
    } else {
        Log "      (not present): $path"
    }
}

function ClearNodeTable($regPath) {
    if (Test-Path $regPath) {
        $vals = Get-ItemProperty $regPath -ErrorAction SilentlyContinue
        $vals.PSObject.Properties |
            Where-Object { $_.Name -notmatch '^PS' } |
            ForEach-Object {
                Remove-ItemProperty -Path $regPath -Name $_.Name -Force -ErrorAction SilentlyContinue
            }
        Log "      Node Table cleared: $regPath"
    } else {
        Log "      (Node Table not present): $regPath"
    }
}

function ShowProgress($cycle, $cycles, $pass, $fail) {
    $done     = $pass + $fail
    $cyclePct = [int](100.0 * $cycle / $cycles)
    $passRate = if ($done -gt 0) { "$([math]::Round(100.0 * $pass / $done, 1))%" } else { "n/a" }
    $filled   = [int]($cyclePct / 5)
    $bar      = "[" + ("#" * $filled).PadRight(20, '-') + "]"
    $color    = if ($fail -eq 0) { "Green" } else { "Yellow" }
    $ts       = Get-Date -Format "HH:mm:ss"
    $line     = "[$ts]   $bar $cyclePct%  Cycle $cycle/$cycles  Pass=$pass  Fail=$fail  SuccessRate=$passRate"
    Write-Host $line -ForegroundColor $color
    Add-Content $LOGFILE $line
}

# Snapshot keys/values into plain arrays once so the loop never touches $QUERIES
# NOTE: do NOT use $expected or $EXPECTED as a loop variable — PS names are
# case-insensitive and would overwrite this hashtable.
$qPaths   = @($QUERIES.Keys)
$qExpects = @($QUERIES.Values)

# Clear log
if (Test-Path $LOGFILE) { Remove-Item $LOGFILE -Force }
Log "=== RSLinxHook Monitor Mode Stress Test: $CYCLES cycles, $($qPaths.Count) checks each ==="
Log "Target: $($TARGET_IPS -join ', ')  Driver: $DRIVER_NAME  Service: $SVC_NAME"
Log ""

# ---- ONE-TIME SETUP: full cold start + inject browse to populate node table ----
Log "============================================================"
Log "SETUP: Cold start RSLinx and inject browse to populate node table"
Log "       (required so --monitor can find the driver without writing)"
Log "============================================================"

Log "  [setup-1] Stopping RSLinx service..."
Stop-Service -Name $SVC_NAME -Force -ErrorAction SilentlyContinue
$svc = Get-Service -Name $SVC_NAME
if ($svc.Status -ne "Stopped") {
    Log "      WARN: service still $($svc.Status) after Stop-Service, waiting 5s..."
    Start-Sleep -Seconds 5
}
Stop-Process -Name "RSOBSERV" -Force -ErrorAction SilentlyContinue
Log "      Service stopped."

Log "  [setup-2] Removing harmony files and clearing node table..."
DeleteIfExists $HARMONY_HRC
DeleteIfExists $HARMONY_RSH
ClearNodeTable $NODE_TABLE

Log "  [setup-3] Starting RSLinx service..."
Start-Service -Name $SVC_NAME -ErrorAction SilentlyContinue
$svc = Get-Service -Name $SVC_NAME
if ($svc.Status -ne "Running") {
    Log "FATAL: Service failed to start ($($svc.Status)) -- cannot run test"
    exit 1
}
Start-Sleep -Seconds 8
$rslinxProc = Get-Process -Name "RSLinx" -ErrorAction SilentlyContinue
Log "      Service running, PID: $($rslinxProc.Id)"

Log "  [setup-4] Running initial inject browse (populates node table for monitor mode)..."
$t0        = Get-Date
$ipArgs    = $TARGET_IPS | ForEach-Object { "--ip"; $_ }
$browseOut = & $BROWSE_EXE --driver $DRIVER_NAME @ipArgs --logdir $LOGDIR 2>&1
$browseS   = [int]((Get-Date) - $t0).TotalSeconds
$browseOk  = $browseOut | Where-Object { $_ -match 'Browse complete' }
$devLine   = ($browseOut | Where-Object { $_ -match 'DEVICES_IDENTIFIED' } | Select-Object -First 1) -replace '^\s+',''

if ($browseOk -and $LASTEXITCODE -eq 0) {
    Log "      Initial browse OK in ${browseS}s -- $devLine"
} else {
    $tail = ($browseOut | Select-Object -Last 4) -join " | "
    Log "FATAL: Initial browse FAILED after ${browseS}s (exit=$LASTEXITCODE): $tail"
    exit 1
}
Log ""

# ---- MAIN LOOP: monitor mode against the same running RSLinx process ----
for ($cycle = 1; $cycle -le $CYCLES; $cycle++) {
    Log "------------------------------------------------------------"
    Log "CYCLE $cycle / $CYCLES   (running total: $totalPass pass, $totalFail fail)"
    Log "------------------------------------------------------------"

    # --- Step 1: Verify RSLinx is still running ---
    Log "  [1] Verifying RSLinx is still running..."
    $svc = Get-Service -Name $SVC_NAME -ErrorAction SilentlyContinue
    if (-not $svc -or $svc.Status -ne "Running") {
        Log "  ABORT: RSLinx service is no longer running ($($svc.Status)) -- monitor-mode COM path may have caused a crash"
        $totalFail += $qPaths.Count
        ShowProgress $cycle $CYCLES $totalPass $totalFail
        break
    }
    $rslinxProc = Get-Process -Name "RSLinx" -ErrorAction SilentlyContinue
    Log "      RSLinx running, PID: $($rslinxProc.Id)"

    # --- Step 2: Monitor-mode browse (skips DoEngineHotLoad and node-table writes) ---
    Log "  [2] Running --monitor browse (no node-table or harmony-file changes)..."
    $t0        = Get-Date
    $ipArgs    = $TARGET_IPS | ForEach-Object { "--ip"; $_ }
    $browseOut = & $BROWSE_EXE --monitor --driver $DRIVER_NAME @ipArgs --logdir $LOGDIR 2>&1
    $browseS   = [int]((Get-Date) - $t0).TotalSeconds
    $browseOk  = $browseOut | Where-Object { $_ -match 'Browse complete' }
    $devLine   = ($browseOut | Where-Object { $_ -match 'DEVICES_IDENTIFIED' } | Select-Object -First 1) -replace '^\s+',''

    $browseExitCode = $LASTEXITCODE
    if ($browseOk -and $browseExitCode -eq 0) {
        Log "      Browse OK in ${browseS}s -- $devLine"
    } else {
        $tail = ($browseOut | Select-Object -Last 4) -join " | "
        Log "      Browse FAILED after ${browseS}s (exit=$browseExitCode): $tail"
        if (Test-Path "C:\temp\hook_log.txt") {
            $hookTail = Get-Content "C:\temp\hook_log.txt" -Tail 15
            Log "      HOOK LOG (last 15 lines):"
            $hookTail | ForEach-Object { Log "        | $_" }
        }
        $totalFail += $qPaths.Count
        ShowProgress $cycle $CYCLES $totalPass $totalFail
        continue
    }

    # --- Step 3: Run queries ---
    Log "  [3] Querying ($($qPaths.Count) checks)..."
    $cycleOk = $true

    for ($qi = 0; $qi -lt $qPaths.Count; $qi++) {
        $qPath   = $qPaths[$qi]
        $qExpect = $qExpects[$qi]

        $qOutFile = "C:\temp\query_diag.txt"
        $proc = Start-Process -FilePath $BROWSE_EXE `
            -ArgumentList "--query", $qPath, "--logdir", $LOGDIR `
            -RedirectStandardOutput $qOutFile `
            -RedirectStandardError  "C:\temp\query_diag_err.txt" `
            -NoNewWindow -Wait -PassThru
        $qOutRaw = if (Test-Path $qOutFile) { Get-Content $qOutFile -Raw } else { "" }
        $qErrRaw = if (Test-Path "C:\temp\query_diag_err.txt") { Get-Content "C:\temp\query_diag_err.txt" -Raw } else { "" }
        $result  = (($qOutRaw -split "`n") | Where-Object { $_ -match '^\[FOUND\]|^\[NOTFOUND\]' } | Select-Object -First 1) -replace '\r',''

        if ($result -and ($result -match [regex]::Escape($qExpect))) {
            Log "      PASS  $qPath  =>  $result"
            $totalPass++
        } else {
            $got = if ($result) { $result } else { "(no output)" }
            Log "      FAIL  $qPath  want: $qExpect  got: $got  exit=$($proc.ExitCode)"
            Log "        STDOUT: $($qOutRaw -replace '\r?\n',' | ')"
            Log "        STDERR: $($qErrRaw -replace '\r?\n',' | ')"
            $totalFail++
            $cycleOk = $false
        }
    }

    $status = if ($cycleOk) { "PASSED" } else { "FAILED" }
    Log "  => Cycle $cycle $status"
    ShowProgress $cycle $CYCLES $totalPass $totalFail
    Log ""
}

# --- Final summary ---
$total  = $totalPass + $totalFail
$pctStr = if ($total -gt 0) { "$([math]::Round(100.0 * $totalFail / $total, 1))" + "%" } else { "n/a" }
Log "============================================================"
Log "MONITOR MODE STRESS TEST COMPLETE: $CYCLES cycles, $total total checks"
Log "  PASS: $totalPass"
Log "  FAIL: $totalFail  ($pctStr failure rate)"
if ($totalFail -eq 0) {
    Log "  RESULT: ALL PASS"
} else {
    Log "  RESULT: FAILURES DETECTED -- review log above"
}
Log "  NOTE: verify C:\temp\hook_log.txt contains no 'hot-load' lines (monitor must skip DoEngineHotLoad)"
Log "  Log: $LOGFILE"
Log "============================================================"

Clear-Host

$TESTS = @(
    @{ Name = "Kill/Clear/Start"; Script = "stress_test.ps1";     Log = "C:\temp\stress_results.txt" }
    @{ Name = "Hook Reuse";       Script = "stress_rebrowse.ps1"; Log = "C:\temp\stress_rebrowse_results.txt" }
    @{ Name = "Monitor Mode";     Script = "stress_monitor.ps1";  Log = "C:\temp\stress_monitor_results.txt" }
)

$summary = @()
$grandStart = Get-Date

Write-Host ""
Write-Host "############################################################" -ForegroundColor Cyan
Write-Host "  RSLinxHook Master Stress Test  ($($TESTS.Count) suites)" -ForegroundColor Cyan
Write-Host "############################################################" -ForegroundColor Cyan
Write-Host ""

foreach ($t in $TESTS) {
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "  SUITE: $($t.Name)  ($($t.Script))" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan

    $t0 = Get-Date
    & (Join-Path $PSScriptRoot $t.Script)
    $elapsed = [int]((Get-Date) - $t0).TotalSeconds

    # Parse log for pass/fail/result
    $pass = 0; $fail = 0; $result = "NO LOG"
    if (Test-Path $t.Log) {
        $log = Get-Content $t.Log -Raw
        if ($log -match 'PASS:\s*(\d+)')   { $pass   = [int]$Matches[1] }
        if ($log -match 'FAIL:\s*(\d+)')   { $fail   = [int]$Matches[1] }
        if ($log -match 'RESULT:\s*(.+)')  { $result = $Matches[1].Trim() }
    }

    $summary += [PSCustomObject]@{
        Name    = $t.Name
        Pass    = $pass
        Fail    = $fail
        Result  = $result
        Elapsed = $elapsed
    }

    Write-Host ""
}

# Grand summary
$totalPass = ($summary | Measure-Object -Property Pass -Sum).Sum
$totalFail = ($summary | Measure-Object -Property Fail -Sum).Sum
$grandTotal = $totalPass + $totalFail
$pct        = if ($grandTotal -gt 0) { "$([math]::Round(100.0 * $totalFail / $grandTotal, 1))%" } else { "n/a" }
$totalSec   = [int]((Get-Date) - $grandStart).TotalSeconds

Write-Host "############################################################" -ForegroundColor Cyan
Write-Host "  MASTER SUMMARY" -ForegroundColor Cyan
Write-Host "############################################################" -ForegroundColor Cyan

foreach ($s in $summary) {
    $color = if ($s.Fail -eq 0) { "Green" } else { "Red" }
    Write-Host ("  {0,-20} Pass={1,-5} Fail={2,-5} {3,6}s  {4}" -f `
        $s.Name, $s.Pass, $s.Fail, $s.Elapsed, $s.Result) -ForegroundColor $color
}

Write-Host ""
$overallColor = if ($totalFail -eq 0) { "Green" } else { "Red" }
Write-Host ("  GRAND TOTAL   Pass={0,-5} Fail={1,-5} ({2} fail rate)  Total time: {3}s" -f `
    $totalPass, $totalFail, $pct, $totalSec) -ForegroundColor $overallColor

if ($totalFail -eq 0) {
    Write-Host "  OVERALL RESULT: ALL PASS" -ForegroundColor Green
} else {
    Write-Host "  OVERALL RESULT: FAILURES DETECTED" -ForegroundColor Red
}
Write-Host ""

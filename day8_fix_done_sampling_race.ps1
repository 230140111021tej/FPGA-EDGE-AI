$ErrorActionPreference = "Stop"

$root = "D:\FPGA_EdgeAI\cnn_baseline"
$vivado = "D:\vivado\2025.1\Vivado\bin"
$tb = Join-Path $root "tb\tb_cnn_integrated_validation.v"
$status = Join-Path $root "cnn_rtl_run_status.txt"
$scores = Join-Path $root "cnn_rtl_final_scores.txt"
$log = Join-Path $root "day8_done_race_fix.log"
$comparator = Join-Path $root "scripts\compare_cnn_final.py"

Set-Location $root
if (!(Test-Path $tb)) { throw "Missing testbench: $tb" }

# Fix the race: sample done after nonblocking assignments have updated.
$src = Get-Content $tb -Raw
$old = 'while(!done && cycles<2000000) begin @(posedge clk);cycles=cycles+1;end'
$new = 'while(done !== 1''b1 && cycles<2000000) begin @(posedge clk); #1; cycles=cycles+1; end'
if ($src.Contains($old)) {
    $src = $src.Replace($old, $new)
    Set-Content -Path $tb -Value $src -Encoding ascii
    Write-Host "Patched testbench polling to sample done 1 ns after each rising edge." -ForegroundColor Green
} elseif ($src.Contains('while(done !== 1''b1 && cycles<2000000) begin @(posedge clk); #1; cycles=cycles+1; end')) {
    Write-Host "Done-sampling race fix is already present." -ForegroundColor Yellow
} else {
    Select-String -Path $tb -Pattern 'while|done|cycles' | ForEach-Object { $_.ToString() }
    throw "Expected wait loop not found. No simulation run."
}

Remove-Item $status, $scores, $log -Force -ErrorAction SilentlyContinue

$xvlog = Join-Path $vivado "xvlog.bat"
$xelab = Join-Path $vivado "xelab.bat"
$xsim = Join-Path $vivado "xsim.bat"
foreach ($tool in @($xvlog,$xelab,$xsim)) {
    if (!(Test-Path $tool)) { throw "Vivado simulation tool not found: $tool" }
}

# Exclude backup RTL that declares a duplicate conv1_full_layer module.
$rtlFiles = Get-ChildItem (Join-Path $root "rtl") -Filter "*.v" |
    Where-Object { $_.Name -ne "conv1_full_layer_valid_backup.v" } |
    Sort-Object FullName | ForEach-Object { $_.FullName }

Write-Host "`nCompiling RTL and testbench (excluding duplicate backup module)..." -ForegroundColor Cyan
& $xvlog -sv -work xil_defaultlib @rtlFiles $tb 2>&1 | Tee-Object -FilePath $log
if ($LASTEXITCODE -ne 0) { throw "xvlog failed. See $log" }

Write-Host "`nElaborating..." -ForegroundColor Cyan
& $xelab xil_defaultlib.tb_cnn_integrated_validation -s cnn_done_race_fix_sim 2>&1 | Tee-Object -FilePath $log -Append
if ($LASTEXITCODE -ne 0) { throw "xelab failed. See $log" }

Write-Host "`nRunning XSim..." -ForegroundColor Cyan
& $xsim cnn_done_race_fix_sim -runall 2>&1 | Tee-Object -FilePath $log -Append

if (!(Test-Path $status)) {
    Write-Host "FAIL: status file was not created. Do not trust scores." -ForegroundColor Red
    exit 2
}
$statusText = (Get-Content $status -Raw).Trim()
Write-Host "`nSimulation status: $statusText"
if ($statusText -ne "PASS") {
    Write-Host "Integration remains unverified. See $log" -ForegroundColor Red
    exit 3
}
if (!(Test-Path $scores)) { throw "PASS status but no score file exists." }

Write-Host "`nFresh final scores:" -ForegroundColor Cyan
Get-Content $scores

if (Test-Path $comparator) {
    Write-Host "`nComparing fresh RTL scores against Python reference..." -ForegroundColor Cyan
    & python $comparator 2>&1 | Tee-Object -FilePath $log -Append
    if ($LASTEXITCODE -ne 0) { throw "Python score comparison failed. See $log" }
} else {
    Write-Warning "Comparator not found at $comparator. Simulation completed, but Python score comparison was not run."
}
Write-Host "`nReview all comparison output before declaring end-to-end validation complete." -ForegroundColor Yellow
Write-Host "Log: $log"

$ErrorActionPreference = "Stop"
$root = "D:\FPGA_EdgeAI\cnn_baseline"
$vivado = "D:\vivado\2025.1\Vivado\bin"
$topPath = Join-Path $root "rtl\cnn_integrated_sim_top.v"
$tbPath = Join-Path $root "tb\tb_cnn_integrated_validation.v"
$log = Join-Path $root "day8_stage_diagnostic.log"
Set-Location $root

if (!(Test-Path $topPath) -or !(Test-Path $tbPath)) { throw "Missing Day 8 top or testbench." }
$top = Get-Content $topPath -Raw
$tb = Get-Content $tbPath -Raw

Write-Host "`n--- Current controller and module interfaces ---" -ForegroundColor Cyan
Write-Host "Top-level state/done/valid declarations and controller snippets:"
Select-String -Path $topPath -Pattern 'phase|state|done|valid|count|always|case|start|pool|input_map' -Context 1,1 |
  ForEach-Object { $_.ToString() } | Select-Object -First 120
Write-Host "`nTestbench:"
Get-Content $tbPath | ForEach-Object -Begin { $n=1 } -Process { "{0,4}: {1}" -f $n++, $_ } | Write-Host

# Do not guess state encodings or rewrite the controller automatically. First compile
# without the backup duplicate module, then report the real source structure.
Write-Host "`n--- Checking duplicate module definitions ---" -ForegroundColor Cyan
$defs = Select-String -Path (Join-Path $root "rtl\*.v") -Pattern '^\s*module\s+conv1_full_layer\b'
$defs | ForEach-Object { Write-Host ("{0}:{1}: {2}" -f $_.Path, $_.LineNumber, $_.Line.Trim()) }
if ($defs.Count -gt 1) {
    Write-Warning "Duplicate module definitions exist. This diagnostic run excludes conv1_full_layer_valid_backup.v."
}

$xvlog = Join-Path $vivado "xvlog.bat"
$xelab = Join-Path $vivado "xelab.bat"
$xsim = Join-Path $vivado "xsim.bat"
Remove-Item $log -Force -ErrorAction SilentlyContinue
$rtlFiles = Get-ChildItem (Join-Path $root "rtl") -Filter "*.v" |
  Where-Object { $_.Name -ne "conv1_full_layer_valid_backup.v" } |
  Sort-Object FullName | ForEach-Object { $_.FullName }

Write-Host "`nCompiling without backup module..." -ForegroundColor Cyan
& $xvlog -sv -work xil_defaultlib @rtlFiles $tbPath 2>&1 | Tee-Object -FilePath $log
if ($LASTEXITCODE -ne 0) { throw "xvlog failed. See $log" }
& $xelab xil_defaultlib.tb_cnn_integrated_validation -s cnn_stage_diag_sim 2>&1 | Tee-Object -FilePath $log -Append
if ($LASTEXITCODE -ne 0) { throw "xelab failed. See $log" }

Write-Host "`nThis pass is a clean compile/elaboration check, not a functional pass." -ForegroundColor Yellow
Write-Host "Diagnostic log: $log"
Write-Host "`nUse the printed source to identify the actual state register and done signals; no unverified score comparison is run."

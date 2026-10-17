$ErrorActionPreference = "Stop"
$root = "D:\FPGA_EdgeAI\cnn_baseline"
Set-Location $root

$scriptPath = Join-Path $root "day8_integrated_cnn_simulation.ps1"
if (!(Test-Path $scriptPath)) { throw "Cannot find $scriptPath" }

$text = Get-Content $scriptPath -Raw
$old = "out_valid(c1_act_valid),.out_data(c1_act)"
$new = "out_valid(c1_act_valid),.out_activation(c1_act)"
if ($text.Contains($old)) {
    $text = $text.Replace($old, $new)
    Set-Content $scriptPath $text -Encoding ascii
    Write-Host "Patched Conv1 requantizer port: out_data -> out_activation." -ForegroundColor Green
} elseif ($text.Contains($new)) {
    Write-Host "Conv1 requantizer port already patched." -ForegroundColor Yellow
} else {
    throw "Could not locate the expected Conv1 requantizer port mapping in day8_integrated_cnn_simulation.ps1. No other files were changed."
}

Write-Host "Rerunning Day 8 integration script..." -ForegroundColor Cyan
& powershell -ExecutionPolicy Bypass -File $scriptPath
if ($LASTEXITCODE -ne 0) { throw "Day 8 integration still failed; send the complete new output." }

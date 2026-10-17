$ErrorActionPreference = "Stop"
$Root = "D:\FPGA_EdgeAI\cnn_baseline"
$Hw = Join-Path $Root "rtl\fc2_full_layer_hw.v"
$Orig = Join-Path $Root "rtl\fc2_full_layer.v"

if (-not (Test-Path $Hw)) { throw "Missing new FC2 module: $Hw" }
if (-not (Test-Path $Orig)) { throw "Missing original FC2 module: $Orig" }

$originalBefore = (Get-FileHash -LiteralPath $Orig -Algorithm SHA256).Hash
$text = Get-Content -Raw -LiteralPath $Hw

if ($text -match '(?m)^\s*module\s+fc2_full_layer_hw\b') {
    Write-Host "Module declaration is already correct; no changes needed." -ForegroundColor Green
    exit 0
}

if ($text -notmatch '(?m)^\s*module\s+fc2_full_layer\b') {
    throw "Expected module declaration 'module fc2_full_layer' not found. No changes made."
}

$text = [regex]::Replace(
    $text,
    '(?m)^(\s*module\s+)fc2_full_layer\b',
    '${1}fc2_full_layer_hw',
    1
)

if ($text -notmatch '(?m)^\s*module\s+fc2_full_layer_hw\b') {
    throw "Rename verification failed. No file written."
}

Set-Content -LiteralPath $Hw -Value $text -Encoding ASCII
$originalAfter = (Get-FileHash -LiteralPath $Orig -Algorithm SHA256).Hash
if ($originalBefore -ne $originalAfter) {
    throw "Safety check failed: original RTL hash changed unexpectedly."
}

Write-Host "Fixed module declaration in rtl\fc2_full_layer_hw.v." -ForegroundColor Green
Write-Host "Original rtl\fc2_full_layer.v remains unchanged."
Write-Host ""
Write-Host "Now rerun:"
Write-Host ".\day10_validate_fc2_hw.ps1"

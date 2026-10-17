$ErrorActionPreference = "Stop"
$root = "D:\FPGA_EdgeAI\cnn_baseline"
Set-Location $root

Write-Host "DAY 9 PREFLIGHT: locate image-selection and reference-generation code" -ForegroundColor Cyan
Write-Host "This script is read-only: it does not edit RTL, Python files, or ROMs." -ForegroundColor Yellow

$dirs = @(
    (Join-Path $root "scripts"),
    (Join-Path $root "tb"),
    (Join-Path $root "rtl")
)
$patterns = @(
    'MNIST',
    'test_dataset',
    'dataset\[',
    'image_index',
    'sample_index',
    'test_idx',
    'index\s*=\s*0',
    'dataset\[[0-9]+\]',
    'conv1_image_u8_hex',
    'cnn_rtl_final_scores',
    'compare_cnn_final',
    'generate_conv2_reference',
    'prepare_fc1_reference',
    'prepare_fc2_reference'
)

foreach ($dir in $dirs) {
    if (!(Test-Path $dir)) { continue }
    Write-Host "`n--- $dir ---" -ForegroundColor Cyan
    Get-ChildItem $dir -File -Recurse |
        Where-Object { $_.Extension -in @(".py", ".ps1", ".v", ".sv") } |
        Select-String -Pattern $patterns -Context 1,1 |
        ForEach-Object {
            "{0}:{1}: {2}" -f $_.Path, $_.LineNumber, $_.Line.Trim()
        }
}

Write-Host "`n--- Key file presence ---" -ForegroundColor Cyan
$check = @(
    "day8_integrated_cnn_simulation.ps1",
    "day8_fix_conv1_requant_port.ps1",
    "day8_fix_done_sampling_race.ps1",
    "rtl\cnn_integrated_sim_top.v",
    "tb\tb_cnn_integrated_validation.v",
    "scripts\compare_cnn_final.py",
    "rom\conv1_image_u8_hex.mem",
    "rom\conv1_image_info.txt"
)
foreach ($rel in $check) {
    $full = Join-Path $root $rel
    "{0,-48} {1}" -f $rel, (Test-Path $full) | Write-Host
}

Write-Host "`nPaste this output back. I will use the actual generator and image-index locations to produce the batch validator without guessing or overwriting the working Day 8 files." -ForegroundColor Green

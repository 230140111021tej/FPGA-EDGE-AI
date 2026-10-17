$ErrorActionPreference = "Stop"
$root = "D:\FPGA_EdgeAI\cnn_baseline"
Set-Location $root

$files = @(
    "scripts\export_real_mnist_image.py",
    "scripts\generate_conv2_reference.py",
    "scripts\prepare_fc1_reference.py",
    "scripts\prepare_fc2_reference.py",
    "scripts\compare_cnn_final.py",
    "day8_integrated_cnn_simulation.ps1",
    "day8_fix_done_sampling_race.ps1",
    "rtl\cnn_integrated_sim_top.v",
    "rtl\conv1_full_layer.v",
    "rtl\conv2_full_layer.v",
    "rtl\fc1_full_layer.v",
    "rtl\fc2_full_layer.v"
)

foreach ($rel in $files) {
    $path = Join-Path $root $rel
    Write-Host "`n========== $rel ==========" -ForegroundColor Cyan
    if (Test-Path $path) {
        $line = 1
        Get-Content $path | ForEach-Object {
            "{0,4}: {1}" -f $line, $_
            $line++
        }
    } else {
        Write-Host "MISSING"
    }
}

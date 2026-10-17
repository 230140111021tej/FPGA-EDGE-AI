$ErrorActionPreference = "Stop"
$Root = "D:\FPGA_EdgeAI\cnn_baseline"
Set-Location $Root
$Out = Join-Path $Root "day10_synthesizable_preflight.txt"
$Log = New-Object System.Collections.Generic.List[string]

function Add-FileSection([string]$Relative) {
    $Path = Join-Path $Root $Relative
    $Log.Add("")
    $Log.Add(("=" * 80))
    $Log.Add("FILE: $Relative")
    $Log.Add(("=" * 80))
    if (-not (Test-Path $Path)) {
        $Log.Add("MISSING")
        return
    }
    $Lines = Get-Content -LiteralPath $Path
    for ($i=0; $i -lt $Lines.Count; $i++) {
        $Log.Add(("{0,4}: {1}" -f ($i+1), $Lines[$i]))
    }
}

$Log.Add("DAY 10 SYNTHESIZABLE CNN PREFLIGHT")
$Log.Add("Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
$Log.Add("READ ONLY: no RTL, ROM, or project files are modified.")
Add-FileSection "rtl\fc2_full_layer.v"
Add-FileSection "rtl\cnn_integrated_sim_top.v"
Add-FileSection "rtl\fc2_shared_mac.v"

$Log.Add("")
$Log.Add(("=" * 80))
$Log.Add("ROM / parameter files used by the layer modules")
$Log.Add(("=" * 80))
$RomFiles = @(
 "rom\conv1_image_u8_hex.mem",
 "rom\conv1_weights_int8_hex.mem",
 "rom\conv1_bias_int32_hex.mem",
 "rom\conv2_pool1_input_hex.mem",
 "rom\conv2_weights_int8_hex.mem",
 "rom\conv2_bias_int32_hex.mem",
 "rom\fc1_pool2_input_hex.mem",
 "rom\fc1_weights_int8_hex.mem",
 "rom\fc1_bias_int32_hex.mem",
 "rom\fc2_input_hex.mem",
 "rom\fc2_weights_int8_hex.mem",
 "rom\fc2_bias_int32_hex.mem"
)
foreach ($r in $RomFiles) {
    $path = Join-Path $Root $r
    if (Test-Path $path) {
        $item = Get-Item $path
        $lines = (Get-Content -LiteralPath $path | Measure-Object -Line).Lines
        $Log.Add(("{0} | bytes={1} | lines={2}" -f $r, $item.Length, $lines))
    } else {
        $Log.Add("$r | MISSING")
    }
}

$Log.Add("")
$Log.Add(("=" * 80))
$Log.Add("Vivado availability")
$Log.Add(("=" * 80))
$Vivado = "D:\vivado\2025.1\Vivado\bin\vivado.bat"
if (Test-Path $Vivado) {
    $Log.Add("Vivado executable found: $Vivado")
    $Log.Add("This preflight does not launch synthesis.")
} else {
    $Log.Add("Vivado executable not found at expected path: $Vivado")
}

$Log | Set-Content -LiteralPath $Out -Encoding UTF8
Write-Host "Preflight complete. No files were modified." -ForegroundColor Green
Write-Host "Report: $Out"
Write-Host "Please attach this report before we change the RTL."

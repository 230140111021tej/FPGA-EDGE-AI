$ErrorActionPreference = "Stop"
$Root = "D:\FPGA_EdgeAI\cnn_baseline"
Set-Location $Root

$Source = Join-Path $Root "rtl\fc2_full_layer.v"
$NewFile = Join-Path $Root "rtl\fc2_full_layer_hw.v"
$LogFile = Join-Path $Root "day10_fc2_hw_interface.log"

if (-not (Test-Path $Source)) { throw "Missing source RTL: $Source" }
if (Test-Path $NewFile) { throw "Refusing to overwrite existing file: $NewFile" }

$src = Get-Content -Raw -LiteralPath $Source
$nl = [Environment]::NewLine

$oldParam = ' parameter BIAS_FILE="rom/fc2_bias_int32_hex.mem"'
$newParam = ' parameter BIAS_FILE="rom/fc2_bias_int32_hex.mem",' + $nl + ' parameter LOAD_INPUT_ROM=1'
if (-not $src.Contains($oldParam)) { throw "Could not find FC2 BIAS_FILE parameter line." }
$src = $src.Replace($oldParam, $newParam)

$oldPorts = ' input wire clk,input wire rst,input wire start,'
$newPorts = ' input wire clk,input wire rst,input wire start,' + $nl +
            ' input wire input_we, input wire [5:0] input_addr, input wire [7:0] input_data,'
if (-not $src.Contains($oldPorts)) { throw "Could not find FC2 port declaration." }
$src = $src.Replace($oldPorts, $newPorts)

$oldRead = '  $readmemh(INPUT_FILE,input_map);'
$newRead = '  if (LOAD_INPUT_ROM != 0) $readmemh(INPUT_FILE,input_map);'
if (-not $src.Contains($oldRead)) { throw "Could not find FC2 input ROM initialization." }
$src = $src.Replace($oldRead, $newRead)

$oldAlways = '   done<=0;out_valid<=0;mac_start<=0;'
$newAlways = $oldAlways + $nl + '   if (input_we) input_map[input_addr] <= input_data;'
if (-not $src.Contains($oldAlways)) { throw "Could not find FC2 control block insertion point." }
$src = $src.Replace($oldAlways, $newAlways)

if ($src -notmatch 'input_we' -or $src -notmatch 'LOAD_INPUT_ROM' -or $src -notmatch 'input_map\[input_addr\]') {
    throw "Patch verification failed. No new RTL was written."
}
Set-Content -LiteralPath $NewFile -Value $src -Encoding ASCII

$log = @"
DAY 10 FC2 HARDWARE INTERFACE
Created: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Original preserved: rtl\fc2_full_layer.v
New module: rtl\fc2_full_layer_hw.v

Added:
- input_we: input activation write enable
- input_addr: 6-bit address for 64 activation entries
- input_data: 8-bit activation value
- LOAD_INPUT_ROM parameter: set to 0 when input activations are supplied through the write interface

This is an interface-only RTL variant. It does not change the original FC2 arithmetic or MAC.
Do not integrate it into cnn_integrated_sim_top.v yet.
Next validation should compile this module, then use a proper testbench driver to load 64 activation values and compare all 10 scores against the original FC2 module.
"@
Set-Content -LiteralPath $LogFile -Value $log -Encoding UTF8

Write-Host "Created separate FC2 hardware-interface module." -ForegroundColor Green
Write-Host "Original rtl\fc2_full_layer.v was not modified."
Write-Host "New module: $NewFile"
Write-Host "Log: $LogFile"
Write-Host "Next step: compile and validate with a reference-driven testbench before integration."

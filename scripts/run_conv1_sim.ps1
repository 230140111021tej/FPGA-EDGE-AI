$ErrorActionPreference = "Stop"
Set-Location "D:\FPGA_EdgeAI\cnn_baseline"
if (!(Test-Path "rom\conv1_image_u8_hex.mem")) {
  $vals = for ($i=0; $i -lt 784; $i++) { "{0:X2}" -f (($i*7+13)%256) }
  Set-Content "rom\conv1_image_u8_hex.mem" $vals -Encoding ascii
  Write-Host "Created deterministic placeholder image. Replace with a real quantized MNIST image for model validation."
}
if (!(Get-Command iverilog -ErrorAction SilentlyContinue)) {
  throw "iverilog not found. Run the testbench in Vivado xsim, or install Icarus Verilog."
}
New-Item -ItemType Directory -Force build | Out-Null
iverilog -g2012 -s tb_conv1_full_layer -o build\conv1_full_layer.vvp rtl\conv1_shared_mac.v rtl\conv1_full_layer.v tb\tb_conv1_full_layer.v
if ($LASTEXITCODE -ne 0) { throw "Compile failed" }
vvp build\conv1_full_layer.vvp
if ($LASTEXITCODE -ne 0) { throw "Simulation failed" }

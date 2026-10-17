$ErrorActionPreference = "Stop"
$Root = "D:\FPGA_EdgeAI\cnn_baseline"
$VivadoBin = "D:\vivado\2025.1\Vivado\bin"
Set-Location $Root

$Hw = Join-Path $Root "rtl\fc2_full_layer_hw.v"
$Orig = Join-Path $Root "rtl\fc2_full_layer.v"
$Mac = Join-Path $Root "rtl\fc2_shared_mac.v"
$InputRom = Join-Path $Root "rom\fc2_fc1_input_hex.mem"
$Tb = Join-Path $Root "tb\tb_fc2_hw_compare.v"
$Log = Join-Path $Root "day10_fc2_hw_compare.log"

foreach ($f in @($Hw,$Orig,$Mac,$InputRom)) {
    if (-not (Test-Path $f)) { throw "Required file missing: $f" }
}
foreach ($tool in @("xvlog.bat","xelab.bat","xsim.bat")) {
    if (-not (Test-Path (Join-Path $VivadoBin $tool))) { throw "Vivado tool missing: $tool" }
}

$tbText = @'
`timescale 1ns/1ps
module tb_fc2_hw_compare;
 reg clk=0, rst=1, start=0, input_we=0;
 reg [5:0] input_addr=0;
 reg [7:0] input_data=0;
 wire orig_busy,orig_done,orig_valid;
 wire [3:0] orig_addr;
 wire signed [31:0] orig_score;
 wire hw_busy,hw_done,hw_valid;
 wire [3:0] hw_addr;
 wire signed [31:0] hw_score;
 reg [7:0] test_input [0:63];
 reg signed [31:0] orig_scores [0:9];
 reg signed [31:0] hw_scores [0:9];
 reg orig_seen [0:9];
 reg hw_seen [0:9];
 integer i, cycles, errors;
 always #5 clk=~clk;

 initial begin
  $readmemh("rom/fc2_fc1_input_hex.mem",test_input);
 end

 fc2_full_layer original (
  .clk(clk),.rst(rst),.start(start),.busy(orig_busy),.done(orig_done),
  .out_addr(orig_addr),.out_score(orig_score),.out_valid(orig_valid)
 );

 fc2_full_layer_hw #(.LOAD_INPUT_ROM(0)) hardware_interface (
  .clk(clk),.rst(rst),.start(start),.input_we(input_we),
  .input_addr(input_addr),.input_data(input_data),
  .busy(hw_busy),.done(hw_done),.out_addr(hw_addr),
  .out_score(hw_score),.out_valid(hw_valid)
 );

 always @(posedge clk) begin
  if (orig_valid) begin orig_scores[orig_addr] <= orig_score; orig_seen[orig_addr] <= 1'b1; end
  if (hw_valid) begin hw_scores[hw_addr] <= hw_score; hw_seen[hw_addr] <= 1'b1; end
 end

 initial begin
  errors=0;
  for(i=0;i<10;i=i+1) begin orig_scores[i]=0;hw_scores[i]=0;orig_seen[i]=0;hw_seen[i]=0;end
  repeat(4) @(negedge clk);
  rst=0;

  // Load all 64 activation bytes into the new module using its public write port.
  for(i=0;i<64;i=i+1) begin
   @(negedge clk);
   input_we=1;
   input_addr=i;
   input_data=test_input[i];
  end
  @(negedge clk);
  input_we=0;

  // Start both modules on the same clock interval.
  start=1;
  @(negedge clk);
  start=0;

  cycles=0;
  while((orig_done!==1'b1 || hw_done!==1'b1) && cycles<10000) begin
   @(posedge clk); #1; cycles=cycles+1;
  end
  if(orig_done!==1'b1 || hw_done!==1'b1) begin
   $display("FAIL: timeout original_done=%b hw_done=%b cycles=%0d",orig_done,hw_done,cycles);
   $fatal(1);
  end
  repeat(2) @(negedge clk);
  for(i=0;i<10;i=i+1) begin
   if(!orig_seen[i] || !hw_seen[i]) begin
    $display("FAIL: missing score index %0d orig_seen=%b hw_seen=%b",i,orig_seen[i],hw_seen[i]);
    errors=errors+1;
   end else if(orig_scores[i] !== hw_scores[i]) begin
    $display("MISMATCH class=%0d original=%0d hw=%0d",i,orig_scores[i],hw_scores[i]);
    errors=errors+1;
   end else begin
    $display("PASS class=%0d score=%0d",i,hw_scores[i]);
   end
  end
  if(errors==0) begin
   $display("DAY10_FC2_HW_INTERFACE_PASS cycles=%0d",cycles);
   $finish;
  end else begin
   $display("DAY10_FC2_HW_INTERFACE_FAIL mismatches=%0d",errors);
   $fatal(1);
  end
 end
endmodule
'@
Set-Content -LiteralPath $Tb -Value $tbText -Encoding ASCII

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("DAY 10 FC2 HW INTERFACE COMPARISON")
$lines.Add("Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
$lines.Add("Original module: rtl\fc2_full_layer.v")
$lines.Add("New module: rtl\fc2_full_layer_hw.v")
$lines.Add("Testbench: tb\tb_fc2_hw_compare.v")
$lines.Add("")
try {
    Push-Location $Root
    & (Join-Path $VivadoBin "xvlog.bat") "rtl\fc2_shared_mac.v" "rtl\fc2_full_layer.v" "rtl\fc2_full_layer_hw.v" "tb\tb_fc2_hw_compare.v" 2>&1 | ForEach-Object { $lines.Add([string]$_); Write-Host $_ }
    if ($LASTEXITCODE -ne 0) { throw "xvlog failed with exit code $LASTEXITCODE" }
    & (Join-Path $VivadoBin "xelab.bat") "tb_fc2_hw_compare" "-s" "day10_fc2_hw_compare_snapshot" 2>&1 | ForEach-Object { $lines.Add([string]$_); Write-Host $_ }
    if ($LASTEXITCODE -ne 0) { throw "xelab failed with exit code $LASTEXITCODE" }
    & (Join-Path $VivadoBin "xsim.bat") "day10_fc2_hw_compare_snapshot" "-runall" 2>&1 | ForEach-Object { $lines.Add([string]$_); Write-Host $_ }
    if ($LASTEXITCODE -ne 0) { throw "xsim failed with exit code $LASTEXITCODE" }
    $lines.Add("Completed: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
} catch {
    $lines.Add("ERROR: $($_.Exception.Message)")
    $lines | Set-Content -LiteralPath $Log -Encoding UTF8
    Pop-Location -ErrorAction SilentlyContinue
    throw
} finally {
    if ((Get-Location).Path -eq $Root) { } else { Pop-Location -ErrorAction SilentlyContinue }
}
$lines | Set-Content -LiteralPath $Log -Encoding UTF8
Write-Host ""
Write-Host "Comparison log: $Log" -ForegroundColor Green
Write-Host "Check for DAY10_FC2_HW_INTERFACE_PASS and ten PASS class lines."

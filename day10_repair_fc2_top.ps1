$ErrorActionPreference = "Stop"
$Root = "D:\FPGA_EdgeAI\cnn_baseline"
Set-Location $Root
$Candidate = Join-Path $Root "rtl\cnn_integrated_fc2_hw_top.v"
$TB = Join-Path $Root "tb\tb_cnn_fc2_hw_top_compare.v"
$Log = Join-Path $Root "day10_fc2_top_repair.log"
$VivadoBin = "D:\vivado\2025.1\Vivado\bin"
$Xvlog = Join-Path $VivadoBin "xvlog.bat"
$Xelab = Join-Path $VivadoBin "xelab.bat"
$Xsim = Join-Path $VivadoBin "xsim.bat"

foreach ($f in @($Candidate,$TB,$Xvlog,$Xelab,$Xsim)) {
  if (!(Test-Path $f)) { throw "Required file not found: $f" }
}

$src = Get-Content $Candidate -Raw
# Restore the phase-6 case label that the previous script accidentally merged into phase 5.
$bad = '5:\s*if\(f1_done\)\s*begin\s*phase<=6;\s*wait_count<=3;\s*end\s*6:\s*if\(wait_count>0\)'
$good = "5: if(f1_done) begin phase<=6;wait_count<=3;end`r`n      6: if(wait_count>0)"
$fixed = [regex]::Replace($src, $bad, $good, 1)
if ($fixed -eq $src) {
  if ($src -match '5:\s*if\(f1_done\).*?6:\s*if\(wait_count>0\)') {
    throw "Phase 5/6 pattern was found but not safely replaced. Candidate unchanged."
  }
  if ($src -notmatch '(?m)^\s*6:\s*if\(wait_count>0\)') {
    throw "Could not locate phase 6 case label. Candidate unchanged; inspect candidate file."
  }
}
# Ensure the phase-6 body and phase-7 start remain separate case branches.
if ($fixed -notmatch '(?s)5:\s*if\(f1_done\).*?6:\s*if\(wait_count>0\).*?9:\s*begin') {
  throw "Phase 5/6/9 structure did not validate. Candidate unchanged."
}
Set-Content -Path $Candidate -Value $fixed -Encoding ascii

# Replace testbench with a fail-closed version. It prints PASS only after both tops complete.
$tbText = @'
`timescale 1ns/1ps
module tb_cnn_fc2_hw_top_compare;
 reg clk=0, rst=1, start=0;
 wire b_busy,b_done,b_scores_valid;
 wire [3:0] b_class;
 wire signed [31:0] b0,b1,b2,b3,b4,b5,b6,b7,b8,b9;
 wire h_busy,h_done,h_scores_valid;
 wire [3:0] h_class;
 wire signed [31:0] h0,h1,h2,h3,h4,h5,h6,h7,h8,h9;
 integer cycles, errors;
 always #5 clk=~clk;

 cnn_integrated_sim_top baseline(
  .clk(clk),.rst(rst),.start(start),.busy(b_busy),.done(b_done),
  .predicted_class(b_class),.scores_valid(b_scores_valid),
  .score0(b0),.score1(b1),.score2(b2),.score3(b3),.score4(b4),
  .score5(b5),.score6(b6),.score7(b7),.score8(b8),.score9(b9)
 );
 cnn_integrated_fc2_hw_top candidate(
  .clk(clk),.rst(rst),.start(start),.busy(h_busy),.done(h_done),
  .predicted_class(h_class),.scores_valid(h_scores_valid),
  .score0(h0),.score1(h1),.score2(h2),.score3(h3),.score4(h4),
  .score5(h5),.score6(h6),.score7(h7),.score8(h8),.score9(h9)
 );

 initial begin
  errors=0;
  repeat(4) @(negedge clk);
  rst=0;
  @(negedge clk); start=1;
  @(negedge clk); start=0;
  cycles=0;
  while((b_done!==1'b1 || h_done!==1'b1) && cycles<2000000) begin
   @(posedge clk); #1; cycles=cycles+1;
  end
  if(b_done!==1'b1 || h_done!==1'b1) begin
   $display("DAY10_FC2_TOP_COMPARE_FAIL_TIMEOUT baseline_done=%b candidate_done=%b cycles=%0d",b_done,h_done,cycles);
   $fatal(1,"CNN top comparison timed out; no PASS marker is valid");
  end
  if(b_class !== h_class) begin $display("MISMATCH predicted_class baseline=%0d candidate=%0d",b_class,h_class); errors=errors+1; end
  if(b0!==h0) begin $display("MISMATCH score0 baseline=%0d candidate=%0d",b0,h0); errors=errors+1; end
  if(b1!==h1) begin $display("MISMATCH score1 baseline=%0d candidate=%0d",b1,h1); errors=errors+1; end
  if(b2!==h2) begin $display("MISMATCH score2 baseline=%0d candidate=%0d",b2,h2); errors=errors+1; end
  if(b3!==h3) begin $display("MISMATCH score3 baseline=%0d candidate=%0d",b3,h3); errors=errors+1; end
  if(b4!==h4) begin $display("MISMATCH score4 baseline=%0d candidate=%0d",b4,h4); errors=errors+1; end
  if(b5!==h5) begin $display("MISMATCH score5 baseline=%0d candidate=%0d",b5,h5); errors=errors+1; end
  if(b6!==h6) begin $display("MISMATCH score6 baseline=%0d candidate=%0d",b6,h6); errors=errors+1; end
  if(b7!==h7) begin $display("MISMATCH score7 baseline=%0d candidate=%0d",b7,h7); errors=errors+1; end
  if(b8!==h8) begin $display("MISMATCH score8 baseline=%0d candidate=%0d",b8,h8); errors=errors+1; end
  if(b9!==h9) begin $display("MISMATCH score9 baseline=%0d candidate=%0d",b9,h9); errors=errors+1; end
  $display("Baseline class=%0d Candidate class=%0d",b_class,h_class);
  $display("Baseline scores: %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d",b0,b1,b2,b3,b4,b5,b6,b7,b8,b9);
  $display("Candidate scores: %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d",h0,h1,h2,h3,h4,h5,h6,h7,h8,h9);
  if(errors==0) begin $display("DAY10_FC2_TOP_COMPARE_PASS cycles=%0d",cycles); $finish; end
  else begin $display("DAY10_FC2_TOP_COMPARE_FAIL mismatches=%0d",errors); $fatal(1,"CNN top comparison mismatch"); end
 end
endmodule
'@
Set-Content -Path $TB -Value $tbText -Encoding ascii

# Recompile and run. Exit immediately if compile/elaboration/simulation returns nonzero.
$lines = @()
$lines += "DAY 10 FC2 TOP REPAIR AND VALIDATION"
$lines += "Generated: $(Get-Date -Format s)"
$lines += "Candidate: $Candidate"
$lines += "Testbench: $TB"
$lines | Set-Content $Log
& $Xvlog -work work `
  (Join-Path $Root "rtl\conv1_shared_mac.v") (Join-Path $Root "rtl\conv1_full_layer.v") (Join-Path $Root "rtl\conv1_requantize.v") `
  (Join-Path $Root "rtl\conv2_shared_mac.v") (Join-Path $Root "rtl\conv2_full_layer.v") (Join-Path $Root "rtl\conv2_requantize.v") `
  (Join-Path $Root "rtl\fc1_shared_mac.v") (Join-Path $Root "rtl\fc1_full_layer.v") (Join-Path $Root "rtl\fc1_requantize.v") `
  (Join-Path $Root "rtl\fc2_shared_mac.v") (Join-Path $Root "rtl\fc2_full_layer.v") (Join-Path $Root "rtl\fc2_full_layer_hw.v") `
  (Join-Path $Root "rtl\cnn_integrated_sim_top.v") $Candidate $TB 2>&1 | Tee-Object -FilePath $Log -Append
if ($LASTEXITCODE -ne 0) { throw "xvlog failed with exit code $LASTEXITCODE. See $Log" }

& $Xelab tb_cnn_fc2_hw_top_compare -s day10_fc2_top_repair_snapshot 2>&1 | Tee-Object -FilePath $Log -Append
if ($LASTEXITCODE -ne 0) { throw "xelab failed with exit code $LASTEXITCODE. See $Log" }

& $Xsim day10_fc2_top_repair_snapshot -runall 2>&1 | Tee-Object -FilePath $Log -Append
if ($LASTEXITCODE -ne 0) { throw "xsim failed with exit code $LASTEXITCODE. See $Log" }

$logText = Get-Content $Log -Raw
if ($logText -notmatch 'DAY10_FC2_TOP_COMPARE_PASS') { throw "No PASS marker in simulation log. Treat as failed. See $Log" }
if ($logText -match 'DAY10_FC2_TOP_COMPARE_FAIL|FAIL_TIMEOUT|MISMATCH') { throw "Failure marker found in simulation log. See $Log" }
Write-Host "Validation PASS. Log: $Log"

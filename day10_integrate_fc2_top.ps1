$ErrorActionPreference = "Stop"
$Root = "D:\FPGA_EdgeAI\cnn_baseline"
$VivadoBin = "D:\vivado\2025.1\Vivado\bin"
Set-Location $Root

$BaseTop = Join-Path $Root "rtl\cnn_integrated_sim_top.v"
$HwFc2 = Join-Path $Root "rtl\fc2_full_layer_hw.v"
$NewTop = Join-Path $Root "rtl\cnn_integrated_fc2_hw_top.v"
$Tb = Join-Path $Root "tb\tb_cnn_fc2_hw_top_compare.v"
$Log = Join-Path $Root "day10_fc2_top_compare.log"

foreach ($f in @($BaseTop,$HwFc2)) {
    if (-not (Test-Path $f)) { throw "Required file missing: $f" }
}
if (Test-Path $NewTop) { throw "Refusing to overwrite existing file: $NewTop" }
if (Test-Path $Tb) { throw "Refusing to overwrite existing testbench: $Tb" }

$src = Get-Content -Raw -LiteralPath $BaseTop
$nl = [Environment]::NewLine

# Rename only the copied top module.
$src = [regex]::Replace($src, '(?m)^(\s*module\s+)cnn_integrated_sim_top\b', '${1}cnn_integrated_fc2_hw_top', 1)
if ($src -notmatch '(?m)^\s*module\s+cnn_integrated_fc2_hw_top\b') { throw "Could not rename copied top module." }

# Add the FC2 activation write signals and transfer counter.
$oldDecl = ' reg c1_start,c2_start,f1_start,f2_start;'
$newDecl = $oldDecl + $nl +
' reg f2_input_we;' + $nl +
' reg [5:0] f2_input_addr;' + $nl +
' reg [7:0] f2_input_data;' + $nl +
' integer f2_transfer_index;'
if (-not $src.Contains($oldDecl)) { throw "Could not find start-signal declaration." }
$src = $src.Replace($oldDecl, $newDecl)

# Replace only FC2 instantiation.
$oldInst = @'
 fc2_full_layer f2(.clk(clk),.rst(rst),.start(f2_start),.busy(f2_busy),.done(f2_done),
  .out_addr(f2_addr),.out_score(f2_score),.out_valid(f2_valid));
'@
$newInst = @'
 fc2_full_layer_hw #(.LOAD_INPUT_ROM(0)) f2(
  .clk(clk),.rst(rst),.start(f2_start),
  .input_we(f2_input_we),.input_addr(f2_input_addr),.input_data(f2_input_data),
  .busy(f2_busy),.done(f2_done),.out_addr(f2_addr),.out_score(f2_score),.out_valid(f2_valid));
'@
if (-not $src.Contains($oldInst)) { throw "Could not find exact FC2 instance in top." }
$src = $src.Replace($oldInst, $newInst)

# Reset interface signals.
$oldReset = '    c1_start<=0;c2_start<=0;f1_start<=0;f2_start<=0;'
$newReset = $oldReset + $nl + '    f2_input_we<=0;f2_input_addr<=0;f2_input_data<=0;f2_transfer_index<=0;'
if (-not $src.Contains($oldReset)) { throw "Could not find reset start-signal assignment." }
$resetRegex = [regex]::new([regex]::Escape($oldReset))
$src = $resetRegex.Replace($src, $newReset, 1)

# Default input write enable low every cycle.
$oldDefault = '    c1_start<=0;c2_start<=0;f1_start<=0;f2_start<=0;'
$newDefault = $oldDefault + $nl + '    f2_input_we<=0;'
# The reset line was also changed and still contains the old string; replace the first occurrence only in the else region safely.
$marker = '   end else begin' + $nl + '    done<=0;scores_valid<=0;' + $nl + $oldDefault
$replacement = '   end else begin' + $nl + '    done<=0;scores_valid<=0;' + $nl + $newDefault
if (-not $src.Contains($marker)) { throw "Could not find default pulse assignments in controller." }
$src = $src.Replace($marker, $replacement)

# Replace the old bulk hierarchical write to FC2 with sequential public-port transfer.
$oldPhase6 = @'
      6: if(wait_count>0) wait_count<=wait_count-1;
         else begin
          for(i=0;i<64;i=i+1) f2.input_map[i]=fc1_acts[i];
          phase<=7;f2_start<=1;
         end
      7: if(f2_done) begin phase<=8;wait_count<=3;end
'@
$newPhase6 = @'
      6: if(wait_count>0) wait_count<=wait_count-1;
         else begin f2_transfer_index<=0;phase<=9;end
      9: begin
          f2_input_we<=1;
          f2_input_addr<=f2_transfer_index[5:0];
          f2_input_data<=fc1_acts[f2_transfer_index];
          if(f2_transfer_index==63) phase<=10;
          else f2_transfer_index<=f2_transfer_index+1;
         end
     10: begin f2_start<=1;phase<=7;end
      7: if(f2_done) begin phase<=8;wait_count<=3;end
'@
if (-not $src.Contains($oldPhase6)) { throw "Could not find exact phase 6/7 block." }
$src = $src.Replace($oldPhase6, $newPhase6)

# Verify the new top has no FC2 hierarchical write and includes all public ports.
if ($src -match 'f2\.input_map' -or $src -notmatch 'f2_input_we' -or $src -notmatch 'fc2_full_layer_hw') {
    throw "New top verification failed. No file written."
}
Set-Content -LiteralPath $NewTop -Value $src -Encoding ASCII

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
   $display("FAIL: timeout baseline_done=%b candidate_done=%b cycles=%0d",b_done,h_done,cycles);
   $fatal(1);
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
  else begin $display("DAY10_FC2_TOP_COMPARE_FAIL mismatches=%0d",errors); $fatal(1); end
 end
endmodule
'@
Set-Content -LiteralPath $Tb -Value $tbText -Encoding ASCII

$Files = @(
 "rtl\conv1_shared_mac.v","rtl\conv1_full_layer.v","rtl\conv1_requantize.v",
 "rtl\conv2_shared_mac.v","rtl\conv2_full_layer.v","rtl\conv2_requantize.v",
 "rtl\fc1_shared_mac.v","rtl\fc1_full_layer.v","rtl\fc1_requantize.v",
 "rtl\fc2_shared_mac.v","rtl\fc2_full_layer.v","rtl\fc2_full_layer_hw.v",
 "rtl\cnn_integrated_sim_top.v","rtl\cnn_integrated_fc2_hw_top.v",
 "tb\tb_cnn_fc2_hw_top_compare.v"
)
$LogLines = New-Object System.Collections.Generic.List[string]
$LogLines.Add("DAY 10 FC2 TOP INTEGRATION COMPARISON")
$LogLines.Add("Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
$LogLines.Add("New top: rtl\cnn_integrated_fc2_hw_top.v")
$LogLines.Add("Baseline top remains unchanged: rtl\cnn_integrated_sim_top.v")
$LogLines.Add("Testbench: tb\tb_cnn_fc2_hw_top_compare.v")
try {
 foreach ($f in $Files) { if (-not (Test-Path (Join-Path $Root $f))) { throw "Missing source file: $f" } }
 & (Join-Path $VivadoBin "xvlog.bat") @Files 2>&1 | ForEach-Object { $LogLines.Add([string]$_); Write-Host $_ }
 if ($LASTEXITCODE -ne 0) { throw "xvlog failed with exit code $LASTEXITCODE" }
 & (Join-Path $VivadoBin "xelab.bat") "tb_cnn_fc2_hw_top_compare" "-s" "day10_fc2_top_compare_snapshot" 2>&1 | ForEach-Object { $LogLines.Add([string]$_); Write-Host $_ }
 if ($LASTEXITCODE -ne 0) { throw "xelab failed with exit code $LASTEXITCODE" }
 & (Join-Path $VivadoBin "xsim.bat") "day10_fc2_top_compare_snapshot" "-runall" 2>&1 | ForEach-Object { $LogLines.Add([string]$_); Write-Host $_ }
 if ($LASTEXITCODE -ne 0) { throw "xsim failed with exit code $LASTEXITCODE" }
 $LogLines.Add("Finished: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
} catch {
 $LogLines.Add("ERROR: $($_.Exception.Message)")
 $LogLines | Set-Content -LiteralPath $Log -Encoding UTF8
 throw
}
$LogLines | Set-Content -LiteralPath $Log -Encoding UTF8
Write-Host ""
Write-Host "Top comparison log: $Log" -ForegroundColor Green
Write-Host "Expected marker: DAY10_FC2_TOP_COMPARE_PASS"

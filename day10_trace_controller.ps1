$ErrorActionPreference = "Stop"
$Root = "D:\FPGA_EdgeAI\cnn_baseline"
Set-Location $Root
$TB = Join-Path $Root "tb\tb_cnn_fc2_hw_top_compare.v"
$Log = Join-Path $Root "day10_controller_trace.log"
$VivadoBin = "D:\vivado\2025.1\Vivado\bin"
$Xvlog = Join-Path $VivadoBin "xvlog.bat"
$Xelab = Join-Path $VivadoBin "xelab.bat"
$Xsim = Join-Path $VivadoBin "xsim.bat"
if (!(Test-Path $TB)) { throw "Missing testbench: $TB" }

$src = Get-Content $TB -Raw
# Add sampled controller/layer state tracing, with bounded output.
$trace = @'
 // Debug trace: sample controller progress independently of the main test.
 initial begin : controller_trace
  integer trace_cycle;
  trace_cycle=0;
  forever begin
   @(posedge clk); #1;
   trace_cycle=trace_cycle+1;
   if (trace_cycle <= 80 || (trace_cycle % 100000)==0) begin
    $display("TRACE cyc=%0d rst=%b start=%b | B phase=%0d busy=%b done=%b c1=%b/%b c2=%b/%b f1=%b/%b f2=%b/%b | H phase=%0d busy=%b done=%b c1=%b/%b c2=%b/%b f1=%b/%b f2=%b/%b",
     trace_cycle,rst,start,baseline.phase,b_busy,b_done,baseline.c1_busy,baseline.c1_done,baseline.c2_busy,baseline.c2_done,baseline.f1_busy,baseline.f1_done,baseline.f2_busy,baseline.f2_done,
     candidate.phase,h_busy,h_done,candidate.c1_busy,candidate.c1_done,candidate.c2_busy,candidate.c2_done,candidate.f1_busy,candidate.f1_done,candidate.f2_busy,candidate.f2_done);
   end
  end
 end
'@
if ($src -match 'Debug trace: sample controller progress') { throw "Trace already inserted. Restore testbench from your saved copy before rerunning." }
$needle = " initial begin`r`n  errors=0;"
if (!$src.Contains($needle)) { $needle = " initial begin`n  errors=0;" }
if (!$src.Contains($needle)) { throw "Could not locate testbench initial block; file unchanged." }
$src = $src.Replace($needle, $trace + "`r`n" + $needle)
Set-Content -Path $TB -Value $src -Encoding ascii

"DAY 10 CONTROLLER TRACE`r`nGenerated: $(Get-Date -Format s)" | Set-Content $Log
& $Xvlog -work work `
  (Join-Path $Root "rtl\conv1_shared_mac.v") (Join-Path $Root "rtl\conv1_full_layer.v") (Join-Path $Root "rtl\conv1_requantize.v") `
  (Join-Path $Root "rtl\conv2_shared_mac.v") (Join-Path $Root "rtl\conv2_full_layer.v") (Join-Path $Root "rtl\conv2_requantize.v") `
  (Join-Path $Root "rtl\fc1_shared_mac.v") (Join-Path $Root "rtl\fc1_full_layer.v") (Join-Path $Root "rtl\fc1_requantize.v") `
  (Join-Path $Root "rtl\fc2_shared_mac.v") (Join-Path $Root "rtl\fc2_full_layer.v") (Join-Path $Root "rtl\fc2_full_layer_hw.v") `
  (Join-Path $Root "rtl\cnn_integrated_sim_top.v") (Join-Path $Root "rtl\cnn_integrated_fc2_hw_top.v") $TB 2>&1 | Tee-Object -FilePath $Log -Append
if ($LASTEXITCODE -ne 0) { throw "xvlog failed. See $Log" }
& $Xelab tb_cnn_fc2_hw_top_compare -s day10_controller_trace_snapshot 2>&1 | Tee-Object -FilePath $Log -Append
if ($LASTEXITCODE -ne 0) { throw "xelab failed. See $Log" }
& $Xsim day10_controller_trace_snapshot -runall 2>&1 | Tee-Object -FilePath $Log -Append
Write-Host "Trace complete: $Log"
Write-Host "Extract TRACE lines with: Select-String -Path `"$Log`" -Pattern '^TRACE|FAIL_TIMEOUT'"

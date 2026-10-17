$ErrorActionPreference = "Stop"
$Root = "D:\FPGA_EdgeAI\cnn_baseline"
Set-Location $Root
$TB = Join-Path $Root "tb\tb_cnn_fc2_hw_top_compare.v"
$Log = Join-Path $Root "day10_fsm_progress.log"
$VivadoBin = "D:\vivado\2025.1\Vivado\bin"
$Xvlog = Join-Path $VivadoBin "xvlog.bat"
$Xelab = Join-Path $VivadoBin "xelab.bat"
$Xsim = Join-Path $VivadoBin "xsim.bat"
if (!(Test-Path $TB)) { throw "Missing testbench: $TB" }

$src = Get-Content $TB -Raw
$old = @'
   $display("DAY10_FC2_TOP_COMPARE_FAIL_TIMEOUT baseline_done=%b candidate_done=%b cycles=%0d",b_done,h_done,cycles);
   $fatal(1,"CNN top comparison timed out; no PASS marker is valid");
'@
$new = @'
   $display("DAY10_FC2_TOP_COMPARE_FAIL_TIMEOUT baseline_done=%b candidate_done=%b cycles=%0d",b_done,h_done,cycles);
   $display("BASELINE CTRL phase=%0d wait_count=%0d busy=%b done=%b start=%b c1_start=%b c1_busy=%b c1_done=%b c2_busy=%b c2_done=%b f1_busy=%b f1_done=%b f2_busy=%b f2_done=%b",
      baseline.phase,baseline.wait_count,b_busy,b_done,start,baseline.c1_start,baseline.c1_busy,baseline.c1_done,baseline.c2_busy,baseline.c2_done,baseline.f1_busy,baseline.f1_done,baseline.f2_busy,baseline.f2_done);
   $display("CANDIDATE CTRL phase=%0d wait_count=%0d busy=%b done=%b start=%b c1_start=%b c1_busy=%b c1_done=%b c2_busy=%b c2_done=%b f1_busy=%b f1_done=%b f2_busy=%b f2_done=%b f2_we=%b f2_addr=%0d transfer_index=%0d",
      candidate.phase,candidate.wait_count,h_busy,h_done,start,candidate.c1_start,candidate.c1_busy,candidate.c1_done,candidate.c2_busy,candidate.c2_done,candidate.f1_busy,candidate.f1_done,candidate.f2_busy,candidate.f2_done,candidate.f2_input_we,candidate.f2_input_addr,candidate.f2_transfer_index);
   $fatal(1,"CNN top comparison timed out; no PASS marker is valid");
'@
if (!$src.Contains($old)) { throw "Could not find expected timeout block. Testbench left unchanged." }
$src = $src.Replace($old,$new)
Set-Content -Path $TB -Value $src -Encoding ascii

"DAY 10 FSM PROGRESS DIAGNOSTICS`r`nGenerated: $(Get-Date -Format s)" | Set-Content $Log
& $Xvlog -work work `
  (Join-Path $Root "rtl\conv1_shared_mac.v") (Join-Path $Root "rtl\conv1_full_layer.v") (Join-Path $Root "rtl\conv1_requantize.v") `
  (Join-Path $Root "rtl\conv2_shared_mac.v") (Join-Path $Root "rtl\conv2_full_layer.v") (Join-Path $Root "rtl\conv2_requantize.v") `
  (Join-Path $Root "rtl\fc1_shared_mac.v") (Join-Path $Root "rtl\fc1_full_layer.v") (Join-Path $Root "rtl\fc1_requantize.v") `
  (Join-Path $Root "rtl\fc2_shared_mac.v") (Join-Path $Root "rtl\fc2_full_layer.v") (Join-Path $Root "rtl\fc2_full_layer_hw.v") `
  (Join-Path $Root "rtl\cnn_integrated_sim_top.v") (Join-Path $Root "rtl\cnn_integrated_fc2_hw_top.v") $TB 2>&1 | Tee-Object -FilePath $Log -Append
if ($LASTEXITCODE -ne 0) { throw "xvlog failed. See $Log" }
& $Xelab tb_cnn_fc2_hw_top_compare -s day10_fsm_debug_snapshot 2>&1 | Tee-Object -FilePath $Log -Append
if ($LASTEXITCODE -ne 0) { throw "xelab failed. See $Log" }
& $Xsim day10_fsm_debug_snapshot -runall 2>&1 | Tee-Object -FilePath $Log -Append
Write-Host "Diagnostic run finished. Inspect: $Log"

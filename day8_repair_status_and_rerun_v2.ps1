$ErrorActionPreference = "Stop"

$root = "D:\FPGA_EdgeAI\cnn_baseline"
$vivado = "D:\vivado\2025.1\Vivado\bin"
$tb = Join-Path $root "tb\tb_cnn_integrated_validation.v"
$top = Join-Path $root "rtl\cnn_integrated_sim_top.v"
$status = Join-Path $root "cnn_rtl_run_status.txt"
$scores = Join-Path $root "cnn_rtl_final_scores.txt"
$log = Join-Path $root "day8_xsim_repair.log"

Set-Location $root
if (!(Test-Path $tb)) { throw "Missing testbench: $tb" }
if (!(Test-Path $top)) { throw "Missing integration top: $top" }

$src = Get-Content $tb -Raw

# Patch only the known timeout line, using literal string replacement to avoid
# PowerShell -replace parsing/precedence problems.
$old = 'if(!done) begin $display("FAIL: integrated CNN timed out at %0d cycles",cycles);$fatal(1);end'
$new = @'
if(!done) begin
    integer status_fd;
    $display("FAIL: integrated CNN timed out at %0d cycles",cycles);
    status_fd=$fopen("cnn_rtl_run_status.txt","w");
    if(status_fd!=0) begin $fwrite(status_fd,"FAIL: timeout at %0d cycles\n",cycles);$fclose(status_fd);end
    $fclose(fd);
    $finish;
  end else begin
    integer status_fd;
    status_fd=$fopen("cnn_rtl_run_status.txt","w");
    if(status_fd!=0) begin $fwrite(status_fd,"PASS\n");$fclose(status_fd);end
  end
'@
if ($src.Contains($old)) {
    $src = $src.Replace($old, $new.Trim())
    Set-Content -Path $tb -Value $src -Encoding ascii
    Write-Host "Patched timeout handling and explicit status reporting." -ForegroundColor Green
} elseif ($src -match 'cnn_rtl_run_status\.txt') {
    Write-Host "Testbench already contains run-status logic; leaving it unchanged." -ForegroundColor Yellow
} else {
    Write-Host "Expected timeout statement was not found. Current timeout-related lines:" -ForegroundColor Red
    Select-String -Path $tb -Pattern 'while|timed out|fatal|finish|fwrite|fopen'
    throw "No source change made. Please send the current testbench contents."
}

Remove-Item $status, $scores, $log -Force -ErrorAction SilentlyContinue

$xvlog = Join-Path $vivado "xvlog.bat"
$xelab = Join-Path $vivado "xelab.bat"
$xsim  = Join-Path $vivado "xsim.bat"
foreach ($tool in @($xvlog,$xelab,$xsim)) {
    if (!(Test-Path $tool)) { throw "Vivado simulation tool not found: $tool" }
}

Write-Host "`nCompiling RTL and testbench..." -ForegroundColor Cyan
$rtlFiles = Get-ChildItem (Join-Path $root "rtl") -Filter "*.v" | Sort-Object FullName | ForEach-Object { $_.FullName }
$compileArgs = @("-sv", "-work", "xil_defaultlib") + $rtlFiles + @($tb)
& $xvlog @compileArgs 2>&1 | Tee-Object -FilePath $log
if ($LASTEXITCODE -ne 0) { throw "xvlog failed. See $log" }

Write-Host "`nElaborating testbench..." -ForegroundColor Cyan
& $xelab "xil_defaultlib.tb_cnn_integrated_validation" "-s" "cnn_integrated_repair_sim" 2>&1 | Tee-Object -FilePath $log -Append
if ($LASTEXITCODE -ne 0) { throw "xelab failed. See $log" }

Write-Host "`nRunning XSim..." -ForegroundColor Cyan
& $xsim "cnn_integrated_repair_sim" "-runall" 2>&1 | Tee-Object -FilePath $log -Append

Write-Host "`n--- Result gate ---" -ForegroundColor Cyan
if (!(Test-Path $status)) {
    Write-Host "FAIL: no run-status file. Integration is unverified." -ForegroundColor Red
    exit 2
}
$statusText = (Get-Content $status -Raw).Trim()
Write-Host "Simulation status: $statusText"
if ($statusText -notmatch '^PASS$') {
    Write-Host "Integration did not complete. Do not compare scores." -ForegroundColor Red
    exit 3
}
if (!(Test-Path $scores)) {
    throw "Simulation status is PASS but the score file is missing."
}
Write-Host "Simulation completed and produced a fresh score file." -ForegroundColor Green
Write-Host "Do not claim end-to-end correctness until the fresh scores are compared against Python." -ForegroundColor Yellow

$ErrorActionPreference = "Stop"

$root = "D:\FPGA_EdgeAI\cnn_baseline"
$vivado = "D:\vivado\2025.1\Vivado\bin"
$tb = Join-Path $root "tb\tb_cnn_integrated_validation.v"
$top = Join-Path $root "rtl\cnn_integrated_sim_top.v"
$status = Join-Path $root "cnn_rtl_run_status.txt"
$scores = Join-Path $root "cnn_rtl_final_scores.txt"
$log = Join-Path $root "day8_xsim_repair.log"

if (!(Test-Path $tb)) { throw "Missing testbench: $tb" }
if (!(Test-Path $top)) { throw "Missing integration top: $top" }

Set-Location $root
Remove-Item $status, $scores, $log -Force -ErrorAction SilentlyContinue

Write-Host "`n--- Inspecting integration testbench ---" -ForegroundColor Cyan
$lines = Get-Content $tb
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match 'while\s*\(!done|timed out|fopen|fwrite|predicted class|finish|fatal|cycles') {
        "{0,4}: {1}" -f ($i + 1), $lines[$i] | Write-Host
    }
}

# Patch the testbench to make the completion state explicit and prevent stale score files
# from being mistaken for a successful integrated run.
$src = Get-Content $tb -Raw

if ($src -notmatch 'cnn_rtl_run_status\.txt') {
    # Initialize status as FAIL before waiting. It becomes PASS only after done is observed.
    $src = $src -replace '(?s)(initial\s+begin)', '$1' + "`r`n    begin : run_status_init`r`n      integer status_fd;`r`n      status_fd = `$fopen(""cnn_rtl_run_status.txt"", ""w"");`r`n      if (status_fd != 0) begin `$fwrite(status_fd, ""FAIL`n""); `$fclose(status_fd); end`r`n    end`r`n"

    # Replace a common timeout block with a status write and immediate finish.
    $timeoutPattern = '(?s)if\s*\(\s*!done\s*\)\s*begin.*?\$fatal\s*\(\s*1\s*\)\s*;\s*end'
    if ($src -match $timeoutPattern) {
        $replacement = @'
if (!done) begin
        integer status_fd;
        $display("FAIL: integrated CNN timed out at %0d cycles", cycles);
        status_fd = $fopen("cnn_rtl_run_status.txt", "w");
        if (status_fd != 0) begin $fwrite(status_fd, "FAIL: timeout at %0d cycles\n", cycles); $fclose(status_fd); end
        $finish;
      end
'@
        $src = [regex]::Replace($src, $timeoutPattern, $replacement, 1)
    } else {
        Write-Warning "Could not find the standard timeout block. Testbench was not safely patched; inspect the lines printed above."
        throw "No matching timeout block found. No simulation was run."
    }

    # Insert PASS status immediately after the !done guard and before scores are written.
    $passAnchor = '(?s)(if\s*\(\s*!done\s*\)\s*begin.*?\$finish\s*;\s*end)'
    if ($src -match $passAnchor) {
        $passWrite = @'
$1
      begin : mark_run_pass
        integer status_fd;
        status_fd = $fopen("cnn_rtl_run_status.txt", "w");
        if (status_fd != 0) begin $fwrite(status_fd, "PASS\n"); $fclose(status_fd); end
      end
'@
        $src = [regex]::Replace($src, $passAnchor, $passWrite, 1)
    } else {
        throw "Could not insert PASS status safely. No simulation was run."
    }

    Set-Content -Path $tb -Value $src -Encoding ascii
    Write-Host "Patched testbench with explicit PASS/FAIL status." -ForegroundColor Green
} else {
    Write-Host "Testbench already contains run-status handling; leaving it unchanged." -ForegroundColor Yellow
}

# Compile and run the patched testbench directly so the Day 8 generator cannot overwrite it.
$xvlog = Join-Path $vivado "xvlog.bat"
$xelab = Join-Path $vivado "xelab.bat"
$xsim  = Join-Path $vivado "xsim.bat"
if (!(Test-Path $xvlog) -or !(Test-Path $xelab) -or !(Test-Path $xsim)) {
    throw "Vivado simulation tools not found under $vivado"
}

Remove-Item $status, $scores -Force -ErrorAction SilentlyContinue
Write-Host "`nCompiling RTL and patched testbench..." -ForegroundColor Cyan
$rtlFiles = Get-ChildItem (Join-Path $root "rtl") -Filter "*.v" | ForEach-Object { $_.FullName }
$compileArgs = @("-sv", "-work", "xil_defaultlib") + $rtlFiles + @($tb)
& $xvlog @compileArgs 2>&1 | Tee-Object -FilePath $log
if ($LASTEXITCODE -ne 0) { throw "xvlog failed. See $log" }

Write-Host "`nElaborating testbench..." -ForegroundColor Cyan
& $xelab "xil_defaultlib.tb_cnn_integrated_validation" "-s" "cnn_integrated_repair_sim" 2>&1 | Tee-Object -FilePath $log -Append
if ($LASTEXITCODE -ne 0) { throw "xelab failed. See $log" }

Write-Host "`nRunning XSim..." -ForegroundColor Cyan
& $xsim "cnn_integrated_repair_sim" "-runall" 2>&1 | Tee-Object -FilePath $log -Append
$runnerExit = $LASTEXITCODE

Write-Host "`n--- Run status ---" -ForegroundColor Cyan
if (!(Test-Path $status)) {
    Write-Host "FAIL: no status file was produced. Do not trust any score comparison." -ForegroundColor Red
    Write-Host "XSim log: $log"
    exit 2
}
$statusText = (Get-Content $status -Raw).Trim()
Write-Host $statusText
if ($statusText -notmatch '^PASS(\s|$)') {
    Write-Host "INTEGRATED CNN NOT VERIFIED. Score comparison is intentionally blocked." -ForegroundColor Red
    Write-Host "Review the XSim log and stage progress above: $log"
    exit 3
}
if (!(Test-Path $scores)) {
    throw "Status says PASS but score file is missing: $scores"
}
if ($runnerExit -ne 0) {
    Write-Warning "Runner exit code was $runnerExit although status says PASS. Review $log."
}
Write-Host "PASS status and fresh score file found. Check the runner output for all per-layer checks before accepting the result." -ForegroundColor Green

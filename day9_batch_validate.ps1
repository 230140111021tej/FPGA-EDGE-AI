$ErrorActionPreference = "Stop"
$root = "D:\FPGA_EdgeAI\cnn_baseline"
$vivado = "D:\vivado\2025.1\Vivado\bin"
Set-Location $root

# This script preserves the exporter, testbench, and current image ROM.
$exporter = Join-Path $root "scripts\export_real_mnist_image.py"
$imageRom = Join-Path $root "rom\conv1_image_u8_hex.mem"
$imageInfo = Join-Path $root "rom\conv1_image_info.txt"
$exporterBackup = Join-Path $root "scripts\export_real_mnist_image.py.day9_backup"
$imageBackup = Join-Path $root "rom\conv1_image_u8_hex.mem.day9_backup"
$infoBackup = Join-Path $root "rom\conv1_image_info.txt.day9_backup"
$resultsPath = Join-Path $root "day9_batch_results.csv"
$runLog = Join-Path $root "day9_batch_validation.log"
$tb = Join-Path $root "tb\tb_cnn_integrated_validation.v"
$top = Join-Path $root "rtl\cnn_integrated_sim_top.v"

foreach ($f in @($exporter,$imageRom,$tb,$top)) {
    if (!(Test-Path $f)) { throw "Required file missing: $f" }
}
foreach ($tool in @("xvlog.bat","xelab.bat","xsim.bat")) {
    if (!(Test-Path (Join-Path $vivado $tool))) { throw "Vivado tool missing: $(Join-Path $vivado $tool)" }
}

# Confirm the Day 8 race fix is present before running anything.
$tbText = Get-Content $tb -Raw
if (!$tbText.Contains("while(done !== 1'b1 && cycles<2000000) begin @(posedge clk); #1; cycles=cycles+1; end")) {
    throw "The Day 8 done-sampling race fix is not present. Stop; do not regenerate the testbench."
}

if ((Test-Path $exporterBackup) -or (Test-Path $imageBackup) -or (Test-Path $infoBackup)) {
    throw "A Day 9 backup already exists. Inspect it before rerunning to avoid overwriting recovery files."
}
Copy-Item $exporter $exporterBackup
Copy-Item $imageRom $imageBackup
if (Test-Path $imageInfo) { Copy-Item $imageInfo $infoBackup }

$rows = [System.Collections.Generic.List[object]]::new()
$allPassed = $true
try {
    $originalExporter = Get-Content $exporter -Raw
    $selectedLine = 'selected = next((i for i in range(len(ds)) if int(ds[i][1]) == 7), 0)'
    if (!$originalExporter.Contains($selectedLine)) {
        throw "Exporter selection line differs from the inspected version. No batch run performed."
    }

    $xvlog = Join-Path $vivado "xvlog.bat"
    $xelab = Join-Path $vivado "xelab.bat"
    $xsim = Join-Path $vivado "xsim.bat"

    # A small deterministic spread across the test set. Includes index 0 and several varied labels.
    foreach ($index in @(0,1,2,3,4,5,10,25,50,100)) {
        Write-Host "`n===== Day 9: MNIST test index $index =====" -ForegroundColor Cyan
        $patchedExporter = $originalExporter.Replace(
            $selectedLine,
            "selected = $index"
        )
        Set-Content -Path $exporter -Value $patchedExporter -Encoding utf8

        & python $exporter 2>&1 | Tee-Object -FilePath $runLog -Append
        if ($LASTEXITCODE -ne 0) { throw "MNIST export failed for index $index." }

        $info = Get-Content $imageInfo -Raw
        if ($info -notmatch "(?m)^index=$index\s*$") {
            throw "Exporter metadata index does not match requested index $index."
        }
        $labelMatch = [regex]::Match($info, '(?m)^label=(\d+)\s*$')
        if (!$labelMatch.Success) { throw "Could not read ground-truth label for index $index." }
        $label = [int]$labelMatch.Groups[1].Value

        # Regenerate every input-dependent reference/ROM in dependency order.
        & python scripts\generate_conv2_reference.py 2>&1 | Tee-Object -FilePath $runLog -Append
        if ($LASTEXITCODE -ne 0) { throw "Conv2 reference generation failed at index $index." }
        & python scripts\prepare_fc1_reference.py 2>&1 | Tee-Object -FilePath $runLog -Append
        if ($LASTEXITCODE -ne 0) { throw "FC1 reference generation failed at index $index." }
        & python scripts\prepare_fc2_reference.py 2>&1 | Tee-Object -FilePath $runLog -Append
        if ($LASTEXITCODE -ne 0) { throw "FC2 reference generation failed at index $index." }

        $status = Join-Path $root "cnn_rtl_run_status.txt"
        $scores = Join-Path $root "cnn_rtl_final_scores.txt"
        Remove-Item $status,$scores -Force -ErrorAction SilentlyContinue

        # Compile only the explicitly required RTL files; exclude the duplicate backup module.
        & $xvlog -sv -work xil_defaultlib `
            rtl\conv1_shared_mac.v rtl\conv1_full_layer.v rtl\conv1_requantize.v `
            rtl\conv2_shared_mac.v rtl\conv2_full_layer.v rtl\conv2_requantize.v `
            rtl\fc1_shared_mac.v rtl\fc1_full_layer.v rtl\fc1_requantize.v `
            rtl\fc2_shared_mac.v rtl\fc2_full_layer.v rtl\cnn_integrated_sim_top.v `
            tb\tb_cnn_integrated_validation.v 2>&1 | Tee-Object -FilePath $runLog -Append
        if ($LASTEXITCODE -ne 0) { throw "xvlog compile failed at index $index." }

        & $xelab xil_defaultlib.tb_cnn_integrated_validation -s day9_batch_sim 2>&1 |
            Tee-Object -FilePath $runLog -Append
        if ($LASTEXITCODE -ne 0) { throw "xelab failed at index $index." }

        & $xsim day9_batch_sim -runall 2>&1 | Tee-Object -FilePath $runLog -Append
        if ($LASTEXITCODE -ne 0) { throw "XSim failed at index $index." }

        if (!(Test-Path $status)) { throw "No fresh simulation status file for index $index." }
        $statusText = (Get-Content $status -Raw).Trim()
        if ($statusText -ne "PASS") { throw "Simulation status is '$statusText' at index $index." }
        if (!(Test-Path $scores)) { throw "No fresh score file for index $index." }

        # Parse and compare all ten scores without relying on stale output.
        $refPath = Join-Path $root "fc2_reference_scores.txt"
        $ref = @(Get-Content $refPath | Where-Object { $_.Trim() -ne "" } | ForEach-Object { [long]$_.Trim() })
        $rtlRows = @(Get-Content $scores | ForEach-Object {
            $parts = $_.Trim() -split '\s+'
            if ($parts.Count -eq 2) { [pscustomobject]@{ Class=[int]$parts[0]; Score=[long]$parts[1] } }
        } | Where-Object { $null -ne $_ })
        if ($ref.Count -ne 10 -or $rtlRows.Count -ne 10) {
            throw "Score count mismatch at index $index (reference=$($ref.Count), RTL=$($rtlRows.Count))."
        }
        $mismatches = 0
        for ($c=0; $c -lt 10; $c++) {
            if ($rtlRows[$c].Class -ne $c -or $rtlRows[$c].Score -ne $ref[$c]) { $mismatches++ }
        }
        $pyPred = 0
        $rtlPred = 0
        for ($c=1; $c -lt 10; $c++) {
            if ($ref[$c] -gt $ref[$pyPred]) { $pyPred = $c }
            if ($rtlRows[$c].Score -gt $rtlRows[$rtlPred].Score) { $rtlPred = $c }
        }
        $pass = ($mismatches -eq 0 -and $pyPred -eq $rtlPred)
        if (!$pass) { $allPassed = $false }
        $rows.Add([pscustomobject]@{
            Index=$index; Label=$label; PythonPrediction=$pyPred; RTLPrediction=$rtlPred
            ScoreMismatches=$mismatches; SimulationStatus=$statusText
            Result=if ($pass) { "PASS" } else { "FAIL" }
        })
        $rows | Export-Csv -Path $resultsPath -NoTypeInformation
        Write-Host "Index=$index Label=$label Python=$pyPred RTL=$rtlPred ScoreMismatches=$mismatches Result=$($rows[$rows.Count-1].Result)"
        if (!$pass) { throw "Numerical mismatch found at MNIST index $index. Stopping batch to preserve diagnosability." }
    }
}
finally {
    # Restore source exporter and original image ROM/metadata even if a run fails.
    if (Test-Path $exporterBackup) { Copy-Item $exporterBackup $exporter -Force; Remove-Item $exporterBackup -Force }
    if (Test-Path $imageBackup) { Copy-Item $imageBackup $imageRom -Force; Remove-Item $imageBackup -Force }
    if (Test-Path $infoBackup) { Copy-Item $infoBackup $imageInfo -Force; Remove-Item $infoBackup -Force }
}

Write-Host "`n===== DAY 9 BATCH SUMMARY =====" -ForegroundColor Cyan
$rows | Format-Table -AutoSize
Write-Host "CSV: $resultsPath"
Write-Host "Log: $runLog"
if (!$allPassed -or $rows.Count -ne 10) { throw "Day 9 batch validation did not complete with all ten PASS results." }
Write-Host "DAY 9 COMPLETE: all ten images matched all ten RTL scores." -ForegroundColor Green

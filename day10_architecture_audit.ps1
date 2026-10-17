$ErrorActionPreference = "Stop"

$Root = "D:\FPGA_EdgeAI\cnn_baseline"
$OutFile = Join-Path $Root "day10_architecture_audit.txt"

if (-not (Test-Path $Root)) {
    Write-Host "ERROR: Project root not found: $Root" -ForegroundColor Red
    Write-Host "Edit the `$Root line in this script if your project is stored elsewhere."
    exit 1
}

$FilesToInspect = @(
    "rtl\cnn_integrated_sim_top.v",
    "rtl\conv1_full_layer.v",
    "rtl\conv1_shared_mac.v",
    "rtl\conv1_requantize.v",
    "rtl\conv2_full_layer.v",
    "rtl\conv2_shared_mac.v",
    "rtl\conv2_requantize.v",
    "rtl\fc1_full_layer.v",
    "rtl\fc1_shared_mac.v",
    "rtl\fc1_requantize.v",
    "rtl\fc2_full_layer.v",
    "rtl\fc2_shared_mac.v",
    "tb\tb_cnn_integrated_validation.v"
)

$Report = New-Object System.Collections.Generic.List[string]
$Report.Add("DAY 10 CNN RTL ARCHITECTURE AUDIT")
$Report.Add("Project root: $Root")
$Report.Add("Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
$Report.Add("")
$Report.Add("PURPOSE: Read-only inspection. This script does not modify RTL or ROM files.")
$Report.Add("")

foreach ($Relative in $FilesToInspect) {
    $Path = Join-Path $Root $Relative
    $Report.Add(("=" * 88))
    $Report.Add("FILE: $Relative")
    $Report.Add(("=" * 88))

    if (-not (Test-Path $Path)) {
        $Report.Add("STATUS: MISSING")
        $Report.Add("")
        continue
    }

    $Lines = Get-Content -LiteralPath $Path
    $Report.Add("STATUS: FOUND ($($Lines.Count) lines)")
    $Report.Add("-- Module declarations / ports --")
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -match '^\s*module\b' -or
            $Lines[$i] -match '^\s*(input|output|inout)\b' -or
            $Lines[$i] -match '^\s*\);?\s*$') {
            $Report.Add(("{0,5}: {1}" -f ($i + 1), $Lines[$i]))
        }
    }

    $Report.Add("-- Potential integration / synthesis concerns --")
    $FoundConcern = $false
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        $Line = $Lines[$i]
        if ($Line -match '\b[a-zA-Z_]\w*\s*\.\s*[a-zA-Z_]\w*\s*\[' -or
            $Line -match '\b(c1|c2|f1|f2)\s*\.\s*(input_map|output_map|weights|biases|mem)\b' -or
            $Line -match '\$readmemh|\$fopen|\$fscanf|\$display|\$write' -or
            $Line -match 'force\b|release\b|#\s*\d+') {
            $Report.Add(("{0,5}: {1}" -f ($i + 1), $Line.Trim()))
            $FoundConcern = $true
        }
    }
    if (-not $FoundConcern) {
        $Report.Add("No matches for the selected patterns.")
    }

    if ($Relative -eq "rtl\cnn_integrated_sim_top.v") {
        $Report.Add("-- Full integration top (for design review) --")
        for ($i = 0; $i -lt $Lines.Count; $i++) {
            $Report.Add(("{0,5}: {1}" -f ($i + 1), $Lines[$i]))
        }
    }
    $Report.Add("")
}

$Report.Add(("=" * 88))
$Report.Add("AUDIT COMPLETE")
$Report.Add("No source files were changed.")
$Report | Set-Content -LiteralPath $OutFile -Encoding UTF8

Write-Host ""
Write-Host "Day 10 read-only audit complete." -ForegroundColor Green
Write-Host "Report: $OutFile"
Write-Host "No RTL files were modified."
Write-Host ""
Write-Host "Next: open day10_architecture_audit.txt and paste its contents here, or attach the report."

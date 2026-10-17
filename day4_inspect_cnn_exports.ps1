$ErrorActionPreference = "Stop"
$root = "D:\FPGA_EdgeAI\cnn_baseline"
Set-Location $root

$manifest = Join-Path $root "outputs\rtl_params\manifest.json"
$report = Join-Path $root "outputs\rtl_params\cnn_export_inspection.txt"
$paramDir = Join-Path $root "outputs\rtl_params"

if (-not (Test-Path $manifest)) {
    throw "Manifest not found: $manifest. No RTL files were modified. Check the model export directory."
}

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("CNN EXPORT INSPECTION")
$lines.Add("Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
$lines.Add("Project root: $root")
$lines.Add("")
$lines.Add("=== manifest.json ===")
$manifestText = Get-Content $manifest -Raw
$lines.Add($manifestText)
$lines.Add("")
$lines.Add("=== Parameter files ===")

$expected = @(
 "conv1_weights_int8.txt","conv1_bias_int32.txt",
 "conv2_weights_int8.txt","conv2_bias_int32.txt",
 "fc1_weights_int8.txt","fc1_bias_int32.txt",
 "fc2_weights_int8.txt","fc2_bias_int32.txt"
)

foreach ($name in $expected) {
    $matches = Get-ChildItem $paramDir -Recurse -File -Filter $name -ErrorAction SilentlyContinue
    if (-not $matches) {
        $lines.Add("MISSING: $name")
    } else {
        foreach ($f in $matches) {
            $lines.Add(("FOUND: {0} | bytes={1} | lines={2}" -f $f.FullName,$f.Length,(Get-Content $f.FullName | Measure-Object -Line).Lines))
            $sample = Get-Content $f.FullName -TotalCount 4
            $lines.Add("  first values: $($sample -join ', ')")
        }
    }
}
$lines.Add("")
$lines.Add("=== Relevant model/export files ===")
$searchRoots = @("outputs","experiments","scripts","models")
foreach ($relative in $searchRoots) {
    $dir = Join-Path $root $relative
    if (Test-Path $dir) {
        $files = Get-ChildItem $dir -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match 'manifest|quant|scale|export|model|mnist|checkpoint|state_dict|weights|bias' } |
            Select-Object -First 100
        foreach ($f in $files) {
            $lines.Add(("FILE: {0} | bytes={1}" -f $f.FullName,$f.Length))
        }
    }
}
$lines.Add("")
$lines.Add("=== Existing Conv1 test artifacts ===")
foreach ($name in @("rom\conv1_image_info.txt","conv1_rtl_outputs.txt","conv1_rtl_activations.txt","rom\conv1_image_u8_hex.mem")) {
    $f = Join-Path $root $name
    if (Test-Path $f) {
        $item = Get-Item $f
        $lines.Add(("FOUND: {0} | bytes={1}" -f $name,$item.Length))
        if ($name -eq "rom\conv1_image_info.txt") {
            $lines.Add((Get-Content $f -Raw))
        }
    } else {
        $lines.Add("MISSING: $name")
    }
}

$lines | Set-Content $report -Encoding utf8
$lines | ForEach-Object { Write-Output $_ }
Write-Output ""
Write-Output "Inspection report saved to: $report"
Write-Output "No RTL, weights, biases, or ROM files were modified."

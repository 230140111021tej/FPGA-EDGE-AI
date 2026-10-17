$ErrorActionPreference = "Stop"
$Root = "D:\FPGA_EdgeAI\cnn_baseline"
Set-Location $Root
$Out = Join-Path $Root "day10_fc1_stall_report.txt"
$files = @(
  "rtl\fc1_full_layer.v",
  "rtl\fc1_shared_mac.v",
  "rtl\fc1_requantize.v",
  "rtl\cnn_integrated_sim_top.v",
  "rtl\cnn_integrated_fc2_hw_top.v"
)
"DAY 10 FC1 STALL INSPECTION" | Set-Content $Out
"Generated: $(Get-Date -Format s)" | Add-Content $Out
foreach ($rel in $files) {
  $path = Join-Path $Root $rel
  "`r`n===== $rel =====" | Add-Content $Out
  if (!(Test-Path $path)) { "MISSING FILE" | Add-Content $Out; continue }
  $lines = Get-Content $path
  for ($i=0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match 'module |parameter|input |output |reg .*state|integer |reg .*count|reg .*idx|reg .*index|always|case\s*\(|default|start|busy|done|valid|count|index|idx|state|accum|mac|counter|endcase|endmodule|phase<=5|phase<=6|5:\s|6:\s') {
      "{0,4}: {1}" -f ($i+1), $lines[$i] | Add-Content $Out
    }
  }
}
"`r`n===== FC1 SIGNAL DECLARATIONS (TOP) =====" | Add-Content $Out
$topPath = Join-Path $Root "rtl\cnn_integrated_sim_top.v"
$topLines = Get-Content $topPath
for ($i=0; $i -lt $topLines.Count; $i++) {
  if ($topLines[$i] -match 'fc1_full_layer|f1\(|f1_start|f1_busy|f1_done|f1_valid|f1_acc|phase|wait_count') {
    "{0,4}: {1}" -f ($i+1), $topLines[$i] | Add-Content $Out
  }
}
Write-Host "Created read-only inspection report: $Out"
Write-Host "Open it and paste the contents here."

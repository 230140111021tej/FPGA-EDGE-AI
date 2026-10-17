$ErrorActionPreference = "Stop"
$Root = "D:\FPGA_EdgeAI\cnn_baseline"
Set-Location $Root
$Out = Join-Path $Root "day10_fc2_top_debug_dump.txt"
"DAY10 FC2 TOP DEBUG DUMP" | Set-Content $Out
"`n=== TESTBENCH ===" | Add-Content $Out
$tb = Join-Path $Root "tb\tb_cnn_fc2_hw_top_compare.v"
if (Test-Path $tb) {
    $n = 0
    Get-Content $tb | ForEach-Object { $n++; "{0,4}: {1}" -f $n, $_ } | Add-Content $Out
} else { "MISSING: $tb" | Add-Content $Out }
"`n=== BASELINE TOP: FSM / START / DONE / PHASE REFERENCES ===" | Add-Content $Out
$topFiles = @(
  (Join-Path $Root "rtl\cnn_integrated_sim_top.v"),
  (Join-Path $Root "rtl\cnn_integrated_fc2_hw_top.v")
)
foreach ($file in $topFiles) {
    "`n--- $file ---" | Add-Content $Out
    if (Test-Path $file) {
        $n = 0
        Get-Content $file | ForEach-Object {
            $n++
            if ($_ -match 'always|case\s*\(|phase|state|start|done|rst|reset|default|endcase|endmodule|f2_input') {
                "{0,4}: {1}" -f $n, $_ | Add-Content $Out
            }
        }
    } else { "MISSING: $file" | Add-Content $Out }
}
"`n=== SIMULATION LOG TAIL ===" | Add-Content $Out
$log = Join-Path $Root "day10_fc2_top_compare.log"
if (Test-Path $log) { Get-Content $log -Tail 100 | Add-Content $Out }
Write-Host "Created diagnostic dump: $Out"
Write-Host "Open it and paste its contents here. This script does not modify RTL or testbench files."

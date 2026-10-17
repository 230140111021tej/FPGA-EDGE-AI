set root [file normalize "."]
set out [file join $root experiments controlled_compare baseline]

file mkdir $out

read_verilog [file join $root rtl mac_unit.v]
read_verilog [file join $root rtl mac_demo_top.v]

read_xdc [file join $root constraints basys3_mac_demo.xdc]
read_xdc [file join $root mac_timing.xdc]

synth_design -top mac_demo_top -part xc7a35tcpg236-1

report_utilization -file [file join $out utilization_synth.rpt]
report_timing_summary -delay_type min_max -report_unconstrained \
    -file [file join $out timing_synth.rpt]

opt_design
place_design
phys_opt_design
route_design

report_utilization -file [file join $out utilization_routed.rpt]
report_timing_summary -delay_type min_max -report_unconstrained \
    -file [file join $out timing_routed.rpt]
report_route_status -file [file join $out route_status.rpt]

write_checkpoint -force [file join $out baseline_routed.dcp]
write_bitstream -force [file join $out mac_demo_top_baseline.bit]

exit

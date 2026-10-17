set root [file normalize "experiments/dsp_inference"]
set project_root [file normalize "."]

set reports [file join $root reports]
set bitstream_dir [file join $root bitstream]

file mkdir $reports
file mkdir $bitstream_dir

read_verilog [file join $root rtl mac_unit.v]
read_verilog [file join $root rtl mac_demo_top.v]

read_xdc [file join $project_root constraints basys3_mac_demo.xdc]
read_xdc [file join $project_root mac_timing.xdc]

synth_design -top mac_demo_top -part xc7a35tcpg236-1

opt_design
place_design
phys_opt_design
route_design

report_utilization \
    -file [file join $reports dsp_utilization_routed.rpt]

report_timing_summary -delay_type min_max \
    -report_unconstrained \
    -file [file join $reports dsp_timing_summary_routed.rpt]

report_route_status \
    -file [file join $reports dsp_route_status.rpt]

write_checkpoint -force \
    [file join $reports dsp_routed.dcp]

write_bitstream -force \
    [file join $bitstream_dir mac_demo_top_dsp.bit]

exit

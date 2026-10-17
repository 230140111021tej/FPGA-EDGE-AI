set root [file normalize "experiments/dsp_inference"]
set out  [file join $root reports]
file mkdir $out

read_verilog [file join $root rtl mac_unit.v]
read_verilog [file join $root rtl mac_demo_top.v]

synth_design -top mac_demo_top -part xc7a35tcpg236-1

report_utilization -file [file join $out forced_dsp_utilization.rpt]
write_checkpoint -force [file join $out forced_dsp_synth.dcp]

exit

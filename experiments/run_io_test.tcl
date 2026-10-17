set root {D:/FPGA_EdgeAI/cnn_baseline}
set out [file join $root experiments io_test]
file mkdir $out

read_verilog [file join $root rtl mac_io_test.v]
read_xdc [file join $root constraints mac_io_test.xdc]

synth_design -top mac_io_test -part xc7a35tcpg236-1
opt_design
place_design
route_design

report_io -file [file join $out io_report.rpt]
report_route_status -file [file join $out route_status.rpt]
write_bitstream -force [file join $out mac_io_test.bit]

exit

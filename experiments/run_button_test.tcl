set root {D:/FPGA_EdgeAI/cnn_baseline}
set out [file join $root experiments button_test]
file mkdir $out

read_verilog [file join $root rtl mac_button_test.v]
read_xdc [file join $root constraints mac_button_test.xdc]

synth_design -top mac_button_test -part xc7a35tcpg236-1
opt_design
place_design
route_design
write_bitstream -force [file join $out mac_button_test.bit]
exit

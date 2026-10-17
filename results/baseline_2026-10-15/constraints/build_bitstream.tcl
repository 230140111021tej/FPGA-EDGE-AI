set project_file "D:/FPGA_EdgeAI/cnn_baseline/vivado_output/cnn_mac_baseline/cnn_mac_baseline.xpr"

open_project $project_file
set_property top mac_demo_top [get_filesets sources_1]

puts "=== RESET OLD RUNS ==="
reset_run synth_1
reset_run impl_1

puts "=== RUN SYNTHESIS ==="
launch_runs synth_1 -jobs 4
wait_on_run synth_1

set synth_status [get_property STATUS [get_runs synth_1]]
puts "SYNTHESIS STATUS: $synth_status"

if {![string match "*Complete*" $synth_status]} {
    error "Synthesis failed or did not complete. Check the synth_1 run log."
}

puts "=== RUN IMPLEMENTATION AND BITSTREAM ==="
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

set impl_status [get_property STATUS [get_runs impl_1]]
puts "IMPLEMENTATION STATUS: $impl_status"

if {![string match "*Complete*" $impl_status]} {
    error "Implementation or bitstream generation failed. Check the impl_1 run log."
}

puts "=== BUILD FINISHED ==="
close_project

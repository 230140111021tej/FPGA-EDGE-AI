set project_file "D:/FPGA_EdgeAI/cnn_baseline/vivado_output/cnn_mac_baseline/cnn_mac_baseline.xpr"
set board_xdc "D:/FPGA_EdgeAI/cnn_baseline/constraints/basys3_mac_demo.xdc"
set duplicate_timing_xdc "D:/FPGA_EdgeAI/cnn_baseline/mac_timing.xdc"

open_project $project_file

set_property top mac_demo_top [get_filesets sources_1]

# Remove the duplicate root-level timing constraint, if present.
set duplicate_file [get_files -quiet $duplicate_timing_xdc]
if {[llength $duplicate_file] > 0} {
    remove_files $duplicate_file
}

# Add the Basys 3 pin constraints if they are not already included.
if {[llength [get_files -quiet $board_xdc]] == 0} {
    add_files -fileset constrs_1 $board_xdc
}

set_property used_in_synthesis true [get_files $board_xdc]
set_property used_in_implementation true [get_files $board_xdc]

update_compile_order -fileset sources_1

puts "=== TOP ==="
puts [get_property top [get_filesets sources_1]]
puts "=== CONSTRAINT FILES ==="
puts [get_files -of_objects [get_filesets constrs_1]]

close_project

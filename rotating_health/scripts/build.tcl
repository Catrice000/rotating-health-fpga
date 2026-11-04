set root [file normalize [file join [file dirname [info script]] ..]]
cd $root
create_project -force rotating_health [file join $root build vivado_control] -part xa7a35tcsg324-1I
set_property XPM_LIBRARIES {XPM_MEMORY} [current_project]
set_property target_language Verilog [current_project]
add_files [glob [file join $root rtl *.v]]
set_property file_type SystemVerilog [get_files *.v]
add_files [glob [file join $root rtl *.hex]]
add_files -fileset constrs_1 [file join $root constraints ego1.xdc]
set_property top health_top [current_fileset]
# Override with -tclargs 4000 after a measured revolution if needed.
set ppr 4096
if {[llength $argv] > 0} {set ppr [lindex $argv 0]}
set_property generic PPR=$ppr [current_fileset]
set cfg [open [file join $root config.json] w]
puts $cfg "{\"ppr\": $ppr, \"sample_rate\": 200, \"fft_size\": 256, \"baud\": 230400}"
close $cfg
update_compile_order -fileset sources_1
launch_runs synth_1 -jobs 2
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {error "Synthesis failed"}
launch_runs impl_1 -to_step write_bitstream -jobs 2
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {error "Implementation failed"}
open_run impl_1
report_timing_summary -file [file join $root build timing.txt]
report_utilization -file [file join $root build utilization.txt]
report_drc -file [file join $root build drc.txt]
set worst [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
if {$worst < 0} {error "Setup timing is not met: $worst"}
set worst_hold [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]
if {$worst_hold < 0} {error "Hold timing is not met: $worst_hold"}
write_bitstream -force [file join $root build rotating_health.bit]
close_project


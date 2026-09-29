# Non-project PL-only build. Run from any directory; no board IP install needed.
set root [file normalize [file join [file dirname [info script]] ..]]
cd $root
set shell [info exists ::env(SHELL_BUILD)]
set out [file join $root build [expr {$shell ? "zcu104_shell" : "zcu104"}]]
file mkdir $out
set_param general.maxThreads 4
foreach name {rv32_alu rv32_regfile rv32_csr rv32_core simple_timer rv32_soc uart_tx uart_rx zcu104_top} {
    read_verilog [file join $root rtl ${name}.v]
}
read_xdc [file join $root constraints zcu104.xdc]
if {$shell} {
    synth_design -top zcu104_top -part xczu7ev-ffvc1156-2-e -generic SHELL_MODE=1 -flatten_hierarchy rebuilt
} else {
    synth_design -top zcu104_top -part xczu7ev-ffvc1156-2-e -flatten_hierarchy rebuilt
}
write_checkpoint -force [file join $out post_synth.dcp]
report_utilization -file [file join $out utilization_synth.rpt]
opt_design
place_design
phys_opt_design
route_design
write_checkpoint -force [file join $out post_route.dcp]
report_timing_summary -delay_type min_max -report_unconstrained -file [file join $out timing_summary.rpt]
report_utilization -file [file join $out utilization_route.rpt]
report_drc -file [file join $out drc.rpt]
report_io -file [file join $out io.rpt]
# Refuse a bitstream if an internal setup or hold check fails.
foreach delay {max min} {
    set paths [get_timing_paths -delay_type $delay -max_paths 1]
    if {[llength $paths] == 0} {error "No $delay timing paths found"}
    if {[get_property SLACK [lindex $paths 0]] < 0} {error "$delay timing failed; see timing_summary.rpt"}
}
write_bitstream -force [file join $out [expr {$shell ? "zcu104_mini_shell.bit" : "zcu104_mini_os.bit"}]]
puts "PASS: ZCU104 Mini OS bitstream built with setup/hold checks passing"

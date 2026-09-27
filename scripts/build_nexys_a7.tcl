set root [file normalize [file join [file dirname [info script]] ..]]
set out  [file join $root build vivado]
file mkdir $out

read_verilog [glob [file join $root rtl *.v]]
read_xdc [file join $root constraints nexys_a7_100t.xdc]

synth_design -top nexys_a7_top -part xc7a100tcsg324-1 -flatten_hierarchy rebuilt
write_checkpoint -force [file join $out post_synth.dcp]
report_utilization -file [file join $out utilization_synth.rpt]

opt_design
place_design
phys_opt_design
route_design
write_checkpoint -force [file join $out post_route.dcp]
report_timing_summary -file [file join $out timing_summary.rpt]
report_utilization -file [file join $out utilization_route.rpt]
write_bitstream -force [file join $out nexys_a7_rv32i.bit]

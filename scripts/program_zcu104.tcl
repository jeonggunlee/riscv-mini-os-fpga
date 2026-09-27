# Programs only volatile PL configuration, never flash or ARM firmware.
# With multiple cables connected, require an explicit HW_TARGET filter.
set root [file normalize [file join [file dirname [info script]] ..]]
set bitfile [file join $root build zcu104 zcu104_mini_os.bit]
if {![file exists $bitfile]} {error "Run make vivado-zcu104 first"}
open_hw_manager
connect_hw_server -url localhost:3121
set targets [get_hw_targets -quiet]
if {[info exists ::env(HW_TARGET)]} {set targets [get_hw_targets -quiet $::env(HW_TARGET)]}
if {[llength $targets] != 1} {error "Expected one cable; set HW_TARGET to select it"}
current_hw_target [lindex $targets 0]
open_hw_target
set devices [get_hw_devices -quiet xczu7_0]
if {[llength $devices] != 1} {error "Expected ZCU104 xczu7_0; refusing to program another device"}
set dev [lindex $devices 0]
current_hw_device $dev
set_property PROGRAM.FILE $bitfile $dev
program_hw_devices $dev
refresh_hw_device $dev
puts "PROGRAMMED_DEVICE=$dev"
puts "PROGRAMMED_BITSTREAM=$bitfile"
report_property $dev
close_hw_target
disconnect_hw_server
close_hw_manager

set root [file normalize [file join [file dirname [info script]] ..]]
set bitfile [file join $root build vivado nexys_a7_rv32i.bit]

open_hw_manager
connect_hw_server
open_hw_target
set dev [lindex [get_hw_devices xc7a100t_0] 0]
if {$dev eq ""} { error "Nexys A7-100T (xc7a100t_0) not found" }
current_hw_device $dev
refresh_hw_device $dev
set_property PROGRAM.FILE $bitfile $dev
program_hw_devices $dev

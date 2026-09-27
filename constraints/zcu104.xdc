# ZCU104 XCZU7EV-2FFVC1156, UG1267 schematic and tables 3-18/3-24.
# Cross-checked with XilinxBoardStore/2022.1/boards/Xilinx/zcu104/1.1/part0_pins.xml.
# UART direction follows the schematic Fig 3-13 and official board XML:
# FPGA TX = C19; A20 is FPGA RX, not TX (table 3-18 FTDI columns are reversed).
set_property -dict {PACKAGE_PIN AH18 IOSTANDARD DIFF_SSTL12} [get_ports CLK_300_P]
set_property -dict {PACKAGE_PIN AH17 IOSTANDARD DIFF_SSTL12} [get_ports CLK_300_N]
create_clock -name clk_300 -period 3.333333 [get_ports CLK_300_P]
create_generated_clock -name cpu_clk -source [get_ports CLK_300_P] \
    -divide_by 24 [get_pins cpu_clk_buf/O]

set_property -dict {PACKAGE_PIN M11 IOSTANDARD LVCMOS33} [get_ports CPU_RESET]
set_property -dict {PACKAGE_PIN C19 IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 8} [get_ports UART_TX]
set_property -dict {PACKAGE_PIN D5 IOSTANDARD LVCMOS33} [get_ports {LED[0]}]
set_property -dict {PACKAGE_PIN D6 IOSTANDARD LVCMOS33} [get_ports {LED[1]}]
set_property -dict {PACKAGE_PIN A5 IOSTANDARD LVCMOS33} [get_ports {LED[2]}]
set_property -dict {PACKAGE_PIN B5 IOSTANDARD LVCMOS33} [get_ports {LED[3]}]

# Asynchronous pushbutton and human/baud-rate outputs have no external
# synchronous capture clock. Do not cut ANY internal CPU or memory paths.
set_false_path -from [get_ports CPU_RESET]
set_false_path -to [get_ports {UART_TX LED[*]}]

## =============================================================================
## constraints.xdc
## Basys 3 Pin Constraints for OV7670 Camera UART Test
## =============================================================================

## --- System Clock (100MHz) ---
set_property PACKAGE_PIN W5 [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports clk]
create_clock -period 10.000 -name sys_clk [get_ports clk]

## --- Reset Button (Center) ---
set_property PACKAGE_PIN T17 [get_ports btnC]
set_property IOSTANDARD LVCMOS33 [get_ports btnC]

## =============================================================================
## OV7670 Camera Pins (connected via Pmod headers)
## Based on pin table in project spec
## =============================================================================

## Camera Data Bus D[7:0]
set_property PACKAGE_PIN P17 [get_ports {cam_data[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {cam_data[0]}]

set_property PACKAGE_PIN N17 [get_ports {cam_data[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {cam_data[1]}]

set_property PACKAGE_PIN M19 [get_ports {cam_data[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {cam_data[2]}]

set_property PACKAGE_PIN M18 [get_ports {cam_data[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {cam_data[3]}]

set_property PACKAGE_PIN L17 [get_ports {cam_data[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {cam_data[4]}]

set_property PACKAGE_PIN K17 [get_ports {cam_data[5]}]
set_property IOSTANDARD LVCMOS33 [get_ports {cam_data[5]}]

set_property PACKAGE_PIN C16 [get_ports {cam_data[6]}]
set_property IOSTANDARD LVCMOS33 [get_ports {cam_data[6]}]

set_property PACKAGE_PIN B16 [get_ports {cam_data[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {cam_data[7]}]

## HREF
set_property PACKAGE_PIN A17 [get_ports cam_href]
set_property IOSTANDARD LVCMOS33 [get_ports cam_href]

## PCLK
set_property PACKAGE_PIN A16 [get_ports cam_pclk]
set_property IOSTANDARD LVCMOS33 [get_ports cam_pclk]

## PWDN
set_property PACKAGE_PIN R18 [get_ports cam_pwdn]
set_property IOSTANDARD LVCMOS33 [get_ports cam_pwdn]

## RST
set_property PACKAGE_PIN P18 [get_ports cam_rst]
set_property IOSTANDARD LVCMOS33 [get_ports cam_rst]

## SCL
set_property PACKAGE_PIN A14 [get_ports cam_scl]
set_property IOSTANDARD LVCMOS33 [get_ports cam_scl]

## SDA
set_property PACKAGE_PIN A15 [get_ports cam_sda]
set_property IOSTANDARD LVCMOS33 [get_ports cam_sda]

## VSYNC
set_property PACKAGE_PIN B15 [get_ports cam_vsync]
set_property IOSTANDARD LVCMOS33 [get_ports cam_vsync]

## XCLK
set_property PACKAGE_PIN C15 [get_ports cam_xclk]
set_property IOSTANDARD LVCMOS33 [get_ports cam_xclk]

## =============================================================================
## UART TX (USB-UART bridge, built into Basys 3)
## =============================================================================
set_property PACKAGE_PIN A18 [get_ports uart_txd]
set_property IOSTANDARD LVCMOS33 [get_ports uart_txd]

## =============================================================================
## LEDs
## =============================================================================
set_property PACKAGE_PIN U16 [get_ports {led[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[0]}]

set_property PACKAGE_PIN E19 [get_ports {led[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[1]}]

set_property PACKAGE_PIN U19 [get_ports {led[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[2]}]

set_property PACKAGE_PIN V19 [get_ports {led[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[3]}]

set_property PACKAGE_PIN W18 [get_ports {led[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[4]}]

set_property PACKAGE_PIN U15 [get_ports {led[5]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[5]}]

set_property PACKAGE_PIN U14 [get_ports {led[6]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[6]}]

set_property PACKAGE_PIN V14 [get_ports {led[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[7]}]

set_property PACKAGE_PIN V13 [get_ports {led[8]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[8]}]

set_property PACKAGE_PIN V3  [get_ports {led[9]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[9]}]

set_property PACKAGE_PIN W3  [get_ports {led[10]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[10]}]

set_property PACKAGE_PIN U3  [get_ports {led[11]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[11]}]

set_property PACKAGE_PIN P3  [get_ports {led[12]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[12]}]

set_property PACKAGE_PIN N3  [get_ports {led[13]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[13]}]

set_property PACKAGE_PIN P1  [get_ports {led[14]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[14]}]

set_property PACKAGE_PIN L1  [get_ports {led[15]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[15]}]

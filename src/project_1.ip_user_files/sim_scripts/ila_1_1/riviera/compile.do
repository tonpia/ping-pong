transcript off
onbreak {quit -force}
onerror {quit -force}
transcript on

vlib work
vlib riviera/xpm
vlib riviera/xil_defaultlib

vmap xpm riviera/xpm
vmap xil_defaultlib riviera/xil_defaultlib

vlog -work xpm  -incr "+incdir+../../../../../../vivado/2025.2/data/rsb/busdef" "+incdir+../../../../project_1.gen/sources_1/ip/ila_1_1/hdl/verilog" -l xpm -l xil_defaultlib \
"/home/splexmus/Documents/vivado/2025.2/data/ip/xpm/xpm_cdc/hdl/xpm_cdc.sv" \
"/home/splexmus/Documents/vivado/2025.2/data/ip/xpm/xpm_memory/hdl/xpm_memory.sv" \

vcom -work xpm -93  -incr \
"/home/splexmus/Documents/vivado/2025.2/data/ip/xpm/xpm_VCOMP.vhd" \

vlog -work xil_defaultlib  -incr -v2k5 "+incdir+../../../../../../vivado/2025.2/data/rsb/busdef" "+incdir+../../../../project_1.gen/sources_1/ip/ila_1_1/hdl/verilog" -l xpm -l xil_defaultlib \
"../../../../project_1.gen/sources_1/ip/ila_1_1/sim/ila_1.v" \

vlog -work xil_defaultlib \
"glbl.v"


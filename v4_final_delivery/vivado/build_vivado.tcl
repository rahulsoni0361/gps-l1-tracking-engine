set project_name "tracker_project_v4"
set project_dir "D:/pclient/gps/v3_hls_to_vhdl/vivado/$project_name"
set vhdl_src_dir "D:/pclient/gps/v3_hls_to_vhdl/native_vhdl"
set ip_repo_dir "D:/pclient/gps/v3_hls_to_vhdl/vivado/ip_repo"
set deploy_dir "D:/pclient/gps/v3_hls_to_vhdl/deploy"

# 1. Package the scrubbed VHDL as an IP Core
create_project -force ip_pkg_project $ip_repo_dir/ip_pkg_project -part xc7z020clg400-1
add_files $vhdl_src_dir
set_property USED_IN {simulation} [get_files $vhdl_src_dir/tb_gps_tracker.vhd]
set_property top gps_tracker [current_fileset]
update_compile_order -fileset sources_1
# Package the IP
ipx::package_project -root_dir $ip_repo_dir/gps_tracker_ip -vendor xilinx.com -library user -taxonomy /UserIP -import_files -set_current false
ipx::unload_core $ip_repo_dir/gps_tracker_ip/component.xml
ipx::edit_ip_in_project -upgrade true -name tmp_edit_project -directory $ip_repo_dir/gps_tracker_ip $ip_repo_dir/gps_tracker_ip/component.xml
ipx::current_core $ip_repo_dir/gps_tracker_ip/component.xml
set core [ipx::current_core]

# Fix Clock associations
ipx::add_bus_parameter ASSOCIATED_BUSIF [ipx::get_bus_interfaces ap_clk -of_objects $core]
set_property value "sample_in:s_axi_config:s_axi_status" [ipx::get_bus_parameters ASSOCIATED_BUSIF -of_objects [ipx::get_bus_interfaces ap_clk -of_objects $core]]
ipx::add_bus_parameter ASSOCIATED_RESET [ipx::get_bus_interfaces ap_clk -of_objects $core]
set_property value "ap_rst_n" [ipx::get_bus_parameters ASSOCIATED_RESET -of_objects [ipx::get_bus_interfaces ap_clk -of_objects $core]]

# Remove FREQ_HZ
foreach bus_intf [ipx::get_bus_interfaces -of_objects $core] {
    if { [llength [ipx::get_bus_parameters FREQ_HZ -of_objects $bus_intf -quiet]] > 0 } {
        ipx::remove_bus_parameter FREQ_HZ $bus_intf
    }
}

# Fix memory map names to prevent Vivado from excluding identically named blocks
set_property name "reg_status" [ipx::get_address_blocks reg0 -of_objects [ipx::get_memory_maps s_axi_status -of_objects $core]]
set_property name "reg_config" [ipx::get_address_blocks reg0 -of_objects [ipx::get_memory_maps s_axi_config -of_objects $core]]

set_property range 4096 [ipx::get_address_blocks reg_status -of_objects [ipx::get_memory_maps s_axi_status -of_objects $core]]
set_property range 4096 [ipx::get_address_blocks reg_config -of_objects [ipx::get_memory_maps s_axi_config -of_objects $core]]

set_property core_revision 4 [ipx::current_core]
ipx::create_xgui_files [ipx::current_core]
ipx::update_checksums [ipx::current_core]
ipx::check_integrity [ipx::current_core]
ipx::save_core [ipx::current_core]
close_project

# 2. Build the main block design using our packaged IP
create_project $project_name $project_dir -part xc7z020clg400-1 -force

set_property ip_repo_paths $ip_repo_dir/gps_tracker_ip [current_project]
update_ip_catalog

create_bd_design "design_1"

# Instantiate Zynq PS
create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 processing_system7_0
set_property -dict [list CONFIG.PCW_USE_S_AXI_HP0 {1}] [get_bd_cells processing_system7_0]

# Instantiate Scrubbed IP
create_bd_cell -type ip -vlnv xilinx.com:user:gps_tracker:1.0 gps_tracker_0

# Instantiate AXI DMA
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_dma:7.1 axi_dma_0
set_property -dict [list CONFIG.c_include_sg {0} CONFIG.c_include_s2mm {0}] [get_bd_cells axi_dma_0]

# Run Connection Automation for PS, DMA, and HLS IP
apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 -config {make_external "FIXED_IO, DDR" apply_board_preset "1" Master "Disable" Slave "Disable" }  [get_bd_cells processing_system7_0]

apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config { Clk_master {Auto} Clk_slave {Auto} Clk_xbar {Auto} Master {/processing_system7_0/M_AXI_GP0} Slave {/gps_tracker_0/s_axi_config} ddr_seg {Auto} intc_ip {New AXI Interconnect} master_apm {0}}  [get_bd_intf_pins gps_tracker_0/s_axi_config]
apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config { Clk_master {Auto} Clk_slave {Auto} Clk_xbar {Auto} Master {/processing_system7_0/M_AXI_GP0} Slave {/gps_tracker_0/s_axi_status} ddr_seg {Auto} intc_ip {New AXI Interconnect} master_apm {0}}  [get_bd_intf_pins gps_tracker_0/s_axi_status]

# Force explicit address mapping to bypass Vivado auto-assignment bug
assign_bd_address -offset 0x40000000 -range 4096 -target_address_space /processing_system7_0/Data [get_bd_addr_segs gps_tracker_0/s_axi_config/reg_config] -force
assign_bd_address -offset 0x40010000 -range 4096 -target_address_space /processing_system7_0/Data [get_bd_addr_segs gps_tracker_0/s_axi_status/reg_status] -force
apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config { Clk_master {Auto} Clk_slave {Auto} Clk_xbar {Auto} Master {/processing_system7_0/M_AXI_GP0} Slave {/axi_dma_0/S_AXI_LITE} ddr_seg {Auto} intc_ip {New AXI Interconnect} master_apm {0}}  [get_bd_intf_pins axi_dma_0/S_AXI_LITE]
apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config { Clk_master {Auto} Clk_slave {Auto} Clk_xbar {Auto} Master {/axi_dma_0/M_AXI_MM2S} Slave {/processing_system7_0/S_AXI_HP0} ddr_seg {Auto} intc_ip {New AXI SmartConnect} master_apm {0}}  [get_bd_intf_pins processing_system7_0/S_AXI_HP0]

# Connect DMA M_AXIS_MM2S to HLS IP input stream
connect_bd_intf_net [get_bd_intf_pins axi_dma_0/M_AXIS_MM2S] [get_bd_intf_pins gps_tracker_0/sample_in]

# Connect ap_clk and ap_rst_n manually if not connected by automation
if { [get_bd_nets -of_objects [get_bd_pins gps_tracker_0/ap_clk] -quiet] == "" } {
    connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] [get_bd_pins gps_tracker_0/ap_clk]
}
if { [get_bd_nets -of_objects [get_bd_pins gps_tracker_0/ap_rst_n] -quiet] == "" } {
    connect_bd_net [get_bd_pins rst_ps7_0_50M/peripheral_aresetn] [get_bd_pins gps_tracker_0/ap_rst_n]
}

# Generate Wrapper
save_bd_design
validate_bd_design
make_wrapper -files [get_files $project_dir/$project_name.srcs/sources_1/bd/design_1/design_1.bd] -top
add_files -norecurse $project_dir/$project_name.gen/sources_1/bd/design_1/hdl/design_1_wrapper.v
update_compile_order -fileset sources_1

# Generate Bitstream
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1

# Export files
file mkdir $deploy_dir
file copy -force $project_dir/$project_name.runs/impl_1/design_1_wrapper.bit $deploy_dir/tracker_hw.bit
file copy -force $project_dir/$project_name.gen/sources_1/bd/design_1/hw_handoff/design_1.hwh $deploy_dir/tracker_hw.hwh

puts "Bitstream generated and exported successfully."
exit

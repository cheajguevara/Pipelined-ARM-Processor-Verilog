set script_dir [file dirname [file normalize [info script]]]
set rtl_dir [file normalize [file join $script_dir .. rtl]]
set output_dir [file join $script_dir build synth]
set part xc7a100tcsg324-1

if {[llength [get_parts -quiet $part]] == 0} {
    error "FPGA part $part is not available in this Vivado installation"
}
file mkdir $output_dir
read_verilog [glob -directory $rtl_dir *.v]
read_xdc [file join $script_dir arm_core_50mhz.xdc]
synth_design -top arm_core -part $part \
    -generic {ARM_COMPATIBLE=1 IRQ_SUPPORT=1}

if {[llength [get_clocks -quiet core_clk]] != 1} {
    error "Expected the 50 MHz core_clk constraint"
}
if {[llength [get_cells -hierarchical -filter {REF_NAME =~ FD*}]] == 0} {
    error "Synthesized core contains no registers"
}
if {[llength [get_cells -hierarchical -filter {REF_NAME == IOBUF}]] != 8} {
    error "Expected eight bidirectional SRAM I/O buffers"
}

report_utilization -file [file join $output_dir utilization.rpt]
report_utilization -hierarchical -file [file join $output_dir utilization_hierarchical.rpt]
report_timing_summary -delay_type max -report_unconstrained \
    -file [file join $output_dir timing_summary.rpt]
check_timing -file [file join $output_dir check_timing.rpt]
write_checkpoint -force [file join $output_dir arm_core_synth.dcp]
puts "IRQ-enabled arm_core synthesized for $part at 50 MHz."
puts "Reports and checkpoint: $output_dir"

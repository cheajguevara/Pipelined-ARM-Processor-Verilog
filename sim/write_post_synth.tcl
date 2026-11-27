set script_dir [file dirname [file normalize [info script]]]
set synth_dir [file join $script_dir build synth]
set checkpoint [file join $synth_dir arm_core_synth.dcp]
if {![file exists $checkpoint]} {
    error "Missing $checkpoint; run sim/run_synth.tcl first"
}
open_checkpoint $checkpoint
write_verilog -force -mode funcsim [file join $synth_dir arm_core_funcsim.v]

############
import volcano  library.volcano
set m /work/nova/nova
set l /library

config rtl clockgate on -integrated $l/ICG
config rtl verilog 2000 on
config map clockedge on
config rtl datapath physical off
config primary unique off
config timing clockgating on
config timing inout net on
config timing inout cell off
config timing slew default generation on
config sdc unit capacitance p
config sdc unit resistance k
config sdc unit time n
config timing clock multiple on
config timing borrow method relax
config timing borrow automatic on
config timing slew mode largest
config timing propagate constants combinational
config timing check recovery on
config volcano -crash.volcano off
config snap error_volcano off
config async concur off
config snap output on [config snap level] volcano prefixtime-dft-insert-scan
config message limit SWP-8 1
config message limit MAP-111 1

config multithread -thread auto -feature all -gr on

set rtl_list [glob ../src/*.v ]
eval import rtl -verilog -include ../src $rtl_list

fix rtl $m

config snap replace [config snap level] fix-netlist-sweep ” run gate sweep $m -hier -cross_boundary -uniquify ”
run bind logical -no_uniquify $m $l

force dft scan style $m muxed_flip_flop
force gate opt_mode $m delay -hier
fix netlist $m $l -effort high
export verilog netlist $m snap/compile_mingate.v -minsize

# Scan Insertion starts here
enwrap “config dft scan lockup on
config dft scan shift_register on
config dft setup clock_groups on
config dft repair violation clock_violation on
config dft repair violation comb_loop on
config dft repair violation disable_tribus on
config dft repair violation latch on
config dft repair violation reset_violation on

” prefixtime-dft-configure $m

enwrap {
force dft scan clock $m [list $m/mpin:clk]

for {set sid 0} {$sid < 6 } {incr sid} {
data create port [data only model_entity $m] SI${sid} -direction in
data create port [data only model_entity $m] SO${sid} -direction out
force dft scan chain $m $sid SI${sid} SO${sid}
}

force dft scan control $m $m/mpin:SE scan_enable

} prefixtime-dft-force $m

enwrap “run dft check $m -pre_scan
run dft scan insert $m
run dft check $m -post_scan
run dft scan trace $m ” prefixtime-dft-insert-scan $m

# Scan Insertion Ends here

# Source Timing Constraints
source -echo $SCRPATH/nova_constraints.tcl

enwrap {
force undriven $m 0
run gate sweep $m -hier -cross_boundary
} pre-ftime-sweep $m

#To enable pipeliing with 5 stages and using clk as clock and also to enable retiming , uncomment below 2 lines
#force gate pipeline $m $l -stage 5 -clk $m/clk
#force gate retime $m on -hier

# Turn on netlist level clock gating. Helps saves area by eliminating feedback
# loops with muxes and helps in routing due to lesser number of pins

config gate clockgate on

# Use sized netlist flow and use new mapper with -smap option
set  FT_FLOW sized
fix time $m $l -effort high -timing_effort high -size -smap

enwrap {
export verilog netlist $m snap/logic_opt_mingate.v
} ftime-export-verilog $m

enwrap {
config hierarchy separator “_”
data flatten $m
} flatten-design $m

### Floorplanning  starts here

enwrap {
force model routing layer $m highest M6

force plan net VDD $m -usage power -port VDD
force plan net VSS $m -usage ground -port VSS

config optimize leakage on -auto on
config capacitance congestion true

} floorplan-configs $m

set fp [ data create floorplan $m fp ]
run floorplan size $fp -target_total_util 0.5 -aspect_ratio 1.0
config autoflow $m set fix_plan
config autoflow $m set fix_shape

fix power $m $l -default_mesh -auto_domains -mesh_range { M4 M5 }

enwrap { run plan create pin $m -incremental } pin-pl-incr $m

config flow $m set floorplan
check design $m

if {[data exists /macro_lib ] } {
export volcano ./snap/floorplan.volcano -object /work -object /macro_lib } else {
export volcano  ./snap/floorplan.volcano -object /work }

#Floorplanning ends here

#Spare Cell Insertion
config snap procedure spare_flops {
global SCRPATH
#Spare Cells to be created are defined in sparE_cell.tcl and they are attached to VSS net and belong the floorplan of $m
run plan create sparecell $m $SCRPATH)/spare_cell.tcl VSS -floorplan [data only model_floorplan $m ]
run plan identify sparecell $m -file snap/spare_cells_identified.tcl
run plan place sparecell $m
puts “nn Executing spare flops proc nn” }

config snap output on [config snap level] spare_flops -snap after fix-cell-place-global1

#force boundary_cell $m -cell “*BND_UF*” -blockage buffer

#Sub Cap and End Cap Insertion
enwrap {
run plan create subcaps $m -subcap [ find_model FILL $l ] -stepdistance 120u
set welltie [find_model FILL $l ]
run plan create endcaps $m -left_endcap $welltie -right_endcap $welltie
} cap-insertion $m

# While Scan reordering, dont order the first flop
config scan optimize $m -not_order_first_flop on

fix cell $m $l -timing

fix opt global $m $l -effort high -label 1

enwrap {
config clock auto_skew_balance on
force plan clock $m -buffer $l/BUF/BUF_HYPER
force plan clock $m -inverter $l/INV/INV_HYPER
force plan clock $m -max_skew 50ps -max_useful_skew 40ps
force timing adjust_latency $m boundary_average } PRE-FIXCLOCK $m
config snap replace  [ config snap level ] fix-clock-route-clock “run route clock $m $l -nondefaul
t_mode double_s -shielding_mode noleaf -effort high -overdrive 3
fix clock $m $l -weight skew -critical_slack 0ps -clock_effort high -timing -nondefault_mode double_s -shielding_mode noleaf

fix opt global $m $l -effort high -dont_move_reg -critical_slack 0ps -secondary_effort off -label 2

fix hold $m $l

enwrap {
config prepare access mode enhanced -ui on
run prepare model access $m -reset
run prepare model access $m
config route flow adaptive $l on
} pre-fix-wire-eap-wrapper $m

fix wire $m $l -slew -crosstalk_delay -crosstalk_effort high

enwrap { config condition case both } rod-case-both $m

enwrap { run place detail $m -eco } rod-rpd-eco $m

run optimize detail $m $l -dont_move_reg -critical_slack 10ps -optimize all -hold_fix_hold_margin 10p -hold_fix_setup_margin 100p -useful_skew

# DRC Cleanup
enwrap {
check route drc $m
check route spacing_short $m
run route refine $m
run route final -incremental -reroute_tile_width 30 $m
run route final -incremental -reroute_tile_width 60 $m
run route final -incremental -reroute_tile_width 20 $m
run route final -incremental -reroute_tile_width 10 $m
run route final -incremental -reroute_tile_width 30 -effort maximum $m
run route final -incremental -reroute_tile_width 60 -effort maximum $m
run route final -incremental -reroute_tile_width 10 -effort maximum $m
run route final -incremental -reroute_tile_width 30 -effort maximum $m
run route final -incremental -reroute_tile_width 50 -effort maximum $m
run route refine $m -type nontrivial
run route refine $m -type notch
run route refine $m -type island
check route antenna $m
check route drc $m
} post-fix-wire-opt-wrapper $m

###########

####Timing Constraints #######

force timing clock {mpin:clk} 3ns -waveform { -rise 0p -fall 1.5ns} -context /work/nova/nova

###############################################################################
# Collect all inputs with some exclusions
###############################################################################
set Inputs [data list “model_pin -direction in” $m]
set Bidirs [data list “model_pin -direction inout” $m ]

# Add the inout ports to the list of inputs

set Inputs [concat $Inputs [data list “model_pin -direction inout” $m ]]

# Remove the clock ports from the list of constrainable inputs

foreach clockPort [data list model_clock $m ] {
set Inputs  [lsearch -all -inline -not -exact $Inputs $clockPort]
}

puts “The number of inputs is     : [llength $Inputs]”

set io_delay_max [ expr [ expr 1.0 / 1500000.0 ] * 0.9 ]
set io_delay_min [ expr [ expr 1.0 / 1500000.0 ] * 0.1 ]

foreach iport $Inputs {
puts “Adding input delay on port $iport”
force timing delay clk $iport -time {-worst  6e-07p  } -type rising_edge  -context $m
force timing delay clk $iport -time {-best 6.66666666667e-08p } -type rising_edge  -context $m
}

###############################################################################
# Collect all outputs with some exclusions
###############################################################################

set Outputs [data list “model_pin -direction out” $m]
set Bidirs [data list “model_pin -direction inout” $m ]
# Add the inout ports to the list of outputs
set Outputs [concat $Outputs $Bidirs]
puts “The number of outputs is    : [llength $Outputs]”

foreach oport $Outputs {
puts “Adding output delay timing check to output port $oport”
force timing check $oport clk -time  6e-07p -type setup_rising  -context $m
force timing check $oport clk -time  6.666666667e-08p -type hold_rising   -context $m
}
###############################################################################
# Assign a default input transition time or set a driving cell if you rather.
###############################################################################
foreach iport $Inputs {
puts “Setting input transition on port $iport”
force timing slew  $iport { -rise {-max 0318p} }
force timing slew  $iport { -rise {-min 0008p} }
force timing slew  $iport { -fall {-max 0314p} }
force timing slew  $iport { -fall {-min 0004p} }
}

###############################################################################
# Assign default loads
###############################################################################
foreach oport $Outputs {
puts “Setting load on port $oport”
force load capacitance $oport {-worst 0.181p }
force load capacitance $oport {-best  0.001p }
}

##########################################################################
puts “Multicycle the async applied inputs”
##########################################################################
set a01  [data list “model_pin -direction in” $m -names {.*mpin:reset_n}]

catch {set a01 [concat $a01] }
foreach p $a01 {
puts “Adding MCP through scan control input $p”
force timing multicycle -from $p -cycles 7 -type setup -reference start
force timing multicycle -from $p -cycles 6 -type hold  -reference start
}

##########################################################################
puts “Set timing constants”
##########################################################################
# Define functional mode
force timing constant $m/mpin:SE 0

return
##########################################################################
puts “Multicycle the output ports that are async in nature”
##########################################################################
set a01 [data list “model_pin -direction out” -names .*mpin:ready.* $m]
set a02 [data list “model_pin -direction out” -names .*mpin:erfound.* $m]
catch {set a01 [concat $a01 $a02] }
foreach aport $a01 {
puts “Setting MCP to async input port $aport”
force timing multicycle -to $a01 -cycles 5 -type setup -reference start
force timing multicycle -to $a01 -cycles 4 -type hold  -reference start
}

##########################################################################
puts “Set max delay on IO through path, use rarely”
# Mindelay and Maxdelay should be the last resort.
##########################################################################
set a01  [data list “model_pin -direction in” $m -names {.*mpin:some_goofy_input}]
set b01  [data list “model_pin -direction out” $m -names {.*mpin:some_goofy_output}]
foreach p $a01 {
puts “Adding min/max delay through input $p”
force timing maxdelay 1.0n -from $a01 -to $b01
force timing mindelay 0.5n -from $a01 -to $b01
}

#####Spare Cells Addition  (spare_cells.tcl) ######

spare_and2 $l/AND2/AND4 20
spare_inv  $l/INV/INVD3 20
spare_buf  $l/BUF/BUF2P 20
spare_nand $l/NAND2/ND4P 20
spare_or $l/OR2/OR4P 20
spare_nor $l/NOR4/NRD2P 20
spare_ff  $l/SDFF/SDFF2 20

###########

ASIC DESIGN

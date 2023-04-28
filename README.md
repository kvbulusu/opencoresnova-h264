# opencoresnova-h264
For archival purposes. Originally appeared in my blog in 2008.
https://kiranbulusu.wordpress.com/2012/05/13/synthesis-and-implementaion-pr-of-low-power-realtime-h-264avc-baseline-decoder/

Technology Node: 45nm process
Clock Freq: 333 MHz (Please note, I have changed the clk freq. I was scaling the clk freq to see study design feasibility . However , it might be possible to close timing by bumping the freq higher, I havent done that as this is intended purely for fun and learning purposes )



Used non default rules with double spacing during CTS
We also enable cross talk and cross talk noise based optimizations during detailed routing.
Std Cell Area:0.744mm2 with 70% util and 3.8 mts wire length
Cell Count : 176K
Scan Insertion : Done. No of scan chains 6

EDA Tools: Talus Design for Logic Synthesis,
Talus Vortex for Placement,Clock Tree Synthesis and Routing
Power:  ( We havent really done too many power optimizations except Clock gating which helps on dynamic power) .  I will try to post another version of script where I did many power optimizations to save leakage/dynamic power while not hurting timing. The cell count/area and wire length are direct consequence of tightening the clock freq.

Another reason why over constraining is bad :) . as long as the tool is predictable and have very good front end – back end correlation, you dont need to over constraint. Synthesis tools like Talus Design and from other vendors offer correlation in range 6-10%  range or may be less in some cases ( please note this largely depends on design/timing criticality/whether macro intensicve etc).

Based on spec, I have written some timing constraints to take the design through the entire flow.  I havent got time to close timing, but it was nearly close. The final timing is about -50ps and is easily fixable with few signal DRC left ( less than 30 ) .

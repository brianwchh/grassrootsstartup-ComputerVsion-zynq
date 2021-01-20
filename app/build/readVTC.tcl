set logfile [open "v_tc.txt" "w"]
puts $logfile [mrd 0x43c00000 0x0051]
close $logfile

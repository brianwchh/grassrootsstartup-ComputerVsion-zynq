set logfile [open "vdma.txt" "w"]
puts $logfile [mrd 0x43000000 0x3b]
close $logfile

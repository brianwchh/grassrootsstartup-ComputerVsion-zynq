set logfile [open "dynclk.txt" "w"]
puts $logfile [mrd 0x43c10000 0x51]
close $logfile

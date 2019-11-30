namespace eval aphttp {
    proc kickstart {cmd port} {
        set socketSet [socket -server [list aphttp::queryConnection $cmd] $port]
        vwait forever
    }
    
    proc queryConnection {cmd socketv address port} {
        fconfigure $socketv -buffering line
        fileevent $socketv readable [list aphttp::mapConnection $cmd $socketv $address $port]
    }
    
    proc parseHeaders {listing {withFirst 1}} {
        set first $withFirst
        set result [dict create]
        foreach line $listing {
            if {$first} {
                set first 0
                set lnSplit [split $line { }]
                lappend lnSplit {}
                lappend lnSplit {}
                dict set result method [lindex $lnSplit 0]
                dict set result url [lindex $lnSplit 1] 
            } else {
                set lnSplit [split $line {:}]
                set halfOne [lindex $lnSplit 0]
                set halfTwo [string range [join [lreplace $lnSplit 0 0] :] 1 end]
                dict set result $halfOne $halfTwo
            }
        }
        return $result
    }
    
    proc mapConnection {cmd socketv address port} {
        set what {}
        set line wtf
        while {! [eof $socketv] && ! [catch {gets $socketv line}] && [string length $line] >= 3} {
            lappend what $line
        }
        set parsedHeaders [aphttp::parseHeaders $what]
        eval "$cmd $socketv \"$address:$port\""
        close $socketv
    }
    
    
    
}

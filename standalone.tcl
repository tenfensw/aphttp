#!/usr/bin/env tclsh
# apHTTP - a programmable HTTP server in Tcl (standalone implementation)
# Copyright (C) Tim K/RoverAMD 2019 <timprogrammer@rambler.ru>.
#
# Permission to use, copy, modify, and/or distribute this software for
# any purpose with or without fee is hereby granted.
# 
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
# WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
# ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
# WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
# ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT
# OF OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

source [file dirname [info script]]/core.tcl

set allUrls {}
set allExtensions [dict create .html text/html .css text/css .htm text/html .js application/javascript .jpeg image/jpeg .png image/png .jpg image/jpeg .gif image/gif .webp image/webp]
set version 0.2
set serverId "apHTTP/$version ($::tcl_platform(os))"

proc findUrl {uid} {
    global allUrls
    foreach itm $allUrls {
        if {[dict get $itm url] == $uid} {
            return $itm
        }
    }
    return [dict create found 0]
}

proc connectionError {sock codev textv} {
    global version
    global serverId
    puts $sock "HTTP/1.1 $codev $textv"
    puts $sock "Server: "
    puts $sock "Connection: closed"
    puts $sock "Content-type: text/plain"
    puts $sock ""
    puts $sock "$codev $textv"
}

proc makeNative {url} {
    set listing {}
    set tmpSplit [split $url ?]
    lappend listing [lindex $tmpSplit 0]
    lappend listing [string map [list {'} {}] [join [lreplace $tmpSplit 0 0] ?]]
    return $listing
}

proc onConnection {dir sock sender} {
    global allExtensions
    global serverId
    upvar 1 parsedHeaders hdrs
    set urlNative [makeNative [dict get $hdrs url]]
    set url [findUrl [lindex $urlNative 0]]
    if {! [dict exists $url method]} {
        dict set url method GET
    }
    if {! [dict get $url found]} {
        connectionError $sock 404 {Not Found}
        return
    } elseif {[dict get $url cgi]} {
        set ip [lindex [split $sender :] 0]
        set cmd "SERVER_SOFTWARE='$serverId' SERVER_NAME='localhost' SERVER_PROTOCOL='CGI/1.1' REQUEST_METHOD=[dict get $url method] SCRIPT_NAME=[dict get $url url] REMOTE_ADDR='$ip' QUERY_STRING='[lindex $urlNative 1]' '$dir/[dict get $url what]' > runner.log 2>stderr.log"
        puts $cmd
        if {[catch {exec -ignorestderr -- sh -c $cmd}]} {
            set desc [open stderr.log r]
            set ctnt [read $desc]
            close $desc
            file delete stderr.log
            file delete runner.log
            puts $sock "HTTP/1.1 500 Internal Server Error"
            puts $sock "Content-type: text/plain"
            puts $sock "Server: $serverId"
            puts $sock "X-apHTTP-UsedCMD: $cmd"
            puts $sock ""
            puts $sock $ctnt
        } else {
            file delete stderr.log
            set desc [open runner.log r]
            set ctntRaw [string map [list "\r\n" "\n"] [read $desc]]
            close $desc
            file delete runner.log
            set ctnt [split $ctntRaw \n]
            set ctntHeaders [aphttp::parseHeaders $ctnt 0]
            if {[dict exists $ctntHeaders Status]} {
                puts $sock "HTTP/1.1 [dict get $ctntHeaders Status]"
            } else {
                puts $sock "HTTP/1.1 200 OK"
            }
            puts $sock "Server: $serverId"
            puts $sock [join $ctnt \n]
        }
    } else {
        set fn "$dir/[dict get $url what]"
        if {! [file exists $fn]} {
            connectionError $sock 404 {Not Found}
        } elseif {[file isdirectory $fn]} {
            connectionError $sock 403 Forbidden
        } else {
            set desc [open $fn r]
            fconfigure $desc -buffering none -translation binary -encoding binary
            set ctnt [read $desc]
            close $desc
            puts $sock "HTTP/1.1 200 OK"
            puts $sock "Server: $serverId"
            puts $sock "X-apHTTP-ConnectionHandleTime: [clock seconds]"
            puts $sock "X-apHTTP-AbsolutePath: $fn"
            set extension [file extension $fn]
            set mimetype application/octet-stream
            if {[dict exists $allExtensions $extension]} {
                set mimetype [dict get $allExtensions $extension]
            }
            puts $sock "Content-type: $mimetype"
            puts $sock ""
            chan configure $sock -buffering none -translation binary -encoding binary
            puts $sock $ctnt
        }
    }
}

if {$::argc < 3} {
    puts "Usage: [info script] <port> <directory> <map>"
    exit 1
}

set port [lindex $::argv 0]
if {! [string is integer $port]} {
    error "Port must be a number."
}
set dir [lindex $::argv 1]
set desc [open [lindex $::argv 2] r]
set mapCtntRaw [read $desc]
close $desc
foreach line [split [string map [list "\r\n" "\n"] $mapCtntRaw] \n] {
    set lineSplit [split $line { }]
    if {[llength $lineSplit] < 2 || [string index $line 0] == "#"} {
        continue
    }
    if {[lindex $lineSplit 1] == "=>" && [llength $lineSplit] >= 3} {
        set fnFinal [lindex $lineSplit 2]
        set cgi 0
        if {[string toupper [lindex $lineSplit 3]] == {CGI}} {
            set cgi 1
        }
        lappend allUrls [dict create found 1 url [lindex $lineSplit 0] cgi $cgi what $fnFinal]
    } elseif {[lindex $lineSplit 0] == "all"} {
        set dirv "$dir/[lindex $lineSplit 1]"
        if {! [file isdirectory $dirv]} {
            error "No such directory - \"$dirv\"."
        }
        set oldPwd [pwd]
        cd $dirv
        foreach fn [glob -directory . -type f *] {
            lappend allUrls [dict create found 1 url "/[lindex $lineSplit 1]/$fn" cgi 0 what $fn]
        }
        cd $oldPwd
    } elseif {[lindex $lineSplit 1] == "is" && [llength $lineSplit] >= 3} {
        set ext [lindex $lineSplit 0]
        if {[string index $ext 0] != {.}} {
            set ext ".$ext"
        }
        dict set allExtensions $ext [lindex $lineSplit 2]
    }
}

aphttp::kickstart [list onConnection $dir] $port

{
---------------------------------------------------------------------------------------------------
    Filename:       sdfat-fdelete.spin
    Description:    FATfs on SD: delete file example code
    Author:         Jesse Burt
    Started:        Jun 16, 2022
    Updated:        Mar 12, 2024
    Copyright (c) 2024 - See end of file for terms of use.
---------------------------------------------------------------------------------------------------
}

CON

    _clkmode    = cfg._clkmode
    _xinfreq    = cfg._xinfreq


OBJ

    cfg:    "boardcfg.flip"
    time:   "time"
    ser:    "com.serial.terminal.ansi" | SER_BAUD=115_200
    sd:     "memfs.sdfat" | CS=0, SCK=1, MOSI=2, MISO=3


PUB main() | err

    setup()

    dir()
    ser.strln(@"press any key to delete")
    ser.getchar()
    err := sd.fdelete(@"TEST0000.TXT")
    if (err < 1)
        perror(@"Error deleting: ", err)
        repeat

    ser.strln(@"press any key to show updated directory listing")
    ser.getchar()
    ser.clear()
    dir()
    ser.strln(@"done")
    repeat

VAR

    byte _fname[8+1+3+1]

PUB dir() | err, show_del, del_cnt, reg_cnt, dir_cnt, t_files, tsz
' Display directory listing
    sd.opendir(0)
    ser.printf1(@"Volume label: [%s]\n\r", sd.vol_name())
    longfill(@err, 0, 7)                        ' init vars to 0

    show_del := false                           ' set non-zero to show deleted files
    
    repeat
        err := sd.next_file(@_fname)            ' get dirent # and copy filename
        if ( err > 0 )
            if ( sd.fdeleted() )                ' how do we handle files marked deleted?
                del_cnt++                       ' tally them up
                if ( show_del == false )        ' skip to next if we're not showing them
                    next
            else
                reg_cnt++                       ' regular file
            if ( sd.fis_dir() )
                dir_cnt++                       ' directory
            ser.printf3(@"%s %d %d", @_fname, sd.ffirst_clust(), sd.fsize() )
            printdate( sd.fdate_created() )
            printtime( sd.ftime_created() )
            printattrs( sd.fattrs() )
            ser.newline()
            tsz += sd.fsize()                   ' total up the reported size of all files
            t_files++
        else
            ser.newline()
            ser.strln(@"end of directory")
    while ( err > 0 )

    ser.newline()
    ser.printf4(@"Total: %d files (%d directories, %d regular files, %d deleted files)\n\r", ...
                t_files, dir_cnt, reg_cnt, del_cnt)
    ser.printf1(@" (%d bytes)\n\r", tsz)

PUB setup() | err

    ser.start()
    time.msleep(20)
    ser.clear()
    ser.strln(@"serial terminal started")

    err := sd.start()
    if (err < 0)
        ser.printf1(@"Error mounting SD card %x\n\r", err)
        repeat
    else
        ser.printf1(@"Mounted card (%d)\n\r", err)

#include "fatfs-common.spinh"
#include "sderr.spinh"


DAT
{
Copyright 2024 Jesse Burt

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and
associated documentation files (the "Software"), to deal in the Software without restriction,
including without limitation the rights to use, copy, modify, merge, publish, distribute,
sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or
substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT
NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT
OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
}


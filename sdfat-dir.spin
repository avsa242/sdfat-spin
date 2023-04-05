{
    --------------------------------------------
    Filename: sdfat-dir.spin
    Author: Jesse Burt
    Description: FATfs on SD: directory listing example code
    Copyright (c) 2022
    Started Jun 11, 2022
    Updated Aug 23, 2022
    See end of file for terms of use.
    --------------------------------------------
}

CON

    _clkmode    = cfg#_clkmode
    _xinfreq    = cfg#_xinfreq

' --
    { SPI configuration }
    CS_PIN      = 3
    SCK_PIN     = 1
    MOSI_PIN    = 2
    MISO_PIN    = 0
' --

OBJ

    cfg : "boardcfg.flip"
    ser : "com.serial.terminal.ansi"
    sd  : "memfs.sdfat"

PUB main{}

    setup{}
    dir{}
    repeat

PUB dir{}: status | dirent, total, endofdir, t_files
' Display directory listing
    dirent := 0
    total := 0
    endofdir := false
    t_files := 0
    repeat                                      ' up to 16 entries per sector
        sd.fclose_ent{}
        status := sd.fopen_ent(dirent++, sd#O_RDONLY)   ' get current dirent's info
        if (status < 0)
            perror(@"Error opening: ", status)
            repeat
        if (sd.fis_vol_nm{})
            ser.printf1(@"Volume name: '%s'\n\r\n\r", sd.fname{})
            next
        if (sd.dirent_never_used{})             ' last directory entry
            endofdir := true
            quit
        if (sd.fdeleted{})                      ' ignore deleted files
            next
        if (sd.fis_dir{})                       ' format subdirs specially
            ser.printf1(string("[%s]\n\r"), sd.fname{})
        else                                    ' regular files
            ser.printf4(string("%s.%s %10.10d %x "), sd.fname{}, sd.fname_ext{}, sd.fsize{}, {
}           sd.ffirst_clust{})
            printdate(sd.fdate_created{})
            printtime(sd.ftime_created{})
            printattrs(sd.fattrs{})
            ser.newline{}
        total += sd.fsize{}                     ' tally up size of all files
        t_files++
    until endofdir
    ser.printf2(string("\n\r\n\r%d Files, total: %d bytes\n\r"), t_files, total)

PUB setup{} | err

    ser.start(115_200)
    ser.clear
    ser.strln(@"serial terminal started")

    err := sd.startx(CS_PIN, SCK_PIN, MOSI_PIN, MISO_PIN)
    if (err < 1)
        ser.printf1(@"Error mounting SD card %x\n\r", err)
        repeat
    else
        ser.printf1(@"Mounted card (%d)\n\r", err)

#include "fatfs-common.spinh"
#include "sderr.spinh"

DAT
{
Copyright 2022 Jesse Burt

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


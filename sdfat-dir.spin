{
    --------------------------------------------
    Filename: sdfat-dir.spin
    Author: Jesse Burt
    Description: FATfs on SD: directory listing example code
    Copyright (c) 2022
    Started Jun 11, 2022
    Updated Jun 26, 2022
    See end of file for terms of use.
    --------------------------------------------
}

CON

    _clkmode        = cfg#_clkmode
    _xinfreq        = cfg#_xinfreq

' --
{ SPI configuration }
    CS              = 3
    SCK             = 1
    MOSI            = 2
    MISO            = 0
' --

OBJ

    cfg : "core.con.boardcfg.flip"
    ser : "com.serial.terminal.ansi"
    sd  : "memfs.sdfat"

PUB Main{} | err

    ser.start(115_200)
    ser.clear
    ser.strln(@"serial terminal started")

    err := sd.startx(CS, SCK, MOSI, MISO)              ' start SD/FAT
    if (err < 1)
        ser.printf1(@"Error mounting SD card %x\n\r", err)
        repeat
    else
        ser.printf1(@"Mounted card (%d)\n\r", err)

    dir{}
    repeat

PUB DIR{}: status | dirent, total, endofdir, t_files
' Display directory listing
    dirent := 0
    total := 0
    endofdir := false
    t_files := 0
    repeat                                      ' up to 16 entries per sector
        \sd.fcloseent{}
        status := \sd.fopenent(dirent++, sd#O_RDONLY)      ' get current dirent's info
        if (status < 0)
            perror(@"Error opening: ", status)
            repeat
        if (sd.fisvolnm{})
            ser.printf1(@"Volume name: '%s'\n\r\n\r", sd.fname{})
            next
        if (sd.direntneverused{})               ' last directory entry
            endofdir := true
            quit
        if (sd.fdeleted{})                      ' ignore deleted files
            next
        if (sd.fisdir{})                        ' format subdirs specially
            ser.printf1(string("[%s]\n\r"), sd.fname{})
        else
            { regular files }
            ser.printf4(string("%s.%s %10.10d %x "), sd.fname{}, sd.fnameext{}, sd.fsize{}, sd.ffirstclust{})
            printdate(sd.fdatecreated{})
            printtime(sd.ftimecreated{})
            printattrs(sd.fattrs{})
            ser.newline{}
        total += sd.fsize{}                     ' tally up size of all files
        t_files++
    until endofdir
    ser.printf2(string("\n\r\n\r%d Files, total: %d bytes\n\r"), t_files, total)

#include "fatfs-common.spinh"
#include "sderr.spinh"


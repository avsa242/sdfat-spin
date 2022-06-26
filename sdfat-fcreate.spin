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
    ser : "com.serial.terminal.ansi-new"
    sd  : "memfs.sdfat"

DAT

    { filename to create must be 8.3 format; pad with spaces if less than full length }
    _fname byte "TEST0004.TXT", 0

PUB Main{} | err, dirent

    ser.start(115_200)
    ser.clear{}
    ser.strln(string("serial terminal started"))

    err := sd.startx(CS, SCK, MOSI, MISO)
    if (err < 1)
        ser.printf1(string("Error mounting SD card %x\n\r"), err)
        repeat
    else
        ser.printf1(string("Mounted card (%d)\n\r"), err)

    dirent := \sd.fcreate(@_fname, sd#FATTR_ARC)
    if (dirent < 0)
        perr(@"Error creating file: ", dirent)
        repeat

    ser.printf2(@"Created %s in directory entry #%d\n\r", @_fname, dirent)

    repeat

#include "sderr.spinh"


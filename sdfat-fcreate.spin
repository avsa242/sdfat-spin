{
    --------------------------------------------
    Filename: sdfat-dir.spin
    Author: Jesse Burt
    Description: FATfs on SD: directory listing example code
    Copyright (c) 2022
    Started Jun 11, 2022
    Updated Aug 27, 2022
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

    cfg : "core.con.boardcfg.flip"
    ser : "com.serial.terminal.ansi"
    sd  : "memfs.sdfat"

DAT

    { filename to create must be 8.3 format; pad with spaces if less than full length }
    _fname byte "TEST0000.TXT", 0

PUB main{} | err, dirent

    setup{}

    dirent := sd.fcreate(@_fname, sd#FATTR_ARC)
    if (dirent < 0)
        perror(string("Error creating file: "), dirent)
        repeat

    ser.printf2(string("Created %s in directory entry #%d\n\r"), @_fname, dirent)
    ser.strln(string("done"))

    repeat

PUB setup{} | err

    ser.start(115_200)
    ser.clear
    ser.strln(string("serial terminal started"))

    err := sd.startx(CS_PIN, SCK_PIN, MOSI_PIN, MISO_PIN)
    if (err < 1)
        ser.printf1(string("Error mounting SD card %x\n\r"), err)
        repeat
    else
        ser.printf1(string("Mounted card (%d)\n\r"), err)

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


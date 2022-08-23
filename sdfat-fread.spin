{
    --------------------------------------------
    Filename: sdfat-fread.spin
    Author: Jesse Burt
    Description: FATfs on SD: FRead() example code
    Copyright (c) 2022
    Started Jun 11, 2022
    Updated Aug 23, 2022
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
    time: "time"
    sd  : "memfs.sdfat"

VAR

    byte _sect_buff[512]

PUB Main | err, fn, pos, act_read, cmd

    ser.start(115_200)
    time.msleep(30)
    ser.clear
    ser.strln(string("serial terminal started"))

    err := sd.startx(CS, SCK, MOSI, MISO)              ' start SD/FAT
    if (err < 1)
        ser.printf1(string("Error mounting SD card %x\n\r"), err)
        repeat
    else
        ser.printf1(string("Mounted card (%d)\n\r"), err)

    fn := @"TEST0004.TXT"
    err := \sd.fopen(fn, sd#O_RDONLY)
    if (err < 0)
        perror(@"FOpen(): ", err)
        repeat

    repeat
        ser.clear
        bytefill(@_sect_buff, 0, 512)
        pos := sd.ftell{}                       ' get current seek position
        act_read := \sd.fread(@_sect_buff, 512)  ' NOTE: this advances the seek pointer by 512
        if (act_read < 1)
            ser.position(0, 4)
            ser.fgcolor(ser#RED)
            perror(@"Read error: ", act_read)
            ser.fgcolor(ser#GREY)
            ser.charin{}
            ser.position(0, 4)
            ser.clearline{}

        ser.position(0, 5)
        ser.printf1(@"fseek(): %d    \n\r", pos)
        ser.hexdump(@_sect_buff, pos, 8, 512 <# act_read, 16 <# act_read)
        repeat until (cmd := ser.charin)
        case cmd
            "[":
                pos := 0 #> (pos-512)
                sd.fseek(pos)
            "]":
                { don't actually do anything here; when reading a block from the file,
                the pointer is already incremented automatically }
            "s":
                pos := 0
                sd.fseek(pos)
            "e":
                pos := sd.fsize{}-512
                sd.fseek(pos)
            "p":
                ser.printf1(@"Enter seek position: (0..%d)> ", sd.fend{})
                pos := ser.decin
                sd.fseek(pos)

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


{
    --------------------------------------------
    Filename: sdfat-fread.spin
    Author: Jesse Burt
    Description: FATfs on SD: fread() example code
    Copyright (c) 2023
    Started Jun 11, 2022
    Updated May 14, 2023
    See end of file for terms of use.
    --------------------------------------------
}

CON

    _clkmode    = cfg#_clkmode
    _xinfreq    = cfg#_xinfreq

' --
    SER_BAUD    = 115_200

    { SPI configuration }
    CS_PIN      = 3
    SCK_PIN     = 1
    MOSI_PIN    = 2
    MISO_PIN    = 0
' --

OBJ

    cfg:    "boardcfg.flip"
    ser:    "com.serial.terminal.ansi"
    time:   "time"
    sd:     "memfs.sdfat"

VAR

    byte _sect_buff[512]

PUB main() | err, fn, pos, act_read

    setup()

    fn := @"TEST0000.TXT"
    err := sd.fopen(fn, sd#O_RDONLY)
    if (err < 0)
        perror(@"fopen(): ", err)
        repeat

    repeat
        ser.clear()
        bytefill(@_sect_buff, 0, 512)
        pos := sd.ftell()                       ' get current seek position
        act_read := sd.fread(@_sect_buff, 512)  ' NOTE: this advances the seek pointer by 512
        if (act_read < 1)
            ser.pos_xy(0, 4)
            ser.fgcolor(ser#RED)
            perror(@"Read error: ", act_read)
            ser.fgcolor(ser#GREY)
            ser.getchar()
            ser.pos_xy(0, 4)
            ser.clear_line()

        ser.pos_xy(0, 5)
        ser.printf1(@"fseek(): %d    \n\r", pos)
        ser.hexdump(@_sect_buff, pos, 8, 512 <# act_read, 16 <# act_read)
        case ser.getchar()
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
                pos := sd.fsize()-512
                sd.fseek(pos)
            "p":
                ser.set_attrs(ser.ECHO)
                ser.printf1(@"Enter seek position: (0..%d)> ", sd.fend())
                pos := ser.getdec()
                ser.set_attrs(0)
                sd.fseek(pos)

PUB setup() | err

    ser.start(SER_BAUD)
    time.msleep(20)
    ser.clear()
    ser.strln(@"serial terminal started")

    err := sd.startx(CS_PIN, SCK_PIN, MOSI_PIN, MISO_PIN)
    if (err < 1)
        ser.printf1(@"Error mounting SD card %x\n\r", err)
        repeat
    else
        ser.printf1(@"Mounted card (%d)\n\r", err)

#include "sderr.spinh"

DAT
{
Copyright 2023 Jesse Burt

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


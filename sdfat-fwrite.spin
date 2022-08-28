{
    --------------------------------------------
    Filename: sdfat-fwrite.spin
    Author: Jesse Burt
    Description: FATfs on SD: FWrite() example code
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
    time: "time"
    sd  : "memfs.sdfat"

VAR

    byte _sect_buff[512]

DAT


    _test_str byte "AAAAAAAAAAAAAAAAAAAAA", 0

PUB main{} | err, fn, pos, cmd

    setup{}

    fn := string("TESTFIL3.TXT")
    err := sd.fopen(fn, sd#O_RDWR)
    if (err < 0)
        perror(string("fopen(): "), err)
        repeat

    { write test string to file }
    sd.fseek(0)
    bytemove(@_sect_buff, @_test_str, strsize(@_test_str))
    err := sd.fwrite(@_sect_buff, strsize(@_test_str))
    if (err < 0)
        perror(string("fwrite(): "), err)
        repeat

    sd.fseek(0)
    repeat
        ser.clear{}
        bytefill(@_sect_buff, 0, 512)
        pos := sd.ftell{}                       ' get current seek position
        err := sd.fread(@_sect_buff, 512)       ' reading advances the seek pointer by the number
                                                '   of bytes actually read
        if (err < 1)
            ser.position(0, 0)
            perror(string("Read error: "), err)
            ser.charin{}
            ser.position(0, 0)
            ser.clearline{}

        ser.position(0, 0)
        ser.printf1(string("fseek(): %d"), pos)
        ser.clearline{}
        ser.newline{}

        { dump file data read; limit display to number of bytes actually read }
        ser.hexdump(@_sect_buff, pos, 8, err, 16 <# err)
        repeat until (cmd := ser.charin{})
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
                ser.printf1(string("Enter seek position: (0..%d)> "), sd.fend{})
                pos := ser.decin{}
                sd.fseek(pos)

PUB setup{} | err

    ser.start(115_200)
    time.msleep(30)
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


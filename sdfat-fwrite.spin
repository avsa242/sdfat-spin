{
    --------------------------------------------
    Filename: sdfat-fwrite.spin
    Author: Jesse Burt
    Description: FATfs on SD: FWrite() example code
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
    time: "time"
    sd  : "memfs.sdfat"

VAR

    byte _sect_buff[512]

DAT

    _test_str byte "this is the test data", 0

PUB Main | err, fn, pos, cmd

    ser.start(115_200)
    time.msleep(30)
    ser.clear
    ser.strln(string("serial terminal started"))

    err := sd.startx(CS, SCK, MOSI, MISO)              ' start SD/FAT
    if (err < 1)
        ser.printf1(string("Error mounting SD card %x\n"), err)
        repeat
    else
        ser.printf1(string("Mounted card (%d)\n"), err)

    fn := @"TESTFIL3.TXT"
    err := \sd.fopen(fn, sd#O_RDWR)
    if (err < 0)
        perr(@"FOpen(): ", err)
        repeat

    { write test string to file }
    sd.fseek(0)
    clearbuff{}
    bytemove(@_sect_buff, @_test_str, strsize(@_test_str))
    err := \sd.fwrite(@_sect_buff, strsize(@_test_str))
    if (err < 0)
        perr(@"fwrite(): ", err)
        repeat

    clearbuff{}
    sd.fseek(0)
    repeat
        ser.clear{}
        bytefill(@_sect_buff, 0, 512)
        pos := sd.ftell{}                       ' get current seek position
        err := \sd.fread(@_sect_buff, 512)       ' reading advances the seek pointer by the number
                                                '   of bytes actually read
        if (err < 1)
            ser.position(0, 0)
            perr(@"Read error: ", err)
            ser.charin{}
            ser.position(0, 0)
            ser.clearline{}

        ser.position(0, 0)
        ser.printf1(@"fseek(): %d", pos)
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
                pos := sd.filesize{}-512
                sd.fseek(pos)
            "p":
                ser.printf1(@"Enter seek position: (0..%d)> ", sd.fend{})
                pos := ser.decin
                sd.fseek(pos)

PUB ClearBuff{}
' Clear sector buffer
    bytefill(@_sect_buff, 0, 512)

#include "sderr.spinh"


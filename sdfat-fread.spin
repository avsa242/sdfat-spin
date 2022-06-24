{
    --------------------------------------------
    Filename: sdfat-fread.spin
    Author: Jesse Burt
    Description: FATfs on SD: FRead() example code
    Copyright (c) 2022
    Started Jun 11, 2022
    Updated Jun 24, 2022
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
        ser.printf1(string("Error mounting SD card %x\n"), err)
        repeat
    else
        ser.printf1(string("Mounted card (%d)\n"), err)

    fn := @"TESTFIL3.TXT"
    err := sd.fopen(fn, sd#O_RDONLY)
    if (err < 0)
        perr(@"FOpen(): ", err)
        repeat

    repeat
        bytefill(@_sect_buff, 0, 512)
        pos := sd.ftell{}                       ' get current seek position
        act_read := sd.fread(@_sect_buff, 512)  ' NOTE: this advances the seek pointer by 512
        if (act_read < 1)
            ser.position(0, 4)
            ser.fgcolor(ser#RED)
            perr(@"Read error: ", act_read)
            ser.fgcolor(ser#GREY)
            ser.charin{}
            ser.position(0, 4)
            ser.clearline{}

        ser.position(0, 5)
        ser.printf1(@"fseek(): %d   \n", pos)
        ser.hexdump(@_sect_buff, pos, 8, 512, 16)
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
                pos := sd.filesize{}-512
                sd.fseek(pos)
            "p":
                ser.printf1(@"Enter seek position: (0..%d)> ", sd.fend{})
                pos := ser.decin
                sd.fseek(pos)

#include "sderr.spinh"


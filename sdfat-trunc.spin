{
    --------------------------------------------
    Filename: sdfat-trunc.spin
    Author: Jesse Burt
    Description: FATfs on SD: truncate file to 0 bytes
    Copyright (c) 2022
    Started Jun 23, 2022
    Updated Jun 23, 2022
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

PUB Main | err, fn, sect

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
    err := sd.fopen(fn, sd#O_WRITE | sd#O_TRUNC)
    if (err < 0)
        perr(@"FOpen(): ", err)
        repeat

    ser.strln(@"updated FAT:")
    sect := sd.fat1start{}
    sd.rdblock(@_sect_buff, sect)
    ser.hexdump(@_sect_buff, 0, 4, 512, 16)

    repeat

#include "sderr.spinh"


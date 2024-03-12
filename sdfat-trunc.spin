{
---------------------------------------------------------------------------------------------------
    Filename:       sdfat-trunc.spin
    Description:    FATfs on SD: truncate file to 0 bytes
    Author:         Jesse Burt
    Started:        Jun 23, 2022
    Updated:        Mar 12, 2024
    Copyright (c) 2024 - See end of file for terms of use.
---------------------------------------------------------------------------------------------------
}

CON

    _clkmode    = cfg._clkmode
    _xinfreq    = cfg._xinfreq


OBJ

    cfg:    "boardcfg.flip"
    time:   "time"
    ser:    "com.serial.terminal.ansi" | SER_BAUD=115_200
    sd:     "memfs.sdfat" | CS=0, SCK=1, MOSI=2, MISO=3


VAR

    byte _sect_buff[512]


DAT

    _test_str byte "this is the test data", 0


PUB main() | err, fn, sect

    setup()

    fn := @"TEST0000.TXT"
    err := sd.fopen(fn, sd.O_WRITE | sd.O_TRUNC)
    if (err < 0)
        perror(@"fopen(): ", err)
        repeat

    ser.strln(@"updated FAT:")
    sect := sd.fat1_start()
    sd.rd_block(@_sect_buff, sect)
    ser.hexdump(@_sect_buff, 0, 4, 512, 16)

    repeat


PUB setup() | err

    ser.start()
    time.msleep(20)
    ser.clear()
    ser.strln(@"serial terminal started")

    err := sd.start()
    if (err < 0)
        ser.printf1(@"Error mounting SD card %x\n\r", err)
        repeat
    else
        ser.printf1(@"Mounted card (%d)\n\r", err)

#include "sderr.spinh"


DAT
{
Copyright 2024 Jesse Burt

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


{
---------------------------------------------------------------------------------------------------
    Filename:       sdfat-eedump.spin
    Description:    FATfs on SD: dump a 64KB EEPROM to a file on SD/FAT
    Author:         Jesse Burt
    Started:        Aug 25, 2022
    Updated:        Mar 11, 2024
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
    ee:     "memory.eeprom.24xxxx" | SCL=28, SDA=29, I2C_FREQ=400_000, I2C_ADDR=0


DAT

    { filename to create must be 8.3 format; pad with spaces if less than full length }
    _fname byte "P1EEPROM.BIN", 0


VAR

    byte _ee_buff[512]


PUB main() | err, dirent, ee_addr, ee_subpg

    setup()

    { open the file for writing, but truncate it to 0 first, in case it already exists and
        is non-zero in size }
    err := sd.fopen(@_fname, sd#O_WRITE | sd#O_TRUNC | sd#O_APPEND | sd#O_CREAT )
    if (err < 0)
        perror(@"Error opening: ", err)
        repeat

    ser.printf1(@"Opened %s\n\r", @_fname)
    ser.strln(@"dumping EEPROM to file...")
    repeat ee_addr from 0 to 65024 step 512
        ser.pos_xy(0, 5)
        ser.printf1(@"EE addr: %d\n\r", ee_addr)
        { read 4 pages from the EE at a time to fill the SD buffer for better efficiency }
        repeat ee_subpg from 0 to 3
            ee.rd_block_lsbf(   @_ee_buff + (ee.page_size() * ee_subpg), ...
                                ee_addr + (ee.page_size() * ee_subpg), ee.page_size())
        sd.fwrite(@_ee_buff, 512)

    ser.str(@"closing file...")
    sd.fclose()
    ser.strln(@"done")
    repeat


PUB setup() | err

    ser.start()
    time.msleep(20)
    ser.clear()
    ser.strln(@"serial terminal started")

    err := sd.start()
    if ( err < 0 )
        ser.printf1(@"Error mounting SD card %x\n\r", err)
        repeat
    else
        ser.printf1(@"Mounted card (%d)\n\r", err)

    if ( ee.start() )
        ser.strln(@"EEPROM driver started")
    else
        ser.strln(@"EEPROM driver failed to start - halting")
        repeat

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


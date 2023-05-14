{
    --------------------------------------------
    Filename: sdfat-eedump.spin
    Author: Jesse Burt
    Description: FATfs on SD: dump a 64KB EEPROM to a file on SD/FAT
    Copyright (c) 2023
    Started Aug 25, 2022
    Updated May 14, 2023
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

    { I2C configuration }
    I2C_SCL     = 28
    I2C_SDA     = 29
    I2C_FREQ    = 400_000
    ADDR_BITS   = 0
' --

OBJ

    cfg:    "boardcfg.flip"
    ser:    "com.serial.terminal.ansi"
    sd:     "memfs.sdfat"
    time:   "time"
    ee:     "memory.eeprom.24xxxx"

DAT

    { filename to create must be 8.3 format; pad with spaces if less than full length }
    _fname byte "P1EEPROM.BIN", 0

VAR

    byte _ee_page[512]

PUB main{} | err, dirent, ee_addr, ee_subpg

    setup{}

    err := sd.fcreate(@_fname, sd#FATTR_ARC)
    if (err < 0)
        if ( err <> sd.EEXIST )
            perror(string("Error creating file: "), err)
            repeat
    ser.strln(string("done"))

    { open the file for writing, but truncate it to 0 first, in case it already exists and
        is non-zero in size }
    err := sd.fopen(@_fname, sd#O_WRITE | sd#O_TRUNC | sd#O_APPEND)
    if (err < 0)
        perror(string("Error opening: "), err)
        repeat

    ser.printf1(string("Opened %s\n\r"), @_fname)

    ser.strln(string("dumping EEPROM to file..."))
    repeat ee_addr from 0 to 65024 step 512
        ser.printf1(string("EE addr: %d\n\r"), ee_addr)
        { read 4 pages from the EE at a time to fill the SD buffer for better efficiency }
        repeat ee_subpg from 0 to 3
            ee.rd_block_lsbf(@_ee_page + (ee.page_size{} * ee_subpg), {
}           ee_addr + (ee.page_size{} * ee_subpg), ee.page_size{})
        sd.fwrite(@_ee_page, 512)

    ser.str(string("closing file..."))
    sd.fclose{}
    ser.strln(string("done"))
    repeat

PUB setup{} | err

    ser.start(115_200)
    time.msleep(20)
    ser.clear{}
    ser.strln(string("serial terminal started"))

    err := sd.startx(CS_PIN, SCK_PIN, MOSI_PIN, MISO_PIN)
    if (err < 1)
        ser.printf1(string("Error mounting SD card %x\n\r"), err)
        repeat
    else
        ser.printf1(string("Mounted card (%d)\n\r"), err)

    if (ee.startx(I2C_SCL, I2C_SDA, I2C_FREQ, ADDR_BITS))
        ser.strln(string("EEPROM driver started"))
    else
        ser.strln(string("EEPROM driver failed to start - halting"))
        repeat

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


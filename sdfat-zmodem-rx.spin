{
    --------------------------------------------
    Filename: sdfat-zmodem-rx.spin
    Author: Jesse Burt
    Description: Receive a file over zmodem (second serial link) and save it to SD/FAT
    Copyright (c) 2022
    Started Aug 26, 2022
    Updated Aug 26, 2022
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

    { second UART configuration }
    COM_RX      = 16
    COM_TX      = 17
' --

OBJ

    cfg : "core.con.boardcfg.flip"
    ser : "com.serial.terminal.ansi"
    sd  : "memfs.sdfat"
    time: "time"
    com : "com.serial.terminal.ansi"

VAR

    long _rxcnt

PUB main | blk_cnt, rx

    setup{}

    wait_for_zm{}

    _rxcnt := blk_cnt := 0
    repeat
        _crc32 := $ffff_ffff
        bytefill(@_rxbuff, 0, 2048)
        repeat
            rx := zdlread{}
            if (rx == GOTCAN)
                ser.strln(string("TRANSFER CANCELLED - HALTING"))
                repeat
            elseif (rx & GOTOR)
                updcrc32(rx & $ff)
                quit
            else
                _rxbuff[blk_cnt++] := rx
                _rxcnt++
                if (blk_cnt == 512)             ' buffer full? write it to SD
                    com.char(XOFF)              ' tell the sender to pause transfer while writing
                    sd.fwrite(@_rxbuff, 512)
                    blk_cnt := 0
                    com.char(XON)
                updcrc32(rx)
                
        ser.position(0, 9)
        ser.printf2(string("Received: %d / %d bytes\n\r"), _rxcnt, _f_sz)
        if (checkcrc{} == ERROR)
            ser.strln(string("bad subpacket CRC"))
    until (rx & $ff) == ZCRCE                   ' last frame received

    if (blk_cnt)                                ' any more leftover data to write?
        com.char(XOFF)
        sd.fwrite(@_rxbuff, blk_cnt)
        com.char(XON)

    repeat until (zgethdr{} == ZEOF)
    zmtx_hexheader(ZRINIT, CANFC32 << 24)

    repeat until (zgethdr{} == ZFIN)
    zmtx_hexheader(ZFIN, 0)
    repeat 2
        repeat until (charin{} == "O")          ' Over and Out

    ser.strln(string("Transfer complete"))

    ser.str(string("closing file..."))
    sd.fclose{}
    ser.strln(string("done"))
    repeat

pub check_sd_filename{}: err
' Check SD card for filename received from sender
    if ((sd.find(@_f_name)) == sd#ENOTFOUND)
        { file doesn't exist yet; create it }
        ser.printf1(string("'%s' doesn't exist; creating..."), @_f_name)
        err := sd.fcreate(@_f_name, sd#FATTR_ARC)
        if (err < 0)
            perror(string("Error creating file: "), err)
            repeat
        sd.fclose
        ser.strln(string("done"))
        err := sd.fopen(@_f_name, sd#O_WRITE | sd#O_APPEND)
    else
        { file already exists; truncate it to 0 first, and we'll just overwrite it }
        ser.printf1(string("'%s' already exists; overwriting..."), @_f_name)
        err := sd.fopen(@_f_name, sd#O_WRITE | sd#O_TRUNC)
        if (err < 0)
            perror(string("Error opening:"), err)
            repeat

pub wait_for_zm{}

    _subpsz := 1024
    longfill(@_f_sz, 0, 6)

    ser.strln(string("Waiting for transfer..."))
    repeat until (zgethdr{} == ZRQINIT)

    zmtx_hexheader(ZRINIT, CANFC32 << 24)

    if (getfileinfo{} == ZFILE)
        ser.printf1(string("Filename: %s\n\r"), @_f_name)
        ser.printf1(string("Size    : %u\n\r"), _f_sz)
    else
        ser.strln(string("error: wrong frame type or bad CRC"))
        repeat 8
            char(CAN)
        repeat                                  ' halt

    check_sd_filename{}

    ser.printf1(string("frame type: %x\n\r"), zmrx_frameend{})

    zmtx_hexheader(ZRPOS, 0)

    repeat until (zgethdr == ZDATA)

PUB char(ch)

    com.char(ch)

PUB charin{}

    return com.charin{}

PUB setup{} | err

    com.startrxtx(COM_RX, COM_TX, 0, 19200)
    ser.start(115_200)
    time.msleep(10)
    ser.clear{}
    ser.strln(string("serial terminal started"))

    err := sd.startx(CS_PIN, SCK_PIN, MOSI_PIN, MISO_PIN)
    if (err < 1)
        ser.printf1(string("Error mounting SD card %x\n\r"), err)
        repeat
    else
        ser.printf1(string("Mounted card (%d)\n\r"), err)

#include "sderr.spinh"
#include "protocol.file-xfer.zmodem.spinh"

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


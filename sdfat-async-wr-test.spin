{
    --------------------------------------------
    Filename: sdfat-async-wr-test.spin
    Author: Jesse Burt
    Description: FATfs on SD: async write logic test
    Copyright (c) 2022
    Started Aug 31, 2022
    Updated Aug 31, 2022
    See end of file for terms of use.
    --------------------------------------------
}

CON

    _clkmode    = cfg#_clkmode
    _xinfreq    = cfg#_xinfreq

    FILESZ      = 1307
    SYNC_IO     = 1
    O_RDWR      = 2

    ERDIO       = -2

OBJ

    cfg : "core.con.boardcfg.flip"
    ser : "com.serial.terminal.ansi"
    time: "time"

VAR

    long _fseek_sect
    word _sect_offs                             ' write pointer in current sector buffer
    byte _sect_buff[512]                        ' sector buffer
    byte _disk[2048]                            ' simulated disk part
    word _sect_wr_ptr
    byte _fmode

DAT

    _linc file "lincoln.txt"                    ' Abe Lincoln quotes from Parallax Propeller Tool

pub main{} | i

'    _fmode := SYNC_IO

    setup{}
    fwrite(@_linc, 1307)

    repeat

pub flush_sect_buff{}
' Flush sector buffer to disk
    sd_wr_block(@_sect_buff+_sect_wr_ptr, _fseek_sect)

pub fwrite(ptr_buff, len): wr_cnt | nr_left, mov_cnt, rd_ptr, resp

    mov_cnt := rd_ptr := 0
    nr_left := len
    repeat
        if (_fmode & O_RDWR)
            { read the sector's current contents, so it can be merged with this write }
            resp := sd_rd_block(@_sect_buff, _fseek_sect)
            if (resp < 1)
                return ERDIO

        { 1. queue user data in the sector buffer, _up to_ 512 bytes at a time }
        mov_cnt := 512 <# nr_left
        ser.fgcolor(ser.bright|ser.yellow)
        ser.printf1(@"queuing %d bytes\n\r", mov_cnt)
        ser.fgcolor(ser.grey)
        bytefill(@_sect_buff, 0, 512)
        bytemove(@_sect_buff+_sect_wr_ptr, ptr_buff+rd_ptr, mov_cnt)
        ser.hexdump(@_sect_buff, 0, 4, mov_cnt, 32)
        { if the buffer is full (or if synchronous I/O is requested), write the buffer to disk }
        if ((mov_cnt == 512) or (_fmode & SYNC_IO))
            ser.fgcolor(ser.green)
            ser.strln(@"buffer full or SYNC_IO set - writing block")
            ser.fgcolor(ser.grey)
            sd_wr_block(@_sect_buff+_sect_wr_ptr, _fseek_sect)
'            ser.hexdump(@_disk, 0, 4, 1307, 32)
'            ser.hexdump(@_sect_buff, 0, 4, 512, 32)
            ser.charin
            _fseek_sect++
        else
            _sect_wr_ptr += mov_cnt             ' advance sector write pointer by amount written
        rd_ptr += mov_cnt                       ' and the user data buffer by the same
        nr_left -= mov_cnt
    while (nr_left > 0)

    return

pub sd_rd_block(ptr_buff, blkaddr)
' simulated SD read
    bytemove(@_sect_buff, @_disk+(blkaddr*512), 512)

pub sd_wr_block(ptr_buff, blkaddr)
' simulated SD write
    bytemove(@_disk+(blkaddr*512), ptr_buff, 512)

PUB setup{} | err

    ser.start(115_200)
    time.msleep(10)
    ser.clear{}
    ser.strln(string("serial terminal started"))

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


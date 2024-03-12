{
---------------------------------------------------------------------------------------------------
    Filename:       sdfat-clustmap.spin
    Description:    FAT/cluster map tool
    Author:         Jesse Burt
    Started:        May 13, 2023
    Updated:        Mar 11, 2024
    Copyright (c) 2024 - See end of file for terms of use.
---------------------------------------------------------------------------------------------------
}

CON

    _clkmode    = cfg._clkmode
    _xinfreq    = cfg._xinfreq


OBJ

    cfg:    "boardcfg.flip"
    ser:    "com.serial.terminal.ansi" | SER_BAUD=115_200
    sd:     "memfs.sdfat" | CS=22+3, SCK=22+1, MOSI=22+2, MISO=22+0
    time:   "time"


PUB main() | sect, fat_nr, tmp, fat_entry, first_ent, last_ent, new_val

    setup()

    sect := 0                                   ' relative to FAT1 start sector
    sd.read_fat(sect)

    repeat
        if ( (sect => 0) and (sect < sd.sects_per_fat()) )
            fat_nr := 1
        elseif ( (sect => sd.sects_per_fat()) and (sect < sd.sects_per_fat() * 2) )
            fat_nr := 2
        ser.pos_xy(0, 3)
        ser.printf2(@"FAT #%d, sector %d", fat_nr, sd.fat1_start()+sect)
        ser.clear_line()
        ser.newline()
        ser.hexdump(sd.getsbp(), 0, 4, 512, 16)
        case ser.getchar()
            "[":                                ' read prev FAT sector (limited to fat1_start())
                sect := 0 #> (sect - 1)
                sd.read_fat(sect)
            "]":                                ' read next FAT sector (limited to sects_per_fat())
                sect := (sect + 1) <# (sd.sects_per_fat() * 2)
                sd.read_fat(sect)
            "s":                                ' read first FAT sector
                sect := 0
                sd.read_fat(sect)
            "e":                                ' read last FAT sector
                sect := sd.sects_per_fat()-1
                sd.read_fat(sect)
            "n":                                ' add a new entry
                ser.set_attrs(ser.ECHO)
                repeat
                    ser.str(@"FAT entry to add (decimal, 0..127)? ")
                    tmp := ser.getdec()
                    if ( (tmp < 0) or (tmp > 127) )
                        ser.fgcolor(ser.RED)
                        ser.strln(@" invalid entry - retry")
                        ser.fgcolor(ser.GREY)
                        next
                    ser.newline()
                    quit
                fat_entry := sd.read_fat_entry(tmp)
                repeat
                    ser.printf1(@"Entry current value: %08.8x\n\r", fat_entry)
                    ser.str(@"New entry (hex, 0..0fffffff)? ")
                        new_val := ser.gethex()
                        if ( (new_val < 0) or (new_val > $0fff_ffff) )
                            ser.fgcolor(ser.RED)
                            ser.strln(@" invalid entry - retry")
                            ser.fgcolor(ser.GREY)
                            next
                        ser.newline()
                        quit
                ser.set_attrs(0)
                sd.write_fat_entry(tmp, new_val)
            "c":                                ' clear FAT entry (in memory only)
                ser.set_attrs(ser.ECHO)
                repeat
                    ser.str(@"FAT entry to clear (decimal, 0..127)? ")
                    tmp := ser.getdec()
                    if ( (tmp < 0) or (tmp > 127) )
                        ser.fgcolor(ser.RED)
                        ser.strln(@" invalid entry - retry")
                        ser.fgcolor(ser.GREY)
                        next
                    ser.newline()
                    quit
                ser.set_attrs(0)
                fat_entry := sd.read_fat_entry(tmp)
                ser.printf1(@"Entry current value: %08.8x\n\r", fat_entry)
                sd.write_fat_entry(tmp, 0)
            "C":                                ' clear range of FAT entries (in memory only)
                ser.set_attrs(ser.ECHO)
                repeat
                    ser.str(@"First FAT entry to clear (decimal, 0..127)? ")
                    first_ent := ser.getdec()
                    if ( (first_ent < 0) or (first_ent > 127) )
                        ser.fgcolor(ser.RED)
                        ser.strln(@" invalid entry - retry")
                        ser.fgcolor(ser.GREY)
                        next
                    ser.newline()
                    quit
                repeat
                    ser.printf1(@"Last FAT entry to clear (decimal, %d..127)? ", first_ent)
                    last_ent := ser.getdec()
                    if ( (last_ent < first_ent) or (last_ent > 127) )
                        ser.fgcolor(ser.RED)
                        ser.strln(@" invalid entry - retry")
                        ser.fgcolor(ser.GREY)
                        next
                    ser.newline()
                    quit
                ser.set_attrs(0)
                fat_entry := sd.read_fat_entry(tmp)
                ser.printf1(@"Entry current value: %08.8x\n\r", fat_entry)
                repeat tmp from first_ent to last_ent
                    sd.write_fat_entry(tmp, 0)
            "w":                                ' write changes to SD
                sd.write_fat(sect)
                sd.read_fat(sect)
    repeat


PUB setup() | err

    ser.start()
    time.msleep(30)
    ser.clear()
    ser.strln(@"serial terminal started")

    err := sd.start()
    if (err < 0)
        ser.printf1(@"Error mounting SD card %x\n\r", err)
        repeat
    else
        ser.printf1(@"Mounted card (%d)\n\r", err)


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


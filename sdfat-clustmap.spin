{
    --------------------------------------------
    Filename: sdfat-clustmap.spin
    Author: Jesse Burt
    Description: FAT/cluster map tool
    Copyright (c) 2023
    Started May 13, 2023
    Updated May 13, 2023
    See end of file for terms of use.
    --------------------------------------------
}
CON

    _clkmode    = xtal1+pll16x
    _xinfreq    = 5_000_000

' --
    { SPI configuration }
    CS_PIN      = 3
    SCK_PIN     = 1
    MOSI_PIN    = 2
    MISO_PIN    = 0
' --

OBJ

    ser:    "com.serial.terminal.ansi"
    time:   "time"
    sd:     "memfs.sdfat"

PUB main() | sect, fat_nr, tmp, fat_entry

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
                sect := (sect + 1) <# sd.sects_per_fat()
                sd.read_fat(sect)
            "s":                                ' read next FAT sector (limited to sects_per_fat())
                sect := 0
                sd.read_fat(sect)
            "e":                                ' read next FAT sector (limited to sects_per_fat())
                sect := sd.sects_per_fat()-1
                sd.read_fat(sect)
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
                fat_entry := sd.clust_rd(tmp)
                ser.printf1(@"Entry current value: %08.8x\n\r", fat_entry)
                sd.clust_wr(tmp, 0)
            "w":                                ' write changes to SD
                sd.write_fat(sect)
                sd.read_fat(sect)
    repeat

PUB setup() | err

    ser.start(115_200)
    time.msleep(30)
    ser.clear()
    ser.strln(string("serial terminal started"))

    err := sd.startx(CS_PIN, SCK_PIN, MOSI_PIN, MISO_PIN)
    if (err < 1)
        ser.printf1(string("Error mounting SD card %x\n\r"), err)
        repeat
    else
        ser.printf1(string("Mounted card (%d)\n\r"), err)


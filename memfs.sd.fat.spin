{
    --------------------------------------------
    Filename: mem-fs.sd.fat.spin
    Author: Jesse Burt
    Description: FAT32-formatted SDHC/XC driver
    Copyright (c) 2022
    Started Aug 1, 2021
    Updated Jun 6, 2022
    See end of file for terms of use.
    --------------------------------------------
}

CON

' Error codes
    ENOTFOUND   = -2                            ' no such file or directory
    EEOF        = -3                            ' end of file
    EBADSEEK    = -4                            ' bad seek value
    EWRONGMODE  = -5                            ' illegal operation for file mode
    EOPEN       = -6                            ' already open
    ENOTOPEN    = -7                            ' no file open

    ENOTIMPLM   = -256                          ' not implemented
    EWRIO       = -512 {$ff_ff_e0_00}           ' I/O error (writing)
    ERDIO       = -513 {$ff_ff_fd_ff}           ' I/O error (reading)

' File open modes
    O_RDONLY    = (1 << 0)                      ' R
    O_WRITE     = (1 << 1)                      ' W (writes _overwrite_)
    O_RDWR      = O_RDONLY | O_WRITE            ' R/W

VAR

    long _fseek_pos, _fseek_sect
    word _sect_offs
    byte _sect_buff[sd#SECT_SZ]
    byte _fmode

OBJ

    sd  : "memory.flash.sd.spi"
    fat : "filesystem.block.fat"
    str : "string"
    ser : "com.serial.terminal.ansi-new"
    time: "time"

PUB Null{}
' This is not a top-level object

PUB Startx(SD_CS, SD_SCK, SD_MOSI, SD_MISO): status

    ser.startrxtx(24, 25, 0, 115200)
    time.msleep(10)
    ser.clear
    ser.strln(@"SD/FAT debug started")
    status := sd.init(SD_CS, SD_SCK, SD_MOSI, SD_MISO)
    if lookdown(status: 1..8)
        mount{}
        return
    return status

PUB Mount{}: status
' Mount SD card
'   Read SD card boot sector and sync filesystem info
    fat.init(@_sect_buff)                       ' point FATfs object to sector buffer
    sd.rdblock(@_sect_buff, 0)                  ' read boot sector into sector buffer
    fat.syncpart{}                              ' get sector # of 1st partition

    sd.rdblock(@_sect_buff, fat.partstart{})    ' now read that sector into sector buffer
    fat.syncbpb{}                               ' update all of the FAT fs data from it

PUB AllocClust{}: status | avail, last, tmp, resp
' Allocate a new cluster
    ifnot (lookdown(_fmode: O_RMWR, O_WRITE, O_APPEND))
        return EWRONGMODE

    { find a free cluster, starting from the file's first cluster }
    avail := findfreeclust(fat.filefirstclust{})
    if (avail < 3)
        return avail                            ' catch err from FindFreeClust()
    last := findlastclust{}
    bytefill(@_sect_buff, 0, 512)
    resp := sd.rdblock(@_sect_buff, fat.fat1start{})
    if (resp <> 512)
        return ERDIO

    { overwrite the FAT entry currently marked as the EOC with a pointer to
        the next available entry }
    bytemove(@_sect_buff+(last*4), @avail, 4)

    { write the EOC marker into the newly allocated entry }
    tmp := fat#MRKR_EOC
    bytemove(@_sect_buff+(avail*4), @tmp, 4)

    { write the updated FAT sector to SD }
    resp := sd.wrblock(@_sect_buff, fat.fat1start{})
    if (resp <> 512)
        return EWRIO
    return avail

PUB FClose{}: status
' Close the currently opened file
'   Returns:
'       0 on success
'       ENOTOPEN if a file isn't currently open
    ifnot (fat.filenum{})
        return ENOTOPEN                         ' file isn't open
    _fseek_pos := 0
    _fseek_sect := 0
    _fmode := 0
    fat.fclose{}
    return 0

PUB FileSize{}: sz
' Get size of opened file
    return fat.filesize{}

PUB Find(ptr_str): dirent | rds, endofdir, name_tmp[3], ext_tmp[2], name_uc[3], ext_uc[2]
' Find file, by name
'   Valid values:
'       ptr_str: pointer to space-padded string containing filename (8.3)
'   Returns:
'       directory entry of file (0..n)
'       or ENOTFOUND (-2) if not found
    dirent := 0
    rds := 0
    endofdir := false
    repeat                                      ' check each rootdir sector
        sd.rdblock(@_sect_buff, fat.rootdirsector{}+rds)
        dirent := 0

        repeat 16                               ' check each file in the sector
            fat.fopen(dirent)                   ' get current file's info
            if (fat.direntneverused{})          ' last directory entry
                endofdir := true
                quit
            if (fat.fileisdeleted{})            ' ignore deleted files
                next
            str.left(@name_tmp, ptr_str, 8)     ' filename is leftmost 8 chars
            str.right(@ext_tmp, ptr_str, 3)     ' ext. is rightmost 3 chars
            name_uc := str.upper(@name_tmp)     ' convert to uppercase
            ext_uc := str.upper(@ext_tmp)
            if strcomp(fat.filename{}, name_uc) and {
}           strcomp(fat.filenameext{}, ext_uc)  ' match found for filename; get
                return dirent+(rds * 16)        '   number relative to entr. 0
            dirent++
        rds++                                   ' go to next root dir sector
    until endofdir
    return ENOTFOUND

PUB FindFreeClust(st_from): avail | sect_offs, fat_ent, fat_ent_prev, resp
' Find a free cluster, starting from cluster #
'   LIMITATIONS:
'   * only works on 1st sector of FAT
'   * doesn't return to the beginning of the FAT to look before the file's first cluster
    avail := 0
    fat_ent := st_from
    resp := sd.rdblock(@_sect_buff, fat.fat1start{})    ' read the FAT
    if (resp <> 512)
        return ERDIO
    repeat
        sect_offs := (fat_ent * 4)              ' conv fat entry # to sector offset
        fat_ent_prev := fat_ent
        { read next entry in chain }
        bytemove(@fat_ent, (@_sect_buff + sect_offs), 4)
    while (fat_ent <> fat#MRKR_EOC)

    { starting with the entry immediately after the EOC, look for an unused/available
        entry }
    sect_offs := (fat_ent_prev + 1) * 4
    repeat while (sect_offs < 508)
        bytemove(@fat_ent, (@_sect_buff + sect_offs), 4)
        if (fat_ent == 0)                       ' found a free one
            avail := (sect_offs / 4)
            quit
        sect_offs += 4                          ' none yet; next FAT entry

PUB FindLastClust{}: cl_nr | sect_offs, fat_ent, fat_ent_prev, resp
' Find last cluster # of file
'   LIMITATIONS:
'       * stays on first sector of FAT
    cl_nr := 0
    fat_ent := fat.filefirstclust{}
    resp := sd.rdblock(@_sect_buff, fat.fat1start{})    ' read the FAT
    if (resp <> 512)
        return ERDIO                            ' catch read error from SD
    repeat
        sect_offs := (fat_ent * 4)              ' conv fat entry # to sector offset
        fat_ent_prev := fat_ent
        { read next entry in chain }
        bytemove(@fat_ent, (@_sect_buff + sect_offs), 4)
    while (fat_ent <> fat#MRKR_EOC)
    return (sect_offs / 4)

PUB FOpen(fn_str, mode): status
' Open file for subsequent operations
'   Valid values:
'       fn_str: pointer to string containing filename (must be space padded)
'       mode: READ (0), or WRITE (1)
'   Returns:
'       file number (dirent #) if successful,
'       or error
    'xxx test already open
    status := find(fn_str)                      ' look for file by name
    if (status == ENOTFOUND)                    ' file not found
        return ENOTFOUND
    fat.fopen(status & $0F)                     ' mask is to keep within # root dir entries per rds
    _fseek_pos := 0
    _fseek_sect := fat.filefirstsect{}          ' initialize current sector with file's first
    _fmode := mode
    return fat.filenum{}

PUB FRead(ptr_dest, nr_bytes): nr_read | nr_left, movbytes, resp
' Read a block of data from current seek position of opened file into ptr_dest
'   Valid values:
'       ptr_dest: pointer to buffer to copy data read
'       nr_bytes: 1..512, or the size of the file, whichever is smaller
'   Returns:
'       number of bytes actually read,
'       or error
    ifnot (fat.filenum{})                       ' no file open
        return ENOTOPEN

    nr_read := nr_left := 0

    ' make sure current seek isn't already at the EOF
    if (_fseek_pos < fat.filesize{})
        { clamp nr_bytes to physical limits:
            sector size, file size, and proximity to end of file }
        nr_bytes := nr_bytes <# fat.bytespersect{} <# fat.filesize{} <# (fat.filesize{}-_fseek_pos) ' XXX seems like this should be -1

        { read a block from the SD card into the internal sector buffer,
            and copy as many bytes as possible from it into the user's buffer }
        resp := sd.rdblock(@_sect_buff, _fseek_sect)
        if (resp < 1)
            return ERDIO

        movbytes := fat.bytespersect{}-_sect_offs
        bytemove(ptr_dest, @_sect_buff+_sect_offs, movbytes <# nr_bytes)
        nr_read := (nr_read + movbytes) <# nr_bytes
        nr_left := (nr_bytes - nr_read)

        if (nr_left > 0)
            ' read the next block from the SD card, and copy the remainder
            '   of the requested length into the user's buffer
            sd.rdblock(@_sect_buff, _fseek_sect)
            bytemove(ptr_dest+nr_read, @_sect_buff, nr_left)
            nr_read += nr_left
        fseek(_fseek_pos + nr_read)             ' update seek pointer
        return nr_read
    else
        return EEOF                             ' reached end of file

PUB FSeek(pos): status | seek_clust, clust_offs, rel_sect_nr, clust_nr, fat_sect, sect_offs
' Seek to position in currently open file
'   Valid values:
'       pos: 0 to file size-1
'   Returns:
'       position seeked to,
'       or error
    ifnot (fat.filenum{})
        return ENOTOPEN                         ' no file open
    if (pos < 0) or (pos => fat.filesize{})     ' catch bad seek positions;
        return EBADSEEK                         '   return error
    longfill(@seek_clust, 0, 4)                 ' clear local vars

    { initialize cluster number with the file's first cluster number }
    clust_nr := fat.filefirstclust{}

    { determine which cluster (in "n'th" terms) in the chain the seek pos. is }
    seek_clust := (pos / fat.bytesperclust{})

    { use remainder to get byte offset within cluster (0..cluster size-1) }
    clust_offs := (pos // fat.bytesperclust{})

    { use high bits of offset within cluster to get sector offset (0..sectors per cluster-1)
        within the cluster }
    rel_sect_nr := (clust_offs >> 9)

    { follow the cluster chain to determine which actual cluster it is }
    fat_sect := (clust_nr >> 7)
    readfat(fat_sect)
    repeat seek_clust
        { 128 clusters per FAT sector (0..127), so any bits above bit 7
            can be used to determine which sector of the FAT should be read }
        sect_offs := (clust_nr * 4)              ' conv fat entry # to sector offset
        { read next entry in chain }
        bytemove(@clust_nr, (@_sect_buff + sect_offs), 4)
        sect_offs += 4

    { set the absolute sector number and the seek position for subsequent R/W:
        translate the cluster number to a sector number on the SD card, and add the
        sector offset from above
        also, set offset within sector to find the start of the data (0..bytes per sector-1) }
    _fseek_sect := fat.clust2sect(clust_nr)+rel_sect_nr
    _fseek_pos := pos
    _sect_offs := (pos // fat.bytespersect{})
    return pos

PUB FWrite(ptr_buff, len): status | sect_wrsz, nr_left
' Write buffer to card
'   ptr_buff: address of buffer to write to SD
'   len: number of bytes to write from buffer
'       NOTE: a full sector is always written
    ifnot (fat.filenum{})
        return ENOTOPEN
    ifnot (_fmode & O_WRITE)
        return EWRONGMODE

    nr_left := len                              ' init to total write length
    repeat while (nr_left > 0)
        sect_wrsz := (sd#SECT_SZ - _sect_offs) <# nr_left
        bytefill(@_sect_buff, 0, fat.bytespersect{})
        if (_fmode & O_RMW)                     ' read-modify-write mode
        { read the sector's current contents, so it can be merged with this write }
            sd.rdblock(@_sect_buff, _fseek_sect)

        { copy the next chunk of data to the sector buffer }
        bytemove(@_sect_buff+_sect_offs, ptr_buff+(len-nr_left), sect_wrsz)

        status := sd.wrblock(@_sect_buff, _fseek_sect)
        if (status == sd#SECT_SZ)
            { update position to advance by how much was just written }
            fseek(_fseek_pos+sect_wrsz)
            nr_left -= sect_wrsz

PUB ReadFAT(fat_sect): resp
' Read the FAT into the sector buffer
'   fat_sect: sector of the FAT to read
    resp := sd.rdblock(@_sect_buff, (fat.fat1start + fat_sect))

' below: temporary, for devel purposes

PUB NextCluster{}: c
    c := 0
    return fat.nextcluster

pub fat1start

    return fat.fat1start

pub sectorspercluster

    return fat.sectorspercluster

pub datastart

    return fat.datastart

pub filenextclust

    return fat.filenextclust

pub bytesperclust

    return fat.bytesperclust

pub clust2sect(c): s

    return fat.clust2sect(c)

pub filefirstclust{}

    return fat.filefirstclust

pub filefirstsect{}

    return fat.filefirstsect

pub filenum

    return fat.filenum

pub rdblock(ptr, sect)

    return sd.rdblock(ptr, sect)

pub rootdirsector

    return fat.rootdirsector

pub wrblock(ptr, sect): resp

    return sd.wrblock(ptr, sect)

pub getpos

    return _fseek_pos

pub getsbp

    return @_sect_buff

DAT
{
    --------------------------------------------------------------------------------------------------------
    TERMS OF USE: MIT License

    Permission is hereby granted, free of charge, to any person obtaining a copy of this software and
    associated documentation files (the "Software"), to deal in the Software without restriction, including
    without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the
    following conditions:

    The above copyright notice and this permission notice shall be included in all copies or substantial
    portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT
    LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
    IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
    WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
    SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
    --------------------------------------------------------------------------------------------------------
}


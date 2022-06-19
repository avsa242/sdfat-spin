{
    --------------------------------------------
    Filename: memfs.sdfat.spin
    Author: Jesse Burt
    Description: FAT32-formatted SDHC/XC driver
    Copyright (c) 2022
    Started Jun 11, 2022
    Updated Jun 19, 2022
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
    ECL_INUSE   = -8                            ' cluster in use
    EEXIST      = -9                            ' file already exists
    ENOSPC      = -10                           ' no space left on device or no free clusters
    EINVAL      = -11                           ' invalid argument

    ENOTIMPLM   = -256                          ' not implemented
    EWRIO       = -512 {$ff_ff_e0_00}           ' I/O error (writing)
    ERDIO       = -513 {$ff_ff_fd_ff}           ' I/O error (reading)

' File open modes
    O_RDONLY    = (1 << 0)                      ' R
    O_WRITE     = (1 << 1)                      ' W (writes _overwrite_)
    O_RDWR      = O_RDONLY | O_WRITE            ' R/W
    O_CREAT     = (1 << 2)                      ' create file
    O_APPEND    = (1 << 3)                      ' W (allow file to grow)

VAR

    long _fseek_pos, _fseek_sect
    word _sect_offs
    byte _sect_buff[sd#SECT_SZ]
    byte _fmode

OBJ

    sd  : "memory.flash.sd.spi"
    str : "string"
    ser : "com.serial.terminal.ansi-new"
    time: "time"

PUB Startx(SD_CS, SD_SCK, SD_MOSI, SD_MISO): status

    ser.startrxtx(24, 25, 0, 115200)
    time.msleep(10)
    ser.clear
    ser.strln(string("SD/FAT debug started"))
    status := sd.init(SD_CS, SD_SCK, SD_MOSI, SD_MISO)
    if lookdown(status: 1..8)
        mount{}
        return
    return status

PUB Mount{}: status
' Mount SD card
'   Read SD card boot sector and sync filesystem info
'   Returns:
'       0 on success
'       negative number on error
    status := 0

    { point FATfs object to sector buffer }
    init(@_sect_buff)

    { read the MBR }
    status := sd.rdblock(@_sect_buff, MBR)
    if (status < 0)
        return status

    { get 1st partition's 1st sector number from it }
    status := readpart{}
    if (status < 0)
        return status

    { now read that sector }
    status := sd.rdblock(@_sect_buff, partstart{})
    if (status < 0)
        return status

    { sync the FATfs metadata from it }
    status := readbpb{}
    if (status < 0)
        return status

PUB AllocClust(cl_nr): status | tmp, fat_sect
' Allocate a new cluster
    ser.strln(string("AllocClust():"))
    ifnot (_fmode & O_WRITE)                    ' file must be opened for writing
        ser.strln(string("bad file mode"))
        return EWRONGMODE

    { read FAT sector }
    fat_sect := clustnum2fatsect(cl_nr)
    if (readfat(fat_sect) <> 512)
        ser.printf1(string("read error %d\n\r"), status)
        return ERDIO

    { check the requested cluster number - is it free? }
    if (clustrd(cl_nr) <> 0)
        ser.strln(@"cluster in use")
        return ECL_INUSE

    { write the EOC marker into the newly allocated entry }
    clustwr(cl_nr, CLUST_EOC)

    { write the updated FAT sector to SD }
    ser.strln(string("updated FAT: "))
    ser.hexdump(@_sect_buff, 0, 4, 512, 16)
    if (writefat(fat_sect) <> 512)
        ser.strln(string("write error"))
        return EWRIO

    ser.strln(string("AllocClust(): [ret]"))
    return cl_nr

PUB AllocClustBlock(cl_st_nr, count): status | cl_nr, tmp, last_cl, fat_sect
' Allocate a block of contiguous clusters
'   cl_st_nr: starting cluster number
'   count: number of clusters to allocate
'   Returns:
'       number of clusters allocated on success
'       negative number on error
    ser.strln(@"AllocClustBlock():")

    { validate the starting cluster number and count }
    if ((cl_st_nr < 3) or (count < 1))
        return EINVAL

    { read FAT sector }
    fat_sect := clustnum2fatsect(cl_st_nr)
    if (readfat(fat_sect) <> 512)
        ser.printf1(string("read error %d\n\r"), status)
        return ERDIO

    last_cl := (cl_st_nr + (count-1))
    { before trying to allocate clusters, check that the requested number of them are free }
    repeat cl_nr from cl_st_nr to last_cl
        ser.printf1(@"cluster %d? ", cl_nr)
        if (clustrd(cl_nr) <> 0)
            ser.strln(@"in use - fail")
            return ENOSPC                       ' cluster is in use
        ser.strln(@"free")

    { link clusters, from first to one before the last one }
    repeat cl_nr from cl_st_nr to (last_cl-1)
        clustwr(cl_nr, (cl_nr + 1))

    { mark last cluster as the EOC }
    clustwr(last_cl, CLUST_EOC)

    { write updated FAT sector }
    if (writefat(fat_sect) <> 512)
        ser.printf1(string("write error %d\n\r"), status)
        return EWRIO

    return count

PUB DirentUpdate(dirent_nr): status
' Update a directory entry on disk
'   dirent_nr: directory entry number
    ser.strln(string("DirentUpdate()"))
    ser.printf1(@"called with: %d\n\r", dirent_nr)

    { read root dir sect }
    ser.strln(@"rdblock")
    status := sd.rdblock(@_sect_buff, dirent2abssect(dirent_nr))
    if (status < 0)
        ser.strln(string("read error"))
        return ERDIO

    { copy currently cached dirent to sector buffer }
    bytemove(@_sect_buff+direntstart(dirent_nr), @_dirent, DIRENT_LEN)

    { write root dir sect back to disk }
    ser.strln(@"wrblock")
    status := sd.wrblock(@_sect_buff, dirent2abssect(dirent_nr))
    if (status < 0)
        ser.strln(string("write error"))
        return EWRIO
    ser.strln(@"[ret]")

PUB FClose2{}: status
' Close the currently opened file
'   Returns:
'       0 on success
'       ENOTOPEN if a file isn't currently open
    ifnot (fnumber{})
        return ENOTOPEN                         ' file isn't open
    _fseek_pos := 0
    _fseek_sect := 0
    _fmode := 0
    fclose{}
    return 0

PUB FCreate(fn_str, attrs): status | dirent_nr, ffc
' Create file
'   fn_str: pointer to string containing filename
'   attrs: initial file attributes

    { first, verify a file with the same name doesn't already exist }
    if (find(fn_str) <> ENOTFOUND)
        return EEXIST

    { find a free directory entry, and open it read/write }
    dirent_nr := findfreedirent{}
    fopenent(dirent_nr, O_RDWR)
    ser.printf1(string("found dirent # %d\n\r"), dirent_nr)

    { find a free cluster, starting at the beginning of the FAT }
    ffc := findfreeclust(3)
    ser.printf1(string("first free cluster: %x\n\r"), ffc)
    if (ffc < 3)
        return ENOSPC

    { set up the file's initial metadata }
    fsetfname(fn_str)
    fsetext(fn_str+9)   'XXX expects string at fn_str to be in '8.3' format, _with_ the period
    fsetattrs(attrs)
    fsetsize(0)
    fsetfirstclust(ffc)
    direntupdate(dirent_nr)

    { allocate a cluster }
    allocclust(ffc)

    return dirent_nr

PUB FDelete(fn_str): status | dirent, clust_nr, fat_sect, nx_clust, tmp
' Delete a file
'   fn_str: pointer to string containing filename
'   Returns:
'       existing directory entry number on success
'       negative numbers on failure
    ser.strln(@"FDelete()")
    { verify file exists }
    dirent := find(fn_str)
    if (dirent < 0)
        return ENOTFOUND

    { rename file with first byte set to FATTR_DEL ($E5) }
    fopenent(dirent, O_RDWR)
    fsetdeleted{}
    direntupdate(dirent)

    { clear the file's entire cluster chain to 0 }
    clust_nr := ffirstclust{}
    fat_sect := clustnum2fatsect(clust_nr)
    status := readfat(fat_sect)
    if (status <> 512)
        ser.strln(string("read error"))
        return ERDIO

    repeat ftotalclust{}
        { read next entry in chain before clearing the current one - need to know where
            to go to next beforehand }
        nx_clust := clustrd(clust_nr)
        clustwr(clust_nr, 0)
        clust_nr := nx_clust

    { write modified FAT back to disk }
    if (writefat(fat_sect) <> 512)
        ser.printf1(string("write error %d\n\r"), status)
        return EWRIO

    return dirent

PUB FileSize{}: sz
' Get size of opened file
    return fsize{}

PUB Find(ptr_str): dirent | rds, endofdir, name_tmp[3], ext_tmp[2], name_uc[3], ext_uc[2]
' Find file, by name
'   Valid values:
'       ptr_str: pointer to space-padded string containing filename (8.3)
'   Returns:
'       directory entry of file (0..n)
'       or ENOTFOUND (-2) if not found
    ser.strln(@"Find():")
    dirent := 0
    rds := 0
    endofdir := false
    str.left(@name_tmp, ptr_str, 8)             ' filename is leftmost 8 chars
    str.right(@ext_tmp, ptr_str, 3)             ' ext. is rightmost 3 chars
    name_uc := str.upper(@name_tmp)             ' convert to uppercase
    ext_uc := str.upper(@ext_tmp)
    repeat                                      ' check each rootdir sector
        sd.rdblock(@_sect_buff, rootdirsect{}+rds)
        dirent := 0

        repeat DIRENTS                          ' check each file in the sector
            readdirent(dirent)                  ' get current file's info
            if (direntneverused{})              ' last directory entry
                endofdir := true
                quit
            if (fdeleted{})                     ' ignore deleted files
                dirent++
                next
            if strcomp(fname{}, name_uc) and {
}           strcomp(fnameext{}, ext_uc)         ' match found for filename; get
                fclose{}
                return (dirent+(rds * DIRENTS)) '   number relative to entr. 0
            dirent++
        rds++                                   ' go to next root dir sector
    until endofdir
    ser.strln(@"error: not found")
    return ENOTFOUND

PUB FindFreeClust(st_from): avail | sect_offs, fat_ent, fat_sect, resp
' Find a free cluster, starting from cluster #
'   LIMITATIONS:
'   * doesn't return to the beginning of the FAT to look before the file's first cluster
    ser.strln(string("FindFreeClust():"))
    avail := 0

    { read FAT }
    fat_ent := st_from
    fat_sect := clustnum2fatsect(st_from)
    ser.printf1(@"fat_ent = %d\n\r", fat_ent)
    if (readfat(fat_sect) <> 512)
        ser.strln(string("read error"))
        return ERDIO

    { starting with the cluster # called for, look for an unused one }
    sect_offs := clustnum2offs(st_from)
    repeat while (sect_offs < 508)
        bytemove(@fat_ent, (@_sect_buff + sect_offs), 4)
        if (fat_ent == 0)                       ' found a free one
            ser.printf1(string("found free clust: %x\n\r"), sectoffs2absclust(sect_offs, fat_sect))
            return sectoffs2absclust(sect_offs, fat_sect)
        sect_offs += 4                          ' none yet; next FAT entry

    { if this point is reached, no free clusters were found }
    return ENOSPC

PUB FindFreeDirent{}: dirent_nr | endofdir
' Find free directory entry
'   Returns: entry number
    ser.strln(@"FindFreeDirent():")
    repeat
        dirent_nr := 0
        repeat 16                               ' up to 16 entries per sector
            fclose2{}
            ser.printf1(@"checking dirent #%d...\n\r", dirent_nr)
            fopenent(dirent_nr, O_RDONLY)    ' get current dirent's info
            { important: skip entries that are subdirs, deleted files, or the volume name,
                but count them as dirents }
            if (fisdir{} or fdeleted{} or fisvolnm{})
                dirent_nr++
                next
            if (direntneverused{})              ' last directory entry
                endofdir := true
                quit
            dirent_nr++
    until endofdir
    fclose2{}

PUB FindLastClust{}: cl_nr | fat_ent, resp, fat_sect
' Find last cluster # of file
'   LIMITATIONS:
'       * stays on first sector of FAT
    ser.strln(string("FindLastClust():"))
    ifnot (_file_nr)
        ser.strln(string("error: no file open"))
        return ENOTOPEN

    cl_nr := 0
    fat_ent := ffirstclust{}

    { read the FAT }
    fat_sect := clustnum2fatsect(fat_ent)
    if (readfat(fat_sect) <> 512)
        ser.strln(string("read error"))
        return ERDIO

    { follow chain }
    repeat
        cl_nr := fat_ent
        fat_ent := clustrd(fat_ent)
    while (fat_ent <> CLUST_EOC)
    ser.printf1(string("last clust is %x\n\r"), cl_nr)
    _last_clust := cl_nr
    return cl_nr

PUB FOpen(fn_str, mode): status
' Open file for subsequent operations
'   Valid values:
'       fn_str: pointer to string containing filename (must be space padded)
'       mode: O_RDONLY (1), or O_WRITE (2), O_RDWR (3)
'   Returns:
'       file number (dirent #) if successful,
'       or error
    ser.strln(@"FOpen():")
    if (fnumber{})                              ' file is already open
        ser.strln(@"error: already open")   'xxx bit of duplication with FOpenEnt()
        return EOPEN
    status := find(fn_str)                      ' look for file by name
'    if (_fmode & O_CREAT)
'        status := fcreate(fn_str, FATTR_ARC)
'    else
    if (status == ENOTFOUND)                ' file not found
        ser.strln(@"error: not found")
        return ENOTFOUND
    ser.printf1(@"found file, dirent # %d\n\r", status)
    return fopenent(status, mode)

PUB FOpenEnt(file_nr, mode): status
' Open file by dirent # for subsequent operations
'   Valid values:
'       file_nr: directory entry number
'       mode: O_RDONLY (1), O_WRITE (2), O_RDWR (3)
'   Returns:
'       file number (dirent #) if successful,
'       or error
    ser.strln(string("FOpenEnt():"))
    if (fnumber{})
        ser.strln(string("already open"))
        return EOPEN
    sd.rdblock(@_sect_buff, (rootdirsect{} + dirent2sect(file_nr)))
    readdirent(file_nr & $0f)               ' cache dirent metadata

    { set up the initial state:
        * set the seek pointer to the file's beginning
        * cache the file's open mode
        * cache the file's last cluster number; it'll be used later if more need to be
            allocated }
    _fseek_pos := 0
    _fseek_sect := ffirstsect{}
    _fmode := mode
    findlastclust{}

    return fnumber{}

PUB FRead(ptr_dest, nr_bytes): nr_read | nr_left, movbytes, resp
' Read a block of data from current seek position of opened file into ptr_dest
'   Valid values:
'       ptr_dest: pointer to buffer to copy data read
'       nr_bytes: 1..512, or the size of the file, whichever is smaller
'   Returns:
'       number of bytes actually read,
'       or error
    ser.strln(@"FRead():")
    ifnot (fnumber{})                          ' no file open
        return ENOTOPEN

    nr_read := nr_left := 0

    { make sure current seek isn't already at the EOF }
    if (_fseek_pos < fsize{})
        { clamp nr_bytes to physical limits:
            sector size, file size, and proximity to end of file }
        ser.printf1(@"nr_bytes: %d\n\r", nr_bytes)
        nr_bytes := nr_bytes <# sectsz{} <# fsize{} <# (fsize{}-_fseek_pos) ' XXX seems like this should be -1
        ser.printf1(@"sectsz: %d\n\r", sectsz{})
        ser.printf1(@"fsize: %d\n\r", fsize{})
        ser.printf1(@"(fsize-_fseek_pos): %d\n\r", fsize{}-_fseek_pos)
        { read a block from the SD card into the internal sector buffer,
            and copy as many bytes as possible from it into the user's buffer }
        resp := sd.rdblock(@_sect_buff, _fseek_sect)
        if (resp < 1)
            return ERDIO

        movbytes := sectsz{}-_sect_offs
        bytemove(ptr_dest, (@_sect_buff+_sect_offs), movbytes <# nr_bytes)
        nr_read := (nr_read + movbytes) <# nr_bytes
        nr_left := (nr_bytes - nr_read)

        if (nr_left > 0)
            { read the next block from the SD card, and copy the remainder
                of the requested length into the user's buffer }
            sd.rdblock(@_sect_buff, _fseek_sect)
            bytemove(ptr_dest+nr_read, @_sect_buff, nr_left)
            nr_read += nr_left
        fseek(_fseek_pos + nr_read)             ' update seek pointer
        return nr_read
    else
        return EEOF                             ' reached end of file

PUB FRename(fn_old, fn_new): status | dirent
' Rename file
'   fn_old: existing filename
'   fn_new: new filename
'   Returns:
'       dirent # of file on success
'       negative numbers on error
    { verify existence of file }
    dirent := find(fn_old)
    if (dirent < 0)
        ser.strln(@"file not found")
        return ENOTFOUND

    { verify new filename is valid }
    if (strcomp(fn_old, fn_new))
        return EEXIST

    fopenent(dirent, O_RDWR)
    fsetfname(fn_new)
    direntupdate(dirent)
    fclose{}

PUB FSeek(pos): status | seek_clust, clust_offs, rel_sect_nr, clust_nr, fat_sect, sect_offs
' Seek to position in currently open file
'   Valid values:
'       pos: 0 to file size-1
'   Returns:
'       position seeked to,
'       or error
    ser.strln(@"FSeek():")
    ifnot (fnumber{})
        ser.strln(@"error: no file open")
        return ENOTOPEN                         ' no file open
    if (pos < 0)                                ' catch bad seek positions
        ser.strln(@"error: illegal seek")
        return EBADSEEK
    { allow a seek position greater than the file's current size only if it was opened
        with _both_ the O_WRITE and O_APPEND bits }
    if (pos => fsize{})
        ser.strln(@"attempt to access beyond end of file:")
        if ((_fmode & O_WRITE) and (_fmode & O_APPEND))
            ser.strln(@"    mode IS write w/append(ok)")
            if (pos < (ftotalclust{} * clustsz{}))
                ser.strln(@"    seek pos IS within allocated clusters (ok)")
                fsetsize(pos+1)                 ' grow file (*limited to clusters allocated)
            else
                ser.strln(@"    outside of allocated clusters (error)")
                return EBADSEEK
        else
            ser.strln(@"    mode is NOT write and/or append (error)")
            return EBADSEEK                     ' error: beyond end of file

    longfill(@seek_clust, 0, 6)                 ' clear local vars

    { initialize cluster number with the file's first cluster number }
    clust_nr := ffirstclust{}

    { determine which cluster (in "n'th" terms) in the chain the seek pos. is }
    seek_clust := (pos / clustsz{})

    { use remainder to get byte offset within cluster (0..cluster size-1) }
    clust_offs := (pos // clustsz{})

    { use high bits of offset within cluster to get sector offset (0..sectors per cluster-1)
        within the cluster }
    rel_sect_nr := (clust_offs >> 9)

    { follow the cluster chain to determine which actual cluster it is }
    fat_sect := clustnum2fatsect(clust_nr)
    readfat(fat_sect)
    repeat seek_clust
        { read next entry in chain }
        clust_nr := clustrd(clust_nr)
        sect_offs += 4

    { set the absolute sector number and the seek position for subsequent R/W:
        translate the cluster number to a sector number on the SD card, and add the
        sector offset from above
        also, set offset within sector to find the start of the data (0..bytes per sector-1) }
    _fseek_sect := (clust2sect(clust_nr) + rel_sect_nr)
    _fseek_pos := pos
    _sect_offs := (pos // sectsz{})
    ser.strln(@"FSeek() [ret]")
    return pos

PUB FTell{}: pos
' Get current seek position in currently opened file
    ifnot (fnumber{})
        return ENOTOPEN                         ' no file open
    return _fseek_pos

PUB FWrite(ptr_buff, len): status | sect_wrsz, nr_left, resp
' Write buffer to card
'   ptr_buff: address of buffer to write to SD
'   len: number of bytes to write from buffer
'       NOTE: a full sector is always written
    ser.strln(@"FWrite():")
    ifnot (fnumber{})
        return ENOTOPEN                         ' no file open
    ifnot (_fmode & O_WRITE)
        return EWRONGMODE                       ' must be open for writing

    nr_left := len                              ' init to total write length
    repeat while (nr_left > 0)
        ser.printf1(@"nr_left = %d\n\r", nr_left)
        { how much of the total to write to this sector }
        sect_wrsz := (sd#SECT_SZ - _sect_offs) <# nr_left
        ser.printf1(@"sect_wrsz = %d\n\r", sect_wrsz)
        bytefill(@_sect_buff, 0, sectsz{})

        if (_fmode & O_RDWR)                    ' read-modify-write mode
        { read the sector's current contents, so it can be merged with this write }
            resp := sd.rdblock(@_sect_buff, _fseek_sect)
            if (resp < 1)
                return ERDIO

        { copy the next chunk of data to the sector buffer }
        bytemove(@_sect_buff+_sect_offs, ptr_buff+(len-nr_left), sect_wrsz)

        status := sd.wrblock(@_sect_buff, _fseek_sect)
        if (status == sd#SECT_SZ)
            { update position to advance by how much was just written }

            fseek(_fseek_pos + sect_wrsz)
            nr_left -= sect_wrsz

    ser.strln(@"FWrite() [ret]")

PUB ReadFAT(fat_sect): resp
' Read the FAT into the sector buffer
'   fat_sect: sector of the FAT to read
    ser.strln(@"ReadFAT():")
    bytefill(@_sect_buff, 0, 512)
    resp := sd.rdblock(@_sect_buff, (fat1start{} + fat_sect))
    ser.hexdump(@_sect_buff, 0, 4, 512, 16)
    ser.strln(@"ReadFAT(): [ret]")

PUB WriteFAT(fat_sect): resp
' Write the FAT from the sector buffer
'   fat_sect: sector of the FAT to write
    ser.strln(@"WriteFAT():")
    ser.hexdump(@_sect_buff, 0, 4, 512, 16)
    resp := sd.wrblock(@_sect_buff, (fat1start{} + fat_sect))
    ser.strln(@"WriteFAT(): [ret]")

#include "filesystem.block.fat.spin"

' below: temporary, for devel purposes

pub rdblock(ptr, sect)

    return sd.rdblock(ptr, sect)

pub wrblock(ptr, sect): resp

    return sd.wrblock(ptr, sect)

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


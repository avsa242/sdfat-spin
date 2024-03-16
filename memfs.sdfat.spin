{
---------------------------------------------------------------------------------------------------
    Filename:       memfs.sdfat.spin
    Description:    FAT32-formatted SDHC/XC driver
    Author:         Jesse Burt
    Started:        Jun 11, 2022
    Updated:        Mar 11, 2024
    Copyright (c) 2024 - See end of file for terms of use.
---------------------------------------------------------------------------------------------------
}

{ debug output overrides }
'#define DBG_RX 14
'#define DBG_TX 15
'#define DBG_BAUD 230_400
'#define INDENT_SPACES 4
'#include "debug.spinh"
CON

    { default I/O settings - these can be overridden by the parent object }
    CS          = 0
    SCK         = 1
    MOSI        = 2
    MISO        = 3


    { File I/O Error codes }
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
    EFSCORRUPT  = -12                           ' filesystem inconsistency or corruption

    ENOTIMPLM   = -256                          ' not implemented
    EWRIO       = -512 {$ff_ff_e0_00}           ' I/O error (writing)
    ERDIO       = -513 {$ff_ff_fd_ff}           ' I/O error (reading)

    { File open modes }
    O_RDONLY    = (1 << 0)                      ' R
    O_WRITE     = (1 << 1)                      ' W (writes _overwrite_)
    O_RDWR      = O_RDONLY | O_WRITE            ' R/W
    O_CREAT     = (1 << 2)                      ' create file
    O_APPEND    = (1 << 3)                      ' W (allow file to grow)
    O_TRUNC     = (1 << 4)                      ' truncate to 0 bytes

    { metadata buffer types }
    META_DIR    = 1
    META_FAT    = 2

VAR

    long _meta_sect                             ' sector # of last metadata read
    long _dir_sect

    word _sect_offs
    word _last_free_dirent

    byte _sect_buff[sd.SECT_SZ]                 ' sector (data) buffer
    byte _meta_buff[sd.SECT_SZ]                 ' metadata buffer
    byte _meta_lastread                         ' type of last metadata read
    byte _curr_file

DAT

    _sys_date word ( ((2023-1980) << 9) | (7 << 5) | 3 )
    _sys_time word ( (18 << 11) | (25 << 5) | 00 )

OBJ

    sd:     "memory.sd-spi"
    str:    "string"
    time:   "time"
'    ser:    "com.serial.terminal.ansi"

pub start(): status
' Start the driver using default I/O settings
    return startx(CS, SCK, MOSI, MISO)

PUB startx(SD_CS, SD_SCK, SD_MOSI, SD_MISO): status
' Start the driver using custom I/O settings
'   SD_CS:      Chip Select
'   SD_SCK:     Serial Clock
'   SD_MOSI:    Master-Out Slave-In
'   SD_MISO:    Master-In Slave-Out
'   Returns:    cog ID+1 of SPI engine, or negative numbers on error
'    ser.startrxtx(DBG_RX, DBG_TX, 0, DBG_BAUD)
'    time.msleep(20)
'    ser.clear()
'    dreset()
'    dstrln_info(@"SD/FAT debug started")

    status := sd.init(SD_CS, SD_SCK, SD_MOSI, SD_MISO)
    if ( lookdown(status: 1..8) )
        status := mount()
    return status

PUB mount(): status
' Mount SD card
'   Read SD card boot sector and sync filesystem info
'   Returns:
'       0 on success
'       negative number on error
    status := 0

    { point FATfs object to sector buffer }
    init(@_meta_buff)

    { read the MBR }
    status := sd.rd_block(@_meta_buff, MBR)
    'dlprintf1(0, 0, INFO, @"sd.rd_block() [ret: %d]\n\r", status)
    if (status < 0)
        return status

    { get 1st partition's 1st sector number from it }
    status := read_part()
    'dlprintf1(0, 0, INFO, @"read_part() [ret: %d]\n\r", status)
    if (status < 0)
        return status

    { now read that sector }
    status := sd.rd_block(@_meta_buff, part_start())
    'dlprintf1(0, 0, INFO, @"sd.rd_block() [ret: %d]\n\r", status)
    if (status < 0)
        return status

    { sync the FATfs metadata from it }
    status := read_bpb()
    'dlprintf1(0, 0, INFO, @"read_bpb() [ret: %d]\n\r", status)
    if (status < 0)
        return status

PUB alloc_clust(cl_nr): status | tmp, fat_sect
' Allocate a new cluster
'   Returns: cluster number allocated
    'dlstrln(1, INFO, @"alloc_clust():")
    ifnot ( (_fmode & O_WRITE) or (_fmode & O_APPEND) or (_fmode & O_CREAT) )
        { must be opened for writing, or newly created }
        'dlstrln(0, 0, ERR, @"bad file mode")
        'dlprintf1(-1, 0, INFO, @"alloc_clust() [ret: %d]\n\r", EWRONGMODE)
        return EWRONGMODE

    { read FAT sector }
    fat_sect := clust_num_to_fat_sect(cl_nr)
    if ( (status := read_fat(fat_sect)) <> 512 )
        'dlprintf1(0, 0, ERR, @"read error %d\n\r", status)
        'dlprintf1(-1, 0, INFO, @"alloc_clust() [ret: %d]\n\r", ERDIO)
        return ERDIO

    { check the requested cluster number - is it free? }
    if ( read_fat_entry(cl_nr) <> 0 )
        'dlstrln(0, 0, ERR, @"cluster in use")
        'dlprintf1(-1, 0, INFO, @"alloc_clust() [ret: %d]\n\r", ECL_INUSE)
        return ECL_INUSE

    { write the EOC marker into the newly allocated entry }
    write_fat_entry(cl_nr, CLUST_EOC)

    { write the updated FAT sector to SD }
    'dlstrln(0, NORM, @"updated FAT: ")
    'dhexdump(@_meta_buff, 0, 4, 512, 16)
    if (status := write_fat(fat_sect) <> 512)
        'dlprintf1(0, 0, ERR, @"write error %d\n\r", status)
        'dlprintf1(-1, 0, INFO, @"alloc_clust() [ret: %d]\n\r", EWRIO)
        return EWRIO

    'dprintf1(-1, 0, INFO, @"alloc_clust() [ret: %d]\n\r", cl_nr)
    return cl_nr

PUB alloc_clust_block(cl_st_nr, count): status | cl_nr, tmp, last_cl, fat_sect
' Allocate a block of contiguous clusters
'   cl_st_nr: starting cluster number
'   count: number of clusters to allocate
'   Returns:
'       number of clusters allocated on success
'       negative number on error
    'dlstrln(0, 1, INFO, @"alloc_clust_block()")
    { validate the starting cluster number and count }
    if ((cl_st_nr < 3) or (count < 1))
        'dlstrln(0, 0, ERR, @"invalid cluster number")
        'dlprintf1(-1, 0, INFO, @"alloc_clust_block() [ret: %d]\n\r", EINVAL)
        return EINVAL

    { read FAT sector }
    fat_sect := clust_num_to_fat_sect(cl_st_nr)
    if (read_fat(fat_sect) <> 512)
        'dlprintf1(0, 0, ERR, @"read error %d\n\r", status)
        'dlprintf1(-1, 0, INFO, @"alloc_clust_block() [ret: %d]\n\r", ERDIO)
        return ERDIO

    last_cl := (cl_st_nr + (count-1))
    { before trying to allocate clusters, check that the requested number of them are free }
    repeat cl_nr from cl_st_nr to last_cl
        'dlprintf1(0, 0, NORM, @"cluster %d? ", cl_nr)
        if ( read_fat_entry(cl_nr) <> 0 )
            'dlstrln(0, 0, ERR, @"in use - fail")
            'dlprintf1(-1, 0, INFO, @"alloc_clust_block() [ret: %d]\n\r", ENOSPC)
            return ENOSPC                        ' cluster is in use
        'dlstrln(0, 0, NORM, @"free")

    { link clusters, from the first to one before the last one }
    repeat cl_nr from cl_st_nr to (last_cl-1)
        write_fat_entry(cl_nr, (cl_nr + 1))

    { mark last cluster as the EOC }
    write_fat_entry(last_cl, CLUST_EOC)

    { write updated FAT sector }
    if (status := write_fat(fat_sect) <> 512)
        'dlprintf1(0, 0, ERR, @"write error %d\n\r", status)
        'dlprintf1(-1, 0, INFO, @"alloc_clust_block() [ret: %d]\n\r", EWRIO)
        return EWRIO
    'dlprintf1(-1, 0, INFO, @"alloc_clust_block() [ret: %d]\n\r", EWRIO)
    return count

PUB dirent_update(dirent_nr): status
' Update a directory entry on disk
'   dirent_nr: directory entry number
    'dlstrln(0, 1, INFO, @"dirent_update()")
    'dlprintf1(0, 0, NORM, @"called with: %d\n\r", dirent_nr)

    { read root dir sect }
    'dlprintf2(0, 0, NORM, @"read rootdir sector #%d (rel: %d)\n\r", dirent_to_abs_sect(dirent_nr), ...
'                                                           dirent_to_abs_sect(dirent_nr) ...
'                                                            - root_dir_sect() )
    status := sd.rd_block(@_meta_buff, dirent_to_abs_sect(dirent_nr))
    _meta_lastread := META_DIR

    if (status < 0)
        'dlprintf1(0, 0, ERR, @"read error %d\n\r", status)
        'dlprintf1(-1, 0, INFO, @"dirent_update() [ret: %d]\n\r", ERDIO)
        return ERDIO

    { copy currently cached dirent to sector buffer }
    bytemove(@_meta_buff+dirent_start(dirent_nr // 16), @_dirent, DIRENT_LEN)

    { write root dir sect back to disk }
    'dlstrln(0, 0, NORM, @"wr_block")
    status := sd.wr_block(@_meta_buff, dirent_to_abs_sect(dirent_nr))
    if (status < 0)
        'dlprintf1(0, 0, ERR, @"write error %d\n\r", status)
        'dlprintf1(-1, 0, INFO, @"dirent_update() [ret: %d]\n\r", EWRIO)
        return EWRIO
    'dlprintf1(-1, 0, INFO, @"dirent_update() [ret: %d]\n\r", status)

PUB fallocate(): status | flc, cl_free, fat_sect
' Allocate a new cluster for the currently opened file
    'dlstrln(0, 1, INFO, @"fallocate()")
    ifnot (_file_nr)
        'dlstrln(0, 0, ERR, @"error: no file open")
        'dlprintf1(-1, 0, INFO, @"fallocate() [ret: %d]\n\r", ENOTOPEN)
        return ENOTOPEN
    { find last cluster # of file }
    flc := _fclust_last
    'dlprintf1(0, 0, NORM, @"last cluster: %x\n\r", flc)

    { find a free cluster }
    cl_free := find_free_clust()
    if (cl_free < 0)
        'dlprintf1(0, 0, ERR, @"error %d\n\r", status)
        'dlprintf1(-1, 0, INFO, @"fallocate() [ret: %d]\n\r", ENOTOPEN)
        return cl_free
    'dlprintf1(0, 0, NORM, @"free cluster found: %x\n\r", cl_free)

    { rewrite the file's last cluster entry to point to the newly found free cluster }
    fat_sect := clust_num_to_fat_sect(flc)
    if (read_fat(fat_sect) <> 512)
        'dlprintf1(0, 0, ERR, @"read error %d\n\r", status)
        'dlprintf1(-1, 0, INFO, @"fallocate() [ret: %d]\n\r", ENOTOPEN)
        return ERDIO
    write_fat_entry(flc, cl_free)
    if (status := write_fat(fat_sect) <> 512)
        'dlprintf1(0, 0, ERR, @"write error %d\n\r", status)
        'dlprintf1(-1, 0, INFO, @"fallocate() [ret: %d]\n\r", ENOTOPEN)
        return EWRIO

    { allocate/write EOC in the newly found free cluster and increment the total cluster count }
    status := alloc_clust(cl_free)
    _fclust_last := status
    _fclust_tot++
    'dlprintf1(-1, 0, INFO, @"fallocate() [ret: %d]\n\r", status)

PUB fcount_clust(): t_clust | fat_entry, fat_sector, nxt_entry
' Count number of clusters used by currently open file
    'dlstrln(0, 1, INFO, @"fcount_clust()")
    ifnot ( fnumber() )
        'dlstrln(0, 0, ERR, @"error: file not open")
        'dlprintf1(-1, 0, INFO, @"fcount_clust() [ret: %d]\n\r", ENOTOPEN)
        return ENOTOPEN

    fat_sector := clust_num_to_fat_sect(ffirst_clust())
    fat_entry := fat_entry_abs_to_rel(ffirst_clust())
    t_clust := 0
    repeat                                      ' for each FAT sector (relative to 1st)...
        'dlprintf1(0, 0, NORM, @"FAT sector %d\n\r", fat_sector)
        read_fat(fat_sector)
        repeat                                  '   for each FAT entry...
            'dlprintf1(0, 0, NORM, @"fat_entry = %02x\n\r", fat_entry)
            nxt_entry := read_fat_entry(fat_entry)
            _fclust_last := fat_entry           ' rolling update of the file's last cluster #
            fat_entry := nxt_entry
            _fclust_tot := ++t_clust            ' track total # of clusters used
            'dlprintf1(0, 0, NORM, @"last clust = %d\n\r", _fclust_last)
            'dlprintf1(0, 0, NORM, @"total clusts = %d\n\r", _fclust_tot)
            'dlprintf1(0, 0, NORM, @"nxt_entry = %02x\n\r", nxt_entry)
            if ( fat_entry_is_eoc(nxt_entry) )
                'dlprintf2(0, 0, WARN, @"EOC reached; total %d/%d clusters\n\r", _fclust_tot, t_clust)
                'dlprintf1(-1, 0, INFO, @"fcount_clust() [ret: %d]\n\r", t_clust)
                return t_clust
        fat_sector++
    while ( fat_sector < (fat1_start() + sects_per_fat()) )
    'dlprintf1(-1, 0, INFO, @"fcount_clust() [ret: %d]\n\r", t_clust)
 
PUB fcreate(fn_str, attrs): status | dirent_nr, ffc
' Create file
'   fn_str: pointer to string containing filename
'   attrs: initial file attributes
    'dlstrln(0, 1, INFO, @"fcreate()")
    { first, verify a file with the same name doesn't already exist }
    if ( find(fn_str) <> ENOTFOUND )
        'dlstrln(0, 0, ERR, @"error: file already exists")
        'dlprintf1(-1, 0, INFO, @"fcreate() [ret: %d]\n\r", EEXIST)
        return EEXIST

    { find a free directory entry, and open it read/write }
    if ( _last_free_dirent )
        'dlprintf1(0, 0, NORM, @"using dirent #%d\n\r", _last_free_dirent)
        dirent_nr := _last_free_dirent

    read_dirent(dirent_nr)                      ' mainly just to zero out anything that's there
    'dlprintf1(0, 0, NORM, @"found dirent # %d\n\r", dirent_nr)

    { find a free cluster, starting at the beginning of the FAT }
    ffc := find_free_clust()
    'dlprintf2(0, 0, NORM, @"first free cluster: %x (%d)\n\r", ffc, ffc)
    if ( ffc < 3 )
        'dlstrln(0, 0, ERR, @"no free clusters")
        'dlprintf1(-1, 0, INFO, @"fcreate() [ret: %d]\n\r", ENOSPC)
        return ENOSPC
    'dlprintf1(0, 0, NORM, @"fmode = %x\n\r", _fmode)

    _fmode := O_CREAT
    { set up the file's initial metadata }
    'dlstrln(0, 0, NORM, @"setting up dirent")
    fset_fname(fn_str)
    fset_ext(fn_str+9)   'XXX expects string at fn_str to be in '8.3' format, _with_ the period
    fset_attrs(attrs)
    fset_size(0)
    fset_date_created(_sys_date)
    fset_time_created(_sys_time)
    fset_first_clust(ffc)
    dirent_update(dirent_nr)
    'dhexdump(@_dirent, 0, 4, DIRENT_LEN, 16)
{
    dlstr(0, 0, NORM, @"file mode is: ")
    if (_fmode & O_RDONLY)
        dstr(@" O_RDONLY")'xxx
    if (_fmode & O_WRITE)
        dstr(@" O_WRITE")'xxx
    if (_fmode & O_CREAT)
        dstr(@" O_CREAT")
    if (_fmode & O_APPEND)
        dstr(@" O_APPEND")
    dnewline()
}
    { allocate a cluster }
    alloc_clust(ffc)

    'dlprintf1(-1, 0, INFO, @"fcreate(): [ret %d]", dirent_nr)
    return dirent_nr

PUB fdelete(fn_str): status | dirent, clust_nr, fat_sect, nxt_clust, tmp
' Delete a file
'   fn_str: pointer to string containing filename
'   Returns:
'       existing directory entry number on success
'       negative numbers on failure
    'dlstrln(0, 1, INFO, @"fdelete()")
    { verify file exists }
    'dlprintf1(0, 0, NORM, @"about to look for %s\n\r", fn_str)
    dirent := find(fn_str)
    if (dirent < 0)
        'dlstrln(0, 0, ERR, @"not found")
        'dlprintf1(-1, 0, INFO, @"fdelete() [ret: %d]\n\r", ENOTFOUND)
        return ENOTFOUND

    { rename file with first byte set to FATTR_DEL ($E5) }
    fopen_ent(dirent, O_RDWR)
    fset_deleted()
    dirent_update(dirent)

    { clear the file's entire cluster chain to 0 }
    clust_nr := ffirst_clust()
    fat_sect := clust_num_to_fat_sect(clust_nr)
    status := read_fat(fat_sect)
    if (status <> 512)
        'dlprintf1(0, 0, ERR, @"read error %d\n\r", status)
        'dlprintf1(-1, 0, INFO, @"fdelete() [ret: %d]\n\r", ERDIO)
        return ERDIO

    repeat ftotal_clust()
        { read next entry in chain before clearing the current one - need to know where
            to go to next beforehand }
        nxt_clust := read_fat_entry(clust_nr)
        write_fat_entry(clust_nr, 0)
        clust_nr := nxt_clust

    { write modified FAT back to disk }
    if (status := write_fat(fat_sect) <> 512)
        'dlprintf1(0, 0, ERR, @"write error %d\n\r", status)
        'dlprintf1(-1, 0, INFO, @"fdelete() [ret: %d]\n\r", EWRIO)
        return EWRIO
    'dlprintf1(-1, 0, INFO, @"fdelete() [ret: %d]\n\r", dirent)
    return dirent

PUB file_size(): sz
' Get size of opened file
    return fsize()

PUB find(ptr_str): dirent | rds, endofdir, name_tmp[3], ext_tmp, fn_tmp[4], d
' Find file, by name
'   Valid values:
'       ptr_str: pointer to space-padded string containing filename (8.3)
'   Returns:
'       directory entry of file (0..n)
'       or ENOTFOUND (-2) if not found
    'dlstrln(0, 1, NORM, @"find():")
    dirent := 0
    rds := 0
    endofdir := false

    { get filename and extension, and convert to uppercase }
    'dlprintf1(0, 0, INFO, @"Looking for %s\n\r", ptr_str)
    opendir(0)
    repeat
        longfill(@fn_tmp, 0, 4)
        d := next_file(@fn_tmp)
        if ( d < 0 )
            'dlstrln(0, 0, NORM, @"not found")
            quit
        'dlprintf1(0, 0, NORM, @"checking dirent %d\n\r", d)
        'dlprintf2(0, 0, NORM, @"dirent's filename is %s.%s\n\r", fname(), fname_ext())
        if ( strcomp(ptr_str, dirent_filename(@fn_tmp)) )
            'dlstrln(0, 0, WARN, @"match found")
            'dlprintf1(-1, 0, INFO, @"find() [ret: %d]\n\r", d)
            return d
    'dlprintf1(-1, 0, INFO, @"find() [ret: %d]\n\r", ENOTFOUND)
    return ENOTFOUND

CON FREE_CLUST = 0
PUB find_free_clust(): f | fat_sector, fat_entry, fat_sect_entry
' Find a free cluster
    'dlstrln(0, 1, INFO, @"find_free_clust():")
    fat_sector := fat1_start()                  ' start at first sector of first FAT
    fat_sect_entry := 3                         ' skip reserved, root dir, and vol label entries

    repeat                                      ' for each FAT sector (relative to 1st)...
        'dlprintf1(0, 0, NORM, @"reading FAT sector %d\n\r", fat_sector)
        read_fat(fat_sector-fat1_start())
        repeat                                  '   for each FAT entry...
            { get absolute FAT entry }
            { fat sector from the fat_entry's point of view is relative to the start of the FAT,
                NOT an absolute sector number }
            'dlprintf2(0, 0, NORM, @"fat_sector = %d\tfat1_start() = %d\n\r", fat_sector, fat1_start())
            fat_entry := ( ((fat_sector-fat1_start()) * 128) + fat_sect_entry )
            'dlprintf1(0, 0, NORM, @"fat_entry = %02.2x\n\r", fat_entry)
            if ( read_fat_entry(fat_sect_entry) == FREE_CLUST )
                'dlprintf1(0, 0, WARN, @"found free entry %02.2x\n\r", fat_entry)
                'dlprintf1(-1, 0, INFO, @"find_free_clust() [ret: %d]\n\r", fat_entry)
                return fat_entry                ' return the absolute FAT entry #
            fat_sect_entry++                    ' otherwise, continue on
        while ( fat_sect_entry < 128 )
        fat_sector++
        'dlprintf1(0, 0, NORM, @"next sector (%08x)\n\r", fat_sector)
    while ( fat_sector < (fat1_start() + sects_per_fat()) )

    'dlprintf1(-1, 0, INFO, @"find_free_clust() [ret: %d]\n\r", ENOSPC)
    return ENOSPC                               ' no free clusters

PUB find_free_dirent(): dirent_nr | endofdir, d
' Find free directory entry
'   Returns: entry number
    'dlstrln(0, 1, NORM, @"find_free_dirent()")
    opendir(0)
    d := 0
    repeat
        dirent_nr := d
        d := next_file(0)
    while ( d > 0 )
    'dhexdump(@_meta_buff, 0, 4, 512, 16)
    'dlprintf1(-1, 0, INFO, @"find_free_dirent() [ret: %d]\n\r", dirent_nr+1)
    return dirent_nr+1                          ' the last used dirent+1 == 1st unused entry

PUB find_last_clust(): cl_nr | fat_ent, resp, fat_sect
' Find last cluster # of file
'   LIMITATIONS:
'       * stays on first sector of FAT
    'dlstrln(0, 1, NORM, @"find_last_clust()")
    if (fnumber() < 0)
        'dlstrln(0, 0, ERR, @"error: no file open")
        'dlprintf1(-1, 0, INFO, @"find_last_clust() [ret: %d]\n\r", ENOTOPEN)
        return ENOTOPEN
    'dlprintf1(0, 0, NORM, @"file number is %d\n\r", fnumber())

    cl_nr := 0
    fat_ent := ffirst_clust()
    { try to catch some invalid cases - these are signs there's something seriously
        wrong with the filesystem }
    if (fat_ent & $f000_000)                    ' top 4 bits of clust nr set? they shouldn't be...
        'dlprintf1(0, 0, ERR, @"error: invalid FAT entry %x\n\r", fat_ent)
        'dlprintf1(-1, 0, INFO, @"find_last_clust() [ret: %d]\n\r", EFSCORRUPT)
        abort EFSCORRUPT
    'dlprintf1(0, 0, NORM, @"first clust: %x\n\r", fat_ent)
    { read the FAT }
    fat_sect := clust_num_to_fat_sect(fat_ent)
    if ( read_fat(fat_sect) <> sd.READ_OK )
        'dlprintf1(0, 0, ERR, @"read error %d\n\r", cl_nr)
        'dlprintf1(-1, 0, INFO, @"find_last_clust() [ret: %d]\n\r", ERDIO)
        return ERDIO

    { follow chain }
    repeat
        cl_nr := fat_ent
        fat_ent := read_fat_entry(fat_ent)
        if ( fat_ent == 0 )
            'dlstrln(0, 0, ERR, @"error: invalid FAT entry 0")
            quit    ' abort EFSCORRUPT?
        'dlprintf1(0, 0, NORM, @"cl_nr: %x\n\r", cl_nr)
        'dlprintf1(0, 0, NORM, @"fat_ent: %x\n\r", fat_ent)
    while not (fat_entry_is_eoc(fat_ent))

    _fclust_last := cl_nr
    'dlprintf1(0, 0, WARN, @"last clust is %x\n\r", cl_nr)
    'dlprintf1(-1, 0, INFO, @"find_last_clust() [ret: %d]\n\r", cl_nr)
    return cl_nr

PUB fopen(fn_str, mode): status
' Open file for subsequent operations
'   Valid values:
'       fn_str: pointer to string containing filename (must be space padded)
'       mode: (bitwise OR together to combine modes)
'           O_RDONLY (1): read-only access
'           O_WRITE (2): overwrite access (won't grow file size)
'           O_RDWR (3): read/write access (= O_RDONLY | O_WRITE)
'           O_CREAT (4): create the file if it doesn't exist
'           O_APPEND (8): write access, always append new data to the end of the file
'               (fseek() calls are ignored)
'           O_TRUNC (16): truncate the file to 0 bytes when opening
'   Returns:
'       file number (dirent #) if successful,
'       or error
    'dlstrln(0, 1, INFO, @"fopen()")
    if ( fnumber() => 0 )                       ' file is already open
        'dlstrln(0, 0, ERR, @"error: already open") 'xxx bit of duplication with FOpenEnt()
        'dlprintf1(-1, 0, INFO, @"fopen() [ret: %d]\n\r", EOPEN)
        return EOPEN

    status := find(fn_str)                   ' look for file by name
    'dlprintf1(0, 0, NORM, @"found file, dirent # %d\n\r", status)

    if ( status == ENOTFOUND )               ' file not found
        if ( mode & O_CREAT )                   ' create it, if the option is given
            status := fcreate(fn_str, FATTR_ARC)
            mode &= !O_CREAT                    ' strip off the create bit for fopen_ent()
            if ( status < 0 )                   ' error creating dirent
                'dlstrln(0, 0, ERR, @"error creating dirent")
                'dlprintf1(-1, 0, INFO, @"fopen() [ret: %d]\n\r", status)
                return
        else
            'dlstrln(0, 0, ERR, @"error: not found (and O_CREAT wasn't specified)")
            'dlprintf1(-1, 0, INFO, @"fopen() [ret: %d]\n\r", status)
            return ENOTFOUND

    status := fopen_ent(status, mode)
    'dlprintf1(-1, 0, INFO, @"fopen(): [ret %d]\n\r", status)

PUB fopen_ent(file_nr, mode): status
' Open file by dirent # for subsequent operations
'   Valid values:
'       file_nr: directory entry number
'       mode: O_RDONLY (1), O_WRITE (2), O_RDWR (3)
'   Returns:
'       file number (dirent #) if successful,
'       or error
    'dlstrln(0, 1, INFO, @"fopen_ent():")
    if (fnumber() => 0)
        'dlprintf1(0, 0, WARN, @"file #%d already open\n\r", fnumber())
        'dlprintf1(-1, 0, INFO, @"fopen_ent() [ret: %d]\n\r", EOPEN)
        return EOPEN

    'dlprintf2(0, 0, NORM, @"reading rootdir sect %d+%d...", root_dir_sect(),  dirent_to_sect(file_nr))
    sd.rd_block(@_meta_buff, (root_dir_sect() + dirent_to_sect(file_nr)))
    _meta_lastread := META_DIR                  ' indicate metadata last read is of type directory
    'dlstrln(0, 0, NORM, @"read ok")

    { open the file }
    read_dirent(file_nr & $0f)                  ' cache dirent metadata
    if (dirent_never_used())
        ifnot (mode & O_CREAT)                  ' need create bit set to open an unused dirent
            fclose()
            'dlstrln(0, 0, ERR, @"error: dirent unused")
            'dlprintf1(-1, 0, INFO, @"fopen_ent() [ret: %d]\n\r", status)
            return ENOTFOUND
    _file_nr := file_nr 'xxx hacky
    'dhexdump(@_dirent, 0, 4, 32, 16)
    'dlprintf1(0, 0, NORM, @"opened file/dirent # %d\n\r", fnumber())

    { set up the initial state:
        * set the seek pointer to the file's beginning
        * cache the file's open mode
        * cache the file's last cluster number; it'll be used later if more need to be
            allocated }
    fcount_clust()

    if (mode & O_TRUNC)                         ' have to check for this first before any others
        ftrunc()                                ' (don't want to truncate to 0 after checking size)

    if (mode & O_APPEND)
        mode |= O_WRITE                         ' in case it isn't already
        fseek(fsize())                          ' init seek pointer to end of file
    else
        _fseek_pos := 0
        _fseek_sect := ffirst_sect()             ' initialize current sector with file's first
    _fmode := mode
    'dlprintf2(0, 0, NORM, @"_fclust_tot: %d  clust_sz: %d\n\r", _fclust_tot, clust_sz())
    'dlprintf1(-1, 0, INFO, @"fopen_ent() [ret: %d]\n\r", fnumber())
    return fnumber()

PUB rdblock_lsbf = fread
PUB fread(ptr_dest, nr_bytes): nr_read | nr_left, movbytes, resp
' Read a block of data from current seek position of opened file into ptr_dest
'   Valid values:
'       ptr_dest: pointer to buffer to copy data read
'       nr_bytes: 1..512, or the size of the file, whichever is smaller
'   Returns:
'       number of bytes actually read,
'       or error
'    dlstrln(0, 1, INFO, @"fread():")
    if (fnumber() < 0)                          ' no file open
'        dlstrln(0, 0, ERR, @"no file open")
'        dlprintf1(-1, 0, INFO, @"fread() [ret: %d]\n\r", ENOTOPEN)
        return ENOTOPEN

    nr_read := nr_left := 0

    { make sure current seek isn't already at the EOF }
    if (_fseek_pos < fsize())
        { clamp nr_bytes to physical limits:
            sector size, file size, and proximity to end of file }
'        dlprintf1(0, 0, NORM, @"nr_bytes: %d\n\r", nr_bytes) 'xxx terminal corruption
        nr_bytes := nr_bytes <# sect_sz() <# fsize() <# (fsize()-_fseek_pos)
'        dlprintf1(0, 0, NORM, @"sectsz: %d\n\r", sect_sz())
'        dlprintf1(0, 0, NORM, @"fsize: %d\n\r", fsize())
'        dlprintf1(0, 0, NORM, @"(fsize-_fseek_pos): %d\n\r", fsize()-_fseek_pos)

        { read a block from the SD card into the internal sector buffer }
        if ( _fseek_sect <> _fseek_prev_sect )
            resp := sd.rd_block(@_sect_buff, _fseek_sect)
            if (resp < 1)
'                dlstrln(0, 0, ERR, @"read error")
'                dlprintf1(-1, 0, INFO, @"fread() [ret: %d]\n\r", ERDIO)
                return ERDIO
'        else
'            dlstrln(0, 0, INFO, @"current seek sector == prev seek sector; not re-reading")

        { copy as many bytes as possible from it into the user's buffer }
        movbytes := sect_sz()-_sect_offs
        bytemove(ptr_dest, (@_sect_buff+_sect_offs), movbytes <# nr_bytes)
        nr_read := (nr_read + movbytes) <# nr_bytes
        nr_left := (nr_bytes - nr_read)

        { if there's still some data left, read the next block from the SD card, and copy
            the remainder of the requested length into the user's buffer }
        if (nr_left > 0)
            resp := sd.rd_block(@_sect_buff, _fseek_sect)
            if (resp < 1)
'                dlstrln(0, 0, ERR, @"read error")
'                dlprintf1(-1, 0, INFO, @"fread() [ret: %d]\n\r", ERDIO)
                return ERDIO
            bytemove(ptr_dest+nr_read, @_sect_buff, nr_left)
            nr_read += nr_left
        _fseek_prev_sect := _fseek_sect
        fseek(_fseek_pos + nr_read)             ' update seek pointer
'        dlprintf1(-1, 0, INFO, @"fread() [ret: %d]\n\r", nr_read)
        return nr_read
    else
'        dlstrln(0, 0, ERR, @"end of file")
'        dlprintf1(-1, 0, INFO, @"fread() [ret: %d]\n\r", EEOF)
        return EEOF                             ' reached end of file
'    dlprintf1(-1, 0, INFO, @"fread() [ret: %d]\n\r", nr_read)

pub rd_byte(): b

    b := 0
    fread(@b, 1)

pub rd_word(): w

    w := 0
    fread(@w, 2)

pub rd_long(): l

    l := 0
    fread(@l, 4)


PUB frename(fn_old, fn_new): status | dirent
' Rename file
'   fn_old: existing filename
'   fn_new: new filename
'   Returns:
'       dirent # of file on success
'       negative numbers on error
    'dlstrln(0, 1, INFO, @"frename()")
    { verify existence of file }
    dirent := find(fn_old)
    if (dirent < 0)
        'dlstrln(0, 0, ERR, @"file not found")
        'dlprintf1(-1, 0, INFO, @"frename() [ret: %d]\n\r", ENOTFOUND)
        return ENOTFOUND

    { verify new filename is valid }
    if (strcomp(fn_old, fn_new))
        'dlstrln(0, 0, ERR, @"file with that name already exists")
        'dlprintf1(-1, 0, INFO, @"frename() [ret: %d]\n\r", EEXIST)
        return EEXIST

    fopen_ent(dirent, O_RDWR)
    fset_fname(fn_new)
    dirent_update(dirent)
    fclose()
    'dlprintf1(-1, 0, INFO, @"frename() [ret: %d]\n\r", status)

PUB fseek(pos): status | seek_clust, clust_offs, rel_sect_nr, clust_nr, fat_sect, sect_offs
' Seek to position in currently open file
'   Valid values:
'       pos: 0 to file size-1
'   Returns:
'       position seeked to,
'       or error
    'dlstrln(0, 1, INFO, @"fseek()")
    longfill(@seek_clust, 0, 6)                 ' clear local vars
    if (fnumber() < 0)
        'dlstrln(0, 0, ERR, @"error: no file open")
        'dlprintf1(-1, 0, INFO, @"fseek() [ret: %d]\n\r", ENOTOPEN)
        return ENOTOPEN                          ' no file open
    if (pos < 0)                                ' catch bad seek positions
        'dlstrln(0, 0, ERR, @"error: illegal seek")
        'dlprintf1(-1, 0, INFO, @"fseek() [ret: %d]\n\r", EBADSEEK)
        return EBADSEEK
    if (pos > fsize())
        ifnot (_fmode & O_APPEND)
            'dlstrln(0, 0, ERR, @"error: illegal seek")
            'dlprintf1(-1, 0, INFO, @"fseek() [ret: %d]\n\r", EBADSEEK)
            return EBADSEEK

    { initialize cluster number with the file's first cluster number }
    clust_nr := ffirst_clust()

    { determine which cluster (in "n'th" terms) in the chain the seek pos. is }
    seek_clust := (pos / clust_sz())

    { use remainder to get byte offset within cluster (0..cluster size-1) }
    clust_offs := (pos // clust_sz())

    { use high bits of offset within cluster to get sector offset (0..sectors per cluster-1)
        within the cluster }
    rel_sect_nr := (clust_offs >> 9)

    { follow the cluster chain to determine which actual cluster it is }
    fat_sect := clust_num_to_fat_sect(clust_nr)
    read_fat(fat_sect)
    repeat seek_clust
        { read next entry in chain }
        clust_nr := read_fat_entry(clust_nr)
        sect_offs += 4

    { set the absolute sector number and the seek position for subsequent R/W:
        translate the cluster number to a sector number on the SD card, and add the
        sector offset from above
        also, set offset within sector to find the start of the data (0..bytes per sector-1) }
    _fseek_sect := (clust_to_sect(clust_nr) + rel_sect_nr)
    _fseek_pos := pos
    _sect_offs := (pos // sect_sz())            ' record which (n'th) sector of the file this is
    'dlprintf1(-1, 0, INFO, @"fseek() [ret: %d]\n\r", pos)
    return pos

PUB ftell(): pos
' Get current seek position in currently opened file
    'dlstrln(0, 1, INFO, @"ftell()")
    if (fnumber() < 0)
        'dstrln(0, 0, ERR, @"no file open")
        'dlprintf1(-1, 0, INFO, @"ftell() [ret: %d]\n\r", ENOTOPEN)
        return ENOTOPEN                          ' no file open
    'dlprintf1(-1, 0, INFO, @"ftell() [ret: %d]\n\r", _fseek_pos)
    return _fseek_pos

PUB ftrunc(): status | clust_nr, fat_sect, clust_cnt, nxt_clust
' Truncate open file to 0 bytes
    { except for the first one, clear the file's entire cluster chain to 0 }
    'dlstrln(0, 1, INFO, @"ftrunc()")
    clust_nr := ffirst_clust()
    fat_sect := clust_num_to_fat_sect(clust_nr)
    clust_cnt := _fclust_tot

    if (clust_cnt > 1)                          ' if there's only one cluster, nothing here
        status := read_fat(fat_sect)             '   needs to be done
        if (status <> 512)
            'dlstrln(0, 0, ERR, @"read error")
            'dlprintf1(-1, 0, INFO, @"ftrunc() [ret: %d]\n\r", status)
            return
        'dlprintf1(0, 0, NORM, @"more than 1 cluster (%d)\n\r", clust_cnt)
        clust_nr := read_fat_entry(clust_nr)    ' immediately skip to the next cluster - make sure
        repeat clust_cnt                        '   the first one _doesn't_ get cleared out
            { read next entry in chain before clearing the current one - need to know where
                to go to next beforehand }
            nxt_clust := read_fat_entry(clust_nr)
            write_fat_entry(clust_nr, 0)
            clust_nr := nxt_clust
        write_fat_entry(ffirst_clust(), CLUST_EOC)
        { write modified FAT back to disk }
        if (status := write_fat(fat_sect) <> 512)
            'dlstrln(0, 0, ERR, @"write error")
            'dlprintf1(-1, 0, INFO, @"ftrunc() [ret: %d]\n\r", status)
            return

    { set filesize to 0 }
    fset_size(0)
    dirent_update(fnumber())
    _fclust_tot := 1                            ' reset file's total cluster count
    _fclust_last := ffirst_clust()              ' remember the first cluster is the last one now

    'dlstrln(0, NORM, @"updated FAT")
    'read_fat(0)
    'dhexdump(@_meta_buff, 0, 4, 512, 16)
    'dlprintf1(-1, 0, INFO, @"ftrunc() [ret: %d]\n\r", status)

PUB fwrite(ptr_buff, len): status | sect_wrsz, nr_left, resp
' Write buffer to card
'   ptr_buff: address of buffer to write to SD
'   len: number of bytes to write from buffer
'       NOTE: a full sector is always written
    'dlstrln(0, 1, INFO, @"fwrite()")
    if (fnumber() < 0)
        'dlstrln(0, 0, ERR, @"no file open")
        'dlprintf1(-1, 0, INFO, @"fwrite() [ret: %d]\n\r", ENOTOPEN)
        return ENOTOPEN                         ' no file open
    ifnot (_fmode & O_WRITE)
        'dlstrln(0, 0, ERR, @"bad file mode")
        'dlprintf1(-1, 0, INFO, @"fwrite() [ret: %d]\n\r", EWRONGMODE)
        return EWRONGMODE                       ' must be open for writing

    { determine file's max phys. size on disk to see if more space needs to be allocated }
    if ( (ftell() + len) > fphys_size() )       ' is req'd size larger than allocated space?
        'dlprintf1(0, 0, NORM, @"ftell() + len = %d\n\r", ftell()+len)
        'dlprintf1(0, 0, NORM, @"fphys_size() = %d\n\r", fphys_size())
        'dlstrln(0, 0, WARN, @"current seek+req'd write len will be greater than file's allocated space")
        ifnot (_fmode & O_APPEND)   ' xxx make sure this is necessary
            'dlstrln(0, 0, ERR, @"error: bad seek (not opened for appending)")
            'dlprintf1(-1, 0, INFO, @"fwrite() [ret: %d]\n\r", EBADSEEK)
            return EBADSEEK
        'dlstrln(0, 0, NORM, @"OK - opened for appending")
        'dlstrln(0, 0, WARN, @"allocating another cluster")
        fallocate()                             ' if yes, then allocate another cluster

    nr_left := len                              ' init to total write length
    repeat while (nr_left > 0)
        'dlprintf1(0, 0, NORM, @"nr_left = %d\n\r", nr_left)
        { how much of the total to write to this sector }
        sect_wrsz := (sd.SECT_SZ - _sect_offs) <# nr_left
        'dlprintf1(0, 0, NORM, @"_sect_offs = %d\n\r", _sect_offs)

        if (_fmode & O_RDWR)                    ' read-modify-write mode
        { We can't simply write the new data to the sector - the card will actually
            erase the sector before writing, so any data in there would be lost. In order to merge
            this new data with what's already in the sector, we have to read the sector first,
            combine it in RAM, then write the modified sector back to the card. }
            resp := sd.rd_block(@_sect_buff, _fseek_sect)
            if (resp < 1)
                'dlstrln(0, 0, ERR, @"read error")
                'dlprintf1(-1, 0, INFO, @"fwrite() [ret: %d]\n\r", ERDIO)
                return ERDIO

        { copy the next chunk of data to the sector buffer }
        bytemove((@_sect_buff+_sect_offs), (ptr_buff+(len-nr_left)), sect_wrsz)
        'dhexdump(@_sect_buff, 0, 4, 512, 16)
        status := sd.wr_block(@_sect_buff, _fseek_sect)
        if ( status <> sd.WRITE_OK )
            'dlstrln(0, 0, ERR, @"write error")
            'dlprintf1(-1, 0, INFO, @"fwrite() [ret: %d]\n\r", EWRIO)
            return EWRIO
        if ( status == sd.WRITE_OK )
            { if written portion goes past the EOF, update the size (otherwise we're just
                overwriting what's already there) }
            'dlprintf1(0, 0, NORM, @"seek pos is %d\n\r", _fseek_pos)
            'dlprintf1(0, 0, NORM, @"sect_wrsz is %d\n\r", sect_wrsz)
            'dlprintf1(0, 0, NORM, @"file end is %d\n\r", fend())
            if ( (_fseek_pos + sect_wrsz) > fsize() )
                'dlprintf2(0, 0, WARN, @"updating size from %d to %d\n\r", fsize(), fsize()+sect_wrsz)
                { remember, it was determined already whether more clusters needed to be allocated
                    to accommodate the new size, so all that needs to be done here is update the
                    size recorded in the dirent }
                fset_size(fsize() + sect_wrsz)
            { update position to advance by how much was just written }
            fseek(_fseek_pos + sect_wrsz)
            nr_left -= sect_wrsz
    'dlprintf1(-1, 0, INFO, @"fwrite() [ret: %d]\n\r", status)
    dirent_update(fnumber())

PUB next_file(ptr_fn): fnr | fch
' Find next file in directory
'   ptr_fn: pointer to copy name of next file found to (set 0 to ignore)
'   Returns:
'       directory entry # (0..15) of file
'       ENOTFOUND (-2) if there are no more files
    'dlstrln(0, 1, INFO, @"next_file()")
    'dlprintf1(0, 0, NORM, @"_last_free_dirent = %d\n\r", _last_free_dirent)
    fnr := 0
    if ( ++_curr_file > 15 )                    ' last dirent in sector; go to next sector
        'dlstrln(0, 0, NORM, @"last dirent")
        if ( ++_dir_sect =< _rootdirend )
            'dlprintf1(0, 0, NORM, @"next dir sector (%d)\n\r", _dir_sect)
            sd.rd_block( @_meta_buff, _dir_sect )
            _meta_lastread := META_DIR
            'dhexdump(@_meta_buff, 0, 4, 512, 16)
        else                                    ' end of root dir
            'dlstrln(0, 0, NORM, @"last dir sector")
            --_dir_sect                         ' back up
            'dlstrln(0, 0, ERR, @"no more files and reached end of root dir"
            'dlprintf1(-1, 0, INFO, @"next_file() [ret: %d]\n\r", ENOTFOUND)
            return ENOTFOUND
        _curr_file := 0

    fch := byte[@_meta_buff][(_curr_file * DIRENT_LEN)]
    'dhexdump(@_meta_buff, 0, 4, 512, 16)
    'dlprintf1(0, 0, NORM, @"reading dirent %d\n\r", _curr_file)
    if ( (fch <> $00) )                         ' reached the end of the directory?
        'dlprintf1(0, 0, NORM, @"fn first char is %02.2x - regular file\n\r", fch)
        read_dirent(_curr_file)
        if ( ptr_fn )
            bytemove(ptr_fn, @_fname, 8)
            bytemove(ptr_fn+8, @".", 1)
            bytemove(ptr_fn+9, @_fext, 3)
            'dlprintf1(0, 0, NORM, @"(%s)\n\r", ptr_fn)
        'dlprintf1(0, 0, INFO, @"netx_file() [ret: %d]\n\r", ( ((_dir_sect-root_dir_sect()) * 16) + _curr_file ) )
        return ( ((_dir_sect-root_dir_sect()) * 16) + _curr_file )
    else
        'dlprintf1(0, 0, NORM, @"fn first char is %02.2x\n\r", fch)
        'dlstrln(0, 0, WARN, @"no more files")
        'dlprintf1(-1, 0, INFO, @"next_file() [ret: %d]\n\r", ENOTFOUND)
        { we're just updating this here/now because we happened to be in the right place at the
            right time; it isn't related to the error we're returning }
        _last_free_dirent := ((_dir_sect-root_dir_sect()) * 16) + _curr_file
        return ENOTFOUND

PUB opendir(ptr_str)
' Open a directory for subsequent operations
'   ptr_str: directory name
'   TODO: find() dirname - currently only re-reads the rootdir
    'dlstrln(0, 1, INFO, @"opendir()")
    _dir_sect := root_dir_sect()
    sd.rd_block(@_meta_buff, _dir_sect)
    read_dirent(0)
    _curr_file := 0
    _meta_lastread := META_DIR
    _meta_sect := _dir_sect
    'dlprintf1(-1, 0, INFO, @"opendir() [ret: %d]\n\r", result)

PUB read_fat(fat_sect): resp
' Read the FAT into the sector buffer
'   fat_sect: sector of the FAT to read (relative to start of FAT1)
    'dlstrln(0, 1, INFO, @"read_fat()")
    fat_sect += fat1_start()
    resp := sd.rd_block(@_meta_buff, fat_sect)
    _meta_lastread := META_FAT
    _meta_sect := fat_sect
    'dlprintf1(0, 0, NORM, @"resp = %d\n\r", resp)
    'dhexdump(@_sect_buff, 0, 4, 512, 16)
    'dlprintf1(-1, 0, INFO, @"read_fat() [ret: %d]\n\r", resp)

PUB write_fat(fat_sect): resp
' Write the FAT from the sector buffer
'   fat_sect: sector of the FAT to write
    'dlstrln(0, 1, INFO, @"write_fat()")
    'dhexdump(@_sect_buff, 0, 4, 512, 16)
    resp := sd.wr_block(@_meta_buff, (fat1_start() + fat_sect))
    'dlprintf1(-1, 0, INFO, @"write_fat() [ret: %d]\n\r", resp)

#include "filesystem.block.fat.spin"

' below: temporary, for devel purposes

pub readsector = rd_block
pub rd_block(ptr, sect)

    return sd.rd_block(ptr, sect)

pub writesector = wr_block
pub wr_block(ptr, sect): resp

    return sd.wr_block(ptr, sect)

PUB flash

    dira[26]:=1
    repeat
        !outa[26]
        time.msleep(50)


pub getsbp

    return @_meta_buff

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


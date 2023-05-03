{
    --------------------------------------------
    Filename: memfs.sdfat.spin
    Author: Jesse Burt
    Description: FAT32-formatted SDHC/XC driver
    Copyright (c) 2023
    Started Jun 11, 2022
    Updated May 3, 2023
    See end of file for terms of use.
    --------------------------------------------
}
#include "debug.spinh"
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
    EFSCORRUPT  = -12                           ' filesystem inconsistency or corruption

    ENOTIMPLM   = -256                          ' not implemented
    EWRIO       = -512 {$ff_ff_e0_00}           ' I/O error (writing)
    ERDIO       = -513 {$ff_ff_fd_ff}           ' I/O error (reading)

' File open modes
    O_RDONLY    = (1 << 0)                      ' R
    O_WRITE     = (1 << 1)                      ' W (writes _overwrite_)
    O_RDWR      = O_RDONLY | O_WRITE            ' R/W
    O_CREAT     = (1 << 2)                      ' create file
    O_APPEND    = (1 << 3)                      ' W (allow file to grow)
    O_TRUNC     = (1 << 4)                      ' truncate to 0 bytes

VAR

    word _sect_offs
    byte _sect_buff[sd#SECT_SZ]                 ' sector (data) buffer
    byte _meta_buff[sd#SECT_SZ]                 ' metadata buffer

OBJ

    sd  : "memory.sd-spi"
    str : "string"
    ser : "com.serial.terminal.ansi"
    time: "time"

PUB startx(SD_CS, SD_SCK, SD_MOSI, SD_MISO): status

'#ifdef DEBUG
    ser.startrxtx(DBG_RX, DBG_TX, 0, DBG_BAUD)
    time.msleep(10)
    ser.clear
'#endif
    dstrln_info(@"SD/FAT debug started")
    status := sd.init(SD_CS, SD_SCK, SD_MOSI, SD_MISO)
    if lookdown(status: 1..8)
        mount{}
        return
    return status

PUB mount{}: status
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
    if (status < 0)
        return status

    { get 1st partition's 1st sector number from it }
    status := read_part{}
    if (status < 0)
        return status

    { now read that sector }
    status := sd.rd_block(@_meta_buff, part_start{})
    if (status < 0)
        return status

    { sync the FATfs metadata from it }
    status := read_bpb{}
    if (status < 0)
        return status

PUB alloc_clust(cl_nr): status | tmp, fat_sect
' Allocate a new cluster
'   Returns: cluster number allocated
    dstrln(@"alloc_clust():")
    ifnot (_fmode & O_WRITE)                    ' file must be opened for writing
        dstrln_err(@"    bad file mode")
        dstrln(@"alloc_clust(): [ret]")
        return EWRONGMODE

    { read FAT sector }
    fat_sect := clust_num_to_fat_sect(cl_nr)
    if (status := read_fat(fat_sect) <> 512)
        dprintf1_err(@"    read error %d\n\r", status)
        return ERDIO

    { check the requested cluster number - is it free? }
    if (clust_rd(cl_nr) <> 0)
        dstrln_err(@"    cluster in use")
        return ECL_INUSE

    { write the EOC marker into the newly allocated entry }
    clust_wr(cl_nr, CLUST_EOC)

    { write the updated FAT sector to SD }
    dstrln(@"    updated FAT: ")
    dhexdump(@_meta_buff, 0, 4, 512, 16)
    if (status := write_fat(fat_sect) <> 512)
        dprintf1_err(@"    write error %d\n\r", status)
        dstrln(@"alloc_clust(): [ret]")
        return EWRIO

    dstrln(@"alloc_clust(): [ret]")
    return cl_nr

PUB alloc_clust_block(cl_st_nr, count): status | cl_nr, tmp, last_cl, fat_sect
' Allocate a block of contiguous clusters
'   cl_st_nr: starting cluster number
'   count: number of clusters to allocate
'   Returns:
'       number of clusters allocated on success
'       negative number on error
    dstrln(@"alloc_clust_block():")

    { validate the starting cluster number and count }
    if ((cl_st_nr < 3) or (count < 1))
        return EINVAL

    { read FAT sector }
    fat_sect := clust_num_to_fat_sect(cl_st_nr)
    if (read_fat(fat_sect) <> 512)
        dprintf1_err(@"    read error %d\n\r", status)
        return ERDIO

    last_cl := (cl_st_nr + (count-1))
    { before trying to allocate clusters, check that the requested number of them are free }
    repeat cl_nr from cl_st_nr to last_cl
        dprintf1(@"    cluster %d? ", cl_nr)
        if (clust_rd(cl_nr) <> 0)
            dstrln_err(@"    in use - fail")
            return ENOSPC                        ' cluster is in use
        dstrln(@"    free")

    { link clusters, from first to one before the last one }
    repeat cl_nr from cl_st_nr to (last_cl-1)
        clust_wr(cl_nr, (cl_nr + 1))

    { mark last cluster as the EOC }
    clust_wr(last_cl, CLUST_EOC)

    { write updated FAT sector }
    if (status := write_fat(fat_sect) <> 512)
        dprintf1_err(@"    write error %d\n\r", status)
        return EWRIO

    return count

PUB dirent_update(dirent_nr): status
' Update a directory entry on disk
'   dirent_nr: directory entry number
    dstrln(@"dirent_update()")
    dprintf1(@"    called with: %d\n\r", dirent_nr)

    { read root dir sect }
    dstrln(@"    rd_block")
    status := sd.rd_block(@_meta_buff, dirent_to_abs_sect(dirent_nr))
    if (status < 0)
        dprintf1_err(@"    read error %d\n\r", status)
        dstrln(@"dirent_update(): [ret]")
        return ERDIO

    { copy currently cached dirent to sector buffer }
    bytemove(@_meta_buff+dirent_start(dirent_nr), @_dirent, DIRENT_LEN)

    { write root dir sect back to disk }
    dstrln(@"    wr_block")
    status := sd.wr_block(@_meta_buff, dirent_to_abs_sect(dirent_nr))
    if (status < 0)
        dprintf1_err(@"    write error %d\n\r", status)
        dstrln(@"dirent_update(): [ret]")
        return EWRIO
    dstrln(@"dirent_update(): [ret]")

PUB fallocate{}: status | flc, cl_free, fat_sect
' Allocate a new cluster for the currently opened file
    dstrln(@"fallocate():")
    ifnot (_file_nr)
        dstrln(@"    error: no file open")
        return ENOTOPEN
    { find last cluster # of file }
    flc := _fclust_last
    dprintf1(@"    last cluster: %x\n\r", flc)

    { find a free cluster }
    cl_free := find_free_clust()
    if (cl_free < 0)
        dprintf1_err(@"    error %d\n\r", status)
        return cl_free
    dprintf1(@"    free cluster found: %x\n\r", cl_free)

    { rewrite the file's last cluster entry to point to the newly found free cluster }
    fat_sect := clust_num_to_fat_sect(flc)
    if (read_fat(fat_sect) <> 512)
        dprintf1_err(@"    read error %d\n\r", status)
        return ERDIO
    clust_wr(flc, cl_free)
    if (status := write_fat(fat_sect) <> 512)
        dprintf1_err(@"    write error %d\n\r", status)
        return EWRIO

    { allocate/write EOC in the newly found free cluster }
    status := alloc_clust(cl_free)
    _fclust_last := status

PUB fclose_ent{}: status
' Close the currently opened file
'   Returns:
'       0 on success
'       ENOTOPEN if a file isn't currently open
    dstrln(@"fclose_ent():")
    if (fnumber{} < 0)
        dstrln_err(@"    error: no file open")
        dstrln(@"fclose_ent(): [ret]")
        return ENOTOPEN                          ' file isn't open
    dprintf1_info(@"    close number %d OK\n\r", fnumber{})
    fclose{}
    dstrln(@"fclose_ent(): [ret]")
    return 0

PUB fcount_clust{}: t_clust | clust_nr, fat_sect, nx_clust, status
' Count number of clusters used by currently open file
    dstrln(@"fcount_clust():")
    ifnot (fnumber{})
        dstrln_err(@"    file not open")
        return ENOTOPEN

    { clear the file's entire cluster chain to 0 }
    clust_nr := ffirst_clust{}
    fat_sect := clust_num_to_fat_sect(clust_nr)
    status := read_fat(fat_sect)
    if (status <> 512)
        dprintf1_err(@"    read error %d\n\r", status)
        return ERDIO

    'xxx the below doesn't go past the first sector of the FAT
    t_clust := 0
    repeat
        { read next entry in chain before clearing the current one - need to know where
            to go to next beforehand }
        nx_clust := clust_rd(clust_nr)
        clust_wr(clust_nr, 0)
        clust_nr := nx_clust
        t_clust++
    while not (clust_is_eoc(clust_nr))
    _fclust_tot := t_clust
    dstrln(@"fcount_clust(): [ret]")

PUB fcreate(fn_str, attrs): status | dirent_nr, ffc
' Create file
'   fn_str: pointer to string containing filename
'   attrs: initial file attributes
    dstrln(@"fcreate():")
    { first, verify a file with the same name doesn't already exist }
    if (find(fn_str) <> ENOTFOUND)
        return EEXIST

    { find a free directory entry, and open it read/write }
    dirent_nr := find_free_dirent{}
    fopen_ent(dirent_nr, O_RDWR | O_CREAT)
    dprintf1(@"    found dirent # %d\n\r", dirent_nr)
    dprintf1(@"    fmode = %x\n\r", _fmode)

    { find a free cluster, starting at the beginning of the FAT }
    ffc := find_free_clust()
    dprintf1("    first free cluster: %x\n\r", ffc)
    if (ffc < 3)
        return ENOSPC
    dprintf1(@"    fmode = %x\n\r", _fmode)

    { set up the file's initial metadata }
    fset_fname(fn_str)
    fset_ext(fn_str+9)   'XXX expects string at fn_str to be in '8.3' format, _with_ the period
    fset_attrs(attrs)
    fset_size(0)
    fset_first_clust(ffc)
    dirent_update(dirent_nr)
    dstr(@"    file mode is: ")
    if (_fmode & O_RDONLY)
        dstr(@" O_RDONLY")'xxx
    if (_fmode & O_WRITE)
        dstr(@" O_WRITE")'xxx
    if (_fmode & O_CREAT)
        dstr(@" O_CREAT")
    if (_fmode & O_APPEND)
        dstr(@" O_APPEND")
    dnewline()

    { allocate a cluster }
    alloc_clust(ffc)

    dstrln(@"fcreate(): [ret]")
    return dirent_nr

PUB fdelete(fn_str): status | dirent, clust_nr, fat_sect, nx_clust, tmp
' Delete a file
'   fn_str: pointer to string containing filename
'   Returns:
'       existing directory entry number on success
'       negative numbers on failure
    dstrln(@"fdelete()")
    { verify file exists }
    dprintf1(@"    about to look for %s\n\r", fn_str)
    dirent := find(fn_str)
    if (dirent < 0)
        return ENOTFOUND

    { rename file with first byte set to FATTR_DEL ($E5) }
    fopen_ent(dirent, O_RDWR)
    fset_deleted{}
    dirent_update(dirent)

    { clear the file's entire cluster chain to 0 }
    clust_nr := ffirst_clust{}
    fat_sect := clust_num_to_fat_sect(clust_nr)
    status := read_fat(fat_sect)
    if (status <> 512)
        dprintf1_err(@"    read error %d\n\r", status)
        return ERDIO

    repeat ftotal_clust{}
        { read next entry in chain before clearing the current one - need to know where
            to go to next beforehand }
        nx_clust := clust_rd(clust_nr)
        clust_wr(clust_nr, 0)
        clust_nr := nx_clust

    { write modified FAT back to disk }
    if (status := write_fat(fat_sect) <> 512)
        dprintf1_err(@"    write error %d\n\r", status)
        return EWRIO
    dstrln(@"fdelete(): [ret]")
    return dirent

PUB file_size{}: sz
' Get size of opened file
    return fsize{}

PUB find(ptr_str): dirent | rds, endofdir, name_tmp[3], ext_tmp
' Find file, by name
'   Valid values:
'       ptr_str: pointer to space-padded string containing filename (8.3)
'   Returns:
'       directory entry of file (0..n)
'       or ENOTFOUND (-2) if not found
    dstrln(@"find():")
    dirent := 0
    rds := 0
    endofdir := false

    { get filename and extension, and convert to uppercase }
    bytemove(@name_tmp, str.toupper(str.left(ptr_str, 8)), 9)
    bytemove(@ext_tmp, str.toupper(str.right(ptr_str, 3)), 4)
    dprintf2(@"    Looking for %s.%s\n\r", @name_tmp, @ext_tmp)
    repeat                                      ' check each rootdir sector
        sd.rd_block(@_meta_buff, root_dir_sect{}+rds)
        dirent := 0

        repeat DIRENTS                          ' check each file in the sector
            read_dirent(dirent)                  ' get current file's info
            if (dirent_never_used{})              ' last directory entry
                endofdir := true
                fclose_ent{}
                quit
            if (fdeleted{})                     ' ignore deleted files
                dirent++
                next
'            ser.strln(fname)
'            ser.strln(@name_tmp)
            if (strcomp(fname{}, @name_tmp) and {
}           strcomp(fname_ext{}, @ext_tmp))      ' match found for filename; get
'                flash
                fclose_ent{}
                return (dirent+(rds * DIRENTS)) '   number relative to entr. 0
            fclose_ent{}
            dirent++
        rds++                                   ' go to next root dir sector
    until endofdir
    dstrln_err(@"    error: not found")
    dstrln(@"find(): [ret]")
    return ENOTFOUND

CON FREE_CLUST = 0
PUB find_free_clust(): f | fat_sector, fat_entry, fat_sect_entry
' Find a free cluster
    fat_sector := fat1_start()                  ' start at first sector of first FAT
    fat_sect_entry := 3                         ' skip reserved, root dir, and vol label entries

    repeat                                      ' for each FAT sector...
        repeat                                  '   for each FAT entry...
            { get absolute FAT entry }
            fat_entry := ( (fat_sector * 128) + fat_sect_entry )
            if ( clust_rd(fat_entry) == FREE_CLUST )
                return fat_entry                ' return the absolute FAT entry #
            fat_sect_entry++                    ' otherwise, continue on
        while ( fat_sect_entry < 128 )
        fat_sector++
    while ( fat_sector < (fat1_start() + sects_per_fat()) )

    return ENOSPC                               ' no free clusters

PUB find_free_dirent{}: dirent_nr | endofdir
' Find free directory entry
'   Returns: entry number
    dstrln(@"find_free_dirent():")
    repeat
        dirent_nr := 0
        repeat 16                               ' up to 16 entries per sector
            fclose_ent{}
            dprintf1(@"    checking dirent #%d...\n\r", dirent_nr)
            fopen_ent(dirent_nr, O_RDONLY)    ' get current dirent's info
            { important: skip entries that are subdirs, deleted files, or the volume name,
                but count them as dirents }
            if (fis_dir{} or fdeleted{} or fis_vol_nm{})
                dirent_nr++
                next
            if (dirent_never_used{})              ' last directory entry
                endofdir := true
                quit
            dirent_nr++
    until endofdir
    fclose_ent{}

PUB find_last_clust{}: cl_nr | fat_ent, resp, fat_sect
' Find last cluster # of file
'   LIMITATIONS:
'       * stays on first sector of FAT
    dstrln(@"find_last_clust():")
    if (fnumber{} < 0)
        dstrln_err(@"    error: no file open")
        return ENOTOPEN
    dprintf1(@"    file number is %d\n\r", fnumber{})

    cl_nr := 0
    fat_ent := ffirst_clust{}
    { try to catch some invalid cases - these are signs there's something seriously
        wrong with the filesystem }
    if (fat_ent & $f000_000)                    ' top 4 bits of clust nr set? they shouldn't be...
        dprintf1_err(@"    error: invalid FAT entry %x\n\r", fat_ent)
        abort EFSCORRUPT
    dprintf1(@"    first clust: %x\n\r", fat_ent)
    { read the FAT }
    fat_sect := clust_num_to_fat_sect(fat_ent)
    if (cl_nr := read_fat(fat_sect) <> 512)
        dprintf1_err(@"    read error %d\n\r", cl_nr)
        return ERDIO

    { follow chain }
    repeat
        cl_nr := fat_ent
        fat_ent := clust_rd(fat_ent)
        if ( fat_ent == 0 )
            dstrln(@"    error: invalid FAT entry 0")
            quit    ' abort EFSCORRUPT?
        dprintf1(@"    cl_nr: %x\n\r", cl_nr)
        dprintf1(@"    fat_ent: %x\n\r", fat_ent)
    while not (clust_is_eoc(fat_ent))
    dprintf1(@"    last clust is %x\n\r", cl_nr)
    _fclust_last := cl_nr
    dstrln(@"find_last_clust(): [ret]")
    return cl_nr

PUB fopen(fn_str, mode): status
' Open file for subsequent operations
'   Valid values:
'       fn_str: pointer to string containing filename (must be space padded)
'       mode: O_RDONLY (1), or O_WRITE (2), O_RDWR (3)
'   Returns:
'       file number (dirent #) if successful,
'       or error
    dstrln(@"fopen():")
    if (fnumber{} => 0)                              ' file is already open
        dstrln_err(@"    error: already open")   'xxx bit of duplication with FOpenEnt()
        return EOPEN
    status := find(fn_str)                      ' look for file by name
'    if (_fmode & O_CREAT)
'        status := fcreate(fn_str, FATTR_ARC)
'    else
    if (status == ENOTFOUND)                ' file not found
        dstrln_err(@"    error: not found")
        return ENOTFOUND
    dprintf1(@"    found file, dirent # %d\n\r", status)
    status := fopen_ent(status, mode)
    dstrln(@"fopen(): [ret]")

PUB flash

    dira[26]:=1
    repeat
        !outa[26]
        time.msleep(50)

PUB fopen_ent(file_nr, mode): status
' Open file by dirent # for subsequent operations
'   Valid values:
'       file_nr: directory entry number
'       mode: O_RDONLY (1), O_WRITE (2), O_RDWR (3)
'   Returns:
'       file number (dirent #) if successful,
'       or error
    dstrln(@"fopen_ent():")
    if (fnumber{} => 0)
        dstrln_warn(@"    already open")
        return EOPEN
    sd.rd_block(@_meta_buff, (root_dir_sect{} + dirent_to_sect(file_nr)))
    read_dirent(file_nr & $0f)               ' cache dirent metadata
    if (dirent_never_used{})
        ifnot (mode & O_CREAT)              ' need create bit set to open an unused dirent
            dstrln_err(@"    error: dirent unused")
            fclose_ent{}
            dstrln(@"fopen_ent(): [ret]")
            return

    dhexdump(@_dirent, 0, 4, 32, 16)
'    ser.printf3(@"    opened file/dirent # %d (%s.%s)\n\r", fnumber{}, @_fname, @_fext) 'xxx corruption in debug output?
    dprintf1(@"    opened file/dirent # %d\n\r", fnumber{})
    { set up the initial state:
        * set the seek pointer to the file's beginning
        * cache the file's open mode
        * cache the file's last cluster number; it'll be used later if more need to be
            allocated }
    if (mode & O_APPEND)
        mode |= O_WRITE                         ' in case it isn't already
        fseek(fsize{})                          ' init seek pointer to end of file
    else
        _fseek_pos := 0
        _fseek_sect := ffirst_sect{}             ' initialize current sector with file's first
    _fmode := mode
    ifnot (mode & O_CREAT)                      ' don't bother checking which cluster # is
        find_last_clust{}                         '   the file's last if creating it
    if (mode & O_TRUNC)
        ftrunc{}
    dstrln(@"fopen_ent(): [ret]")
    return fnumber{}

PUB fread(ptr_dest, nr_bytes): nr_read | nr_left, movbytes, resp
' Read a block of data from current seek position of opened file into ptr_dest
'   Valid values:
'       ptr_dest: pointer to buffer to copy data read
'       nr_bytes: 1..512, or the size of the file, whichever is smaller
'   Returns:
'       number of bytes actually read,
'       or error
    dstrln(@"fread():")
    if (fnumber{} < 0)                          ' no file open
        return ENOTOPEN

    nr_read := nr_left := 0

    { make sure current seek isn't already at the EOF }
    if (_fseek_pos < fsize{})
        { clamp nr_bytes to physical limits:
            sector size, file size, and proximity to end of file }
'        dprintf1("nr_bytes: %d\n\r", nr_bytes) 'xxx terminal corruption
        nr_bytes := nr_bytes <# sect_sz{} <# fsize{} <# (fsize{}-_fseek_pos) ' XXX seems like this should be -1
        dprintf1(@"sectsz: %d\n\r", sect_sz{})
        dprintf1(@"fsize: %d\n\r", fsize{})
        dprintf1(@"(fsize-_fseek_pos): %d\n\r", fsize{}-_fseek_pos)

        { read a block from the SD card into the internal sector buffer }
        if ( _fseek_sect <> _fseek_prev_sect )
            resp := sd.rd_block(@_sect_buff, _fseek_sect)
            if (resp < 1)
                return ERDIO
        else
            dstrln_info(@"current seek sector == prev seek sector; not re-reading")

        { copy as many bytes as possible from it into the user's buffer }
        movbytes := sect_sz{}-_sect_offs
        bytemove(ptr_dest, (@_sect_buff+_sect_offs), movbytes <# nr_bytes)
        nr_read := (nr_read + movbytes) <# nr_bytes
        nr_left := (nr_bytes - nr_read)

        { if there's still some data left, read the next block from the SD card, and copy
            the remainder of the requested length into the user's buffer }
        if (nr_left > 0)
            resp := sd.rd_block(@_sect_buff, _fseek_sect)
            if (resp < 1)
                return ERDIO
            bytemove(ptr_dest+nr_read, @_sect_buff, nr_left)
            nr_read += nr_left
        _fseek_prev_sect := _fseek_sect
        fseek(_fseek_pos + nr_read)             ' update seek pointer
        return nr_read
    else
        return EEOF                             ' reached end of file
    dstrln(@"fread(): [ret]")

PUB frename(fn_old, fn_new): status | dirent
' Rename file
'   fn_old: existing filename
'   fn_new: new filename
'   Returns:
'       dirent # of file on success
'       negative numbers on error
    { verify existence of file }
    dirent := find(fn_old)
    if (dirent < 0)
        dstrln_err(@"file not found")
        return ENOTFOUND

    { verify new filename is valid }
    if (strcomp(fn_old, fn_new))
        return EEXIST

    fopen_ent(dirent, O_RDWR)
    fset_fname(fn_new)
    dirent_update(dirent)
    fclose_ent{}

PUB fseek(pos): status | seek_clust, clust_offs, rel_sect_nr, clust_nr, fat_sect, sect_offs
' Seek to position in currently open file
'   Valid values:
'       pos: 0 to file size-1
'   Returns:
'       position seeked to,
'       or error
    dstrln(@"fseek():")
    longfill(@seek_clust, 0, 6)                 ' clear local vars
    if (fnumber{} < 0)
        dstrln_err(@"    error: no file open")
        return ENOTOPEN                          ' no file open
    if (pos < 0)                                ' catch bad seek positions
        dstrln_err(@"    error: illegal seek")
        return EBADSEEK
    if (pos > fsize{})
        ifnot (_fmode & O_APPEND)
            dstrln_err(@"    error: illegal seek")
            return EBADSEEK

    { initialize cluster number with the file's first cluster number }
    clust_nr := ffirst_clust{}

    { determine which cluster (in "n'th" terms) in the chain the seek pos. is }
    seek_clust := (pos / clust_sz{})

    { use remainder to get byte offset within cluster (0..cluster size-1) }
    clust_offs := (pos // clust_sz{})

    { use high bits of offset within cluster to get sector offset (0..sectors per cluster-1)
        within the cluster }
    rel_sect_nr := (clust_offs >> 9)

    { follow the cluster chain to determine which actual cluster it is }
    fat_sect := clust_num_to_fat_sect(clust_nr)
    read_fat(fat_sect)
    repeat seek_clust
        { read next entry in chain }
        clust_nr := clust_rd(clust_nr)
        sect_offs += 4

    { set the absolute sector number and the seek position for subsequent R/W:
        translate the cluster number to a sector number on the SD card, and add the
        sector offset from above
        also, set offset within sector to find the start of the data (0..bytes per sector-1) }
    _fseek_sect := (clust_to_sect(clust_nr) + rel_sect_nr)
    _fseek_pos := pos
    _sect_offs := (pos // sect_sz{})
    dstrln(@"fseek(): [ret]")
    return pos

PUB ftell{}: pos
' Get current seek position in currently opened file
    if (fnumber{} < 0)
        return ENOTOPEN                          ' no file open
    return _fseek_pos

PUB ftrunc{}: status | clust_nr, fat_sect, clust_cnt, nx_clust
' Truncate open file to 0 bytes
    { except for the first one, clear the file's entire cluster chain to 0 }
    dstrln(@"ftrunc():")
    clust_nr := ffirst_clust{}
    fat_sect := clust_num_to_fat_sect(clust_nr)
    clust_cnt := fcount_clust{}

    if (clust_cnt > 1)                          ' if there's only one cluster, nothing here
        status := read_fat(fat_sect)             '   needs to be done
        if (status <> 512)
            dprintf1_err(@"    read error %d\n\r", status)
            return
        dprintf1(@"    more than 1 cluster (%d)\n", clust_cnt)
        clust_nr := clust_rd(clust_nr)           ' immediately skip to the next cluster - make sure
        repeat clust_cnt                        '   the first one _doesn't_ get cleared out
            { read next entry in chain before clearing the current one - need to know where
                to go to next beforehand }
            nx_clust := clust_rd(clust_nr)
            clust_wr(clust_nr, 0)
            clust_nr := nx_clust
        clust_wr(ffirst_clust{}, CLUST_EOC)
        { write modified FAT back to disk }
        if (status := write_fat(fat_sect) <> 512)
            dprintf1_err(@"    write error %d\n\r", status)
            return

    { set filesize to 0 }
    fset_size(0)
    dirent_update(fnumber{})

    dstrln(@"updated FAT")
    read_fat(0)
    dhexdump(@_meta_buff, 0, 4, 512, 16)
    dstrln(@"ftrunc(): [ret]")

PUB fwrite(ptr_buff, len): status | sect_wrsz, nr_left, resp
' Write buffer to card
'   ptr_buff: address of buffer to write to SD
'   len: number of bytes to write from buffer
'       NOTE: a full sector is always written
    dstrln(@"fwrite():")
    if (fnumber{} < 0)
        return ENOTOPEN                          ' no file open
    ifnot (_fmode & O_WRITE)
        return EWRONGMODE                        ' must be open for writing

    { determine file's max phys. size on disk to see if more space needs to be allocated }
    fcount_clust{}
    if ((ftell{} + len) > (fphys_size{}-1))      ' is req'd size larger than allocated space?
        ifnot (_fmode & O_APPEND)   ' xxx make sure this is necessary
            return EBADSEEK
        dstrln_info(@"    allocating another cluster")
        fallocate{}                             ' if yes, then allocate another cluster

    nr_left := len                              ' init to total write length
    repeat while (nr_left > 0)
        dprintf1(@"    nr_left = %d\n\r", nr_left)
        { how much of the total to write to this sector }
        sect_wrsz := (sd#SECT_SZ - _sect_offs) <# nr_left
        dprintf1(@"    _sect_offs = %d\n\r", _sect_offs)
        dprintf1(@"    sect_wrsz = %d\n\r", sect_wrsz)

        if (_fmode & O_RDWR)                    ' read-modify-write mode
        { read the sector's current contents, so it can be merged with this write }
            resp := sd.rd_block(@_sect_buff, _fseek_sect)
            if (resp < 1)
                return ERDIO

        { copy the next chunk of data to the sector buffer }
        bytemove((@_sect_buff+_sect_offs), (ptr_buff+(len-nr_left)), sect_wrsz)

        status := sd.wr_block(@_sect_buff, _fseek_sect)
        if (status == sd#SECT_SZ)
            if (_fmode & O_APPEND)              ' if appending, update size in dirent cache
                fset_size(fsize{} + sect_wrsz)
            { update position to advance by how much was just written }
            fseek(_fseek_pos + sect_wrsz)
            nr_left -= sect_wrsz
    dstrln(@"fwrite(): [ret]")
    dirent_update(fnumber{})

PUB read_fat(fat_sect): resp
' Read the FAT into the sector buffer
'   fat_sect: sector of the FAT to read
    dstrln(@"read_fat():")
    resp := sd.rd_block(@_meta_buff, (fat1_start{} + fat_sect))
'    ser.hexdump(@_sect_buff, 0, 4, 512, 16)
    dstrln(@"read_fat(): [ret]")

PUB write_fat(fat_sect): resp
' Write the FAT from the sector buffer
'   fat_sect: sector of the FAT to write
    dstrln(@"write_fat():")
'    ser.hexdump(@_sect_buff, 0, 4, 512, 16)
    resp := sd.wr_block(@_meta_buff, (fat1_start{} + fat_sect))
    dstrln(@"write_fat(): [ret]")

#include "filesystem.block.fat.spin"

' below: temporary, for devel purposes

pub rd_block(ptr, sect)

    return sd.rd_block(ptr, sect)

pub wr_block(ptr, sect): resp

    return sd.wr_block(ptr, sect)

pub getsbp

    return @_meta_buff

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


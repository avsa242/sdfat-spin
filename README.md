# sdfat-spin
------------

This is a P8X32A/Propeller, P2X8C4M64P/Propeller 2 implementation of the FAT filesystem on SD.

**IMPORTANT**: This software is meant to be used with the [spin-standard-library](https://github.com/avsa242/spin-standard-library) (P8X32A) or [p2-spin-standard-library](https://github.com/avsa242/p2-spin-standard-library) (P2X8C4M64P). Please install the applicable library first before attempting to use this code, otherwise you will be missing several files required to build the project.


## Salient Features

* FAT32 on SDHC/SDXC
* Open file by name or dirent number
* Read currently opened file's attributes: file name and extension, is directory, is the volume name, size, date, time
* Read, write a block of data (writes are currently _always_ synchronous)
* File management: rename, delete, create, find by filename
* Cluster management: Find free cluster, allocate an arbitrary cluster, allocate block of clusters, allocate additional cluster for currently open file, count clusters allocated to file
* POSIX-ish familiarities: (some) method names and params, file open modes


## File open modes supported

| Symbol	| Description 					| Seek behavior allowed	|
|---------------|-----------------------------------------------|-----------------------|
| `O_RDONLY`	| Read 						| random               	|
| `O_WRITE`	| Write 					| random		|
| `O_RDWR`	| Read/Write 					| random		|
| `O_CREAT`	| Create file 					| n/a			|
| `O_APPEND`	| Writes append to file	 			| always points to EOF	|
| `O_TRUNC`	| Truncate file to 0 bytes after opening	| n/a			|

(modes are bitfields that can be OR'd together)


## Requirements

P1/SPIN1:
* spin-standard-library
* [fatfs-spin](https://github.com/avsa242/fatfs-spin)
* [sdmem-spin](https://github.com/avsa242/sdmem-spin)

~~P2/SPIN2:~~
* ~~p2-spin-standard-library~~


## Compiler Compatibility

| Processor | Language | Compiler               | Backend      | Status                |
|-----------|----------|------------------------|--------------|-----------------------|
| P1        | SPIN1    | FlexSpin (6.8.1)       | Bytecode     | OK                    |
| P1        | SPIN1    | FlexSpin (6.8.1)       | Native/PASM  | Some demos FTBFS      |
| P2        | SPIN2    | FlexSpin (6.8.1)       | NuCode       | Not yet implemented   |
| P2        | SPIN2    | FlexSpin (6.8.1)       | Native/PASM2 | Not yet implemented   |

(other versions or toolchains not listed are __not supported__, and _may or may not_ work)


## Limitations

* Very early in development - may malfunction, or outright fail to build
* FAT16, FAT12 not yet supported
* Pre-SDHC cards unsupported (unplanned)
* No (sub)directory support yet
* No long filename support yet
* Slow
* API should be considered unstable


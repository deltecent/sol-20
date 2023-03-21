; this is a disassembled dump of the CBIOS found on my SOL boot disk.
; the comments are my best guesses and aren't to be fully trusted.
;
; FIRST VERSION DATE: 12/19/99
;      REVISION DATE: 12/20/01
;
; remaining mysteries:
;   1) the call to the SELDSK routine uses bit 7 of the incoming C reg
;      to trigger certain behaviors.  this use of C is non-standard.
;   2) "WRMAPN" uses self modifying code (pointless) and the logic to
;      modify the byte appear to be broken in some cases anyway.
;   3) the "BOOT" routine copies a four-byte table from B9E0 to
;      $0050, but cp/m supposedly doesn't use this range of memory.
;   4) there is a truncated jump vector table highly similar to the
;      one at the official start of BIOS.  Interestingly, it is at the
;      location one would expect for a standard/lean bios.  Is this
;      to make "dirty" programs work that can't cope with fat bios's?
;   5) search for the string "FIXME" for a couple other minor points.
;   6) there are sundry bytes scattered about that aren't used.
;
; the following sources were consulted in making this translation:
;   "The Programmer's CP/M Handbook", Andy Johnson-Laird
;   NBIOS56.ASM (c) 1980, 1981, 1982 by Steve Bogolub
;   the CP/M 2.2 Alteration Guide
;
; a purely local (and somewhat loose) convention is that labels that
; are "real" entry points are terminated with a colon after the label,
; while "throwaway" labels for loops and targets of local branches
; don't have colons.  thus as you scan through the code you have some
; idea of the significance of the instruction as a target.


MSIZE	EQU	48		; CP/M version memory size in kilobytes

; ------------------------------------------------------------
;
; "bias" is address offset from 3400H for memory systems
; than 16k (referred to as "b" throughout text)
;
;BIAS	EQU	(MSIZE-20)*1024
; we have a fat bios so it starts earlier.
BIAS	EQU	(MSIZE-20)*1024-0700H
;
CCP	EQU	3400H+BIAS	; base of CCP
BDOS	EQU	CCP+0806H	; base of BDOS
BIOS	EQU	CCP+1600H	; base of BIOS

TPA	EQU	0100H		; start of TPA area

IOBYTE	EQU	0003H		; standard CPM IOBYTE address
DEFDRV	EQU	0004H		; default disk drive: 0=A, 1=B, ... 15=P


; ------------------------------------------------------------
; start of BIOS

	ORG	BIOS

; bios jump vector table.
;
; good programs will use these, but it would appear that some
; programs jump where the expect bios to be, up at $BA00, so
; there is a secondary table there.

	JMP	BOOT		; cold start
WBOOTE:	JMP	WBOOT		; warm start
	JMP	CONST		; get console status
	JMP	CONIN		; console input
	JMP	CONOUT		; console output
	JMP	LIST		; printer output
	JMP	PUNCH		; punch output
	JMP	READER		; reader input
	JMP	HOME		; home selected drive
	JMP	SELDSK		; select disk drive
	JMP	SETTRK		; set track number
	JMP	SETSEC		; set sector number
	JMP	SETDMA		; set transfer address
	JMP	READ		; perform disk read
	JMP	WRITE		; perform disk write
	JMP	LISTST		; return list status
	JMP	SECTRAN		; translate sector

	JMP	BLKOP		; ???


CRIGHT	DB	CR,LF
	DB	'CP/M2 on North Star',CR,LF
	DB	'0'+(MSIZE/10)
	DB	'0'+(MSIZE MOD 10)
	DB	'K Vers 2.22 DQ  ',CR,LF
	DB	'(C) 1981 Lifeboat Associates',CR,LF,'$'


; cold boot: standard BIOS entry point
BOOT:
	LXI	SP,TPA		; stack just under TPA
	XRA	A
	STA	DEFDRV		; default drive is A:
	STA	WBFLAG		; we are doing a cold boot
	CALL	CALBR8		; calibrate the disk speed
	CALL	MAKSTT		; make sector translation tables
	CALL	INITTBL
	LXI	H,B9E0
	LXI	D,0050H		; $0050 to $005B is supposedly reserved/unused
	CALL	BLKMOV4		; copy $B9E0 to $0050
	CALL	BOOT2		; cold boot
	JMP	GOCPM


; warm boot: standard BIOS entry point
WBOOT:
	LXI	SP,TPA		; stack just below TPA
	CALL	INITTBL

	; transfer disk A, track 0, sectors 4-9 to memory at 9C00H
; trk 0, sec 4 -> 0x9C00
; trk 0, sec 5 -> 0x9E00
; trk 0, sec 6 -> 0xA000
; trk 0, sec 7 -> 0xA200
; trk 0, sec 8 -> 0xA400
; trk 0, sec 9 -> 0xA600
	MVI	A,06H		; 6 sectors
	LXI	B,0081H		; trk 00, NSORD dbl-dens, disk A
	LXI	D,0401H		; start w/sec 4, E=01 -> read
	LXI	H,CCP-0100H	; destination
	CALL	BLKOP
	JNZ	WBOOT		; jump on failure

	; transfer disk A, track 1, sectors 0-4 to memory at A800H
; trk 1, sec 0 -> 0xA800
; trk 1, sec 1 -> 0xAA00
; trk 1, sec 2 -> 0xAC00
; trk 1, sec 3 -> 0xAE00
; trk 1, sec 4 -> 0xB000
	MVI	A,05H		; transfer 5 sectors
	LXI	B,0181H		; trk 01, NSORD dbl-dens, disk A
	LXI	D,0001H		; start w/sec 0, E=01 -> read
	LXI	H,CCP+0B00H	; destination
	CALL	BLKOP
	JNZ	WBOOT		; jump on failure

	; the final transfer is only 256B.  we can't directly load
	; the 512B sector to its resting spot as it would overwrite
	; this code you are reading here.  so instead the 512B sector
	; is saved to HSTBUF and then the first 256B of that is moved
	; to its proper location.

	; transfer disk A, track 1, sector 5 to HSTBUF
	MVI	A,01H		; transfer 1 sector
	LXI	B,0181H		; track 01, NSORD dbl-dens, disk A
	LXI	D,0501H		; start w/sec 5, E=01 -> read
	LHLD	PHSTBUF		; pointer to host disk buffer
	CALL	BLKOP
	JNZ	WBOOT		; jump on failure

	; transfer first 256B of HSTBUF from B200H to B2FF
	LHLD	PHSTBUF		; pointer to host disk buffer
	LXI	D,CCP+1500H	; disk A, track 1, sector 5 to B200H
	MVI	B,00H		; 256 bytes
	CALL	BLKMOV

; end of load operation, set parameters and go to cp/m
GOCPM:
	MVI	A,0C3H		; C3 is a JMP instruction
	STA	0000H		; for JMP to WBOOT
	STA	0005H		; for JMP to BDOS
	LXI	H,WBOOTE	; wboot entry point
	SHLD	0001H		; set address field for JMP at 0
	LXI	H,BDOS		; third BDOS vector table entry
	SHLD	0006H		; address field of JMP at 0005 to BDOS

	; print boot message if this is the first time
	LXI	H,WBFLAG
	MOV	A,M
	ORA	A		; Z set on cold boot, cleared on warm boot
	MVI	M,1		; set flag so next time we don't print msg
	PUSH	PSW		; note: carry is 0
	LXI	H,CRIGHT
	CZ	PRMSG		; print copyright message on cold boot
	POP	PSW

	PUSH	PSW
	CNZ	WARM2		; clear screen if warm boot
	POP	PSW		; restore WBFLAG to Z flag

	; set up default drive
	LDA	DEFDRV
	MOV	C,A

	; auto execute a command if
	;   coldboot && (optflg[0]==1)
	;   warmboot && (optflg[1]==1)
	; stated another way, if optflg[1:0] is
	;   0, never perform autocommand
	;   1, perform autocommand on coldboot
	;   2, perform autocommand on warmboot
	;   3, perform autocommand on coldboot and warmboot
	LDA	OPTFLG
	RRC			; cy=optflg[0]; RRC doesn't affect Z flag
	JZ	GOCCP		; jump if cold boot
	RRC			; cy=optflg[1]
GOCCP	JNC	CCP+0003H	; clear input buffer, then get CCP command
	JMP	CCP+0000H	; just get CCP command

; a slightly shorter way is:
;	INR	A		; A=2 on warmboot, A=1 on coldboot
;	MOV	B,A
;	LDA	OPTFLG
;	ANA	B		; test bit 0 or 1
;	JZ	CCP+0003H	; clear input buffer, then get CCP command
;	JMP	CCP+0000H	; just get CCP command


; this is the disk parameter header table.
; there are four disk parameter headers, one or each disk of A,B,C,D

DPBASE:
	; disk A (0)
	DW	0000H		; XLT: logical->physical translation vector
	DW	0,0,0		; scratch area for bdos
	DW	DIRBUF		; DIRBUF: 128 scratch buffer for dir ops
	DW	DPB0		; DPB: disk parameter block
	DW	CSV0		; CSV: addr of scratch for bdos disk change test
	DW	ALV0		; ALV: addr of scratch for bdos disk allocation

	; disk B (1)
	DW	0000H		; XLT: logical->physical translation vector
	DW	0,0,0		; scratch area for bdos
	DW	DIRBUF		; DIRBUF: 128 scratch buffer for dir ops
	DW	DPB0		; DPB: disk parameter block
	DW	CSV1		; CSV: addr of scratch for bdos disk change test
	DW	ALV1		; ALV: addr of scratch for bdos disk allocation

	; disk C (2)
	DW	0000H		; XLT: logical->physical translation vector
	DW	0,0,0		; scratch area for bdos
	DW	DIRBUF		; DIRBUF: 128 scratch buffer for dir ops
	DW	DPB0		; DPB: disk parameter block
	DW	CSV2		; CSV: addr of scratch for bdos disk change test
	DW	ALV2		; ALV: addr of scratch for bdos disk allocation

	; disk D (3)
	DW	0000H		; XLT: logical->physical translation vector
	DW	0,0,0		; scratch area for bdos
	DW	DIRBUF		; DIRBUF: 128 scratch buffer for dir ops
	DW	DPB0		; DPB: disk parameter block
	DW	CSV3		; CSV: addr of scratch for bdos disk change test
	DW	ALV3		; ALV: addr of scratch for bdos disk allocation

; below are four disk parameter blocks for four different disk
; formats.  each physical disk will point to one of these formats.

; disk format: double density, double sided, format 2 (2K Blocks)
DPB0:	DW	40	; SPT: sectors per track   10 512B sec = 40 128B sec
	DB	04H	; BSH: block shift factor  LOG2(allocblksize/128)
	DB	0FH	; BLM: block mask          ((1<<BSH)-1)
	DB	01H	; EXM: extent mask
	DW	00A9H	; DSM: total storage
	DW	64-1	; DRM: directory max       # of dir entries-1
	DB	80H	; AL0: alloc 0
	DB	00H	; AL1: alloc 1
	DW	0010H	; CKS: check size; size of dir check vector
	DW	0002H	; OFF: # of reserved tracks (track offset)

; disk format: single density, single sided, format 1 (1K Blocks)
DPB1:	DW	20	; SPT: 20 128B sectors per track
	DB	03H	; BSH: block shift factor
	DB	07H	; BLM: block mask ((1<<BSH)-1)
	DB	00H	; EXM: extent mask
	DW	004FH	; DSM: total storage
	DW	64-1	; DRM: directory max
	DB	0C0H	; AL0: alloc 0
	DB	00H	; AL1: alloc 1
	DW	0010H	; CKS: check size; size of dir check vector
	DW	0003H	; OFF: # of reserved tracks (track offset)

; disk format: double density, single sided, format 1 (1K Blocks)
DPB2:	DW	40	; SPT: 40 128B sectors per track
	DB	03H	; BSH: block shift factor
	DB	07H	; BLM: block mask ((1<<BSH)-1)
	DB	00H	; EXM: extent mask
	DW	00A4H	; DSM: total storage
	DW	64-1	; DRM: directory max
	DB	0C0H	; AL0: alloc 0
	DB	00H	; AL1: alloc 1
	DW	0010H	; CKS: check size; size of dir check vector
	DW	0002H	; OFF: # of reserved tracks (track offset)

; disk format: double density, single sided, format 2 (2K Blocks)
DPB3:	DW	40	; SPT: 40 128B sectors per track
	DB	04H	; BSH: block shift factor
	DB	0FH	; BLM: block mask ((1<<BSH)-1)
	DB	01H	; EXM: extent mask
	DW	0051H	; DSM: total storage
	DW	64-1	; DRM: directory max
	DB	80H	; AL0: alloc 0
	DB	00H	; AL1: alloc 1
	DW	0010H	; CKS: check size; size of dir check vector
	DW	0002H	; OFF: # of reserved tracks (track offset)


; select disk: standard BIOS entry point
; C contains a disk to select for subsequent disk operations.
; FIXME: this routine does stuff that the docs don't hint at.
;        if bit 7 of disk specifier is 1, then certain side
;        effects take place.  what's this about?
;
; Quoting the CP/M docs:
;   Select the disc drive in register C (0=A:, 1=B: ...).
;   Entered with DE=0 or FFFFh.  If DE=0, the disc will be logged in;
;   if it is FFFFh, no attempt will be made to read it.
;
;   SELDSK returns the address of a Disc Parameter Header in HL.
;
; It would appear that this BIOS ignores the entry value of DE
; and instead uses the MSB of C to implement this behavior.
; Other BIOSs seem to just look at the LSB of E instead, but
; many don't check DE at all.
SELDSK:
	LXI	D,SELERR
	PUSH	D		; push error handler address
	MOV	A,C		; C=selected disk.  0->A, 1->B, 2->C, 3->D
	ANI	7FH		; ignore bit 7 for now

	LXI	H,NUMDSK
	CMP	M		; is request for a nonexistent disk?
	RNC			; error -- really jumps to selerr

	STA	SEKDSK		; disk to use: 0 to (NUMDSK-1)
	MOV	A,C		; orig disk num was either 0-3, or 128-131
	ORA	A		; set flags
	CM	FORCECHK	; if bit 7 is set, force disk format check
	CALL	CHKFMT		; determine disk format
	RNZ			; jump to error routine
	POP	D		; forget about error handler

GETDPH:	; return with HL pointing at DPBASE for SEKDSK
	LDA	SEKDSK
	MOV	L,A
	MVI	H,00H		; hl=SEKDSK
	DAD	H		; hl*2
	DAD	H		; hl*4
	DAD	H		; hl*8
	DAD	H		; hl*16
	LXI	D,DPBASE
	DAD	D
	RET

; some type of error occured during SELDSK
SELERR	LXI	H,0000H		; HL=0000H indicates error to caller
	MOV	A,L
	STA	DEFDRV		; change default drive back to A:
	INR	A		; A=1, zflag=0.  why?
	RET			; we really return to caller of SELDSK


; move the current drive to track 0.
; standard BIOS entry point.
HOME:
	MVI	C,00H

; set track: standard BIOS entry point
SETTRK:
	MVI	H,00H
	MOV	L,C
	SHLD	SEKTRK
	RET


; set sector: standard BIOS entry point
SETSEC:
	MOV	A,C
	STA	SEKSEC
	RET


; set dma data address: standard BIOS entry point
SETDMA:
	MOV	H,B
	MOV	L,C
	SHLD	DMAADR
	RET


; sector translate: standard BIOS entry point
SECTRAN:
	XCHG		; HL = base of sector translation table
	MVI	B,00H	; BC = logical sector
	DAD	B
	MOV	L,M
	MVI	H,00H	; HL = physical sector
	RET


; console output: standard BIOS entry point
; Write the character in C to the screen.
CONOUT:
	PUSH	B
	CALL	CHKDRTY		; save cached writes
	POP	B
	JMP	CONOUT2


; read sector: standard BIOS entry point
READ:
	CALL	CHKDRTY		; save cached writes
	RNZ			; return on failure
	CALL	ALLOC
	STA	READOP		; A=1 at this point
	JMP	RWOPER


; write sector: standard BIOS entry point
;
; with CP/M 2.0, sector blocking is a BIOS function.  that is,
; CP/M sectors are 128B, while the N.S. sector size is 512B.
; when we do a write of an arbitrary 128B sector, we have to
; worry about merging it in with the other (512-128) bytes of
; native sector data.  This may require a preread of the 512B
; sector before the write can happen.
;
; check out section 12 and Appendix G of the CP/M 2.2 Alteration Guide.
;
; on entry, C has this info:
;    0 = normal sector write
;    1 = write to directory sector
;    2 = write to the first sector of a new data block
;
; in case 2, we don't need to preread the physical sector since
; it is invalid anyway.  in case 0 we want to do deblocking magic.
; in case 1, we don't want to use deblocking because of the danger
; of really messing up the directory structure in case of a
; subsequent error.

; BDOS constants on entry to WRITE:
WRALL	EQU	0	; write to allocated sector
WRDIR	EQU	1	; write to directory sector
WRUAL	EQU	2	; write to unallocated

WRITE:
	XRA	A
	STA	READOP		; 0 means write
	MOV	A,C
	STA	WRTYPE
	CALL	WRMAP		; part of deblocking logic
	JMP	RWOPER		; finish it off

WRMAP	ORA	A		; A is wrtype
	JZ	WRNORM		; jump if normal sector write
	CPI	WRUAL		; check to see if unallocated write
; the following is self-modified code.
;	MVI	A,10H		; for example
	DB	3EH		; MVI A,
WRMAPN:	DB	10H		; ... 10H  -- # of 128B sectors/group
	JZ	NEWBLK		; jump if first sector of a new block of data
	XRA	A		; 0 for dir write triggers immediate write
NEWBLK	STA	UNACNT		; $00 if dir write, $10 otherwise
	LXI	H,SEKREC
	LXI	D,UNAREC
	CALL	BLKMOV4		; copy SEKREC to UNAREC

	; see if HSTBUF contains logical sector we are writing to
WRNORM	LXI	H,UNACNT
	DCR	M
	JM	ALLOC		; we have exhaused the preread buffer
	LXI	D,SEKREC
	LXI	H,UNAREC
	CALL	CMPDSKREC	; compare SEKREC vs UNAREC
	JNZ	ALLOC		; disk # or track don't match
	LDAX	D
	CMP	M
	JNZ	ALLOC		; sector doesn't match

; at this point, we are writing to a logical sector where we are
; either appending to the physical sector or else writing where
; the physical sector was preread.
	LHLD	PSECTRN		; get sector translation table
	LDAX	D		; get sector we are targeting
STSCAN	CMP	M		; scan the translation table
	INX	H		; ... until we find a match
	JNZ	STSCAN		; ... (we must eventually)
	MOV	A,M		; read one past current
	CPI	01H		; $01 is first entry in table, and end sentinal
	JNZ	MIDTRK
	LHLD	UNATRK		; end of track: inc to next track
	INX	H
	SHLD	UNATRK
MIDTRK	STA	UNASEC		; mapped to physical 128B sector
	XRA	A
	STA	RSFLAG		; don't need preread
	RET


; mark HSTBUF as empty, basically.  this will cause subsequent
; accesses to preread the HSTBUF before proceeding.
ALLOC:
	XRA	A
	STA	UNACNT		; no 128B sectors to accumulate
	INR	A
	STA	RSFLAG		; we need to preread after this
	RET			; returns to "write:" caller


; common read/write operation, used by READ and WRITE routines.
; exit:
;   Z-flag: 1=success, 0=failure
RWOPER:
	LXI	H,HSTACT	; host active flag
	MOV	A,M
	MVI	M,1		; always becomes 1
	ORA	A		; was it already?
	JZ	FILHST		; fill HSTBUF if not

	; compare the sector
	LXI	H,HSTREC
	LXI	D,SEKREC
	CALL	CMPDSKREC	; compare HSTREC vs SEKREC dsk/trk info
	JNZ	NOTSAME		; mismatch
	LDAX	D		; SEKSEC sector
	DCR	A
	JZ	NOTSAME		; jump if sector is 1
	LDAX	D		; get sector again (INR A would be faster)
	CALL	CPM2NS		; map to 512B sectors
	MOV	C,A		; C=512B sector #
	MOV	A,M		; get HSTREC sector
	CALL	CPM2NS		; map to 512B sectors
	CMP	C
	JZ	MATCH		; they match

	; SEKREC is different than HSTREC.  save HSTBUF if dirty.
NOTSAME	LDA	DIRTY
	ORA	A
	CNZ	WRSEK2		; save contents of HSTBUF if dirty
	RNZ			; return on failure

	; copy SECREC to SEC2REC and preread HSTBUF if required
FILHST	XRA	A
	STA	DIRTY		; no pending HSTBUF writes
	LXI	H,SEKREC
	LXI	D,HSTREC	; only place this is written
	CALL	BLKMOV4		; copy SEKREC to HSTREC
	LDA	RSFLAG		; see if preread is required
	ORA	A
	CNZ	RDSEK2		; yes, read
	RNZ			; return on failure

MATCH	LDA	SEKSEC
	DCR	A		; CP/M numbers logical sectors from 1
	ANI	03H		; there are four sub-sectors
	MOV	L,A
	MVI	H,0		; HL = which 128B sub-sector of 512B
	DAD	H
	DAD	H
	DAD	H
	DAD	H
	DAD	H
	DAD	H
	DAD	H		; HL = A*128
	XCHG			; DE = A*128
	LHLD	PHSTBUF		; pointer to host disk buffer
	DAD	D
	XCHG			; DE = HSTBUF + 128*(sub-sector #)
	LHLD	DMAADR		; HL = logical sector buffer (128B)
	LDA	READOP
	ORA	A
	JNZ	MATCH5
	MVI	A,1
	STA	DIRTY		; writing, so HSTBUF will be dirty
	XCHG			; nullify next instruction -- cheap skip
MATCH5	XCHG
	CALL	BLKMOV128	; RD: DMAADR<-HSTBUF, WR: HSTBUF<-DMAADR
	LDA	READOP
	DCR	A
	RZ			; done if we are reading
	LDA	WRTYPE
	CPI	WRDIR
	JZ	CHKDRTY		; writing to DIR can't be deferred
	XRA	A		; return with Z-flag set
	RET


; write HSTBUF if it has data waiting to be written to disk
; return Z-flag: 1 on success, 0 on failure
CHKDRTY:
	LDA	DIRTY
	ORA	A
	RZ			; return if no pending writes
	CALL	WIPEHST
	JMP	WRSEK2

WIPEHST:
	XRA	A
	STA	HSTACT		; HSTBUF is inactive
	STA	UNACNT		; clear unalloc count
	STA	DIRTY
	RET


INITTBL:
	; initialize track table.  indicates which track each disk is on.
	; $59 indicates no known track.
	LXI	H,5959H
	SHLD	NSTRK+0
	SHLD	NSTRK+2

	; init small table of disk format bytes.
	LXI	H,0000H
	SHLD	DSKFMT+0
	SHLD	DSKFMT+2

	CALL	WIPEHST
	MVI	C,0
	JMP	SELDSK


; bit 4 of the disk format byte is normally always set to '1', according to
; N* conventions.  this code uses this bit as a flag to indicate if we've
; determined the disk format yet.  by forcing it to 0 here, we cause CHKFMT
; below to read the format byte off the disk.
FORCECHK:
	CALL	GETCURFMT
	ANI	0EFH		; clear bit 4
	MOV	M,A		; update DSKFMT table entry
	RET

; if the currently selected disk has a valid format byte, just return.
; bit 4 in an entry in the format table is used to flag validity or not.
; if it is invalid,
;    1) flush any pending writes (which would be from a different drive)
;    2) read the track 0, sector 0 of the disk
;    3) validate its format byte at offset $5C
;    4) store the format in the DSKFMT table
;    5) scan the DSKFMTTBL table for a matching format byte
;    6) copy the DBP/DBH/SKEW data for this format to the
;       appropriate data structures
;
; returns with Z-flag set if all is OK
CHKFMT:
	CALL	GETCURFMT
	ANI	10H		; test bit 4
	XRI	10H		; invert bit 4
	RZ			; return if bit 4 was originally 1
	; bit 4 of format byte was 0 -- invalid format
	CALL	CHKDRTY		; flush any outstanding write
	RNZ			; return on failure
	LDA	SEKDSK
	MOV	C,A
	CALL	VDISK
	INR	C		; cp/m numbers disks from 0, while we start from 1
	MVI	B,0		; track 0
	MVI	E,10		; number of retries

RETRY	DCR	E
	RM			; no more retries
	PUSH	D
	MOV	A,C		; \
	XRI	NSDBLD		;  >-- flip between single and double density
	MOV	C,A		; /
	PUSH	B

	LHLD	PHSTBUF		; pointer to host disk buffer
	LXI	D,0001H		; read (E=1) starting at sector 0 (D=0)
	MVI	A,1
	STA	NUMSEC		; read one sector
	CALL	DOBURST		; read track B, C=partial NSORD byte

	POP	B
	POP	D
	JNZ	RETRY

	CALL	GETBFMT		; C=disk format byte
	MOV	A,C
	ORI	10H		; bit 4 is always set
	MOV	C,A		; C contains encoded disk format

	; scan the DSKFMTTBL table for an entry that matches C
	LXI	H,DSKFMTTBL-6	; dskfmttbl[-1]
	LXI	D,6
NXTDFMT	DAD	D		; point to next table entry
	MOV	A,M		; entry+0: disk format byte
	ORA	A
	JZ	BADFMT		; sentinal: end of table
	CMP	C		; look for match
	JNZ	NXTDFMT		; try next entry in table

	; get # of logical 128B sectors per physical sector for this format
	INX	H
	MOV	A,M
	STA	WRMAPN		; modify code
; FIXME: isn't this broken?  Say we have disk A (0) and disk B (1)
;        which are different formats.  disk A will come through this
;        code and set WRMAPN.  later disk B will modify WRMAPN.  the
;        next access to disk A will check the head of this routine
;        and since the format byte is valid, it won't come this way
;        and change WRMAPN back.  the other data structures are OK
;        because BDOS has a pointer for each area, while WRMAPN is
;        shared by all.
;
;        hmm, but isn't there even more broken stuff?  this routine
;        sets PSECTRN when the disk is logged in, but if the format
;        is already known, it doesn't get set again.
;
;        one possible fix: this is called once per SELDSK, which
;        isn't all that often.  rather than doing a "RZ" early on
;        if the disk format is valid, just skip reading the sector
;        and proceed at the "scan the DSKFMTTBL table" section.
;        thus WRMAPN and PSECTRN will always be up to date for the
;        current disk.  while making this change, get rid of the
;        code modification that WRMAPN is doing and just save it
;        to a byte somewhere and read it on the other end.
;
;        it is moot if all disk drives have the same disk format,
;        (likely), but why pretend to support mixed formats if we
;        don't go all the way?

	; get approprite DPB (disk parameter block) pointer for this format
	INX	H
	MOV	E,M
	INX	H
	MOV	D,M
	PUSH	D

	; get appropriate sector skew table for this format
	INX	H
	MOV	E,M
	INX	H
	MOV	D,M
	XCHG
	PUSH	H
	SHLD	PSECTRN

	; save format of selected disk
	CALL	GETCURFMT
	MOV	M,C

	; save skewtable pointer to DPH
	CALL	GETDPH
	POP	D		; recall skewtable pointer
	CALL	SAVDE

	; save DPB (disk parameter block) pointer to DPH
	LXI	D,0009H
	DAD	D
	POP	D

SAVDE	MOV	M,E		; save DE to (HL)
	INX	H
	MOV	M,D
	XRA	A		; clear A and flags
	RET


; get boot sector format byte.  sanitity test it and
; return the format in reg C.
GETBFMT:
	MOV	A,C
	ANI	NSDBLD		; isolate single/double density flag
	MOV	C,A
	RZ			; single density, return 00H
	LHLD	PHSTBUF		; pointer to host disk buffer
	LXI	D,005CH		; byte at offset $5C of sector 0,
	DAD	D		; ... track 0, is format byte
	MOV	A,M
	ANI	10H		; should always be 1
	MVI	C,NSDBLD
	RZ			; bit 4 wasn't set -- claim DD, SS, fmt 1, 48tpi
	MOV	C,M		; report what format byte claims
	RET


; look up a byte in table DSKFMT, indexed by SEKDSK.
; value returned in A, with a pointer to the entry in HL.
GETCURFMT:
	LDA	SEKDSK

; look up a byte in table DSKFMT, indexed by A.
; value returned in A, with a pointer to the entry in HL.
; this fails if DSKFMT table straddles a 256B page.
GETFMT:
	LXI	H,DSKFMT
	ADD	L
	MOV	L,A
	MOV	A,M
	RET


; disk format table; 6B per entry.
;
; the first byte is compared to the "format byte" of the disk,
; which is at location $5C of the sector 0, track 0 sector.  This
; is a convention used by Lifeboat CP/M and NorthStar.  Here
; quoted from some N* docs:
;
; Here is the structure of the format byte as in these implementations:
;
;    bit	80H	;0 = single density, 1 = double density
;    bit	40H	;0 = single sided,   1 = double sided
;    bit	20H	;0 = format 1,	     1 = format 2
;    bit	10H	;always set to 1
;    bit	 8H	;not assigned
;    bit	 4H	;not assigned
;    bit	 2H	;0 = 48 track/in.,   1 = 96 track/in.
;    bit	 1H	;always set to 0 (see below)
; ...
; Thus, the format bytes used in either or both the Lifeboat and North
; Star BIOS's are as follows:
;
;     10H	single density, single sided, 48 tpi
;
;     90H	double density,	single sided, 48 tpi (format 1)
;     B0H	double density,	single sided, 48 tpi (format 2)
;
;     F0H	double density, double sided, 48 tpi (format 2) QUAD
;     F2H	double density, double sided, 96 tpi (format 2) OCTAL
;
; In addition to these, there are two others possible:
;
;     D0H	double density, double sided, 48 tpi (format 1) QUAD
;     D2H	double density, double sided, 96 tpi (format 1) OCTAL
;
; The actual format for format 1 and format 2 will depend on the par-
; ameters contained in the Disk Parameter Block for each format byte
; and the use of format 1 and format 2 here is not meant to imply that
; they have the same meaning when applied to the different actual formats.

DSKFMTTBL:
	DB	0F0H		; double density, double sided, format 2
	DB	10H		; (allocation block size)/128B = 4KB/128
	DW	DPB0		; B460
	DW	SKEWDD		; BD49

	DB	10H		; single density, single sided, format 1
	DB	08H		; (allocation block size)/128B = 2KB/128
	DW	DPB1		; B46F
	DW	SKEWSD		; BD35

	DB	90H		; double density, single sided, format 1
	DB	08H		; (allocation block size)/128B = 2KB/128
	DW	DPB2		; B47E
	DW	SKEWDD

	DB	0B0H		; double density, single sided, format 2
	DB	10H		; (allocation block size)/128B = 4KB/128
	DW	DPB3		; B48D
	DW	SKEWDD		; BD49

	DB	00H		; sentinal ends table


; transfer 512B of data to/from the HSTBUF and the physical sector
; corresponding to the logical sector described by HSTREC.
; entry:
;    SECDSK2/SECTRK2/HSTSEC structure
;    C contains disk number (0=A, 1=B, 2=C, 3=D)
; exit:
;    Z flag: 1 if success, 0 otherwise

WRSEK2:
	XRA	A		; set flag to 0  (write)
	JMP	SEK2OP

RDSEK2:
	MVI	A,1		; set flag to 1  (read)

SEK2OP	PUSH	PSW		; save r/w flag
	LDA	HSTDSK
	MOV	C,A
	CALL	VDISK
	INR	C		; cp/m numbers disks from 0, while we start from 1
	POP	PSW		; recall r/w flag
	MOV	E,A		; E=0 means write, E=1 means read
	CALL	LOG2OP		; set up logical DSK/TRK/SEC2 to physical
	JMP	BLKOP		; perform operation on selected sector(s)


; take the logical CP/M sector described by the HSTDSK/HSTTRK/HSTSEC
; structure, map it to a physical 512 byte sector, and finally set up
; the registers that BLKOP is expecting.  this routine always assumes
; 512B physical sectors.  if the disk is actually single density, it
; twiddles the sector number and operates on two 256B sectors at once.
;
; entry:
;    HSTDSK/HSTTRK/HSTSEC structure set as desired
;    C=disk drive 0=A, 1=B, ...
; exit:
;    A=1 (double density) or 2 (single density)
;    B=track
;    C=modified NSORD byte
;    D=physical sector number
;    E=unaffected
;   HL=points to HSTBUF
;
LOG2OP:
	LDA	HSTDSK		; disk
	CALL	GETFMT
	ANI	NSDBLD		; isolate double density bit
	ORA	C
	MOV	C,A		; C now has density bit set
	LDA	HSTTRK
	MOV	B,A		; B=track
	LDA	HSTSEC		; sector-of-track
	CALL	CPM2NS		; 128B logical sector to phys sector
	MOV	D,A		; D=physical sector #
	LHLD	PHSTBUF		; pointer to host disk buffer
	MOV	A,C
	RLC			; double density bit into carry
	MVI	A,1
	RC			; return if DD; one sector is 512B
	MOV	A,D		; single density ...
	RLC			; ... so sectors are half the size
	MOV	D,A		; ... so double sector #
	MVI	A,2		; SD, so do two sectors for 512B
	RET


; this routine allows having a number of virtual disk drives.
; if the system has N physical disks, it simply returns immediately.
; if the system has only one drive, the user is prompted to manually
; swap the disks every time a different logical disk is specified.
; after making the user hit a key, it returns with the disk specifier
; pointing at drive 0.
;
; entry:
;    C species disk unit (0,1,2,3 for A,B,C,D)
; exit:
;   return with C as-is (0-3) if OPTFLG[7]=0, else return with C=0
;
VDISK:
	LDA	OPTFLG
	ANI	80H
	RZ			; might C be nonzero?
	LXI	H,PDRIVE	; points at disk drive name
	MOV	A,C
	ADI	'A'		; 0->"A", 1->"B", 2->"C", 3->"D"
	CMP	M
	JZ	DRVOK
	MOV	M,A		; change message to point to drive
	LXI	H,PROMPT
	CALL	PRMSG		; prompt user to change disks
	CALL	CONIN		; get any key from keyboard and swallow it
DRVOK	MVI	C,0
	RET

PROMPT:	DB	CR,LF,'Mount disk '
PDRIVE:	DB	'A'
	DB	', then <CR>',CR,LF,'$'


; doing "ld hl,(cordcmd) ; ld a,(hl)" causes NS disk "corder" command
; to be issued.
CURDRV:	DB	0		; (DS 1) current drive
CORDCMD:DB	0		; (DS 1) holds LSB of NSORD command we've built
	DB	NSORD SHR 8	; $B736: ld hl,(cordcmd) reads this too, but not set


; entry:
;     A=number of sectors to transfer
;     B=track to transfer
;     C=NSORD byte (bit 7=data density,6=disk side),
;       lsbs contain disk number (0=A, 1=B, 2=C, 3=D)
;     D=starting sector of transfer
;     E=some encoding of read/write
;    HL=memory address to read to/write from
; exit:
;    Z-flag: 1 if success, 0 otherwise

BLKOP:
	STA	NUMSEC
	MVI	A,10		; number of retries

; this entry point is as above, except that NUMSEC must already
; be set, and A contains the retry count.
DOBURST:
	DI			; interrupts must be disabled during reads
	PUSH	PSW
	PUSH	H
	PUSH	D
	PUSH	B
	PUSH	H		; 2nd time for HL

	; see if the track we're reading is on side 1 or 2 of the disk
	LXI	H,TRACKS
	MOV	A,M
	DCR	A		; A is max track number
	SUB	B
	JNC	SIDEONE

	; the track specified is larger than the # of tracks per side
	ADD	M
	MOV	B,A		; B=2*(tracks)-1-B
	MOV	A,C		; flip from bottom to top of disk
	ORI	NSTOP		; change to top (second) side
	MOV	C,A

SIDEONE	POP	H
	LDA	NUMSEC
	CALL	RDWRBLK		; transfer A sectors, track B, sector D, mem HL
	POP	B
	POP	D
	POP	H
	PUSH	PSW		; save results of RDWRBLK
	LDA	OPTFLG
	ANI	10H		; bit 4: test interrupt reenable bit
	JZ	CHKSTAT
	EI			; safe to take interrupts again
CHKSTAT	POP	PSW		; recall RDWRBLK status
	JZ	RWBLKOK		; zero means RDWRBLK succeeded
	POP	PSW		; recall retry counter
	DCR	A
	JNZ	DOBURST

BADFMT:
NOZFLAG:
	MVI	A,1
	ORA	A		; make sure z flag isn't set
	RET

RWBLKOK	POP	PSW		; clear retry counter
	MOV	A,E		; inspect read/write command
	XRI	01H
	RZ			; done if we were reading

	; read-after-write verification operation
	LDA	OPTFLG
	ANI	40H		; bit 6
	RZ
	LDA	NUMSEC
	MVI	E,1		; read back in what we just wrote
	JMP	BLKOP


; this routine performs either a read or write operation
; on a number of sectors for a given track.  the track and
; sector information is all in physical sectors.
;
; entry:
;   A -- number of sectors to operate on
;   B -- physical track number
;   C -- disk "order" byte
;   D -- sector # to begin reading or writing
;   E -- read or write command (format TBD)
;  HL -- address to read from/write to
;
; exit:
;  success: A=0, zflag=true
;  failure: A=1, zflag=false, ERFLAG indicates reason
;	ERFLAG=2 : bad checksum
;	ERFLAG=4 : didn't see the index hole
;	ERFLAG=5 : incorrect density
;	ERFLAG=6 : disk is write protected
;	ERFLAG=7 : accessing 2nd side of single sided disk
;  ... what happened to errors 1 and 3?
;
RDWRBLK:
	PUSH	PSW
	PUSH	H

	MOV	A,C		; get partial NSORD command
	ANI	(NSDBLD OR NSTOP)
	MOV	H,A

	; if we are operating on a track after track 20,
	; write precompensation must be turned on when we write data.
	MVI	A,20
	CMP	B		; 20-B.  compare to desired track
	RAR			; \
	RAR			;  >-- these could be replaced by "SBB A"
	RAR			; /
	ANI	NSPRE		; isolate carry bit from "CMP B"
	ORA	H		; OR in DP bit (write precompensation)
	MOV	H,A		; bits 7,6,5 are meaningful

	MOV	A,C		; get partial NSORD command
	ANI	3FH		; clear out density and side flags
	MOV	C,A
; FIXME:
; hmm, we AND with $3F, but this potentially leaves some bits
; set (ie, 3,4,5) that might trip us up later.

	; map ordinary disk drive select binary number 1,2,3,4 to
	; values 1,2,4,8 (1<<(drv-1)).
	CPI	3
	JC	DLT3		; 1->1, 2->2
	RAL			; 3->6, 4->8
	ANI	0CH		;  ->4,  ->8

DLT3	ORA	H		; merge back into partial NSORD command
	STA	CORDCMD		; NSORD command: DD,SS,DP,DS are set
				; NOTE: only place this is set

	; test bit (8-drivenumber) of (DBLSIDE)
	; GUESS: map of which drives are double sided
	MOV	A,C
	ANI	07H		; isolate drive (in simple binary 1,2,3,4)
	MOV	L,A
	LDA	DBLSIDE		; [ $FF at capture ]
SHMSB	DCR	L
	RLC			; rotate into, but not through, carry
	JNZ	SHMSB		; A=(DBLSIDE) << L  (L=1,2,3,4)
	JC	TWOSIDE

	; disk is singled sided.  make sure we're not accessing 2nd side.
	LDA	CORDCMD		; get NSORD command
	ANI	NSTOP		; are we addressing the top of the disk?
	MVI	A,7		; error code, in case we need it
	JNZ	SAVERR2		; error if we're on 2nd side (top)

TWOSIDE	POP	H
	PUSH	H
	PUSH	D
	PUSH	B
	CALL	STRTDRV		; make sure drive selected by C is ready
	POP	B

	MOV	A,E		; recall read/write command
	DCR	A
	ANI	02H		; write protect bit
	LXI	H,NSSTATB	; B-status
	ANA	M		; check write protect status
	MVI	A,6		; error code
	JNZ	SAVERR		; branch if disk is write protected

	PUSH	B		; save B, the track we seek
	LXI	H,NSTRK-1
	MVI	B,00H		; bc=drive # in simple binary (1,2,3,4)
	DAD	B
	MOV	A,M		; figure out which track this disk is on
	XRI	59H		; have we operated on disk yet?
	PUSH	H
	CZ	SEEK		; no, seek track 0
	POP	H
	POP	PSW		; corresponds to PUSH B, so that B ends up in A
	CALL	SEEK		; find track specified by A
	LHLD	CORDCMD		; this sequence issues ...
	MOV	A,M		; ... the NSORD command in cordcmd

	MOV	A,L
	ANI	NSDBLD		; isolate bit 7
	XRI	NSDBLD		; flip it
	MOV	C,A		; C is 00H/80H if we want dbl/sng density
	XRI	NSDBLD		; flip it back
	RAR
	RAR
	RAR			; bit 7 moves to bit 4
	ADI	0FH		; either 0F (SD) or 1F (DD)
	MOV	B,A		; this gets used when writing (see WRSEC:)

	POP	D
	POP	H
	POP	PSW		; stack is clean now

	; precompensate for loop counter logic coming up next
	; why not "CPI 1/RZ" instead of the following mess?
	INR	A
	PUSH	PSW
	DCR	D
	PUSH	D
	PUSH	B

NXTSEC:
	POP	B		; recall C.  we don't care about B.
	POP	D		; recall D (sec #) and E (read/write).
	INR	D		; sector # to read
	POP	PSW
	DCR	A		; count of # of sectors to read
	RZ			; we're done, with no errors

	PUSH	PSW
	PUSH	D
	PUSH	B

	; wait for sector "D" to show up
W8SEC	PUSH	D
	CALL	WAIT1S		; wait for next sector
	POP	D
	LDA	NSSTATC+NSCCMOTR ; kick motors and get sector number
	ANI	NSSC		; strip non-sector bits
	CMP	D
	JNZ	W8SEC

	; at this point we don't care if it is a read or a write.
	; here's the distinction.
	DCR	E
	JM	WRSEC		; write one sector

	; OK, we are going to read a sector.
	MVI	B,140		; # times to wait for BODY flag
	LXI	D,NSREAD	; set up read data regs
	CALL	CKDENSE		; check for proper density (C, bit 7)

; wait for RE so we can do sector read, and test
; the double density bit.
W8BODY	LDA	NSSTATA		; get A-status
	RRC			; bit 0 into carry
	JC	RDBODY		; jump if sector body being read
	DCR	B
	JNZ	W8BODY
	MVI	A,01H		; error code: didn't find sector body
	; ... fall through

; clean up stack a bit and save error number
SAVERR:	POP	H
SAVERR2:POP	H
	POP	B
	STA	ERFLAG		; log reason for error
	JMP	NOZFLAG

	; transfer 2*C bytes from the disk to (HL), verifying the
	; sector checksum as we go.  we do 2*C bytes at a time to
	; allow having an 8b loop counter for 512 bytes transferred.
	;
	; note that C was set a while back with 80H if the read is
	; single density and 00H if the read is double density.
	; this results in us looping 128 times to get 256B, or 256
	; times to get 512 bytes, based on the track density.

RDBODY	MVI	B,00H		; initialize the sector data checksum
RNXTBYT	LDAX	D		; get data byte from disk
	MOV	M,A		; save it to buffer
	XRA	B		; checksum
	RLC			; ... the
	MOV	B,A		; ... byte
	INX	H

	STC			; why?  killing time?  "xor b" clears this

	LDAX	D		; get data byte from disk
	MOV	M,A		; save it to buffer
	XRA	B		; checksum
	RLC     		; ... the
	MOV	B,A		; ... byte
	INX	H

	DCR	C
	JNZ	RNXTBYT		; read next byte

	LDAX	D		; read checksum from disk
	XRA	B		; compare to what we computed
	JZ	NXTSEC		; jump if OK
	MVI	A,2		; error code: bad checksum
	JMP	SAVERR


; wait until we start scanning data.  then check if the data density
; (single or double) is what we expect.  this is expressed by setting
; C to express the desired density:
;    $00 for double density, $80 for single density
; exit:
;   success: A=05H and zflag clear
CKDENSE:
	LDA	NSSTATA		; get A-status
	ANI	NSRE		; status valid flag (phase lock locked in)
	JZ	CKDENSE		; invalid status; wait for it
	XTHL			; kill
	XTHL			; ...
	XTHL			; ...
	XTHL			; ...
	XTHL			; ...
	XTHL			; ...
	XTHL			; ...
	XTHL			; ... time
	LDA	NSSTATA		; get A-status
	RAL
	RAL			; bit 5 moves to bit 7
	XRA	C		; compare to disk density we expect
	MVI	A,5		; set error code in case we need it
	RM			; return if OK
	POP	B		; toss out return address
	JMP	SAVERR		; incorrect density


; seek to track specified by A.
; entry:
;    A is track to seek
;   HL is pointer to corresponding NSTRK entry
; exit:
;    A, C, D, HL are trash
SEEK:
	MOV	D,A		; save the target track #
	SUB	M		; see how far away we are from target
	MOV	M,D		; but always set new track
	RZ			; if there, done
	LXI	H,NSORD+NSIN	; assume stepping in
	MOV	C,A		; save step count
	JP	STEPIT		; branch if right
	CMA			; wrong, negate count
	INR	A
	MOV	C,A		; then save that
	LDA	NSSTATB		; get B-status
	ANI	NST0		; are we on track zero?
	RNZ			; must be done if so
	MVI	L,NSOUT		; if not, stepping out

STEPIT	CALL	QTRSEC		; wait for 1/4 sector rotation

	; map drive number 1,2,3,4 into bit mask expected by controller
STPMOR	LDA	CURDRV
	CPI	03H
	JC	DRVLT3		; 1->1, 2->2,
	RAL			; 3->6, 4->8
	ANI	0CH		;  ->4,  ->8
DRVLT3	ORA	L		; merge in drive selector
	MOV	L,A
	MOV	D,M		; issue command

	; set disk head STEP control bit
	ORI	NSSTEP
	MOV	L,A
	MOV	D,M		; issue command

	; reset disk head STEP control bit
	XRI	NSSTEP
	MOV	L,A
	MOV	D,M		; issue command

	CALL	QTRSEC		; wait for 1/4 sector rotation, about 0.4ms

	; for some drives, we need to give extra time between each
	; track step operation.  DSKDLY is a map of fast drives.
	LDA	DSKDLY
	ANA	L		; disk 1,2,3,4 is bit 0,1,2,3
; this is silly: this uses up 2 bytes masking when it would cost only
; one byte to have DSKDLY broken out as a separate byte in storage.
	ANI	0FH
	MVI	D,2
	CZ	SCWAIT		; wait for 2 sectors to pass for slow drives

	CALL	NOPHOOK		; do nothing hook
	LDA	NSSTATB+NSCCMOTR; get B-status and kick motors
	ANI	NST0		; are we at track zero?
	JNZ	WAIT1S		; done stepping if so
	DCR	C		; ... else count of last track
	JNZ	STPMOR		; go back if more to do
	; ... fall through and wait one more sector time
	; ... to make sure it is safe for I/O

; sector wait.
; entry:
;    D contains the # of sectors to wait.
; exit:
;    D = 0
;    A = "A-status"
; call wait1s to wait one sector time.

WAIT1S:
	MVI	D,1
SCWAIT:
	CALL	NOPHOOK		; do nothing hook
	LDA	NSSTATA+NSCCRSF	; reset sector flag
SCW5	LDA	NSSTATA		; get A-status
	ORA	A		; check sector flag
	JP	SCW5		; wait for sector flag (bit 7)
	DCR	D		; count down wait counter
	LDA	NSSTATA+NSCCRSF	; reset sector flag again
	RZ
	JMP	SCWAIT


; select disk drive indicated by register C.
; if the disk drive motors are not on, fire them up.
; if the currently selected disk is not the same as what C wants,
; switch to the drive selected by C.
; entry:
;    C contains the drive to select
; exit:
;    A,D,E trashed
STRTDRV:
	CALL	WAIT1S		; wait for sector hole
	ANI	NSMO		; test if motors are on
	LDA	NSSTATA+NSCCMOTR; get A-status, kick motors
	JNZ	MOTRON		; jp if motors are running

	; the disk drive motors are not running yet.
	; we just touched the motor enable bit, but we must let
	; disk come up to speed.
	MVI	D,48		; 48 sectors
	LDA	CORDCMD
	ORA	A
	JP	SPINUP		; jump if single density
	MVI	D,23		; 23 sectors
SPINUP	CALL	SCWAIT		; let 23 or 48 sectors go by
	JMP	NEWDRV

	; see if the current drive is the one we want
MOTRON	LDA	CURDRV
	CMP	C
	RZ			; yes, done

	; we need to make a different drive the active drive
NEWDRV	MOV	A,C
	STA	CURDRV
	MVI	D,NSORD SHR 8
	LDA	CORDCMD
	MOV	E,A
	LDAX	D		; issue the NSORD to change the drive

	; make sure we are up to speed
	MVI	D,2
	CALL	SCWAIT		; let 2 sectors go by

	; as each sector goes by, wait until we see one that contains
	; the index mark.  although the disk has only 10 512B sectors,
	; we test 12 just in case something odd happens.
	MVI	B,12		; check for up to 12 sectors
INDWAIT	CALL	WAIT1S		; wait for sector hole
	LDA	NSSTATA		; get A-status
	ANI	NSIX		; index hole seen?
	RNZ			; return if yes
	DCR	B
	JNZ	INDWAIT		; check next sector

	; didn't see the index hole
	MVI	A,4		; error code
	POP	B		; clean up the stack  (return address)
	POP	B		; (bc; still have de/hl/af on stack)
	JMP	SAVERR


; write a sector; assumes sector is already under head.
; entry:
;   HL points to the data source.
;   C contains (sector_length_in_bytes/2).
WRSEC:
	LDA	NSSTATA+NSCCWRT	; initiate sector write

W84WI	LDA	NSSTATA+NSCCMOTR; keep motors running, get A-stat
	ANI	NSWI		; must loop until 96 usec window
	JNZ	W84WI		; passed, so loop while true

; now write the 31 or 15 bytes of leading zeros on the sector
WRZROS	LDA	NSWRT+00H	; write a $00 byte
	MOV	A,A		; kill time
	MVI	D,NSWRT SHR 8	; kill time, but used later
	DCR	B
	JNZ	WRZROS		; write $00 B times

; follow with one or two sync bytes
	LDA	NSWRT+0FBH	; write $FB
	LDA	CORDCMD
	RLC			; bits 7=1 means double density
	JNC	ONESYNC
	LDA	NSWRT+0FBH	; write $FB a second time for DD
ONESYNC	MOV	C,C		; kill time
	ORA	A		; kill time

; write out 256 or 512 bytes.  do this two at a time so
; we can use a single byte loop counter.
WRLOOP	MOV	A,M		; get next byte to output
	MOV	E,A		; DE= {$E9,xx}, where xx is byte being written
	XRA	B		; add into checksum into B
	RLC
	MOV	B,A
	LDAX	D		; write data byte
	INX	H

	MOV	A,M		; get 2nd byte of this loop
	MOV	E,A		; DE= {$E9,yy}, yy is byte being written
	XRA	B		; add into checksum into B
	RLC
	MOV	B,A
	LDAX	D		; write data byte
	INX	H

	DCR	C		; loop counter
	JNZ	WRLOOP

	MOV	E,B
	INX	B
	LDAX	D
	JMP	NXTSEC


; calibrate disk speed vs CPU speed -- find out how long it takes between
; sector holes, quantized to a timer loop of 3164 cycles (1.582ms @ 2MHz).
; note that the per-sector timing is nominally 1/(300 RPM*10), which is
; about 20 ms.  the exact rotational speed doesn't matter as this routine
; and the next only care about relative timing.
;
CALBR8:
	CALL	WAIT1S		; find a sector hole
	MVI	D,0
TIMER1	INR	D
	MVI	A,226		; 226*14=3164 cycles, 1.582ms @ 2MHz
TIMER2	DCR	A		;  4 cycles
	JNZ	TIMER2		; 10 cycles
	LDA	NSSTATA		; get A-status
	ORA	A
	JP	TIMER1		; no sector hole
	MOV	A,D
	STA	DSKSPD		; save how many loops per sector
	RET


; delay a quarter of the time it takes for the disk to rotate
; between index holes.
; (21+56*14) cycles, or 805 cycles, per (DSKSPD), which is 0.4ms at 2MHz.
; note that the loop count is 1/4 what it is above (56/226 = 0.247).
; thus, for a given count, this is 1/4 whatever it is above.
; due to quantization, though, it is only roughly accurate.
; entry: none
;  exit: A, D are 00H
;
QTRSEC:
	LDA	DSKSPD
DLY1	MVI	D,56		;  7 cycles
DLY2	DCR	D		;  4 cycles \__ 14*56
	JNZ	DLY2		; 10 cycles /
	DCR	A		;  4 cycles
	JNZ	DLY1		; 10 cycles
	RET


; compare one dsk/SEKTRK/SEKSEC struct against another, partially.
; the two structs are pointed at by DE and HL.  We return with the
; zero flag set if the first two bytes match, and with is cleared
; if there is a mismatch in the first two bytes.  if there is a match,
; HL and DE are left pointing at the fourth byte of the struct so the
; caller can continue the comparison as required.
CMPDSKREC:
	LDAX	D
	CMP	M		; compare disk drive numbers
	RNZ
	INX	H
	INX	D
	LDAX	D		; compare track LSBs.  if we had >256 tracks,
	CMP	M		; ... we'd need to check track MSBs too.
	INX	H
	INX	D
	INX	H
	INX	D		; leave pointing at sector-of-track bytes
	RET


; Double density NS disks have 512 bytes/sector, while CP/M expects 128.
; Map 128B CP/M sector-of-track to 512B D.D. NS sector-of-track.
; If the physical disk is actually S.D., this number must be doubled.
; entry:
;    A contains logical 128B sector number
;    (first sector number is 1)
; exit:
;    A contains physical sector number, assuming 512B sectors
;    (first sector number is 0)
;    no other registers are affected
CPM2NS:
	DCR	A		; CP/M starts counting sectors from 1
	ANI	0FCH		; round down
	RRC			; \__ divide by four
	RRC			; /
	RET


; move 4 bytes from (hl) to (de)
; A=0, B=0, zflag=1 on exit
BLKMOV4:
	MVI	B,04H
	JMP	BLKMOV

; move 128 bytes from (hl) to (de)
; A=0, B=0, zflag=1 on exit
BLKMOV128:
	MVI	B,80H

; move B bytes from (hl) to (de).  B=0 means 256 bytes.
; A=0, B=0, zflag=1 on exit
BLKMOV:
	MOV	A,M
	STAX	D
	INX	H
	INX	D
	DCR	B
	JNZ	BLKMOV
	XRA	A
	RET


; read a string from (hl) and echo it until we see a "$" character
PRMSG:
	MOV	A,M
	CPI	'$'
	RZ
	MOV	C,M
	INX	H
	PUSH	H
	CALL	CONOUT2
	POP	H
	JMP	PRMSG


; build the single density and double density sector translation tables
MAKSTT:
	; set up the single density sector translation table
	LXI	H,SKEWSD
	MVI	A,1		; first sector is 1
	MVI	C,20		; there are 20 sectors per track
	CALL	FILLSEQ

	; set up the double density sector translation table
	MVI	A,21
MAKSTT2	SUI	20
	CALL	FILLSEQ4
	ADI	16
	CALL	FILLSEQ4
	CPI	41		; there are 40 sectors per track
	JNZ	MAKSTT2

	; the table starts and ends with sector 1; used as sentinal
	MVI	M,01H
	RET

; fill four bytes of memory starting at (hl) with successive values
; starting with the value in A,
FILLSEQ4:
	MVI	C,4
	; ... fall through

; fill sequential memory with sequential values.
; fill memory starting at (hl) with successive values starting with the
; value in A, filling C bytes.  C=0 maps to 256 bytes.
FILLSEQ:
	MOV	M,A
	INX	H
	INR	A
	DCR	C
	JNZ	FILLSEQ
	RET


; ------------------------------------------------------------
; storage


	DB	0,0,0,0,0,0,0,0		; (DS 8) unused
B9E0	DB	00H,0C0H,02H,0C2H	; not sure what this is
; hmm, $C000 happens to be the boot ROM
;      $C202 is "jp getCmdStr" (command input)
;      not sure if this matters.
	DB	0,0,0,0,0,0,0		; (DS 7) unused
PHSTBUF	DW	HSTBUF			; pointer to host disk buffer (512 bytes)
	DB	0,0,0			; (DS 3) unused


; what is this here for?
NOPHOOK:
	RET
	DB	0,0,0		; (DS 3) unused

ERFLAG	DB	00H		; was $00 at capture

; the boot pgm stores the floppy ctrlr base address here.
; however, it isn't used because the code is hardwired for a given address.
FDCBASE	DB	0E8H		; $B9F5

TRACKS	DB	35		; number of tracks/side ($23 at time of capture)

	DB	43H		; $B9F7 unused?  $43 at time of capture

; disk info block
;   bit: 7 6 5 4  3 2 1 0
;  disk: A B C D  D C B A
; bits 4-7 indicate, with '1', if the disk is double sided.
; bits 0-3 indicate, with '0', if we should wait more between each track step.
DSKDLY	EQU 	$		; bits 0-3
DBLSIDE	DB	0FFH		; bits 4-7

NUMDSK	DB	04H		; number of disk drives in system

; as we mount disks, the disk format type for each drive is stored here.
DSKFMT	DB	0,0,0,0		; set to 0,0,0,0 on init

B9FE	DB	26H		; unused? $26 on capture

; strange collection of R/O bitfields.  perhaps this is stored as a "live"
; byte rather than as a compile option so that some hack command line
; utilties or other programs can twiddle the bits to change the options
; on the fly.
;   bit 7: single disk system flag
;          0->we really have n disks
;          1->only one physical drive, so every time the logical drive
;             changes, prompt the user to manually swap the disks
;   bit 6: verify writes (guess)
;          0 -> just assume writes went OK
;          1 -> read after write as a form of verification
;   bit 4: 0 -> leave interrupts disabled after a sector operation,
;          1 -> reenable interrupts (EI) after a sector operation
;   bit 1: on cold or warm boot,
;          0 -> clear input buffer & start CCP
;          1 -> start CCP with whatever is in input buffer
; all other bits are unused.
OPTFLG	DB	10H 		; R/O use by this code (address $B9FF)


; this is where BIOS is supposed to reside in a standard 48K CP/M system,
; but we have a fat bios.  for whatever reason, there is a vector table
; at the real bottom of BIOS, and another one here -- perhaps for
; compatibility with programs that just assume it is here.

BOOT2:	JMP	COLD		; cold boot
;WARM2:	JMP	WARM		; warm boot
WARM2:	JMP	WARM+3		; warm boot; skip screen clear
CONST:	JMP	CONSTAT		; console status
CONIN:	JMP	CNIN		; console input
CONOUT2:JMP	CNOUT		; console output
LIST:	JMP	LSTOUT		; list
PUNCH:	JMP	PNCHOUT		; tape punch
READER:	JMP	RDRIN		; tape reader
LISTST:	JMP	LSTSTAT		; FIXME -- this should be "home" figure it out


BA1B	DB	0F9H 		;	ld	sp,hl
BA1C	DB	01H

DEFIOB:	DB	10$01$01$00B	; default IOBYTE:LST:,PUN:,RDR:,CON:

BA1E	DB	00H
BA1F	DB	00H
BA20	DB	00H


; cold boot entry
COLD:
	MVI	A,00H
	OUT	STAPT		; clear status port flags

	; set iobyte from default iobyte
	LDA	DEFIOB
	STA	IOBYTE

	; SOLOS has user definable input and output devices (one each).
	; here we point them at a stub, which can be patched later.
	LXI	H,UIVEC
	SHLD	UIPRT
	LXI	H,UOVEC
	SHLD	UOPRT

	; initialize pollin table.  $80 means empty.
	LXI	H,8080H
	SHLD	POLLIN+0
	SHLD	POLLIN+2
	; fall through ...

; warm boot entry
WARM:
	CALL	PERSE		; erase the screen, home, BOT=0
	CALL	SAVCUR
	RET


; return printer status
LSTSTAT:
	MVI	A,00H		; \__ why not "xor a"?
	ORA	A		; /
	RET


; Returns its status in A; 0 if no character is ready, 0FFh if one is.
CONSTAT:
	LDA	IOBYTE		; bits [1:0]
	ANI	03H
	; fall through ...

IOSTAT:
	SHLD	SAVHL		; not sure why push/pop scheme wouldn't suffice
	MOV	H,B
	MOV	L,C
	SHLD	SAVBC

	; index pollin table by the io device number, 0-3.
	MOV	C,A
	MVI	B,00H
	LXI	H,POLLIN
	DAD	B
	SHLD	STATADR		; save address of indexed table entry

	; see if we've already polled and gotten input for this device
	MOV	A,M
	CPI	80H
	JNZ	IOSTDN

	; there is no preread, pending input for this device, so poll it
	MOV	A,C		; recover chosen i/o device
	CALL	AINP		; poll device
	MOV	M,A		; A contains the char we received
	JNZ	IOSTDN		; if AINP returned with nz, we got input

	; no input; use $80 as a marker for no valid input
	MVI	M,80H		; no input from AINP
	MVI	A,00H		; returning with $00 means no input
	JMP	RSTBCHL		; return with z flag set

IOSTDN:	; done
	MVI	A,0FFH		; returning with $FF means ready to read
	JMP	RSTBCHL		; return with z flag cleared


; the SOLOS UIPRT vector is set up to point here.
; the intent is that this could be patched with a "jmp xxxxH" later.
UIVEC:
	RET
	NOP
	NOP


; Wait until the keyboard is ready to provide a character, and return it in A.
CNIN:
	LDA	IOBYTE		; bits [1:0]
	JMP	W84CHR

; Read a character from the "paper tape reader" - or whatever the current
; auxiliary device is.  If the device isn't ready, wait until it is.
; The character will be returned in A. If this device isn't implemented,
; return character 26 (^Z).
RDRIN:
	LDA	IOBYTE
	RAR			; bits [3:2]
	RAR
	; fall through ...

W84CHR:
	ANI	03H		; silly 2nd time around
	STA	SAVA		; sign that a higher-level language was used.
	CALL	IOSTAT		; ... notice that a is saved/restored,
	LDA	SAVA		; ... yet it is a dead variable.
	JZ	W84CHR		; loop until we have a char
	SHLD	SAVHL		; why not push/pop?

	LHLD	STATADR
	MOV	A,M		; get input read earlier
	MVI	M,80H		; indicate no pending input

	LHLD	SAVHL		; isn't the return value ignored?
	ANI	7FH		; chop off "parity" bit
	RET


; the SOLOS UOPRT vector is set up to point here.
; the intent is that this could be patched later.
; the intent is that this could be patched with a "jp $xxxx" later.
UOVEC:
	RET
	NOP
	NOP


; send byte in register C to the device selected by IOBYTE
CNOUT:
	LDA	IOBYTE		; bits [1:0]
	JMP	OUTPUT

; Write the character in C to the printer. If the printer
; isn't ready, wait until it is.
LSTOUT:
	LDA	IOBYTE
	RLC			; bits [7:6]
	RLC
	JMP	OUTPUT

; Write the character in C to the "paper tape punch" - or
; whatever the current auxiliary device is.  If the device
; isn't ready, wait until it is.
PNCHOUT:
	LDA	IOBYTE
	RAR			; bits [5:4]
	RAR
	RAR
	RAR

; if the output device is the CRT, then certain escape code
; sequences are interpreted by this driver.
;    <ESC>G<COLUMN+' '><ROW+' '>  -- move cursor to (row,column)
;    <ESC>L  -- move cursor left one place
;    <ESC>R  -- move cursor right one place
;    <ESC>N  -- normal mode;    text is not inverted
;    <ESC>F  -- inverted  mode; text is inverted
;    <ESC>C  -- home cursor and clear screen
OUTPUT:
	SHLD	SAVHL
	MOV	H,B
	MOV	L,C
	SHLD	SAVBC
	MOV	B,C		; copy char in C to B
	ANI	03H		; io device field is 2b wide
	JNZ	DISPB

	; output device is console
	LDA	ESCSEQ		; see if we are doing an ESC sequence
	ORA	A
	JZ	NOESC		; jump if 0: not processing ESC sequence
	SUI	02H
	JM	ESC1		; jump if 1: we've seen an ESC so far
	JZ	ESC2		; jump if 2: we've seen ESC and next char
	; ... >=3
ESC2:
	LDA	ESCSTAT
	ORA	A
	JNZ	ESCGX
	JMP	CRTB		; uh, confused, just send it

ESC1:	; we've seen <ESC> so far, and we've just gotten another char
	MOV	A,C
	CPI	'G'
	JZ	ESCG		; goto screen (x,y)
	CPI	'L'
	JZ	ESCL		; move cursor left 1 char
	CPI	'R'
	JZ	ESCR		; move cursor right 1 char
	CPI	'N'
	JZ	ESCN		; normal mode text
	CPI	'F'
	JZ	ESCF		; inverse mode text
	CPI	'C'
	JZ	ESCC		; clear screen and home
	JMP	CRTB		; just process it as is


; we aren't in the middle of processing an escape sequence,
; although we might be starting one.  send C to CRT.
; (B has a copy of C already)
NOESC:
	MOV	A,C
	CPI	7FH		; DEL
	JZ	OUTDEL
	CPI	1BH		; ESC
	JNZ	PLAINCH
	MVI	A,01H
	STA	ESCSEQ		; we're starting an escape sequence
	JMP	OUTDONE

; sending to CRT.  not an escape sequence, not DEL nor ESC
PLAINCH:
	CPI	20H		; space
	JC	CRTB		; control chars don't get highlighting
	CALL	NOCURS		; turn off cursor highlighting
	LDA	INVTXT		; get normal/inverse text mode
	ORA	C		; merge in character to print
	XRI	80H		; flip norm/inv bit since the cursor is here
	MOV	B,A
	CALL	OCHAR		; send B
	JMP	MOVCUR		; move cursor

; send a delete to the CRT
OUTDEL:
	MVI	B,5FH		; unfortunately, SOL uses underscore
	; fall through ...

; send character in B to the CRT (override iobyte)
CRTB:
	MVI	A,00H		; output device is CRT (0)
	; fall through ...

; dispatch character in B to the iodevice specified by A
DISPB:
	CALL	AOUT
	; fall through ...

; clear escape state, and turn on highlighting at cursor
MOVCUR:
	CALL	CLRESC		; clear escape state
	CALL	SAVCUR
	MOV	A,M
	ORI	80H		; turn on cursor highlighting
	MOV	M,A
	; fall through ...

; return with printed char in A
OUTDONE:
	MOV	A,C
	; fall through ...

; restore bc and hl
RSTBCHL:
	LHLD	SAVBC
	MOV	B,H
	MOV	C,L
	LHLD	SAVHL
	RET


; save the cursor location in (curloc)
; return with HL pointing to the current byte on screen.
SAVCUR:
	CALL	VIDHL
	SHLD	CURLOC		; save cursor location
	RET


; turn off the cursor highlighting
NOCURS:
	LHLD	CURLOC
	MOV	A,M
	ANI	7FH		; turn off cursor bit
	MOV	M,A
	RET


; compute memory address of the current cursor position.
; entry:
;     no registrs, but NCHAR, LINE, and BOT are referenced
; exit:
;     HL = VDMEM location of cursor
;     other registers unaffected
;
; The SOLOS VDADD routine could have been used here, perhaps with a
; bit of massaging, but I guess it wasn't used for portability's sake.
;
; this is made slightly tricky by the SOL "window shade" logic.
; that is, there is a register that makes the display start from
; the N-th absolute row and then wraps around, saving a lot of cycles
; when the screen needs to be scrolled up (or down) a row.
VIDHL:
	PUSH	PSW
	PUSH	B
	PUSH	D
	LDA	NCHAR
	MOV	C,A		; C = cursor column
	LDA	LINE
	MOV	L,A		; L = cursor line
	LDA	BOT
	ADD	L		; line is relative to scroll display offset
; form L = L MOD 16
; not sure why they didn't just do "AND #0FH"
; this whole thing should be replaced with a modifed
; version of SOLOS's VDADD routine, which is about 4x faster.
SUB16	CPI	16		; 16 lines on the screen
	JC	MODDONE
	SUI	16
	JMP	SUB16
MODDONE	LXI	H,VDMEM-64	; start of display, backed up one row
	LXI	D,64		; 64 bytes per display line
VIDADR	DAD	D
	DCR	A
	JP	VIDADR
	MOV	E,C		; de=cursor column (d is already $00)
	DAD	D		; add horizontal offset
	POP	D
	POP	B
	POP	PSW
	RET

; <ESC> C seen so far in escape sequence
ESCC:
	MVI	B,0BH		; CLEAR
	XRA	A
	CALL	AOUT
	MVI	B,0EH		; HOME
	JMP	CRTB

; <ESC> G seen so far in escape sequence
ESCG:
	MVI	A,01H
	STA	ESCSTAT
	MVI	A,02H
	STA	ESCSEQ		; waiting for more
	JMP	OUTDONE

; <ESC> G <COLUMN+' '>               ... or ...
; <ESC> G <COLUMN+' '>  <ROW+' '>    seen so far
ESCGX:
	PUSH	PSW		; save (escstat)
	CALL	NOCURS		; turn off cursor highlighting
	POP	PSW
	CPI	02H		; we're comparing to ESCSTAT here
	JZ	ESCGY		; working on 4th byte
	INR	A		; escstat must have been 1.  now it's 2.
	STA	ESCSTAT		; bump so we process line next time
	MVI	A,03H
	STA	ESCSEQ		; we've seen 3 chars of esc sequence
	MOV	A,C		; third char of esc sequence
	SUI	20H		; 3rd byte has bias of 32
	STA	NCHAR		; move cursor to this column (mod 64)
	JMP	OUTDONE

; <ESC> G <COLUMN+' '>  <ROW+' '>    seen so far
ESCGY:
	MOV	A,C
	SUI	20H		; 4th byte has a bias of 32
	ADI	40H		; not sure why -$20+$40
	STA	LINE		; move cursor to this row (mod 16)
	CALL	CLRESC		; silly -- the next jump does this too
	JMP	MOVCUR

; <ESC> L seen so far in escape sequence
ESCL:
	MVI	B,01H		; CTRL-A, move cursor left
	JMP	ESCR2		; silly; just JMP CRTB

; <ESC> R seen so far in escape sequence
ESCR:
	MVI	B,13H		; CRTL-S, move cursor right
ESCR2	JMP	CRTB

; <ESC> N seen so far in escape sequence
ESCN:
	MVI	A,00H		; normal text mode
	JMP	TXTMOD

; <ESC> F seen so far in escape sequence
ESCF:
	MVI	A,80H		; inverse text mode

; set the text mode: $00 is normal, $80 is inverse mode
TXTMOD:
	STA	INVTXT
	CALL	CLRESC
	JMP	OUTDONE

; clear the escape sequence state
CLRESC:
	MVI	A,00H
	STA	ESCSEQ
	STA	ESCSTAT
	RET

; ----- there is no compiled code or constants after this point.
;       what exists here is just buffers and other storage.
; update: actually, INVTXT must be initialized

CURLOC	DW	0	; absolute cursor location in VDMEM
INVTXT	DB	80H	; subsequent text is normal ($00) or inverse ($80)
ESCSTAT	DB	0	; escape sequence state (byte 1)
ESCSEQ	DB	0	; byte num of CRT escape sequence (0,1, or 2)
SAVA	DB	0	; holds A for a while ($00 at capture)
STATADR	DW	0	; address in pollin of last device polled
POLLIN	DB	0,0,0,0	; holds any input we read while polling status
SAVHL	DW	0	; holds HL for a while ($A80E at capture)
SAVBC	DW	0	; holds BC for a while ($007F at capture)

; scrach area common to all disks for directory
; operations within BDOS.
	IF	((($+0FFH) SHR 8) - 0BCH)
    ERROR: CODE BEFORE DIRBUF GREW (OR SHRANK) TOO MUCH
	ENDIF
	ORG	0BC00H
DIRBUF	DS	128

; ALV and CSV scratch buffers for disks 0-3
ALV0	DS	22	; (DSM/8)+1
CSV0	DS	16	; (DRM+1)/4
ALV1	DS	22	; (DSM/8)+1
CSV1	DS	16	; (DRM+1)/4
ALV2	DS	22	; (DSM/8)+1
CSV2	DS	16	; (DRM+1)/4
ALV3	DS	22	; (DSM/8)+1
CSV3	DS	16	; (DRM+1)/4

; contains logic (128B cp/m) sector we are seeking
SEKREC	EQU	$
SEKDSK	DS	1	; seek disk number
SEKTRK	DS	2	; seek track number
SEKSEC	DS	1	; seek sector number

; copy of SEKDSK/SEKTRK/SEKSEC
HSTREC	EQU	$	; absolute sector address, as (dsk,track,sector-of-track)
HSTDSK	DS	1	; host disk number
HSTTRK	DS	2	; host track number
HSTSEC	DS	1	; host sector number

; contains absolute sector address of unallocated sector.
; used by sector deblocking code.
UNAREC	EQU	$
UNADSK	DS	1	; last unalloc disk
UNATRK	DS	2	; last unalloc track
UNASEC	DS	1	; last unalloc sector

UNACNT	DS 	1	; unallocated record count (used by deblocking writes)
HSTACT	DS	1	; host active flag
DIRTY	DS	1	; HSTBUF 0=no pending writes, 1=pending write
RSFLAG	DS	1	; read sector flag
READOP	DS	1	; 0 means write operation, 1 means read
WRTYPE	DS	1	; C parameter bdos passed on bios write call
DMAADR	DS	2	; disk transfer DMA address; $0080 at time of capture
NSTRK	DS	4	; current track of each disk; $02,$59,$59,$59 at capture
WBFLAG	DS	1	; 0=cold boot, 1=warm boot
PSECTRN	DS	2	; pointer to sector translation table.  secDD at capture
NUMSEC	DS	1	; number of sectors to transfer
DSKSPD	DS	1	; time between sector holes, auto calibrated


; single density disk sector translation table.
; note the fourness is because of the 128-to-512 sector blocking.
; NOTE: these tables are actually built by code ("MAKSTT:").
SKEWSD	DS	20
;SKEWSD:
;	DB	01H,02H,03H,04H
;	DB	05H,06H,07H,08H
;	DB	09H,0AH,0BH,0CH
;	DB	0DH,0EH,0FH,10H
;	DB	11H,12H,13H,14H

; double density disk sector translation table.
; same as north star DD disk format.
; note the fourness is because of the 128-to-512 sector blocking.
; after deblocking, works out to skew factor of 5.
SKEWDD	DS	41
;SKEWDD:
;	DB	01H,02H,03H,04H		; note: $01 is magic to SKEWSD table
;	DB	15H,16H,17H,18H
;	DB	05H,06H,07H,08H
;	DB	19H,1AH,1BH,1CH
;	DB	09H,0AH,0BH,0CH
;	DB	1DH,1EH,1FH,20H
;	DB	0DH,0EH,0FH,10H
;	DB	21H,22H,23H,24H
;	DB	11H,12H,13H,14H
;	DB	25H,26H,27H,28H

;	DB	01H			; note: used to catch end of track

; this is a 512B buffer for holding physical disk sectors.
; it is used to block/deblock logical 128B CP/M sectors.
; although the CP/M docs say IF tests zero vs nonzero,
; it actually appears to just test the lsb, and the following
; check will fail if we slip by two pages instead of just one
	IF	((($+0FFH) SHR 8) - 0BEH)
    ERROR: CODE BEFORE HSTBUF GREW (OR SHRANK) TOO MUCH
	ENDIF
	ORG	0BE00H
HSTBUF:	DS	512


; ------------------------------------------------------------
; SOLOS control variables
UIPRT	EQU	0C800H		; user defined  input routine vector
UOPRT	EQU	0C802H		; user defined output routine vector
NCHAR	EQU	0C808H		; current cursor character of row
LINE	EQU	0C809H		; current cursor line-of-screen
BOT	EQU	0C80AH		; beginning of hw scroll text displacement

; SOL specific defs
STAPT	EQU	0FAH		; I/O status port
VDMEM	EQU	0CC00H		; start of VDM memory

; solos ROM routine addresses
AOUT	EQU	0C01CH		; pseudo-port output routine
AINP	EQU	0C022H		; pseudo-port  input routine
OCHAR	EQU	0C098H		; send char to screen
PERSE	EQU	0C0D5H		; erase screen

; generic defs
CR	EQU	0DH		; carriage return
LF	EQU	0AH		; line feed


; ------------------------------------------------------------
; IO port mapping from north star disk controller
;
; The following docs are lifted more or less verbatim from
; NorthStar document "Micro-disk system MDS-A-D Double Density"

; Case 0: PROM addressing
;
;  +----+----+----+----+----+----+----+----+
;  |             PROM Address              |
;  +----+----+----+----+----+----+----+----+
;
; Read byte from the 256 bytes of PROM.

NSBOOT	EQU	0E800H

; Case 1: Write byte of data
;
;  +----+----+----+----+----+----+----+----+
;  |                 Data                  |
;  +----+----+----+----+----+----+----+----+
;
; Write a byte of data to the disk.  Wait if the write shift
; register is not empty.  The low order 8 bits specify the
; byte to be written.

NSWRT	EQU	0E900H


; Case 2: Controller Orders
;
;  +----+----+----+----+----+----+----+----+
;  | DD | SS | DP | ST |        DS         |
;  +----+----+----+----+----+----+----+----+
;
; Load 8-bit order register from low order 8 address bits.
;
; DD  Controls density on write.
;     DD=1 for double density.
;     DD=0 for single density.
;
; SS  specifies the side of a double-sided diskette.  The
;     bottom side (and only side of a single-sided diskette)
;     is selecte when SS=0.  The second (top) side is
;     selected when SS=1.
;
; DP  has shared use.  During stepping operations, DP=0
;     specifies a step out and DP=1 specifies a step in.
;     During write operations, write precompensation is
;     invoked if and only if DP=1.
;
; ST  controls the level of the head step signal to the disk
;     drives.
;
; DS  is the drive select field, encoded as follows
;
;        0=no drive selected
;        1=drive 1 selected
;        2=drive 2 selected
;        4=drive 3 selected
;        8=drive 4 selected

NSORD	EQU	0EA00H

NSDBLD	EQU	80H		; double density
NSSNGD	EQU	00H		; single density

NSTOP	EQU	40H		; bottom (only?) side
NSBOT	EQU	00H		; bottom (only?) side

NSIN	EQU	20H		; step in       (if CORD_STEP is true)
NSOUT	EQU	00H		; step out      (if CORD_STEP is true)
NSPRE	EQU	20H		; write precomp (if CORD_STEP is false)

NSSTEP	EQU	10H		; step pulse on


; Case 3: Controller Command
;
;  +----+----+----+----+----+----+----+----+
;  |        DM         |        CC         |
;  +----+----+----+----+----+----+----+----+
;
; Perform a disk controller command.  The commands are
; specified by the 8 low order address bits.
;
; DM   The DM field controls what gets multiplexed onto the
;      DI bus during the command.
;
;         1=A-status
;         2=B-status
;         3=C-status
;         4=Read data (may enter wait state)
;
; CC   Command code.
;
;         0=no operation
;         1=reset sector flag
;         2=disarm interrupt
;         3=arm interrupt
;         4=set body (diagnostic)
;         5=turn on drive motors
;         6=begin write
;         7=reset controller, deselect drives, stop motors

NSCCNOP		EQU	0H
NSCCRSF		EQU	1H
NSCCNOINT	EQU	2H
NSCCARM		EQU	3H
NSCCBODY	EQU	4H
NSCCMOTR	EQU	5H
NSCCWRT		EQU	6H
NSCCSTP		EQU	7H


; DISK CONTROLLER STATUS BYTES
;
; There are three status bytes that can be read on the Data Input
; Bus.
;
;     A-Status
;          +----+----+----+----+----+----+----+----+
;          | SF | IX | DD | MO | WI | RE | SP | BD |
;          +----+----+----+----+----+----+----+----+
;
; SF   Sector Flag: set when sector hole detected, reset by
;      software.
;
; IX   Index Detect: true if index hole detected during previous
;      sector.
;
; DD   Double Density Indicator: true if data being read is encoded
;      in double density.
;
; MO   Motor On: true while motor(s) are on.
;
; WI   Window: true during 96-microsecond window at beginning of
;      sector.
;
; RE   Read Enable: true while phase-locked loop is enabled.
;
; BD   Body: set when sync character is detected.
;
; SP   Spare: reserved for future use.
;
;
;     B-Status
;          +----+----+----+----+----+----+----+----+
;          | SF | IX | DD | MO | WR | SP | WP | T0 |
;          +----+----+----+----+----+----+----+----+
;
; SF, IX, DD, MO, SP: same as A-Status
;
; WR   Write: true during valid write operation.
;
; WP   Write Protect: true while the diskette installed in the
;      selected drive is write protected.
;
; T0   Track 0: true if selected drive is at sector 0.
;        [ NOTE: I think this is in error: it is true if the
;                head for the selected drive is at track 0,
;                not sector 0.  This isn't based on any
;                experiment, just the name and reason.  ]
;
;     C-Status
;          +----+----+----+----+----+----+----+----+
;          | SF | IX | DD | MO |        SC         |
;          +----+----+----+----+----+----+----+----+
;
; SF, IX, DD, MO: same as A-Status
;
; SC   Sector Counter: indicates the current sector position.


NSCMD	EQU	0EB00H

NSSTATA	EQU	NSCMD+10H	; "A-Status"
NSSTATB	EQU	NSCMD+20H	; "B-Status"
NSSTATC	EQU	NSCMD+30H	; "C-Status"
NSREAD	EQU	NSCMD+40H	; read data

NSSF	EQU	80H		; sector flag mask
NSIX	EQU	40H		; index hole flag mask
NSDD	EQU	20H		; double density flag mask
NSMO	EQU	10H		; motor on flag mask

NSWI	EQU	08H		; A-status, window flag mask
NSRE	EQU	04H		; A-status, read enable flag mask
NSBD	EQU	02H		; A-status, body flag mask

NSWR	EQU	08H		; B-status, write flag mask
NSWP	EQU	02H		; B-status, write protect flag mask
NST0	EQU	01H		; B-status, track 0 flag mask

NSSC	EQU	0FH		; C-status, sector count field mask


; DISK CONTROLLER DATA FORMAT
;
; Each diskette has 35 tracks of data.  Each track is divided into
; 10 sectors.  The rotational position of the beginning of the
; sectors is marked by sector holes in the diskette.  Each sector
; is recorded using the following format.  This information is
; recorded starting about 96 microseconds after the sector hole is
; detected.
;
;                       Single Density  Double Density
;        Zeros             16 bytes        32 bytes
;        Sync Char(FB)      1 byte          2 bytes
;        Data             256 bytes       512 bytes
;        Check Char         1 byte          1 byte
;
; [ NOTE: a bit further on the docs claim 15/31 leading $00
;         bytes for each sector, not 16/32. ]
;
; The check character is computed iteratively by setting it to zero
; and then exclusive ORing each successive data byte value with the
; current value of the check character and left cycling the result.


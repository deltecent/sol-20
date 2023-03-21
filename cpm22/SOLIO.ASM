;------------------------------------------------------------
;USER AREA for Lifeboat CP/M2
;
;  This code provides I/O support for the Sol-20 and differs
;  from the default Sol-20 support by mapping the Sol-20 DEL
;  key to perform "normal" destructive backspace. The serial
;  I/O below is mostly the diassembled code provided by
;  Lifeboat for the Sol-20. It avoids using stack for some
;  reason, I haven't investigated as to why.
;  
;    1.0   7-15-15   Mike Douglas
;    1.1   6-10-17   Mike Douglas
;	Add FASTOFF assembly option to turn off drive
;	motors whenever CONIN is called. Since disk
;	activity is complete whenever a program is
;	waiting on user input, CONIN serves well as
;	a "disk idle" indicator. By turning the drive
;	motor off at this point, the long 9.6 sec wait
;	to remove or swap disks is avoided. Also, the
;	urge to type commands fast to beat the disk
;	shutdown is also avoided.
;
;  To install this patch, run MOVCPM and save to a file
;  (e.g., CPM.COM) as instructed. Then use DDT to install
;  the patch:
;
;     A>DDT CPM.COM
;     -ISOLIO.HEX
;     -R6C00	(replace 6C00 with value of "OFFSET" below)
;     -G0
;     A>SYSGEN   (hit return at source prompt to use
;		 image in memory)
;------------------------------------------------------------

; Change MSIZE to the desired CP/M memory size in K.

MSIZE	equ	48		;Distribution size

; Set FASTOFF to 1 to turn off drive motors when CONIN
;   is called (i.e., program is not using disks).

FASTOFF	equ	1

; These equates are automatically changed by MSIZE.

BIAS	EQU	(MSIZE-20)*1024-0700H
CCP	EQU	3400H+BIAS	; base of CCP
BDOS	EQU	CCP+0806H	; base of BDOS
BIOS	EQU	CCP+1600H	; base of BIOS
USER	EQU	CCP+1D00H	; base of USER area
OFFSET	equ	2700H-USER	; offset to overlay SYSGEN image

; SOLOS/CUTER entry points

AOUT	equ	0C01Ch		;send byte in b out pseudo port in a
AINP	equ	0C022h		;return byte in a from port in a
UIPRT	equ	0C800h		;user defined input routine for port 3
UOPRT	equ	0C802h		;user defined output outine for port 3
STAPT	equ	0FAh		;Sol-20 control/status port

; Misc equates

IOBYTE	equ	3		;location of CP/M IOBYTE
RETINST	equ	0C9h		;8080 RET instruction
EMPTY	equ	080h		;empty byte in receive buffer
CR	equ	00Dh		;ASCII carriage return
DEL	equ	07Fh		;Sol-20 DEL on keyboard
BS	equ	008h		;ASCII backspace
SOLBS	equ	081h		;makes Sol-20 screen to backspace
DISKOFF	equ	0EB17h		;FDC reset command

	ORG	USER		;Start of USER AREA
;----------------------------------------------------------------------
; JUMP TABLE - Jumps MUST remain here in same order.
;----------------------------------------------------------------------
cInit	jmp	coldIni		;cold start init
	jmp	warmIni		;warm start init
	jmp	conStat		;BIOS console status call
	jmp	conIn		;BIOS console input call
	jmp	conOut		;BIOS console output call
	jmp	listOut		;BIOS list output call
	jmp	punOut		;BIOS punch output call
	jmp	rdrIn		;BIOS reader input call
	jmp	lstStat		;BIOS list status call

; This 8 byte data area used externally MUST remain.

lenUser	dw	USRLEN		;Length of USER AREA
defIob	db	94h		;defalt I/O byte 10 01 01 00
hsType	db	0		;Handshaking type (not used)
nullOc	db	0		;Printer nulls (not used)
	db	0,0,0		;Reserved

;-----------------------------------------------------------------------
; coldIni - cold start initialization
;   This entry is called during cold boot.
;-----------------------------------------------------------------------
coldIni	nop			;reserve spot to patch
	nop	
	nop
	xra	a
	out	STAPT		;ensure tape drives stopped
	lda	defIob		;initialize default I/O Byte
	sta	IOBYTE
	lxi	h,RETINST	;init SOLOS user routines to RET
	shld	UIPRT		;user input routine
	lxi	h,RETINST	;do again so it can be patched
	shld	UOPRT		;user output routine
	lxi	h,EMPTY*256+EMPTY	;init buffer table to empty
	shld	bufTbl		;one spot per pseudo port number
	shld	bufTbl+2
	ret

;-----------------------------------------------------------------------
; warmIni - warm start initialization
;   This entry is called during each warm boot.
;-----------------------------------------------------------------------
warmIni	nop			;reserve sport to patch
	nop
	nop
	ret

;-----------------------------------------------------------------------
; conStat - console status check
;   Use SOLOS AINP routine to test for character. AINP accepts a
;   pseudo port number in a to do input from one of three ports.
;   Since AINP returns a character if present, we have to buffer
;   the returned value for a later call to conIN.
;-----------------------------------------------------------------------
conStat	lda	IOBYTE		;get IOBYTE = pseudo port
	ani	3		;get console bits alone
doStat	shld	saveHL		;save HL (not push due to stack issues?)
	mov	h,b
	mov	l,c
	shld	saveBC		;save BC
	mov	c,a		;c=pseudo port number
	mvi	b,0		;form bc=index by pseudo port
	lxi	h,bufTbl
	dad	b		;hl->buffer table per port
	shld	bufPtr		;pointer to buffered char
	mov	a,m		;a=buffered char for this port
	cpi	EMPTY
	jnz	haveChr		;not empty, already have byte
	mov	a,c		;pseudo port=IOBYTE
	call	AINP		;SOLOS read from port in A
	mov	m,a		;save possible char in buffer table
	jnz	haveChr		;not-zero = have a character
	mvi	m,EMPTY		;otherwise, force empty
	xra	a		;CP/M no character status
	jmp	inExit		;exit input routine	

; haveChr - a character is present and has been buffered for a later
;   call from conIn. Return FF and non-zero status to CP/M

haveChr	mvi	a,0FFH		;CP/M character present status
inExit	lhld	saveBC		;restore BC, HL and exit
	mov	b,h
	mov	c,l
	lhld	saveHL
	ret

;-----------------------------------------------------------------------
; conIn, rdrIn - console and reader input.
;   If a character is already buffered, return it. Otherwise, wait
;   for a new character.
;-----------------------------------------------------------------------
conIn	equ	$

 IF FASTOFF
	lda	DISKOFF		;turn off drive motors
 ENDIF

	lda	IOBYTE		;get IOBYTE = pseudo port
	jmp	doIn

rdrIn	lda	IOBYTE		;get IOBYTE = pseudo port
	rar			;put in ls bits
	rar
	jmp	doIn		;leave jump for possible patch

; doIn - do the input operation. If a character already buffered
;   return it. Otherwise, wait for a new character

doIn	ani	3		;get pseudo port alone
	sta	savPort		;save it
inLoop	call	doStat		;do status check on port in a
	lda	savPort		;restore port
	jz	inLoop		;no character present, keep waiting

; new byte present and buffered in the buffer table. Pull it out and
;   set the buffer to empty. If the pseudo device is the console,
;   translate DEL to BS

	shld	saveHL
	lhld	bufPtr		;hl=saved I/O table pointer
	ora	a		;Sol pseudo port?
	jnz	notSolI		;no
	mvi	a,DEL		;translate DEL to BS
	cmp	m
	jnz	notSolI
	mvi	a,BS		;return backspace instead
	jmp	setEmp		;set buffer to empty

notSolI	mov	a,m		;a=buffered character
setEmp	mvi	m,EMPTY		;set buffer spot to empty
	lhld	saveHL		;restore HL
	ani	07FH
	ret

;-----------------------------------------------------------------------
; conOut, listOut, punOut - console, list and punch output.
;   Output to the selected device. If sending to the Sol-20
;   screen, translate BS to 81h which is equivalent to BS.
;-----------------------------------------------------------------------
conOut	lda	IOBYTE		;get IOBYTE = pseudo port
	jmp	charOut

listOut	lda	IOBYTE		;get IOBYTE = pseudo port
	rlc			;put in ls bits
	rlc
	jmp	charOut

punOut	lda	IOBYTE		;get IOBYTE = pseudo port
	rar			;put in ls bits
	rar
	rar
	rar
	jmp	charOut		;leave for possible patch

; charOut - send the character in c

charOut	shld	saveHL		;save HL and BC
	mov	h,b
	mov	l,c
	shld	saveBC
	mov	b,c		;b=char to send
	ani	3		;a=pseudo port to use
	jnz	notSolO		;not-zero means not Sol-20 screen

; Sol-20 screen output, don't send multiple CR's in a row, translate
;   ASCII BS to 81h which does the equivalent operation on the Sol

	lda	prevChr		;what was the previous char?
	cpi	CR		;if CR, don't send again
	jnz	notCr
	cmp	b		;is this CR too?
	jz	outExit		;yes, just ignore
notCr	mov	a,b		;character to send in a
	cpi	BS		;is it a backspace?
	jnz	notBs		;no
	mvi	b,SOLBS		;send Sol BS (81h) instead
notBs	mov	a,b
	sta	prevChr		;save previous char
	xra	a		;pseudo port is zero

; send character in b through port in a using AOUT in monitor

notSolO	call	AOUT		;monitor AOUT
outExit	lhld	saveBC
	mov	b,h
	mov	c,l
	lhld	saveHL
	mov	a,c
	ret

;-----------------------------------------------------------------------
; lstStat - list status not supported. Return zero per CP/M spec.
;-----------------------------------------------------------------------
lstStat	xra	a		;always or never ready?
	ret

;-----------------------------------------------------------------------
; Data area
;-----------------------------------------------------------------------
saveBC	ds	2		;saved BC
saveHL	ds	2		;saved HL
bufPtr	ds	2		;pointer into buffer table
savPort	ds	1		;saved pseudo port number
prevChr	ds	1		;previous character sent
bufTbl	ds	4		;character buffer per pseudo-port

USRLEN	EQU	$-cInit		;Length of USER AREA
	END

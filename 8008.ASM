;	i8008 program loader for generic MS-DOS
;
;	Copyright (C) 2025 by Gazelle
;
;Permission is hereby granted, free of charge, to any person
;obtaining a copy of this software and associated documentation
;files (the "Software"), to deal in the Software without
;restriction, including without limitation the rights to use,
;copy, modify, merge, publish, distribute, sublicense, and/or sell
;copies of the Software, and to permit persons to whom the
;Software is furnished to do so, subject to the following
;conditions:
;
;The above copyright notice and this permission notice shall be
;included in all copies or substantial portions of the Software.
;
;THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
;EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
;OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
;NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
;HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
;WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
;FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
;OTHER DEALINGS IN THE SOFTWARE.

;Repository https://github.com/Gazelle8087/8008-loader-for-DOS
;
;2025/6/5 Rev. 1.00 Initial release
;2025/6/7 Rev. 1.01 8008 SP register assignment can be changed(BP or DI)

		page 0,180
		.model	tiny
		.code

code_step	equ	0fbh
code_undef1	equ	0fch
code_HLT_00	equ	0fdh
code_HLT_01	equ	0feh
code_HLT_FF	equ	0ffh
		org	100h

		assume	ds:nothing,es:nothing,ss:nothing

start:		jmp	hajime

		align	2
stack80		dw	8 dup (0)
save_SP		dw	?
save_si		dw	?
save_ax		dw	?
save_bx		dw	?
save_cx		dw	?
save_dx		dw	?
z80_seg		dw	?
em_file_handle	dw	?
cpm_file_handle	dw	?
cpm_arg_offset	dw	?
fcb_addr	dw	?
path_flag	db	0
env_flag	db	0
drv_flag	db	0
file_name_end	dw	?
start_addr	dw	0
disp_counter	db	16

cpm_str		db	'.CO8',0
i808_str	db	'.808',0
env_key		db	'Z_EM='
em_file_name0	db	'8008EM.BIN',0
em_file_name0_end:
env_str		db	128 dup (0)
em_file_name	db	128 dup (?)
cpm_file_name	db	128 dup (?)
buffer_area	db	128 dup (?)

;---------------------------------------------

hajime:		mov	ax,cs
		mov	es,ax
		mov	ds,ax
		mov	dx,offset open_msg
		mov	ah,9
		int	21h
		mov	ah,4ah		;192KB écÇµÇƒÉÅÉÇÉääJï˙
		mov	bx,3001h
		int	21h
		jnc	main_read_emulator
		jmp	no_mem
main_read_emulator:
		mov	ax,cs
		mov	ss,ax
		mov	sp,0f000h
		add	ax,1000h
		test	ax,1
		jz	em_seg_even
		inc	ax
em_seg_even:	mov	em_seg,ax
		add	ax,1000h
		mov	z80_seg,ax

		call	search_env

		call	read_emulator

		call	read_cpm_file
;--------------------------------------
SP08		equ	bp
;SP08		equ	di

ifidni		SP08,<bp>
step_counter	equ	di
exit_code	equ	di
endif

ifidni		SP08,<di>
step_counter	equ	bp
exit_code	equ	bp
endif

		mov	ds,z80_seg
		mov	es,z80_seg
		mov	si,start_addr	;PC reg of 8008
		mov	SP08,0		;SP internal reg for 8008
		mov	save_si,si

		mov	dx,80h
		mov	ah,1ah
		int	21h
		cld
go_cpm:
no_op:
		mov	dx,save_dx
		mov	cx,save_cx
		mov	bx,save_bx
		mov	ax,save_ax
		mov	si,save_si
		mov	SP08,save_SP
		xor	step_counter,step_counter

		db	09ah		;CALL far
		dw	0e0h		;8008 emulator entry point
EM_SEG		dw	?		;emulator loading segment

		mov	save_SP,SP08
		mov	save_ax,ax
		mov	save_bx,bx
		mov	save_cx,cx
		mov	save_dx,dx
		mov	save_si,si

chk_bp_00:	cmp	exit_code,0		;DI=00h then IN 00 console status
		jne	chk_bp_01
		mov	ah,0bh
		int	21h
		or	al,04		;always conout ready
		mov	byte ptr save_ax,al
		jmp	go_cpm

chk_bp_01:	cmp	exit_code,1		;DI=01h then IN 01 console input
		jne	chk_bp_10
		mov	ah,7
		int	21h
		mov	byte ptr save_ax,al
		jmp	go_cpm

chk_bp_10:	cmp	exit_code,10h		;DI=10h then OUT 10 console output
		jne	chk_bp_1f
		cmp	al,0ffh
		jne	chk_bp_11
		xor	ax,ax
chk_bp_11:	mov	dl,al
		mov	ah,6
		int	21h
		jmp	go_cpm

chk_bp_1f:	cmp	exit_code,1fh
		jne	chk_bp_fe
		mov	ax,cs
		mov	ds,ax
		mov	es,ax
		mov	ah,9
		mov	dx,offset Exit_msg
		int	21h
		mov	ax,4c00h
		int	21h

chk_bp_fe:	cmp	exit_code,0feh		;DI(return code) = 0feh : HLT(code 01)
		jne	z80_error
		cmp	cl,40		;28h
		ja	z80_error
		mov	ah,cl
		int	21h		;DOS function act as supervisor call
		mov	save_ax,ax
		mov	save_bx,bx
		mov	save_cx,cx
		mov	save_dx,dx
		jmp	go_cpm

;---------------------------------
Z80em_undef_msg		db	'Undefined code $'
Z80em_unexec_msg	db	'Unexecutable code $'
Z80em_error_msg		db	' at $'
z80em_err_addr		dw	?
Exit_msg		db	'Exit from 8008 emulator',0dh,0ah,'$'

Z80_error:	mov	dx,offset z80em_unexec_msg
		mov	cx,1
		mov	bx,1
		cmp	exit_code,20h
		jb	z80_error_0
		cmp	exit_code,code_step
		jb	z80em_internal_error
		cmp	exit_code,100h
		jae	z80em_internal_error
		cmp	exit_code,code_HLT_00
		jbe	z80_error_0

		mov	dx,offset z80em_undef_msg
		jmp	z80_error_0

z80_error_0:	mov	ax,cs
		mov	ds,ax
		mov	ah,9
		int	21h

		sub	si,bx
		mov	z80em_err_addr,si
		mov	es,z80_seg
z80_error_6:
		mov	al,es:[si]
		call	dsphex2
		inc	si
		loop	z80_error_6
		mov	dx,offset z80em_error_msg
		mov	ah,9
		int	21h
		mov	ax,z80em_err_addr
		call	dsphex4
		mov	ax,4c00h
		int	21h

;======================================
open_msg		db	'i8008 simulator loader for DOS Rev. 1.00  '
			db	'Copyright (c) 2025 by Gazelle',0dh,0ah,0ah,24h
no_mem_msg		db	'No enough memory.$'
em_open_error_msg	db	'8008EM.BIN open error.$'
em_read_error_msg	db	'8008EM.BIN read error.$'
em_close_error_msg	db	'8008EM.BIN close error.$'
cpm_open_error_msg	db	'8008 executable file open error.$'
cpm_read_error_msg	db	'8008 executable file read error.$'
cpm_close_error_msg	db	'8008 executable file close error.$'
too_long_path_msg	db	'too long path.$'
too_large_com_msg	db	'too large 8008 executable file.$'
internal_error_msg	db	'8008EM.BIN internal error.$'

em_close_error:	mov	dx,offset em_close_error_msg
		jmp	error_exit
em_open_error:	mov	dx,offset em_open_error_msg
		jmp	error_exit
em_read_error:	mov	dx,offset em_read_error_msg
		jmp	error_exit
cpm_close_error:mov	dx,offset cpm_close_error_msg
		jmp	error_exit
cpm_open_error:	mov	dx,offset cpm_open_error_msg
		jmp	error_exit
cpm_read_error:	mov	dx,offset cpm_read_error_msg
		jmp	error_exit
no_mem:		mov	dx,offset no_mem_msg
		jmp	error_exit
too_long_path:	mov	dx,offset too_long_path_msg
		jmp	error_exit
too_large_com:	mov	dx,offset too_large_com_msg
		jmp	error_exit
z80em_internal_error:
		mov	dx,offset internal_error_msg
		jmp	error_exit

error_exit:
		mov	ax,cs
		mov	ds,ax
		mov	ah,9
		int	21h
		mov	ax,4c00h
		int	21h
;======================================

search_env:	mov	ax,cs
		mov	es,ax
		mov	ax,cs:[002ch]
		mov	ds,ax
		mov	si,0
		cld

search_env_next_4:
		mov	bx,0ffffh
		mov	di,offset env_key
		mov	dl,es:[di]
		lodsb
search_env_next_2:
		cmp	al,dl
		je	search_env_match_1
search_env_next_3:
		cmp	al,0
		je	search_env_next_5
search_env_next_1:
		lodsb
		and	si,si
		je	search_env_exit_1
		cmp	al,0
		jne	search_env_next_1
search_env_next_5:
		lodsb
		and	si,si
		je	search_env_exit_1
		cmp	al,0
		je	search_env_exit
		jmp	search_env_next_2

search_env_match_1:
		mov	bx,si
		dec	bx

search_env_match_3:
		lodsb
		and	si,si
		je	search_env_exit_1
		inc	di
		mov	dl,es:[di]
		cmp	al,dl
		je	search_env_match_2
search_env_match_4:
		cmp	al,0
		je	search_env_next_4
		lodsb
		and	si,si
		je	search_env_exit_1
		jmp	search_env_match_4
search_env_match_2:
		cmp	al,'='
		jne	search_env_match_3

		mov	cx,128
		mov	di,offset env_str
search_env_get:
		lodsb
		stosb
		cmp	al,0
		je	search_env_exit
		loop	search_env_get
		jmp	search_env_exit_1

search_env_exit_1:
		mov	bx,0ffffh
search_env_exit:
		mov	ax,cs
		mov	ds,ax
		ret
;================================================

read_emulator:
		mov	ax,cs
		mov	ds,ax
		mov	es,ax
		mov	ax,3d00h
		mov	dx,offset em_file_name0		;search current dir
;		call	disp_file_name
		int	21h
		jnc	read_em_4

		mov	si,offset env_str
		mov	di,offset em_file_name
		cld
		lodsb
		and	al,al
		jnz	read_em_31
		jmp	em_open_error
read_em_31:
		stosb
		mov	cx,117
read_em_1:
		lodsb
		and	al,al
		jz	read_em_2
		stosb
		loop	read_em_1
		jmp	too_long_path
read_em_2:
		mov	al,'\'
		stosb
read_em_3:
		mov	si,offset em_file_name0
		mov	cx,offset em_file_name0_end - offset em_file_name0
		rep	movsb

		mov	ax,3d00h
		mov	dx,offset em_file_name
;		call	disp_file_name
		int	21h
		jnc	read_em_4
		jmp	em_open_error
read_em_4:
		mov	em_file_handle,ax
		mov	bx,ax
		mov	ah,3fh
		mov	cx,0ffffh
		mov	ds,em_seg
		mov	dx,0
		int	21h
		jnc	read_em_5
		jmp	em_read_error
read_em_5:
		mov	ax,cs
		mov	ds,ax
		mov	ah,3eh
		mov	bx,em_file_handle
		int	21h
		jnc	read_em_exit
		jmp	em_close_error
read_em_exit:
		mov	ax,cs
		mov	ds,ax
		mov	es,ax
		ret
;================================================
read_cpm_file:
read_cpm_00:
		mov	di,offset cpm_file_name
read_cpm_0:
		mov	si,81h
		mov	cl,ds:[80h]
		mov	ch,0
read_cpm_01:	lodsb
		cmp	al,' '
		je	read_cpm_01
		cmp	al,09h
		je	read_cpm_01
		dec	si

read_cpm_02:	lodsb
		cmp	al,' '
		je	read_cpm_03
		cmp	al,0dh
		je	read_cpm_03
		cmp	al,0
		je	read_cpm_03
		cmp	al,09h
		je	read_cpm_03
		cmp	al,':'
		jne	read_cpm_04
		cmp	ah,'A'
		jb	read_cpm_04
		cmp	ah,'Z'
		jbe	read_cpm_06
		cmp	ah,'z'
		ja	read_cpm_04
		cmp	ah,'a'
		jb	read_cpm_04
read_cpm_06:	mov	drv_flag,1
read_cpm_04:	cmp	al,'\'
		jne	read_cpm_05
		mov	path_flag,1
read_cpm_05:	stosb
		mov	ah,al
		loop	read_cpm_02

read_cpm_03:	dec	si
		mov	cpm_arg_offset,si
		mov	file_name_end,di

		dec	si
		mov	cx,4
read_cpm_08:	std
		lodsb
		cmp	al,'.'
		je	read_cpm_09
		loop	read_cpm_08

		mov	di,file_name_end
		mov	si,offset cpm_str
		cld
		movsw
		movsw
		movsb

		mov	ax,3d00h
		mov	dx,offset cpm_file_name
;		call	disp_file_name
		int	21h
		jc	read_cpm_10
		mov	start_addr,100h
		jmp	read_cpm_6

read_cpm_10:	mov	di,file_name_end
		mov	si,offset i808_str
		cld
		movsw
		movsw
read_cpm_09:
		mov	al,0
		stosb
		mov	ax,3d00h
		mov	dx,offset cpm_file_name
;		call	disp_file_name
		int	21h
		jc	read_cpm_11
		mov	start_addr,00h
		jmp	read_cpm_6
read_cpm_11:
		cmp	env_flag,1
		je	read_cpm_111
		cmp	drv_flag,1
		je	read_cpm_111
		cmp	path_flag,1
		je	read_cpm_111
		jmp	read_cpm_12
read_cpm_111:
		jmp	cpm_open_error

read_cpm_12:	mov	env_flag,1
		mov	si,offset env_str
		mov	di,offset cpm_file_name
		cld
		lodsb
		and	al,al
		jz	read_cpm_111
		stosb
		mov	cx,127
read_cpm_1:
		lodsb
		and	al,al
		jz	read_cpm_2
		stosb
		loop	read_cpm_1
		jmp	too_long_path
read_cpm_2:
		mov	al,'\'
		stosb
read_cpm_3:
		jmp	read_cpm_0

read_cpm_6:
		mov	cpm_file_handle,ax
		mov	bx,ax
		mov	ah,3fh
		mov	cx,0fe00h
		mov	ds,z80_seg
		mov	dx,start_addr
		int	21h
		jnc	read_cpm_7
		jmp	cpm_read_error
read_cpm_7:
		and	ax,ax
		jnz	read_cpm_71
		jmp	cpm_read_error
read_cpm_71:
		cmp	ax,0fe00h
		jne	read_cpm_8
		jmp	too_large_com
read_cpm_8:
		mov	ax,cs
		mov	ds,ax
		mov	ah,3eh
		mov	bx,cpm_file_handle
		int	21h
		jnc	read_cpm_exit
		jmp	cpm_close_error
read_cpm_exit:
		ret
;================================================
dsphex4:	push	dx
		mov	dx,ax
		mov	al,ah
		call	dsphex2
		mov	ax,dx
		pop	dx

dsphex2:	push	dx
		mov	dl,al
		shr	al,1
		shr	al,1
		shr	al,1
		shr	al,1
		call	dsphex1
		mov	al,dl
		pop	dx

dsphex1:	push	dx
		and	al,0fh
		cmp	al,9
		jbe	dsphex1_1
		add	al,'@'-'9'
dsphex1_1:	add	al,'0'
		mov	dl,al
		mov	ah,2
		int	21h
		pop	dx
		ret
;======================================
disp_file_name:
		push	ax
		push	cx
		push	dx
		push	si
		mov	si,dx
		cld
		mov	cx,128
disp_file_name_loop:
		lodsb
		cmp	al,0
		je	disp_file_name_exit
		mov	dl,al
		mov	ah,2
		int	21h
		loop	disp_file_name_loop
disp_file_name_exit:
		mov	dl,0dh
		mov	ah,02
		int	21h
		mov	dl,0ah
		mov	ah,2
		int	21h
		pop	si
		pop	dx
		pop	cx
		pop	ax
		ret
;======================================
	end	start

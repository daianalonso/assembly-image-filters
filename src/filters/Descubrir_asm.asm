global Descubrir_asm


section .rodata
	mask_b: times 4 DB 0xFF, 0x00, 0x00, 0x00    
	mask_g: times 4 DB 0x00, 0xFF, 0x00, 0x00
	mask_r: times 4 DB 0x00, 0x00, 0xFF, 0x00
	reordenar: DB 0x00, 0x00, 0x00, 0x80, 0x01, 0x01, 0x01, 0x80, 0x02, 0x02, 0x02, 0x80, 0x03, 0x03, 0x03, 0x80
	unos: times 4 DB 0x1, 0x0, 0x0, 0x0
	tres: times 4 DB 0x3, 0x0, 0x0, 0x0 

section .text
;void Descubrir_c(
;    uint8_t *src, uint8_t *dst, int width,
;    int height, int src_row_size, int dst_row_size)
; rdi <- src
; rsi <- dst
; edx <- width
; ecx <- height
; r8 <- src_row_size
; r9 <- dst_row_size
Descubrir_asm:
push rbp
	mov rbp, rsp
	push r12
	push r13
	push r14
	push r15
	xor r12, r12
	xor r13, r13 
	%define i r12
	%define j r13

	mov r15, rdx

	mov rax, rcx
	mul r8			; rax = height*src_size_row
	sub rax, 16 		 
	lea r14, [rdi + rax] ; r14 <- apunta a la posición src[(height-1)-1][(width-1)-4] ya que vamos a tomar los últimos 4 pixels
	
	shr r15, 2 ; r15 <- width/4 (ya que vamos a procesar de a 4 pixeles por iteración)

	.procesarSiguienteFila:
		cmp i, rcx	; i < height ?
		je .fin
		.procesarSiguientesPixeles:
			cmp j, r15	; j < width/4 ?
			je .finalizarFila

			; src[(height-1)-i][(width-1)-j]
			movdqu xmm1, [r14] ; xmm1 = |p_3|p_2|p_1|p_0|

			; Invertimos el orden de los pixels
			pshufd xmm1, xmm1, 0x1b		; xmm1 = |p0|p1|p2|p3|

			movdqu xmm2, xmm1
			movdqu xmm8, [mask_b]
			pand xmm2, xmm8	     ; xmm2 = |0|0|0|bp|0|0|0|bp|0|0|0|bp|0|0|0|bp|

			movdqu xmm8, [mask_g]
			movdqu xmm3, xmm1
			pand xmm3, xmm8	     ; xmm3 = |0|0|gp|0|0|0|gp|0|0|0|gp|0|0|0|gp|0|
			psrld xmm3, 8		 ; xmm3 = |0|0|0|gp|0|0|0|gp|0|0|0|gp|0|0|0|gp|

			movdqu xmm8, [mask_r]
			pand xmm1, xmm8   	 ; xmm1 = |0|rp|0|0|0|rp|0|0|0|rp|0|0|0|rp|0|0|
			psrld xmm1, 16 	   	 ; xmm1 = |0|0|0|rp|0|0|0|rp|0|0|0|rp|0|0|0|rp|

			; Convertimos desde DWORD a BYTE
			packusdw xmm2, xmm2  
			packusdw xmm3, xmm3
			packusdw xmm1, xmm1

			packuswb xmm2, xmm2
			packuswb xmm3, xmm3
			packuswb xmm1, xmm1 

			;Reordenamos los bytes 
			movdqu xmm8, [reordenar]
			pshufb xmm2, xmm8  ;bit7
			pshufb xmm1, xmm8	;bit5
			pshufb xmm3, xmm8	;bit6


			;src[(height-1)-i][(width-1)-j] >> 2
			psrld xmm1, 2  ;Componente ROJA
			psrld xmm2, 2  ;Componente AZUL
			psrld xmm3, 2  ;Componente VERDE

			;Levantamos src[i][j]
			movdqu xmm4, [rdi]  ;xmm4 = |p3|p2|p1|p0|

			; Obtenemos componentes AZULES
			movdqu xmm5, xmm4
			movdqu xmm8, [mask_b]
			pand xmm5, xmm8		; xmm5 = |0|0|0|bp3|0|0|0|bp2|0|0|0|bp1|0|0|0|bp0|

			; Obtenemos componentes VERDES
			movdqu xmm8, [mask_g]
			movdqu xmm6, xmm4
			pand xmm6, xmm8 	; xmm6 = |0|0|gp3|0|0|0|gp2|0|0|0|gp1|0|0|0|gp0|0|
			psrld xmm6, 8		; xmm6 = |0|0|0|gp3|0|0|0|gp2|0|0|0|gp1|0|0|0|gp0|

			; Obtenemos componentes ROJAS
			movdqu xmm8, [mask_r]
			pand xmm4, xmm8   	; xmm4 = |0|rp3|0|0|0|rp2|0|0|0|rp1|0|0|0|rp0|0|0|
			psrld xmm4, 16 	  	; xmm4 = |0|0|0|rp3|0|0|0|rp2|0|0|0|rp1|0|0|0|rp0|

			; (src[(height-1)-i][(width-1)-j] >> 2) ^ src[i][j])
			pxor xmm2, xmm5	 ; <- b
			pxor xmm3, xmm6	 ; <- g
			pxor xmm1, xmm4  ; <- r 

			;(src[(height-1)-i][(width-1)-j] >> 2) ^ src[i][j]) & 0x3
			movdqu xmm8, [tres]
			pand xmm1, xmm8
			pand xmm2, xmm8
			pand xmm3, xmm8

			;bit2, bit3, bit4:
			movdqu xmm10, xmm2
			movdqu xmm11, xmm3
			movdqu xmm12, xmm1

			psrld xmm10, 1  ; b >> 1
			psrld xmm11, 1	; g >> 1
			psrld xmm12, 1  ; r >> 1

			movdqu xmm8, [unos]
			pand xmm10, xmm8  ; b >> 1 & 0x1
			pand xmm11, xmm8  ; g >> 1 & 0x1
			pand xmm12, xmm8  ; r >> 1 & 0x1

			;bit5, bit6, bit7:
			pand xmm2, xmm8   ; b & 0x1 = bit7
			pand xmm3, xmm8   ; g & 0x1 = bit6
			pand xmm1, xmm8   ; r & 0x1 = bit5

			; Obtenemos la componente de color
			; bit7 << 7:
			pslld xmm2, 7 
			; bit6 << 6:
			pslld xmm3, 6
			; bit5 << 5:
			pslld xmm1, 5
			; bit4 << 4:
			pslld xmm10, 4
			; bit3 << 3
			pslld xmm11, 3
			; bit2 << 2:
			pslld xmm12, 2

			; Obtenemos el color
			por xmm1, xmm2
			por xmm1, xmm3
			por xmm1, xmm10
			por xmm1, xmm11
			por xmm1, xmm12

			packusdw xmm1, xmm1
			packuswb xmm1, xmm1 		; xmm1 = |00|00|00|00|00|00|00|00|00|00|00|00|color3|color2|color1|color0|
			movdqu xmm8, [reordenar]	; xmm1 = |00|color3|color3|color3|00|color2|color2|color2|00|color1|color1|color1|00|color0|color0|color0|
			pshufb xmm1, xmm8

			; color -> xmm1
			;Guardamos el color en destino
			movdqu [rsi], xmm1

			; Seteo las componentes de transparencia en 255 en dst
			mov byte [rsi + 3], 255
			mov byte [rsi + 7], 255
			mov byte [rsi + 11], 255
			mov byte [rsi + 15], 255
			
			; Avanzo
			add rsi, 16	; Apuntamos los siguientes 4 pixels en dst
			add rdi, 16 ; Apuntamos los siguientes 4 pixels en src
			sub r14, 16 ; Apuntamos los siguiente pixel en src(mirror) a izquierda
			inc j
			jmp .procesarSiguientesPixeles

		.finalizarFila:
			xor j, j ; Reinicio el iterador de columna
			inc i
		    jmp .procesarSiguienteFila

	.fin:
		pop r15
		pop r14
		pop r13
		pop r12
		pop rbp
		ret


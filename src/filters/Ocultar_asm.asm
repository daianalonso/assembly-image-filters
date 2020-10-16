global Ocultar_asm

section .rodata
	mask_b: times 4 DB 0xFF, 0x00, 0x00, 0x00    
	mask_g: times 4 DB 0x00, 0xFF, 0x00, 0x00
	mask_r: times 4 DB 0x00, 0x00, 0xFF, 0x00
	reordenar: DB 0x00, 0x80, 0x80, 0x80, 0x01, 0x80, 0x80, 0x80, 0x02, 0x80, 0x80, 0x80, 0x03, 0x80, 0x80, 0x80
	unos: times 4 DB 0x1, 0x0, 0x0, 0x0
	cerofc: times 4 DD 0xFC
	tres: times 4 DB 0x3, 0x0, 0x0, 0x0
section .text
;void Ocultar( uint8_t *src,
;    uint8_t *src2, uint8_t *dst,
;    int width, int height,
;    int src_row_size, int dst_row_size)
; rdi <- src
; rsi <- src2
; rdx <- dst
; rcx <- width
; r8 <- height
; r9 <- src_row_size
; rsp + 8 <- dst_row_size
Ocultar_asm:
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

	mov rax, r8
	mul r9			; rax = height*src_size_row
	sub rax, 16 		 
	lea r14, [rdi + rax] ; r14 <- apunta a la posición src[(height-1)-1][(width-1)-4] ya que vamos a tomar los últimos 4 pixels
	
	shr rcx, 2	; rcx <- width/4 (ya que vamos a procesar de a 4 pixeles por iteración)

	.procesarSiguienteFila:
		cmp i, r8	; i < height?
		je .fin
		.procesarSiguientesPixeles:
			cmp j, rcx	; j < width/4 ?
			je .finalizarFila

			; PRIMERA PARTE: Convertir a escala de grises
			; uint8_t color = (uint32_t)(src2_matrix[i][j].b + 2 * src2_matrix[i][j].g + src2_matrix[i][j].r) >> 2;

			; Tomamos los siguientes 4 pixels de SRC2
			movdqu xmm0, [rsi]  ;xmm0 = |p3|p2|p1|p0|

			; Obtenemos componentes AZULES
			movdqu xmm1, xmm0
			movdqu xmm8, [mask_b]
			pand xmm1, xmm8		; xmm1 = |0|0|0|bp3|0|0|0|bp2|0|0|0|bp1|0|0|0|bp0|

			; Obtenemos componentes VERDES
			movdqu xmm8, [mask_g]
			movdqu xmm2, xmm0
			pand xmm2, xmm8 	; xmm2 = |0|0|gp3|0|0|0|gp2|0|0|0|gp1|0|0|0|gp0|0|
			psrld xmm2, 8		; xmm2 = |0|0|0|gp3|0|0|0|gp2|0|0|0|gp1|0|0|0|gp0|

			pslld xmm2, 1		; xmm2 = |0|0|0|2*gp3|0|0|0|2*gp2|0|0|0|2*gp1|0|0|0|2*gp0|

			; Obtenemos componentes ROJAS
			movdqu xmm8, [mask_r]
			pand xmm0, xmm8   	; xmm0 = |0|rp3|0|0|0|rp2|0|0|0|rp1|0|0|0|rp0|0|0|
			psrld xmm0, 16 	  	; xmm0 = |0|0|0|rp3|0|0|0|rp2|0|0|0|rp1|0|0|0|rp0|

			; Sumamos componentes de cada pixel
			paddd xmm0, xmm2 	; xmm0 = |rp3+2*gp3|rp2+2*gp2|rp1+2*gp1|rp0+2*gp0|
			paddd xmm0, xmm1 	; xmm0 = |rp3+2*gp3+bp3|rp2+2*gp2+bp2|rp1+2*gp1+bp1|rp0+2*gp0+bp0|

			psrld xmm0, 2 		; xmm0 = xmm0/4 = color(p3,p2,p1,p0)

			pxor xmm3, xmm3  ; relleno con ceros 
			packusdw xmm0, xmm3 ; xmm0 = |0|0|0|0|color(p3)|color(p2)|color(p1)|color(p0)|
			packuswb xmm0, xmm3 ; xmm0 = |0|0|0|0|0|0|0|0|0|0|0|0|color(p3)|color(p2)|color(p1)|color(p0)|
			movdqu xmm8, [reordenar]
			pshufb xmm0, xmm8   ; xmm0 = |0|0|0|color(p3)|0|0|0|color(p2)|0|0|0|color(p1)|0|0|0|color(p0)|

			; SEGUNDA PARTE:
			; uint8_t bitsB = (((color >> 4) & 0x1) << 1) | ((color >> 7) & 0x1);
			; bitsB
			movdqu xmm6, xmm0
			movdqu xmm8, xmm0
			; ((color >> 4) & 0x1) << 1
			psrld xmm6, 4
			movdqu xmm4, [unos]
			pand xmm6, xmm4
			pslld xmm6, 1
			; (color >> 7) & 0x1
			psrld xmm8, 7
			pand xmm8, xmm4
			; or
			por xmm6, xmm8 ; xmm6 = bitsB

			; bitsG
            ; uint8_t bitsG = (((color >> 3) & 0x1) << 1) | ((color >> 6) & 0x1);
			movdqu xmm7, xmm0
			movdqu xmm8, xmm0
			; ((color >> 3) & 0x1) << 1
			psrld xmm7, 3
			pand xmm7, xmm4
			pslld xmm7, 1
			; (color >> 6) & 0x1
			psrld xmm8, 6
			pand xmm8, xmm4
			; or
			por xmm7, xmm8 ; xmm7 = bitsG

			; bits R uso xmm0
            ; uint8_t bitsR = (((color >> 2) & 0x1) << 1) | ((color >> 5) & 0x1);
			movdqu xmm8, xmm0
			; ((color >> 2) & 0x1) << 1
			psrld xmm0, 2
			pand xmm0, xmm4
			pslld xmm0, 1
			; (color >> 5) & 0x1
			psrld xmm8, 5
			pand xmm8, xmm4
			; or
			por xmm0, xmm8 		; xmm0 = bitsR
		
			; (src[i][j])
			movdqu xmm9, [rdi]  ;xmm9 = |p|p|p|p|

			movdqu xmm1, xmm9
			movdqu xmm8, [mask_b]
			pand xmm1, xmm8		; xmm1 = |0|0|0|bp|0|0|0|bp|0|0|0|bp|0|0|0|bp|

			movdqu xmm8, [mask_g]
			movdqu xmm2, xmm9
			pand xmm2, xmm8 	; xmm2 = |0|0|gp|0|0|0|gp|0|0|0|gp|0|0|0|gp|0|
			psrld xmm2, 8		; xmm2 = |0|0|0|gp|0|0|0|gp|0|0|0|gp|0|0|0|gp|

			movdqu xmm8, [mask_r]
			pand xmm9, xmm8   	; xmm9 = |0|rp|0|0|0|rp|0|0|0|rp|0|0|0|rp|0|0|
			psrld xmm9, 16 	  	; xmm9 = |0|0|0|rp|0|0|0|rp|0|0|0|rp|0|0|0|rp|

			; (src[i][j].r & OxFC)
			movdqu xmm4, [cerofc] 
			; xmm9 = |0|0|0|rp|0|0|0|rp|0|0|0|rp|0|0|0|rp|
			pand xmm9, xmm4
			; (src[i][j].b & OxFC)
			; xmm1 = |0|0|0|bp|0|0|0|bp|0|0|0|bp|0|0|0|bp|
			pand xmm1, xmm4
			; (src[i][j].g & OxFC)
			; xmm2 = |0|0|0|gp|0|0|0|gp|0|0|0|gp|0|0|0|gp|
			pand xmm2, xmm4

			movdqu xmm4, [tres]
			;(bitsB & 0x3)
			pand xmm6, xmm4
			;(bitsG & 0x3)
			pand xmm7, xmm4
			;(bitsR & 0x3)
			pand xmm0, xmm4

			; r14 <- src[(height-1)-i][(width-1)-j]
			movdqu xmm10, [r14] ; xmm10 = |p|p|p|p|

			pshufd xmm10, xmm10, 0x1b	; Invertimos el orden de los pixels

			movdqu xmm11, xmm10
			movdqu xmm8, [mask_b]
			pand xmm11, xmm8	; xmm11 = |0|0|0|bp|0|0|0|bp|0|0|0|bp|0|0|0|bp|

			movdqu xmm8, [mask_g]
			movdqu xmm12, xmm10  
			pand xmm12, xmm8	 ; xmm12 = |0|0|gp|0|0|0|gp|0|0|0|gp|0|0|0|gp|0|
			psrld xmm12, 8		 ; xmm12 = |0|0|0|gp|0|0|0|gp|0|0|0|gp|0|0|0|gp|

			movdqu xmm8, [mask_r]
			pand xmm10, xmm8   	; xmm10 = |0|rp|0|0|0|rp|0|0|0|rp|0|0|0|rp|0|0|
			psrld xmm10, 16    	; xmm10 = |0|0|0|rp|0|0|0|rp|0|0|0|rp|0|0|0|rp|

			;src[(height-1)-i][(width-1)-j] >> 2
			psrld xmm11, 2
			psrld xmm12, 2
			psrld xmm10, 2

			;src[(height-1)-i][(width-1)-j] >> 2 & 0x3
			pand xmm10, xmm4
			pand xmm11, xmm4
			pand xmm12, xmm4

			;(bitsB & 0x3) ^ (src[(height-1)-i][(width-1)-j].b >> 2 & 0x3)
			pxor xmm11, xmm6 
			;(bitsG & 0x3) ^ (src[(height-1)-i][(width-1)-j].g >> 2 & 0x3)
			pxor xmm12, xmm7
			;(bitsR & 0x3) ^ (src[(height-1)-i][(width-1)-j].r >> 2 & 0x3)
			pxor xmm10, xmm0

			;(src[i][j].b & OxFC) + (bitsB & 0x3) ^ (src[(height-1)-i][(width-1)-j].b >> 2 & 0x3)
			paddsw xmm1, xmm11		; xmm1 = |0|0|0|bp1|0|0|0|bp2|0|0|0|bp3|0|0|0|bp4|
			;(src[i][j].g & OxFC) + (bitsG & 0x3) ^ (src[(height-1)-i][(width-1)-j].g >> 2 & 0x3)
			paddsw xmm2, xmm12		; xmm2 = |0|0|0|gp1|0|0|0|gp2|0|0|0|gp3|0|0|0|gp4|
			;(src[i][j].r & OxFC) + (bitsR & 0x3) ^ (src[(height-1)-i][(width-1)-j].r >> 2 & 0x3)
			paddsw xmm9, xmm10		; xmm9 = |0|0|0|rp1|0|0|0|rp2|0|0|0|rp3|0|0|0|rp4|

			pslld xmm2, 8
			pslld xmm9, 16
			por xmm1, xmm2
			por xmm1, xmm9

			movdqu [r15], xmm1

			; Seteo las componentes de transparencia en 255 en dst
			mov byte [r15 + 3], 255
			mov byte [r15 + 7], 255
			mov byte [r15 + 11], 255
			mov byte [r15 + 15], 255
			
			; Avanzo
			add rsi, 16 ; Apuntamos los siguientes 4 pixels en src2 (4 pixeles de 4 bytes)
			add r15, 16	; Apuntamos los siguientes 4 pixels en dst
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

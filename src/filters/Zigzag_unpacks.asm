global Zigzag_asm

section .rodata
	mask_b: 	times 4 DB 0xFF, 0x00, 0x00, 0x00    
	mask_g: 	times 4 DB 0x00, 0xFF, 0x00, 0x00
	mask_r: 	times 4 DB 0x00, 0x00, 0xFF, 0x00
	mask_alpha: times 4 DB 0x00, 0x00, 0x00, 0xFF ; Máscara para setear transparencia en 255
	
	cinco:  	DD 5.0, 5.0, 5.0, 5.0
	filtrar_b: 	DD 0xFFFFFFFF, 0x0, 0x0, 0x0
	filtrar_g: 	DD 0x0, 0xFFFFFFFF, 0x0, 0x0
	filtrar_r: 	DD 0x0, 0x0, 0xFFFFFFFF, 0x0

	blanco_32: 	DB 0xFF, 0xFF, 0xFF, 0xFF
	blanco_64: 	times 2 DB 0xFF, 0xFF, 0xFF, 0xFF

section .text
;void Zigzag_c(
;    uint8_t *src, uint8_t *dst,
;    int width, int height,
;    int src_row_size, int dst_row_size)

; rdi <- src
; rsi <- dst
; rdx <- width (cantidad columnas)
; rcx <- height (cantidad filas)
; r8 <- src_row_size
; r9 <- dst_row_size

	; Por cada columna y por cada fila recorriendo dejando un marco de 2 pixeles 
	; i <- [2...height-2], j <- [2... width-2]
	; separo las operaciones en casos 
	; uso div, dividendo(rax) divisor(r/m), el resto se guarda en rdx
	; si la fila i mod 4 es 0 o 2 
	; si la fila i mod 4 es 1 
	; si la fila mod 4 es 3
Zigzag_asm:
	%define i r13
	%define j r14
	push rbp
	mov rbp, rsp
	push r12
	push r13
	push r14
	push r15
	push rbx
	sub rsp, 8

	mov r15, 4		; Para calcular "i mod 4" 

	mov r12, rdx 	; r12 <- cantColumnas

	; Rellenar borde superior de blanco
	mov j, 0
	.blanquearSiguienteColumnaSuperior:
		cmp j, r12 
		je .aplicarFiltro ; j = width?

		mov eax, [blanco_32]
		mov dword [rsi], eax		; dst[0][j] = rgba(255,255,255,255)  
		mov dword [rsi + r9], eax	; dst[1][j] = rgba(255,255,255,255)	

		add rsi, 4
		inc j
		jmp .blanquearSiguienteColumnaSuperior		

	; Comenzar a aplicar el filtro
	.aplicarFiltro:
		sub r12, 2 		; r12 <- width-2
		sub rcx, 2 		; rcx <- height-2 

		lea rdi, [rdi + 2 * r8] ; Apuntamos al primer pixel de la tercer fila
		lea rsi, [rsi + r9] 	; Apuntamos al primer pixel de la tercer fila

		mov i, 2
		.procesarSiguienteFila:
			cmp i, rcx
			je .terminarFiltro	; i = height-2?
			
			; Rellenar con blanco dos primeros pixeles de la fila
			mov rax, [blanco_64]
			mov [rsi], rax  
			add rsi, 8

			mov j, 2
			.procesarSiguienteColumna:
				cmp j, r12
				je .finalizarFila ; j = width-2?

				;Tomamos los pixels
				movdqu xmm0, [rdi] 		; xmm0 = |p3|p2|p1|p0| = |a3|r3|g3|b3|a2|r2|g2|b2|a1|r1|g1|b1|a0|r0|g0|b0|
				
				; Tomamos los pixels siguientes
				lea rbx, [rdi + 16] ; rbx apunta a p4
				movdqu xmm4, [rbx] 		; xmm4 = |p7|p6|p5|p4|

				; Calculamos "i mod 4"
				xor rdx, rdx
				mov rax, i
				div r15 ; rdx <- resto
			
				; i mod 4 = 1?
				cmp rdx, 1 	 
				je .copiarAIzq
			
				; i mod 4 = 3?
				cmp rdx, 3	
				je .copiarADer
			
				; CASOS "i mod 4 = 0" o " i mod 4 = 2"

				; Separamos componente AZUL de primeros 4 pixels
				movdqu xmm1, xmm0
				movdqu xmm8, [mask_b] 
				pand xmm1, xmm8 		; xmm1 = |0|0|0|bp3|0|0|0|bp2|0|0|0|bp1|0|0|0|bp0|
				
				; Separamos componente VERDE de primeros 4 pixels
				movdqu xmm2, xmm0
				movdqu xmm8,[mask_g] 
				pand xmm2, xmm8 		; xmm2 = |0|0|gp3|0|0|0|gp2|0|0|0|gp1|0|0|0|gp0|0|
				psrld xmm2, 8	  		; xmm2 = |0|0|0|gp3|0|0|0|gp2|0|0|0|gp1|0|0|0|gp0|
				
				; Separamos componente ROJO de primeros pixels
				movdqu xmm3, xmm0
				movdqu xmm8, [mask_r]
				pand xmm3, xmm8 		; xmm3 = |0|rp3|0|0|0|rp2|0|0|0|rp1|0|0|0|rp0|0|0|
				psrld xmm3, 16 	  		; xmm3 = |0|0|0|rp3|0|0|0|rp2|0|0|0|rp1|0|0|0|rp0|

				; Tomamos y separamos componentes del quinto pixel
				;pmovzxbd xmm5, xmm4		; xmm5 = |0|0|0|p4.a|0|0|0|p4.r|0|0|0|p4.g|0|0|0|p4.b|
				movdqu xmm5, xmm4
				pxor xmm11, xmm11
				punpcklbw xmm5, xmm11     ; |0|p5.a|0|p5.r|0|p5.g|0|p5.b|0|p4.a|0|p4.r|0|p4.g|0|p4.b|  
				punpcklwd xmm5, xmm11

				;Shiftear p5 a la parte baja en xmm4 
				psrldq xmm4, 4 ; xmm4 = |0|p7|p6|p5|

				; Tomamos y separamos componentes del sexto pixel 
				;pmovzxbd xmm6, xmm4     ; xmm6 = |0|0|0|p5a|0|0|0|p5.r|0|0|0|p5.g|0|0|0|p5.b|
				movdqu xmm6, xmm4 
				punpcklbw xmm6, xmm11    ; xmm6 = |0|p6.a|0|p6.r|0|p6.g|0|p6.b|0|p5.a|0|p5.r|0|p5.g|0|p5.b|  
				punpcklwd xmm6, xmm11	 ; xmm6 = |0|0|0|p5a|0|0|0|p5.r|0|0|0|p5.g|0|0|0|p5.b|	

				; Tomamos y separamos componentes del primer pixel
				;pmovzxbd xmm9, xmm0 ; xmm9 = |0|0|0|p0.a|0|0|0|p0.r|0|0|0|p0.g|0|0|0|p0.b|
				movdqu xmm9, xmm0
				punpcklbw xmm9, xmm11     ; |0|p1.a|0|p1.r|0|p1.g|0|p1.b|0|p0.a|0|p0.r|0|p0.g|0|p0.b|  
				punpcklwd xmm9, xmm11

				phaddd xmm1, xmm1 		; xmm1 =  |bp3+bp2|bp1+bp0|bp3+bp2|bp1+bp0|
				phaddd xmm1, xmm1 		; xmm1 =  |=|=|=|bp3+bp2+bp1+bp0|	

				phaddd xmm2, xmm2 		; xmm2 =  |gp3+gp2|gp1+gp0|gp3+gp2|gp1+gp0|
				phaddd xmm2, xmm2 		; xmm2 =  |=|=|=|gp3+gp2+gp1+gp0|

				phaddd xmm3, xmm3 		; xmm3 = |rp3+rp2|rp1+rp0|rp3+rp2|rp1+rp0|
				phaddd xmm3, xmm3 		; xmm3 = |=|=|=|rp3+rp2+rp1+rp0|

				movdqu xmm7, [filtrar_r]
				pand xmm3, xmm7 		; xmm3 = |0x0|rp3+rp2+rp1+rp0|0x0|0x0|

				movdqu xmm7, [filtrar_g]
				pand xmm2, xmm7 		; xmm2 = |0x0|0x0|gp3+gp2+gp1+gp0|0x0|

				movdqu xmm7, [filtrar_b]
				pand xmm1, xmm7 		; xmm1 = |0x0|0x0|0x0|bp3+bp2+bp1+bp0|

				por xmm3, xmm2 			
				por xmm3, xmm1 			; xmm3 = |0x0|rp3+rp2+rp1+rp0|gp3+gp2+gp1+gp0|bp3+bp2+bp1+bp0|

				movdqu xmm4, xmm3       ; xmm4 = |0x0|rp3+rp2+rp1+rp0|gp3+gp2+gp1+gp0|bp3+bp2+bp1+bp0|
				psubd xmm4, xmm9		; xmm4 = |0x0|rp3+rp2+rp1|gp3+gp2+gp1|bp3+bp2+bp1|
				paddd xmm6, xmm5        ; xmm6 = |0x0|p5.a+p4.a|p5.r+p4.r|p5.g+p4.g|p5.b+p4.b|
				paddd xmm4, xmm6        ; xmm4 = |0x0|suma(r(p5,p4,p3,p2,p1))|suma(g(p5,p4,p3,p2,p1))|suma(b(p5,p4,p3,p2,p1))|

				paddd xmm3, xmm5		; xmm3 = |0x0|suma(r(p4,p3,p2,p1,p0))|suma(g(p4,p3,p2,p1,p0))|suma(b(p4,p3,p2,p1,p0))|

				cvtdq2ps xmm4, xmm4     ; Todo en floats 
				movdqu xmm8, [cinco]
				divps xmm4, xmm8		;  xmm4 = |0x0|suma(r(p5,p4,p3,p2,p1))/5|suma(g(p5,p4,p3,p2,p1))/5|suma(b(p5,p4,p3,p2,p1))/5|
				cvtps2dq xmm4, xmm4		; Volvemos a enteros

				cvtdq2ps xmm3, xmm3     ; Todo en floats 
				movdqu xmm8, [cinco]
				divps xmm3, xmm8		;  xmm3 = |0x0|suma(r(p4,p3,p2,p1,p0))/5|suma(g(p4,p3,p2,p1,p0))/5|suma(b(p4,p3,p2,p1,p0))/5|
				cvtps2dq xmm3, xmm3		; Volvemos a enteros

				packusdw xmm3, xmm4		; xmm3 = |0x0|res1(R)|res1(G)|res1(B)|0x0|res0(R)|res0(G)|res0(B)|
				packuswb xmm3, xmm3 	; xmm3 = |0x0|res1(R,G,B)|0x0|res0(R,G,B)|0x0|res1(R,G,B)|0x0|res0(R,G,B)|


				movq [rsi], xmm3

				
				mov byte [rsi + 3], 255	; dst[i][j].a = 255
				mov byte [rsi + 7], 255  ; dst[i][j+1].a = 255

				add rsi, 4	; Siguiente pixel de src
				add rdi, 4 	; Siguiente pixel de dst
				inc j
				jmp .procesarSiguienteColumna

				; CASO "i mod 4 = 1"
				.copiarAIzq:
					; dst[i][j] = src[i][j-2]
					movdqu [rsi], xmm0
					jmp .finalizarColumna

				; CASO "i mod 4 = 3"
				.copiarADer:
					; dst[i][j] = src[i][j+2]
					movdqu [rsi], xmm4
					
				.finalizarColumna:
					
					; dst[i][j].a = dst[i][j+1].a = dst[i][j+2].a = dst[i][j+3].a = 255
					movdqu xmm14, [rsi]			; xmm15 = |a|r|g|b|a|r|g|b|a|r|g|b|a|r|g|b|
					movdqu xmm15, [mask_alpha]
					por xmm14, xmm15			; xmm15 = |255|r|g|b|255|r|g|b|255|r|g|b|255|r|g|b|
					movdqu [rsi], xmm14
					
					add j, 4
					add rsi, 16
					add rdi, 16
					jmp .procesarSiguienteColumna 
			
			.finalizarFila:
				; Rellenar con blanco dos ultimos pixeles de la fila
				mov rax, [blanco_64]
				mov [rsi], rax 
				add rsi, 8	
				
				add rdi, 16	; Terminamos en src[i][width - 4], arrancamos en src[i+1][0]

				inc i
				jmp .procesarSiguienteFila
				
		.terminarFiltro:

			; Rellenar borde inferior de blanco
			add r12, 2	; Sumamos 2 porque r12 = width - 2
			mov j, 0
			.blanquearSiguienteColumnaInferior:
				cmp j, r12 
				je .fin ; j = width?

				mov eax, [blanco_32]
				mov dword [rsi], eax		; dst[height-2][j] = rgba(255,255,255,255)  
				mov dword [rsi + r9], eax	; dst[height-1][j] = rgba(255,255,255,255)

				add rsi, 4
				inc j
				jmp .blanquearSiguienteColumnaInferior	

		.fin:
			add rsp, 8
			pop rbx
			pop r15
			pop r14
			pop r13
			pop r12
			pop rbp
			ret

            .INCLUDE <m328pdef.inc>

                                            ; Keyboard input emulation for testing.
                                            ; In this mode, the controller reads numerical strings and
;            .EQU EMULKEYPD=1                ; translates them into MM74C922 encoder codes, simulating button presses.

                                            ; Under the stack: 3 floating-point variables, each 4 bytes.
                                            ; 16 bytes for ASCII codes of pressed keys,
            .EQU SP=RAMEND-(3*4+16+256)     ; and 256 bytes for an ASCII string.
            .EQU LCDLEN=16                  ; Maximum length of the visible string in the LCD.
;            .EQU LCDLEN=40                  ; Temporary limit increase to check overflow handling in ATOF.

            .DEF S=R0                       ; Number of characters used in the current LCD line.
            .DEF P=R1                       ; Operand index, lies in the range [0,1].
            .DEF KEY=R2                     ; ASCII code of the pressed key.
            .DEF LCDLIM=R3                  ; Maximum number of characters to show on LCD (can change in different contexts).

            .DEF RETL=R22                   ; The return address is backed up here after an interrupt.
            .DEF RETH=R23                   ;

            .DSEG

.IFDEF EMULKEYPD
            .ORG 0x012A                     ; Start of the table mapping ASCII codes to encoder codes. The table occupies addresses in the range [0x012A,0x0143].
REVKEYMAP:  .BYTE 26                        ; The lower byte of the address corresponds to the ASCII code of the key. The smallest key code is 0x2A('*'), and the largest is 0x43('C').
.ENDIF

            .ORG SP+1                       ;
A:          .BYTE 4                         ; 0x07E4. Operand A.
B:          .BYTE 4                         ; 0x07E8. Operand B.
C:          .BYTE 4                         ; 0x07EC. Result C.
KEYMAP:     .BYTE 16                        ; 0x07F0. Table of ASCII characters of pressed keys.
NUMSTR:     .BYTE 256                       ; 0x0800. Pointer to the numeric ASCII string in SRAM.

            .CSEG
            .ORG 0x00

            JMP RESET
            JMP KEYPAD
            
            .INCLUDE "lcd1602.asm"
            .INCLUDE "float32avr.asm"

;
; Keyboard interrupt handler.
KEYPAD:     IN KEY,PIND                     ; Raw key code is in the upper nibble of port D.
            LDI R17,0xF0                    ; Extract and shift it to the lower nibble.
            AND KEY,R17                     ;
            CLC                             ;
            ROR KEY                         ;
            ROR KEY                         ;
            ROR KEY                         ;
            ROR KEY                         ;

            LDI R17,LOW(KEYMAP)             ; Add the key code to the lower nibble of the ASCII character table address.
            OR R17,KEY                      ; Y=0x07F0|0x0X, 0x0X - key code in the range [0x00,0x0F].
            MOV YL,R17                      ;
            LDI YH,HIGH(KEYMAP)             ;

            LD KEY,Y                        ; KEY=ASCII(RAWKEY), RAWKEY - raw code from MM74C922.

.IFDEF EMULKEYPD
            POP RETH                        ; Backup return address from the interrupt.
            POP RETL                        ;
            POP R17                         ; Extract the address of the current state handler.
            POP R16                         ;
            PUSH ZL                         ; Backup pointer to the test numeric string used for input emulation.
            PUSH ZH                         ;
            MOV ZL,R16                      ; Move the address of the current state handler to Z.
            MOV ZH,R17                      ;
            IJMP                            ;
.ELSE
            POP RETH                        ; Backup return address from the interrupt.
            POP RETL                        ;
            POP ZH                          ; Extract the address of the current state handler.
            POP ZL                          ;
            IJMP                            ; Jump to the current state handler.
.ENDIF

            ;
            ; S0: Initial state before entering the first or second operand.
            ;
            ; Only numeric keys and minus are allowed.
S0:         LDI R16,'C'                     ;
            EOR R16,KEY                     ; KEY='C'?
            BREQ S0RESETIN                  ; Yes, reset input and return to the zero state.

            LDI R16,'-'                     ;
            EOR R16,KEY                     ; KEY='-'?
            BREQ S0MINUS                    ;

            LDI R16,'0'                     ;
            EOR R16,KEY                     ; KEY='0'?
            BREQ S0DIG0                     ;

            LDI R16,0xF0                    ; All digits from 1 to 9 in ASCII have the same upper nibble equal to 0x30.
            AND R16,KEY                     ; Other possible keys: '.','+','*','/', have the upper nibble equal to 0x20.
            LDI R17,0x30                    ;
            EOR R16,R17                     ; KEY=['1','9']?
            BREQ S0DIG19                    ;

            LDI R16,LOW(S0)                 ; An invalid key was pressed in this state.
            LDI R17,HIGH(S0)                ; S0->S0.
            RJMP S0END                      ; Ignore input and remain in the current state.

S0RESETIN:  JMP RESETINPUT                  ; Long jump as it cannot be reached directly from BREQ.

S0MINUS:    LDI R16,LOW(S2)                 ; S0->S2.
            LDI R17,HIGH(S2)                ;
            RJMP S0PRNTKEY                  ;

S0DIG0:     LDI R16,LOW(S1)                 ; S0->S1.
            LDI R17,HIGH(S1)                ;
            RJMP S0PRNTKEY                  ;

S0DIG19:    LDI R16,LOW(S4)                 ; S0->S4.
            LDI R17,HIGH(S4)                ;

S0PRNTKEY:  ST X+,KEY                       ; *NUMSTR=KEY.
            INC S                           ;

;
; NOTE: Disable interaction with LCD in keyboard emulation mode.
; The reason is that in keyboard emulation mode, after transmitting
; a control instruction to the LCD, the seventh bit may remain set on port B.
; This bit serves as the BUSY flag in read mode. However, since LCD emulation
; is not implemented, the state of port B does not reset. When the next LCD instruction is called,
; it might lead to an infinite wait for the BUSY flag to clear.
.IFNDEF EMULKEYPD
            PUSH S                          ; Backup registers that PRNTCHR may overwrite.
            PUSH R16                        ;
            PUSH R17                        ;
            MOV CHAR,KEY                    ; Display the pressed key on the LCD.
            RCALL PRNTCHR                   ;
            POP R17                         ;
            POP R16                         ;
            POP S                           ;
.ENDIF

.IFDEF EMULKEYPD
S0END:      POP ZH                          ; Restore pointer to the test numeric string.
            POP ZL                          ;
            PUSH R16                        ; Save the new state.
            PUSH R17                        ;
            PUSH RETL                       ; Restore return address from the interrupt.
            PUSH RETH                       ;
            RETI                            ;
.ELSE
S0END:      PUSH R16                        ; Save the new state.
            PUSH R17                        ;
            PUSH RETL                       ; Restore return address from the interrupt.
            PUSH RETH                       ;
            RETI                            ;
.ENDIF

            ;
            ; S1: Intermediate state after pressing zero.
            ;
            ; Only a decimal point or operator keys are allowed.
S1:         LDI R16,'C'                     ;
            EOR R16,KEY                     ; KEY='C'?
            BREQ S1RESETIN                  ;

            LDI R16,'.'                     ;
            EOR R16,KEY                     ; KEY='.'?
            BREQ S1DECPNT                   ;

            LDI R16,0xF0                    ; '+','-','*','/' in ASCII have the same high nibble: 0x20.
            AND R16,KEY                     ; '.' is excluded above.
            LDI R17,0x20                    ;
            EOR R16,R17                     ; KEY=['+','-','/']?
            BREQ S1OPERATOR                 ;
            LDI R16,'x'                     ; We replaced the multiplication symbol with 'x', which is in the last row of the ASCII table.
            EOR R16,KEY                     ; KEY='x'?
            BREQ S1OPERATOR                 ;

            LDI R16,LOW(S1)                 ;
            LDI R17,HIGH(S1)                ;
            RJMP S1END                      ;

S1RESETIN:  JMP RESETINPUT                  ; Long jump as BREQ can't reach directly.

S1DECPNT:   LDI R16,LOW(S3)                 ; S1->S3.
            LDI R17,HIGH(S3)                ;
            RJMP S1PRNTKEY                  ;

S1OPERATOR: LDI R16,2                       ;
            EOR R16,P                       ; Is the second operand input complete?
            BREQ S1OPERAND2                 ; Yes, proceed to float conversion and calculation.
            RJMP OPERAND1                   ; No, first operand entered, convert it to float.

S1OPERAND2: JMP OPERAND2                    ; Long jump.

S1PRNTKEY:  ST X+,KEY                       ; *NUMSTR=KEY.
            INC S                           ;

.IFNDEF EMULKEYPD
            PUSH S                          ;
            PUSH R16                        ;
            PUSH R17                        ;
            MOV CHAR,KEY                    ; Display the pressed key on the LCD.
            RCALL PRNTCHR                   ;
            POP R17                         ;
            POP R16                         ;
            POP S                           ;
.ENDIF
          
.IFDEF EMULKEYPD
S1END:      POP ZH                          ; Restore pointer to the test numeric string.
            POP ZL                          ;
            PUSH R16                        ; Save the new state.
            PUSH R17                        ;
            PUSH RETL                       ; Restore return address from the interrupt.
            PUSH RETH                       ;
            RETI                            ;
.ELSE
S1END:      PUSH R16                        ;
            PUSH R17                        ;
            PUSH RETL                       ;
            PUSH RETH                       ;
            RETI                            ;
.ENDIF

            ;
            ; S2: Intermediate state after pressing minus.
            ;
            ; Only numeric keys are allowed.
S2:         LDI R16,'C'                     ;
            EOR R16,KEY                     ; KEY='C'?
            BREQ RESETINPUT                 ;
            
            LDI R16,'0'                     ;
            EOR R16,KEY                     ; KEY='0'?
            BREQ S2DIG0                     ;

            LDI R16,0xF0                    ;
            AND R16,KEY                     ;
            LDI R17,0x30                    ;
            EOR R16,R17                     ; KEY=['1','9']?
            BREQ S2DIG19                    ;

            LDI R16,LOW(S2)                 ;
            LDI R17,HIGH(S2)                ;
            RJMP S2END                      ;

S2DIG0:     LDI R16,LOW(S1)                 ; S2->S1.
            LDI R17,HIGH(S1)                ;
            RJMP S2PRNTKEY                  ;

S2DIG19:    LDI R16,LOW(S4)                 ; S2->S4.
            LDI R17,HIGH(S4)                ;

S2PRNTKEY:  ST X+,KEY                       ; *NUMSTR=KEY.
            INC S                           ;

.IFNDEF EMULKEYPD
            PUSH S                          ;
            PUSH R16                        ;
            PUSH R17                        ;
            MOV CHAR,KEY                    ; Display the pressed key on the LCD.
            RCALL PRNTCHR                   ;
            POP R17                         ;
            POP R16                         ;
            POP S                           ;
.ENDIF

.IFDEF EMULKEYPD
S2END:      POP ZH                          ; Restore pointer to the test numeric string.
            POP ZL                          ;
            PUSH R16                        ; Save the new state.
            PUSH R17                        ;
            PUSH RETL                       ; Restore return address from the interrupt.
            PUSH RETH                       ;
            RETI                            ;
.ELSE
S2END:      PUSH R16                        ;
            PUSH R17                        ;
            PUSH RETL                       ;
            PUSH RETH                       ;
            RETI                            ;
.ENDIF

            ;
            ; Reset input when the 'C' key is pressed.
RESETINPUT:
.IFDEF EMULKEYPD
            POP ZH                          ; Restore the pointer to the test numeric string.
            POP ZL                          ;
.ENDIF
            LDI R16,2                       ;
            EOR R16,P                       ; Was the reset pressed during the input of the second operand?
            BRNE RESET1                     ; No, we are still in the phase of entering the first operand (before pressing the operator key).
            POP R16                         ; Yes, the first operand has already been entered, and the stack contains: the operator character
            POP R16                         ; and four bytes of the first operand in float32 format.
            POP R16                         ; Discard the 4 bytes of the first operand.
            POP R16                         ;
            POP R16                         ; Discard the operator character. The stack is now empty.

RESET1:     LDI XL,LOW(NUMSTR)              ; Move the NUMSTR pointer to the beginning of the string.
            LDI XH,HIGH(NUMSTR)             ;

            LDI R16,0                       ; S=0.
            MOV S,R16                       ;

            LDI R16,1                       ; P=1.
            MOV P,R16                       ;

            LDI R16,LCDLEN-1                ; Reserve the last character of the first line for the operator symbol.
            MOV LCDLIM,R16                  ;

            LDI R16,LOW(S0)                 ; Initial state - S0.
            LDI R17,HIGH(S0)                ;
            PUSH R16                        ;
            PUSH R17                        ;
            PUSH RETL                       ;
            PUSH RETH                       ;

.IFNDEF EMULKEYPD
            RCALL CLEARLCD                  ;
            RCALL ENBLCURS                  ;
.ENDIF
            RETI                            ;

            ;
            ; The input of the first operand is complete.
.IFDEF EMULKEYPD
OPERAND1:   POP ZH                          ; Temporarily restore the pointer to the test numeric string.
            POP ZL                          ;
            PUSH KEY                        ; Save the pressed arithmetic operator at the bottom of the stack.
            PUSH ZL                         ; Place the pointer to the string on top.
            PUSH ZH                         ;
.ELSE
OPERAND1:   PUSH KEY                        ; Save the pressed arithmetic operator at the bottom of the stack.
.ENDIF
            LDI R16,0                       ; *NUMSTR='\0'.
            ST X,R16                        ;

            LDI XL,LOW(NUMSTR)              ; Return the pointer to the start of the string
            LDI XH,HIGH(NUMSTR)             ; before calling ATOF.

            ;
            ; Error handler for floating-point calculations performed inside ATOF.
            ;
            ; Due to current input limitations: only decimal fractions, no exponential notation,
            ; overflow cannot occur during ATOF, and division by zero in ATOF is impossible in principle.
            ;
            ; But if the input method is updated, then an overflow is possible during conversion,
            ; when single precision becomes insufficient during intermediate calculations.
            ;
            ; TODO: Add error message output to the LCD.
            ; For the first version, this is not critical, as the input is limited and exceptions in ATOF cannot occur.
            LDI ZL,LOW(OP1FLTERR0)          ;
            LDI ZH,HIGH(OP1FLTERR0)         ;
            RJMP OP1CNVRT                   ;
OP1FLTERR0: POP R16                         ; Discard the return address after ATOF from the stack.
            POP R16                         ;
            POP RETH                        ; Restore the return address from the interrupt.
            POP RETL                        ;
            POP KEY                         ; KEY was saved before ATOF - discard it.
.IFDEF EMULKEYPD
            POP ZH                          ; If in keyboard emulation mode,
            POP ZL                          ; restore the pointer to the test numeric string.
.ENDIF
            POP R16                         ; The operator symbol at the bottom of the stack is no longer needed.

            LDI XL,LOW(NUMSTR)              ; NUMSTR="ERR".
            LDI XH,HIGH(NUMSTR)             ;
            LDI R16,'E'                     ;
            ST X+,R16                       ;
            LDI R16,'R'                     ;
            ST X+,R16                       ;
            ST X+,R16                       ;
            CLR R16                         ;
            ST X,R16                        ; NUMSTR+='\0'.

            LDI R16,LOW(SHOWRES)            ; An exception occurred while entering the first operand,
            LDI R17,HIGH(SHOWRES)           ; further input is pointless, show an error message.
            RJMP OP1END                     ;

OP1CNVRT:   PUSH KEY                        ; Although KEY is already on the stack, it will be needed later for LCD output.
            PUSH RETL                       ; We are still inside an interrupt handler, so it is essential
            PUSH RETH                       ; not to lose the correct return address.
            CALL ATOF                       ;
            POP RETH                        ;
            POP RETL                        ;
            POP KEY                         ;

.IFDEF EMULKEYPD
            POP ZH                          ; Restore the pointer to the test numeric string.
            POP ZL                          ;
.ENDIF
            PUSH R11                        ; The first operand has been entered and converted to float32.
            PUSH R10                        ; Save it on the stack in little-endian.
            PUSH R9                         ;
            PUSH R8                         ;

            LDI XL,LOW(NUMSTR)              ; Reset the string pointer to the beginning.
            LDI XH,HIGH(NUMSTR)             ;

            CLR S                           ; Reset the entered character counter.
            LDI R16,2                       ; Next, the second operand will be entered.
            MOV P,R16                       ;
            LDI R16,LCDLEN                  ; When entering the second operand, there's no need to reserve a character for the operator at the end of the string,
            MOV LCDLIM,R16                  ; so the entire LCD line is allocated for the number (visible part).

.IFNDEF EMULKEYPD
            RCALL CURSL1END                 ; Place the cursor at the end of the visible part of the first LCD line.
            PUSH S                          ;
            MOV CHAR,KEY                    ; Output the operator symbol to the LCD.
            RCALL PRNTCHR                   ;
            POP S                           ;
            RCALL CURSL2BEG                 ; Place the cursor at the beginning of the second LCD line.
.ENDIF

            LDI R16,LOW(S0)                 ; Entering the second operand is identical to entering the first.
            LDI R17,HIGH(S0)                ;
OP1END:     PUSH R16                        ;
            PUSH R17                        ;
            PUSH RETL                       ;
            PUSH RETH                       ;
            RETI                            ;

            ;
            ; The entry of the second operand is completed.
OPERAND2:   LDI R16,0                       ; *NUMSTR='\0'.
            ST X,R16                        ;

            LDI XL,LOW(NUMSTR)              ; Return the pointer to the start of the string
            LDI XH,HIGH(NUMSTR)             ; before calling ATOF.

            ;
            ; Error handler for floating-point calculations performed inside ATOF.
            ;
            ; Due to current input limitations: only decimal fractions, no exponential notation,
            ; overflow cannot occur during ATOF, and division by zero in ATOF is impossible in principle.
            ;
            ; But if the input method is updated, then an overflow is possible during conversion,
            ; when single precision becomes insufficient during intermediate calculations.
            ;
            ; TODO: Add error message output to the LCD.
            ; For the first version, this is not critical, as the input is limited and exceptions in ATOF cannot occur.
            LDI ZL,LOW(OP2FLTERR0)          ;
            LDI ZH,HIGH(OP2FLTERR0)         ;
            RJMP OP2CONVERT                 ;
OP2FLTERR0: POP R16                         ; Discard the return address after ATOF from the stack.
            POP R16                         ;
            POP RETH                        ; Restore the return address from the interrupt.
            POP RETL                        ;
.IFDEF EMULKEYPD
            POP ZH                          ; If in keyboard emulation mode,
            POP ZL                          ; restore the pointer to the test numeric string.
.ENDIF
            LDI YL,LOW(SP)                  ; The stack contains 4 bytes of the first operand in float32 format
            LDI YH,HIGH(SP)                 ; and one byte of the arithmetic operator symbol.
            OUT SPL,YL                      ; Since an exception occurred and they are no longer needed,
            OUT SPH,YH                      ; simply reset the stack to its initial address.

            LDI XL,LOW(NUMSTR)              ; NUMSTR="ERR".
            LDI XH,HIGH(NUMSTR)             ;
            LDI R16,'E'                     ;
            ST X+,R16                       ;
            LDI R16,'R'                     ;
            ST X+,R16                       ;
            ST X+,R16                       ;
            CLR R16                         ;
            ST X,R16                        ; NUMSTR+='\0'.
            RJMP OP2END                     ;

OP2CONVERT: PUSH RETL                       ;
            PUSH RETH                       ;
            CALL ATOF                       ;
            POP RETH                        ;
            POP RETL                        ;

            MOV R12,R8                      ; Place the second entered operand
            MOV R13,R9                      ; as the second operand of the arithmetic operation.
            MOV R14,R10                     ;
            MOV R15,R11                     ;

.IFDEF EMULKEYPD
            POP R18                         ; Temporarily restore the pointer to the test numeric string.
            POP R17                         ;
.ENDIF
            POP R8                          ; Restore the first entered operand and place it
            POP R9                          ; as the first operand of the arithmetic operation.
            POP R10                         ;
            POP R11                         ;

            POP R16                         ; R16=OPERATOR.

.IFDEF EMULKEYPD
            PUSH R17                        ; Backup the pointer to the test numeric string again.
            PUSH R18                        ;
.ENDIF

            ;
            ; Error handler for arithmetic subroutines: FADD32, FSUB32, FMUL32, FDIV32.
            ;
            ; If the arithmetic operation is executed without overflow or division by zero,
            ; then subsequent conversion of the result by FTOA will not lead to either overflow or division by zero.
            ;
            ; Moreover, due to current input limitations: only decimal fractions, without exponential notation - 
            ; currently, during any arithmetic operation, only division by zero can occur.
            LDI ZL,LOW(OP2FLTERR1)          ; If an error occurs during FADD32, FSUB32, FMUL32, FDIV32
            LDI ZH,HIGH(OP2FLTERR1)         ; such as division by zero or overflow,
            RJMP OPCHK                      ; the execution will jump to this handler.
OP2FLTERR1: POP R16                         ; The return address from the subroutine that threw the exception
            POP R16                         ; is no longer of interest.
            POP RETH                        ; Restore the return address from the interrupt that was placed in the stack earlier.
            POP RETL                        ;
.IFDEF EMULKEYPD
            POP ZH                          ; If in keyboard emulation mode,
            POP ZL                          ; restore the pointer to the test numeric string.
.ENDIF

;
; In keyboard emulation mode, since the LCD is not used,
; display the error for visual control in SRAM.
.IFDEF EMULKEYPD
            LDI XL,LOW(NUMSTR)              ; NUMSTR="ERR".
            LDI XH,HIGH(NUMSTR)             ;
            LDI R16,'E'                     ;
            ST X+,R16                       ;
            LDI R16,'R'                     ;
            ST X+,R16                       ;
            ST X+,R16                       ;
            CLR R16                         ;
            ST X,R16                        ; NUMSTR+='\0'.
;
; Otherwise, display the error directly on the LCD.
.ELSE
            RCALL DSBLCURS                  ;
            RCALL CLEARLCD                  ;

            LDI R16,'E'                     ;
            MOV CHAR,R16                    ;
            RCALL PRNTCHR                   ; LCD+=E.
            LDI R16,'R'                     ;
            MOV CHAR,R16                    ;
            RCALL PRNTCHR                   ; LCD+=R.
            RCALL PRNTCHR                   ; LCD+=R.
.ENDIF
            RJMP OP2END                     ; End of exception handler OP2FLTERR1.

OPCHK:      LDI R17,'+'                     ;
            EOR R17,R16                     ;
            BREQ CALCADD                    ;

            LDI R17,'-'                     ;
            EOR R17,R16                     ;
            BREQ CALCSUB                    ;

            LDI R17,'x'                     ;
            EOR R17,R16                     ;
            BREQ CALCMUL                    ;

            LDI R17,'/'                     ;
            EOR R17,R16                     ;
            BREQ CALCDIV                    ;

CALCADD:    PUSH RETL                       ;
            PUSH RETH                       ;
            CALL FADD32                     ;
            POP RETH                        ;
            POP RETL                        ;
            RJMP RESULT                     ;

CALCSUB:    PUSH RETL                       ;
            PUSH RETH                       ;
            CALL FSUB32                     ;
            POP RETH                        ;
            POP RETL                        ;
            RJMP RESULT                     ;

CALCMUL:    PUSH RETL                       ;
            PUSH RETH                       ;
            CALL FMUL32                     ;
            POP RETH                        ;
            POP RETL                        ;
            RJMP RESULT                     ;

CALCDIV:    PUSH RETL                       ;
            PUSH RETH                       ;
            CALL FDIV32                     ;
            POP RETH                        ;
            POP RETL                        ;
            
RESULT:     LDI XL,LOW(NUMSTR)              ;
            LDI XH,HIGH(NUMSTR)             ;

            LDI R16,LCDLEN                  ; Set the MAXLEN argument of the FTOAE subroutine
            MOV R12,R16                     ; equal to the number of visible characters on the LCD.

            PUSH RETL                       ;
            PUSH RETH                       ;
            CALL FTOAE                      ; *NUMSTR=FTOAE(C,LCDLEN), where C is the computation result in float32,
            POP RETH                        ; and LCDLEN is the maximum output string length, equal to the LCD line length.
            POP RETL                        ;

.IFNDEF EMULKEYPD
            RCALL DSBLCURS                  ;
            RCALL CLEARLCD                  ;

            LDI XL,LOW(NUMSTR)              ; Shift the pointer to the start of the string containing the computation result.
            LDI XH,HIGH(NUMSTR)             ;
            RCALL PRNTSTR                   ; Output the string with the result to the LCD.
.ENDIF

.IFDEF EMULKEYPD
            POP ZH                          ; Restore the pointer to the test numeric string.
            POP ZL                          ;
.ENDIF
OP2END:     LDI R16,LOW(SHOWRES)            ; Result computed, new state: show result.
            LDI R17,HIGH(SHOWRES)           ;
            PUSH R16                        ;
            PUSH R17                        ;
            PUSH RETL                       ;
            PUSH RETH                       ;
            RETI                            ;

            ;
            ; SHOWRES - Idle state for displaying the result of the last calculation.
            ;
            ; Only the reset key is allowed.
SHOWRES:    LDI R16,'C'                     ;
            EOR R16,KEY                     ; Was the 'C' key pressed?
            BRNE STAY                       ; No, ignore the key press.
            JMP RESETINPUT                  ; Yes, reset the calculator to its initial state.

.IFDEF EMULKEYPD
STAY:       POP ZH                          ; Restore the pointer to the test numeric string.
            POP ZL                          ; Stack is empty.
            LDI R16,LOW(SHOWRES)            ;
            LDI R17,HIGH(SHOWRES)           ;
.ELSE
STAY:       LDI R16,LOW(SHOWRES)            ;
            LDI R17,HIGH(SHOWRES)           ;
.ENDIF
            PUSH R16                        ;
            PUSH R17                        ;
            PUSH RETL                       ;
            PUSH RETH                       ;
            RETI                            ;

            ;
            ; S3: Intermediate state after pressing the decimal point.
            ;
            ; Only numeric keys are allowed.
S3:         LDI R16,'C'                     ;
            EOR R16,KEY                     ;
            BREQ S3RESETIN                  ;

            LDI R16,0xF0                    ;
            AND R16,KEY                     ;
            LDI R17,0x30                    ;
            EOR R16,R17                     ; KEY=['0','9']?
            BREQ S3DIG09                    ;

            LDI R16,LOW(S3)                 ;
            LDI R17,HIGH(S3)                ;
            RJMP S3END                      ;

S3RESETIN:  JMP RESETINPUT                  ;

S3DIG09:    LDI R16,LOW(S5)                 ;
            LDI R17,HIGH(S5)                ;

            ST X+,KEY                       ;
            INC S                           ;

.IFNDEF EMULKEYPD
            PUSH S                          ;
            PUSH R16                        ;
            PUSH R17                        ;
            MOV CHAR,KEY                    ; Display the pressed key on the LCD.
            RCALL PRNTCHR                   ;
            POP R17                         ;
            POP R16                         ;
            POP S                           ;
.ENDIF

.IFDEF EMULKEYPD
S3END:      POP ZH                          ; Restore the pointer to the test numeric string.
            POP ZL                          ;
            PUSH R16                        ; Save the new state.
            PUSH R17                        ;
            PUSH RETL                       ; Restore the return address from the interrupt.
            PUSH RETH                       ;
            RETI                            ;
.ELSE
S3END:      PUSH R16                        ;
            PUSH R17                        ;
            PUSH RETL                       ;
            PUSH RETH                       ;
            RETI                            ;
.ENDIF

            ;
            ; S4: Input of the integer part.
            ;
            ; In this state, all keys are allowed, so there is no default behavior branch.
            ; If the decimal point key is pressed and only one space is available (just enough for the point),
            ; entering the point is ignored to avoid an invalid value with a trailing point like "123.".
S4:         LDI R16,'C'                     ;
            EOR R16,KEY                     ; KEY='C'?
            BREQ S4RESETIN                  ;

            LDI R16,'.'                     ;
            EOR R16,KEY                     ; KEY='.'?
            BREQ S4DECPNT                   ;

            LDI R16,0xF0                    ;
            AND R16,KEY                     ;
            LDI R17,0x30                    ;
            EOR R16,R17                     ; KEY=['0','9']?
            BREQ S4DIG09                    ;

            LDI R16,0xF0                    ;
            AND R16,KEY                     ;
            LDI R17,0x20                    ;
            EOR R16,R17                     ; KEY=['+','-','/']?
            BREQ S4OPERATOR                 ;
            LDI R16,'x'                     ;
            EOR R16,KEY                     ; KEY='x'?
            BREQ S4OPERATOR                 ;

S4SKIP:     LDI R16,LOW(S4)                 ; Ignore the key press, stay in the current state.
            LDI R17,HIGH(S4)                ;
            RJMP S4END                      ;

S4RESETIN:  JMP RESETINPUT                  ; Long jump.

S4DECPNT:   MOV R16,LCDLIM                  ; R16=(LCDLIM-2)-S.
            DEC R16                         ;
            DEC R16                         ;
            MOV R17,S                       ;
            COM R17                         ; To avoid a "trailing" decimal point situation, it is only allowed 
            INC R17                         ; if there is at least space for two more characters: the point itself and one digit after it.
            ADD R16,R17                     ; Is there space on the screen for a '.' and at least one more digit?
            BRMI S4SKIP                     ; No, ignore the decimal point press.
            LDI R16,LOW(S3)                 ; Yes, display the point and move to the new state.
            LDI R17,HIGH(S3)                ;
            RJMP S4PRNTKEY                  ;

S4DIG09:    MOV R16,S                       ; If S in the current interrupt is one less than LCDLIM, it will equal LCDLIM in the next interrupt.
            EOR R16,LCDLIM                  ; S<LCDLIM?
            BREQ S4SKIP                     ; No, cannot input more digits, ignore the key press.
            LDI R16,LOW(S4)                 ; Yes, display the digit and stay in the current state,
            LDI R17,HIGH(S4)                ; waiting for the next key press.
            RJMP S4PRNTKEY                  ;

S4OPERATOR: LDI R16,2                       ;
            EOR R16,P                       ; Is the second operand input complete?
            BREQ S4OPERAND2                 ; Yes, convert to float and calculate.
            RJMP OPERAND1                   ; No, the first operand is entered, convert it to float.

S4OPERAND2: JMP OPERAND2                    ;

S4PRNTKEY:  ST X+,KEY                       ;
            INC S                           ;

.IFNDEF EMULKEYPD
            PUSH S                          ;
            PUSH R16                        ;
            PUSH R17                        ;
            MOV CHAR,KEY                    ; Display the pressed key on the LCD.
            RCALL PRNTCHR                   ;
            POP R17                         ;
            POP R16                         ;
            POP S                           ;
.ENDIF

.IFDEF EMULKEYPD
S4END:      POP ZH                          ; Restore the pointer to the test numeric string.
            POP ZL                          ;
            PUSH R16                        ; Save the new state.
            PUSH R17                        ;
            PUSH RETL                       ; Restore the return address from the interrupt.
            PUSH RETH                       ;
            RETI                            ;
.ELSE
S4END:      PUSH R16                        ;
            PUSH R17                        ;
            PUSH RETL                       ;
            PUSH RETH                       ;
            RETI                            ;
.ENDIF

            ;
            ; S5: Input of the fractional part.
            ;
            ; All keys are allowed except the decimal point.
S5:         LDI R16,'C'                     ;
            EOR R16,KEY                     ; KEY='C'?
            BREQ S5RESETIN                  ;

            LDI R16,0xF0                    ;
            AND R16,KEY                     ;
            LDI R17,0x30                    ;
            EOR R16,R17                     ; KEY=['0','9']?
            BREQ S5DIG09                    ;

            LDI R16,'.'                     ; Decimal point is not allowed in this state.
            EOR R16,KEY                     ; KEY='.'?
            BREQ S5SKIP                     ; Yes, ignore the key press.

            LDI R16,0xF0                    ; The decimal point was excluded earlier
            AND R16,KEY                     ; because it also has 0x20 in the high nibble of ASCII -
            LDI R17,0x20                    ; now checking arithmetic operators using 0x20 is unambiguous.
            EOR R16,R17                     ; KEY=['+','-','/']?
            BREQ S5OPERATOR                 ;
            LDI R16,'x'                     ;
            EOR R16,KEY                     ; KEY='x'?
            BREQ S5OPERATOR                 ;

S5SKIP:     LDI R16,LOW(S5)                 ;
            LDI R17,HIGH(S5)                ;
            RJMP S5END                      ;

S5RESETIN:  JMP RESETINPUT                  ;

S5DIG09:    MOV R16,S                       ;
            EOR R16,LCDLIM                  ; S<LCDLIM?
            BREQ S5SKIP                     ; No, no more digits can be entered; ignore input.
            LDI R16,LOW(S5)                 ; Yes, display the digit and stay in the current state,
            LDI R17,HIGH(S5)                ; waiting for the next key press.
            RJMP S5PRNTKEY                  ;

S5OPERATOR: LDI R16,2                       ;
            EOR R16,P                       ; Has the second operand input finished?
            BREQ S5OPERAND2                 ; Yes, proceed to convert to float and calculate.
            RJMP OPERAND1                   ; No, the first operand was entered; convert it to float.

S5OPERAND2: JMP OPERAND2                    ; Long jump.

S5PRNTKEY:  ST X+,KEY                       ;
            INC S                           ;

.IFNDEF EMULKEYPD
            PUSH S                          ;
            PUSH R16                        ;
            PUSH R17                        ;
            MOV CHAR,KEY                    ; Display the pressed key on the LCD.
            RCALL PRNTCHR                   ;
            POP R17                         ;
            POP R16                         ;
            POP S                           ;
.ENDIF

.IFDEF EMULKEYPD
S5END:      POP ZH                          ; Restore the pointer to the test numeric string.
            POP ZL                          ;
            PUSH R16                        ; Save the new state.
            PUSH R17                        ;
            PUSH RETL                       ; Restore the return address from the interrupt.
            PUSH RETH                       ;
            RETI                            ;
.ELSE  
S5END:      PUSH R16                        ;
            PUSH R17                        ;
            PUSH RETL                       ;
            PUSH RETH                       ;
            RETI                            ;
.ENDIF

;
; Fresh start of the calculator.
RESET:      LDI YL,LOW(SP)                  ;
            LDI YH,HIGH(SP)                 ;
            OUT SPL,YL                      ;
            OUT SPH,YH                      ;

.IFNDEF EMULKEYPD
            RCALL INITLCD                   ;
.ENDIF

;
; Emulation of keyboard input for testing the interrupt handler.
;
; During keyboard input testing, configure Port D as output.
; This allows setting key code on the port and triggering an interrupt programmatically directly from the current code.
.IFDEF EMULKEYPD
            SER R16                         ; Configure Port D as output,
            OUT DDRD,R16                    ; to programmatically set the key code and trigger an INT0 interrupt.
            LDI R16,0x00                    ;
            OUT PORTD,R16                   ;
.ELSE
            CLR R16                         ;
            OUT DDRD,R16                    ;
.ENDIF

            LDI R16,(1<<ISC01|1<<ISC00)     ; Enable external interrupts
            STS EICRA,R16                   ; on INT0, triggered on a rising edge - where the keyboard is connected.
            LDI R16,(1<<INT0)               ;
            OUT EIMSK,R16                   ;
            SEI                             ;

            LDI ZL,LOW(KEYMAPPRG<<1)        ; Copy the ASCII key table from program memory to SRAM.
            LDI ZH,HIGH(KEYMAPPRG<<1)       ;
            LDI XL,LOW(KEYMAP)              ;
            LDI XH,HIGH(KEYMAP)             ;
READ:       LPM R0,Z+                       ;
            AND R0,R0                       ; NUL?
            BREQ MAIN                       ; Yes, all characters are loaded into SRAM.
            ST X+,R0                        ; No, write the character in SRAM and continue.
            RJMP READ                       ;

;
;
MAIN:       NOP
            
            ;
            ; Initial reset of the calculator.
            LDI XL,LOW(NUMSTR)              ; Set NUMSTR pointer to the beginning of the string.
            LDI XH,HIGH(NUMSTR)             ;

            LDI R16,0                       ; The number of entered characters S=0.
            MOV S,R16                       ;

            LDI R16,1                       ; Begin input from the first operand P=1.
            MOV P,R16                       ;

            LDI R16,LCDLEN-1                ; Reserve the last character of the first line for the operator symbol.
            MOV LCDLIM,R16                  ;

            LDI R16,LOW(S0)                 ; The initial state is S0.
            LDI R17,HIGH(S0)                ;
            PUSH R16                        ;
            PUSH R17                        ;
            
;
; Keyboard input emulation for testing the interrupt handler.
;
; Read each character of the numeric string from program memory,
; convert its ASCII code to the raw keyboard encoder code,
; set the code on Port D, and set the INT0 pin to high,
; triggering a keyboard interrupt programmatically.
.IFDEF EMULKEYPD
            ;
            ; Uncomment when testing the second operand input.
;            LDI R16,2                       ;
;            MOV P,R16                       ;

;            LDI R16,LCDLEN                  ;
;            MOV LCDLIM,R16                  ;

            ;
            ; Initialization of the reverse keymap table - mapping ASCII codes to raw encoder codes.
            ;
            ; The ASCII code is used as the lower byte of the SRAM address where the raw code is stored.
            ; Read the numeric string, convert each ASCII character to a raw key code,
            ; set this code on Port D, and trigger an INT0 interrupt after each character read.
            ; This emulates keyboard input programmatically.
            LDI R17,0x00                    ; Raw key code.
            LDI ZL,LOW(KEYMAPPRG << 1)      ; NOTE: The LSB of program memory address is used as a byte number: first or second,
            LDI ZH,HIGH(KEYMAPPRG << 1)     ; see datasheet for more information.
READ0:      LPM R4,Z+                       ;
            AND R4,R4                       ; Reached the end of the string?
            BREQ EMULINPUT                  ; Yes, the table is formed, proceed to keyboard input emulation.
            MOV YL,R4                       ; No, continue.
            LDI YH,HIGH(REVKEYMAP)          ;
            ST Y,R17                        ; Write the raw key code.
            INC R17                         ; Move to the next symbol.
            RJMP READ0                      ;

            ;
            ; Arithmetic expression input emulation.
            ;
            ; NOTE: During input testing, if an exception occurs after reading the first operand,
            ; despite generating an error message and transitioning to SHOWRES state, which
            ; ignores all input except the reset key, the emulation loop will continue
            ; reading the expression until the end of the string, triggering keyboard interrupts
            ; and entering SHOWRES. However, since the full arithmetic expression does not contain
            ; the 'C' key, no changes will occur in the calculator's state. The behavior will mimic
            ; a user encountering an error message and continuing to press numeric or operator keys, which the calculator ignores while waiting for the 'C' key.
            ; This simplifies the emulation code by allowing it to "read" the string to the end without additional checks, completing naturally.
EMULINPUT:  LDI ZL,LOW(TESTNUM << 1)        ;
            LDI ZH,HIGH(TESTNUM << 1)       ;
READ1:      LPM R4,Z+                       ;
            AND R4,R4                       ; Reached the end of the string?
            BREQ END                        ; Yes, the numeric string is "entered".
            MOV YL,R4                       ; No, map the ASCII symbol to encoder code.
            LDI YH,HIGH(REVKEYMAP)          ;
            LD R16,Y                        ;
            CLC                             ;
            ROL R16                         ; Place code bits in the high nibble of Port D.
            ROL R16                         ;
            ROL R16                         ;
            ROL R16                         ;
            LDI R17,0b00000100              ; Emulate the encoder's data ready bit,
            EOR R16,R17                     ; setting INT0 high - this triggers the interrupt.
            OUT PORTD,R16                   ;
            LDI R17,0b11111011              ; Clear the data ready bit, so the next iteration
            AND R16,R17                     ; can trigger another interrupt.
            OUT PORTD,R16                   ;
            RJMP READ1                      ;
.ENDIF

END:        RJMP END

;
; Table of ASCII codes for pressed keys.
KEYMAPPRG:  .DB "C0./789x456-123+",0

;
; Test cases for verifying correct keyboard input.
; The examples are defined in [State Graph and Test Examples.xmind].
; First come the "green" examples, containing valid numeric strings.
; Then, with a new numbering, follow the "yellow" examples, containing invalid numeric strings
; that must be ignored by the keyboard handler.
;
; NOTE: It hasn't been translated to preserve exact cyrillic matching with the aforementioned file.
.IFDEF EMULKEYPD
            ; Пример 1. Корректные значения.
;TESTNUM:  .DB "0.0123456789123",0

            ; Пример 2. Корректные значения. Второй операнд.
;TESTNUM:  .DB "0.01234567891234",0

            ; Пример 3. Корректные значения.
;TESTNUM:  .DB "0",0

            ; Пример 4. Корректные значения.
;TESTNUM:  .DB "7.0123456789123",0

            ; Пример 5. Корректные значения.
;TESTNUM:  .DB "1234567890123.0",0

            ; Пример 6. Корректные значения. Второй операнд.
;TESTNUM:  .DB "7.01234567891234",0

            ; Пример 7. Корректные значения. Второй операнд.
;TESTNUM:  .DB "12345678901234.9",0

            ; Пример 8. Корректные значения.
;TESTNUM:  .DB "123456789012345",0

            ; Пример 9. Корректные значения. Второй операнд.
;TESTNUM:  .DB "1234567890123456",0

            ; Пример 10. Корректные значения.
;TESTNUM:  .DB "3",0

            ; Пример 11. Корректные значения.
;TESTNUM:  .DB "-0.012345678912",0

            ; Пример 12. Корректные значения. Второй операнд.
;TESTNUM:  .DB "-0.0123456789123",0

            ; Пример 13. Корректные значения.
;TESTNUM:  .DB "-0",0

            ; Пример 14. Корректные значения.
;TESTNUM:  .DB "-7.012345678912",0

            ; Пример 15. Корректные значения.
;TESTNUM:  .DB "-123456789012.5",0

            ; Пример 16. Корректные значения. Второй операнд.
;TESTNUM:  .DB "-7.0123456789123",0

            ; Пример 17. Корректные значения. Второй операнд.
;TESTNUM:  .DB "-1234567890123.5",0

            ; Пример 18. Корректные значения.
;TESTNUM:  .DB "-12345678901234",0

            ; Пример 19. Корректные значения. Второй операнд.
;TESTNUM:  .DB "-123456789012345",0

            ; Пример 20. Корректные значения.
;TESTNUM:  .DB "-8",0


            ; Пример 1. Некорректные значения.
;TESTNUM:  .DB "0.01234567891234",0

            ; Пример 2. Некорректные значения. Второй операнд.
;TESTNUM:  .DB "0.012345678912345",0

            ; Пример 3. Некорректные значения.
;TESTNUM:  .DB "0.7.",0

            ; Пример 4. Некорректные значения.
;TESTNUM:  .DB "0..",0
;TESTNUM:  .DB "0.+",0

            ; Пример 5. Некорректные значения.
;TESTNUM:  .DB "01",0
;TESTNUM:  .DB "00",0

            ; Пример 6. Некорректные значения.
;TESTNUM:  .DB "7.01234567891234",0

            ; Пример 7. Некорректные значения.
;TESTNUM:  .DB "7.012345678912345",0

            ; Пример 8. Некорректные значения.
;TESTNUM:  .DB "1.0.",0

            ; Пример 9. Некорректные значения.
;TESTNUM:  .DB "4..",0
;TESTNUM:  .DB "4.*",0

            ; Пример 10. Некорректные значения.
;TESTNUM:  .DB "123456789012345.",0
;TESTNUM:  .DB "12345678901234.",0

            ; Пример 11. Некорректные значения. Второй операнд.
;TESTNUM:  .DB "1234567890123456.",0
;TESTNUM:  .DB "123456789012345.",0

            ; Пример 12. Некорректные значения.
;TESTNUM:  .DB "1234567890123456",0

            ; Пример 13. Некорректные значения. Второй операнд.
;TESTNUM:  .DB "12345678901234567",0

            ; Пример 14. Некорректные значения.
;TESTNUM:  .DB "-0.0123456789123",0

            ; Пример 15. Некорректные значения. Второй операнд.
;TESTNUM:  .DB "-0.01234567891234",0

            ; Пример 16. Некорректные значения.
;TESTNUM:  .DB "-0.0.",0

            ; Пример 17. Некорректные значения.
;TESTNUM:  .DB "-0..",0
;TESTNUM:  .DB "-0./",0

            ; Пример 18. Некорректные значения.
;TESTNUM:  .DB "-09",0
;TESTNUM:  .DB "-00",0

            ; Пример 19. Некорректные значения.
;TESTNUM:  .DB "-7.0123456789123",0

            ; Пример 20. Некорректные значения. Второй операнд.
;TESTNUM:  .DB "-7.01234567891234",0

            ; Пример 21. Некорректные значения.
;TESTNUM:  .DB "-9.0.",0

            ; Пример 22. Некорректные значения.
;TESTNUM:  .DB "-6..",0
;TESTNUM:  .DB "-6.+",0

            ; Пример 23. Некорректные значения.
;TESTNUM:  .DB "-12345678901234.",0
;TESTNUM:  .DB "-1234567890123.",0

            ; Пример 24. Некорректные значения. Второй операнд.
;TESTNUM:  .DB "-123456789012345.",0
;TESTNUM:  .DB "-12345678901234.",0

            ; Пример 25. Некорректные значения.
;TESTNUM:  .DB "-123456789012345",0

            ; Пример 26. Некорректные значения. Второй операнд.
;TESTNUM:  .DB "-1234567890123456",0

            ; Пример 27. Некорректные значения.
;TESTNUM:  .DB "-.",0
;TESTNUM:  .DB "--",0

            ; Пример 28. Некорректные значения.
;TESTNUM:  .DB ".",0
;TESTNUM:  .DB "/",0

            ;
            ; Пример 1. Обработка исключений. Исключение при делении на ноль.
;TESTNUM:  .DB "1/0+",0

            ;
            ; Пример 2. Обработка исключений. Переполнение в ATOF при конвертации второго операнда.
            ; NOTE: Для тестов нужно временно увеличить LCDLEN до 40 знаков,
            ; чтобы в первую строку вошло 39 десятичных разрядов (последний зарезервирован под символ оператора).
;TESTNUM:  .DB "1/340282430000000000000000000000000000000+",0

            ;
            ; Пример 3. Обработка исключений. Переполнение в ATOF при конвертации первого операнда.
            ; Для тестов нужно временно увеличить LCDLEN до 40 знаков.
;TESTNUM:  .DB "340282430000000000000000000000000000000/3.7+",0

            ;
            ; Пример 1. Арифметические выражения. Триггер вычисления.
;TESTNUM:  .DB "2+3+",0
;TESTNUM:  .DB "2+3-",0
;TESTNUM:  .DB "2+3*",0
;TESTNUM:  .DB "2+3/",0

            ;
            ; Пример 2. Арифметические выражения. Знаки операндов.
;TESTNUM:  .DB "10*7+",0

            ;
            ; Пример 3. Арифметические выражения. Знаки операндов.
;TESTNUM:  .DB "10*-7+",0

            ;
            ; Пример 4. Арифметические выражения. Знаки операндов.
;TESTNUM:  .DB "-10*7+",0

            ;
            ; Пример 5. Арифметические выражения. Знаки операндов.
;TESTNUM:  .DB "-10*-7+",0

            ;
            ; Пример 6. Арифметические выражения. Наименьшие значения операндов.
;TESTNUM:  .DB "0.0000000000001+0.00000000000001+",0

            ;
            ; Пример 7. Арифметические выражения. Наибольшие значения операндов.
;TESTNUM:  .DB "999999999999999+9999999999999999+",0

            ;
            ; Пример 8. Арифметические выражения. Наименьший результат.
;TESTNUM:  .DB "0.0000000000001/9999999999999999+",0

            ;
            ; Пример 9. Арифметические выражения. Наибольший результат.
;TESTNUM:  .DB "999999999999999*9999999999999999+",0

            ;
            ; Пример 10. Арифметические выражения. Арифметический оператор.
;TESTNUM:  .DB "9+1+",0

            ;
            ; Пример 11. Арифметические выражения. Арифметический оператор.
;TESTNUM:  .DB "10-1+",0

            ;
            ; Пример 12. Арифметические выражения. Арифметический оператор.
;TESTNUM:  .DB "3*2+",0

            ;
            ; Пример 13. Арифметические выражения. Арифметический оператор.
;TESTNUM:  .DB "1/2+",0

            ;
            ; Пример 14. Арифметические выражения. Нулевые операнды.
;TESTNUM:  .DB "5+0+",0

            ;
            ; Пример 15. Арифметические выражения. Нулевые операнды.
;TESTNUM:  .DB "0+5+",0

            ;
            ; Пример 16. Арифметические выражения. Нулевые операнды.
;TESTNUM:  .DB "5-0+",0

            ;
            ; Пример 17. Арифметические выражения. Нулевые операнды.
;TESTNUM:  .DB "0-5+",0

            ;
            ; Пример 18. Арифметические выражения. Нулевые операнды.
;TESTNUM:  .DB "5*0+",0

            ;
            ; Пример 19. Арифметические выражения. Нулевые операнды.
;TESTNUM:  .DB "0*5+",0

            ;
            ; Пример 20. Арифметические выражения. Нулевые операнды.
;TESTNUM:  .DB "5/0+",0

            ;
            ; Пример 21. Арифметические выражения. Нулевые операнды.
;TESTNUM:  .DB "0/5+",0

            ;
            ; Пример 22. Арифметические выражения. Нулевые операнды.
;TESTNUM:  .DB "-0+5+",0

            ;
            ; Пример 23. Арифметические выражения. Нулевые операнды.
;TESTNUM:  .DB "0/0+",0
            
            ;
            ; Пример 24. Арифметические выражения. Случайный Пример.
;TESTNUM:  .DB "301.9533944630/23204.0642586600+",0

            ;
            ; Пример 1. Проверка сброса в состоянии S0.
            ; NOTE: См. граф состояний, чтобы понять,
            ; какие клавиши в какие состояния переводят калькулятор.
;TESTNUM:  .DB "C",0

            ;
            ; Пример 2. Проверка сброса в состоянии S1.
;TESTNUM:  .DB "0C",0

            ;
            ; Пример 3. Проверка сброса в состоянии S2.
;TESTNUM:  .DB "-C",0

            ;
            ; Пример 4. Проверка сброса в состоянии S3.
;TESTNUM:  .DB "1.C",0
            
            ;
            ; Пример 5. Проверка сброса в состоянии S4.
;TESTNUM:  .DB "1C",0

            ;
            ; Пример 6. Проверка сброса в состоянии S5 - фаза ввода первого операнда.
;TESTNUM:  .DB "1.2C",0

            ;
            ; Пример 7. Проверка сброса в состоянии SHOWRES без ошибки.
;TESTNUM:  .DB "1.5*2+C",0

            ;
            ; Пример 7. Проверка сброса в состоянии SHOWRES после ошибки.
            ; NOTE: При вычислении результата произошла ошибка.
;TESTNUM:  .DB "1/0+C",0

            ;
            ; Пример 8. Проверка сброса после ввода первого операнда и оператора - фаза ввода второго операнда.
            ; NOTE: В этом сценарии в стеке уже лежит первый операнд в формате float32 и символ оператора.
            ; Этот тест проверяет, что после сброса стек очищается.
;TESTNUM:  .DB "15+C",0
.ENDIF

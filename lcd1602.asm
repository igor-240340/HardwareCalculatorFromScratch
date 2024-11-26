;
; LCD1602-HD44780-AVR - a library for interfacing with the monochrome LCD1602 display based on the HD44780 controller.
;
; Copyright (c) 2024 Igor Voytenko <igor.240340@gmail.com>
;
; Control is performed via PORTC.
; Data/instruction read/write is handled via PORTB (in full 8-bit mode).
; Interaction occurs in synchronous mode, waiting for the BUSY flag to clear.
            .EQU BUSYFLAG=7                 ; Bit number in PORTB where the BUSY flag is expected.
            
            .EQU RS=0                       ; 0 - Instruction register, 1 - Data register.
            .EQU RW=1                       ; 0 - Write, 1 - Read.
            .EQU E=2                        ; Pulse to execute an instruction.

            .EQU EH=0b00000100              ; Enable pulse high.
            .EQU EL=0b00000000              ; Enable pulse low.
            .EQU INSTREG=0b00000000         ; Select the instruction register in the LCD.
            .EQU DATREG=0b00000001          ; Select the data register in the LCD.
            .EQU R=0b00000010               ; Read data from the LCD.
            .EQU W=0b00000000               ; Write data to the LCD.
            
            .EQU CLEARDISP=0x01             ; Instruction code for Clear Display.
            
            .EQU ENTRMODE=0x04              ; Instruction code for Entry Mode Set.
            .EQU CURSINC=0x02               ; Cursor movement direction - left to right.
            .EQU CURSDEC=0x00               ; Cursor movement direction - right to left.
            .EQU DISPCURSHFT=0x01           ; Shift the display along with the cursor.

            .EQU DISPCTRL=0x08              ; Instruction code for Display On/Off Control.
            .EQU DISPON=0x04                ;
            .EQU DISPOFF=0x00               ;
            .EQU CURSON=0x02                ;
            .EQU CURSOFF=0x00               ;
            .EQU CURSBLNKON=0x01            ;
            .EQU CURSBLNKOFF=0x00           ;

            .EQU CURDISPSHFT=0x10           ; Instruction code for Cursor or Display Shift.
            .EQU SHFTDSPLY=0x08             ; Shift the display.
            .EQU SHFTDIRLFT=0x00            ; Shift the display to the left.
            .EQU SHFTDIRRGHT=0x04           ; Shift the display to the right.

            .EQU FUNCSET=0x20               ; Instruction code for Function Set.
            .EQU DATLEN8=0x10               ; Data transmission mode - 8-bit.
            .EQU DATLEN4=0x00               ; Data transmission mode - 4-bit.
            .EQU DISPLINES2=0x08            ; Number of lines - two.
            .EQU DISPLINES1=0x00            ; Number of lines - one.
            .EQU FONT5X10=0x04              ; Font 5x10 dots.
            .EQU FONT5X8=0x00               ; Font 5x8 dots.
                        
            .EQU SETDDADDR=0x80             ; Instruction code for Set DDRAM Address.
            .EQU L1BEGADDR=0x00             ; Starting address of the first line in DDRAM.
            .EQU L1ENDADDR=0x0F             ; Address of the last visible character in the first line of DDRAM.
            .EQU L2BEGADDR=0x40             ; Starting address of the second line in DDRAM.

            .EQU SYSCONF=(FUNCSET|DATLEN8|DISPLINES2|FONT5X8)
            .EQU DISPCONF=(DISPCTRL|DISPON|CURSON|CURSBLNKON)

            .DEF CHAR=R0                    ; A character to be printed by PRNTCHR.

            ;
            ; LCD initialization.
INITLCD:    LDI R16,0b00000111              ; Control line setup.
            OUT DDRC,R16                    ; RS,RW,E - configured as output.

            LDI R16,0xFF                    ; Data line setup.
            OUT DDRB,R16                    ; D0-D7 - configured as output.

            RCALL DELAY20MS                 ; Wait for more than 15ms as per the datasheet.

            LDI R16,(FUNCSET|DATLEN8)       ; Configure 8-bit data transfer mode.
            OUT PORTB,R16                   ;
            RCALL EPULSECMD                 ;
;            RCALL DELAY5MS                  ; Wait for more than 4.1ms as per the datasheet.

;            LDI R16,(FUNCSET|DATLEN8)       ; Repeat the previous instruction as per the datasheet.
;            OUT PORTB,R16                   ;
;            RCALL EPULSECMD                 ;
;            RCALL DELAY110US                ; Wait for more than 100us as per the datasheet.

;            LDI R16,(FUNCSET|DATLEN8)       ; Another repeat of the previous instruction as per the datasheet.
;            OUT PORTB,R16                   ;
;            RCALL EPULSECMD                 ;
; NOTE: The datasheet recommends repeating the first instruction
; with the specified timings during initialization, but in practice, the LCD controller might "start up" on the first attempt.
; If any issues arise, try uncommenting this code.

            RCALL WAITBUSY                  ; Configure interface width, number of lines, and font size.
            LDI R16,SYSCONF                 ;
            OUT PORTB,R16                   ;
            RCALL EPULSECMD                 ;

            RCALL WAITBUSY                  ; Turn on the display and configure cursor settings.
            LDI R16,DISPCONF                ;
            OUT PORTB,R16                   ;
            RCALL EPULSECMD                 ;
            
            RCALL WAITBUSY                  ;
            LDI R16,CLEARDISP               ;
            OUT PORTB,R16                   ;
            RCALL EPULSECMD                 ;

            RCALL WAITBUSY                  ; Move the cursor right on input without shifting the display.
            LDI R16,(ENTRMODE|CURSINC)      ;
            OUT PORTB,R16                   ;
            RCALL EPULSECMD                 ;

            RET                             ;
            
            ;
            ; Output a single character stored in the CHAR register to the display.
PRNTCHR:    RCALL WAITBUSY                  ;
            OUT PORTB,CHAR                  ;
            RCALL EPULSEDAT                 ;
            RET                             ;

            ;
            ; Output characters of a string from SRAM.
            ;
            ; String address in SRAM is expected in XH:XL.
PRNTSTR:    LD CHAR,X+                      ;
            AND CHAR,CHAR                   ; End of the string?
            BREQ ENDPRNTSTR                 ; Yes, the entire string has been displayed.

            RCALL PRNTCHR                   ; No, output the next character.
            RJMP PRNTSTR                    ;

ENDPRNTSTR: RET                             ;

            ;
            ; Move the cursor to the beginning of the first line.
CURSL1BEG:  RCALL WAITBUSY
            LDI R16,(SETDDADDR|L1BEGADDR)
            OUT PORTB,R16
            RCALL EPULSECMD
            RET

            ;
            ; Move the cursor to the beginning of the second line.
CURSL2BEG:  RCALL WAITBUSY
            LDI R16,(SETDDADDR|L2BEGADDR)
            OUT PORTB,R16
            RCALL EPULSECMD
            RET

            ;
            ; Move the cursor to the end of the first line (end of the visible region).
CURSL1END:  RCALL WAITBUSY
            LDI R16,(SETDDADDR|L1ENDADDR)
            OUT PORTB,R16
            RCALL EPULSECMD
            RET

            ;
            ; Clear the screen and return the cursor to the beginning of the first line.
CLEARLCD:   RCALL WAITBUSY
            LDI R16,CLEARDISP
            OUT PORTB,R16
            RCALL EPULSECMD
            RET

            ;
            ; Hide the cursor.
DSBLCURS:   RCALL WAITBUSY
            LDI R16,(DISPCTRL|DISPON|CURSOFF|CURSBLNKOFF)
            OUT PORTB,R16
            RCALL EPULSECMD
            RET

            ;
            ; Show a blinking cursor.
ENBLCURS:   RCALL WAITBUSY
            LDI R16,(DISPCTRL|DISPON|CURSON|CURSBLNKON)
            OUT PORTB,R16
            RCALL EPULSECMD
            RET

            ;
            ; Shift the display one position to the left.
SHFTLFT:    RCALL WAITBUSY
            LDI R16,(CURDISPSHFT|SHFTDSPLY|SHFTDIRLFT)
            OUT PORTB,R16
            RCALL EPULSECMD
            RET

            ;
            ; Shift the display one position to the right.
SHFTRGHT:   RCALL WAITBUSY
            LDI R16,(CURDISPSHFT|SHFTDSPLY|SHFTDIRRGHT)
            OUT PORTB,R16
            RCALL EPULSECMD
            RET

            ;
            ; Generate a data readiness pulse when executing an instruction.
EPULSECMD:  LDI R16,(EH|W|INSTREG)          ;
            OUT PORTC,R16                   ;
            NOP                             ; Pulse duration: 500ns.
            NOP                             ; As per the datasheet, at least 400ns.
            NOP                             ;
            NOP                             ;
            CBI PORTC,E                     ;
            RET                             ;

            ;
            ; Generate a data readiness pulse when transferring data.
EPULSEDAT:  LDI R16,(EH|W|DATREG)           ;
            OUT PORTC,R16                   ;
            NOP                             ;
            NOP                             ;
            NOP                             ;
            NOP                             ;
            CBI PORTC,E                     ; RS (DATREG) must remain set on the falling edge
            RET                             ; because the LCD controller processes the current instruction on the falling edge.

            ;
            ; Synchronous wait for the LCD to be ready to accept a new command.
            ;
            ; NOTE: In case of an issue with the LCD controller, this subroutine
            ; may remain in an infinite loop. As a precaution, a watchdog timer can be used.
WAITBUSY:   LDI R16,0                       ; Set PORTB to input mode.
            OUT DDRB,R16                    ;

REPEAT0:    CBI PORTC,RS                    ; Generate an E pulse to read the BUSY flag.
            SBI PORTC,RW                    ; Set bits sequentially because a bug was observed on the actual controller:
            SBI PORTC,E                     ; simultaneous bit setting causes the controller to ignore them and output a blank character.
            NOP                             ; Hold the E pulse for at least 400ns.
            NOP                             ;
            NOP                             ;
            NOP                             ;
            
            IN R17,PINB                     ; According to the datasheet, BUSY flag reading should occur while E is high.

            CBI PORTC,E                     ;

            SBRC R17,BUSYFLAG               ; Is the BUSY flag cleared?
            RJMP REPEAT0                    ; No, continue waiting.

            LDI R16,0xFF                    ; Yes, the LCD is ready for interaction.
            OUT DDRB,R16                    ; Set PORTB back to output mode.
            RET                             ;

            ;
            ; Delay 110us (8MHz).
            ; NOTE: Assembly code auto-generated by utility from Bret Mulvey.
DELAY110US: LDI R16,2
            LDI R17,33
L0:         DEC R17
            BRNE L0
            DEC R16
            BRNE L0
            NOP
            RET

            ;
            ; Delay 5ms (8MHz).
            ; NOTE: Assembly code auto-generated by utility from Bret Mulvey.
DELAY5MS:   LDI R16,52
            LDI R17,240
L1:         DEC R17
            BRNE L1
            DEC R16
            BRNE L1
            RET

            ;
            ; Delay 20ms (8MHz).
            ; NOTE: Assembly code auto-generated by utility from Bret Mulvey.
DELAY20MS:  LDI R16,208
            LDI R17,200
L2:         DEC R17
            BRNE L2
            DEC R16
            BRNE L2
            RET

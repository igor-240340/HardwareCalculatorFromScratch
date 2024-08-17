;
; LCD1602-HD44780-AVR
; БИБЛИОТЕКА ДЛЯ ВЗАИМОДЕЙСТВИЯ С МОНОХРОМНЫМ ЖК ДИСПЛЕЕМ LCD1602 НА БАЗЕ КОНТРОЛЛЕРА HD44780.
;
; Copyright (c) 2024 IGOR VOYTENKO <igor.240340@gmail.com>
;
; УПРАВЛЕНИЕ ОСУЩЕСТВЛЯЕТСЯ ЧЕРЕЗ PORTC.
; ЗАПИСЬ/ЧТЕНИЕ ДАННЫХ/ИНСТРУКЦИЙ ОСУЩЕСТВЛЯЕТСЯ ЧЕРЕЗ PORTB (В ПОЛНОМ - 8-БИТНОМ РЕЖИМЕ).
; ВЗАИМОДЕЙСТВИЕ ПРОИСХОДИТ В СИНХРОННОМ РЕЖИМЕ, С ОЖИДАНИЕМ СБРОСА ФЛАГА BUSY.
            .EQU BUSYFLAG=7                 ; НОМЕР БИТА В PORTB, НА КОТОРОМ ОЖИДАЕТСЯ ЗНАЧЕНИЕ ФЛАГА BUSY.
            
            .EQU CLEARDISP=0x01             ; КОД ИНСТРУКЦИИ CLEAR DISPLAY.
            
            .EQU ENTRMODE=0x04              ; КОД ИНСТРУКЦИИ ENTRY MODE SET.
            .EQU CURSINC=0x02               ; НАПРАВЛЕНИЕ ДВИЖЕНИЯ КУРСОРА - СЛЕВА НАПРАВО.
            .EQU CURSDEC=0x00               ; НАПРАВЛЕНИЕ ДВИЖЕНИЯ КУРСОРА - СПРАВА НАЛЕВО.
            .EQU DISPCURSHFT=0x01           ; СДВИГАТЬ ДИСПЛЕЙ ВМЕСТЕ С КУРСОРОМ.

            .EQU DISPCTRL=0x08              ; КОД ИНСТРУКЦИИ DISPLAY ON/OFF CONTROL.
            .EQU DISPON=0x04                ;
            .EQU DISPOFF=0x00               ;
            .EQU CURSON=0x02                ;
            .EQU CURSOFF=0x00               ;
            .EQU CURSBLNKON=0x01            ;
            .EQU CURSBLNKOFF=0x00           ;

            .EQU CURDISPSHFT=0x10           ; КОД ИНСТРУКЦИИ CURSOR OR DISPLAY SHIFT.
            .EQU SHFTDSPLY=0x08             ; СДВИГ ДИСПЛЕЯ.
            .EQU SHFTDIRLFT=0x00            ; СДВИГ ДИСПЛЕЯ ВЛЕВО.
            .EQU SHFTDIRRGHT=0x04           ; СДВИГ ДИСПЛЕЯ ВПРАВО.

            .EQU FUNCSET=0x20               ; КОД ИНСТРУКЦИИ FUNCTION SET.
            .EQU DATLEN8=0x10               ; РЕЖИМ ПЕРЕДАЧИ ДАННЫХ - 8-BIT.
            .EQU DATLEN4=0x00               ; РЕЖИМ ПЕРЕДАЧИ ДАННЫХ - 4-BIT.
            .EQU DISPLINES2=0x08            ; КОЛИЧЕСТВО СТРОК - ДВЕ.
            .EQU DISPLINES1=0x00            ; КОЛИЧЕСТВО СТРОК - ОДНА.
            .EQU FONT5X10=0x04              ; ШРИФТ 5 НА 10 ТОЧЕК.
            .EQU FONT5X8=0x00               ; ШРИФТ 5 НА 8 ТОЧЕК.
                        
            .EQU SETDDADDR=0x80             ; КОД ИНСТРУКЦИИ SET DDRAM ADDRESS.
            .EQU L1BEGADDR=0x00             ; АДРЕС НАЧАЛА ПЕРВОЙ СТРОКИ В DDRAM.
            .EQU L1ENDADDR=0x0F             ; АДРЕС ПОСЛЕДНЕГО ВИДИМОГО СИМВОЛА ПЕРВОЙ СТРОКИ В DDRAM.
            .EQU L2BEGADDR=0x40             ; АДРЕС НАЧАЛА ВТОРОЙ СТРОКИ В DDRAM.

            .EQU SYSCONF=(FUNCSET|DATLEN8|DISPLINES2|FONT5X8)
            .EQU DISPCONF=(DISPCTRL|DISPON|CURSON|CURSBLNKON)
            
            .DEF CHAR=R0                    ; ЗДЕСЬ ОЖИДАЕТСЯ СИМВОЛ, ВЫВОДИМЫЙ PRNTCHR.

            ;
            ; ИНИЦИАЛИЗАЦИЯ LCD.
INITLCD:    LDI R16,0b00000111              ; НАСТРОЙКА ЛИНИИ УПРАВЛЕНИЯ.
            OUT DDRC,R16                    ; E,RW,RS - НА ВЫХОД.

            LDI R16,0xFF                    ; НАСТРОЙКА ЛИНИИ ДАННЫХ.
            OUT DDRB,R16                    ; D0-D7 - НА ВЫХОД.

            RCALL DELAY20MS                 ; ЖДЕМ БОЛЬШЕ 15MS ПО ДАТАШИТУ.

            LDI R16,(FUNCSET|DATLEN8)       ; НАСТРОЙКА 8-БИТНОГО РЕЖИМА ПЕРЕДАЧИ.
            OUT PORTB,R16                   ;
            RCALL EPULSECMD                 ;
            RCALL DELAY5MS                  ; ЖДЕМ БОЛЬШЕ 4.1MS ПО ДАТАШИТУ.

            LDI R16,(FUNCSET|DATLEN8)       ; ПОВТОР ПРЕДЫДУЩЕЙ ИНСТРУКЦИИ ПО ДАТАШИТУ.
            OUT PORTB,R16                   ;
            RCALL EPULSECMD                 ;
            RCALL DELAY110US                ; ЖДЕМ БОЛЬШЕ 100US ПО ДАТАШИТУ.

            LDI R16,(FUNCSET|DATLEN8)       ; ЕЩЁ ОДИН ПОВТОР ПРЕДЫДУЩЕЙ ИНСТРУКЦИИ ПО ДАТАШИТУ.
            OUT PORTB,R16                   ;
            RCALL EPULSECMD                 ;

            RCALL WAITBUSY                  ; НАСТРОЙКА ШИРИНЫ ИНТЕРФЕЙСА, КОЛИЧЕСТВА СТРОК, РАЗМЕРА ШРИФТА.
            LDI R16,SYSCONF                 ;
            OUT PORTB,R16                   ;
            RCALL EPULSECMD                 ;

            RCALL WAITBUSY                  ; ВКЛЮЧЕНИЕ ДИСПЛЕЯ, НАСТРОЙКИ КУРСОРА.
            LDI R16,DISPCONF                ;
            OUT PORTB,R16                   ;
            RCALL EPULSECMD                 ;
            
            RCALL WAITBUSY                  ;
            LDI R16,CLEARDISP               ;
            OUT PORTB,R16                   ;
            RCALL EPULSECMD                 ;

            RCALL WAITBUSY                  ; ДВИЖЕНИЕ КУРСОРА ВПРАВО ПРИ ВВОДЕ, БЕЗ СДВИГА ДИСПЛЕЯ.
            LDI R16,(ENTRMODE|CURSINC)      ;
            OUT PORTB,R16                   ;
            RCALL EPULSECMD                 ;

            RET                             ;
            
            ;
            ; ВЫВОДИТ НА ЭКРАН ОДИН СИМВОЛ, ХРАНЯЩИЙСЯ В РЕГИСТРЕ CHAR.
PRNTCHR:    RCALL WAITBUSY                  ;
            OUT PORTB,CHAR                  ;
            RCALL EPULSEDAT                 ;
            RET                             ;

            ;
            ; ВЫВОД НА ЭКРАН СИМВОЛОВ СТРОКИ ИЗ SRAM.
            ;
            ; АДРЕС СТРОКИ В SRAM ОЖИДАЕТСЯ В XH:XL.
PRNTSTR:    LD CHAR,X+                      ;
            AND CHAR,CHAR                   ; КОНЕЦ СТРОКИ?
            BREQ ENDPRNTSTR                 ; ДА, ВЫВЕЛИ ВСЮ СТРОКУ.

            RCALL PRNTCHR                   ; НЕТ, ВЫВОДИМ СИМВОЛ.
            RJMP PRNTSTR                    ;

ENDPRNTSTR: RET                             ;

            ;
            ; ПЕРЕМЕЩЕНИЕ КУРСОРА В НАЧАЛО ПЕРВОЙ СТРОКИ.
CURSL1BEG:  RCALL WAITBUSY
            LDI R16,(SETDDADDR|L1BEGADDR)
            OUT PORTB,R16
            RCALL EPULSECMD
            RET

            ;
            ; ПЕРЕМЕЩЕНИЕ КУРСОРА В НАЧАЛО ВТОРОЙ СТРОКИ.
CURSL2BEG:  RCALL WAITBUSY
            LDI R16,(SETDDADDR|L2BEGADDR)
            OUT PORTB,R16
            RCALL EPULSECMD
            RET

            ;
            ; ПЕРЕМЕЩЕНИЕ КУРСОРА В КОНЕЦ ПЕРВОЙ СТРОКИ (В КОНЕЦ ВИДИМОЙ ЧАСТИ).
CURSL1END:  RCALL WAITBUSY
            LDI R16,(SETDDADDR|L1ENDADDR)
            OUT PORTB,R16
            RCALL EPULSECMD
            RET

            ;
            ; ОЧИСТКА ЭКРАНА И ВОЗВРАТ КУРСОРА В НАЧАЛО ПЕРВОЙ СТРОКИ.
CLEARLCD:   RCALL WAITBUSY
            LDI R16,CLEARDISP
            OUT PORTB,R16
            RCALL EPULSECMD
            RET

            ;
            ; СКРЫТИЕ КУРСОРА.
DSBLCURS:   RCALL WAITBUSY
            LDI R16,(DISPCTRL|DISPON|CURSOFF|CURSBLNKOFF)
            OUT PORTB,R16
            RCALL EPULSECMD
            RET

            ;
            ; ПОКАЗ МИГАЮЩЕГО КУРСОРА.
ENBLCURS:   RCALL WAITBUSY
            LDI R16,(DISPCTRL|DISPON|CURSON|CURSBLNKON)
            OUT PORTB,R16
            RCALL EPULSECMD
            RET

            ;
            ; СДВИГ ДИСПЛЕЯ ВЛЕВО НА ОДНУ ПОЗИЦИЮ.
SHFTLFT:    RCALL WAITBUSY
            LDI R16,(CURDISPSHFT|SHFTDSPLY|SHFTDIRLFT)
            OUT PORTB,R16
            RCALL EPULSECMD
            RET

            ;
            ; СДВИГ ДИСПЛЕЯ ВПРАВО НА ОДНУ ПОЗИЦИЮ.
SHFTRGHT:   RCALL WAITBUSY
            LDI R16,(CURDISPSHFT|SHFTDSPLY|SHFTDIRRGHT)
            OUT PORTB,R16
            RCALL EPULSECMD
            RET

            ;
            ; ФОРМИРОВАНИЕ ИМПУЛЬСА ГОТОВНОСТИ ДАННЫХ В СЛУЧАЕ ВЫПОЛНЕНИЯ ИНСТРУКЦИИ.
EPULSECMD:  LDI R16,0b00000100              ;
            OUT PORTC,R16                   ;
            LDI R16,0b00000000              ;
            OUT PORTC,R16                   ;
            RET                             ;

            ;
            ; ФОРМИРОВАНИЕ ИМПУЛЬСА ГОТОВНОСТИ ДАННЫХ В СЛУЧАЕ ПЕРЕДАЧИ ДАННЫХ.
EPULSEDAT:  LDI R16,0b00000101              ;
            OUT PORTC,R16                   ;
            LDI R16,0b00000001              ;
            OUT PORTC,R16                   ;
            RET                             ;

            ;
            ; СИНХРОННОЕ ОЖИДАНИЕ ГОТОВНОСТИ LCD ПРИНЯТЬ НОВУЮ КОМАНДУ.
            ;
            ; NOTE: В СЛУЧАЕ НЕПОЛАДКИ НА СТОРОНЕ КОНТРОЛЛЕРА LCD ЭТА ПОДПРОГРАММА МОЖЕТ ОСТАТЬСЯ В БЕСКОНЕЧНОМ ЦИКЛЕ.
            ; В КАЧЕСТВЕ МЕРЫ ПРЕДОСТОРОЖНОСТИ МОЖНО ИСПОЛЬЗОВАТЬ СТОРОЖЕВОЙ ТАЙМЕР.
WAITBUSY:   LDI R16,0                       ; ПЕРЕКЛЮЧАЕМ PORTB НА ВХОД.
            OUT DDRB,R16                    ;

REPEAT0:    LDI R16,0b00000110              ; ФОРМИРУЕМ ИМПУЛЬС НА E.
            OUT PORTC,R16                   ;

            IN R17,PINB                     ;

            LDI R16,0b00000010              ;
            OUT PORTC,R16                   ;

            SBRC R17,BUSYFLAG               ; BUSY-ФЛАГ СБРОШЕН?
            RJMP REPEAT0                    ; НЕТ, ОЖИДАЕМ.

            LDI R16,0xFF                    ; ДА, LCD ГОТОВ К ВЗАИМОДЕЙСТВИЮ.
            OUT DDRB,R16                    ; ПЕРЕКЛЮЧАЕМ PORTB НА ВЫХОД.
            RET                             ;

            ;
            ; ЗАДЕРЖКА 110US (16MHz).
            ; NOTE: ASSEMBLY CODE AUTO-GENERATED BY UTILITY FROM BRET MULVEY.
DELAY110US: LDI R16,3
            LDI R17,70
D0:         DEC R17
            BRNE D0
            DEC R16
            BRNE D0
            NOP
            RET

            ;
            ; ЗАДЕРЖКА 5MS (16MHz). ИСПОЛЬЗУЕТ R16,R17.
            ; NOTE: ASSEMBLY CODE AUTO-GENERATED BY UTILITY FROM BRET MULVEY.
DELAY5MS:   LDI R16,104
            LDI R17,226
D1:         DEC R17
            BRNE D1
            DEC R16
            BRNE D1
            RJMP PC+1
            NOP
            RET

            ;
            ; ЗАДЕРЖКА 20ms (16MHz). ИСПОЛЬЗУЕТ R16,R17,R18.
            ; NOTE: ASSEMBLY CODE AUTO-GENERATED BY UTILITY FROM BRET MULVEY.
DELAY20MS:  LDI R16,2
            LDI R17,160
            LDI R18,145
D2:         DEC R18
            BRNE D2
            DEC  R17
            BRNE D2
            DEC  R16
            BRNE D2
            NOP
            RET

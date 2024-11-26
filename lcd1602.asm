;
; LCD1602-HD44780-AVR - библиотека для взаимодействия с монохромным ЖК-дисплеем LCD1602 на базе контроллера HD44780.
;
; Copyright (c) 2024 Igor Voytenko <igor.240340@gmail.com>
;
; Управление осуществляется через PORTC.
; Запись/чтение данных/инструкций осуществляется через PORTB (в полном - 8-битном режиме).
; Взаимодействие происходит в синхронном режиме, с ожиданием сброса BUSY-флага.
            .EQU BUSYFLAG=7                 ; Номер бита в PORTB, на котором ожидается значение флага BUSY.
            
            .EQU RS=0                       ; 0 - регистр инструкций, 1 - регистр данных.
            .EQU RW=1                       ; 0 - запись, 1 - чтение.
            .EQU E=2                        ; Импульс на выполнение инструкции.

            .EQU EH=0b00000100              ; Enable pulse high.
            .EQU EL=0b00000000              ; Enable pulse low.
            .EQU INSTREG=0b00000000         ; Выбор регистра инструкций в LCD.
            .EQU DATREG=0b00000001          ; Выбор регистра данных в LCD.
            .EQU R=0b00000010               ; Чтение данных из LCD.
            .EQU W=0b00000000               ; Запись данных в LCD.
            
            .EQU CLEARDISP=0x01             ; Код инструкции Clear Display.
            
            .EQU ENTRMODE=0x04              ; Код инструкции Entry Mode Set.
            .EQU CURSINC=0x02               ; Направление движения курсора - слева направо.
            .EQU CURSDEC=0x00               ; Направление движения курсора - справа налево.
            .EQU DISPCURSHFT=0x01           ; Сдвигать дисплей вместе с курсором.

            .EQU DISPCTRL=0x08              ; Код инструкции Display On/Off Control.
            .EQU DISPON=0x04                ;
            .EQU DISPOFF=0x00               ;
            .EQU CURSON=0x02                ;
            .EQU CURSOFF=0x00               ;
            .EQU CURSBLNKON=0x01            ;
            .EQU CURSBLNKOFF=0x00           ;

            .EQU CURDISPSHFT=0x10           ; Код инструкции Cursor or Display Shift.
            .EQU SHFTDSPLY=0x08             ; Сдвиг дисплея.
            .EQU SHFTDIRLFT=0x00            ; Сдвиг дисплея влево.
            .EQU SHFTDIRRGHT=0x04           ; Сдвиг дисплея вправо.

            .EQU FUNCSET=0x20               ; Код инструкции Function Set.
            .EQU DATLEN8=0x10               ; Режим передачи данных - 8-bit.
            .EQU DATLEN4=0x00               ; Режим передачи данных - 4-bit.
            .EQU DISPLINES2=0x08            ; Количество строк - две.
            .EQU DISPLINES1=0x00            ; Количество строк - одна.
            .EQU FONT5X10=0x04              ; Шрифт 5 на 10 точек.
            .EQU FONT5X8=0x00               ; Шрифт 5 на 8 точек.
                        
            .EQU SETDDADDR=0x80             ; Код инструкции Set DDRAM Address.
            .EQU L1BEGADDR=0x00             ; Адрес начала первой строки в DDRAM.
            .EQU L1ENDADDR=0x0F             ; Адрес последнего видимого символа первой строки в DDRAM.
            .EQU L2BEGADDR=0x40             ; Адрес начала второй строки в DDRAM.

            .EQU SYSCONF=(FUNCSET|DATLEN8|DISPLINES2|FONT5X8)
            .EQU DISPCONF=(DISPCTRL|DISPON|CURSON|CURSBLNKON)

            .DEF CHAR=R0                    ; Здесь ожидается символ, выводимый PRNTCHR.

            ;
            ; Инициализация LCD.
INITLCD:    LDI R16,0b00000111              ; Настройка линии управления.
            OUT DDRC,R16                    ; RS,RW,E - на выход.

            LDI R16,0xFF                    ; Настройка линии данных.
            OUT DDRB,R16                    ; D0-D7 - на выход.

            RCALL DELAY20MS                 ; Ждем больше 15ms по даташиту.

            LDI R16,(FUNCSET|DATLEN8)       ; Настройка 8-битного режима передачи.
            OUT PORTB,R16                   ;
            RCALL EPULSECMD                 ;
;            RCALL DELAY5MS                  ; Ждем больше 4.1ms по даташиту.

;            LDI R16,(FUNCSET|DATLEN8)       ; Повтор предыдущей инструкции по даташиту.
;            OUT PORTB,R16                   ;
;            RCALL EPULSECMD                 ;
;            RCALL DELAY110US                ; Ждем больше 100us по даташиту.

;            LDI R16,(FUNCSET|DATLEN8)       ; Ещё один повтор предыдущей инструкции по даташиту.
;            OUT PORTB,R16                   ;
;            RCALL EPULSECMD                 ;
; NOTE: Даташит рекомендует при инициализации повторить первую инструкцию
; с указанными таймингами, но на практике контроллер LCD может "завестись" и с первого раза.
; Если будут проблемы - попробуйте раскомментировать этот код.

            RCALL WAITBUSY                  ; Настройка ширины интерфейса, количества строк, размера шрифта.
            LDI R16,SYSCONF                 ;
            OUT PORTB,R16                   ;
            RCALL EPULSECMD                 ;

            RCALL WAITBUSY                  ; Включение дисплея, настройки курсора.
            LDI R16,DISPCONF                ;
            OUT PORTB,R16                   ;
            RCALL EPULSECMD                 ;
            
            RCALL WAITBUSY                  ;
            LDI R16,CLEARDISP               ;
            OUT PORTB,R16                   ;
            RCALL EPULSECMD                 ;

            RCALL WAITBUSY                  ; Движение курсора вправо при вводе, без сдвига дисплея.
            LDI R16,(ENTRMODE|CURSINC)      ;
            OUT PORTB,R16                   ;
            RCALL EPULSECMD                 ;

            RET                             ;
            
            ;
            ; Выводит на экран один символ, хранящийся в регистре CHAR.
PRNTCHR:    RCALL WAITBUSY                  ;
            OUT PORTB,CHAR                  ;
            RCALL EPULSEDAT                 ;
            RET                             ;

            ;
            ; Вывод на экран символов строки из SRAM.
            ;
            ; Адрес строки в SRAM ожидается в XH:XL.
PRNTSTR:    LD CHAR,X+                      ;
            AND CHAR,CHAR                   ; Конец строки?
            BREQ ENDPRNTSTR                 ; Да, вывели всю строку.

            RCALL PRNTCHR                   ; Нет, выводим символ.
            RJMP PRNTSTR                    ;

ENDPRNTSTR: RET                             ;

            ;
            ; Перемещение курсора в начало первой строки.
CURSL1BEG:  RCALL WAITBUSY
            LDI R16,(SETDDADDR|L1BEGADDR)
            OUT PORTB,R16
            RCALL EPULSECMD
            RET

            ;
            ; Перемещение курсора в начало второй строки.
CURSL2BEG:  RCALL WAITBUSY
            LDI R16,(SETDDADDR|L2BEGADDR)
            OUT PORTB,R16
            RCALL EPULSECMD
            RET

            ;
            ; Перемещение курсора в конец первой строки (в конец видимой части).
CURSL1END:  RCALL WAITBUSY
            LDI R16,(SETDDADDR|L1ENDADDR)
            OUT PORTB,R16
            RCALL EPULSECMD
            RET

            ;
            ; Очистка экрана и возврат курсора в начало первой строки.
CLEARLCD:   RCALL WAITBUSY
            LDI R16,CLEARDISP
            OUT PORTB,R16
            RCALL EPULSECMD
            RET

            ;
            ; Скрытие курсора.
DSBLCURS:   RCALL WAITBUSY
            LDI R16,(DISPCTRL|DISPON|CURSOFF|CURSBLNKOFF)
            OUT PORTB,R16
            RCALL EPULSECMD
            RET

            ;
            ; Показ мигающего курсора.
ENBLCURS:   RCALL WAITBUSY
            LDI R16,(DISPCTRL|DISPON|CURSON|CURSBLNKON)
            OUT PORTB,R16
            RCALL EPULSECMD
            RET

            ;
            ; Сдвиг дисплея влево на одну позицию.
SHFTLFT:    RCALL WAITBUSY
            LDI R16,(CURDISPSHFT|SHFTDSPLY|SHFTDIRLFT)
            OUT PORTB,R16
            RCALL EPULSECMD
            RET

            ;
            ; Сдвиг дисплея вправо на одну позицию.
SHFTRGHT:   RCALL WAITBUSY
            LDI R16,(CURDISPSHFT|SHFTDSPLY|SHFTDIRRGHT)
            OUT PORTB,R16
            RCALL EPULSECMD
            RET

            ;
            ; Формирование импульса готовности данных в случае выполнения инструкции.
EPULSECMD:  LDI R16,(EH|W|INSTREG)          ;
            OUT PORTC,R16                   ;
            NOP                             ; Длительность импульса - 500ns.
            NOP                             ; По даташиту - не менее 400ns.
            NOP                             ;
            NOP                             ;
            CBI PORTC,E                     ;
            RET                             ;

            ;
            ; Формирование импульса готовности данных в случае передачи данных.
EPULSEDAT:  LDI R16,(EH|W|DATREG)           ;
            OUT PORTC,R16                   ;
            NOP                             ;
            NOP                             ;
            NOP                             ;
            NOP                             ;
            CBI PORTC,E                     ; RS (DATREG) должен оставаться установленным на спаде фронта,
            RET                             ; т.к. контроллер LCD обрабатывает текущую инструкцию по спаду.

            ;
            ; Синхронное ожидание готовности LCD принять новую команду.
            ;
            ; NOTE: в случае неполадки на стороне контроллера LCD эта подпрограмма может остаться в бесконечном цикле.
            ; В качестве меры предосторожности можно использовать сторожевой таймер.
WAITBUSY:   LDI R16,0                       ; Переключаем PORTB на вход.
            OUT DDRB,R16                    ;

REPEAT0:    CBI PORTC,RS                    ; Формируем импульс E на чтение BUSY-флага.
            SBI PORTC,RW                    ; Устанавливаем биты последовательно, поскольку на реальном контроллере обнаружился баг -
            SBI PORTC,E                     ; при одновременной установке битов контроллер игнорирует их и выводит на экран пустой символ.
            NOP                             ; Удерживаем импульс E не менее 400ns.
            NOP                             ;
            NOP                             ;
            NOP                             ;
            
            IN R17,PINB                     ; По даташиту чтение BUSY-флага должно происходить, пока E на высоком уровне.

            CBI PORTC,E                     ;

            SBRC R17,BUSYFLAG               ; BUSY-флаг сброшен?
            RJMP REPEAT0                    ; Нет, ожидаем.

            LDI R16,0xFF                    ; Да, LCD готов к взаимодействию.
            OUT DDRB,R16                    ; Переключаем PORTB обратно - на выход.
            RET                             ;

            ;
            ; Задержка 110us (8MHz).
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
            ; Задержка 5ms (8MHz).
            ; NOTE: Assembly code auto-generated by utility from Bret Mulvey.
DELAY5MS:   LDI R16,52
            LDI R17,240
L1:         DEC R17
            BRNE L1
            DEC R16
            BRNE L1
            RET

            ;
            ; Задержка 20ms (8MHz).
            ; NOTE: Assembly code auto-generated by utility from Bret Mulvey.
DELAY20MS:  LDI R16,208
            LDI R17,200
L2:         DEC R17
            BRNE L2
            DEC R16
            BRNE L2
            RET

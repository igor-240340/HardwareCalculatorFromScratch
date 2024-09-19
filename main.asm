            .INCLUDE <m328pdef.inc>

                                            ; Эмуляция ввода с клавиатуры для тестирования.
                                            ; в этом режиме контроллер читает числовые строки и
;            .EQU EMULKEYPD=1                ; транслирует их в коды энкодера MM74C922, имитируя нажатие кнопок.

                                            ; Под стеком 3 переменных по 4 байта под float32,
                                            ; 16 байт под ASCII-коды нажатых клавиш и еще
            .EQU SP=RAMEND-(3*4+16+256)     ; 256 байт под ASCII-строку.
            .EQU LCDLEN=16                  ; Длина строки в LCD.
;            .EQU LCDLEN=40                  ; Тестовое увеличение лимита для проверки обработки переполнения в ATOF.

            .DEF S=R0                       ; Количество использованных символов в текущей строке дисплея.
            .DEF P=R1                       ; Номер вводимого операнда, лежит в [0,1].
            .DEF KEY=R2                     ; ASCII-код нажатой клавиши.
            .DEF LCDLIM=R3                  ; Максимальное количество выводимых на LCD символов.

            .DEF RETL=R22                   ; Сюда бэкапим адрес возврата после прерывания.
            .DEF RETH=R23                   ;

            .DSEG

.IFDEF EMULKEYPD
            .ORG 0x012A                     ; Начало таблицы соответствия между ASCII-кодами и кодами энкодера. Таблица лежит в [0x012A,0x0143].
REVKEYMAP:  .BYTE 26                        ; Младший байт адреса - ASCII-код клавиши. Наименьший код клавиши - 0x2A('*'), наибольший - 0x43('C').
.ENDIF

            .ORG SP+1                       ;
A:          .BYTE 4                         ; 0x07E4. Операнд A.
B:          .BYTE 4                         ; 0x07E8. Операнд B.
C:          .BYTE 4                         ; 0x07EC. Результат C.
KEYMAP:     .BYTE 16                        ; 0x07F0. Таблица символов нажатых клавиш.
NUMSTR:     .BYTE 256                       ; 0x0800. Указатель на ASCII-строку с числом в SRAM.

            .CSEG
            .ORG 0x00

            JMP RESET
            JMP KEYPAD
            
            .INCLUDE "lcd1602.asm"
            .INCLUDE "float32avr.asm"

;
; Обработка прерываний от клавиатуры.
KEYPAD:     IN KEY,PIND                     ; Сырой код клавиши - в старшем полубайте порта D.
            LDI R17,0xF0                    ; Извлекаем и сдвигаем в младший полубайт.
            AND KEY,R17                     ;
            CLC                             ;
            ROR KEY                         ;
            ROR KEY                         ;
            ROR KEY                         ;
            ROR KEY                         ;

            LDI R17,LOW(KEYMAP)             ; Добавляем код клавиши в младший полубайт адреса таблицы символов.
            OR R17,KEY                      ; Y=0x07F0|0x0X, 0x0X - код клавиши в отрезке [0x00,0x0F].
            MOV YL,R17                      ;
            LDI YH,HIGH(KEYMAP)             ;

            LD KEY,Y                        ; KEY=ASCII(RAWKEY), RAWKEY - сырой код от MM74C922.

.IFDEF EMULKEYPD
            POP RETH                        ; Бэкапим адрес возврата после прерывания.
            POP RETL                        ;
            POP R17                         ; Извлекаем адрес текущего состояния.
            POP R16                         ;
            PUSH ZL                         ; Бэкапим указатель на тестовую числовую строку, на основе которой эмулируется ввод.
            PUSH ZH                         ;
            MOV ZL,R16                      ; Перемещаем адрес обработчика текущего состояния в Z.
            MOV ZH,R17                      ;
            IJMP                            ;
.ELSE
            POP RETH                        ; Бэкапим адрес возврата после прерывания.
            POP RETL                        ;
            POP ZH                          ; Извлекаем адрес обработчика текущего состояния.
            POP ZL                          ;
            IJMP                            ; Прыгаем на обработчик, соответствующий текущему состоянию.
.ENDIF

            ;
            ; S0 - начальное состояние перед вводом первого или второго операнда.
            ;
            ; Допустимы только цифровые клавиши и минус.
S0:         LDI R16,'C'                     ;
            EOR R16,KEY                     ; KEY='C'?
            BREQ S0RESETIN                  ; Да, сбрасываем ввод, возвращаемся в нулевое состояние.

            LDI R16,'-'                     ;
            EOR R16,KEY                     ; KEY='-'?
            BREQ S0MINUS                    ;

            LDI R16,'0'                     ;
            EOR R16,KEY                     ; KEY='0'?
            BREQ S0DIG0                     ;

            LDI R16,0xF0                    ; Все цифры от 1 до 9 в ASCII имеют одинаковый старший полубайт равный 0x30.
            AND R16,KEY                     ; Другие возможные клавиши на этом этапе: '.','+','*','/', имеют старший полубайт равный 0x20.
            LDI R17,0x30                    ;
            EOR R16,R17                     ; KEY=['1','9']?
            BREQ S0DIG19                    ;

            LDI R16,LOW(S0)                 ; Была нажата недопустимая в этом состоянии клавиша.
            LDI R17,HIGH(S0)                ; S0->S0.
            RJMP S0END                      ; Игнорируем ввод и остаёмся в текущем состоянии.

S0RESETIN:  JMP RESETINPUT                  ; Дальний прыжок, т.к. не достаем непосредственно из BREQ.

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
; NOTE: Отключаем взаимодействие с LCD в режиме эмуляции клавиатуры.
; Причина в том, что в режиме эмуляции клавиатуры после передачи в LCD
; Управляющей инструкции, на порту B может быть установлен седьмой бит,
; который в режиме чтения является BUSY-флагом, но поскольку эмуляции LCD нет, то
; не происходит сброса состояния порта B и при вызове очередной LCD-инструкции
; мы попадём в бесконечный цикл ожидания сброса BUSY-флага.
.IFNDEF EMULKEYPD
            PUSH S                          ; Бэкапим регистры, которые PRNTCHR может испортить.
            PUSH R16                        ;
            PUSH R17                        ;
            MOV CHAR,KEY                    ; Выводим нажатую клавишу на LCD.
            RCALL PRNTCHR                   ;
            POP R17                         ;
            POP R16                         ;
            POP S                           ;
.ENDIF

.IFDEF EMULKEYPD
S0END:      POP ZH                          ; Восстанавливаем указатель на тестовую числовую строку.
            POP ZL                          ;
            PUSH R16                        ; Запоминаем новое состояние.
            PUSH R17                        ;
            PUSH RETL                       ; Восстанавливаем адрес возврата после прерывания.
            PUSH RETH                       ;
            RETI                            ;
.ELSE
S0END:      PUSH R16                        ; Запоминаем новое состояние.
            PUSH R17                        ;
            PUSH RETL                       ; Восстанавливаем адрес возврата после прерывания.
            PUSH RETH                       ;
            RETI                            ;
.ENDIF

            ;
            ; S1 - ПРОМЕЖУТОЧНОЕ СОСТОЯНИЕ ПОСЛЕ НАЖАТИЯ НУЛЯ.
            ;
            ; ДОПУСТИМЫ ТОЛЬКО ТОЧКА ИЛИ КЛАВИШИ ОПЕРАТОРА.
S1:         LDI R16,'C'                     ;
            EOR R16,KEY                     ; KEY='C'?
            BREQ S1RESETIN                  ;

            LDI R16,'.'                     ;
            EOR R16,KEY                     ; KEY='.'?
            BREQ S1DECPNT                   ;

            LDI R16,0xF0                    ; '+','-','*','/' В ASCII ИМЕЮТ ОДИНАКОВЫЙ СТАРШИЙ ПОЛУБАЙТ РАВНЫЙ 0x20.
            AND R16,KEY                     ; А '.' МЫ УЖЕ ИСКЛЮЧИЛИ ВЫШЕ.
            LDI R17,0x20                    ;
            EOR R16,R17                     ; KEY=['+','-','/']?
            BREQ S1OPERATOR                 ;
            LDI R16,'x'                     ; Мы заменили символ умножения на 'x', который находится в последней строке ASCII-таблицы.
            EOR R16,KEY                     ; KEY='x'?
            BREQ S1OPERATOR                 ;

            LDI R16,LOW(S1)                 ;
            LDI R17,HIGH(S1)                ;
            RJMP S1END                      ;

S1RESETIN:  JMP RESETINPUT                  ; ДАЛЬНИЙ ПРЫЖОК, Т.К. НЕ ДОСТАЕМ НЕПОСРЕДСТВЕННО ИЗ BREQ.

S1DECPNT:   LDI R16,LOW(S3)                 ; S1->S3.
            LDI R17,HIGH(S3)                ;
            RJMP S1PRNTKEY                  ;

S1OPERATOR: LDI R16,2                       ;
            EOR R16,P                       ; ЗАВЕРШЕН ВВОД ВТОРОГО ОПЕРАНДА?
            BREQ S1OPERAND2                 ; ДА, ПЕРЕХОДИМ К КОНВЕРТАЦИИ В FLOAT32 И ВЫЧИСЛЕНИЮ.
            RJMP OPERAND1                   ; НЕТ, ВВЕДЕН ПЕРВЫЙ ОПЕРАНД, КОНВЕРТИРУЕМ ЕГО В FLOAT

S1OPERAND2: JMP OPERAND2                    ; ДАЛЬНИЙ ПРЫЖОК.

S1PRNTKEY:  ST X+,KEY                       ; *NUMSTR=KEY.
            INC S                           ;

.IFNDEF EMULKEYPD
            PUSH S                          ;
            PUSH R16                        ;
            PUSH R17                        ;
            MOV CHAR,KEY                    ; ВЫВОДИМ НАЖАТУЮ КЛАВИШУ НА LCD.
            RCALL PRNTCHR                   ;
            POP R17                         ;
            POP R16                         ;
            POP S                           ;
.ENDIF
          
.IFDEF EMULKEYPD
S1END:      POP ZH                          ; ВОССТАНАВЛИВАЕМ УКАЗАТЕЛЬ НА ТЕСТОВУЮ ЧИСЛОВУЮ СТРОКУ.
            POP ZL                          ;
            PUSH R16                        ; ЗАПОМИНАЕМ НОВОЕ СОСТОЯНИЕ.
            PUSH R17                        ;
            PUSH RETL                       ; ВОССТАНАВЛИВАЕМ АДРЕС ВОЗВРАТА ПОСЛЕ ПРЕРЫВАНИЯ.
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
            ; S2 - ПРОМЕЖУТОЧНОЕ СОСТОЯНИЕ ПОСЛЕ НАЖАТИЯ МИНУСА.
            ;
            ; ДОПУСТИМЫ ТОЛЬКО ЦИФРОВЫЕ КЛАВИШИ.
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
            MOV CHAR,KEY                    ; ВЫВОДИМ НАЖАТУЮ КЛАВИШУ НА LCD.
            RCALL PRNTCHR                   ;
            POP R17                         ;
            POP R16                         ;
            POP S                           ;
.ENDIF

.IFDEF EMULKEYPD
S2END:      POP ZH                          ; ВОССТАНАВЛИВАЕМ УКАЗАТЕЛЬ НА ТЕСТОВУЮ ЧИСЛОВУЮ СТРОКУ.
            POP ZL                          ;
            PUSH R16                        ; ЗАПОМИНАЕМ НОВОЕ СОСТОЯНИЕ.
            PUSH R17                        ;
            PUSH RETL                       ; ВОССТАНАВЛИВАЕМ АДРЕС ВОЗВРАТА ПОСЛЕ ПРЕРЫВАНИЯ.
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
            ; СБРОС ВВОДА ПО НАЖАТИЮ КЛАВИШИ 'C'.
RESETINPUT:
.IFDEF EMULKEYPD
            POP ZH                          ; ВОССТАНАВЛИВАЕМ УКАЗАТЕЛЬ НА ТЕСТОВУЮ ЧИСЛОВУЮ СТРОКУ.
            POP ZL                          ;
.ENDIF
            LDI R16,2                       ;
            EOR R16,P                       ; СБРОС НАЖАТ В ФАЗЕ ВВОДА ВТОРОГО ОПЕРАНДА?
            BRNE RESET1                     ; НЕТ, МЫ ЕЩЕ В ФАЗЕ ВВОДА ПЕРВОГО ОПЕРАНДА (ДО НАЖАТИЯ ОПЕРАТОРА).
            POP R16                         ; ДА, ПЕРВЫЙ ОПЕРАНД УЖЕ ВВЕДЁН И В СТЕКЕ ЛЕЖАТ: СИМВОЛ ОПЕРАТОРА
            POP R16                         ; И ЧЕТЫРЕ БАЙТА ПЕРВОГО ОПЕРАНДА В ФОРМАТЕ FLOAT32.
            POP R16                         ; ВЫБРАСЫВАЕМ 4 БАЙТА ПЕРВОГО ОПЕРАНДА.
            POP R16                         ;
            POP R16                         ; ВЫБРАСЫВАЕМ СИМВОЛ ОПЕРАТОРА. СТЕК ПУСТ.

RESET1:     LDI XL,LOW(NUMSTR)              ; СМЕЩАЕМ УКАЗАТЕЛЬ NUMSTR В НАЧАЛО СТРОКИ.
            LDI XH,HIGH(NUMSTR)             ;

            LDI R16,0                       ; S=0.
            MOV S,R16                       ;

            LDI R16,1                       ; P=1.
            MOV P,R16                       ;

            LDI R16,LCDLEN-1                ; РЕЗЕРВИРУЕМ ПОСЛЕДНИЙ СИМВОЛ ПЕРВОЙ СТРОКИ ПОД СИМВОЛ ОПЕРАТОРА.
            MOV LCDLIM,R16                  ;

            LDI R16,LOW(S0)                 ; НАЧАЛЬНОЕ СОСТОЯНИЕ - S0.
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
            ; ВВОД ПЕРВОГО ОПЕРАНДА ЗАВЕРШЁН.
.IFDEF EMULKEYPD
OPERAND1:   POP ZH                          ; ВРЕМЕННО ВОССТАНАВЛИВАЕМ УКАЗАТЕЛЬ НА ТЕСТОВУЮ ЧИСЛОВУЮ СТРОКУ.
            POP ZL                          ;
            PUSH KEY                        ; СОХРАНЯЕМ В САМЫЙ НИЗ СТЕКА НАЖАТЫЙ АРИФМЕТИЧЕСКИЙ ОПЕРАТОР.
            PUSH ZL                         ; ПОМЕЩАЕМ СВЕРХУ УКАЗАТЕЛЬ НА СТРОКУ.
            PUSH ZH                         ;
.ELSE
OPERAND1:   PUSH KEY                        ; СОХРАНЯЕМ В САМЫЙ НИЗ СТЕКА НАЖАТЫЙ АРИФМЕТИЧЕСКИЙ ОПЕРАТОР.
.ENDIF
            LDI R16,0                       ; *NUMSTR='\0'.
            ST X,R16                        ;

            LDI XL,LOW(NUMSTR)              ; ВОЗВРАЩАЕМ УКАЗАТЕЛЬ В НАЧАЛО СТРОКИ
            LDI XH,HIGH(NUMSTR)             ; ПЕРЕД ВЫЗОВОМ ATOF.

            ;
            ; ОБРАБОТЧИК ОШИБОК, ВОЗНИКАЮЩИХ ПРИ ВЫЧИСЛЕНИЯХ С ПЛАВАЮЩЕЙ ТОЧКОЙ, КОТОРЫЕ ПРОИСХОДЯТ ВНУТРИ ATOF.
            ;
            ; В СИЛУ ТЕКУЩИХ ОГРАНИЧЕНИЙ НА ВВОД - ТОЛЬКО ДЕСЯТИЧНЫЕ ДРОБИ, БЕЗ ЭКСПОНЕНЦИАЛЬНОЙ ЗАПИСИ -
            ; ПРИ ВЫПОЛНЕНИИ ATOF ПЕРЕПОЛНЕНИЕ ВОЗНИКНУТЬ НЕ МОЖЕТ, А ДЕЛЕНИЕ НА НОЛЬ В ATOF НЕВОЗМОЖНО В ПРИНЦИПЕ.
            ;
            ; НО ЕСЛИ СПОСОБ ВВОДА БУДЕТ ОБНОВЛЁН, ТО ВОЗМОЖНО ПЕРЕПОЛНЕНИЕ ПРИ КОНВЕРТАЦИИ,
            ; КОГДА ДЛЯ ПРОМЕЖУТОЧНЫХ ВЫЧИСЛЕНИЯХ ОДИНАРНОЙ ТОЧНОСТИ СТАНОВИТСЯ НЕДОСТАТОЧНО.
            ;
            ; TODO: ДОБАВИТЬ ВЫВОД СООБЩЕНИЯ ОБ ОШИБКЕ НА LCD.
            ; В ПЕРВОЙ ВЕРСИИ ЭТО НЕ КРИТИЧНО, Т.К. ВВОД ОГРАНИЧЕН И ИСКЛЮЧЕНИЯ В ATOF БЫТЬ НЕ МОЖЕТ.
            LDI ZL,LOW(OP1FLTERR0)          ;
            LDI ZH,HIGH(OP1FLTERR0)         ;
            RJMP OP1CNVRT                   ;
OP1FLTERR0: POP R16                         ; ВЫБРАСЫВАЕМ ИЗ СТЕКА АДРЕС ВОЗВРАТА ПОСЛЕ ATOF.
            POP R16                         ;
            POP RETH                        ; ВОССТАНАВЛИВАЕМ АДРЕС ВОЗВРАТА ПОСЛЕ ПРЕРЫВАНИЯ.
            POP RETL                        ;
            POP KEY                         ; ПЕРЕД FTOA МЫ СОХРАНЯЛИ KEY - ИЗВЛЕКАЕМ ЕГО.
.IFDEF EMULKEYPD
            POP ZH                          ; ЕСЛИ МЫ В РЕЖИМЕ ЭМУЛЯЦИИ И ТЕСТИРОВАНИЯ ВВОДА С КЛАВИАТУРЫ, ТО
            POP ZL                          ; ВОССТАНАВЛИВАЕМ УКАЗАТЕЛЬ НА ТЕСТОВУЮ ЧИСЛОВУЮ СТРОКУ.
.ENDIF
            POP R16                         ; НА ДНЕ СТЕКА ОСТАЛСЯ ЕЩЕ СИМВОЛ ОПЕРАТОРА, ОН БОЛЬШЕ НЕ НУЖЕН.

            LDI XL,LOW(NUMSTR)              ; NUMSTR="ERR".
            LDI XH,HIGH(NUMSTR)             ;
            LDI R16,'E'                     ;
            ST X+,R16                       ;
            LDI R16,'R'                     ;
            ST X+,R16                       ;
            ST X+,R16                       ;
            CLR R16                         ;
            ST X,R16                        ; NUMSTR+='\0'.

            LDI R16,LOW(SHOWRES)            ; ПРИ ВВОДЕ ПЕРВОГО ОПЕРАНДА ПРОИЗОШЛО ИСКЛЮЧЕНИЕ,
            LDI R17,HIGH(SHOWRES)           ; ДАЛЬНЕЙШИЙ ВВОД НЕ ИМЕЕТ СМЫСЛА, ПОКАЗЫВАЕМ СООБЩЕНИЕ ОБ ОШИБКЕ.
            RJMP OP1END                     ;

OP1CNVRT:   PUSH KEY                        ; ХОТЯ KEY УЖЕ ЕСТЬ В СТЕКЕ, НИЖЕ ОН НУЖЕН ДЛЯ ВЫВОДА НА LCD.
            PUSH RETL                       ; МЫ ВСЁ ЕЩЕ ВНУТРИ ОБРАБОТКИ ПРЕРЫВАНИЯ, ПОЭТОМУ ВАЖНО
            PUSH RETH                       ; НЕ ПОТЕРЯТЬ КОРРЕКТНЫЙ АДРЕС ВОЗВРАТА.
            CALL ATOF                       ;
            POP RETH                        ;
            POP RETL                        ;
            POP KEY                         ;

.IFDEF EMULKEYPD
            POP ZH                          ; ВОССТАНАВЛИВАЕМ УКАЗАТЕЛЬ НА ТЕСТОВУЮ ЧИСЛОВУЮ СТРОКУ.
            POP ZL                          ;
.ENDIF
            PUSH R11                        ; ПЕРВЫЙ ОПЕРАНД ВВЕДЕН И КОНВЕРТИРОВАН В FLOAT32.
            PUSH R10                        ; СОХРАНЯЕМ ЕГО В СТЕКЕ В LITTLE-ENDIAN.
            PUSH R9                         ;
            PUSH R8                         ;

            LDI XL,LOW(NUMSTR)              ; СБРАСЫВАЕМ УКАЗАТЕЛЯ СТРОКИ В НАЧАЛО.
            LDI XH,HIGH(NUMSTR)             ;

            CLR S                           ; СБРАСЫВАЕМ СЧЕТЧИК ВВЕДЕННЫХ СИМВОЛОВ.
            LDI R16,2                       ; ДАЛЕЕ БУДЕТ ВВОД ВТОРОГО ОПЕРАНДА.
            MOV P,R16                       ;
            LDI R16,LCDLEN                  ; ПРИ ВВОДЕ ВТОРОГО ОПЕРАНДА В КОНЦЕ СТРОКИ УЖЕ НЕ НАДО РЕЗЕРВИРОВАТЬ СИМВОЛ ПОД ОПЕРАТОР,
            MOV LCDLIM,R16                  ; ПОЭТОМУ ВСЯ СТРОКА LCD ОТВЕДЕНА ПОД ЧИСЛО.

.IFNDEF EMULKEYPD
            RCALL CURSL1END                 ; СТАВИМ КУРСОР В КОНЕЦ ВИДИМОЙ ЧАСТИ ПЕРВОЙ СТРОКИ LCD.
            PUSH S                          ;
            MOV CHAR,KEY                    ; ВЫВОДИМ СИМВОЛ ОПЕРАТОРА НА LCD.
            RCALL PRNTCHR                   ;
            POP S                           ;
            RCALL CURSL2BEG                 ; СТАВИМ КУРСОР В НАЧАЛО ВТОРОЙ СТРОКИ LCD.
.ENDIF

            LDI R16,LOW(S0)                 ; ВВОД ВТОРОГО ОПЕРАНДА ИДЕНТИЧЕН ВВОДУ ПЕРВОГО.
            LDI R17,HIGH(S0)                ;
OP1END:     PUSH R16                        ;
            PUSH R17                        ;
            PUSH RETL                       ;
            PUSH RETH                       ;
            RETI                            ;

            ;
            ; ВВОД ВТОРОГО ОПЕРАНДА ЗАВЕРШЁН.
OPERAND2:   LDI R16,0                       ; *NUMSTR='\0'.
            ST X,R16                        ;

            LDI XL,LOW(NUMSTR)              ; ВОЗВРАЩАЕМ УКАЗАТЕЛЬ В НАЧАЛО СТРОКИ
            LDI XH,HIGH(NUMSTR)             ; ПЕРЕД ВЫЗОВОМ ATOF.

            ;
            ; ОБРАБОТЧИК ОШИБОК, ВОЗНИКАЮЩИХ ПРИ ВЫЧИСЛЕНИЯХ С ПЛАВАЮЩЕЙ ТОЧКОЙ, КОТОРЫЕ ПРОИСХОДЯТ ВНУТРИ ATOF.
            ;
            ; В СИЛУ ТЕКУЩИХ ОГРАНИЧЕНИЙ НА ВВОД - ТОЛЬКО ДЕСЯТИЧНЫЕ ДРОБИ, БЕЗ ЭКСПОНЕНЦИАЛЬНОЙ ЗАПИСИ -
            ; ПРИ ВЫПОЛНЕНИИ ATOF ПЕРЕПОЛНЕНИЕ ВОЗНИКНУТЬ НЕ МОЖЕТ, А ДЕЛЕНИЕ НА НОЛЬ В ATOF НЕВОЗМОЖНО В ПРИНЦИПЕ.
            ;
            ; НО ЕСЛИ СПОСОБ ВВОДА БУДЕТ ОБНОВЛЁН, ТО ВОЗМОЖНО ПЕРЕПОЛНЕНИЕ ПРИ КОНВЕРТАЦИИ,
            ; КОГДА ДЛЯ ПРОМЕЖУТОЧНЫХ ВЫЧИСЛЕНИЯХ ОДИНАРНОЙ ТОЧНОСТИ СТАНОВИТСЯ НЕДОСТАТОЧНО.
            ;
            ; TODO: В СЛУЧАЕ ИСКЛЮЧЕНИЯ В ATOF ВЫВОДИТЬ ОШИБКУ НА LCD.
            ; СЕЙЧАС НЕ КРИТИЧНО, Т.К. ТЕКУЩИЕ ОГРАНИЧЕНИЯ НА ВВОД ОПЕРАНДОВ НЕ ПРИВЕДУТ К ИСКЛЮЧЕНИЮ В ATOF.
            LDI ZL,LOW(OP2FLTERR0)          ;
            LDI ZH,HIGH(OP2FLTERR0)         ;
            RJMP OP2CONVERT                 ;
OP2FLTERR0: POP R16                         ; ВЫБРАСЫВАЕМ ИЗ СТЕКА АДРЕС ВОЗВРАТА ПОСЛЕ ATOF.
            POP R16                         ;
            POP RETH                        ; ВОССТАНАВЛИВАЕМ АДРЕС ВОЗВРАТА ПОСЛЕ ПРЕРЫВАНИЯ.
            POP RETL                        ;
.IFDEF EMULKEYPD
            POP ZH                          ; ЕСЛИ МЫ В РЕЖИМЕ ЭМУЛЯЦИИ И ТЕСТИРОВАНИЯ ВВОДА С КЛАВИАТУРЫ, ТО
            POP ZL                          ; ВОССТАНАВЛИВАЕМ УКАЗАТЕЛЬ НА ТЕСТОВУЮ ЧИСЛОВУЮ СТРОКУ.
.ENDIF
            LDI YL,LOW(SP)                  ; В СТЕКЕ ОСТАЛОСЬ 4 БАЙТА ПЕРВОГО ОПЕРАНДА В ФОРМАТЕ FLOAT32
            LDI YH,HIGH(SP)                 ; И ОДИН БАЙТ СИМВОЛА АРИФМЕТИЧЕСКОГО ОПЕРАТОРА.
            OUT SPL,YL                      ; Т.К. ВОЗНИКЛО ИСКЛЮЧЕНИЕ И ОНИ НАМ БОЛЬШЕ НЕ НУЖНЫ,
            OUT SPH,YH                      ; МЫ ПРОСТО СБРАСЫВАЕМ СТЕК В ЕГО НАЧАЛЬНЫЙ АДРЕС.

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

            MOV R12,R8                      ; РАЗМЕЩАЕМ ВТОРОЙ ВВЕДЁННЫЙ ОПЕРАНД
            MOV R13,R9                      ; КАК ВТОРОЙ ОПЕРАНД АРИФМЕТИЧЕСКОЙ ОПЕРАЦИИ.
            MOV R14,R10                     ;
            MOV R15,R11                     ;

.IFDEF EMULKEYPD
            POP R18                         ; ВРЕМЕННО ВОССТАНАВЛИВАЕМ УКАЗАТЕЛЬ НА ТЕСТОВУЮ ЧИСЛОВУЮ СТРОКУ.
            POP R17                         ;
.ENDIF
            POP R8                          ; ИЗВЛЕКАЕМ ПЕРВЫЙ ВВЕДЁННЫЙ ОПЕРАНД И РАЗМЕЩАЕМ ЕГО
            POP R9                          ; КАК ПЕРВЫЙ ОПЕРАНД АРИФМЕТИЧЕСКОЙ ОПЕРАЦИИ.
            POP R10                         ;
            POP R11                         ;

            POP R16                         ; R16=OPERATOR.

.IFDEF EMULKEYPD
            PUSH R17                        ; СНОВА БЭКАПИМ УКАЗАТЕЛЬ НА ТЕСТОВУЮ СТРОКУ.
            PUSH R18                        ;
.ENDIF

            ;
            ; ОБРАБОТЧИК ОШИБОК ДЛЯ АРИФМЕТИЧЕСКИХ ПОДПРОГРАММ: FADD32, FSUB32, FMUL32, FDIV32.
            ;
            ; ЕСЛИ АРИФМЕТИЧЕСКАЯ ОПЕРАЦИЯ ВЫПОЛНЯЕТСЯ БЕЗ ПЕРЕПОЛНЕНИЯ ИЛИ ДЕЛЕНИЯ НА НОЛЬ,
            ; ТО ПОСЛЕДУЮЩЕЕ ВЫПОЛНЕНИЕ КОНВЕРТАЦИИ РЕЗУЛЬТАТА FTOA НЕ ПРИВЕДЁТ НИ К ПЕРЕПОЛНЕНИЮ, НИ К ДЕЛЕНИЮ НА НОЛЬ.
            ;
            ; БОЛЕЕ ТОГО, ИЗ-ЗА ТЕКУЩИХ ОГРАНИЧЕНИЙ НА ВВОД - ТОЛЬКО ДЕСЯТИЧНЫЕ ДРОБИ, БЕЗ ЭКСПОНЕНЦИАЛЬНОЙ ЗАПИСИ -
            ; СЕЙЧАС ПРИ ВЫПОЛНЕНИИ ЛЮБОЙ АРИФМЕТИЧЕСКОЙ ОПЕРАЦИИ МОЖЕТ ПРОИЗОЙТИ ТОЛЬКО ДЕЛЕНИЕ НА НОЛЬ.
            LDI ZL,LOW(OP2FLTERR1)          ; ЕСЛИ ПРИ ВЫЗОВЕ FADD32, FSUB32, FMUL32, FDIV32
            LDI ZH,HIGH(OP2FLTERR1)         ; ПРОИЗОЙДЕТ ОШИБКА: ДЕЛЕНИЕ НА НОЛЬ ИЛИ ПЕРЕПОЛНЕНИЕ,
            RJMP OPCHK                      ; ТО МЫ ПОПАДЁМ НА ЭТОТ ОБРАБОТЧИК.
OP2FLTERR1: POP R16                         ; АДРЕС ВОЗВРАТА ИЗ ПОДПРОГРАММЫ, КОТОРАЯ ВЫБРОСИЛА ИСКЛЮЧЕНИЕ,
            POP R16                         ; НАС БОЛЬШЕ НЕ ИНТЕРЕСУЕТ.
            POP RETH                        ; ПЕРЕД ВЫЗОВОМ АДРЕС ВОЗВРАТА ИЗ ПРЕРЫВАНИЯ БЫЛ ПОМЕЩЕН В СТЕК - ВОССТАНАВЛИВАЕМ ЕГО.
            POP RETL                        ;
.IFDEF EMULKEYPD
            POP ZH                          ; ЕСЛИ МЫ В РЕЖИМЕ ЭМУЛЯЦИИ И ТЕСТИРОВАНИЯ ВВОДА С КЛАВИАТУРЫ, ТО
            POP ZL                          ; ВОССТАНАВЛИВАЕМ УКАЗАТЕЛЬ НА ТЕСТОВУЮ ЧИСЛОВУЮ СТРОКУ.
.ENDIF

;
; ПОСКОЛЬКУ В РЕЖИМЕ ЭМУЛЯЦИИ КЛАВИАТУРЫ LCD НЕ ИСПОЛЬЗУЕТСЯ,
; СООБЩЕНИЕ ОБ ОШИБКЕ ДЛЯ ВИЗУАЛЬНОГО КОНТРОЛЯ ВЫВОДИМ В SRAM.
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
; ИНАЧЕ - ВЫВОДИМ ОШИБКУ СРАЗУ НА LCD.
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
            RJMP OP2END                     ; КОНЕЦ ОБРАБОТЧИКА ИСКЛЮЧЕНИЙ OP2FLTERR1.

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

            LDI R16,LCDLEN                  ; УСТАНАВЛИВАЕМ АРГУМЕНТ MAXLEN ПОДПРОГРАММЫ FTOAE
            MOV R12,R16                     ; РАВНЫМ КОЛИЧЕСТВУ СИМВОЛОВ В LCD.

            PUSH RETL                       ;
            PUSH RETH                       ;
            CALL FTOAE                      ; *NUMSTR=FTOAE(C,LCDLEN), ГДЕ C - РЕЗУЛЬТАТ ВЫЧИСЛЕНИЙ В ФОРМАТЕ БИНАРНОГО FLOAT32,
            POP RETH                        ; А LCDLEN - МАКСИМАЛЬНАЯ ДЛИНА ВЫХОДНОЙ СТРОКИ, РАВНАЯ ДЛИНЕ СТРОКИ В LCD.
            POP RETL                        ;

.IFNDEF EMULKEYPD
            RCALL DSBLCURS                  ;
            RCALL CLEARLCD                  ;

            LDI XL,LOW(NUMSTR)              ; СМЕЩАЕМ УКАЗАТЕЛЬ В НАЧАЛО СТРОКИ, СОДЕРЖАЩЕЙ РЕЗУЛЬТАТ ВЫЧИСЛЕНИЯ.
            LDI XH,HIGH(NUMSTR)             ;
            RCALL PRNTSTR                   ; ВЫВОДИМ СТРОКУ С РЕЗУЛЬТАТОМ НА LCD.
.ENDIF

.IFDEF EMULKEYPD
            POP ZH                          ; ВОССТАНАВЛИВАЕМ УКАЗАТЕЛЬ НА ТЕСТОВУЮ СТРОКУ.
            POP ZL                          ;
.ENDIF
OP2END:     LDI R16,LOW(SHOWRES)            ; РЕЗУЛЬТАТ ВЫЧИСЛЕН, НОВОЕ СОСТОЯНИЕ - ПОКАЗ РЕЗУЛЬТАТА.
            LDI R17,HIGH(SHOWRES)           ;
            PUSH R16                        ;
            PUSH R17                        ;
            PUSH RETL                       ;
            PUSH RETH                       ;
            RETI                            ;

            ;
            ; SHOWRES - ХОЛОСТОЕ СОСТОЯНИЕ ДЛЯ ПОКАЗА РЕЗУЛЬТАТА ПОСЛЕДНЕГО ВЫЧИСЛЕНИЯ.
            ;
            ; РАЗРЕШЕНА ТОЛЬКО КЛАВИША СБРОСА.
SHOWRES:    LDI R16,'C'                     ;
            EOR R16,KEY                     ; БЫЛА НАЖАТА КЛАВИША 'C'?
            BRNE STAY                       ; НЕТ, ИГНОРИРУЕМ НАЖАТИЕ.
            JMP RESETINPUT                  ; ДА, СБРАСЫВАЕМ СОСТОЯНИЕ КАЛЬКУЛЯТОРА НА НУЛЕВОЕ.

.IFDEF EMULKEYPD
STAY:       POP ZH                          ; ВОССТАНАВЛИВАЕМ УКАЗАТЕЛЬ НА ТЕСТОВУЮ ЧИСЛОВУЮ СТРОКУ.
            POP ZL                          ; СТЕК ПУСТОЙ.
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
            ; S3 - ПРОМЕЖУТОЧНОЕ СОСТОЯНИЕ ПОСЛЕ НАЖАТИЯ ТОЧКИ.
            ;
            ; ДОПУСТИМЫ ТОЛЬКО ЦИФРОВЫЕ КЛАВИШИ.
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
            MOV CHAR,KEY                    ; ВЫВОДИМ НАЖАТУЮ КЛАВИШУ НА LCD.
            RCALL PRNTCHR                   ;
            POP R17                         ;
            POP R16                         ;
            POP S                           ;
.ENDIF

.IFDEF EMULKEYPD
S3END:      POP ZH                          ; ВОССТАНАВЛИВАЕМ УКАЗАТЕЛЬ НА ТЕСТОВУЮ ЧИСЛОВУЮ СТРОКУ.
            POP ZL                          ;
            PUSH R16                        ; ЗАПОМИНАЕМ НОВОЕ СОСТОЯНИЕ.
            PUSH R17                        ;
            PUSH RETL                       ; ВОССТАНАВЛИВАЕМ АДРЕС ВОЗВРАТА ПОСЛЕ ПРЕРЫВАНИЯ.
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
            ; S4 - ВВОД ЦИФР ЦЕЛОЙ ЧАСТИ.
            ;
            ; В ЭТОМ СОСТОЯНИИ ДОПУСТИМЫ ВСЕ КЛАВИШИ, ПОЭТОМУ НЕТ ВЕТКИ ДЛЯ ДЕФОЛТНОГО ПОВЕДЕНИЯ.
            ; ЕСЛИ НАЖАТА КЛАВИША ДЕСЯТИЧНОЙ ТОЧКИ И ДОСТУПНО ТОЛЬКО ОДНО ЗНАКОМЕСТО (КАК РАЗ ПОД ТОЧКУ),
            ; ВВОД ТОЧКИ ИГНОРИРУЕТСЯ, ЧТОБЫ ИЗБЕЖАТЬ НЕКОРРЕКТНОГО ЗНАЧЕНИЯ С ВИСЯЩЕЙ ТОЧКОЙ ВИДА "123.".
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

S4SKIP:     LDI R16,LOW(S4)                 ; ИГНОРИРУЕМ НАЖАТИЕ, ОСТАЁМСЯ В ТЕКУЩЕМ СОСТОЯНИИ.
            LDI R17,HIGH(S4)                ;
            RJMP S4END                      ;

S4RESETIN:  JMP RESETINPUT                  ; ДАЛЬНИЙ ПРЫЖОК.

S4DECPNT:   MOV R16,LCDLIM                  ; R16=(LCDLIM-2)-S.
            DEC R16                         ;
            DEC R16                         ;
            MOV R17,S                       ;
            COM R17                         ; ЧТОБЫ ИЗБЕЖАТЬ СИТУАЦИИ "ВИСЯЩЕЙ" ТОЧКИ, ЕЁ ДОПУСКАЕТСЯ СТАВИТЬ ТОЛЬКО ЕСЛИ В СТРОКЕ
            INC R17                         ; ЕСТЬ МЕСТО КАК МИНИМУМ ЕЩЕ ПОД ДВА ЗНАКА - ПОД САМУ ТОЧКУ И ПОД ОДНУ ЦИФРУ ПОСЛЕ ТОЧКИ.
            ADD R16,R17                     ; НА ЭКРАНЕ ЕСТЬ МЕСТО ПОД '.' И КАК МИНИМУМ ЕЩЕ ОДНУ ЦИФРУ?
            BRMI S4SKIP                     ; НЕТ, ИГНОРИРУЕМ НАЖАТИЕ ТОЧКИ.
            LDI R16,LOW(S3)                 ; ДА, ОТОБРАЖАЕМ ТОЧКУ И ПЕРЕХОДИМ В НОВОЕ СОСТОЯНИЕ.
            LDI R17,HIGH(S3)                ;
            RJMP S4PRNTKEY                  ;

S4DIG09:    MOV R16,S                       ; ЕСЛИ S В ТЕКУЩЕМ СОСТОЯНИИ ОКАЗАЛСЯ МЕНЬШЕ LCDLIM, ТО В СЛЕДУЮЩЕМ СОСТОЯНИИ ОН БУДЕТ РАВЕН LCDLIM.
            EOR R16,LCDLIM                  ; S<LCDLIM?
            BREQ S4SKIP                     ; НЕТ, БОЛЬШЕ ЦИФР ВВЕСТИ НЕЛЬЗЯ, ИГНОРИРУЕМ ВВОД.
            LDI R16,LOW(S4)                 ; ДА, ОТОБРАЖАЕМ ЦИФРУ И ОСТАЕМСЯ В ТЕКУЩЕМ СОСТОЯНИИ,
            LDI R17,HIGH(S4)                ; ОЖИДАЯ СЛЕДУЮЩЕГО НАЖАТИЯ.
            RJMP S4PRNTKEY                  ;

S4OPERATOR: LDI R16,2                       ;
            EOR R16,P                       ; ЗАВЕРШЕН ВВОД ВТОРОГО ОПЕРАНДА?
            BREQ S4OPERAND2                 ; ДА, ПЕРЕХОДИМ К КОНВЕРТАЦИИ В FLOAT32 И ВЫЧИСЛЕНИЮ.
            RJMP OPERAND1                   ; НЕТ, ВВЕДЕН ПЕРВЫЙ ОПЕРАНД, КОНВЕРТИРУЕМ ЕГО В FLOAT.

S4OPERAND2: JMP OPERAND2                    ;

S4PRNTKEY:  ST X+,KEY                       ;
            INC S                           ;

.IFNDEF EMULKEYPD
            PUSH S                          ;
            PUSH R16                        ;
            PUSH R17                        ;
            MOV CHAR,KEY                    ; ВЫВОДИМ НАЖАТУЮ КЛАВИШУ НА LCD.
            RCALL PRNTCHR                   ;
            POP R17                         ;
            POP R16                         ;
            POP S                           ;
.ENDIF

.IFDEF EMULKEYPD
S4END:      POP ZH                          ; ВОССТАНАВЛИВАЕМ УКАЗАТЕЛЬ НА ТЕСТОВУЮ ЧИСЛОВУЮ СТРОКУ.
            POP ZL                          ;
            PUSH R16                        ; ЗАПОМИНАЕМ НОВОЕ СОСТОЯНИЕ.
            PUSH R17                        ;
            PUSH RETL                       ; ВОССТАНАВЛИВАЕМ АДРЕС ВОЗВРАТА ПОСЛЕ ПРЕРЫВАНИЯ.
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
            ; ВВОД ЦИФР ДРОБНОЙ ЧАСТИ.
            ;
            ; РАЗРЕШЕНЫ ВСЕ КЛАВИШИ, КРОМЕ ДЕСЯТИЧНОЙ ТОЧКИ.
S5:         LDI R16,'C'                     ;
            EOR R16,KEY                     ; KEY='C'?
            BREQ S5RESETIN                  ;

            LDI R16,0xF0                    ;
            AND R16,KEY                     ;
            LDI R17,0x30                    ;
            EOR R16,R17                     ; KEY=['0','9']?
            BREQ S5DIG09                    ;

            LDI R16,'.'                     ; ТОЧКА НЕ РАЗРЕШЕНА В ЭТОМ СОСТОЯНИИ.
            EOR R16,KEY                     ; KEY='.'?
            BREQ S5SKIP                     ; ДА, ИГНОРИРУЕМ НАЖАТИЕ КЛАВИШИ.

            LDI R16,0xF0                    ; ВЫШЕ МЫ ИСКЛЮЧИЛИ ТОЧКУ,
            AND R16,KEY                     ; ПОСКОЛЬКУ ОНА ТОЖЕ ИМЕЕТ 0x20 В ASCII В СТАРШЕМ БАЙТЕ.
            LDI R17,0x20                    ;
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
            BREQ S5SKIP                     ; НЕТ, БОЛЬШЕ ЦИФР ВВЕСТИ НЕЛЬЗЯ, ИГНОРИРУЕМ ВВОД.
            LDI R16,LOW(S5)                 ; ДА, ОТОБРАЖАЕМ ЦИФРУ И ОСТАЕМСЯ В ТЕКУЩЕМ СОСТОЯНИИ,
            LDI R17,HIGH(S5)                ; ОЖИДАЯ СЛЕДУЮЩЕГО НАЖАТИЯ.
            RJMP S5PRNTKEY                  ;

S5OPERATOR: LDI R16,2                       ;
            EOR R16,P                       ; ЗАВЕРШЕН ВВОД ВТОРОГО ОПЕРАНДА?
            BREQ S5OPERAND2                 ; ДА, ПЕРЕХОДИМ К КОНВЕРТАЦИИ В FLOAT32 И ВЫЧИСЛЕНИЮ.
            RJMP OPERAND1                   ; НЕТ, ВВЕДЕН ПЕРВЫЙ ОПЕРАНД, КОНВЕРТИРУЕМ ЕГО В FLOAT.

S5OPERAND2: JMP OPERAND2                    ; ДАЛЬНИЙ ПРЫЖОК.

S5PRNTKEY:  ST X+,KEY                       ;
            INC S                           ;

.IFNDEF EMULKEYPD
            PUSH S                          ;
            PUSH R16                        ;
            PUSH R17                        ;
            MOV CHAR,KEY                    ; ВЫВОДИМ НАЖАТУЮ КЛАВИШУ НА LCD.
            RCALL PRNTCHR                   ;
            POP R17                         ;
            POP R16                         ;
            POP S                           ;
.ENDIF

.IFDEF EMULKEYPD
S5END:      POP ZH                          ; ВОССТАНАВЛИВАЕМ УКАЗАТЕЛЬ НА ТЕСТОВУЮ ЧИСЛОВУЮ СТРОКУ.
            POP ZL                          ;
            PUSH R16                        ; ЗАПОМИНАЕМ НОВОЕ СОСТОЯНИЕ.
            PUSH R17                        ;
            PUSH RETL                       ; ВОССТАНАВЛИВАЕМ АДРЕС ВОЗВРАТА ПОСЛЕ ПРЕРЫВАНИЯ.
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
; НОВЫЙ СТАРТ КАЛЬКУЛЯТОРА.
RESET:      LDI YL,LOW(SP)                  ;
            LDI YH,HIGH(SP)                 ;
            OUT SPL,YL                      ;
            OUT SPH,YH                      ;

.IFNDEF EMULKEYPD
            RCALL INITLCD                   ;
.ENDIF

;
; ЭМУЛЯЦИЯ ВВОДА С КЛАВИАТУРЫ ДЛЯ ПРОВЕРКИ ОБРАБОТЧИКА ПРЕРЫВАНИЙ ПО КЛАВИАТУРЕ.
;
; КОНФИГУРАЦИЯ ПОРТА D - НА ВЫХОД, НА ВРЕМЯ ПРОГРАММНОГО ТЕСТИРОВАНИЯ ВВОДА С КЛАВИАТУРЫ.
; ЭТО НУЖНО ДЛЯ ВЫСТАВЛЕНИЯ ДАННЫХ НА ПОРТУ И ПРОГРАММНОГО ВЫЗОВА ПРЕРЫВАНИЯ ПРЯМО ИЗ ЭТОГО КОДА.
.IFDEF EMULKEYPD
            SER R16                         ; НАСТРАИВАЕМ ПОРТ D НА ВЫХОД,
            OUT DDRD,R16                    ; ЧТОБЫ ПРОГРАММНО ВЫСТАВЛЯТЬ КОД КЛАВИШИ И ИНИЦИИРОВАТЬ ПРЕРЫВАНИЕ ПО INT0.
            LDI R16,0x00                    ;
            OUT PORTD,R16                   ;
.ELSE
            CLR R16                         ;
            OUT DDRD,R16                    ;
.ENDIF

            LDI R16,(1<<ISC01|1<<ISC00)     ; РАЗРЕШАЕМ ВНЕШНИЕ ПРЕРЫВАНИЯ
            STS EICRA,R16                   ; ПО INT0, ПО ПЕРЕДНЕМУ ФРОНТУ - ТАМ СИДИТ КЛАВИАТУРА.
            LDI R16,(1<<INT0)               ;
            OUT EIMSK,R16                   ;
            SEI                             ;

            LDI ZL,LOW(KEYMAPPRG<<1)        ; ЧИТАЕМ ТАБЛИЦУ ASCII-КОДОВ КЛАВИШ В SRAM.
            LDI ZH,HIGH(KEYMAPPRG<<1)       ;
            LDI XL,LOW(KEYMAP)              ;
            LDI XH,HIGH(KEYMAP)             ;
READ:       LPM R0,Z+                       ;
            AND R0,R0                       ; ПРОЧИТАЛИ NUL?
            BREQ MAIN                       ; ДА, ВСЕ СИМВОЛЫ СЧИТАНЫ В SRAM.
            ST X+,R0                        ; НЕТ, ЗАПИСЫВАЕМ СИМВОЛ В SRAM И ПРОДОЛЖАЕМ.
            RJMP READ                       ;

;
;
MAIN:       NOP
            
            ;
            ; НАЧАЛЬНЫЙ СБРОС КАЛЬКУЛЯТОРА.
            LDI XL,LOW(NUMSTR)              ; СМЕЩАЕМ УКАЗАТЕЛЬ NUMSTR В НАЧАЛО СТРОКИ.
            LDI XH,HIGH(NUMSTR)             ;

            LDI R16,0                       ; S=0.
            MOV S,R16                       ;

            LDI R16,1                       ; P=1.
            MOV P,R16                       ;

            LDI R16,LCDLEN-1                ; РЕЗЕРВИРУЕМ ПОСЛЕДНИЙ СИМВОЛ ПЕРВОЙ СТРОКИ ПОД СИМВОЛ ОПЕРАТОРА.
            MOV LCDLIM,R16                  ;

            LDI R16,LOW(S0)                 ; НАЧАЛЬНОЕ СОСТОЯНИЕ - S0.
            LDI R17,HIGH(S0)                ;
            PUSH R16                        ;
            PUSH R17                        ;
            
;
; ЭМУЛЯЦИЯ ВВОДА С КЛАВИАТУРЫ ДЛЯ ПРОВЕРКИ ОБРАБОТЧИКА ПРЕРЫВАНИЙ ПО КЛАВИАТУРЕ.
;
; ЧИТАЕМ КАЖДЫЙ СИМВОЛ ЧИСЛОВОЙ СТРОКИ ИЗ ПАМЯТИ ПРОГРАММ,
; ПРЕОБРАЗУЕМ ЕГО ASCII КОД В СЫРОЙ КОД ЭНКОДЕРА КЛАВИАТУРЫ,
; ВЫСТАВЛЯЕМ КОД НА ПОРТУ D И УСТАНАВЛИВАЕТ ПИН INT0 В ЕДИНИЦУ,
; ВЫЗЫВАЯ ПРЕРЫВАНИЕ ПО КЛАВИАТУРЕ ПРОГРАММНО.
.IFDEF EMULKEYPD
            ;
            ; РАСКОММЕНТИРОВАТЬ ПРИ ТЕСТИРОВАНИИ ВВОДА ВТОРОГО ОПЕРАНДА.
;            LDI R16,2                       ;
;            MOV P,R16                       ;

;            LDI R16,LCDLEN                  ;
;            MOV LCDLIM,R16                  ;

            ;
            ; ИНИЦИАЛИЗАЦИЯ ОБРАТНОЙ ТАБЛИЦЫ КЛАВИШ - ОТОБРАЖЕНИЕ ASCII-КОДА КЛАВИШИ В СЫРОЙ КОД ЭНКОДЕРА.
            ;
            ; ASCII-КОД ИСПОЛЬЗУЕТСЯ КАК МЛАДШИЙ БАЙТ АДРЕСА В SRAM, ПО КОТОРОМУ ЗАПИСЫВАЕТСЯ СЫРОЙ КОД.
            ; ЧИТАЕМ ЧИСЛОВУЮ СТРОКУ, ПРЕОБРАЗУЯ ASCII-КОД КАЖДОГО СИМВОЛА В СЫРОЙ КОД КЛАВИШИ И
            ; ВЫСТАВЛЯЕМ ЭТОТ КОД НА ПОРТУ D, ИНИЦИИРУЯ ПРЕРЫВАНИЕ ПО INT0 ПОСЛЕ КАЖДОГО ПРОЧИТАННОГО СИМВОЛА.
            ; ТАКИМ ОБРАЗОМ ПРОГРАММНО ЭМУЛИРУЕТСЯ ВВОД С КЛАВИАТУРЫ.
            LDI R17,0x00                    ; СЫРОЙ КОД КЛАВИШИ.
            LDI ZL,LOW(KEYMAPPRG << 1)      ;
            LDI ZH,HIGH(KEYMAPPRG << 1)     ;
READ0:      LPM R4,Z+                       ;
            AND R4,R4                       ; ДОСТИГЛИ КОНЦА СТРОКИ?
            BREQ EMULINPUT                  ; ДА, ТАБЛИЦА СФОРМИРОВАНА, ПЕРЕХОДИМ К ЭМУЛЯЦИИ ВВОДА С КЛАВИАТУРЫ.
            MOV YL,R4                       ; НЕТ, ПРОДОЛЖАЕМ.
            LDI YH,HIGH(REVKEYMAP)          ;
            ST Y,R17                        ; ЗАПИСЫВАЕМ СЫРОЙ КОД КЛАВИШИ.
            INC R17                         ; ПЕРЕХОДИМ К СЛЕДУЮЩЕМУ СИМВОЛУ.
            RJMP READ0                      ;

            ;
            ; ЭМУЛЯЦИЯ ВВОДА АРИФМЕТИЧЕСКИХ ВЫРАЖЕНИЙ.
            ;
            ; NOTE: ПРИ ТЕСТИРОВАНИИ ВВОДА, ЕСЛИ ПОСЛЕ ЧТЕНИЯ ПЕРВОГО ОПЕРАНДА ВОЗНИКАЕТ ИСКЛЮЧЕНИЕ,
            ; НЕСМОТРЯ НА ФОРМИРОВАНИЕ СООБЩЕНИЯ ОБ ОШИБКЕ И ПЕРЕХОД В СОСТОЯНИЕ SHOWRES, КОТОРОЕ
            ; ИГНОРИРУЕТ ЛЮБОЙ ВВОД КРОМЕ КЛАВИШИ СБРОСА, ЦИКЛ ЭМУЛЯЦИИ ПРОДОЛЖИТ ЧИТАТЬ ВЫРАЖЕНИЕ ДО КОНЦА СТРОКИ,
            ; ВЫЗЫВАЯ ПРЕРЫВАНИЯ ПО КЛАВИАТУРЕ И ПОПАДАЯ В SHOWRES.
            ; НО ПОСКОЛЬКУ СИМВОЛА 'C' В ПОЛНОМ АРИФМЕТИЧЕСКОМ ВЫРАЖЕНИИ НЕ БУДЕТ, НИКАКИХ ИЗМЕНЕНИЙ В СОСТОЯНИИ КАЛЬКУЛЯТОРА
            ; НЕ ПРОИЗОЙДЕТ. ПОВЕДЕНИЕ БУДЕТ ТАКИМ ЖЕ, КАК В СЛУЧАЕ, КОГДА ПОЛЬЗОВАТЕЛЬ ПОЛУЧИЛ СООБЩЕНИЕ ОБ ОШИБКЕ И ПРОДОЛЖАЕТ
            ; НАЖИМАТЬ ЦИФРОВЫЕ КЛАВИШИ И КЛАВИШИ ОПЕРАТОРОВ, А КАЛЬКУЛЯТОР ИГНОРИРУЕТ ВВОД И ОЖИДАЕТ ТОЛЬКО НАЖАТИЕ КЛАВИШИ 'C'.
EMULINPUT:  LDI ZL,LOW(TESTNUM << 1)        ;
            LDI ZH,HIGH(TESTNUM << 1)       ;
READ1:      LPM R4,Z+                       ;
            AND R4,R4                       ; ДОСТИГЛИ КОНЦА СТРОКИ?
            BREQ END                        ; ДА, ЧИСЛОВАЯ СТРОКА "ВВЕДЕНА".
            MOV YL,R4                       ; НЕТ, МАПИМ ASCII-СИМВОЛ В КОД ЭНКОДЕРА.
            LDI YH,HIGH(REVKEYMAP)          ;
            LD R16,Y                        ;
            CLC                             ;
            ROL R16                         ; РАЗМЕЩАЕМ БИТЫ КОДА В СТАРШЕМ ПОЛУБАЙТЕ ПОРТА D.
            ROL R16                         ;
            ROL R16                         ;
            ROL R16                         ;
            LDI R17,0b00000100              ; ЭМУЛИРУЕМ БИТ ГОТОВНОСТИ ДАННЫХ,
            EOR R16,R17                     ; УСТАНАВЛИВАЯ INT0 В ЕДИНИЦУ. ЭТО ИНИЦИИРУЕТ ПРЕРЫВАНИЕ.
            OUT PORTD,R16                   ;
            LDI R17,0b11111011              ; УБИРАЕМ БИТ ГОТОВНОСТИ ДАННЫХ, ЧТОБЫ НА СЛЕДУЮЩЕЙ ИТЕРАЦИИ
            AND R16,R17                     ; ВНОВЬ ИНИЦИИРОВАТЬ ПРЕРЫВАНИЕ.
            OUT PORTD,R16                   ;
            RJMP READ1                      ;
.ENDIF

END:        RJMP END

;
; ТАБЛИЦА ASCII-КОДОВ НАЖАТЫХ КЛАВИШ.
KEYMAPPRG:  .DB "C0./789x456-123+",0

;
; ТЕСТОВЫЕ ПРИМЕРЫ ДЛЯ ПРОВЕРКИ КОРРЕКТНОГО ВВОДА С КЛАВИАТУРЫ.
; ПРИМЕРЫ ОПРЕДЕЛЕНЫ В [ТРАЕКТОРИИ НА ГРАФЕ СОСТОЯНИЙ И ТЕСТОВЫЕ ПРИМЕРЫ.XMIND].
; СНАЧАЛА ПОРЯД ИДУТ "ЗЕЛЁНЫЕ" ПРИМЕРЫ, СОДЕРЖАЩИЕ КОРРЕКТНЫЕ ЧИСЛОВЫЕ СТРОКИ.
; ДАЛЕЕ, С НОВОЙ НУМЕРАЦИЕЙ, ИДУТ "ЖЁЛТЫЕ" ПРИМЕРЫ, СОДЕРЖАЩИЕ НЕКОРРЕКТНЫЕ ЧИСЛОВЫЕ СТРОКИ,
; КОТОРЫЕ ДОЛЖНЫ БЫТЬ ПРОИГНОРИРОВАНЫ ОБРАБОТЧИКОМ КЛАВИАТУРЫ.
.IFDEF EMULKEYPD
            ; ПРИМЕР 1. КОРРЕКТНЫЕ ЗНАЧЕНИЯ.
;TESTNUM:  .DB "0.0123456789123",0

            ; ПРИМЕР 2. КОРРЕКТНЫЕ ЗНАЧЕНИЯ. ВТОРОЙ ОПЕРАНД.
;TESTNUM:  .DB "0.01234567891234",0

            ; ПРИМЕР 3. КОРРЕКТНЫЕ ЗНАЧЕНИЯ.
;TESTNUM:  .DB "0",0

            ; ПРИМЕР 4. КОРРЕКТНЫЕ ЗНАЧЕНИЯ.
;TESTNUM:  .DB "7.0123456789123",0

            ; ПРИМЕР 5. КОРРЕКТНЫЕ ЗНАЧЕНИЯ.
;TESTNUM:  .DB "1234567890123.0",0

            ; ПРИМЕР 6. КОРРЕКТНЫЕ ЗНАЧЕНИЯ. ВТОРОЙ ОПЕРАНД.
;TESTNUM:  .DB "7.01234567891234",0

            ; ПРИМЕР 7. КОРРЕКТНЫЕ ЗНАЧЕНИЯ. ВТОРОЙ ОПЕРАНД.
;TESTNUM:  .DB "12345678901234.9",0

            ; ПРИМЕР 8. КОРРЕКТНЫЕ ЗНАЧЕНИЯ.
;TESTNUM:  .DB "123456789012345",0

            ; ПРИМЕР 9. КОРРЕКТНЫЕ ЗНАЧЕНИЯ. ВТОРОЙ ОПЕРАНД.
;TESTNUM:  .DB "1234567890123456",0

            ; ПРИМЕР 10. КОРРЕКТНЫЕ ЗНАЧЕНИЯ.
;TESTNUM:  .DB "3",0

            ; ПРИМЕР 11. КОРРЕКТНЫЕ ЗНАЧЕНИЯ.
;TESTNUM:  .DB "-0.012345678912",0

            ; ПРИМЕР 12. КОРРЕКТНЫЕ ЗНАЧЕНИЯ. ВТОРОЙ ОПЕРАНД.
;TESTNUM:  .DB "-0.0123456789123",0

            ; ПРИМЕР 13. КОРРЕКТНЫЕ ЗНАЧЕНИЯ.
;TESTNUM:  .DB "-0",0

            ; ПРИМЕР 14. КОРРЕКТНЫЕ ЗНАЧЕНИЯ.
;TESTNUM:  .DB "-7.012345678912",0

            ; ПРИМЕР 15. КОРРЕКТНЫЕ ЗНАЧЕНИЯ.
;TESTNUM:  .DB "-123456789012.5",0

            ; ПРИМЕР 16. КОРРЕКТНЫЕ ЗНАЧЕНИЯ. ВТОРОЙ ОПЕРАНД.
;TESTNUM:  .DB "-7.0123456789123",0

            ; ПРИМЕР 17. КОРРЕКТНЫЕ ЗНАЧЕНИЯ. ВТОРОЙ ОПЕРАНД.
;TESTNUM:  .DB "-1234567890123.5",0

            ; ПРИМЕР 18. КОРРЕКТНЫЕ ЗНАЧЕНИЯ.
;TESTNUM:  .DB "-12345678901234",0

            ; ПРИМЕР 19. КОРРЕКТНЫЕ ЗНАЧЕНИЯ. ВТОРОЙ ОПЕРАНД.
;TESTNUM:  .DB "-123456789012345",0

            ; ПРИМЕР 20. КОРРЕКТНЫЕ ЗНАЧЕНИЯ.
;TESTNUM:  .DB "-8",0


            ; ПРИМЕР 1. НЕКОРРЕКТНЫЕ ЗНАЧЕНИЯ.
;TESTNUM:  .DB "0.01234567891234",0

            ; ПРИМЕР 2. НЕКОРРЕКТНЫЕ ЗНАЧЕНИЯ. ВТОРОЙ ОПЕРАНД.
;TESTNUM:  .DB "0.012345678912345",0

            ; ПРИМЕР 3. НЕКОРРЕКТНЫЕ ЗНАЧЕНИЯ.
;TESTNUM:  .DB "0.7.",0

            ; ПРИМЕР 4. НЕКОРРЕКТНЫЕ ЗНАЧЕНИЯ.
;TESTNUM:  .DB "0..",0
;TESTNUM:  .DB "0.+",0

            ; ПРИМЕР 5. НЕКОРРЕКТНЫЕ ЗНАЧЕНИЯ.
;TESTNUM:  .DB "01",0
;TESTNUM:  .DB "00",0

            ; ПРИМЕР 6. НЕКОРРЕКТНЫЕ ЗНАЧЕНИЯ.
;TESTNUM:  .DB "7.01234567891234",0

            ; ПРИМЕР 7. НЕКОРРЕКТНЫЕ ЗНАЧЕНИЯ.
;TESTNUM:  .DB "7.012345678912345",0

            ; ПРИМЕР 8. НЕКОРРЕКТНЫЕ ЗНАЧЕНИЯ.
;TESTNUM:  .DB "1.0.",0

            ; ПРИМЕР 9. НЕКОРРЕКТНЫЕ ЗНАЧЕНИЯ.
;TESTNUM:  .DB "4..",0
;TESTNUM:  .DB "4.*",0

            ; ПРИМЕР 10. НЕКОРРЕКТНЫЕ ЗНАЧЕНИЯ.
;TESTNUM:  .DB "123456789012345.",0
;TESTNUM:  .DB "12345678901234.",0

            ; ПРИМЕР 11. НЕКОРРЕКТНЫЕ ЗНАЧЕНИЯ. ВТОРОЙ ОПЕРАНД.
;TESTNUM:  .DB "1234567890123456.",0
;TESTNUM:  .DB "123456789012345.",0

            ; ПРИМЕР 12. НЕКОРРЕКТНЫЕ ЗНАЧЕНИЯ.
;TESTNUM:  .DB "1234567890123456",0

            ; ПРИМЕР 13. НЕКОРРЕКТНЫЕ ЗНАЧЕНИЯ. ВТОРОЙ ОПЕРАНД.
;TESTNUM:  .DB "12345678901234567",0

            ; ПРИМЕР 14. НЕКОРРЕКТНЫЕ ЗНАЧЕНИЯ.
;TESTNUM:  .DB "-0.0123456789123",0

            ; ПРИМЕР 15. НЕКОРРЕКТНЫЕ ЗНАЧЕНИЯ. ВТОРОЙ ОПЕРАНД.
;TESTNUM:  .DB "-0.01234567891234",0

            ; ПРИМЕР 16. НЕКОРРЕКТНЫЕ ЗНАЧЕНИЯ.
;TESTNUM:  .DB "-0.0.",0

            ; ПРИМЕР 17. НЕКОРРЕКТНЫЕ ЗНАЧЕНИЯ.
;TESTNUM:  .DB "-0..",0
;TESTNUM:  .DB "-0./",0

            ; ПРИМЕР 18. НЕКОРРЕКТНЫЕ ЗНАЧЕНИЯ.
;TESTNUM:  .DB "-09",0
;TESTNUM:  .DB "-00",0

            ; ПРИМЕР 19. НЕКОРРЕКТНЫЕ ЗНАЧЕНИЯ.
;TESTNUM:  .DB "-7.0123456789123",0

            ; ПРИМЕР 20. НЕКОРРЕКТНЫЕ ЗНАЧЕНИЯ. ВТОРОЙ ОПЕРАНД.
;TESTNUM:  .DB "-7.01234567891234",0

            ; ПРИМЕР 21. НЕКОРРЕКТНЫЕ ЗНАЧЕНИЯ.
;TESTNUM:  .DB "-9.0.",0

            ; ПРИМЕР 22. НЕКОРРЕКТНЫЕ ЗНАЧЕНИЯ.
;TESTNUM:  .DB "-6..",0
;TESTNUM:  .DB "-6.+",0

            ; ПРИМЕР 23. НЕКОРРЕКТНЫЕ ЗНАЧЕНИЯ.
;TESTNUM:  .DB "-12345678901234.",0
;TESTNUM:  .DB "-1234567890123.",0

            ; ПРИМЕР 24. НЕКОРРЕКТНЫЕ ЗНАЧЕНИЯ. ВТОРОЙ ОПЕРАНД.
;TESTNUM:  .DB "-123456789012345.",0
;TESTNUM:  .DB "-12345678901234.",0

            ; ПРИМЕР 25. НЕКОРРЕКТНЫЕ ЗНАЧЕНИЯ.
;TESTNUM:  .DB "-123456789012345",0

            ; ПРИМЕР 26. НЕКОРРЕКТНЫЕ ЗНАЧЕНИЯ. ВТОРОЙ ОПЕРАНД.
;TESTNUM:  .DB "-1234567890123456",0

            ; ПРИМЕР 27. НЕКОРРЕКТНЫЕ ЗНАЧЕНИЯ.
;TESTNUM:  .DB "-.",0
;TESTNUM:  .DB "--",0

            ; ПРИМЕР 28. НЕКОРРЕКТНЫЕ ЗНАЧЕНИЯ.
;TESTNUM:  .DB ".",0
;TESTNUM:  .DB "/",0

            ;
            ; ПРИМЕР 1. ОБРАБОТКА ИСКЛЮЧЕНИЙ. ИСКЛЮЧЕНИЕ ПРИ ДЕЛЕНИИ НА НОЛЬ.
;TESTNUM:  .DB "1/0+",0

            ;
            ; ПРИМЕР 2. ОБРАБОТКА ИСКЛЮЧЕНИЙ. ПЕРЕПОЛНЕНИЕ В ATOF ПРИ КОНВЕРТАЦИИ ВТОРОГО ОПЕРАНДА.
            ; ДЛЯ ТЕСТОВ НУЖНО ВРЕМЕННО УВЕЛИЧИТЬ LCDLEN ДО 40 ЗНАКОВ,
            ; ЧТОБЫ В ПЕРВУЮ СТРОКУ ВОШЛО 39 ДЕСЯТИЧНЫХ РАЗРЯДОВ (ПОСЛЕДНИЙ ЗАРЕЗЕРВИРОВАН ПОД СИМВОЛ ОПЕРАТОРА).
;TESTNUM:  .DB "1/340282430000000000000000000000000000000+",0

            ;
            ; ПРИМЕР 3. ОБРАБОТКА ИСКЛЮЧЕНИЙ. ПЕРЕПОЛНЕНИЕ В ATOF ПРИ КОНВЕРТАЦИИ ПЕРВОГО ОПЕРАНДА.
            ; ДЛЯ ТЕСТОВ НУЖНО ВРЕМЕННО УВЕЛИЧИТЬ LCDLEN ДО 40 ЗНАКОВ.
;TESTNUM:  .DB "340282430000000000000000000000000000000/3.7+",0

            ;
            ; ПРИМЕР 1. АРИФМЕТИЧЕСКИЕ ВЫРАЖЕНИЯ. ТРИГГЕР ВЫЧИСЛЕНИЯ.
;TESTNUM:  .DB "2+3+",0
;TESTNUM:  .DB "2+3-",0
;TESTNUM:  .DB "2+3*",0
;TESTNUM:  .DB "2+3/",0

            ;
            ; ПРИМЕР 2. АРИФМЕТИЧЕСКИЕ ВЫРАЖЕНИЯ. ЗНАКИ ОПЕРАНДОВ.
;TESTNUM:  .DB "10*7+",0

            ;
            ; ПРИМЕР 3. АРИФМЕТИЧЕСКИЕ ВЫРАЖЕНИЯ. ЗНАКИ ОПЕРАНДОВ.
;TESTNUM:  .DB "10*-7+",0

            ;
            ; ПРИМЕР 4. АРИФМЕТИЧЕСКИЕ ВЫРАЖЕНИЯ. ЗНАКИ ОПЕРАНДОВ.
;TESTNUM:  .DB "-10*7+",0

            ;
            ; ПРИМЕР 5. АРИФМЕТИЧЕСКИЕ ВЫРАЖЕНИЯ. ЗНАКИ ОПЕРАНДОВ.
;TESTNUM:  .DB "-10*-7+",0

            ;
            ; ПРИМЕР 6. АРИФМЕТИЧЕСКИЕ ВЫРАЖЕНИЯ. НАИМЕНЬШИЕ ЗНАЧЕНИЯ ОПЕРАНДОВ.
;TESTNUM:  .DB "0.0000000000001+0.00000000000001+",0

            ;
            ; ПРИМЕР 7. АРИФМЕТИЧЕСКИЕ ВЫРАЖЕНИЯ. НАИБОЛЬШИЕ ЗНАЧЕНИЯ ОПЕРАНДОВ.
;TESTNUM:  .DB "999999999999999+9999999999999999+",0

            ;
            ; ПРИМЕР 8. АРИФМЕТИЧЕСКИЕ ВЫРАЖЕНИЯ. НАИМЕНЬШИЙ РЕЗУЛЬТАТ.
;TESTNUM:  .DB "0.0000000000001/9999999999999999+",0

            ;
            ; ПРИМЕР 9. АРИФМЕТИЧЕСКИЕ ВЫРАЖЕНИЯ. НАИБОЛЬШИЙ РЕЗУЛЬТАТ.
;TESTNUM:  .DB "999999999999999*9999999999999999+",0

            ;
            ; ПРИМЕР 10. АРИФМЕТИЧЕСКИЕ ВЫРАЖЕНИЯ. АРИФМЕТИЧЕСКИЙ ОПЕРАТОР.
;TESTNUM:  .DB "9+1+",0

            ;
            ; ПРИМЕР 11. АРИФМЕТИЧЕСКИЕ ВЫРАЖЕНИЯ. АРИФМЕТИЧЕСКИЙ ОПЕРАТОР.
;TESTNUM:  .DB "10-1+",0

            ;
            ; ПРИМЕР 12. АРИФМЕТИЧЕСКИЕ ВЫРАЖЕНИЯ. АРИФМЕТИЧЕСКИЙ ОПЕРАТОР.
;TESTNUM:  .DB "3*2+",0

            ;
            ; ПРИМЕР 13. АРИФМЕТИЧЕСКИЕ ВЫРАЖЕНИЯ. АРИФМЕТИЧЕСКИЙ ОПЕРАТОР.
;TESTNUM:  .DB "1/2+",0

            ;
            ; ПРИМЕР 14. АРИФМЕТИЧЕСКИЕ ВЫРАЖЕНИЯ. НУЛЕВЫЕ ОПЕРАНДЫ.
;TESTNUM:  .DB "5+0+",0

            ;
            ; ПРИМЕР 15. АРИФМЕТИЧЕСКИЕ ВЫРАЖЕНИЯ. НУЛЕВЫЕ ОПЕРАНДЫ.
;TESTNUM:  .DB "0+5+",0

            ;
            ; ПРИМЕР 16. АРИФМЕТИЧЕСКИЕ ВЫРАЖЕНИЯ. НУЛЕВЫЕ ОПЕРАНДЫ.
;TESTNUM:  .DB "5-0+",0

            ;
            ; ПРИМЕР 17. АРИФМЕТИЧЕСКИЕ ВЫРАЖЕНИЯ. НУЛЕВЫЕ ОПЕРАНДЫ.
;TESTNUM:  .DB "0-5+",0

            ;
            ; ПРИМЕР 18. АРИФМЕТИЧЕСКИЕ ВЫРАЖЕНИЯ. НУЛЕВЫЕ ОПЕРАНДЫ.
;TESTNUM:  .DB "5*0+",0

            ;
            ; ПРИМЕР 19. АРИФМЕТИЧЕСКИЕ ВЫРАЖЕНИЯ. НУЛЕВЫЕ ОПЕРАНДЫ.
;TESTNUM:  .DB "0*5+",0

            ;
            ; ПРИМЕР 20. АРИФМЕТИЧЕСКИЕ ВЫРАЖЕНИЯ. НУЛЕВЫЕ ОПЕРАНДЫ.
;TESTNUM:  .DB "5/0+",0

            ;
            ; ПРИМЕР 21. АРИФМЕТИЧЕСКИЕ ВЫРАЖЕНИЯ. НУЛЕВЫЕ ОПЕРАНДЫ.
;TESTNUM:  .DB "0/5+",0

            ;
            ; ПРИМЕР 22. АРИФМЕТИЧЕСКИЕ ВЫРАЖЕНИЯ. НУЛЕВЫЕ ОПЕРАНДЫ.
;TESTNUM:  .DB "-0+5+",0

            ;
            ; ПРИМЕР 23. АРИФМЕТИЧЕСКИЕ ВЫРАЖЕНИЯ. НУЛЕВЫЕ ОПЕРАНДЫ.
;TESTNUM:  .DB "0/0+",0
            
            ;
            ; ПРИМЕР 24. АРИФМЕТИЧЕСКИЕ ВЫРАЖЕНИЯ. СЛУЧАЙНЫЙ ПРИМЕР.
;TESTNUM:  .DB "301.9533944630/23204.0642586600+",0

            ;
            ; ПРИМЕР 1. ПРОВЕРКА СБРОСА В СОСТОЯНИИ S0.
            ; NOTE: СМ. ГРАФ СОСТОЯНИЙ, ЧТОБЫ ПОНЯТЬ,
            ; КАКИЕ КЛАВИШИ В КАКИЕ СОСТОЯНИЯ ПЕРЕВОДЯТ КАЛЬКУЛЯТОР.
;TESTNUM:  .DB "C",0

            ;
            ; ПРИМЕР 2. ПРОВЕРКА СБРОСА В СОСТОЯНИИ S1.
;TESTNUM:  .DB "0C",0

            ;
            ; ПРИМЕР 3. ПРОВЕРКА СБРОСА В СОСТОЯНИИ S2.
;TESTNUM:  .DB "-C",0

            ;
            ; ПРИМЕР 4. ПРОВЕРКА СБРОСА В СОСТОЯНИИ S3.
;TESTNUM:  .DB "1.C",0
            
            ;
            ; ПРИМЕР 5. ПРОВЕРКА СБРОСА В СОСТОЯНИИ S4.
;TESTNUM:  .DB "1C",0

            ;
            ; ПРИМЕР 6. ПРОВЕРКА СБРОСА В СОСТОЯНИИ S5 - ФАЗА ВВОДА ПЕРВОГО ОПЕРАНДА.
;TESTNUM:  .DB "1.2C",0

            ;
            ; ПРИМЕР 7. ПРОВЕРКА СБРОСА В СОСТОЯНИИ SHOWRES БЕЗ ОШИБКИ.
;TESTNUM:  .DB "1.5*2+C",0

            ;
            ; ПРИМЕР 7. ПРОВЕРКА СБРОСА В СОСТОЯНИИ SHOWRES ПОСЛЕ ОШИБКИ.
            ; NOTE: ПРИ ВЫЧИСЛЕНИИ РЕЗУЛЬТАТА ПРОИЗОШЛА ОШИБКА.
;TESTNUM:  .DB "1/0+C",0

            ;
            ; ПРИМЕР 8. ПРОВЕРКА СБРОСА ПОСЛЕ ВВОДА ПЕРВОГО ОПЕРАНДА И ОПЕРАТОРА - ФАЗА ВВОДА ВТОРОГО ОПЕРАНДА.
            ; NOTE: В ЭТОМ СЦЕНАРИИ В СТЕКЕ УЖЕ ЛЕЖИТ ПЕРВЫЙ ОПЕРАНД В ФОРМАТЕ FLOAT32
            ; И СИМВОЛ ОПЕРАТОРА. ЭТОТ ТЕСТ ПРОВЕРЯЕТ, ЧТО ПОСЛЕ СБРОСА СТЕК ОЧИЩАЕТСЯ.
;TESTNUM:  .DB "15+C",0
.ENDIF

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
            ; S1 - промежуточное состояние после нажатия нуля.
            ;
            ; Допустимы только точка или клавиши оператора.
S1:         LDI R16,'C'                     ;
            EOR R16,KEY                     ; KEY='C'?
            BREQ S1RESETIN                  ;

            LDI R16,'.'                     ;
            EOR R16,KEY                     ; KEY='.'?
            BREQ S1DECPNT                   ;

            LDI R16,0xF0                    ; '+','-','*','/' - в ASCII имеют одинаковый старший полубайт равный 0x20.
            AND R16,KEY                     ; А '.' мы уже исключили выше.
            LDI R17,0x20                    ;
            EOR R16,R17                     ; KEY=['+','-','/']?
            BREQ S1OPERATOR                 ;
            LDI R16,'x'                     ; Мы заменили символ умножения на 'x', который находится в последней строке ASCII-таблицы.
            EOR R16,KEY                     ; KEY='x'?
            BREQ S1OPERATOR                 ;

            LDI R16,LOW(S1)                 ;
            LDI R17,HIGH(S1)                ;
            RJMP S1END                      ;

S1RESETIN:  JMP RESETINPUT                  ; Дальний прыжок, т.к. не достаем непосредственно из BREQ.

S1DECPNT:   LDI R16,LOW(S3)                 ; S1->S3.
            LDI R17,HIGH(S3)                ;
            RJMP S1PRNTKEY                  ;

S1OPERATOR: LDI R16,2                       ;
            EOR R16,P                       ; Завершен ввод второго операнда?
            BREQ S1OPERAND2                 ; Да, переходим к конвертации в float32 и вычислению.
            RJMP OPERAND1                   ; Нет, введен первый операнд, конвертируем его в float.

S1OPERAND2: JMP OPERAND2                    ; Дальний прыжок.

S1PRNTKEY:  ST X+,KEY                       ; *NUMSTR=KEY.
            INC S                           ;

.IFNDEF EMULKEYPD
            PUSH S                          ;
            PUSH R16                        ;
            PUSH R17                        ;
            MOV CHAR,KEY                    ; Выводим нажатую клавишу на LCD.
            RCALL PRNTCHR                   ;
            POP R17                         ;
            POP R16                         ;
            POP S                           ;
.ENDIF
          
.IFDEF EMULKEYPD
S1END:      POP ZH                          ; Восстанавливаем указатель на тестовую числовую строку.
            POP ZL                          ;
            PUSH R16                        ; Запоминаем новое состояние.
            PUSH R17                        ;
            PUSH RETL                       ; Восстанавливаем адрес возврата после прерывания.
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
            ; S2 - Промежуточное состояние после нажатия минуса.
            ;
            ; Допустимы только цифровые клавиши.
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
            MOV CHAR,KEY                    ; Выводим нажатую клавишу на LCD.
            RCALL PRNTCHR                   ;
            POP R17                         ;
            POP R16                         ;
            POP S                           ;
.ENDIF

.IFDEF EMULKEYPD
S2END:      POP ZH                          ; Восстанавливаем указатель на тестовую числовую строку.
            POP ZL                          ;
            PUSH R16                        ; Запоминаем новое состояние.
            PUSH R17                        ;
            PUSH RETL                       ; Восстанавливаем адрес возврата после прерывания.
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
            ; Сброс ввода по нажатию клавиши 'C'.
RESETINPUT:
.IFDEF EMULKEYPD
            POP ZH                          ; Восстанавливаем указатель на тестовую числовую строку.
            POP ZL                          ;
.ENDIF
            LDI R16,2                       ;
            EOR R16,P                       ; Сброс нажат в фазе ввода второго операнда?
            BRNE RESET1                     ; Нет, мы еще в фазе ввода первого операнда (до нажатия оператора).
            POP R16                         ; Да, первый операнд уже введён и в стеке лежат: символ оператора
            POP R16                         ; и четыре байта первого операнда в формате float32.
            POP R16                         ; Выбрасываем 4 байта первого операнда.
            POP R16                         ;
            POP R16                         ; Выбрасываем символ оператора. Стек пуст.

RESET1:     LDI XL,LOW(NUMSTR)              ; Смещаем указатель NUMSTR в начало строки.
            LDI XH,HIGH(NUMSTR)             ;

            LDI R16,0                       ; S=0.
            MOV S,R16                       ;

            LDI R16,1                       ; P=1.
            MOV P,R16                       ;

            LDI R16,LCDLEN-1                ; Резервируем последний символ первой строки под символ оператора.
            MOV LCDLIM,R16                  ;

            LDI R16,LOW(S0)                 ; Начальное состояние - S0.
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
            ; Ввод первого операнда завершён.
.IFDEF EMULKEYPD
OPERAND1:   POP ZH                          ; Временно восстанавливаем указатель на тестовую числовую строку.
            POP ZL                          ;
            PUSH KEY                        ; Сохраняем в самый низ стека нажатый арифметический оператор.
            PUSH ZL                         ; Помещаем сверху указатель на строку.
            PUSH ZH                         ;
.ELSE
OPERAND1:   PUSH KEY                        ; Сохраняем в самый низ стека нажатый арифметический оператор.
.ENDIF
            LDI R16,0                       ; *NUMSTR='\0'.
            ST X,R16                        ;

            LDI XL,LOW(NUMSTR)              ; Возвращаем указатель в начало строки
            LDI XH,HIGH(NUMSTR)             ; Перед вызовом ATOF.

            ;
            ; Обработчик ошибок, возникающих при вычислениях с плавающей точкой, которые происходят внутри ATOF.
            ;
            ; В силу текущих ограничений на ввод: только десятичные дроби, без экспоненциальной записи,
            ; при выполнении ATOF переполнение возникнуть не может, а деление на ноль в ATOF невозможно в принципе.
            ;
            ; Но если способ ввода будет обновлён, то возможно переполнение при конвертации,
            ; когда для промежуточных вычислениях одинарной точности становится недостаточно.
            ;
            ; TODO: Добавить вывод сообщения об ошибке на LCD.
            ; В первой версии это не критично, т.к. ввод ограничен и исключения в ATOF быть не может.
            LDI ZL,LOW(OP1FLTERR0)          ;
            LDI ZH,HIGH(OP1FLTERR0)         ;
            RJMP OP1CNVRT                   ;
OP1FLTERR0: POP R16                         ; Выбрасываем из стека адрес возврата после ATOF.
            POP R16                         ;
            POP RETH                        ; Восстанавливаем адрес возврата после прерывания.
            POP RETL                        ;
            POP KEY                         ; Перед FTOA мы сохраняли KEY - извлекаем его.
.IFDEF EMULKEYPD
            POP ZH                          ; Если мы в режиме эмуляции и тестирования ввода с клавиатуры, то
            POP ZL                          ; восстанавливаем указатель на тестовую числовую строку.
.ENDIF
            POP R16                         ; На дне стека остался еще символ оператора - он больше не нужен.

            LDI XL,LOW(NUMSTR)              ; NUMSTR="ERR".
            LDI XH,HIGH(NUMSTR)             ;
            LDI R16,'E'                     ;
            ST X+,R16                       ;
            LDI R16,'R'                     ;
            ST X+,R16                       ;
            ST X+,R16                       ;
            CLR R16                         ;
            ST X,R16                        ; NUMSTR+='\0'.

            LDI R16,LOW(SHOWRES)            ; При вводе первого операнда произошло исключение,
            LDI R17,HIGH(SHOWRES)           ; Дальнейший ввод не имеет смысла, показываем сообщение об ошибке.
            RJMP OP1END                     ;

OP1CNVRT:   PUSH KEY                        ; Хотя KEY уже есть в стеке, ниже он нужен для вывода на LCD.
            PUSH RETL                       ; Мы всё еще внутри обработки прерывания, поэтому важно
            PUSH RETH                       ; не потерять корректный адрес возврата.
            CALL ATOF                       ;
            POP RETH                        ;
            POP RETL                        ;
            POP KEY                         ;

.IFDEF EMULKEYPD
            POP ZH                          ; Восстанавливаем указатель на тестовую числовую строку.
            POP ZL                          ;
.ENDIF
            PUSH R11                        ; Первый операнд введен и конвертирован в float32.
            PUSH R10                        ; Сохраняем его в стеке в little-endian.
            PUSH R9                         ;
            PUSH R8                         ;

            LDI XL,LOW(NUMSTR)              ; Сбрасываем указателя строки в начало.
            LDI XH,HIGH(NUMSTR)             ;

            CLR S                           ; Сбрасываем счетчик введенных символов.
            LDI R16,2                       ; Далее будет ввод второго операнда.
            MOV P,R16                       ;
            LDI R16,LCDLEN                  ; При вводе второго операнда в конце строки уже не надо резервировать символ под оператор,
            MOV LCDLIM,R16                  ; поэтому вся строка LCD отведена под число (имеется ввиду видимая часть).

.IFNDEF EMULKEYPD
            RCALL CURSL1END                 ; Ставим курсор в конец видимой части первой строки LCD.
            PUSH S                          ;
            MOV CHAR,KEY                    ; Выводим символ оператора на LCD.
            RCALL PRNTCHR                   ;
            POP S                           ;
            RCALL CURSL2BEG                 ; Ставим курсор в начало второй строки LCD.
.ENDIF

            LDI R16,LOW(S0)                 ; Ввод второго операнда идентичен вводу первого.
            LDI R17,HIGH(S0)                ;
OP1END:     PUSH R16                        ;
            PUSH R17                        ;
            PUSH RETL                       ;
            PUSH RETH                       ;
            RETI                            ;

            ;
            ; Ввод второго операнда завершён.
OPERAND2:   LDI R16,0                       ; *NUMSTR='\0'.
            ST X,R16                        ;

            LDI XL,LOW(NUMSTR)              ; Возвращаем указатель в начало строки
            LDI XH,HIGH(NUMSTR)             ; перед вызовом ATOF.

            ;
            ; Обработчик ошибок, возникающих при вычислениях с плавающей точкой, которые происходят внутри ATOF.
            ;
            ; В силу текущих ограничений на ввод: только десятичные дроби, без экспоненциальной записи -
            ; при выполнении ATOF переполнение возникнуть не может, а деление на ноль в ATOF невозможно в принципе.
            ;
            ; Но если способ ввода будет обновлён, то возможно переполнение при конвертации,
            ; когда для промежуточных вычислениях одинарной точности становится недостаточно.
            ;
            ; TODO: В случае исключения в ATOF выводить ошибку на LCD.
            ; Сейчас не критично, т.к. текущие ограничения на ввод операндов не приведут к исключению в ATOF.
            LDI ZL,LOW(OP2FLTERR0)          ;
            LDI ZH,HIGH(OP2FLTERR0)         ;
            RJMP OP2CONVERT                 ;
OP2FLTERR0: POP R16                         ; Выбрасываем из стека адрес возврата после ATOF.
            POP R16                         ;
            POP RETH                        ; Восстанавливаем адрес возврата после прерывания.
            POP RETL                        ;
.IFDEF EMULKEYPD
            POP ZH                          ; Если мы в режиме эмуляции и тестирования ввода с клавиатуры, то
            POP ZL                          ; восстанавливаем указатель на тестовую числовую строку.
.ENDIF
            LDI YL,LOW(SP)                  ; В стеке осталось 4 байта первого операнда в формате float32
            LDI YH,HIGH(SP)                 ; и один байт символа арифметического оператора.
            OUT SPL,YL                      ; Поскольку возникло исключение и они нам больше не нужны,
            OUT SPH,YH                      ; мы просто сбрасываем стек в его начальный адрес.

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

            MOV R12,R8                      ; Размещаем второй введённый операнд
            MOV R13,R9                      ; как второй операнд арифметической операции.
            MOV R14,R10                     ;
            MOV R15,R11                     ;

.IFDEF EMULKEYPD
            POP R18                         ; Временно восстанавливаем указатель на тестовую числовую строку.
            POP R17                         ;
.ENDIF
            POP R8                          ; Извлекаем первый введённый операнд и размещаем его
            POP R9                          ; как первый операнд арифметической операции.
            POP R10                         ;
            POP R11                         ;

            POP R16                         ; R16=OPERATOR.

.IFDEF EMULKEYPD
            PUSH R17                        ; Снова бэкапим указатель на тестовую строку.
            PUSH R18                        ;
.ENDIF

            ;
            ; Обработчик ошибок для арифметических подпрограмм: FADD32, FSUB32, FMUL32, FDIV32.
            ;
            ; Если арифметическая операция выполняется без переполнения или деления на ноль,
            ; то последующее выполнение конвертации результата FTOA не приведёт ни к переполнению, ни к делению на ноль.
            ;
            ; Более того, из-за текущих ограничений на ввод:только десятичные дроби, без экспоненциальной записи -
            ; сейчас при выполнении любой арифметической операции может произойти только деление на ноль.
            LDI ZL,LOW(OP2FLTERR1)          ; Если при вызове FADD32, FSUB32, FMUL32, FDIV32
            LDI ZH,HIGH(OP2FLTERR1)         ; произойдет ошибка: деление на ноль или переполнение,
            RJMP OPCHK                      ; то мы попадём на этот обработчик.
OP2FLTERR1: POP R16                         ; Адрес возврата из подпрограммы, которая выбросила исключение,
            POP R16                         ; нас больше не интересует.
            POP RETH                        ; Перед вызовом адрес возврата из прерывания был помещен в стек - восстанавливаем его.
            POP RETL                        ;
.IFDEF EMULKEYPD
            POP ZH                          ; Если мы в режиме эмуляции и тестирования ввода с клавиатуры, то
            POP ZL                          ; восстанавливаем указатель на тестовую числовую строку.
.ENDIF

;
; Поскольку в режиме эмуляции клавиатуры LCD не используется,
; сообщение об ошибке для визуального контроля выводим в SRAM.
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
; Иначе - выводим ошибку сразу на LCD.
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
            RJMP OP2END                     ; Конец обработчика исключений OP2FLTERR1.

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

            LDI R16,LCDLEN                  ; Устанавливаем аргумент MAXLEN подпрограммы FTOAE
            MOV R12,R16                     ; равным количеству видимых символов в LCD.

            PUSH RETL                       ;
            PUSH RETH                       ;
            CALL FTOAE                      ; *NUMSTR=FTOAE(C,LCDLEN), где C - результат вычислений в формате бинарного float32,
            POP RETH                        ; а LCDLEN - максимальная длина выходной строки, равная длине строки в LCD.
            POP RETL                        ;

.IFNDEF EMULKEYPD
            RCALL DSBLCURS                  ;
            RCALL CLEARLCD                  ;

            LDI XL,LOW(NUMSTR)              ; Смещаем указатель в начало строки, содержащей результат вычисления.
            LDI XH,HIGH(NUMSTR)             ;
            RCALL PRNTSTR                   ; Выводим строку с результатом на LCD.
.ENDIF

.IFDEF EMULKEYPD
            POP ZH                          ; Восстанавливаем указатель на тестовую строку.
            POP ZL                          ;
.ENDIF
OP2END:     LDI R16,LOW(SHOWRES)            ; Результат вычислен, новое состояние - показ результата.
            LDI R17,HIGH(SHOWRES)           ;
            PUSH R16                        ;
            PUSH R17                        ;
            PUSH RETL                       ;
            PUSH RETH                       ;
            RETI                            ;

            ;
            ; SHOWRES - холостое состояние для показа результата последнего вычисления.
            ;
            ; Разрешена только клавиша сброса.
SHOWRES:    LDI R16,'C'                     ;
            EOR R16,KEY                     ; Была нажата клавиша 'C'?
            BRNE STAY                       ; Нет, игнорируем нажатие.
            JMP RESETINPUT                  ; Да, сбрасываем состояние калькулятора на нулевое.

.IFDEF EMULKEYPD
STAY:       POP ZH                          ; Восстанавливаем указатель на тестовую числовую строку.
            POP ZL                          ; Стек пустой.
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
            ; S3 - промежуточное состояние после нажатия точки.
            ;
            ; Допустимы только цифровые клавиши.
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
            MOV CHAR,KEY                    ; Выводим нажатую клавишу на LCD.
            RCALL PRNTCHR                   ;
            POP R17                         ;
            POP R16                         ;
            POP S                           ;
.ENDIF

.IFDEF EMULKEYPD
S3END:      POP ZH                          ; Восстанавливаем указатель на тестовую числовую строку.
            POP ZL                          ;
            PUSH R16                        ; Запоминаем новое состояние.
            PUSH R17                        ;
            PUSH RETL                       ; Восстанавливаем адрес возврата после прерывания.
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
            ; S4 - ввод цифр целой части.
            ;
            ; В этом состоянии допустимы все клавиши, поэтому нет ветки для дефолтного поведения.
            ; Если нажата клавиша десятичной точки и доступно только одно знакоместо (как раз под точку),
            ; ввод точки игнорируется, чтобы избежать некорректного значения с висящей точкой вида "123.".
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

S4SKIP:     LDI R16,LOW(S4)                 ; Игнорируем нажатие, остаёмся в текущем состоянии.
            LDI R17,HIGH(S4)                ;
            RJMP S4END                      ;

S4RESETIN:  JMP RESETINPUT                  ; ДАЛЬНИЙ ПРЫЖОК.

S4DECPNT:   MOV R16,LCDLIM                  ; R16=(LCDLIM-2)-S.
            DEC R16                         ;
            DEC R16                         ;
            MOV R17,S                       ;
            COM R17                         ; Чтобы избежать ситуации "висящей" точки, её допускается ставить только если в строке
            INC R17                         ; есть место как минимум еще под два знака - под саму точку и под одну цифру после точки.
            ADD R16,R17                     ; На экране есть место под '.' и как минимум еще одну цифру?
            BRMI S4SKIP                     ; Нет, игнорируем нажатие точки.
            LDI R16,LOW(S3)                 ; Да, отображаем точку и переходим в новое состояние.
            LDI R17,HIGH(S3)                ;
            RJMP S4PRNTKEY                  ;

S4DIG09:    MOV R16,S                       ; Если S в текущем состоянии оказался меньше LCDLIM, то в следующем состоянии он будет равен LCDLIM.
            EOR R16,LCDLIM                  ; S<LCDLIM?
            BREQ S4SKIP                     ; Нет, больше цифр ввести нельзя, игнорируем ввод.
            LDI R16,LOW(S4)                 ; Да, отображаем цифру и остаемся в текущем состоянии,
            LDI R17,HIGH(S4)                ; ожидая следующего нажатия.
            RJMP S4PRNTKEY                  ;

S4OPERATOR: LDI R16,2                       ;
            EOR R16,P                       ; Завершен ввод второго операнда?
            BREQ S4OPERAND2                 ; Да, переходим к конвертации в float32 и вычислению.
            RJMP OPERAND1                   ; Нет, введен первый операнд, конвертируем его в float.

S4OPERAND2: JMP OPERAND2                    ;

S4PRNTKEY:  ST X+,KEY                       ;
            INC S                           ;

.IFNDEF EMULKEYPD
            PUSH S                          ;
            PUSH R16                        ;
            PUSH R17                        ;
            MOV CHAR,KEY                    ; Выводим нажатую клавишу на LCD.
            RCALL PRNTCHR                   ;
            POP R17                         ;
            POP R16                         ;
            POP S                           ;
.ENDIF

.IFDEF EMULKEYPD
S4END:      POP ZH                          ; Восстанавливаем указатель на тестовую числовую строку.
            POP ZL                          ;
            PUSH R16                        ; Запоминаем новое состояние.
            PUSH R17                        ;
            PUSH RETL                       ; Восстанавливаем адрес возврата после прерывания.
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
            ; Ввод цифр дробной части.
            ;
            ; Разрешены все клавиши, кроме десятичной точки.
S5:         LDI R16,'C'                     ;
            EOR R16,KEY                     ; KEY='C'?
            BREQ S5RESETIN                  ;

            LDI R16,0xF0                    ;
            AND R16,KEY                     ;
            LDI R17,0x30                    ;
            EOR R16,R17                     ; KEY=['0','9']?
            BREQ S5DIG09                    ;

            LDI R16,'.'                     ; Точка не разрешена в этом состоянии.
            EOR R16,KEY                     ; KEY='.'?
            BREQ S5SKIP                     ; Да, игнорируем нажатие клавиши.

            LDI R16,0xF0                    ; Выше мы сначала исключили точку,
            AND R16,KEY                     ; поскольку она тоже имеет 0x20 в ASCII в старшем байте - 
            LDI R17,0x20                    ; теперь проверка арифметических операторов по 0x20 однозначна.
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
            BREQ S5SKIP                     ; Нет, больше цифр ввести нельзя, игнорируем ввод.
            LDI R16,LOW(S5)                 ; Да, отображаем цифру и остаемся в текущем состоянии,
            LDI R17,HIGH(S5)                ; ожидая следующего нажатия.
            RJMP S5PRNTKEY                  ;

S5OPERATOR: LDI R16,2                       ;
            EOR R16,P                       ; Завершен ввод второго операнда?
            BREQ S5OPERAND2                 ; Да, переходим к конвертации в float32 и вычислению.
            RJMP OPERAND1                   ; Нет, введен первый операнд, конвертируем его в float.

S5OPERAND2: JMP OPERAND2                    ; Дальний прыжок.

S5PRNTKEY:  ST X+,KEY                       ;
            INC S                           ;

.IFNDEF EMULKEYPD
            PUSH S                          ;
            PUSH R16                        ;
            PUSH R17                        ;
            MOV CHAR,KEY                    ; Выводим нажатую клавишу на LCD.
            RCALL PRNTCHR                   ;
            POP R17                         ;
            POP R16                         ;
            POP S                           ;
.ENDIF

.IFDEF EMULKEYPD
S5END:      POP ZH                          ; Восстанавливаем указатель на тестовую числовую строку.
            POP ZL                          ;
            PUSH R16                        ; Запоминаем новое состояние.
            PUSH R17                        ;
            PUSH RETL                       ; Восстанавливаем адрес возврата после прерывания.
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
; Эмуляция ввода с клавиатуры для проверки обработчика прерываний по клавиатуре.
;
; Конфигурация порта D - на выход, на время программного тестирования ввода с клавиатуры.
; Это нужно для выставления данных на порту и программного вызова прерывания прямо из текущего кода.
.IFDEF EMULKEYPD
            SER R16                         ; Настраиваем порт D на выход,
            OUT DDRD,R16                    ; чтобы программно выставлять код клавиши и инициировать прерывание по INT0.
            LDI R16,0x00                    ;
            OUT PORTD,R16                   ;
.ELSE
            CLR R16                         ;
            OUT DDRD,R16                    ;
.ENDIF

            LDI R16,(1<<ISC01|1<<ISC00)     ; Разрешаем внешние прерывания
            STS EICRA,R16                   ; по INT0, по переднему фронту - там сидит клавиатура.
            LDI R16,(1<<INT0)               ;
            OUT EIMSK,R16                   ;
            SEI                             ;

            LDI ZL,LOW(KEYMAPPRG<<1)        ; Читаем таблицу ASCII-кодов клавиш в SRAM.
            LDI ZH,HIGH(KEYMAPPRG<<1)       ;
            LDI XL,LOW(KEYMAP)              ;
            LDI XH,HIGH(KEYMAP)             ;
READ:       LPM R0,Z+                       ;
            AND R0,R0                       ; Прочитали NUL?
            BREQ MAIN                       ; Да, все символы считаны в SRAM.
            ST X+,R0                        ; Нет, записываем символ в SRAM и продолжаем.
            RJMP READ                       ;

;
;
MAIN:       NOP
            
            ;
            ; Начальный сброс калькулятора.
            LDI XL,LOW(NUMSTR)              ; Смещаем указатель NUMSTR в начало строки.
            LDI XH,HIGH(NUMSTR)             ;

            LDI R16,0                       ; S=0.
            MOV S,R16                       ;

            LDI R16,1                       ; P=1.
            MOV P,R16                       ;

            LDI R16,LCDLEN-1                ; Резервируем последний символ первой строки под символ оператора.
            MOV LCDLIM,R16                  ;

            LDI R16,LOW(S0)                 ; Начальное состояние - S0.
            LDI R17,HIGH(S0)                ;
            PUSH R16                        ;
            PUSH R17                        ;
            
;
; Эмуляция ввода с клавиатуры для проверки обработчика прерываний по клавиатуре.
;
; Читаем каждый символ числовой строки из памяти программ,
; преобразуем его ASCII-код в сырой код энкодера клавиатуры,
; выставляем код на порту D и устанавливает пин INT0 в единицу,
; вызывая прерывание по клавиатуре программно.
.IFDEF EMULKEYPD
            ;
            ; Раскомментировать при тестировании ввода второго операнда.
;            LDI R16,2                       ;
;            MOV P,R16                       ;

;            LDI R16,LCDLEN                  ;
;            MOV LCDLIM,R16                  ;

            ;
            ; Инициализация обратной таблицы клавиш - отображение ASCII-кода клавиши в сырой код энкодера.
            ;
            ; ASCII-код используется как младший байт адреса в SRAM, по которому записывается сырой код.
            ; Читаем числовую строку, преобразуя ASCII-код каждого символа в сырой код клавиши и
            ; выставляем этот код на порту D, инициируя прерывание по INT0 после каждого прочитанного символа.
            ; Таким образом программно эмулируется ввод с клавиатуры.
            LDI R17,0x00                    ; Сырой код клавиши.
            LDI ZL,LOW(KEYMAPPRG << 1)      ;
            LDI ZH,HIGH(KEYMAPPRG << 1)     ;
READ0:      LPM R4,Z+                       ;
            AND R4,R4                       ; Достигли конца строки?
            BREQ EMULINPUT                  ; Да, таблица сформирована, переходим к эмуляции ввода с клавиатуры.
            MOV YL,R4                       ; Нет, продолжаем.
            LDI YH,HIGH(REVKEYMAP)          ;
            ST Y,R17                        ; Записываем сырой код клавиши.
            INC R17                         ; Переходим к следующему символу.
            RJMP READ0                      ;

            ;
            ; Эмуляция ввода арифметических выражений.
            ;
            ; NOTE: При тестировании ввода, если после чтения первого операнда возникает исключение,
            ; несмотря на формирование сообщения об ошибке и переход в состояние SHOWRES, которое
            ; игнорирует любой ввод кроме клавиши сброса, цикл эмуляции продолжит читать выражение до конца строки,
            ; вызывая прерывания по клавиатуре и попадая в SHOWRES.
            ; Но поскольку символа 'C' в полном арифметическом выражении не будет, никаких изменений в состоянии калькулятора
            ; не произойдет. Поведение будет таким же, как в случае, когда пользователь получил сообщение об ошибке и продолжает
            ; нажимать цифровые клавиши и клавиши операторов, а калькулятор игнорирует ввод и ожидает только нажатие клавиши 'C'.
            ; Это сделано для простоты кода эмуляции - чтобы не делать доп. проверку, а просто дать коду "дочитать" строку до конца
            ; и завершиться естественным путём.
EMULINPUT:  LDI ZL,LOW(TESTNUM << 1)        ;
            LDI ZH,HIGH(TESTNUM << 1)       ;
READ1:      LPM R4,Z+                       ;
            AND R4,R4                       ; Достигли конца строки?
            BREQ END                        ; Да, числовая строка "введена".
            MOV YL,R4                       ; Нет, мапим ASCII-символ в код энкодера.
            LDI YH,HIGH(REVKEYMAP)          ;
            LD R16,Y                        ;
            CLC                             ;
            ROL R16                         ; Размещаем биты кода в старшем полубайте порта D.
            ROL R16                         ;
            ROL R16                         ;
            ROL R16                         ;
            LDI R17,0b00000100              ; Эмулируем бит готовности данных энкодера,
            EOR R16,R17                     ; устанавливая INT0 в единицу - это инициирует прерывание.
            OUT PORTD,R16                   ;
            LDI R17,0b11111011              ; Убираем бит готовности данных, чтобы на следующей итерации
            AND R16,R17                     ; вновь инициировать прерывание.
            OUT PORTD,R16                   ;
            RJMP READ1                      ;
.ENDIF

END:        RJMP END

;
; Таблица ASCII-кодов нажатых клавиш.
KEYMAPPRG:  .DB "C0./789x456-123+",0

;
; Тестовые примеры для проверки корректного ввода с клавиатуры.
; Примеры определены в [Траектории на графе состояний и тестовые примеры.xmind].
; сначала поряд идут "зелёные" примеры, содержащие корректные числовые строки.
; Далее, с новой нумерацией, идут "жёлтые" примеры, содержащие некорректные числовые строки,
; которые должны быть проигнорированы обработчиком клавиатуры.
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
            ; для тестов нужно временно увеличить LCDLEN до 40 знаков.
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

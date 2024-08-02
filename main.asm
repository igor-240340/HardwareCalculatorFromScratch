            .INCLUDE <M328PDEF.INC>

                                            ; ПОД СТЕКОМ 3 ПЕРЕМЕННЫХ ПО 4 БАЙТА ПОД FLOAT32,
                                            ; 16 БАЙТ ПОД ASCII КОДЫ НАЖАТЫХ КЛАВИШ И ЕЩЕ
            .EQU SP=RAMEND-(3*4+16+256)     ; 256 БАЙТ ПОД ASCII СТРОКУ.
            .EQU LCDLEN=16                  ; ДЛИНА СТРОКИ В LCD.

            .DEF S=R0                       ; КОЛИЧЕСТВО ИСПОЛЬЗОВАННЫХ СИМВОЛОВ В ТЕКУЩЕЙ СТРОКЕ ДИСПЛЕЯ.
            .DEF P=R1                       ; НОМЕР ВВОДИМОГО ОПЕРАНДА, ЛЕЖИТ В [0,1].
            .DEF KEY=R2                     ; ASCII КОД НАЖАТОЙ КЛАВИШИ.
            .DEF LCDLIM=R3                  ; МАКСИМАЛЬНОЕ КОЛИЧЕСТВО ВЫВОДИМЫХ НА LCD СИМВОЛОВ.

            .DEF RETL=R22                   ; СЮДА БЭКАПИМ АДРЕС ВОЗВРАТА ПОСЛЕ ПРЕРЫВАНИЯ.
            .DEF RETH=R23                   ;

            .DSEG
            .ORG 0x0100                     ; ТАБЛИЦА ИСПОЛЬЗУЕТСЯ ТОЛЬКО В ТЕСТАХ, РАЗМЕЩАЕМ ПОДАЛЬШЕ ОТ БОЕВЫХ ДАННЫХ.
REVKEYMAP:  .BYTE 26                        ; ТАБЛИЦА СООТВЕТСТВИЯ МЕЖДУ ASCII КОДАМИ И КОДАМИ ЭНКОДЕРА.

            .ORG SP+1                       ;
A:          .BYTE 4                         ; 0x07E4. ОПЕРАНД A.
B:          .BYTE 4                         ; 0x07E8. ОПЕРАНД B.
C:          .BYTE 4                         ; 0x07EC. РЕЗУЛЬТАТ C.
KEYMAP:     .BYTE 16                        ; 0x07F0. ТАБЛИЦА СИМВОЛОВ НАЖАТЫХ КЛАВИШ.
NUMSTR:     .BYTE 256                       ; 0x0800. УКАЗАТЕЛЬ НА ASCII СТРОКУ С ЧИСЛОМ В SRAM.

            .CSEG
            .ORG 0x00

            JMP RESET
            JMP KEYPAD
            
            .INCLUDE "FLOAT32.ASM"

;
; ОБРАБОТКА ПРЕРЫВАНИЙ ОТ КЛАВИАТУРЫ.
KEYPAD:     IN KEY,PIND                     ; КОД КЛАВИШИ - В СТАРШЕМ ПОЛУБАЙТЕ ПОРТА D.
            LDI R17,0xF0                    ; ИЗВЛЕКАЕМ И СДВИГАЕМ В МЛАДШИЙ ПОЛУБАЙТ.
            AND KEY,R17                     ;
            CLC                             ;
            ROR KEY                         ;
            ROR KEY                         ;
            ROR KEY                         ;
            ROR KEY                         ;

            LDI R17,LOW(KEYMAP)             ; ДОБАВЛЯЕМ КОД КЛАВИШИ В МЛАДШИЙ ПОЛУБАЙТ АДРЕСА ТАБЛИЦЫ СИМВОЛОВ.
            OR R17,KEY                      ; Y=0x07F0|0x0X, 0x0X - КОД КЛАВИШИ В ОТРЕЗКЕ [0x00,0x0F].
            MOV YL,R17                      ;
            LDI YH,HIGH(KEYMAP)             ;

            LD KEY,Y                        ; KEY=ASCII(RAWKEY), RAWKEY - СЫРОЙ КОД ОТ MM74C922.

            POP RETH                        ; БЭКАПИМ АДРЕС ВОЗВРАТА ПОСЛЕ ПРЕРЫВАНИЯ.
            POP RETL                        ;
            POP ZH                          ; ИЗВЛЕКАЕМ АДРЕС ОБРАБОТЧИКА ТЕКУЩЕГО СОСТОЯНИЯ.
            POP ZL                          ;
            IJMP                            ; ПРЫГАЕМ НА ОБРАБОТЧИК, СООТВЕТСТВУЮЩИЙ ТЕКУЩЕМУ СОСТОЯНИЮ.

            ;
            ;
S0:         LDI R16,'C'                     ;
            EOR R16,KEY                     ; KEY='C'?
            BREQ S0RESETIN                  ; ДА, СБРАСЫВАЕМ ВВОД, ВОЗВРАЩАЕМСЯ В НУЛЕВОЕ СОСТОЯНИЕ.

            LDI R16,'-'                     ;
            EOR R16,KEY                     ; KEY='-'?
            BREQ S0MINUS                    ;

            LDI R16,'0'                     ;
            EOR R16,KEY                     ; KEY='0'?
            BREQ S0DIG0                     ;

            LDI R16,0xF0                    ; ВСЕ ЦИФРЫ ОТ 1 ДО 9 В ASCII ИМЕЮТ ОДИНАКОВЫЙ СТАРШИЙ ПОЛУБАЙТ РАВНЫЙ 0x30.
            AND R16,KEY                     ; ДРУГИЕ ВОЗМОЖНЫЕ КЛАВИШИ НА ЭТОМ ЭТАПЕ: '.','+','*','/', ИМЕЮТ СТАРШИЙ ПОЛУБАЙТ РАВНЫЙ 0x20.
            LDI R17,0x30                    ;
            EOR R16,R17                     ; KEY=['1','9']?
            BREQ S0DIG19                    ;

            LDI R16,LOW(S0)                 ; БЫЛА НАЖАТА НЕДОПУСТИМАЯ В ЭТОМ СОСТОЯНИИ КЛАВИША.
            LDI R17,HIGH(S0)                ; S0->S0.
            RJMP S0END                      ; ИГНОРИРУЕМ ВВОД И ОСТАЁМСЯ В ТЕКУЩЕМ СОСТОЯНИИ.

S0RESETIN:  JMP RESETINPUT                  ; ДАЛЬНИЙ ПРЫЖОК, Т.К. НЕ ДОСТАЕМ НЕПОСРЕДСТВЕННО ИЗ BREQ.

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

S0END:      PUSH R16                        ; ЗАПОМИНАЕМ НОВОЕ СОСТОЯНИЕ.
            PUSH R17                        ;
            PUSH RETL                       ; ВОССТАНАВЛИВАЕМ АДРЕС ВОЗВРАТА ПОСЛЕ ПРЕРЫВАНИЯ.
            PUSH RETH                       ;
            RETI                            ;

            ;
            ;
S1:         LDI R16,'C'                     ;
            EOR R16,KEY                     ; KEY='C'?
            BREQ RESETINPUT                 ;

            LDI R16,'.'                     ;
            EOR R16,KEY                     ; KEY='.'?
            BREQ S1DECPNT                   ;

            LDI R16,0xF0                    ; '+','-','*','/' В ASCII ИМЕЮТ ОДИНАКОВЫЙ СТАРШИЙ ПОЛУБАЙТ РАВНЫЙ 0x20.
            AND R16,KEY                     ; А '.' МЫ УЖЕ ИСКЛЮЧИЛИ ВЫШЕ.
            LDI R17,0x20                    ;
            EOR R16,R17                     ; KEY=['+','-','*','/']?
            BREQ S1OPERATOR                 ;

            LDI R16,LOW(S1)                 ;
            LDI R17,HIGH(S1)                ;
            RJMP S1END                      ;

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
            
S1END:      PUSH R16                        ;
            PUSH R17                        ;
            PUSH RETL                       ;
            PUSH RETH                       ;
            RETI                            ;

            ;
            ;
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

S2END:      PUSH R16                        ;
            PUSH R17                        ;
            PUSH RETL                       ;
            PUSH RETH                       ;
            RETI                            ;

            ;
            ;
RESETINPUT: LDI XL,LOW(NUMSTR)              ; СМЕЩАЕМ УКАЗАТЕЛЬ NUMSTR В НАЧАЛО СТРОКИ.
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
            RETI                            ;

            ;
            ; ВВОД ПЕРВОГО ОПЕРАНДА ЗАВЕРШЁН.
OPERAND1:   PUSH KEY                        ; СОХРАНЯЕМ В САМЫЙ НИЗ СТЕКА НАЖАТЫЙ АРИФМЕТИЧЕСКИЙ ОПЕРАТОР.

            LDI R16,0                       ; *NUMSTR='\0'.
            ST X,R16                        ;
            
            LDI XL,LOW(NUMSTR)              ; ВОЗВРАЩАЕМ УКАЗАТЕЛЬ В НАЧАЛО СТРОКИ
            LDI XH,HIGH(NUMSTR)             ; ПЕРЕД ВЫЗОВОМ ATOF.

            LDI ZL,LOW(FLOATERR)            ; ЗАПИСЫВАЕМ В Z АДРЕС ОБРАБОТЧИКА ОШИБОК
            LDI ZH,HIGH(FLOATERR)           ; ДЛЯ БИБЛИОТЕКИ FLOAT32AVR. [NOTE: НА САМОМ ДЕЛЕ ДЛЯ ТЕХ ЗНАЧЕНИЙ, КОТОРЫЕ МЫ РАЗРЕШАЕМ ВВОДИТЬ, ПЕРЕПОЛНЕНИЯ БЫТЬ НЕ ДОЛЖНО.]

            PUSH RETL                       ; МЫ ВСЁ ЕЩЕ ВНУТРИ ОБРАБОТКИ ПРЕРЫВАНИЯ, ПОЭТОМУ ВАЖНО
            PUSH RETH                       ; НЕ ПОТЕРЯТЬ КОРРЕКТНЫЙ АДРЕС ВОЗВРАТА.
            CALL ATOF                       ;
            POP RETH                        ;
            POP RETL                        ;

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

            LDI R16,LOW(S0)                 ; ВВОД ВТОРОГО ОПЕРАНДА ИДЕНТИЧЕН ВВОДУ ПЕРВОГО.
            LDI R17,HIGH(S0)                ;
            PUSH R16                        ;
            PUSH R17                        ;
            PUSH RETL                       ;
            PUSH RETH                       ;
            RETI                            ;

            ;
            ; ВВОД ВТОРОГО ОПЕРАНДА ЗАВЕРШЁН.
OPERAND2:   LDI R16,0                       ; *NUMSTR='\0'.
            ST X,R16                        ;

            LDI ZL,LOW(FLOATERR)            ; ЗАПИСЫВАЕМ В Z АДРЕС ОБРАБОТЧИКА ОШИБОК
            LDI ZH,HIGH(FLOATERR)           ; ДЛЯ БИБЛИОТЕКИ FLOAT32AVR.

            LDI XL,LOW(NUMSTR)              ; ВОЗВРАЩАЕМ УКАЗАТЕЛЬ В НАЧАЛО СТРОКИ
            LDI XH,HIGH(NUMSTR)             ; ПЕРЕД ВЫЗОВОМ ATOF.

            PUSH RETL                       ;
            PUSH RETH                       ;
            CALL ATOF                       ;
            POP RETH                        ;
            POP RETL                        ;

            MOV R12,R8                      ; РАЗМЕЩАЕМ ВТОРОЙ ВВЕДЁННЫЙ ОПЕРАНД
            MOV R13,R9                      ; КАК ВТОРОЙ ОПЕРАНД АРИФМЕТИЧЕСКОЙ ОПЕРАЦИИ.
            MOV R14,R10                     ;
            MOV R15,R11                     ;

            POP R8                          ; ИЗВЛЕКАЕМ ПЕРВЫЙ ВВЕДЁННЫЙ ОПЕРАНД И РАЗМЕЩАЕМ ЕГО
            POP R9                          ; КАК ПЕРВЫЙ ОПЕРАНД АРИФМЕТИЧЕСКОЙ ОПЕРАЦИИ.
            POP R10                         ;
            POP R11                         ;

            POP R16                         ; R16=OPERATOR.
            LDI R17,'+'                     ;
            EOR R17,R16                     ;
            BREQ CALCADD                    ;

            LDI R17,'-'                     ;
            EOR R17,R16                     ;
            BREQ CALCSUB                    ;

            LDI R17,'*'                     ;
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

            PUSH RETL                       ;
            PUSH RETH                       ;
            CALL FTOA                       ; *NUMSTR=FTOA(C), ГДЕ C - РЕЗУЛЬТАТ ВЫЧИСЛЕНИЙ.
            POP RETH                        ;
            POP RETL                        ;

            LDI R16,LOW(SHOWRES)            ;
            LDI R17,HIGH(SHOWRES)           ;
            PUSH R16                        ;
            PUSH R17                        ;
            PUSH RETL                       ;
            PUSH RETH                       ;
            RETI                            ;

            ;
            ; ХОЛОСТОЕ СОСТОЯНИЕ ДЛЯ ПОКАЗА РЕЗУЛЬТАТА ПОСЛЕДНЕГО ВЫЧИСЛЕНИЯ.
            ; ВОЗМОЖЕН ЛИБО ПЕРЕХОД НА СБРОС ЛИБО ВЫКЛЮЧЕНИЕ ПИТАНИЯ.
SHOWRES:    NOP


            ;
            ;
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

S3END:      PUSH R16                        ;
            PUSH R17                        ;
            PUSH RETL                       ;
            PUSH RETH                       ;
            RETI                            ;

            ;
            ; S4 - ВВОД ЦИФР ЦЕЛОЙ ЧАСТИ.
            ; В ЭТОМ СОСТОЯНИИ ДОПУСТИМЫ ВСЕ КЛАВИШИ, ПОЭТОМУ НЕТ ВЕТКИ ДЛЯ ДЕФОЛТНОГО ПОВЕДЕНИЯ.
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
            EOR R16,R17                     ; KEY=['+','-','*','/']?
            BREQ S4OPERATOR                 ;

S4SKIP:     LDI R16,LOW(S4)                 ; ИГНОРИРУЕМ НАЖАТИЕ, ОСТАЁМСЯ В ТЕКУЩЕМ СОСТОЯНИИ.
            LDI R17,HIGH(S4)                ;
            RJMP S4END                      ;

S4RESETIN:  JMP RESETINPUT                  ; ДАЛЬНИЙ ПРЫЖОК.

S4DECPNT:   MOV R16,LCDLIM                  ; R16=(LCDLIM-2)-S.
            DEC R16                         ;
            DEC R16                         ;
            MOV R17,S                       ;
            COM R17                         ;
            INC R17                         ;
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

S4END:      PUSH R16                        ;
            PUSH R17                        ;
            PUSH RETL                       ;
            PUSH RETH                       ;
            RETI                            ;

            ;
            ;
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
            EOR R16,R17                     ; KEY=['+','-','*','/']?
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
            
S5END:      PUSH R16                        ;
            PUSH R17                        ;
            PUSH RETL                       ;
            PUSH RETH                       ;
            RETI                            ;
            
;
;
RESET:      LDI YL,LOW(SP)                  ;
            LDI YH,HIGH(SP)                 ;
            OUT SPL,YL                      ;
            OUT SPH,YH                      ;

;============================================================================================
; BEGIN: ЭМУЛЯЦИЯ ВВОДА С КЛАВИАТУРЫ ДЛЯ ПРОВЕРКИ ОБРАБОТЧИКА ПРЕРЫВАНИЙ ПО КЛАВИАТУРЕ.
;
; КОНФИГУРАЦИЯ ПОРТА D НА ВЫХОД НА ВРЕМЯ ПРОГРАММНОГО ТЕСТИРОВАНИЯ ВВОДА С КЛАВИАТУРЫ.
; ЭТО НУЖНО ДЛЯ ВЫСТАВЛЕНИЯ ДАННЫХ НА ПОРТУ
; И ПРОГРАММНОГО ВЫЗОВА ПРЕРЫВАНИЯ ПРЯМО ИЗ ЭТОГО КОДА.
;============================================================================================
            SER R16                         ;
            OUT DDRD,R16                    ;
            LDI R16,0x00                    ;
            OUT PORTD,R16                   ;
;============================================================================================
; END: ЭМУЛЯЦИЯ ВВОДА С КЛАВИАТУРЫ ДЛЯ ПРОВЕРКИ ОБРАБОТЧИКА ПРЕРЫВАНИЙ ПО КЛАВИАТУРЕ.END NOTE.
;============================================================================================

;============================================================================================
; BEGIN: БОЕВАЯ КОНФИГУРАЦИЯ ПОРТА D НА ВХОД.
;
; РАСКОММЕНТИРОВАТЬ ПОСЛЕ ПРОВЕРКИ ВВОДА С КЛАВИАТУРЫ.
;============================================================================================
;            CLR R16                         ;
;            OUT DDRD,R16                    ;
;            LDI R16,0xFF                    ;
;            OUT PORTD,R16                   ;
;============================================================================================
; END: БОЕВАЯ КОНФИГУРАЦИЯ ПОРТА D НА ВХОД.
;============================================================================================

            LDI R16,(1<<ISC01|1<<ISC00)     ; РАЗРЕШАЕМ ВНЕШНИЕ ПРЕРЫВАНИЯ
            STS EICRA,R16                   ; ПО INT0, ПО ПЕРЕДНЕМУ ФРОНТУ.
            LDI R16,(1<<INT0)               ;
            OUT EIMSK,R16                   ;
            SEI                             ;

            LDI ZL,LOW(KEYMAPPRG << 1)      ; ЧИТАЕМ ТАБЛИЦУ ASCII КОДОВ КЛАВИШ В SRAM.
            LDI ZH,HIGH(KEYMAPPRG << 1)     ;
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
            
;============================================================================================
; BEGIN: ЭМУЛЯЦИЯ ВВОДА С КЛАВИАТУРЫ ДЛЯ ПРОВЕРКИ ОБРАБОТЧИКА ПРЕРЫВАНИЙ ПО КЛАВИАТУРЕ.
;
; ЧИТАЕМ КАЖДЫЙ СИМВОЛ ЧИСЛОВОЙ СТРОКИ ИЗ ПАМЯТИ ПРОГРАММ,
; ПРЕОБРАЗУЕМ ЕГО ASCII КОД В СЫРОЙ КОД ЭНКОДЕРА КЛАВИАТУРЫ,
; ВЫСТАВЛЯЕМ КОД НА ПОРТУ D И УСТАНАВЛИВАЕТ ПИН INT0 В ЕДИНИЦУ,
; ВЫЗЫВАЯ ПРЕРЫВАНИЕ ПО КЛАВИАТУРЕ ПРОГРАММНО.
;============================================================================================
            ;
            ; РАСКОММЕНТИРОВАТЬ ПРИ ТЕСТИРОВАНИИ ВВОДА ВТОРОГО ОПЕРАНДА.
;            LDI R16,2                       ;
;            MOV P,R16                       ;

;            LDI R16,LCDLEN                  ;
;            MOV LCDLIM,R16                  ;

            ;
            ; ИНИЦИАЛИЗАЦИЯ ОБРАТНОЙ ТАБЛИЦЫ КЛАВИШ - МАПИТ ASCII КОД КЛАВИШИ В СЫРОЙ КОД ЭНКОДЕРА.
            ;
            ; МЫ ЧИТАЕМ ЧИСЛОВУЮ СТРОКУ И ASCII КОД КАЖДОГО СИМВОЛА ПРЕОБРАЗУЕМ В СЫРОЙ КОД КЛАВИШИ.
            ; ТАКИМ ОБРАЗОМ ЭМУЛИРУЕТСЯ ВВОД С КЛАВИАТУРЫ.
            LDI R17,0x00                    ; СЫРОЙ КОД КЛАВИШИ.
            LDI ZL,LOW(KEYMAPPRG << 1)      ;
            LDI ZH,HIGH(KEYMAPPRG << 1)     ;
READ0:      LPM R0,Z+                       ;
            AND R0,R0                       ; ПРОЧИТАЛИ NUL?
            BREQ EMULKEY                    ; ДА, ТАБЛИЦА СФОРМИРОВАНА.
            MOV XL,R0                       ; НЕТ, ПРОДОЛЖАЕМ.
            LDI XH,HIGH(REVKEYMAP)          ;
            ST X,R17                        ; ЗАПИСЫВАЕМ СЫРОЙ КОД КЛАВИШИ.
            INC R17                         ; ПЕРЕХОДИМ К СЛЕДУЮЩЕЙ КЛАВИШЕ.
            RJMP READ0                      ;

EMULKEY:    LDI ZL,LOW(NUMTEST << 1)        ;
            LDI ZH,HIGH(NUMTEST << 1)       ;
READ1:      LPM R0,Z+                       ;
            AND R0,R0                       ; NUL?
            BREQ MAIN                       ; ДА, ЧИСЛОВАЯ СТРОКА ПРОЧИТАНА И "ВВЕДЕНА".
            MOV XL,R0                       ; НЕТ, ПРОДОЛЖАЕМ.
            LDI XH,HIGH(REVKEYMAP)          ;
            LD R16,X                        ;
            CLC                             ;
            ROL R16                         ;
            ROL R16                         ;
            ROL R16                         ;
            ROL R16                         ;
            LDI R17,4                       ;
            EOR R16,R17                     ;
            OUT PORTD,R16                   ;
            RJMP READ1                      ;
;============================================================================================
; END: BEGIN: ЭМУЛЯЦИЯ ВВОДА С КЛАВИАТУРЫ ДЛЯ ПРОВЕРКИ ОБРАБОТЧИКА ПРЕРЫВАНИЙ ПО КЛАВИАТУРЕ.
;============================================================================================

END:        RJMP END

;
; ОБРАБОТЧИК ОШИБОК, ВОЗНИКАЮЩИХ ПРИ ВЫЧИСЛЕНИЯХ С ПЛАВАЮЩЕЙ ТОЧКОЙ:
; - ДЕЛЕНИЕ НА НОЛЬ.
; - ПЕРЕПОЛНЕНИЕ.
FLOATERR:   RJMP END

;
; ТАБЛИЦА ASCII КОДОВ НАЖАТЫХ КЛАВИШ.
KEYMAPPRG:  .DB "C0./123*456-789+",0

;===========================================================================================
; BEGIN: ЭМУЛЯЦИЯ ВВОДА С КЛАВИАТУРЫ ДЛЯ ПРОВЕРКИ ОБРАБОТЧИКА ПРЕРЫВАНИЙ ПО КЛАВИАТУРЕ.
;
; ТЕСТОВЫЕ ПРИМЕРЫ ДЛЯ ПРОВЕРКИ КОРРЕКТНОГО ВВОДА С КЛАВИАТУРЫ.
; ПРИМЕРЫ ОПРЕДЕЛЕНЫ В [ТРАЕКТОРИИ ГРАФА СОСТОЯНИЙ И ТЕСТОВЫЕ ПРИМЕРЫ.XMIND].
; СНАЧАЛА ПОРЯД ИДУТ "ЗЕЛЁНЫЕ" ПРИМЕРЫ, СОДЕРЖАЩИЕ КОРРЕКТНЫЕ ЧИСЛОВЫЕ СТРОКИ.
; ДАЛЕЕ, С НОВОЙ НУМЕРАЦИЕЙ, ИДУТ "ЖЁЛТЫЕ" ПРИМЕРЫ, СОДЕРЖАЩИЕ НЕКОРРЕКТНЫЕ ЧИСЛОВЫЕ СТРОКИ,
; КОТОРЫЕ ДОЛЖНЫ БЫТЬ ПРОИГНОРИРОВАНЫ ОБРАБОТЧИКОМ КЛАВИАТУРЫ.
;===========================================================================================
            ; ПРИМЕР 1.
NUMTEST:  .DB "0.0123456789123",0
;===========================================================================================
; END: ЭМУЛЯЦИЯ ВВОДА С КЛАВИАТУРЫ ДЛЯ ПРОВЕРКИ ОБРАБОТЧИКА ПРЕРЫВАНИЙ ПО КЛАВИАТУРЕ.
;===========================================================================================
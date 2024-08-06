            .INCLUDE <M328PDEF.INC>

;            .EQU EMULKEYPD=1                ; РЕЖИМ ТЕСТИРОВАНИЯ ВВОДА С КЛАВИАТУРЫ.

                                            ; ПОД СТЕКОМ 3 ПЕРЕМЕННЫХ ПО 4 БАЙТА ПОД FLOAT32,
                                            ; 16 БАЙТ ПОД ASCII-КОДЫ НАЖАТЫХ КЛАВИШ И ЕЩЕ
            .EQU SP=RAMEND-(3*4+16+256)     ; 256 БАЙТ ПОД ASCII-СТРОКУ.
            .EQU LCDLEN=16                  ; ДЛИНА СТРОКИ В LCD.
;            .EQU LCDLEN=40                  ; ТЕСТОВОЕ УВЕЛИЧЕНИЕ ЛИМИТА ДЛЯ ПРОВЕРКИ ОБРАБОТКИ ПЕРЕПОЛНЕНИЯ В ATOF.
            .EQU PREC=100                   ; КОЛИЧЕСТВО ЗНАКОВ ПОСЛЕ ТОЧКИ ДЛЯ FTOA.

            .DEF S=R0                       ; КОЛИЧЕСТВО ИСПОЛЬЗОВАННЫХ СИМВОЛОВ В ТЕКУЩЕЙ СТРОКЕ ДИСПЛЕЯ.
            .DEF P=R1                       ; НОМЕР ВВОДИМОГО ОПЕРАНДА, ЛЕЖИТ В [0,1].
            .DEF KEY=R2                     ; ASCII-КОД НАЖАТОЙ КЛАВИШИ.
            .DEF LCDLIM=R3                  ; МАКСИМАЛЬНОЕ КОЛИЧЕСТВО ВЫВОДИМЫХ НА LCD СИМВОЛОВ.

            .DEF RETL=R22                   ; СЮДА БЭКАПИМ АДРЕС ВОЗВРАТА ПОСЛЕ ПРЕРЫВАНИЯ.
            .DEF RETH=R23                   ;

            .DSEG

.IFDEF EMULKEYPD
            .ORG 0x012A                     ; НАЧАЛО ТАБЛИЦЫ СООТВЕТСТВИЯ МЕЖДУ ASCII-КОДАМИ И КОДАМИ ЭНКОДЕРА. ТАБЛИЦА ЛЕЖИТ В [0x012A,0x0143].
REVKEYMAP:  .BYTE 26                        ; МЛАДШИЙ БАЙТ АДРЕСА - ASCII-КОД КЛАВИШИ. НАИМЕНЬШИЙ КОД КЛАВИШИ - 0x2A('*'), НАИБОЛЬШИЙ - 0x43('C').
.ENDIF

            .ORG SP+1                       ;
A:          .BYTE 4                         ; 0x07E4. ОПЕРАНД A.
B:          .BYTE 4                         ; 0x07E8. ОПЕРАНД B.
C:          .BYTE 4                         ; 0x07EC. РЕЗУЛЬТАТ C.
KEYMAP:     .BYTE 16                        ; 0x07F0. ТАБЛИЦА СИМВОЛОВ НАЖАТЫХ КЛАВИШ.
NUMSTR:     .BYTE 256                       ; 0x0800. УКАЗАТЕЛЬ НА ASCII-СТРОКУ С ЧИСЛОМ В SRAM.

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

.IFDEF EMULKEYPD
            POP RETH                        ; БЭКАПИМ АДРЕС ВОЗВРАТА ПОСЛЕ ПРЕРЫВАНИЯ.
            POP RETL                        ;
            POP R17                         ; ИЗВЛЕКАЕМ АДРЕС ТЕКУЩЕГО СОСТОЯНИЯ.
            POP R16                         ;
            PUSH ZL                         ; БЭКАПИМ УКАЗАТЕЛЬ НА ТЕСТОВУЮ ЧИСЛОВУЮ СТРОКУ, НА ОСНОВЕ КОТОРОЙ ЭМУЛИРУЕТСЯ ВВОД.
            PUSH ZH                         ;
            MOV ZL,R16                      ; ПЕРЕМЕЩАЕМ АДРЕС ОБРАБОТЧИКА ТЕКУЩЕГО СОСТОЯНИЯ В Z.
            MOV ZH,R17                      ;
            IJMP                            ;
.ELSE
            POP RETH                        ; БЭКАПИМ АДРЕС ВОЗВРАТА ПОСЛЕ ПРЕРЫВАНИЯ.
            POP RETL                        ;
            POP ZH                          ; ИЗВЛЕКАЕМ АДРЕС ОБРАБОТЧИКА ТЕКУЩЕГО СОСТОЯНИЯ.
            POP ZL                          ;
            IJMP                            ; ПРЫГАЕМ НА ОБРАБОТЧИК, СООТВЕТСТВУЮЩИЙ ТЕКУЩЕМУ СОСТОЯНИЮ.
.ENDIF

            ;
            ; S0 - НАЧАЛЬНОЕ СОСТОЯНИЕ ПЕРЕД ВВОДОМ ПЕРВОГО ИЛИ ВТОРОГО ОПЕРАНДА.
            ;
            ; ДОПУСТИМЫ ТОЛЬКО ЦИФРОВЫЕ КЛАВИШИ И МИНУС.
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

.IFDEF EMULKEYPD
S0END:      POP ZH                          ; ВОССТАНАВЛИВАЕМ УКАЗАТЕЛЬ НА ТЕСТОВУЮ ЧИСЛОВУЮ СТРОКУ.
            POP ZL                          ;
            PUSH R16                        ; ЗАПОМИНАЕМ НОВОЕ СОСТОЯНИЕ.
            PUSH R17                        ;
            PUSH RETL                       ; ВОССТАНАВЛИВАЕМ АДРЕС ВОЗВРАТА ПОСЛЕ ПРЕРЫВАНИЯ.
            PUSH RETH                       ;
            RETI                            ;
.ELSE
S0END:      PUSH R16                        ; ЗАПОМИНАЕМ НОВОЕ СОСТОЯНИЕ.
            PUSH R17                        ;
            PUSH RETL                       ; ВОССТАНАВЛИВАЕМ АДРЕС ВОЗВРАТА ПОСЛЕ ПРЕРЫВАНИЯ.
            PUSH RETH                       ;
            RETI                            ;
.ENDIF

            ;
            ; S1 - ПРОМЕЖУТОЧНОЕ СОСТОЯНИЕ ПОСЛЕ НАЖАТИЯ НУЛЯ.
            ;
            ; ДОПУСТИМЫ ТОЛЬКО ТОЧКА ИЛИ КЛАВИШИ ОПЕРАТОРА.
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
            LDI ZL,LOW(OP1FLTERR0)          ;
            LDI ZH,HIGH(OP1FLTERR0)         ;
            RJMP OP1CNVRT                   ;
OP1FLTERR0: POP R16                         ; ВЫБРАСЫВАЕМ ИЗ СТЕКА АДРЕС ВОЗВРАТА ПОСЛЕ ATOF.
            POP R16                         ;
            POP RETH                        ; ВОССТАНАВЛИВАЕМ АДРЕС ВОЗВРАТА ПОСЛЕ ПРЕРЫВАНИЯ.
            POP RETL                        ;
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
            ST X+,R16                       ; NUMSTR+='\0'.

            LDI R16,LOW(SHOWRES)            ; ПРИ ВВОДЕ ПЕРВОГО ОПЕРАНДА ПРОИЗОШЛО ИСКЛЮЧЕНИЕ,
            LDI R17,HIGH(SHOWRES)           ; ДАЛЬНЕЙШИЙ ВВОД НЕ ИМЕЕТ СМЫСЛА, ПОКАЗЫВАЕМ СООБЩЕНИЕ ОБ ОШИБКЕ.
            RJMP OP1END                     ;

OP1CNVRT:   PUSH RETL                       ; МЫ ВСЁ ЕЩЕ ВНУТРИ ОБРАБОТКИ ПРЕРЫВАНИЯ, ПОЭТОМУ ВАЖНО
            PUSH RETH                       ; НЕ ПОТЕРЯТЬ КОРРЕКТНЫЙ АДРЕС ВОЗВРАТА.
            CALL ATOF                       ;
            POP RETH                        ;
            POP RETL                        ;

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
            ST X+,R16                       ; NUMSTR+='\0'.
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
            LDI XL,LOW(NUMSTR)              ; NUMSTR="ERR".
            LDI XH,HIGH(NUMSTR)             ;
            LDI R16,'E'                     ;
            ST X+,R16                       ;
            LDI R16,'R'                     ;
            ST X+,R16                       ;
            ST X+,R16                       ;
            CLR R16                         ;
            ST X+,R16                       ; NUMSTR+='\0'.
            RJMP OP2END                     ;

OPCHK:      LDI R17,'+'                     ;
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

            LDI R16,PREC                    ; УСТАНАВЛИВАЕМ ЖЕЛАЕМОЕ КОЛИЧЕСТВО ДЕСЯТИЧНЫХ ДРОБНЫХ РАЗРЯДОВ.
            MOV R12,R16                     ;

            PUSH RETL                       ;
            PUSH RETH                       ;
            CALL FTOA                       ; *NUMSTR=FTOA(C,PRECISION), ГДЕ C - РЕЗУЛЬТАТ ВЫЧИСЛЕНИЙ В ФОРМАТЕ БИНАРНОГО FLOAT32,
            POP RETH                        ; А PRECISION - КОЛИЧЕСТВО ДЕСЯТИЧНЫХ ДРОБНЫХ РАЗРЯДОВ.
            POP RETL                        ;

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
.IFDEF EMULKEYPD
SHOWRES:    POP ZH                          ; ВОССТАНАВЛИВАЕМ УКАЗАТЕЛЬ НА ТЕСТОВУЮ ЧИСЛОВУЮ СТРОКУ.
            POP ZL                          ; СТЕК ПУСТОЙ.

            LDI R16,'C'                     ;
            EOR R16,KEY                     ; БЫЛА НАЖАТА КЛАВИША 'C'?
            BRNE STAY                       ; НЕТ, ИГНОРИРУЕМ НАЖАТИЕ.
            JMP RESETINPUT                  ; ДА, СБРАСЫВАЕМ СОСТОЯНИЕ КАЛЬКУЛЯТОРА НА НУЛЕВОЕ.
.ELSE
SHOWRES:    LDI R16,'C'                     ;
            EOR R16,KEY                     ; БЫЛА НАЖАТА КЛАВИША 'C'?
            BRNE STAY                       ; НЕТ, ИГНОРИРУЕМ НАЖАТИЕ.
            JMP RESETINPUT                  ; ДА, СБРАСЫВАЕМ СОСТОЯНИЕ КАЛЬКУЛЯТОРА НА НУЛЕВОЕ.
.ENDIF

STAY:       LDI R16,LOW(SHOWRES)            ;
            LDI R17,HIGH(SHOWRES)           ;
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

;
; ЭМУЛЯЦИЯ ВВОДА С КЛАВИАТУРЫ ДЛЯ ПРОВЕРКИ ОБРАБОТЧИКА ПРЕРЫВАНИЙ ПО КЛАВИАТУРЕ.
;
; КОНФИГУРАЦИЯ ПОРТА D - НА ВЫХОД, НА ВРЕМЯ ПРОГРАММНОГО ТЕСТИРОВАНИЯ ВВОДА С КЛАВИАТУРЫ.
; ЭТО НУЖНО ДЛЯ ВЫСТАВЛЕНИЯ ДАННЫХ НА ПОРТУ И ПРОГРАММНОГО ВЫЗОВА ПРЕРЫВАНИЯ ПРЯМО ИЗ ЭТОГО КОДА.
.IFDEF EMULKEYPD
            SER R16                         ; НАСТРАИВАЕМ ПОРТ D НА ВЫХОД,
            OUT DDRD,R16                    ; ЧТОБЫ ПРОГРАММНО ВЫСТАВЛЯТЬ КОД КЛАВИШИ И
            LDI R16,0x00                    ; ИНИЦИИРОВАТЬ ПРЕРЫВАНИЕ ПО INT0.
            OUT PORTD,R16                   ;
.ELSE
            CLR R16                         ;
            OUT DDRD,R16                    ;
            LDI R16,0xFF                    ;
            OUT PORTD,R16                   ;
.ENDIF

            LDI R16,(1<<ISC01|1<<ISC00)     ; РАЗРЕШАЕМ ВНЕШНИЕ ПРЕРЫВАНИЯ
            STS EICRA,R16                   ; ПО INT0, ПО ПЕРЕДНЕМУ ФРОНТУ.
            LDI R16,(1<<INT0)               ;
            OUT EIMSK,R16                   ;
            SEI                             ;

            LDI ZL,LOW(KEYMAPPRG << 1)      ; ЧИТАЕМ ТАБЛИЦУ ASCII-КОДОВ КЛАВИШ В SRAM.
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
KEYMAPPRG:  .DB "C0./123*456-789+",0

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
TESTNUM:  .DB "0/0+",0

;TESTNUM:  .DB "0+5+",0
.ENDIF

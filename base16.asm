                                            ; Kernel/CPU-Architektur: x86-64 Bit Linux (Little Endian)
                                            ; Der Standard-Linker ld erzeugt beim direkten Linken von
                                            ; Assembler-Objektdateien eine klassische EXEC-Binärdatei,
                                            ; bei der alle virtuellen Zieladressen festgeschrieben werden.
section .rodata                             ; Read only: 0x00400000

hexlut: db '0123456789ABCDEF'               ; Lookup-Table ASCII-Hex-Zeichen

align 16
                                            ; Inverse Lookup: ASCII-Byte
hexinv:                                     ; Nibble-Wert (0–15) oder 0xFF = ungültig
    times 48 db 0xFF                        ; 0x00–0x2F  ungültig
    db 0,1,2,3,4,5,6,7,8,9                  ; '0'–'9'    (0x30–0x39)
    times 7  db 0xFF                        ; 0x3A–0x40  ungültig
    db 10,11,12,13,14,15                    ; 'A'–'F'    (0x41–0x46)
    times 26 db 0xFF                        ; 0x47–0x60  ungültig
    db 10,11,12,13,14,15                    ; 'a'–'f'    (0x61–0x66)
    times (256-103) db 0xFF                 ; 0x67–0xFF  ungültig

msg_help:
    db  "base16 – Binary <-> Hex-ASCII", 10
    db  10
    db  "Usage:", 10
    db  "  cat file.bin | ./base16           Encode  stdin -> stdout", 10
    db  "  base16 < infile > outfile         Encode  (Redirect)", 10
    db  "  base16 infile outfile             Encode  Datei -> Datei", 10
    db  "  base16 --bin infile outfile       Decode  Datei -> Datei", 10
    db  "  base16 --bin < infile > outfile   Decode  (Redirect)", 10
    db  10
    db  "Default: Binary -> Hex-ASCII", 10
    db  "Mit --bin: Hex-ASCII -> Binary", 10
msg_help_len equ $ - msg_help

msg_err_open:
    db  "Fehler: Datei konnte nicht geoeffnet werden", 10
msg_err_open_len equ $ - msg_err_open

arg_bin:     db  "--bin", 0
arg_bin_len  equ 5



section .bss                                ; 0x0000000000402000 RW
align 16
inbuf:   resb 0x4000                        ; 16 KiB Eingabepuffer
outbuf:  resb 0x8000                        ; 32 KiB Ausgabepuffer Encode verdoppelt
termios: resb 64                            ; Puffer TTY-Erkennung
                                            ; --------------------------
                                            ; Wenn das Programm startest über den Systemaufruf
                                            ; execve lädt der Kernel die ELF-Datei und prüft deren Header.
section .text                               ; Da der Kernel im privilegierten Modus Ring 0 läuft,
    global _start                           ; nutzt er spezielle CPU-Befehle: sysretq oder iretq,
                                            ; Diese Befehle wechseln gleichzeitig das CPU-Privilegienlevel
                                            ; von Ring 0 Kernel zu Ring 3 Userspace.
_start:                                     ; Kernel setzt den Instruction Pointer hier auf 0x00401000 R E
    mov     r13, [rsp]                      ; argc
    cmp     r13, 1                          ;
    je      .check_pipe                     ; keine Parameter -> Pipe/TTY pruefen
    cmp     r13, 2                          ;
    je      .check_bin_flag_only            ; nur "--bin" -> Decode von stdin
    cmp     r13, 3                          ;
    je      .mode_encode_files              ; infile outfile -> Encode
    cmp     r13, 4                          ;
    je      .check_bin_files                ; --bin infile outfile -> Decode
    jmp     .show_help                      ; alles andere -> Hilfe

; ================================================================================================
; Keine Parameter: Ist stdin ein Terminal?
;   ja     Hilfe ausgeben
;   nein   Encode von stdin nach stdout Pipe
;
; Schlaegt fehl (rax < 0), wenn fd 0 kein Terminal ist.
; ================================================================================================
.check_pipe:                                ; ioctl(0, TCGETS, &termios)
    mov     rax, 16                         ; sys_ioctl
    xor     rdi, rdi                        ;
    mov     rsi, 0x5401                     ; TCGETS
    lea     rdx, [rel termios]
    syscall
    test    rax, rax
    jns     .show_help                      ; Erfolg -> TTY -> Hilfe
    lea     r10, [rel encode_func]
    xor     r14, r14                        ; in_fd  = 0 (stdin)
    mov     r15, 1                          ; out_fd = 1 (stdout)
    jmp     .read_loop

; ================================================================================================
; Genau ein Argument: muss "--bin" sein, Decode stdin pipe to stdout
; ================================================================================================
.check_bin_flag_only:
    mov     rsi, [rsp+16]                   ; argv[1]
    call    .is_bin_flag
    test    rax, rax
    jz      .show_help
    lea     r10, [rel decode_func]
    xor     r14, r14
    mov     r15, 1
    jmp     .read_loop

; ================================================================================================
; argc == 3:  infile outfile Encode (Binary to Hex)
; ================================================================================================
.mode_encode_files:
    lea     r10, [rel encode_func]
    mov     rdi, [rsp+16]                   ; argv[1] = infile
    mov     rsi, [rsp+24]                   ; argv[2] = outfile
    call    .open_files
    jmp     .read_loop

; ================================================================================================
; argc == 4:  --bin infile outfile, Decode Hex to Binary
; ================================================================================================
.check_bin_files:
    mov     rsi, [rsp+16]                   ; argv[1]
    call    .is_bin_flag
    test    rax, rax
    jz      .show_help
    lea     r10, [rel decode_func]
    mov     rdi, [rsp+24]                   ; argv[2] = infile
    mov     rsi, [rsp+32]                   ; argv[3] = outfile
    call    .open_files
    jmp     .read_loop

; ================================================================================================
; .is_bin_flag
;   Eingabe:  rsi = Zeiger auf Argument-String
;   Ausgabe:  rax = 1 wenn String genau "--bin" ist, sonst 0
; ================================================================================================
.is_bin_flag:
    push    rsi
    push    rdi
    push    rcx
    lea     rdi, [rel arg_bin]
    mov     rcx, arg_bin_len
.cmp_loop:
    mov     al, [rsi]
    mov     ah, [rdi]
    cmp     al, ah
    jne     .not_bin
    inc     rsi
    inc     rdi
    dec     rcx
    jnz     .cmp_loop
    mov     al, [rsi]
    test    al, al
    jnz     .not_bin
    mov     rax, 1
    jmp     .bin_done
.not_bin:
    xor     rax, rax
.bin_done:
    pop     rcx
    pop     rdi
    pop     rsi
    ret

; ================================================================================================
; .open_files
;   Eingabe:  rdi = Pfad Eingabedatei, rsi = Pfad Ausgabedatei
;   Ausgabe:  r14 = in_fd, r15 = out_fd
; ================================================================================================
.open_files:
    push    rsi
    mov     rax, 2                          ; sys_open
    xor     rsi, rsi                        ; O_RDONLY
    xor     rdx, rdx
    syscall
    cmp     rax, 0
    jl      .open_fail
    mov     r14, rax
    pop     rdi
    mov     rax, 2
    mov     rsi, 0x241                      ; O_WRONLY|O_CREAT|O_TRUNC
    mov     rdx, 0644o
    syscall
    cmp     rax, 0
    jl      .open_fail
    mov     r15, rax
    ret

.open_fail:
    mov     rax, 1
    mov     rdi, 2
    lea     rsi, [rel msg_err_open]
    mov     rdx, msg_err_open_len
    syscall
    mov     rax, 60
    mov     rdi, 1
    syscall

.show_help:
    mov     rax, 1
    mov     rdi, 2
    lea     rsi, [rel msg_help]
    mov     rdx, msg_help_len
    syscall
    mov     rax, 60
    mov     rdi, 1
    syscall

; ================================================================================================
; Streaming-Hauptschleife
;   r10 = Konvertierungsfunktion
;   r14 = Eingabe-fd
;   r15 = Ausgabe-fd
; ================================================================================================
.read_loop:
    xor     eax, eax
    mov     rdi, r14
    lea     rsi, [rel inbuf]
    mov     edx, 0x4000
    syscall
    test    rax, rax
    jle     .exit
    mov     r12, rax
    cmp     r12, 0x4000
    jne     .not_full
    xor     r8d, r8d
    jmp     .do_convert
.not_full:
    mov     r8d, 1
.do_convert:
    lea     rsi, [rel inbuf]
    lea     rdi, [rel outbuf]
    call    r10
    lea     rsi, [rel outbuf]
    mov     rdx, rdi
    sub     rdx, rsi
    test    rdx, rdx
    jz      .after_write
    mov     eax, 1
    mov     rdi, r15
    syscall
.after_write:
    test    r8d, r8d
    jz      .read_loop
.exit:
    mov     rax, 3
    mov     rdi, r14
    syscall
    mov     rax, 3
    mov     rdi, r15
    syscall
    mov     eax, 60
    xor     edi, edi
    syscall

; ================================================================================================
; encode_func: Binary to Hex-ASCII
;
; Eingabe:  rsi = Eingabepuffer, rdi = Ausgabepuffer, r12 = Länge
; Ausgabe:  rdi = Ende der Ausgabe
; Register: rax, rbx, rcx, rdx, r9
;
; Beispiel:  Byte 0xA3
;   High-Nibble: 0xA3 >> 4  =  0x0A mapping  hexlut[10] = 'A'
;   Low-Nibble:  0xA3 & 0x0F = 0x03 mapping  hexlut[3]  = '3'
;   Ergebnis auf Vector rdi: A3
; ================================================================================================
encode_func:
    lea     r9, [rel hexlut]
    mov     rbx, r12
.enc_main:
    cmp     rbx, 8
    jb      .enc_remainder
    mov     rax, [rsi]                      ; 8 Bytes laden
    add     rsi, 8
    sub     rbx, 8
    mov     rcx, 8
.enc_byte8:
    mov     rdx, rax
    shr     rdx, 4                          ; High-Nibble
    and     edx, 0x0F
    mov     dl, [r9 + rdx]
    mov     [rdi], dl
    inc     rdi
    mov     rdx, rax
    and     edx, 0x0F                       ; Low-Nibble
    mov     dl, [r9 + rdx]
    mov     [rdi], dl
    inc     rdi
    shr     rax, 8                          ; naechstes Byte
    dec     rcx
    jnz     .enc_byte8
    jmp     .enc_main
.enc_remainder:
    test    rbx, rbx
    jz      .enc_done
.enc_rem:
    movzx   eax, byte [rsi]
    inc     rsi
    dec     rbx
    mov     edx, eax
    shr     edx, 4
    and     edx, 0x0F
    mov     dl, [r9 + rdx]
    mov     [rdi], dl
    inc     rdi
    and     eax, 0x0F
    mov     dl, [r9 + rax]
    mov     [rdi], dl
    inc     rdi
    test    rbx, rbx
    jnz     .enc_rem
.enc_done:
    ret

; ================================================================================================
; decode_func: Hex-ASCII to Binary
;
; Eingabe:  rsi = Eingabepuffer, rdi = Ausgabepuffer, r12 = Länge
; Ausgabe:  rdi = Ende der Ausgabe
; Register: rax, rbx, rcx, rdx, r9
;
; Beispiel:  "A3"
;   'A' mapping hexinv['A'] = 10
;   '3' mapping hexinv['3'] =  3
;   Ergebnis: (10 << 4) | 3 = 0xA3
;
; Ungültige Zeichen (0xFF) werden übersprungen.
; Ungerade Nibble-Anzahl: letztes Nibble als Low, High = 0.
; ================================================================================================
decode_func:
    lea     r9, [rel hexinv]
    mov     rbx, r12
.dec_loop:
    cmp     rbx, 2
    jb      .dec_odd
    movzx   eax, byte [rsi]
    inc     rsi
    movzx   eax, byte [r9 + rax]
    cmp     al, 0xFF
    je      .dec_skip_one
    mov     ecx, eax
    shl     ecx, 4                          ; High-Nibble
    movzx   eax, byte [rsi]
    inc     rsi
    movzx   eax, byte [r9 + rax]
    cmp     al, 0xFF
    je      .dec_skip_lo
    or      ecx, eax                        ; High | Low
    mov     [rdi], cl
    inc     rdi
    sub     rbx, 2
    jmp     .dec_loop
.dec_skip_one:
    dec     rbx
    jmp     .dec_loop
.dec_skip_lo:
    mov     [rdi], cl
    inc     rdi
    sub     rbx, 2
    jmp     .dec_loop
.dec_odd:
    test    rbx, rbx
    jz      .dec_done
    movzx   eax, byte [rsi]
    inc     rsi
    dec     rbx
    movzx   eax, byte [r9 + rax]
    cmp     al, 0xFF
    je      .dec_done
    mov     [rdi], al                       ; High=0, Low=Nibble
    inc     rdi
.dec_done:
    ret

; ================================================================================================
; Vergleich zwei Files
;
;   - Dateien werden chunkweise per read() gelesen und verglichen
;   - Kein vollständiges Mapping der Dateien ins RAM
;   - Erste Differenzposition wird mitgeführt und ausgegeben
;
; nasm -f elf64 compare.asm -o compare.o && ld compare.o -o compare
; ./compare dateiA dateiB
; Vergleichsvorbereitung Streaming:
;
; Persistente Register (dürfen von syscall NICHT zerstört werden):
;   r8  = verbleibende Bytes
;   r9  = Buffer A
;   r10 = Buffer B
;   r12 = XOR-Akkumulator (0 = identisch)
;   r13 = aktuelle Chunk-Größe
;   r14 = fd_a
;   r15 = fd_b
;
; Achtung: rcx und r11 werden von jedem syscall zerstört
; Deshalb liegt first_diff in BSS, nicht in r11
; ================================================================================================
section .data
    msg_usage       db  "Usage: ./compare <DateiA> <DateiB>", 10
    msg_usage_len   equ $ - msg_usage
    msg_size_a      db  "Datei A: "
    msg_size_a_len  equ $ - msg_size_a
    msg_size_b      db  " Bytes", 10, "Datei B: "
    msg_size_b_len  equ $ - msg_size_b
    msg_bytes       db  " Bytes", 10
    msg_bytes_len   equ $ - msg_bytes
    msg_identical   db  "Dateien sind identisch", 10
    msg_identical_len equ $ - msg_identical
    msg_different   db  "Dateien unterscheiden sich", 10
    msg_different_len equ $ - msg_different
    msg_diff_at     db  "Unterschied bei Byte-Offset: "
    msg_diff_at_len equ $ - msg_diff_at
    msg_newline     db  10
    msg_newline_len equ 1
    msg_error       db  "Fehler beim Oeffnen/Lesen der Datei", 10
    msg_error_len   equ $ - msg_error
    BUFSIZE         equ 4 * 1024 * 1024

section .bss
    numbuf          resb 32
    statbuf_a       resb 144
    statbuf_b       resb 144
    file_size       resq 1                  ; gespeicherte Dateigröße
    first_diff      resq 1                  ; Offset der ersten Differenz −1 = keine

section .text
    global _start

; ================================================================================================
_start:                                     ; Programmstart
    mov     rax, [rsp]
    cmp     rax, 3
    jne     usage_error
    mov     r12, [rsp+16]                   ; argv[1]
    mov     r13, [rsp+24]                   ; argv[2]
    mov     rax, 2                          ; sys_open
    mov     rdi, r12                        ; Datei A öffnen
    xor     rsi, rsi                        ; O_RDONLY
    xor     rdx, rdx
    syscall
    cmp     rax, 0
    jl      open_error
    mov     r14, rax                        ; fd_a
    mov     rax, 2
    mov     rdi, r13
    xor     rsi, rsi
    xor     rdx, rdx
    syscall                                 ; Datei B öffnen
    cmp     rax, 0
    jl      open_error
    mov     r15, rax                        ; fd_b
    mov     rax, 5                          ; sys_fstat
    mov     rdi, r14
    lea     rsi, [rel statbuf_a]
    syscall
    cmp     rax, 0
    jl      open_error
    mov     rbx, [rel statbuf_a + 48]       ; st_size A
    mov     rax, 5
    mov     rdi, r15
    lea     rsi, [rel statbuf_b]
    syscall
    cmp     rax, 0
    jl      open_error
    mov     rcx, [rel statbuf_b + 48]       ; st_size B
    cmp     rbx, rcx
    je      sizes_equal                     ; unterschiedliche Größe
    mov     rax, 1
    mov     rdi, 2
    lea     rsi, [rel msg_size_a]
    mov     rdx, msg_size_a_len
    syscall
    mov     rdi, rbx
    call    print_number
    mov     rax, 1
    mov     rdi, 2
    lea     rsi, [rel msg_size_b]
    mov     rdx, msg_size_b_len
    syscall
    mov     rdi, rcx
    call    print_number
    mov     rax, 1
    mov     rdi, 2
    lea     rsi, [rel msg_bytes]
    mov     rdx, msg_bytes_len
    syscall
    jmp     exit_1
sizes_equal:
    mov     [rel file_size], rbx        ; Dateigröße merken

; ================================================================================================
; Zwei Puffer allokieren kein File-Mapping
; PROT_READ|PROT_WRITE = 3
; MAP_PRIVATE|MAP_ANONYMOUS = 0x22
; ================================================================================================
    mov     rax, 9                      ; sys_mmap
    xor     rdi, rdi
    mov     rsi, BUFSIZE
    mov     rdx, 3
    mov     r10, 0x22
    mov     r8, -1
    xor     r9, r9
    syscall
    cmp     rax, 0
    jl      open_error
    mov     r12, rax                    ; bufA
    mov     rax, 9
    xor     rdi, rdi
    mov     rsi, BUFSIZE
    mov     rdx, 3
    mov     r10, 0x22
    mov     r8, -1
    xor     r9, r9
    syscall
    cmp     rax, 0
    jl      open_error
    mov     r10, rax                    ; bufB
    mov     r8, rbx                     ; remaining = Dateigröße
    mov     r9, r12                     ; bufA
    xor     r12, r12                    ; XOR-Akkumulator = 0
    mov     qword [rel first_diff], -1  ; siehe Zeile 8: Vergleichsvorbereitung Streaming

; ================================================================================================
; XOR-Vergleich des aktuellen Chunks
;
; Absolute Position eines Bytes = (file_size - remaining_vor_diesem_Chunk) + Index_im_Chunk
;
; remaining wurde noch nicht verringert
; base = file_size - r8
; index im Chunk = r13 - rcx
; rcx zählt noch runter
;
; offset = (file_size - remaining) + (chunk_size - rcx) = file_size - r8 + r13 - rcx
; ================================================================================================
compare_loop:
    test    r8, r8
    jz      compare_done
    mov     rdx, BUFSIZE
    cmp     r8, rdx
    cmovb   rdx, r8                     ; rdx = min(remaining, BUFSIZE)
    mov     r13, rdx                    ; Chunk-Größe
    mov     rax, 0                      ; sys_read
    mov     rdi, r14
    mov     rsi, r9
    mov     rdx, r13
    syscall                             ; Chunk aus Datei A lesen
    cmp     rax, 0
    jle     open_error
    cmp     rax, r13
    jne     open_error
    mov     rax, 0
    mov     rdi, r15
    mov     rsi, r10
    mov     rdx, r13
    syscall                             ; Chunk aus Datei B lesen
    cmp     rax, 0
    jle     open_error
    cmp     rax, r13
    jne     open_error
    mov     rsi, r9                     ; Buffer A
    mov     rdi, r10                    ; Buffer B
    mov     rcx, r13                    ; Bytes in diesem Chunk
xor_loop:
    test    rcx, rcx
    jz      xor_done
    mov     al, [rsi]
    xor     al, [rdi]
    or      r12b, al                    ; irgendeine Differenz?
    test    al, al                      ; Erste Differenz
    jz      .no_diff                    ; absoluten Offset berechnen und speichern
    cmp     qword [rel first_diff], -1
    jne     .no_diff
    mov     rax, [rel file_size]        ; siehe offset Zeile 157
    sub     rax, r8                     ; bereits verarbeitete Bytes vor diesem Chunk
    add     rax, r13
    sub     rax, rcx                    ; add Index innerhalb des Chunks
    mov     [rel first_diff], rax
.no_diff:
    inc     rsi
    inc     rdi
    dec     rcx
    jmp     xor_loop
xor_done:
    sub     r8, r13                     ; remaining -= Chunk-Größe
    jmp     compare_loop
compare_done:
    test    r12, r12
    jnz     files_different
    mov     rax, 1
    mov     rdi, 1
    lea     rsi, [rel msg_identical]
    mov     rdx, msg_identical_len
    syscall
    jmp     cleanup_exit_0
files_different:
    mov     rax, 1
    mov     rdi, 1
    lea     rsi, [rel msg_different]
    mov     rdx, msg_different_len
    syscall
    cmp     qword [rel first_diff], -1
    je      cleanup_exit_0
    mov     rax, 1
    mov     rdi, 2
    lea     rsi, [rel msg_diff_at]
    mov     rdx, msg_diff_at_len
    syscall
    mov     rdi, [rel first_diff]
    call    print_number
    mov     rax, 1
    mov     rdi, 2
    lea     rsi, [rel msg_newline]
    mov     rdx, msg_newline_len
    syscall
cleanup_exit_0:
    mov     rax, 11                     ; munmap
    mov     rdi, r9
    mov     rsi, BUFSIZE
    syscall
    mov     rax, 11
    mov     rdi, r10
    mov     rsi, BUFSIZE
    syscall
    mov     rax, 3                      ; close
    mov     rdi, r14
    syscall
    mov     rax, 3
    mov     rdi, r15
    syscall
    mov     rax, 60
    xor     rdi, rdi                    ; exit return 0
    syscall
usage_error:
    mov     rax, 1
    mov     rdi, 2
    lea     rsi, [rel msg_usage]
    mov     rdx, msg_usage_len
    syscall
    jmp     exit_1
open_error:
    mov     rax, 1
    mov     rdi, 2
    lea     rsi, [rel msg_error]
    mov     rdx, msg_error_len
    syscall
exit_1:
    mov     rax, 60
    mov     rdi, 1
    syscall

; ================================================================================================
; print_number: Wert in rdi als Dezimalzahl auf stderr
; ================================================================================================
print_number:
    push    rbx
    push    rcx
    push    rdx
    push    rsi
    push    rdi
    lea     rsi, [rel numbuf + 31]
    mov     byte [rsi], 0
    mov     rax, rdi
    mov     rbx, 10
    xor     rcx, rcx
.convert:
    xor     rdx, rdx
    div     rbx
    add     dl, '0'
    dec     rsi
    mov     [rsi], dl
    inc     rcx
    test    rax, rax
    jnz     .convert
    mov     rax, 1
    mov     rdi, 2
    mov     rdx, rcx
    syscall
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
    ret

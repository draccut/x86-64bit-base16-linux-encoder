; ================================================================================================
; erzeugt "random500mb.bin" (500 MiB) mit Daten aus /dev/random
;
; random500.asm
; nasm -f elf64 random500.asm -o random500.o
; ld random500.o -o random500
;./random500
; ================================================================================================

section .data
    outname     db "random500mb.bin", 0
    devrandom   db "/dev/random", 0
    bufsize     equ 0x1000                    ; 4 KiB Puffer
    filesize    equ 500 * 1024 * 1024         ; 500 MiB

section .bss
    buffer      resb bufsize

section .text
    global _start

; ================================================================================================
_start:
    mov     rax, 2                          ; sys_open
    lea     rdi, [rel devrandom]
    xor     rsi, rsi                        ; O_RDONLY = 0
    xor     rdx, rdx
    syscall                                 ; /dev/random öffnen
    cmp     rax, 0
    jl      exit_error
    mov     r12, rax                        ; r12 = fd_random
                                            ;
    mov     rax, 2                          ; sys_open
    lea     rdi, [rel outname]
    mov     rsi, 577                        ; O_WRONLY|O_CREAT|O_TRUNC = 1|64|512 = 577
    mov     rdx, 0o644                      ; rw-r--r--
    syscall                                 ; Ausgabedatei anlegen und öffnen
    cmp     rax, 0
    jl      exit_error
    mov     r13, rax                        ; r13 = fd_out
    mov     r14, filesize                   ; noch zu schreibende Bytes

; ================================================================================================
write_loop:
    mov     rdx, bufsize
    cmp     r14, bufsize
    jae     .size_ok
    mov     rdx, r14
.size_ok:
    mov     rax, 0                          ; sys_read
    mov     rdi, r12
    lea     rsi, [rel buffer]
    syscall                                 ; Aus /dev/random lesen
    cmp     rax, 0
    jle     exit_error                      ; Fehler oder EOF
    mov     r15, rax                        ; tatsächlich gelesene Bytes
    mov     rax, 1                          ; sys_write
    mov     rdi, r13
    lea     rsi, [rel buffer]
    mov     rdx, r15
    syscall                                 ; In die Datei schreiben
    cmp     rax, r15
    jne     exit_error
    sub     r14, r15
    jnz     write_loop
    mov     rax, 3                          ; sys_close
    mov     rdi, r12
    syscall                                 ; FDs schließen
    mov     rax, 3
    mov     rdi, r13
    syscall
    mov     rax, 60                         ; sys_exit
    xor     rdi, rdi                        ; return 0
    syscall                                 ; Erfolg

; ================================================================================================
exit_error:
    mov     rax, 60
    mov     rdi, 1                          ; return 1
    syscall

; ================================================================================================
; nasm -f elf64 random500.asm -o random500.o && ld random500.o -o random500
; ================================================================================================

section .data
    outname     db "/tmp/default.bin", 0
    devrandom   db "/dev/random", 0
    bufsize     equ 0x1000                  ; 4 KiB Puffer
    filesize    equ 500 * 1024 * 1024       ; 500 MiB

section .bss
    buffer      resb bufsize

section .text
    global _start

_start:                                     ; START
    mov     rax, [rsp]                      ; argc
    mov     r8,  0                          ; r8  = argv[1] (oder 0)
    mov     r9,  0                          ; r9  = argv[2] (oder 0)
    mov     r10, 0                          ; r10 = argv[3] Message (oder 0)
    cmp     rax, 1
    je      .defaults                       ; keine Argumente → Defaults
    mov     r8, [rsp + 16]                  ; r8 = argv[1]
    cmp     rax, 2
    je      .one_file                       ; nur eine Ausgabedatei
    mov     r9, [rsp + 24]                  ; r9 = argv[2]
    cmp     rax, 3
    je      .two_files
    mov     r10, [rsp + 32]                 ; r10 = argv[3] (Message)
    jmp     .two_files
.defaults:
    lea     r8, [rel outname]               ; r8 zeigt auf Default-Pfad
.one_file:
    mov     rax, 2                          ; sys_open
    lea     rdi, [rel devrandom]
    xor     rsi, rsi                        ; O_RDONLY
    xor     rdx, rdx
    syscall
    cmp     rax, 0
    jl      exit_error
    mov     r12, rax                        ; r12 = fd_random
    mov     rax, 2
    mov     rdi, r8
    mov     rsi, 577                        ; O_WRONLY|O_CREAT|O_TRUNC
    mov     rdx, 0o644
    syscall
    cmp     rax, 0
    jl      exit_error
    mov     r13, rax                        ; r13 = fd_out1
    mov     r15, 0                          ; r15 = 0 → nur eine Datei
    mov     r14, filesize
    jmp     write_loop
.two_files:
    mov     rax, 2
    lea     rdi, [rel devrandom]
    xor     rsi, rsi
    xor     rdx, rdx
    syscall
    cmp     rax, 0
    jl      exit_error
    mov     r12, rax                        ; r12 = fd_random
    mov     rax, 2
    mov     rdi, r8
    mov     rsi, 577
    mov     rdx, 0o644
    syscall
    cmp     rax, 0
    jl      exit_error
    mov     r13, rax                        ; r13 = fd_out1
    mov     rax, 2
    mov     rdi, r9
    mov     rsi, 577
    mov     rdx, 0o644
    syscall
    cmp     rax, 0
    jl      exit_error
    mov     r15, rax                        ; r15 = fd_out2
    mov     r14, filesize

; ================================================================================================
write_loop:
    test    r14, r14
    jz      .finished
    mov     rdx, bufsize
    cmp     r14, bufsize
    jae     .size_ok
    mov     rdx, r14
.size_ok:                                   ; aus /dev/random lesen
    mov     rax, 0                          ; sys_read
    mov     rdi, r12
    lea     rsi, [rel buffer]
    syscall
    cmp     rax, 0
    jle     exit_error
    mov     rbx, rax                        ; rbx = tatsächlich gelesene Bytes
    mov     rax, 1                          ; sys_write
    mov     rdi, r13
    lea     rsi, [rel buffer]
    mov     rdx, rbx
    syscall
    cmp     rax, rbx
    jne     exit_error
    test    r15, r15
    jz      .next
    mov     rax, 1
    mov     rdi, r15
    lea     rsi, [rel buffer]
    mov     rdx, rbx
    syscall
    cmp     rax, rbx
    jne     exit_error
.next:
    sub     r14, rbx
    jmp     write_loop
.finished:
    mov     rax, 3
    mov     rdi, r12
    syscall
    mov     rax, 3
    mov     rdi, r13
    syscall
    test    r15, r15
    jz      .maybe_msg
    mov     rax, 3
    mov     rdi, r15
    syscall
.maybe_msg:
    test    r10, r10
    jz      exit_zero
    mov     rdi, r10
    xor     rcx, rcx
.strlen:
    cmp     byte [rdi + rcx], 0
    je      .print
    inc     rcx
    jmp     .strlen
.print:
    mov     rax, 1
    mov     rdi, 1
    mov     rsi, r10
    mov     rdx, rcx
    syscall
    jmp     exit_zero

; ================================================================================================
exit_error:
    mov     rax, 60
    mov     rdi, 1
    syscall

exit_zero:
    mov     rax, 60
    xor     rdi, rdi
    syscall

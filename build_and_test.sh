function help {
    cat << EOF
Usage: ./build_and_test.sh <command>

Commands:
  build   Build base16 and the test suite
  clean   Remove object files and binaries
  test    Build (if needed) and run the test suite
  help    Show this help

If no command is given, this help is displayed.
EOF
}

function build_base16 {
    nasm -f elf64 base16.asm -o base16.o
    ld base16.o -o base16
}

function build_test_suite {
    nasm -f elf64 compare.asm -o compare.o
    ld compare.o -o compare
    nasm -f elf64 random500.asm -o random500.o
    ld random500.o -o random500
}

function clean_up {
    rm -f base16.o compare.o random500.o
    rm -f base16 compare random500
}

function run_tests {
    if [[ ! -x ./compare ]] || [[ ! -x ./random500 ]] || [[ ! -x ./base16 ]]; then
        echo "Binaries missing – running build first..."
        build
    fi
    echo "Running test suite..."
    echo "TODO"
}

function build {
    echo "Building base16..."
    build_base16
    echo "Building test suite..."
    build_test_suite
    echo "Build finished."
}

function clean {
    echo "Cleaning up..."
    clean_up
    echo "Done."
}

function test {
    run_tests
}

function dispatch {
    local cmd="${1:-}"
    case "$cmd" in
        build)
            build
            ;;
        clean)
            clean
            ;;
        test)
            test
            ;;
        help|--help|-h)
            help
            ;;
        "")
            help
            ;;
        *)
            echo "Unknown command: $cmd" >&2
            echo >&2
            help >&2
            exit 1
            ;;
    esac
}

dispatch "${1:-}"

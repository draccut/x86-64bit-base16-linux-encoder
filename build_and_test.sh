function help {
    cat << EOF
Usage: ./build_and_test.sh <command>

Commands:
  build   Build base16 and the test suite
  clean   Remove object files and binaries
  tests   Build (if needed) and run the test suite
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


function tests {
    local temp_dir="temp"
    local random_binary_block="${temp_dir}/random500mb.bin"
    local cc_random_binary_block="${temp_dir}/random500mb.bin.copy"
    local origin_copy_block="${temp_dir}/origin.copy"
    rm -rf "${temp_dir}"
    mkdir -p "${temp_dir}"

    function test_all_assembly_files_are_compiled {
        echo "=== Clean + Build ==="
        clean
        build
        echo "Build fertig."
    }

    function test_compare_asm_same_files {
        echo ""
        echo "=== Test: beide Dateien müssen identisch sein ==="
        echo "param 1: ${random_binary_block}"
        echo "param 2: ${cc_random_binary_block}"
        ./compare "${random_binary_block}" "${cc_random_binary_block}"
        echo "sollen gleich sein"
        cp "${random_binary_block}" "${origin_copy_block}"
    }

    function test_compare_to_empty_path {
        echo ""
        echo "=== Test: Vergleich mit nicht existierender Datei ==="
        ./compare "${random_binary_block}" "${random_binary_block}.b256.notreal"
    }

    function test_encoding_one_file_and_compare {
        echo ""
        echo "=== Test: nach Base16-Kodierung dürfen die Dateien NICHT mehr gleich sein ==="
        ./base16 "${random_binary_block}" "${random_binary_block}.base16"
        mv "${random_binary_block}.base16" "${random_binary_block}"
        ./compare "${random_binary_block}" "${origin_copy_block}"
        echo "Test: not equals (erwartet)"
    }

    function test_encoding_with_nibble {
        echo ""
        echo "=== Test: Base16 Encoder/Decoder mit Nibble-Manipulation ==="
        ./base16 "${random_binary_block}" "${random_binary_block}.b16"
        echo -n "A" >> "${random_binary_block}.b16"  # absichtlich kaputt machen
        ./base16 --bin "${random_binary_block}.b16" "${random_binary_block}.b256"
        ./compare "${origin_copy_block}" "${random_binary_block}.b256"
        echo "sollte jetzt ungleich sein (wegen des extra 'A')"
    }

    function test_encoding_decoding {
        echo ""
        echo "=== Test: Roundtrip (encode --> decode) muss wieder identisch sein ==="
        ./random500 "${random_binary_block}" "${cc_random_binary_block}" "Zwei Files beide haben eine Länge die % 8 = 0"
        ./base16 "${random_binary_block}" "${random_binary_block}.b16"
        ./base16 --bin "${random_binary_block}.b16" "${random_binary_block}.res"
        ./compare "${cc_random_binary_block}" "${random_binary_block}.res"
        echo "--> Test equals (erwartet)"
    }

    echo "Running test suite..."
    test_all_assembly_files_are_compiled
    ./random500 "${random_binary_block}" "${cc_random_binary_block}" "random --> bss buffer --> {storeFile1, storeFile2} es gilt: storeFile1 = storeFile2"
    test_compare_asm_same_files
    ./random500 "${random_binary_block}"
    test_compare_to_empty_path
    ./random500 "${random_binary_block}" "${cc_random_binary_block}" "Test after encoding not the same"
    cp "${random_binary_block}" "${origin_copy_block}"
    test_encoding_one_file_and_compare
    ./random500 "${random_binary_block}" "${cc_random_binary_block}" "Check base16.asm encoder with half bytes"
    cp "${random_binary_block}" "${origin_copy_block}"
    test_encoding_with_nibble
    test_encoding_decoding
    echo ""
    echo "=== Alle Tests durchgelaufen ==="
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
        tests)
            tests
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

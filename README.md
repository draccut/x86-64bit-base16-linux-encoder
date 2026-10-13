# x86-64bit-base16-linux-encoder

Dieses x86-64-Bit-Assembler-Programm für Linux streamt Binärdaten und kodiert diese in Base16 Hexadezimal.
Die dazugehörigen Tests sind ebenfalls vollständig in Assembler geschrieben.

```
cat /dev/random | base64
cat /dev/random | base32
cat /dev/random | base16
```

### Eingabe:

```
cat file | base16                 Encode  stdin -> stdout
base16 < infile > outfile         Encode  (Redirect)
base16 infile outfile             Encode  Datei -> Datei
base16 --bin infile outfile       Decode  Datei -> Datei
base16 --bin < infile > outfile   Decode  (Redirect)
base16                            ohne Pipe/Args -> Hilfe
```

Streaming: solange ein voller Puffer gelesen wird nach dem Schreiben erneut lesen, bis r12 < max

### Das Test-Setup umfasst:

- Ein Vergleichsprogramm, das Unterschiede zwischen zwei Dateien aufzeigt. Damit wird überprüft, ob die Datei nach dem Kodieren und anschließenden Dekodieren identisch mit der Ausgangsdatei bleibt.

- Ein Generator-Programm, das automatisch Testdateien für diese Überprüfung erstellt.

### Decode-Besonderheiten

- Ungerade Nibble-Anzahl: letztes Nibble als Low-Nibble, High = 0

- Ungültige Hex-Zeichen (Whitespace, Kommas) werden übersprungen

### Kompilieren und Tests

./build_and_test.sh

```
Usage: ./build_and_test.sh <command>

Commands:
  build   Build base16 and the test suite
  clean   Remove object files and binaries
  test    Build (if needed) and run the test suite
  help    Show this help

If no command is given, this help is displayed.
```

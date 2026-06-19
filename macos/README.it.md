# Strumenti nativi per macOS

RCKangaroo-MT usa ancora NVIDIA CUDA per il solver kangaroo completo ad alte prestazioni, ma la cartella `macos/` ora contiene strumenti nativi Apple Silicon per preparazione target, check secp256k1, solve CPU tiny-range, benchmark, smoke test Metal e prime primitive aritmetiche Metal.

## Build e check

```sh
make macos-check
```

Questo compila `macos/rck_macos`, esegue vettori secp256k1 host, valida il parsing target, lancia il selftest CPU nativo e prova il check Metal field-add quando Metal e' visibile.

Esempio tiny-range CPU:

```sh
./macos/rck_macos solve-small --range 8 --start 0 --pubkey 025CBDF0646E5DB4EAA398F365F2EA7A0E3D419B7E0330E39CE92BDDEDCAC4F9BC
```

Benchmark CPU:

```sh
make macos-bench
```

Smoke test Metal:

```sh
./macos/rck_macos metal-smoke
```

Se nell'ambiente corrente non e' visibile un device Metal, il comando segnala uno skip invece di fallire. Su un runtime Apple Silicon normale con accesso al device, compila ed esegue un kernel Metal minimo.

Check e benchmark Metal per l'addizione nel campo secp256k1:

```sh
./macos/rck_macos metal-field-test
make macos-metal-field-bench
```

Il kernel field-add usa quattro limb little-endian da 64 bit modulo il primo secp256k1 e confronta l'output Metal con l'oracle CPU. In CI o sessioni sandbox senza device Metal visibile, segnala uno skip pulito.

## Preparare una lista target

```sh
python3 macos/prepare_targets.py stripped.txt -o targets.cleaned.txt
```

Lo script:

- accetta public key secp256k1 compresse `02...` / `03...` e non compresse `04...`;
- valida ogni punto sulla curva secp256k1;
- rimuove righe vuote, commenti e commenti inline con `#`;
- scrive di default public key compresse normalizzate;
- rimuove i duplicati, a meno di usare `--keep-duplicates`.

Opzioni utili:

```sh
python3 macos/prepare_targets.py stripped.txt --stats-only
python3 macos/prepare_targets.py stripped.txt -o targets.cleaned.txt --skip-invalid
python3 macos/prepare_targets.py stripped.txt -o targets.uncompressed.txt --uncompressed
```

Poi copia `targets.cleaned.txt` sulla macchina CUDA e avvia:

```sh
./rckangaroo -dp 16 -range 84 -start 1000000000000000000000 -targets targets.cleaned.txt
```

## Note

Lo script macOS e' volutamente in Python puro e usa solo la standard library. Non richiede Homebrew, CUDA, OpenSSL o pacchetti Python esterni.

Usa autoresearch dalla root della repo:

```sh
python3 autoresearch/runner.py --experiment baseline --budget-sec 5
python3 autoresearch/runner.py --experiment metal_field_add --budget-sec 5
```

Autoresearch registra l'assenza del device Metal come `status=skip`, non come crash, quindi lo stesso esperimento puo' girare sia su Apple Silicon locale sia in CI/headless.

Se vuoi generare tames per il solver completo, fallo sulla macchina CUDA. Con la modalita multi-target il file tames deve gia esistere; generalo separatamente prima di usare `-targets`.

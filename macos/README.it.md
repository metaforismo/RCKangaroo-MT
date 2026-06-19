# Strumenti nativi per macOS

RCKangaroo-MT usa ancora NVIDIA CUDA per il solver kangaroo completo ad alte prestazioni, ma la cartella `macos/` ora contiene strumenti nativi Apple Silicon per preparazione target, check secp256k1, solve CPU tiny-range, benchmark e smoke test Metal.

## Build e check

```sh
make macos-check
```

Questo compila `macos/rck_macos`, esegue vettori secp256k1 host, valida il parsing target e lancia il selftest CPU nativo.

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
```

Se vuoi generare tames per il solver completo, fallo sulla macchina CUDA. Con la modalita multi-target il file tames deve gia esistere; generalo separatamente prima di usare `-targets`.

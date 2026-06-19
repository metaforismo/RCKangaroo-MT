# Strumenti nativi per macOS

RCKangaroo-MT usa ancora NVIDIA CUDA per il solver kangaroo completo ad alte prestazioni, ma la cartella `macos/` ora contiene strumenti nativi Apple Silicon per preparazione target, check secp256k1, solve CPU tiny-range, aritmetica di campo CPU, benchmark, smoke test Metal e prime primitive aritmetiche Metal.

## Build e check

```sh
make macos-check
```

Questo compila `macos/rck_macos`, esegue vettori secp256k1 host, valida il parsing target, lancia il selftest CPU nativo, controlla l'aritmetica di campo CPU e prova il check Metal field-add quando Metal e' visibile.

La build macOS usa `-O3` di default. Puoi fare override quando serve:

```sh
make macos-check MACOS_CXXFLAGS="-std=c++17 -O0 -g -I."
```

Esempio tiny-range CPU:

```sh
./macos/rck_macos solve-small --range 8 --start 0 --pubkey 025CBDF0646E5DB4EAA398F365F2EA7A0E3D419B7E0330E39CE92BDDEDCAC4F9BC
./macos/rck_macos jacobian-kangaroo-small --range 8 --start 0 --pubkey 025CBDF0646E5DB4EAA398F365F2EA7A0E3D419B7E0330E39CE92BDDEDCAC4F9BC --jumps 8 --dp-bits 0 --max-steps 4096
./macos/rck_macos jacobian-kangaroo-multi-small --range 8 --start 2 --targets tests/jacobian_kangaroo_multi_targets.txt --jumps 8 --dp-bits 0 --max-steps 4096
```

`jacobian-kangaroo-small` e' un solver bounded toy per range minuscoli. Esegue walk tame/wild con jump table deterministica, mantiene gli stati in coordinate Jacobian, registra distinguished points e verifica ogni candidato ricavato da collisione con `MultiplyG`. Serve per correttezza ed esperimenti architetturali; non e' il motore kangaroo CUDA/Metal completo.

`jacobian-kangaroo-multi-small` carica un file target con il parser condiviso ed esegue il solver kangaroo Jacobian bounded sui target finche' un candidato viene verificato. Questa versione e' volutamente sequenziale e solo tiny-range; preserva gli indici dei target e testa il data path multi-target su macOS senza spacciarsi per il futuro motore GPU/Metal con tame condivisi.

Benchmark CPU:

```sh
make macos-bench
make macos-point-bench
./macos/rck_macos point-bench --iterations 256 --min-ms 50
make macos-jacobian-point-bench
./macos/rck_macos jacobian-point-bench --iterations 256 --min-ms 50
make macos-jacobian-walk-bench
./macos/rck_macos jacobian-walk-bench --iterations 256 --min-ms 50 --jumps 16
```

`macos-bench` misura il throughput dello scalar `MultiplyG`. `macos-point-bench` misura un walk seriale di addizioni affini: parte da `2G`, aggiunge ripetutamente `G`, e valida il punto finale con un oracle `MultiplyG(n+2)`. E' ancora aritmetica CPU affine, non il percorso solver Metal/Jacobian finale, ma rappresenta meglio il costo del kangaroo walk rispetto alle sole operazioni field isolate.

`macos-jacobian-point-bench` mantiene il punto del walk in coordinate Jacobian ed esegue addizioni mixed Jacobian-piu'-affine di `G`, spostando la costosa inversione di campo fuori dal loop interno. Il JSON include throughput affine di riferimento e `speedup_vs_affine`, così il miglioramento e' misurato contro il baseline point-add piu' semplice.

`macos-jacobian-walk-bench` usa una jump table deterministica di punti affini e applica addizioni mixed Jacobian selezionate dallo stato proiettivo corrente. Traccia in parallelo la distanza scalare e valida il punto finale con un oracle scalare. E' un benchmark del core della walk, non ancora un solver kangaroo completo con distinguished points o collision handling.

Check e benchmark CPU per l'aritmetica nel campo secp256k1:

```sh
./macos/rck_macos cpu-field-test
make macos-cpu-field-bench
./macos/rck_macos cpu-field-bench --iterations 4096 --min-ms 50
```

Il percorso CPU field usa quattro limb little-endian da 64 bit e carry arithmetic con `unsigned __int128`. Il benchmark riporta throughput `field_mul_mod_p` e throughput reference `EcInt` per confronto. `--iterations` controlla la dimensione del sample deterministico; `--min-ms` ripete quel sample finche' la misura nativa dura almeno quei millisecondi, così autoresearch riceve dati meno rumorosi.

Smoke test Metal:

```sh
./macos/rck_macos metal-smoke
```

Se nell'ambiente corrente non e' visibile un device Metal, il comando segnala uno skip invece di fallire. Su un runtime Apple Silicon normale con accesso al device, compila ed esegue un kernel Metal minimo.

Check e benchmark Metal per addizione e moltiplicazione nel campo secp256k1:

```sh
./macos/rck_macos metal-field-test
make macos-metal-field-bench
./macos/rck_macos metal-field-mul-test
make macos-metal-field-mul-bench
make macos-metal-kernels-check
```

I kernel field usano quattro limb little-endian da 64 bit modulo il primo secp256k1 e confrontano l'output Metal con oracle CPU. `field_mul_mod_p` usa decomposizione a 32 bit per moltiplicazione 64x64 portabile dentro Metal. In CI o sessioni sandbox senza device Metal visibile, i check runtime segnalano uno skip pulito. `macos-metal-kernels-check` compila il source Metal estratto quando il Metal Toolchain e' installato; altrimenti segnala uno skip pulito del toolchain.

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
python3 autoresearch/runner.py --experiment point_add_g --budget-sec 5
python3 autoresearch/runner.py --experiment jacobian_point_add_g --budget-sec 5
python3 autoresearch/runner.py --experiment jacobian_jump_walk --budget-sec 5
python3 autoresearch/runner.py --experiment cpu_field_mul --budget-sec 5
python3 autoresearch/runner.py --experiment metal_field_add --budget-sec 5
python3 autoresearch/runner.py --experiment metal_field_mul --budget-sec 5
```

Autoresearch registra l'assenza del device Metal come `status=skip`, non come crash, quindi lo stesso esperimento puo' girare sia su Apple Silicon locale sia in CI/headless.

Se vuoi generare tames per il solver completo, fallo sulla macchina CUDA. Con la modalita multi-target il file tames deve gia esistere; generalo separatamente prima di usare `-targets`.

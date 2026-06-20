# RCKangaroo-MT

RCKangaroo-MT e' un fork GPLv3 di `RCKangaroo v3.1` di RetiredCoder, basato sull'implementazione CUDA del metodo SOTA Kangaroo per ECDLP su secp256k1.

Progetto upstream: https://github.com/RetiredC/RCKangaroo
Raccolta RetiredCoder: https://github.com/RetiredC
Thread di discussione: https://bitcointalk.org/index.php?topic=5517607

Questo fork mantiene single-target, benchmark e tames del progetto originale, e aggiunge una modalita multi-target sperimentale piu strumenti macOS nativi per correttezza, benchmark, smoke test Metal e autoresearch.

## Funzionalita

- Implementazione CUDA SOTA Kangaroo originale di RCKangaroo v3.1.
- Risoluzione single-target con `-pubkey`.
- Benchmark mode quando non viene passato alcun target.
- Generazione/caricamento tames con `-tames` e `-max`.
- Risoluzione multi-target con `-targets`.
- Loader target per public key secp256k1 compresse `02...` / `03...` e non compresse `04...`.
- Metadati target per ogni distinguished point, cosi' la collisione risolta viene verificata contro il target corretto.
- Oracle CPU macOS per tiny-range, test di correttezza e benchmark locali.
- Backend Metal smoke e microkernel field-add/field-sub/field-double/field-neg/field-mul/field-square per verificare il runtime Apple Silicon.
- Runner autoresearch per esperimenti con gate fissi e risultati misurabili.

## Requisiti

Il solver completo ad alte prestazioni richiede NVIDIA CUDA. Linux e Windows con CUDA sono i target runtime previsti per il motore kangaroo originale.

Apple Silicon/macOS non puo eseguire kernel CUDA sulla GPU Apple. Questa repo ora include un percorso separato per preparazione target, correttezza host, tiny-range CPU, benchmark, smoke test Metal e autoresearch.

## Matrice backend

| Backend | Stato | Scopo |
|---|---|---|
| CUDA | Solver completo | Motore kangaroo CUDA originale con aggiunte multi-target. |
| macOS CPU | Funzionante | Oracle tiny-range, test secp256k1, benchmark baseline e microbenchmark `field_mul_mod_p`. |
| macOS Metal | Backend aritmetico iniziale | Compila ed esegue smoke Metal piu' microkernel `field_add_mod_p`, `field_sub_mod_p`, `field_double_mod_p`, `field_neg_mod_p`, `field_mul_mod_p` e `field_square_mod_p` quando un device Metal e' visibile. |
| Autoresearch | Funzionante | Esegue check e benchmark con gate fissi e registra righe keep/discard. |

## Build su Linux CUDA

Modifica `CUDA_PATH` nel `Makefile` se CUDA non si trova in `/usr/local/cuda-12.0`.

```sh
make
```

Check host-only, senza CUDA:

```sh
make check-host
```

## Parametri CLI

```text
-gpu      ID delle GPU da usare, per esempio "035" per GPU 0, 3 e 5.
-pubkey   Singola public key da risolvere. Supporta formato compresso e non compresso.
-targets  File di testo con una public key per riga per la modalita multi-target.
-start    Offset iniziale dell'intervallo, in hex.
-range    Range della private key in bit. Deve essere 32...170 nel parser CLI.
-dp       Bit dei distinguished point. Deve essere 14...60.
-max      Stop dopo max * 1.15 * sqrt(range) operazioni.
-tames    Carica o genera un file tames.
```

`-pubkey` e `-targets` sono alternativi. Entrambi richiedono `-start`, `-range` e `-dp`.

## Esempio single-target

```sh
./rckangaroo -dp 16 -range 84 -start 1000000000000000000000 -pubkey 0329c4574a4fd8c810b7e42a4b398882b381bcd85e40c6883712912d167c83e73a
```

## Esempio multi-target

Prepara un file con una public key per riga:

```text
# commenti e righe vuote sono consentiti
0279BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798
0379BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798
```

Avvia:

```sh
./rckangaroo -dp 16 -range 84 -start 1000000000000000000000 -targets targets.cleaned.txt
```

L'output iniziale include:

```text
Loading multi-target public keys from targets.cleaned.txt...
Successfully loaded N targets into memory.

Initializing Multi-Target Math Architecture...
Successfully mapped N targets against the Base Point.
```

Quando viene trovata una chiave, il solver stampa e aggiunge a `RESULTS.TXT`:

```text
TARGET INDEX
TARGET SOURCE LINE
X
Y
PRIVATE KEY
```

## Note multi-target

Il loader sottrae da ogni target l'offset `-start`. Le wild kangaroo partono poi da punti specifici per target e portano un `target_id` fino all'output GPU dei distinguished point. Le tame kangaroo restano universali, quindi una tame DP puo risolvere una collisione per qualunque target wild. La modalita attuale si ferma al primo target risolto.

Con file target molto grandi, tutti i target vengono caricati e indicizzati, ma la densita wild effettiva per target dipende dal numero di GPU e dal numero di kangaroo. Piu GPU aumentano la popolazione wild attiva.

I file tames originali v3.1 restano utilizzabili nel flusso single-target normale. In modalita multi-target usa tames generati da questo fork e generali separatamente prima di usare `-targets`.

## Workflow companion macOS

Valida e normalizza una lista target su macOS:

```sh
python3 macos/prepare_targets.py stripped.txt -o targets.cleaned.txt
```

Build e test del percorso nativo macOS:

```sh
make macos-check
make macos-bench
./macos/rck_macos metal-smoke
./macos/rck_macos metal-field-test
./macos/rck_macos metal-field-sub-test
./macos/rck_macos metal-field-double-test
./macos/rck_macos metal-field-neg-test
./macos/rck_macos metal-field-mul-test
./macos/rck_macos metal-field-square-test
python3 autoresearch/runner.py --experiment baseline --budget-sec 5
python3 autoresearch/runner.py --experiment metal_field_sub --budget-sec 5
python3 autoresearch/runner.py --experiment metal_field_double --budget-sec 5
python3 autoresearch/runner.py --experiment metal_field_neg --budget-sec 5
python3 autoresearch/runner.py --experiment metal_field_square --budget-sec 5
```

Dettagli:

- English: `macos/README.md`
- Italiano: `macos/README.it.md`

## Limiti

Questo resta un solver GPU in stile proof-of-concept. Non aggiunge networking, coordinamento distribuito, checkpoint completi di tutte le DP o un backend kangaroo Apple GPU completo, ancora.

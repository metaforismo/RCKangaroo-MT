# RCKangaroo-MT

RCKangaroo-MT e' un fork GPLv3 di `RCKangaroo v3.1` di RetiredCoder, basato sull'implementazione CUDA del metodo SOTA Kangaroo per ECDLP su secp256k1.

Progetto upstream: https://github.com/RetiredC/RCKangaroo  
Raccolta RetiredCoder: https://github.com/RetiredC  
Thread di discussione: https://bitcointalk.org/index.php?topic=5517607

Questo fork mantiene single-target, benchmark e tames del progetto originale, e aggiunge una modalita multi-target sperimentale piu strumenti companion per macOS.

## Funzionalita

- Implementazione CUDA SOTA Kangaroo originale di RCKangaroo v3.1.
- Risoluzione single-target con `-pubkey`.
- Benchmark mode quando non viene passato alcun target.
- Generazione/caricamento tames con `-tames` e `-max`.
- Risoluzione multi-target con `-targets`.
- Loader target per public key secp256k1 compresse `02...` / `03...` e non compresse `04...`.
- Metadati target per ogni distinguished point, cosi' la collisione risolta viene verificata contro il target corretto.
- Script macOS per validare e normalizzare liste target.

## Requisiti

Il solver richiede NVIDIA CUDA. Linux e Windows con CUDA sono i target runtime previsti.

Apple Silicon/macOS non puo eseguire il solver CUDA sulla GPU Apple. Usa gli strumenti in `macos/` per preparare i target su Mac, poi esegui il solver su una macchina CUDA.

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

Dettagli:

- English: `macos/README.md`
- Italiano: `macos/README.it.md`

## Limiti

Questo resta un solver GPU in stile proof-of-concept. Non aggiunge networking, coordinamento distribuito, checkpoint completi di tutte le DP o backend Apple GPU.

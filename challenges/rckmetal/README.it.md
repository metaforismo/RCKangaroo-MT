# RCKangaroo-MT Metal Lab

Questo e' un challenge pack Benchforge per il percorso macOS/Metal.

La root della challenge e' la root della repository, non questa cartella. E'
voluto: la verifica Benchforge copia la challenge root in una directory pulita,
quindi deve includere i sorgenti reali del solver.

## Obiettivo

Massimizzare `ops_per_sec` per:

```bash
./macos/rck_macos metal-jacobian-jump-walk-bench \
  --iterations 16384 \
  --steps 8 \
  --jumps 16 \
  --dp-bits 4 \
  --min-ms 50
```

Lo score harness esegue tre sample e registra la mediana. Un run e' valido solo
se il benchmark Metal riporta `correctness:true`, `skipped:false`, il checksum
distanza atteso e il checksum DP proiettivo atteso.

## Comandi

Inizializza Benchforge se serve:

```bash
git submodule update --init tools/benchforge
```

Loop locale:

```bash
make benchforge-rckmetal-doctor
make benchforge-rckmetal-run
make benchforge-rckmetal-submit
make benchforge-rckmetal-leaderboard
make benchforge-rckmetal-report
```

CLI diretta equivalente:

```bash
node ./challenges/rckmetal/bin/rckmetal.js doctor --run
node ./challenges/rckmetal/bin/rckmetal.js run
node ./challenges/rckmetal/bin/rckmetal.js submit --verify --bundle-output .benchforge/latest.bundle.json --output .benchforge/verifier-result.json
node ./challenges/rckmetal/bin/rckmetal.js leaderboard
node ./challenges/rckmetal/bin/rckmetal.js export-site
```

Il report statico viene scritto in:

```text
.benchforge/site/index.html
.benchforge/site/leaderboard.json
```

## Trust

I run locali servono per iterare, non sono prova pubblica.

Nomi status Benchforge:

- `local`: misurato sulla macchina del contributor.
- `candidate`: impacchettato come bundle riproducibile
  `benchforge.submission.v1`.
- `accepted`: riprodotto dal verifier locale.
- `verified`, `promoted`, `replicated`: riservati a runner esterni fidati.

Per promuovere un risultato serve un verifier indipendente su un track hardware
dichiarato. Il primo track di questa repo e' Apple Silicon M3 Metal.

## Note

Usa le note per non perdere esperimenti:

```bash
node ./challenges/rckmetal/bin/rckmetal.js notes add "Tried <idea>; result <summary>."
node ./challenges/rckmetal/bin/rckmetal.js notes search "Metal"
```

Le note locali in `.benchforge/` sono scratchpad. Le scoperte da condividere
vanno in `challenges/rckmetal/NOTES.md` o `docs/RESEARCH_LOG.md`.

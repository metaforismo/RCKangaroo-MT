# Gate Di Qualita

Questo progetto ottimizza componenti kangaroo CUDA, CPU e Metal solo se correttezza e riproducibilita restano intatte. Ogni ottimizzazione e una candidata finche non supera i gate sotto.

## Checklist Obbligatoria

- target: dichiarare path, comando, benchmark e piattaforma esatti che si stanno cambiando.
- allowed edits: tenere gli edit dentro il target; non mischiare refactor, documentazione o log generati non collegati al cambio prestazionale.
- correctness oracle: dichiarare l'oracle prima di editare. Esempi: `make macos-check`, oracle scalare CPU, riferimento EcInt, oracle CPU per Metal, fixture target/private-key note.
- performance metric: dichiarare la metrica prima di editare. Esempi: `ops_per_sec`, `paired_speedup`, `correctness`, `avg_dp_count`, `last_dp_count`.
- baseline gate: confrontare contro `main` con baseline paired quando la ragione del cambio e la performance. Una candidata sotto soglia si scarta.
- hidden tests: assumere che test non visibili coprano forma CLI, marker JSON, parsing target, comportamento skip ed edge case. Non rompere i contratti di output pubblici.
- reproducibility: registrare comando, branch, commit, hardware/runtime, argomenti, e se Metal/CUDA era accessibile in sandbox o in modo nativo.
- logging: appendere log ufficiali `autoresearch` solo per risultati accettati. Rimuovere le righe candidate scartate dai file append-only prima di lasciare la branch.
- submission: fare commit solo dopo source check, CLI check e benchmark gate rilevanti. Merge fast-forward su `main`, rilanciare la suite richiesta su `main`, poi push.
- rollback: se la correttezza fallisce, la performance regredisce, i contratti di output cambiano senza motivo, o l'evidenza e rumorosa, non fare merge. Lasciare il worktree fallito isolato o cancellarlo solo durante cleanup esplicito.

## Regole Mac Metal

- Il MacBook Air M3 ha una GPU Apple esposta via Metal, non CUDA.
- Una sandbox puo nascondere il device Metal. Trattare `no Metal device available` come skip runtime, poi rilanciare i benchmark GPU con accesso Metal nativo prima di fare affermazioni sulla GPU.
- I cambi ai kernel Metal devono preservare oracle CPU e comportamento skip.
- Il throughput GPU da solo non basta: correctness, schema output, comandi riproducibili e log stabili fanno parte del risultato.

## Evidenza Accettata

- `make macos-check`
- Source check mirati per il sottosistema editato
- CLI check mirati per comandi o marker JSON cambiati
- `python3 autoresearch/runner.py --experiment <name> --budget-sec 5 --paired-baseline-ref main` per candidate prestazionali
- Output benchmark Metal nativo quando il target e un kernel Metal

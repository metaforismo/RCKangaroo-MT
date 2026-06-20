# Strumenti nativi per macOS

RCKangaroo-MT usa ancora NVIDIA CUDA per il solver kangaroo completo ad alte prestazioni, ma la cartella `macos/` ora contiene strumenti nativi Apple Silicon per preparazione target, check secp256k1, solve CPU tiny-range, aritmetica di campo CPU, benchmark, smoke test Metal e prime primitive aritmetiche Metal.

## Build e check

```sh
make macos-check
```

Questo compila `macos/rck_macos`, esegue vettori secp256k1 host, valida il parsing target, lancia il selftest CPU nativo, controlla l'aritmetica di campo CPU e prova i check Metal field-add/sub/double/mul4/neg/mul/square quando Metal e' visibile.

La build macOS usa `-O3` piu' ThinLTO (`MACOS_LTO_FLAGS=-flto=thin`) di default. ThinLTO permette a clang di ottimizzare il call graph Jacobian e field secp256k1 tra translation unit, utile soprattutto per il fallback CPU su Apple Silicon. Puoi fare override o disattivarlo quando serve:

```sh
make macos-check MACOS_CXXFLAGS="-std=c++17 -O0 -g -I."
make macos-check MACOS_LTO_FLAGS=
```

Esempio tiny-range CPU:

```sh
./macos/rck_macos solve-small --range 8 --start 0 --pubkey 025CBDF0646E5DB4EAA398F365F2EA7A0E3D419B7E0330E39CE92BDDEDCAC4F9BC
./macos/rck_macos jacobian-kangaroo-small --range 8 --start 0 --pubkey 025CBDF0646E5DB4EAA398F365F2EA7A0E3D419B7E0330E39CE92BDDEDCAC4F9BC --jumps 8 --dp-bits 0 --max-steps 4096
./macos/rck_macos jacobian-kangaroo-multi-small --range 8 --start 2 --targets tests/jacobian_kangaroo_multi_targets.txt --jumps 8 --dp-bits 0 --max-steps 4096
```

`jacobian-kangaroo-small` e' un solver bounded toy per range minuscoli. Esegue walk tame/wild con jump table deterministica, mantiene gli stati in coordinate Jacobian, passa RHS field e punti step Jacobian per riferimento const (`field_rhs_passing=const_ref`, `jacobian_step_passing=const_ref`), converte in batch la coppia tame/wild ad affine con una sola inversione di campo per loop (`affine_conversion=batch`), registra distinguished points in una tabella open-addressed riusabile su chiave punto compressa (`dp_lookup=open_address_linear`, `dp_hash=partial_limb_mix`, `dp_key=x_parity`) con una stima reserve sqrt-range (`dp_reserve=sqrt_range_estimate`), target di capacita' a load massimo due terzi (`dp_capacity=max_load_2of3`), primo DP inline in ogni bucket (`dp_bucket_storage=inline_first`) e clear degli overflow vuoti evitato (`dp_clear=empty_guard`), evita copie inutili dei punti nei check caldi (`point_passing=const_ref`), riporta la dimensione della tabella DP come `dp_count` e prova i candidati da collisione tramite equality completa del punto affine cross-side piu' range check (`candidate_verification=full_point_collision`). Serve per correttezza ed esperimenti architetturali; non e' il motore kangaroo CUDA/Metal completo.

`jacobian-kangaroo-multi-small` carica un file target con il parser condiviso ed esegue un tame walk bounded piu' un wild walk per target nello stesso loop kangaroo Jacobian. La tabella dei distinguished point tame e' condivisa fra tutti i wild target e indicizzata con una tabella linear-probing riusabile (`dp_lookup=open_address_linear`, `dp_hash=partial_limb_mix`, `dp_key=x_parity`, `dp_reserve=sqrt_range_estimate`, `dp_capacity=max_load_2of3`, `dp_bucket_storage=inline_first`, `dp_clear=empty_guard`), così i collision check scandiscono solo i DP con la stessa chiave punto compressa e il caso comune con un solo DP per chiave evita allocazioni vector per-record. L'hash miscela pochi limb del punto per scegliere il probe iniziale, mentre l'equality `x+parity(y)` resta identita' affine esatta. Una collisione cross-side sul punto completo prova il candidato dopo range check e target-index check (`candidate_verification=full_point_collision`), quindi il tiny solver caldo non riesegue `MultiplyG` dopo ogni collisione risolta. La stima reserve usa sqrt(range) e `dp_bits`, evitando tabelle grandi e quasi vuote quando `max_steps` e' molto piu' grande del tiny range; la tabella punta a un load massimo piu' denso di due terzi e fa comunque rehash se servono piu' slot. Gli argomenti punto caldi, RHS field, punti step Jacobian e letture dal vettore affine usano riferimenti const (`point_passing=const_ref`, `field_rhs_passing=const_ref`, `jacobian_step_passing=const_ref`, `affine_z_access=const_ref`). Il batch affine usa il flag infinity mantenuto dagli stati Jacobian per la validita' di Z (`affine_z_check=infinity_flag`), usa moltiplicazioni field in-place per prefix e conversione coordinate (`affine_field_ops=inplace`), riusa i buffer, usa un fast path all-active, gestisce l'indice zero fuori dal reverse loop all-active (`affine_reverse_loop=split_zero`) e salta l'update finale inutilizzato nella reverse pass (`affine_buffer=resize_reuse`, `affine_active_path=all_active_fast`, `affine_tail_update=skip_final`). La CLI riporta conteggio target, stati tame/wild attivi e dimensione della tabella DP. Resta codice CPU tiny-range per correttezza ed esperimenti architetturali; non e' il motore CUDA/Metal completo.

Benchmark CPU:

```sh
make macos-bench
make macos-point-bench
./macos/rck_macos point-bench --iterations 256 --min-ms 50
make macos-jacobian-point-bench
./macos/rck_macos jacobian-point-bench --iterations 256 --min-ms 50
make macos-jacobian-batch-affine-bench
./macos/rck_macos jacobian-batch-affine-bench --iterations 256 --min-ms 50 --points 17
make macos-jacobian-walk-bench
./macos/rck_macos jacobian-walk-bench --iterations 256 --min-ms 50 --jumps 16
make macos-jacobian-kangaroo-small-bench
./macos/rck_macos jacobian-kangaroo-small-bench --iterations 1 --min-ms 50 --range 8 --jumps 8 --dp-bits 0 --max-steps 4096
make macos-jacobian-kangaroo-multi-small-bench
./macos/rck_macos jacobian-kangaroo-multi-small-bench --target-count 4 --iterations 1 --min-ms 50 --range 8 --jumps 8 --dp-bits 0 --max-steps 4096
make macos-jacobian-kangaroo-multi16-small-bench
./macos/rck_macos jacobian-kangaroo-multi-small-bench --target-count 16 --iterations 1 --min-ms 50 --range 8 --jumps 8 --dp-bits 0 --max-steps 4096
```

`macos-bench` misura il throughput dello scalar `MultiplyG`. `macos-point-bench` misura un walk seriale di addizioni affini: parte da `2G`, aggiunge ripetutamente `G`, e valida il punto finale con un oracle `MultiplyG(n+2)`. E' ancora aritmetica CPU affine, non il percorso solver Metal/Jacobian finale, ma rappresenta meglio il costo del kangaroo walk rispetto alle sole operazioni field isolate.

`macos-jacobian-point-bench` mantiene il punto del walk in coordinate Jacobian ed esegue addizioni mixed Jacobian-piu'-affine di `G`, spostando la costosa inversione di campo fuori dal loop interno. Il JSON include throughput affine di riferimento e `speedup_vs_affine`, così il miglioramento e' misurato contro il baseline point-add piu' semplice.

`macos-jacobian-batch-affine-bench` isola il percorso batch inversion usato dal solver multi-target shared-tame. Costruisce un punto tame Jacobian piu' punti wild Jacobian configurabili, converte l'intero batch ad affine con una sola inversione di campo per iterazione, valida ogni punto affine contro riferimenti scalari, riporta `field_rhs_passing=const_ref`, `affine_z_access=const_ref`, `affine_z_check=infinity_flag`, `affine_field_ops=inplace`, `affine_buffer=resize_reuse`, `affine_active_path=all_active_fast`, `affine_reverse_loop=split_zero` e `affine_tail_update=skip_final`, e riporta conversioni batch al secondo piu' punti affini al secondo.

`macos-jacobian-walk-bench` usa una jump table deterministica di punti affini e applica addizioni mixed Jacobian selezionate dallo stato proiettivo corrente. Passa il punto step proiettivo per riferimento const (`jacobian_step_passing=const_ref`) e riporta `ecint_carry_impl` piu' `ecint_mul_final_sub`, così i cambi alle catene carry e alla riduzione finale nel percorso `EcInt` condiviso sono visibili nel JSON. Per jump count potenze di due seleziona i jump con una maschera bitwise invece del modulo intero (`jump_index=power2_mask`, fallback `modulo` negli altri casi). Traccia in parallelo la distanza scalare e valida il punto finale con un oracle scalare. E' un benchmark del core della walk, non ancora un solver kangaroo completo con distinguished points o collision handling.

`macos-jacobian-kangaroo-small-bench` genera un target sintetico deterministico e misura solve tiny single-target kangaroo al secondo con lookup DP open-addressed. Precalcola la jump table deterministica e il contesto range/tame-start una volta per run benchmark, riusa scratch storage tra solve misurati e riporta `architecture=single_target`, `field_rhs_passing=const_ref`, `jacobian_step_passing=const_ref`, `ecint_carry_impl`, `ecint_mul_final_sub`, `dp_lookup=open_address_linear`, `dp_hash=partial_limb_mix`, `dp_key=x_parity`, `candidate_verification=full_point_collision`, `dp_reserve=sqrt_range_estimate`, `dp_capacity=max_load_2of3`, `dp_bucket_storage=inline_first`, `dp_clear=empty_guard`, `point_passing=const_ref`, `affine_conversion=batch`, `jump_index`, `jump_table=precomputed`, `scratch=reused`, `range_context=precomputed`, conteggio stati tame/wild e dimensione della tabella DP, così si puo' confrontare direttamente con il benchmark multi-target shared-tame.

`macos-jacobian-kangaroo-multi-small-bench` genera target sintetici deterministici, mette un target risolvibile all'ultimo indice, precalcola la jump table deterministica e il contesto range/tame-start una volta per run benchmark, riusa scratch storage tra solve misurati e misura solve tiny multi-target shared-tame al secondo con lookup DP open-addressed. Il solver multi riporta `affine_conversion=batch` perche' converte in batch lo stato tame piu' gli stati wild Jacobian con una sola inversione di campo per loop, e il benchmark riporta `field_rhs_passing=const_ref`, `jacobian_step_passing=const_ref`, `ecint_carry_impl`, `ecint_mul_final_sub`, `dp_lookup=open_address_linear`, `dp_hash=partial_limb_mix`, `dp_key=x_parity`, `candidate_verification=full_point_collision`, `dp_reserve=sqrt_range_estimate`, `dp_capacity=max_load_2of3`, `dp_bucket_storage=inline_first`, `dp_clear=empty_guard`, `point_passing=const_ref`, `affine_z_access=const_ref`, `affine_z_check=infinity_flag`, `affine_field_ops=inplace`, `affine_buffer=resize_reuse`, `affine_active_path=all_active_fast`, `affine_reverse_loop=split_zero`, `affine_tail_update=skip_final`, `jump_index`, `jump_table=precomputed`, `scratch=reused` e `range_context=precomputed`. Esegue anche un baseline single-target con gli stessi parametri e riporta `single_target_ops_per_sec`, `speedup_vs_single` e `target_throughput_vs_single`; l'ultimo campo moltiplica i solve multi al secondo per il numero di target prima del confronto con il baseline single-target. Usa `--target-count` per confrontare 1, 2, 4, 8 o piu' target mantenendo range bounded e parametri jump uguali. Il Makefile espone anche `macos-jacobian-kangaroo-multi16-small-bench` e il relativo esperimento autoresearch per tracciare separatamente il comportamento a 16 target rispetto al gate default a 4 target.

Check e benchmark CPU per l'aritmetica nel campo secp256k1:

```sh
./macos/rck_macos cpu-field-test
make macos-cpu-field-bench
./macos/rck_macos cpu-field-bench --iterations 4096 --min-ms 50
```

Il percorso CPU field usa quattro limb little-endian da 64 bit. Su Apple Clang, le catene carry/borrow usano `__builtin_addcll` e `__builtin_subcll`; sugli altri compilatori resta il fallback portabile `unsigned __int128`. Il benchmark riporta throughput `field_mul_mod_p`, `carry_impl`, `ecint_mul_final_sub` e throughput reference `EcInt` per confronto. I wrapper `EcInt` condivisi usati dai percorsi Jacobian walk e kangaroo riportano invece il proprio modo come `ecint_carry_impl`. `--iterations` controlla la dimensione del sample deterministico; `--min-ms` ripete quel sample finche' la misura nativa dura almeno quei millisecondi, così autoresearch riceve dati meno rumorosi.

Smoke test Metal:

```sh
./macos/rck_macos metal-smoke
```

Se nell'ambiente corrente non e' visibile un device Metal, il comando segnala uno skip invece di fallire. Su un runtime Apple Silicon normale con accesso al device, compila ed esegue un kernel Metal minimo.

Check e benchmark Metal per addizione, sottrazione, doubling, moltiplicazione per 4, negazione, moltiplicazione e quadrato nel campo secp256k1:

```sh
./macos/rck_macos metal-field-test
make macos-metal-field-bench
./macos/rck_macos metal-field-sub-test
make macos-metal-field-sub-bench
./macos/rck_macos metal-field-double-test
make macos-metal-field-double-bench
./macos/rck_macos metal-field-mul4-test
make macos-metal-field-mul4-bench
./macos/rck_macos metal-field-neg-test
make macos-metal-field-neg-bench
./macos/rck_macos metal-field-mul-test
make macos-metal-field-mul-bench
./macos/rck_macos metal-field-square-test
make macos-metal-field-square-bench
make macos-metal-kernels-check
```

I kernel field usano quattro limb little-endian da 64 bit modulo il primo secp256k1 e confrontano l'output Metal con oracle CPU. `field_sub_mod_p` gestisce l'underflow modulare aggiungendo il primo secp256k1 dopo una sottrazione con borrow. `field_double_mod_p` calcola il doubling modulare con un solo input load e la stessa riduzione condizionale dell'addizione, dando alle formule Jacobian un percorso piu' economico per i termini espliciti `2*x`. `field_mul4_mod_p` calcola `4*x mod p` applicando due volte nello stesso kernel la helper di doubling, evitando due dispatch separati per le formule con termini espliciti `4*x`. `field_neg_mod_p` calcola la negazione modulare canonica, mantenendo zero come zero e usando `p - x` per input non nulli. `field_mul_mod_p` usa decomposizione a 32 bit per moltiplicazione 64x64 portabile dentro Metal; `field_square_mod_p` ora usa un accumulatore simmetrico con 10 prodotti limb prima del riduttore condiviso, in linea con le formule Jacobian che fanno molti quadrati di campo. In CI o sessioni sandbox senza device Metal visibile, i check runtime segnalano uno skip pulito. `macos-metal-kernels-check` compila il source Metal estratto quando il Metal Toolchain e' installato; altrimenti segnala uno skip pulito del toolchain.

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
python3 autoresearch/runner.py --experiment jacobian_kangaroo_multi_small --budget-sec 5
python3 autoresearch/runner.py --experiment cpu_field_mul --budget-sec 5
python3 autoresearch/runner.py --experiment metal_field_add --budget-sec 5
python3 autoresearch/runner.py --experiment metal_field_sub --budget-sec 5
python3 autoresearch/runner.py --experiment metal_field_double --budget-sec 5
python3 autoresearch/runner.py --experiment metal_field_mul4 --budget-sec 5
python3 autoresearch/runner.py --experiment metal_field_neg --budget-sec 5
python3 autoresearch/runner.py --experiment metal_field_mul --budget-sec 5
python3 autoresearch/runner.py --experiment metal_field_square --budget-sec 5
```

L'esperimento `jacobian_jump_walk` usa tre campioni del runner e registra throughput mediano/min/max, cosi i confronti del walk-core sono meno sensibili ai picchi brevi dello scheduler macOS.

Autoresearch registra l'assenza del device Metal come `status=skip`, non come crash, quindi lo stesso esperimento puo' girare sia su Apple Silicon locale sia in CI/headless.

Se vuoi generare tames per il solver completo, fallo sulla macchina CUDA. Con la modalita multi-target il file tames deve gia esistere; generalo separatamente prima di usare `-targets`.

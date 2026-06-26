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

Entrambi i tiny solver kangaroo riportano `affine_initial_conversion=unit_z_copy`. Al passo zero del solver gli stati tame e wild Jacobian sono appena creati da punti affini, quindi la coordinata `Z` e' esattamente uno e la prima vista affine puo' copiare `x/y` senza inversione di campo. Dai passi successivi resta `affine_conversion=batch`; predicato DP, verifica collisioni, range check, target-index check e sequenza di jump non cambiano.

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
./macos/rck_macos jacobian-kangaroo-multi-small-bench --target-count 16 --iterations 1 --min-ms 50 --range 20 --jumps 4 --dp-bits 4 --max-steps 500000 --jump-schedule scaled4-balanced
./macos/rck_macos jacobian-kangaroo-multi-small-bench --target-count 16 --iterations 1 --min-ms 0 --range 20 --jumps 4 --dp-bits 4 --max-steps 2000000 --jump-schedule scaled4-balanced --key-offset 524288
```

`macos-bench` misura il throughput dello scalar `MultiplyG`. `macos-point-bench` misura un walk seriale di addizioni affini: parte da `2G`, aggiunge ripetutamente `G`, e valida il punto finale con un oracle `MultiplyG(n+2)`. E' ancora aritmetica CPU affine, non il percorso solver Metal/Jacobian finale, ma rappresenta meglio il costo del kangaroo walk rispetto alle sole operazioni field isolate.

`macos-jacobian-point-bench` mantiene il punto del walk in coordinate Jacobian ed esegue addizioni mixed Jacobian-piu'-affine di `G`, spostando la costosa inversione di campo fuori dal loop interno. Il JSON include throughput affine di riferimento e `speedup_vs_affine`, così il miglioramento e' misurato contro il baseline point-add piu' semplice.

`macos-jacobian-batch-affine-bench` isola il percorso batch inversion usato dal solver multi-target shared-tame. Costruisce un punto tame Jacobian piu' punti wild Jacobian configurabili, converte l'intero batch ad affine con una sola inversione di campo per iterazione, valida ogni punto affine contro riferimenti scalari, riporta `field_rhs_passing=const_ref`, `affine_z_access=const_ref`, `affine_z_check=infinity_flag`, `affine_field_ops=inplace`, `affine_buffer=resize_reuse`, `affine_active_path=all_active_fast`, `affine_reverse_loop=split_zero` e `affine_tail_update=skip_final`, e riporta conversioni batch al secondo piu' punti affini al secondo.

`macos-jacobian-walk-bench` usa una jump table deterministica di punti affini e applica addizioni mixed Jacobian selezionate dallo stato proiettivo corrente. Passa il punto step proiettivo per riferimento const (`jacobian_step_passing=const_ref`) e riporta `ecint_carry_impl` piu' `ecint_mul_final_sub`, così i cambi alle catene carry e alla riduzione finale nel percorso `EcInt` condiviso sono visibili nel JSON. Per jump count potenze di due seleziona i jump con una maschera bitwise invece del modulo intero (`jump_index=power2_mask`, fallback `modulo` negli altri casi). Traccia in parallelo la distanza scalare e valida il punto finale con un oracle scalare. E' un benchmark del core della walk, non ancora un solver kangaroo completo con distinguished points o collision handling.

`macos-jacobian-kangaroo-small-bench` genera un target sintetico deterministico e misura solve tiny single-target kangaroo al secondo con lookup DP open-addressed. Precalcola la jump table deterministica e il contesto range/tame-start una volta per run benchmark, riusa scratch storage tra solve misurati e riporta `architecture=single_target`, `field_rhs_passing=const_ref`, `jacobian_step_passing=const_ref`, `ecint_carry_impl`, `ecint_mul_final_sub`, `dp_lookup=open_address_linear`, `dp_hash=partial_limb_mix`, `dp_key=x_parity`, `candidate_verification=full_point_collision`, `dp_reserve=sqrt_range_estimate`, `dp_capacity=max_load_2of3`, `dp_bucket_storage=inline_first`, `dp_clear=empty_guard`, `point_passing=const_ref`, `affine_conversion=batch`, `affine_initial_conversion=unit_z_copy`, `jump_index`, `jump_table=precomputed`, `scratch=reused`, `range_context=precomputed`, conteggio stati tame/wild e dimensione della tabella DP, così si puo' confrontare direttamente con il benchmark multi-target shared-tame.

`macos-jacobian-kangaroo-multi-small-bench` genera target sintetici deterministici, mette un target risolvibile all'ultimo indice, precalcola la jump table deterministica e il contesto range/tame-start una volta per run benchmark, riusa scratch storage tra solve misurati e misura solve tiny multi-target shared-tame al secondo con lookup DP open-addressed. Il solver multi riporta `affine_conversion=batch` perche' converte in batch lo stato tame piu' gli stati wild Jacobian con una sola inversione di campo per loop dopo il fast path del passo zero `affine_initial_conversion=unit_z_copy`, e il benchmark riporta `field_rhs_passing=const_ref`, `jacobian_step_passing=const_ref`, `ecint_carry_impl`, `ecint_mul_final_sub`, `dp_lookup=open_address_linear`, `dp_hash=partial_limb_mix`, `dp_key=x_parity`, `candidate_verification=full_point_collision`, `dp_reserve=sqrt_range_estimate`, `dp_capacity=max_load_2of3`, `dp_bucket_storage=inline_first`, `dp_clear=empty_guard`, `point_passing=const_ref`, `affine_z_access=const_ref`, `affine_z_check=infinity_flag`, `affine_field_ops=inplace`, `affine_buffer=resize_reuse`, `affine_active_path=all_active_fast`, `affine_reverse_loop=split_zero`, `affine_tail_update=skip_final`, `jump_index`, `jump_table=precomputed`, `scratch=reused` e `range_context=precomputed`. Esegue anche un baseline single-target con gli stessi parametri e riporta `single_target_ops_per_sec`, `speedup_vs_single` e `target_throughput_vs_single`; l'ultimo campo moltiplica i solve multi al secondo per il numero di target prima del confronto con il baseline single-target. Usa `--target-count` per confrontare 1, 2, 4, 8 o piu' target mantenendo range bounded e parametri jump uguali. Il Makefile espone anche `macos-jacobian-kangaroo-multi16-small-bench` e il relativo esperimento autoresearch per tracciare separatamente il comportamento a 16 target rispetto al gate default a 4 target.

I benchmark kangaroo CPU accettano `--jump-schedule power2` di default. La modalita' sperimentale `--jump-schedule scaled4-balanced` e' valida solo con `--jumps 4` e usa le distanze `{1, 2, 8192, 8193}`. Mantiene gcd `1` e una media di avanzamento scalare vicina alla schedule power-of-two a 16 entry, quindi e' un probe matematico lato solver, non solo una micro-ottimizzazione raw per step.

Gli stessi benchmark accettano anche `--key-offset N` per posizionare la chiave sintetica risolvibile a un offset scelto dentro il range bounded. Senza questa opzione restano i fixture storici (`0x7` nel single-target e `start + 5` nel multi-target). Il JSON riporta il `key_offset` effettivo dopo clamp, utile per sweep su posizioni basse, centrali e alte dell'intervallo.

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

Check e benchmark Metal per addizione, sottrazione, doubling, moltiplicazione per 4, negazione, moltiplicazione, quadrato e square-mul fuso nel campo secp256k1:

```sh
./macos/rck_macos metal-field-test
make macos-metal-field-bench
make macos-metal-target-lookup-bench
./macos/rck_macos metal-target-lookup-bench --target-count 1048576 --query-count 1048576 --hits 4096 --min-ms 500
make macos-metal-target-lookup-compact-bench
./macos/rck_macos metal-target-lookup-compact-bench --target-count 1048576 --query-count 1048576 --hits 4096 --min-ms 500
make macos-metal-target-lookup-tag32-bench
./macos/rck_macos metal-target-lookup-tag32-bench --target-count 1048576 --query-count 1048576 --hits 4096 --min-ms 500
make macos-metal-target-lookup-tag32-filter-bench
./macos/rck_macos metal-target-lookup-tag32-filter-bench --target-count 25005000 --query-count 1082368 --hits 64 --min-ms 500
make macos-metal-target-lookup-tag32-filter-persistent-bench
./macos/rck_macos metal-target-lookup-tag32-filter-persistent-bench --target-count 25005000 --query-count 1082368 --hits 64 --min-ms 700
make macos-metal-target-lookup-tag16-filter-persistent-bench
./macos/rck_macos metal-target-lookup-tag16-filter-persistent-bench --target-count 25005000 --query-count 1082368 --hits 64 --min-ms 700
make macos-metal-target-lookup-tag16-hash-filter-persistent-bench
./macos/rck_macos metal-target-lookup-tag16-hash-filter-persistent-bench --target-count 25005000 --query-count 1082368 --hits 64 --min-ms 700
make macos-metal-target-lookup-tag32-persistent-bench
./macos/rck_macos metal-target-lookup-tag32-persistent-bench --target-count 1048576 --query-count 1048576 --hits 4096 --min-ms 500
./macos/rck_macos metal-target-lookup-tag32-persistent-bench --target-count 25005000 --query-count 1082368 --hits 64 --min-ms 700
./macos/rck_macos target-lookup-tag32-cpu-bench --target-count 25005000 --query-count 1057 --hits 64 --min-ms 50
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
./macos/rck_macos metal-field-square-mul-test
make macos-metal-field-square-mul-bench
./macos/rck_macos metal-jacobian-add-test
make macos-metal-jacobian-add-bench
./macos/rck_macos metal-jacobian-walk-test
make macos-metal-jacobian-walk-bench
./macos/rck_macos metal-jacobian-jump-walk-test
make macos-metal-jacobian-jump-walk-bench
make macos-metal-jacobian-jump-walk-dp-bench
./macos/rck_macos metal-jacobian-dynamic-walk-test
make macos-metal-jacobian-dynamic-walk-bench
make macos-metal-jacobian-dynamic-walk-stable-bench
./macos/rck_macos metal-jacobian-dynamic-compact-dp-test
make macos-metal-jacobian-dynamic-compact-dp-bench
make macos-metal-jacobian-dynamic-compact-dp-stable-bench
./macos/rck_macos metal-jacobian-dynamic-dp-stream-test
make macos-metal-jacobian-dynamic-dp-stream-bench
make macos-metal-jacobian-dynamic-dp-stream-stable-bench
make macos-metal-jacobian-dynamic-dp-stream-dp8-stable-bench
make macos-metal-jacobian-dynamic-dp-stream-inplace-stable-bench
make macos-metal-jacobian-dynamic-dp-stream-inplace-steps16-stable-bench
make macos-metal-jacobian-dynamic-dp-stream-inplace-steps32-stable-bench
make macos-metal-jacobian-dynamic-dp-stream-inplace-steps64-stable-bench
make macos-metal-jacobian-dynamic-dp-stream-inplace-steps128-stable-bench
make macos-metal-jacobian-dynamic-dp-stream-inplace-steps256-stable-bench
make macos-metal-jacobian-dynamic-dp-stream-xyzz-steps256-stable-bench
make macos-metal-jacobian-dynamic-dp-stream-xyzz-steps512-stable-bench
make macos-metal-jacobian-dynamic-dp-stream-xyzz-chain-steps512-bench
make macos-metal-jacobian-dynamic-dp-count-dp8-stable-bench
make macos-metal-kernels-check
```

I kernel field usano quattro limb little-endian da 64 bit modulo il primo secp256k1 e confrontano l'output Metal con oracle CPU. `field_sub_mod_p` gestisce l'underflow modulare aggiungendo il primo secp256k1 dopo una sottrazione con borrow. `field_double_mod_p` calcola il doubling modulare con un solo input load e la stessa riduzione condizionale dell'addizione, dando alle formule Jacobian un percorso piu' economico per i termini espliciti `2*x`. `field_mul4_mod_p` calcola `4*x mod p` applicando due volte nello stesso kernel la helper di doubling, evitando due dispatch separati per le formule con termini espliciti `4*x`. `field_neg_mod_p` calcola la negazione modulare canonica, mantenendo zero come zero e usando `p - x` per input non nulli. `field_mul_mod_p` usa decomposizione a 32 bit per moltiplicazione 64x64 portabile dentro Metal; `field_square_mod_p` usa un accumulatore simmetrico con 10 prodotti limb prima del riduttore condiviso, in linea con le formule Jacobian che fanno molti quadrati di campo. `field_square_mul_mod_p` fonde `a*a*b mod p` in un solo dispatch e valida contro la stessa composizione oracle CPU, dando al futuro lavoro Jacobian su Metal un benchmark a overhead piu' basso per termini square/multiply adiacenti. `target_lookup_exact256` e' un gate di join multi-target esatto per candidati DP affini al confine packet: interroga una tabella open-addressed deterministica indicizzata da `x` affine completo piu' parita' di `y`, usa equality esatta della chiave per la verifica dei candidati, e riporta `lookup_layout=open_address_exact256`, `target_key=x256_y_parity`, `target_table_bytes`, `bytes_per_target`, `lookups_per_sec` e `target_lookup_checksum`. `target_lookup_compact_exact256` conserva la stessa verifica esatta `x256+y_parity`, ma nella tabella open-addressed salva hash a 64 bit piu' indice target e tiene le chiavi complete in un array separato; `target_lookup_tag32_exact256` salva solo un tag high-hash a 32 bit piu' indice target in ogni bucket, poi carica e confronta la chiave completa al match del tag. Il JSON riporta `target_key_bytes`, `target_bucket_bytes` e `bytes_per_target` ridotto per i layout compatti. Il target lookup usa di default un cap a 64 threadgroup su M3; un `--tg-limit N` esplicito lo sovrascrive per gli sweep. `jacobian_add_affine` e' la prima primitiva Metal a livello point: calcola batch di addizioni Jacobian-piu'-affine, emette un flag infinito insieme a `x/y/z`, copre il percorso generico piu' i rami `p` infinito, doubling e punto all'infinito, e valida ogni risultato contro l'oracle CPU della formula Jacobian. `jacobian_affine_walk_fixed` mantiene ogni stato Jacobian dentro un thread Metal per un numero fisso di passi mixed-add ripetuti, poi valida lo stato finale contro lo stesso loop oracle CPU; e' uno strato walk-core prima di jump table variabili e gestione DP. `jacobian_affine_walk_jump_table` mantiene lo stesso stato Jacobian nei registri ma legge un indice di salto deterministico, validato dall'host, per ogni campione e step, seleziona dalla tabella affine dei jump senza modulo nel loop del kernel, accumula la distanza scalare a 64 bit corrispondente, opzionalmente emette un flag DP candidato sui bit bassi di `x[0]` projective, e valida punto finale piu' distanza piu' flag contro un oracle CPU che riproduce la stessa sequenza di indici. Il flag DP e' un filtro candidato projective economico, non una chiave affine per collision table. La specializzazione Metal pubblica `steps=8`, `dp_bits=4` usa input packed a byte per i flag infinito e una vista struct-row binariamente compatibile della tabella affine dei jump, mentre le forme fallback generiche mantengono il formato host piu' largo e l'indicizzazione scalare della tabella. I dispatch Metal usano di default un threadgroup piu' grande, allineato alla SIMD width e limitato a 256 thread, invece di un solo execution-width group. I benchmark riportano `threadgroup_limit`, `thread_execution_width`, `max_threads_per_threadgroup` e `threads_per_threadgroup` per riproducibilita'. I benchmark Metal accettano `--min-ms`; il Makefile usa `--min-ms 50`, così l'overhead dei dispatch brevi viene smussato mentre il JSON riporta comunque `sample_count`, `min_ms`, `iterations` totali, `distance_checksum`, `dp_count`, `dp_checksum` e `ops_per_sec`. Usa `--tg-limit N` sui comandi bench Metal per provare un cap threadgroup alternativo senza cambiare il default. In CI o sessioni sandbox senza device Metal visibile, i check runtime segnalano uno skip pulito. `macos-metal-kernels-check` compila il source Metal estratto quando il Metal Toolchain e' installato; altrimenti segnala uno skip pulito del toolchain.

`jacobian_affine_walk_dynamic_jump_table` e' un'architettura Metal separata che calcola l'indice di salto kangaroo dentro il kernel dallo stato Jacobian corrente, usando lo stesso mixer `x/y/z` del percorso kangaroo CPU. Supporta sia mask power-of-two sia modulo, traccia distanza a 64 bit e candidati DP projective, e ha una specializzazione `steps=8`, `dp_bits=4` con flag infinito packed e accesso struct-row alla tabella dei jump. Questo percorso e' piu' vicino a un vero walk kangaroo GPU rispetto al benchmark sintetico con indici precomputati, ma viene riportato separatamente e non e' usato per il public score path DP precomputato.
Per jump count power-of-two, il percorso dinamico `steps=8`, `dp_bits=4` usa una specializzazione branchless con `jump_mask`. I jump count non power-of-two restano sul kernel dinamico generico, così il comportamento modulo resta coperto dallo stesso oracle CPU.
Il percorso DP8 stream in-place ha anche specializzazioni packet `steps=16`, `steps=32`, `steps=64`, `steps=128` e `steps=256`. Eseguono piu' salti dinamici per thread, salvano lo stato Jacobian aggiornato nel buffer di input, e validano sia lo stream DP sparso sia lo stato finale contro replay CPU. Queste modalita' sono utili per tuning di packet in walk GPU persistenti perche' ammortizzano load/store dello stato su piu' operazioni di gruppo; controllano il predicato DP solo al confine del packet. Il packet a 256 step e' un probe del plateau: i confronti paired locali battono 128 step, ma le mediane autoresearch grezze restano abbastanza vicine da richiedere una scelta deliberata della dimensione packet invece di assumere che il packet piu' grande sia sempre il piu' veloce. I packet DP8 in-place con `steps=16` o superiore usano di default un cap a 128 thread su M3 perche' i test paired hanno battuto il cap condiviso a 256 thread; `steps=8` mantiene il default condiviso, e un `--tg-limit N` esplicito continua a prevalere su entrambi.

`jacobian_affine_walk_dynamic_dp_stream_xyzz` e' un'architettura packet separata che conserva lo stato come `X,Y,ZZ,ZZZ` invece di `X,Y,Z`. Aggiorna `ZZ` e `ZZZ` direttamente nella formula mixed-add, evitando di ricomputare `Z^2` e `Z^3` a ogni passo, e valida sia lo stream DP sparso sia lo stato finale XYZZ contro un oracle CPU XYZZ. Poiche' lo stato non conserva piu' `Z`, il mixer di salto usa la stessa struttura avalanche con `ZZ0` al posto di `Z0`; l'operazione e' riportata separatamente dal packet Jacobian in-place. DP8 usa la specializzazione packet hardcoded `0xFF` per il fast path promosso, DP12 ha una specializzazione hardcoded `0xFFF` per probe solver sparsi, DP16 ha una specializzazione hardcoded `0xFFFF` per probe molto sparsi di pressione tabella, mentre gli altri valori usano un kernel con `ProjectiveDpMask(dp_bits)` runtime, cosi' DP10 e altre forme possono essere misurate sullo stesso oracle XYZZ senza cambiare la matematica. Il kernel a 256 step e' la baseline del sistema di coordinate, mentre autoresearch paired su M3 ha mantenuto la specializzazione a 512 step come plateau XYZZ corrente.

`metal-jacobian-dynamic-dp-stream-xyzz-affine-scan-bench` e' il primo probe DP affine al confine packet. Il kernel Metal esegue il walk dinamico XYZZ e scrive una distanza packet a 64 bit per walker; poi l'host normalizza in batch `X,Y,ZZ,ZZZ` con una sola inversione sui prodotti `ZZ*ZZZ`, scansiona i bit bassi di `x` affine e riporta `dp_tracking=affine_x_limb0_cpu_batch`. Cosi' il predicato DP resta piu' vicino a un solver reale senza introdurre inversioni per step. Il JSON separa throughput GPU grezzo (`gpu_ops_per_sec`) e throughput end-to-end packet-piu'-affine-scan (`ops_per_sec`) e registra `affine_scan_seconds`, cosi' i prossimi lavori possono spostare la normalizzazione su Metal senza nasconderne il costo.

`metal-jacobian-dynamic-dp-stream-xyzz-affine-scan-target-lookup-tag32-bench` collega quella superficie DP affine al gate multi-target compatto esatto. La scan host emette `x256` affine completo piu' parita' di `y` per candidati DP reali al confine packet, inietta un numero controllato di quelle chiavi in una tabella target tag32, e di default lancia il kernel Metal `target_lookup_tag32_exact256` sul set di query DP. Il JSON runtime riporta `output_layout=affine_dp_scan_target_lookup`, `dp_tracking=affine_x256_y_parity_cpu_batch`, `target_key=x256_y_parity`, `candidate_verification`, `dp_query_count`, `lookup_repeat`, `lookup_query_mode`, `lookup_engine`, `lookup_engine_effective`, `query_count`, `injected_hits`, `hit_count`, `miss_count`, `lookup_seconds`, `lookups_per_sec` e `target_lookup_checksum`. `--lookup-engine cpu` lascia invariati walk GPU e scan affine, ma sposta sull'host CPU solo la join target tag32 esatta finale. `--lookup-engine gpu-filter` usa su Metal un filtro tag32 da 4 byte per bucket e poi verifica su CPU solo i positivi compatti con equality esatta `x256 + y_parity`; il JSON riporta `lookup_layout=open_address_tag32_filter_exact256`, `filter_positive_count` e `filter_false_positive_count`. `--lookup-engine gpu-filter16-hash` usa il filtro tag16 da 2 byte e hash query precomputati da 64 bit, poi risolve i positivi compatti con la stessa equality CPU esatta; il JSON riporta `lookup_layout=open_address_tag16_hash_filter_exact256`, `query_input=hash64`, `target_query_hash_bytes` e gli stessi contatori positivi/falsi positivi. `--lookup-engine auto` lascia visibile la richiesta come `lookup_engine=auto`, poi registra il percorso scelto in `lookup_engine_effective`; la policy attuale lascia su CPU i grandi batch limitati da 25M target finche' un gate paired end-to-end non conferma il filtro, e usa ancora GPU con cap lookup a 512 thread per tabelle piu' cache-friendly quando il batch accumulato raggiunge almeno un milione di query. `--lookup-tg-limit N` regola solo il kernel Metal finale di target lookup, lasciando invariata la policy threadgroup del walk XYZZ. `--lookup-repeat N` espande il batch reale di query DP affini prima del lookup, cosi' il benchmark puo' modellare un solver che accumula DP al confine packet prima di lanciare una join target piu' grande. Il default `--lookup-query-mode repeat` ripete il batch reale di DP e ripete gli indici target esatti attesi dello stesso fattore. `--lookup-query-mode distinct-misses` conserva un batch reale di DP, poi riempie gli slot bulk rimanenti con chiavi deterministiche verificate come miss nella tabella target tag32; cosi' si ottiene un probe di join target mostly-miss piu' realistico per la cache, mantenendo un oracle esatto di hit/miss. Il default `N=1` e `--lookup-engine gpu` conservano il gate end-to-end originale. I gate autoresearch `bulk1024`, `distinct_misses1024`, `lookup_tg512` e `gpu_filter25m` separano volutamente throughput lookup, throughput walk e costo di verifica esatta. E' un benchmark integrato non-cheating per la join multi-target sul path macOS: throughput del walk, costo della scan affine, filtro target ed equality finale restano visibili.

`metal-target-lookup-tag32-persistent-bench` mantiene residenti in Metal tabella tag32, chiavi, query, output e pipeline mentre ripete i dispatch per il `--min-ms` richiesto. Il JSON separa `metal_setup_seconds`, `dispatch_seconds` gia' caldo, `lookups_per_sec` inclusivo del setup e `dispatch_lookups_per_sec`. Il cap threadgroup di default resta 64 sotto 16,777,216 target, ma le grandi tabelle diagnostiche usano 1024 di default su M3 dopo controlli paired a 25M target; un `--tg-limit N` esplicito prevale sempre su questo default adattivo. E' una diagnostica per capire l'economia di tabelle target GPU residenti a lungo, non un sostituto del gate integrato affine-scan target-lookup.

`metal-target-lookup-tag32-filter-persistent-bench` mantiene residenti il filtro tag32 compatto da 4 byte, il batch di query, il buffer degli indici positivi e la pipeline, poi verifica su CPU solo i positivi compatti con equality esatta `x256 + y_parity` dopo ogni dispatch. Il JSON riporta `buffer_lifetime=persistent`, `filter_positive_count`, `filter_false_positive_count`, `metal_setup_seconds`, `dispatch_seconds`, `exact_verify_seconds`, `lookups_per_sec` inclusivo del setup, `dispatch_lookups_per_sec` senza setup e `gpu_dispatch_lookups_per_sec` puramente Metal. La metrica senza setup include comunque il tempo di verifica exact CPU; la metrica GPU misura solo il dispatch. Le grandi tabelle filtro usano un default a 512 thread su M3, mentre `--tg-limit N` esplicito lo sovrascrive.

`metal-target-lookup-tag16-filter-persistent-bench` mantiene la stessa architettura con filtro persistente, ma salva un tag high-hash da 2 byte per bucket GPU. Il filtro residente piu' piccolo dimezza la memoria del filtro sui grandi casi da 25M target, pagando collisioni tag aggiuntive; la correttezza resta affidata solo alla equality CPU esatta `x256 + y_parity` sui positivi compatti. Il JSON usa `lookup_layout=open_address_tag16_filter_exact256`, `candidate_verification=tag16_filter_then_cpu_exact_key_equality` e riporta i falsi positivi separatamente dagli hit reali.

`metal-target-lookup-tag16-hash-filter-persistent-bench` usa lo stesso filtro tag16 residente e la stessa verifica exact CPU, ma il kernel Metal legge hash query precomputati da 64 bit invece delle righe complete `TargetLookupKey`. Il JSON riporta `query_input=hash64`, `target_query_hash_bytes`, `lookup_layout=open_address_tag16_hash_filter_exact256` e `candidate_verification=tag16_hash_filter_then_cpu_exact_key_equality`. E' un probe di banda query e lavoro hash, non cambia tabella target, resolver degli indici positivi o oracle finale di equality esatta.

Il benchmark affine-scan integrato espone anche `--lookup-engine gpu-filter16-hash`: usa lo stesso filtro tag16 e gli stessi hash query precomputati nel join finale dei DP, ma mantiene invariati walk, scansione affine, iniezione hit controllata e verifica exact CPU sui positivi compatti. Il JSON riporta `lookup_layout=open_address_tag16_hash_filter_exact256`, `query_input=hash64` e `target_query_hash_bytes`.

`jacobian_affine_walk_dynamic_dp_stream_xyzz_chain` estende il packet XYZZ in un probe piu' vicino a un solver con distanza cumulativa. Mantiene `X,Y,ZZ,ZZZ`, flag infinity e un buffer distanza per campione residenti attraverso piu' dispatch packet nello stesso command buffer Metal. Il JSON runtime riporta `packet_count`, `distance_tracking=dp_stream_cumulative_uint64`, `stream_indexing=packet_sample_u32` e `jump_schedule`; cosi' uno stesso walker puo' emettere piu' DP ai confini packet senza confondere record di packet diversi. L'oracle host riproduce ogni confine packet, valida lo stato finale XYZZ, e controlla conteggio stream sparso, duplicati, DP mancanti, distanze e termini DP. I comandi chain e persistent-chain accettano `--dp-bits` fino a 32 bit con DP8/DP12/DP16 hardcoded e maschera runtime per gli altri valori; i packet long-step usano di default un cap a 128 thread su M3, e un `--tg-limit N` esplicito continua a prevalere. Accettano anche `--jump-schedule scaled4-balanced` con `--jumps 4` per probe di correttezza della schedule, mentre il default resta `power2`. E' un probe architetturale per walk GPU persistenti, non un sostituto della baseline throughput XYZZ single-packet.

`jacobian_affine_walk_dynamic_dp_compact` e' un benchmark solo dinamico per `steps=8`, `dp_bits=4` e jump count power-of-two, pensato per la futura emissione GPU dei distinguished point. Usa lo stesso mixer di salto dentro il kernel e lo stesso oracle CPU replay del walk dinamico completo, ma emette solo flag packed, distanza scalare a 64 bit e un termine checksum DP compatto invece di copiare lo stato Jacobian finale da 96 byte. Il JSON runtime lo marca come `output_layout=dp_compact` e `output_bytes_per_sample=17`; il walk dinamico completo resta l'oracle esatto dello stato finale e il riferimento per la verifica delle collisioni.

`jacobian_affine_walk_dynamic_dp_stream` spinge la stessa idea oltre usando un contatore atomico per emettere solo i record DP effettivi come `(sample_index, distance, dp_term)`. Il JSON runtime lo marca come `output_layout=dp_stream`, `output_bytes_per_record=20`, `emitted_records`, `dp_capacity` e `dp_stream_overflow`. Lo stream non ha ordine garantito, quindi la verifica host ricostruisce i flag DP per campione prima del confronto con l'oracle CPU replay. Il gate DP4 usa ancora il kernel hardcoded DP4; gli altri valori di `dp_bits` usano un kernel con maschera runtime `ProjectiveDpMask(dp_bits)`, così le forme sparse DP8/DP12 si possono misurare senza cambiare l'oracle del walk. Quando l'host prova che la distanza scalare massima su otto passi entra in `uint32_t`, il kernel stream non-DP4 usa un accumulatore interno a 32 bit con guardia e cast finale all'output stream a 64 bit, preservando l'oracle `dp_stream_uint64`. La forma stream DP8 ha inoltre una specializzazione con maschera hardcoded `0xFF`, evitando il buffer runtime della maschera DP e mantenendo gli stessi record e checksum. Poiche' `dp_capacity` e' uguale al numero di campioni e ogni campione puo' emettere al massimo un record, quella specializzazione DP8 omette il ramo overflow dentro il kernel; l'host continua a riportare overflow se il conteggio atomico finale supera la capacita'. La forma stream DP12 molto sparsa usa di default un cap a 128 thread dopo conferma paired su M3, mentre DP6 e DP10 restano sul default condiviso a 256 thread dopo conferme rumorose negative. Un `--tg-limit N` esplicito vince sempre su questi default. Sul gate DP4 riduce molto il volume logico di output, ma gli atomics possono renderlo piu' lento dell'output compact per campione; trattalo come probe architetturale di emissione sparsa per `dp_bits` piu' alti, non come sostituto dell'oracle completo dello stato finale.

`jacobian_affine_walk_dynamic_dp_count` e' una diagnostica count-only per lo stesso walk dinamico. Usa la maschera DP runtime e un contatore atomico, ma non scrive record DP, distanze o termini checksum. Il JSON runtime lo marca come `output_layout=dp_count`, `output_bytes_total=4` e `distance_tracking=none`. Usalo per stimare quanta parte di un run sparse-stream sia overhead di scrittura record rispetto al walk aritmetico; non e' un percorso di output candidati per collisioni.

Comandi esempio per sweep threadgroup:

```sh
./macos/rck_macos metal-field-mul-bench --iterations 1048576 --min-ms 50 --tg-limit 128
./macos/rck_macos metal-field-mul-bench --iterations 1048576 --min-ms 50 --tg-limit 256
./macos/rck_macos metal-field-mul-bench --iterations 1048576 --min-ms 50 --tg-limit 512
./macos/rck_macos metal-jacobian-add-bench --iterations 65536 --min-ms 50 --tg-limit 256
./macos/rck_macos metal-jacobian-walk-bench --iterations 16384 --steps 8 --min-ms 50 --tg-limit 256
./macos/rck_macos metal-jacobian-jump-walk-bench --iterations 16384 --steps 8 --jumps 16 --min-ms 50 --tg-limit 256
./macos/rck_macos metal-jacobian-jump-walk-bench --iterations 16384 --steps 8 --jumps 16 --dp-bits 4 --min-ms 50 --tg-limit 256
./macos/rck_macos metal-jacobian-dynamic-walk-bench --iterations 16384 --steps 8 --jumps 16 --dp-bits 4 --min-ms 50 --tg-limit 256
./macos/rck_macos metal-jacobian-dynamic-compact-dp-bench --iterations 16384 --steps 8 --jumps 16 --dp-bits 4 --min-ms 200 --tg-limit 256
./macos/rck_macos metal-jacobian-dynamic-dp-stream-bench --iterations 16384 --steps 8 --jumps 16 --dp-bits 4 --min-ms 200 --tg-limit 256
./macos/rck_macos metal-jacobian-dynamic-dp-stream-bench --iterations 16384 --steps 8 --jumps 16 --dp-bits 8 --min-ms 200 --tg-limit 256
./macos/rck_macos metal-jacobian-dynamic-dp-stream-bench --iterations 16384 --steps 8 --jumps 16 --dp-bits 12 --min-ms 200
./macos/rck_macos metal-jacobian-dynamic-dp-stream-bench --iterations 16384 --steps 8 --jumps 16 --dp-bits 12 --min-ms 200 --tg-limit 256
./macos/rck_macos metal-jacobian-dynamic-dp-stream-xyzz-chain-bench --iterations 262144 --steps 512 --packets 2 --jumps 16 --dp-bits 8 --min-ms 500
./macos/rck_macos metal-jacobian-dynamic-dp-stream-xyzz-chain-bench --iterations 262144 --steps 512 --packets 2 --jumps 4 --dp-bits 8 --min-ms 500 --jump-schedule scaled4-balanced
./macos/rck_macos metal-jacobian-dynamic-dp-stream-xyzz-persistent-chain-bench --iterations 262144 --steps 512 --packets 2 --rounds 2 --jumps 16 --dp-bits 8
./macos/rck_macos metal-jacobian-dynamic-dp-stream-xyzz-persistent-chain-bench --iterations 262144 --steps 512 --packets 2 --rounds 2 --jumps 4 --dp-bits 8 --jump-schedule scaled4-balanced
./macos/rck_macos metal-jacobian-dynamic-dp-count-bench --iterations 16384 --steps 8 --jumps 16 --dp-bits 8 --min-ms 200 --tg-limit 256
./macos/rck_macos metal-target-lookup-bench --target-count 1048576 --query-count 1048576 --hits 4096 --min-ms 500 --tg-limit 64
./macos/rck_macos metal-target-lookup-compact-bench --target-count 1048576 --query-count 1048576 --hits 4096 --min-ms 500 --tg-limit 64
./macos/rck_macos metal-target-lookup-tag32-bench --target-count 1048576 --query-count 1048576 --hits 4096 --min-ms 500 --tg-limit 64
```

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
python3 autoresearch/runner.py --experiment metal_field_square_mul --budget-sec 5
python3 autoresearch/runner.py --experiment metal_target_lookup_exact256 --budget-sec 10
python3 autoresearch/runner.py --experiment metal_target_lookup_compact_exact256 --budget-sec 10 --paired-baseline-ref main
python3 autoresearch/runner.py --experiment metal_target_lookup_tag32_exact256 --budget-sec 10 --paired-baseline-ref main
python3 autoresearch/runner.py --experiment metal_target_lookup_tag32_filter_exact256 --budget-sec 10 --paired-baseline-ref main --confirm-runs 2
python3 autoresearch/runner.py --experiment metal_target_lookup_tag32_filter_persistent --budget-sec 10 --paired-baseline-ref main --confirm-runs 2
python3 autoresearch/runner.py --experiment metal_target_lookup_tag16_filter_persistent --budget-sec 30 --paired-baseline-ref main --confirm-runs 2
python3 autoresearch/runner.py --experiment metal_target_lookup_tag16_hash_filter_persistent --budget-sec 30 --paired-baseline-ref main --confirm-runs 2
python3 autoresearch/runner.py --experiment metal_jacobian_dynamic_dp_stream_xyzz_affine_scan_target_lookup_tag32_gpu_filter25m --budget-sec 10 --paired-baseline-ref main --confirm-runs 2
```

L'esperimento `jacobian_jump_walk` usa tre campioni del runner e registra throughput mediano/min/max, cosi i confronti del walk-core sono meno sensibili ai picchi brevi dello scheduler macOS.

Autoresearch registra l'assenza del device Metal come `status=skip`, non come crash, quindi lo stesso esperimento puo' girare sia su Apple Silicon locale sia in CI/headless.

Se vuoi generare tames per il solver completo, fallo sulla macchina CUDA. Con la modalita multi-target il file tames deve gia esistere; generalo separatamente prima di usare `-targets`.

# Note on ASR Decoder

## Kaldi Faster Decoder
* 通过max_active确定weight_cutoff, adptive_beam(max_active_cutoff - best_cost)
* next_weight_cutoff = new_weight + adaptive_beam

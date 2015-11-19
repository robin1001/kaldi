# Note on ASR Decoder

## TODO
三元的 942M 在构图过程中会占到70%左右，64G的内存

## 数据传输
* amr
* bv

## Kaldi Faster Decoder
* 通过max_active确定weight_cutoff, adptive_beam(max_active_cutoff - best_cost)
* next_weight_cutoff = new_weight + adaptive_beam

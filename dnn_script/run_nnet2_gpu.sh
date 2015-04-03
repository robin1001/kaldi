#!/bin/bash

#
# Copyright 2013 Bagher BabaAli,
#           2014 Brno University of Technology (Author: Karel Vesely)
#
# TIMIT, description of the database:
# http://perso.limsi.fr/lamel/TIMIT_NISTIR4930.pdf
#
# Hon and Lee paper on TIMIT, 1988, introduces mapping to 48 training phonemes, 
# then re-mapping to 39 phonemes for scoring:
# http://repository.cmu.edu/cgi/viewcontent.cgi?article=2768&context=compsci
#

. ./cmd.sh 
[ -f path.sh ] && . ./path.sh
set -e

# Acoustic model parameters
numLeavesTri1=2500
numGaussTri1=15000
numLeavesMLLT=2500
numGaussMLLT=15000
numLeavesSAT=2500
numGaussSAT=15000
numGaussUBM=400
numLeavesSGMM=7000
numGaussSGMM=9000

feats_nj=10
train_nj=2
decode_nj=2

echo ============================================================================
echo "                    DNN Hybrid Training & Decoding                        "
echo ============================================================================

# DNN hybrid system training parameters
dnn_mem_reqs="mem_free=1.0G,ram_free=1.0G"
dnn_extra_opts="--num_epochs 20 --num-epochs-extra 10 --add-layers-period 1 --shrink-interval 3"
time steps/nnet2/train_tanh.sh --mix-up 5000 --initial-learning-rate 0.04\
  --final-learning-rate 0.004 --num-hidden-layers 2  \
  --num-jobs-nnet "$train_nj" --cmd "$train_cmd" "${dnn_train_extra_opts[@]}" \
  --num-threads 1 --parallel-opts "-l gpu=1" \
  data/train data/lang exp/tri3_ali exp/tri4_nnet_gpu

[ ! -d exp/tri4_nnet_gpu/decode_dev ] && mkdir -p exp/tri4_nnet_gpu/decode_dev
decode_extra_opts=(--num-threads 1 --parallel-opts "-l gpu=1")
steps/nnet2/decode.sh --cmd "$decode_cmd" --nj "$decode_nj" "${decode_extra_opts[@]}" \
  --transform-dir exp/tri3/decode_dev exp/tri3/graph data/dev \
  exp/tri4_nnet_gpu/decode_dev | tee exp/tri4_nnet_gpu/decode_dev/decode.log

[ ! -d exp/tri4_nnet_gpu/decode_test ] && mkdir -p exp/tri4_nnet_gpu/decode_test
steps/nnet2/decode.sh --cmd "$decode_cmd" --nj "$decode_nj" "${decode_extra_opts[@]}" \
  --transform-dir exp/tri3/decode_test exp/tri3/graph data/test \
  exp/tri4_nnet_gpu/decode_test | tee exp/tri4_nnet_gpu/decode_test/decode.log

echo ============================================================================
echo "Finished successfully on" `date`
echo ============================================================================

exit 0

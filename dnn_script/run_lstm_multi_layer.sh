#!/bin/bash

# Copyright 2015  Brno University of Technology (Author: Karel Vesely)
# Apache 2.0

# This example script trains a LSTM network on FBANK features.
# The LSTM code comes from Yiayu DU, and Wei Li, thanks!

. ./cmd.sh
. ./path.sh

dev=data-fbank/test
train=data-fbank/train

dev_original=data/test
train_original=data/train

gmm=exp/tri3

stage=1
. utils/parse_options.sh || exit 1;

# Make the FBANK features
[ ! -e $dev ] && if [ $stage -le 0 ]; then
  # Dev set
  utils/copy_data_dir.sh $dev_original $dev || exit 1; rm $dev/{cmvn,feats}.scp
  steps/make_fbank_pitch.sh --nj 10 --cmd "$train_cmd" \
     $dev $dev/log $dev/data || exit 1;
  steps/compute_cmvn_stats.sh $dev $dev/log $dev/data || exit 1;
  # Training set
  utils/copy_data_dir.sh $train_original $train || exit 1; rm $train/{cmvn,feats}.scp
  steps/make_fbank_pitch.sh --nj 10 --cmd "$train_cmd -tc 10" \
     $train $train/log $train/data || exit 1;
  steps/compute_cmvn_stats.sh $train $train/log $train/data || exit 1;
  # Split the training set
  utils/subset_data_dir_tr_cv.sh --cv-spk-percent 10 $train ${train}_tr90 ${train}_cv10
fi

cell_dim=1024
lstm_layers=3
echo "lstm training"
if [ $stage -le 1 ]; then
  # Train the DNN optimizing per-frame cross-entropy.
  dir=exp/lstm-c${cell_dim}-${lstm_layers}layer
  ali=${gmm}_ali
  (tail --pid=$$ -F $dir/log/train_nnet.log 2>/dev/null)& # forward log
  # Train
  $cuda_cmd $dir/log/train_nnet.log \
    dnn_script/train_layer_wise.sh  --network-type lstm --learn-rate 0.0001 \
	  --hid-layers $lstm_layers  \
      --cmvn-opts "--norm-means=true --norm-vars=true" --feat-type plain --splice 0 \
      --train-opts "--momentum 0.7 --halving-factor 0.8 --max-iters 40" \
      --train-tool "nnet-train-lstm-streams --num-stream=4 --targets-delay=5" \
	  --proto-opts "--num-cells $cell_dim" \
    ${train}_tr90 ${train}_cv10 data/lang $ali $ali $dir || exit 1;

  # Decode (reuse HCLG graph)
  steps/nnet/decode.sh --nj 20 --cmd "$decode_cmd" --config conf/decode_dnn.config --acwt 0.1 \
    $gmm/graph $dev $dir/decode || exit 1;
  steps/nnet/decode.sh --nj 20 --cmd "$decode_cmd" --config conf/decode_dnn.config --acwt 0.1 \
    --nnet-forward-opts "--no-softmax=true --prior-scale=1.0 --time-shift=5" \
    $gmm/graph $dev $dir/decode_time-shift5 || exit 1;
fi

# TODO : sequence training,

echo Success
exit 0

# Getting results [see RESULTS file]
# for x in exp/*/decode*; do [ -d $x ] && grep WER $x/wer_* | utils/best_wer.sh; done

#!/bin/bash

# Copyright 2012-2014  Brno University of Technology (Author: Karel Vesely)
# Apache 2.0

# This example script trains a DNN on top of FBANK features. 
# The training is done in 3 stages,
#
. ./cmd.sh ## You'll want to change cmd.sh to something that will work on your system.
           ## This relates to the queue.

. ./path.sh ## Source the tools/utils (import the queue.pl)

dev=data-fbank/test
train=data-fbank/train

dev_original=data/test
train_original=data/train

gmm=exp/tri3

stage=1
. utils/parse_options.sh || exit 1;

# Make the FBANK features
if [ $stage -le 0 ]; then
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

if [ $stage -le 2 ]; then
  # Train the DNN optimizing per-frame cross-entropy.
  dir=exp/dnn_layer_wise2
  ali=${gmm}_ali
  (tail --pid=$$ -F $dir/log/train_nnet.log 2>/dev/null)& # forward log
  # Train
  $cuda_cmd $dir/log/train_nnet.log \
    dnn_script/train_layer_wise.sh  --hid-layers 4 --learn-rate 0.008 \
	--train-opts "--min-iters 15" \
    ${train}_tr90 ${train}_cv10 data/lang $ali $ali $dir || exit 1;
  # Decode (reuse HCLG graph)
  steps/nnet/decode.sh --nj 20 --cmd "$decode_cmd" --config conf/decode_dnn.config --acwt 0.1 \
    $gmm/graph $dev $dir/decode || exit 1;
fi


# Sequence training using sMBR criterion, we do Stochastic-GD 
# with per-utterance updates. We use usually good acwt 0.1
#dir=exp/dnn4d-fbank_pretrain-dbn_dnn_smbr
#srcdir=exp/dnn4d-fbank_pretrain-dbn_dnn
#acwt=0.1
#
#if [ $stage -le 3 ]; then
#  # First we generate lattices and alignments:
#  steps/nnet/align.sh --nj 20 --cmd "$train_cmd" \
#    $train data/lang $srcdir ${srcdir}_ali || exit 1;
#  steps/nnet/make_denlats.sh --nj 20 --cmd "$decode_cmd" --config conf/decode_dnn.config --acwt $acwt \
#    $train data/lang $srcdir ${srcdir}_denlats || exit 1;
#fi
#
#if [ $stage -le 4 ]; then
#  # Re-train the DNN by 6 iterations of sMBR 
#  steps/nnet/train_mpe.sh --cmd "$cuda_cmd" --num-iters 6 --acwt $acwt --do-smbr true \
#    $train data/lang $srcdir ${srcdir}_ali ${srcdir}_denlats $dir || exit 1
#  # Decode
#  for ITER in 1 2 3 4 5 6; do
#    steps/nnet/decode.sh --nj 20 --cmd "$decode_cmd" --config conf/decode_dnn.config \
#      --nnet $dir/${ITER}.nnet --acwt $acwt \
#      $gmm/graph $dev $dir/decode_it${ITER} || exit 1
#  done 
#fi

echo Success
exit 0

# Getting results [see RESULTS file]
# for x in exp/*/decode*; do [ -d $x ] && grep WER $x/wer_* | utils/best_wer.sh; done

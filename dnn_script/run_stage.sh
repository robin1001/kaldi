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

feats_nj=24
train_nj=24
decode_nj=10

stage=0
timit=/media/files/hcq/TIMIT/TIMIT/TIMIT/

if [ $stage -le 0 ]; then
	echo ============================================================================
	echo "                Data & Lexicon & Language Preparation                     "
	echo ============================================================================
	#timit=/export/corpora5/LDC/LDC93S1/timit/TIMIT # @JHU
	#timit=/mnt/matylda2/data/TIMIT/timit # @BUT
	local/timit_data_prep.sh $timit || exit 1
	
	local/timit_prepare_dict.sh
	
	# Caution below: we remove optional silence by setting "--sil-prob 0.0",
	# in TIMIT the silence appears also as a word in the dictionary and is scored.
	utils/prepare_lang.sh --sil-prob 0.0 --position-dependent-phones false --num-sil-states 3 \
	 data/local/dict "sil" data/local/lang_tmp data/lang
	
	local/timit_format_data.sh
fi

if [ $stage -le 1 ]; then
	echo ============================================================================
	echo "         MFCC Feature Extration & CMVN for Training and Test set          "
	echo ============================================================================
	# Now make MFCC features.
	mfccdir=mfcc
	
	
	for x in train dev test; do 
	  steps/make_mfcc.sh --cmd "$train_cmd" --nj $feats_nj data/$x exp/make_mfcc/$x $mfccdir
	  steps/compute_cmvn_stats.sh data/$x exp/make_mfcc/$x $mfccdir
	done
fi

if [ $stage -le 2 ]; then
	echo ============================================================================
	echo "                     MonoPhone Training & Decoding                        "
	echo ============================================================================
	
	steps/train_mono.sh  --nj "$train_nj" --cmd "$train_cmd" data/train data/lang exp/mono
	
	utils/mkgraph.sh --mono data/lang_test_bg exp/mono exp/mono/graph
	
	steps/decode.sh --nj "$decode_nj" --cmd "$decode_cmd" \
	 exp/mono/graph data/dev exp/mono/decode_dev
	
	steps/decode.sh --nj "$decode_nj" --cmd "$decode_cmd" \
	 exp/mono/graph data/test exp/mono/decode_test
fi

if [ $stage -le 3 ]; then
	echo ============================================================================
	echo "           tri1 : Deltas + Delta-Deltas Training & Decoding               "
	echo ============================================================================
	
	steps/align_si.sh --boost-silence 1.25 --nj "$train_nj" --cmd "$train_cmd" \
	 data/train data/lang exp/mono exp/mono_ali
	
	# Train tri1, which is deltas + delta-deltas, on train data.
	steps/train_deltas.sh --cmd "$train_cmd" \
	 $numLeavesTri1 $numGaussTri1 data/train data/lang exp/mono_ali exp/tri1
	
	utils/mkgraph.sh data/lang_test_bg exp/tri1 exp/tri1/graph
	
	steps/decode.sh --nj "$decode_nj" --cmd "$decode_cmd" \
	 exp/tri1/graph data/dev exp/tri1/decode_dev
	
	steps/decode.sh --nj "$decode_nj" --cmd "$decode_cmd" \
	 exp/tri1/graph data/test exp/tri1/decode_test
fi

if [ $stage -le 4 ]; then
	echo ============================================================================
	echo "                 tri2 : LDA + MLLT Training & Decoding                    "
	echo ============================================================================
	
	steps/align_si.sh --nj "$train_nj" --cmd "$train_cmd" \
	  data/train data/lang exp/tri1 exp/tri1_ali
	
	steps/train_lda_mllt.sh --cmd "$train_cmd" \
	 --splice-opts "--left-context=3 --right-context=3" \
	 $numLeavesMLLT $numGaussMLLT data/train data/lang exp/tri1_ali exp/tri2
	
	utils/mkgraph.sh data/lang_test_bg exp/tri2 exp/tri2/graph
	
	steps/decode.sh --nj "$decode_nj" --cmd "$decode_cmd" \
	 exp/tri2/graph data/dev exp/tri2/decode_dev
	
	steps/decode.sh --nj "$decode_nj" --cmd "$decode_cmd" \
	 exp/tri2/graph data/test exp/tri2/decode_test
fi

if [ $stage -le 5 ]; then
	echo ============================================================================
	echo "              tri3 : LDA + MLLT + SAT Training & Decoding                 "
	echo ============================================================================
	
	# Align tri2 system with train data.
	steps/align_si.sh --nj "$train_nj" --cmd "$train_cmd" \
	 --use-graphs true data/train data/lang exp/tri2 exp/tri2_ali
	
	# From tri2 system, train tri3 which is LDA + MLLT + SAT.
	steps/train_sat.sh --cmd "$train_cmd" \
	 $numLeavesSAT $numGaussSAT data/train data/lang exp/tri2_ali exp/tri3
	
	utils/mkgraph.sh data/lang_test_bg exp/tri3 exp/tri3/graph
	
	steps/decode_fmllr.sh --nj "$decode_nj" --cmd "$decode_cmd" \
	 exp/tri3/graph data/dev exp/tri3/decode_dev
	
	steps/decode_fmllr.sh --nj "$decode_nj" --cmd "$decode_cmd" \
	 exp/tri3/graph data/test exp/tri3/decode_test
fi


if [ $stage -le 6 ]; then
	echo ============================================================================
	echo "                    DNN Hybrid Training & Decoding                        "
	echo ============================================================================
	
	# DNN hybrid system training parameters
	dnn_mem_reqs="mem_free=1.0G,ram_free=1.0G"
	dnn_extra_opts="--num_epochs 20 --num-epochs-extra 10 --add-layers-period 1 --shrink-interval 3"
	
	steps/nnet2/train_tanh.sh --mix-up 5000 --initial-learning-rate 0.015 \
	  --final-learning-rate 0.002 --num-hidden-layers 2  \
	  --num-jobs-nnet "$train_nj" --cmd "$train_cmd" "${dnn_train_extra_opts[@]}" \
	  data/train data/lang exp/tri3_ali exp/tri4_nnet
	
	[ ! -d exp/tri4_nnet/decode_dev ] && mkdir -p exp/tri4_nnet/decode_dev
	decode_extra_opts=(--num-threads 6 --parallel-opts "-pe smp 6 -l mem_free=4G,ram_free=4.0G")
	steps/nnet2/decode.sh --cmd "$decode_cmd" --nj "$decode_nj" "${decode_extra_opts[@]}" \
	  --transform-dir exp/tri3/decode_dev exp/tri3/graph data/dev \
	  exp/tri4_nnet/decode_dev | tee exp/tri4_nnet/decode_dev/decode.log
	
	[ ! -d exp/tri4_nnet/decode_test ] && mkdir -p exp/tri4_nnet/decode_test
	steps/nnet2/decode.sh --cmd "$decode_cmd" --nj "$decode_nj" "${decode_extra_opts[@]}" \
	  --transform-dir exp/tri3/decode_test exp/tri3/graph data/test \
	  exp/tri4_nnet/decode_test | tee exp/tri4_nnet/decode_test/decode.log
fi


#if [ $stage -le 7 ]; then
#	echo ============================================================================
#	echo "                    System Combination (DNN+SGMM)                         "
#	echo ============================================================================
#	
#	for iter in 1 2 3 4; do
#	  local/score_combine.sh --cmd "$decode_cmd" \
#	   data/dev data/lang_test_bg exp/tri4_nnet/decode_dev \
#	   exp/sgmm2_4_mmi_b0.1/decode_dev_it$iter exp/combine_2/decode_dev_it$iter
#	
#	  local/score_combine.sh --cmd "$decode_cmd" \
#	   data/test data/lang_test_bg exp/tri4_nnet/decode_test \
#	   exp/sgmm2_4_mmi_b0.1/decode_test_it$iter exp/combine_2/decode_test_it$iter
#	done
#fi

echo ============================================================================
echo "                    Getting Results [see RESULTS file]                    "
echo ============================================================================

bash RESULTS dev
bash RESULTS test

echo ============================================================================
echo "Finished successfully on" `date`
echo ============================================================================

exit 0

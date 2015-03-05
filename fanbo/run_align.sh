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

decode_nj=2
train_nj=10

echo ============================================================================
echo "                Data & Lexicon & Language Preparation                     "
echo ============================================================================

[ -d ./data ] && rm -r ./data
[ -d ./exp ] && rm -r ./exp
local/fanbo_data_prep2.sh || exit 1

local/fanbo_prepare_dict.sh

# Caution below: we insert optional-silence with probability 0.5, which is the
# default, but this is probably not appropriate for this setup, since silence
# appears also as a word in the dictionary and is scored.  We could stop this
# by using the option --sil-prob 0.0, but apparently this makes results worse.
# (-> In sclite scoring the deletions of 'sil' are not scored as errors)

#utils/prepare_lang.sh --num-sil-states 3 \
utils/prepare_lang.sh --position-dependent-phones false --num-sil-states 7 --num-nonsil-states 7 \
 data/local/dict "sil" data/local/lang_tmp data/lang

local/fanbo_format_data.sh

#echo ============================================================================
#echo "         MFCC Feature Extration & CMVN for Training and Test set           "
#echo ============================================================================
#
# Now make MFCC features.
mfccdir=mfcc

for x in train test; do 
  steps/make_mfcc.sh --cmd "$train_cmd" --nj 30 data/$x exp/make_mfcc/$x $mfccdir
  steps/compute_cmvn_stats.sh data/$x exp/make_mfcc/$x $mfccdir
done

#echo ============================================================================
#echo "                     MonoPhone Training & Decoding                        "
#echo ============================================================================

steps/train_mono.sh  --nj "$train_nj" --cmd "$train_cmd" data/train data/lang exp/mono

utils/mkgraph.sh --mono data/lang_test_bg exp/mono exp/mono/graph

steps/decode.sh --nj "$decode_nj" --cmd "$decode_cmd" \
 exp/mono/graph data/test exp/mono/decode_test


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
 exp/tri1/graph data/test exp/tri1/decode_test

echo ============================================================================
echo "                 tri2 : LDA + MLLT Training & Decoding                    "
echo ============================================================================

steps/align_si.sh --nj "$train_nj" --cmd "$train_cmd" \
  data/train data/lang exp/tri1 exp/tri1_ali

echo ============================================================================
echo "                 ali: get alignment result                    "
echo ============================================================================

do_align.sh exp/tri1_ali
get_ali_time.sh align_phone.txt

exit 0

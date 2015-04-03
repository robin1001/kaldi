#!/bin/bash

data=data/train
lang=data/lang
alidir=exp/tri3_ali
dir=exp/layer_wise_dnn
gmmdir=exp/tri3
stage=0

. ./cmd.sh
. ./path.sh


if [ ! -d $dir ]; then
	mkdir -p $dir
fi

#train layer wise
if [ $stage -le 0 ]; then
	dnn_script/train_layer_wise.sh --max_iters 30 --use_gpu "yes" \
	$data $lang $alidir $dir || exit 1
fi

if [ $stage -le 1 ]; then
  	cmvn=`cat $alidir/cmvn_opts 2>/dev/null`
  	echo $cmvn
  	dnn_script/decode_layer_wise.sh --nj 10 --cmd "$decode_cmd" --acwt 0.2 \
	--use_gpu "yes"  --srcdir $dir \
    $gmmdir/graph data/test $dir/decode_test || exit 1;
fi


echo "DNN layer wise training & decoding Done!!!"

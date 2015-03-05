#!/bin/bash
# create by robin1001, 2014-12-09

#fanbo's task
#do alignment for all data, for convenience reason here test data set is part of train data
#just for convnience
wav_dir=./wav/zhy
label_file=./wav/zhy.text
dir=`pwd`/data/local/data
mkdir -p $dir $lmdir
utils=`pwd`/utils

#get all wav list, select 1000 sentences for test
find $wav_dir -name "*.wav" > $dir/all.flist
shuf $dir/all.flist | head -n 1000 > $dir/test.flist
#here is the main difference to run.sh
#run.sh grep -v -f $dir/test.flist $dir/all.flist > $dir/train.flist
cat $dir/all.flist > $dir/train.flist

#prepare uttids, scp, text, utt2spk
for x in train test; do
    sed -e "s:.*/\(.*\).wav:\1:" $dir/${x}.flist > $dir/${x}.uttids
    paste $dir/${x}.uttids $dir/${x}.flist | sort -k1 > $dir/${x}.scp
	grep -f $dir/${x}.uttids $label_file | sort -k1 > $dir/${x}.text
    awk '{print $1, $1}' $dir/${x}.uttids | sort -k1 > $dir/${x}.utt2spk
    cat $dir/${x}.utt2spk | $utils/utt2spk_to_spk2utt.pl | sort -k1 > $dir/${x}.spk2utt || exit 1;
done

n1=`cat $dir/train.scp | wc -l`
n2=`cat $dir/test.scp | wc -l`
echo "train set ${n1} sentence, test set ${n2} sentence"
echo "data prepare done"

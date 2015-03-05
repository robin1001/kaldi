#!/bin/bash

if [ $# -ne 1 ]; then 
	echo "Usage: do_align.sh ali_gz_dir"
	exit -1
fi

dir=$1

tmpdir=$(mktemp -d)
tmp1=$tmpdir/tmp1
tmp2=$tmpdir/tmp2
for x in $dir/ali.*.gz; do
	echo $x	
	ali-to-phones --write-lengths $dir/final.mdl "ark:gunzip -c ${x}|" ark,t:- >> $tmp1
	show-alignments data/lang/phones.txt $dir/final.mdl "ark:gunzip -c ${x}|" >> $tmp2
done

cat $tmp1 | sort -k1 > align_phone.txt
cat $tmp2 | sort -k1 > align_raw.txt


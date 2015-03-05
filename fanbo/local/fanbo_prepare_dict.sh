#!/bin/bash
set -e
srcdir=data/local/data
dir=data/local/dict
lmdir=data/local/nist_lm
tmpdir=data/local/lm_tmp

if [ -d $tmpdir ]; then rm -r $tmpdir; fi
mkdir -p $dir $lmdir $tmpdir

[ -f path.sh ] && . ./path.sh

#sil phone
echo sil > $dir/silence_phones.txt
echo sil > $dir/optional_silence.txt

#lexicon, phones
cut -d ' ' -f2- $srcdir/train.text | tr ' ' '\n' | sort -u > $dir/phones.txt
paste $dir/phones.txt $dir/phones.txt > $dir/lexicon.txt || exit 1;
grep -v -F -f $dir/silence_phones.txt $dir/phones.txt > $dir/nonsilence_phones.txt 

#extra_questions
cat $dir/silence_phones.txt| awk '{printf("%s ", $1);} END{printf "\n";}' > $dir/extra_questions.txt || exit 1;
cat $dir/nonsilence_phones.txt | perl -e 'while(<>){ foreach $p (split(" ", $_)) {
  $p =~ m:^([^\d]+)(\d*)$: || die "Bad phone $_"; $q{$2} .= "$p "; } } foreach $l (values %q) {print "$l\n";}' \
 >> $dir/extra_questions.txt || exit 1;

phn=`cat $dir/phones.txt | wc -l`
echo "${phn} phones in sum"

# (2) Create the phone bigram LM
[ -z "$IRSTLM" ] && \
  echo "LM building won't work without setting the IRSTLM env variable" && exit 1;
! which build-lm.sh 2>/dev/null  && \
  echo "IRSTLM does not seem to be installed (build-lm.sh not on your path): " && \
  echo "go to <kaldi-root>/tools and try 'make irstlm_tgt'" && exit 1;
#add <s> ... </s>
cut -d' ' -f2- $srcdir/train.text | awk '{print "<s>", $0, "</s>"}'  > $srcdir/lm_train.text
#cut -d' ' -f2- $srcdir/train.text | sed -e 's:^:<s> :' -e 's:$: </s>:'  > $srcdir/lm_train.text
which build-lm.sh
build-lm.sh -i $srcdir/lm_train.text -n 2 -o $tmpdir/lm_phone_bg.ilm.gz

compile-lm $tmpdir/lm_phone_bg.ilm.gz -t=yes /dev/stdout | \
grep -v unk | gzip -c > $lmdir/lm_phone_bg.arpa.gz 

echo "Dictionary & language model preparation succeeded"

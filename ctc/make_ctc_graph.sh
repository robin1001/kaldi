#!/bin/bash
# Make Ctc Decode Graph, mainly copy from(https://github.com/yajiemiao/eesen)
# Created on 2015-08-05
# Author: zhangbinbin(zhangbinbin02@baidu.com)

dir=syllable
tmpdir=$dir/lang_tmp
mkdir -p $dir $tmpdir

[ -f path.sh ] && . ./path.sh

lexicon_file=$dir/syllable.lexicon
phone_file=$dir/syllable.txt
grammer_fst=$dir/G.fst

#cp $srcdir/lexicon_numbers.txt $dir

# Add probabilities to lexicon entries. There is in fact no point of doing this here since all the entries have 1.0.
# But utils/make_lexicon_fst.pl requires a probabilistic version, so we just leave it as it is. 
perl -ape 's/(\S+\s+)(.+)/${1}1.0\t$2/;' < $lexicon_file > $tmpdir/lexiconp.txt || exit 1;

# Add disambiguation symbols to the lexicon. This is necessary for determinizing the composition of L.fst and G.fst.
# Without these symbols, determinization will fail. 
ndisambig=`utils/add_lex_disambig.pl $tmpdir/lexiconp.txt $tmpdir/lexiconp_disambig.txt`
ndisambig=$[$ndisambig+1];

( for n in `seq 0 $ndisambig`; do echo '#'$n; done ) > $tmpdir/disambig.txt

# Get the full list of CTC tokens used in FST. These tokens include <eps>, the blank <blk>, the actual labels (e.g.,
# phonemes), and the disambiguation symbols. 
cat $phone_file | awk '{print $1}' > $tmpdir/units.txt
(echo '<eps>'; echo '<blk>';) | cat - $tmpdir/units.txt $tmpdir/disambig.txt | awk '{print $1 " " (NR-1)}' > $dir/tokens.txt

# Compile the tokens into FST
./ctc_token_fst.py $dir/tokens.txt | fstcompile --isymbols=$dir/tokens.txt --osymbols=$dir/tokens.txt \
   --keep_isymbols=false --keep_osymbols=false | fstarcsort --sort_type=olabel > $dir/T.fst || exit 1;

# Encode the words with indices. Will be used in lexicon and language model FST compiling. 
cat $tmpdir/lexiconp.txt | awk '{print $1}' | sort | uniq  | awk '
  BEGIN {
    print "<eps> 0";
  } 
  {
    printf("%s %d\n", $1, NR);
  }
  END {
    printf("#0 %d\n", NR+1);
  }' > $dir/words.txt || exit 1;

# Now compile the lexicon FST. Depending on the size of your lexicon, it may take some time. 
token_disambig_symbol=`grep \#0 $dir/tokens.txt | awk '{print $2}'`
word_disambig_symbol=`grep \#0 $dir/words.txt | awk '{print $2}'`

utils/make_lexicon_fst.pl --pron-probs $tmpdir/lexiconp_disambig.txt 0 "sil" '#'$ndisambig | \
  fstcompile --isymbols=$dir/tokens.txt --osymbols=$dir/words.txt \
  --keep_isymbols=false --keep_osymbols=false |   \
  fstaddselfloops  "echo $token_disambig_symbol |" "echo $word_disambig_symbol |" | \
  fstarcsort --sort_type=olabel > $dir/L.fst || exit 1;
echo "Dict and token FSTs compiling succeeded"

# Compose the final decoding graph. The composition of L.fst and G.fst is determinized and
# minimized.
fsttablecompose $dir/L.fst $grammer_fst | fstdeterminizestar --use-log=true | \
    fstminimizeencoded | fstarcsort --sort_type=ilabel > $dir/LG.fst || exit 1;
fsttablecompose $dir/T.fst $dir/LG.fst > $dir/TLG.fst || exit 1;

echo "Composing decoding graph TLG.fst succeeded"

# Decode
#decode-faster --beam=13.0 --max-active=7000 --acoustic-scale=1.0 \
#    --allow-partial=true \
#    --words-symbols-table=$dir/words.txt \
#    $dir/TLG.fst "ark:input_score_file" "ark,t:result_file"


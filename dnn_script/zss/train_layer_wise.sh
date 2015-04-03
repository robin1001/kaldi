# Begin configuration.
config=            # config, which is also sent to all other scripts

# NETWORK INITIALIZATION
mlp_init=          # select initialized MLP (override initialization)
num_hidden_layers=3
add_layers_period=1
halving=0
halving_count=0
iter=0
pretrain_first=1
bin_dir=../../../src/nnetbin

close_melupdate=false
close_melmask=false

update_mv=0
#
init_opts=         # options, passed to the initialization script

# FEATURE PROCESSING
# feature config (applies always)
norm_vars=true # use variance normalization?

# TRAINING SCHEDULER
learn_rate=0.008
momentum=0.5
l1_penalty=0
l2_penalty=0
# data processing
minibatch_size=256
randomizer_size=32768
randomizer_seed=777
feature_transform=
# learn rate scheduling
max_iters=100
#start_halving_inc=0.5
#end_halving_inc=0.1
start_halving_impr=0.001
end_halving_impr=0.001
halving_factor=0.5
# misc.
verbose=1
# tool
use_gpu="yes" # yes|no|optionaly
nj=24
# End configuration.

echo "$0 $@"  # Print the command line for logging

[ -f path.sh ] && . ./path.sh; 


. parse_options.sh || exit 1;


if [ $# != 4 ]; then
   echo "Usage: $0 <data-train> <lang-dir> <ali-train> <exp-dir> <data-test>"
   echo " e.g.: $0 data/train data/lang exp/mono_ali exp/mono_nnet"
   echo "main options (for others, see top of script file)"
   echo "  --config <config-file>  # config containing options"
   exit 1;
fi

data=$1
lang=$2
alidir=$3
dir=$4

##利用的命令
#saisai#train_tool=$bin_dir/bd-nnet-train-frmshuff
train_tool=$bin_dir/nnet-train-frmshuff
##检查ali文件夹中是否有final.mdl（模型文件），ali.1.gz（对齐的抄本）
for f in $alidir/final.mdl $alidir/ali.[1-$nj].gz; do
  [ ! -f $f ] && echo "$0: no such file $f"  && exit 1;
done

echo
echo "# INFO"
echo "$0 : Training Neural Network"
printf "\t Dest-dir       : $dir \n"
printf "\t Train-set : $data \n"
printf "\t Ali-dir : $alidir \n"

mkdir -p $dir/{log,nnet}

num_utts_subset=300
###### PREPARE ALIGNMENTS ######
if [ ! -f $dir/valid_uttlist ];then
    awk '{print $1}' $data/feats.scp | utils/shuffle_list.pl | head -$num_utts_subset > $dir/valid_uttlist || exit 1;
fi

labels_tr="ark:ali-to-pdf $alidir/final.mdl \"ark:gunzip -c $alidir/ali.*.gz |\" ark:- | ali-to-post ark:- ark:- |"
labels_cv="ark:ali-to-pdf $alidir/final.mdl \"ark:gunzip -c $alidir/ali.*.gz |\" ark:- | ali-to-post ark:- ark:- |"
# 
labels_tr_pdf="ark:ali-to-pdf $alidir/final.mdl \"ark:gunzip -c $alidir/ali.*.gz |\" ark:- |" # for analyze-counts.
labels_tr_phn="ark:ali-to-phones --per-frame=true $alidir/final.mdl \"ark:gunzip -c $alidir/ali.*.gz |\" ark:- |"


# get pdf-counts, used later to post-process DNN posteriors
analyze-counts --verbose=1 --binary=false "$labels_tr_pdf" $dir/ali_train_pdf.counts 2>$dir/log/analyze_counts_pdf.log || exit 1

# copy the old transition model, will be needed by decoder
copy-transition-model --binary=false $alidir/final.mdl $dir/final.mdl || exit 1
# copy the tree
cp $alidir/tree $dir/tree || exit 1

# make phone counts for analysis
analyze-counts --verbose=1 --symbol-table=$lang/phones.txt "$labels_tr_phn" $dir/ali_train_phn.counts 2>$dir/log/analyze_counts_phones.log || exit 1

cmvn_opts=`cat $alidir/cmvn_opts 2>/dev/null`
cp $alidir/cmvn_opts $dir 2>/dev/null

feats_tr="ark,s,cs:utils/filter_scp.pl --exclude $dir/valid_uttlist $data/feats.scp | shuf | apply-cmvn $cmvn_opts --utt2spk=ark:$data/utt2spk scp:$data/cmvn.scp scp:- ark:- | splice-feats ark:- ark:-|"
feats_cv="ark,s,cs:utils/filter_scp.pl $dir/valid_uttlist $data/feats.scp | apply-cmvn $cmvn_opts --utt2spk=ark:$data/utt2spk scp:$data/cmvn.scp scp:- ark:- | splice-feats ark:- ark:-|"

# set feat_dim and num_leaves
feat_dim=$(feat-to-dim "$feats_tr" -) || exit 1;
feat_dim_cv=$(feat-to-dim "$feats_cv" -) || exit 1;
echo feat_tr dim is $feat_dim
echo feat_cv dim is $feat_dim_cv

num_leaves=`am-info $alidir/final.mdl 2>/dev/null | awk '/number of pdfs/{print $NF}'` || exit 1;
echo number of pdfs is $num_leaves

if [ ! -f $dir/nnet.proto ] ; then
    echo creating $dir/nnet.proto ...
    cat > $dir/nnet.proto <<EOF
<NnetProto>
<AffineTransform> <InputDim> $feat_dim <OutputDim> 1024 <BiasMean> -2.000000 <BiasRange> 4.000000 <ParamStddev> 0.043805
<Sigmoid> <InputDim> 1024 <OutputDim> 1024
<AffineTransform> <InputDim> 1024 <OutputDim> $num_leaves <BiasMean> 0.000000 <BiasRange> 0.000000 <ParamStddev> 0.084503
<Softmax> <InputDim> $num_leaves <OutputDim> $num_leaves 
</NnetProto>
EOF
fi

if [ ! -f $dir/hidden.conf ] ; then
    cat > $dir/hidden.conf <<EOF
<NnetProto>
<AffineTransform> <InputDim> 1024 <OutputDim> 1024 <BiasMean> -2.000000 <BiasRange> 4.000000 <ParamStddev> 0.043805
<Sigmoid> <InputDim> 1024 <OutputDim> 1024
</NnetProto>
EOF
fi

###### INITIALIZE THE NNET ######
echo 
echo "# NN-INITIALIZATION"
if [ -z "$mlp_init" ]; then
    mlp_proto=$dir/nnet.proto
    mlp_init=$dir/nnet.init
    log=$dir/log/nnet_initialize.log
    $bin_dir/nnet-initialize $mlp_proto $mlp_init 2>$log || { cat $log; exit 1; } 
fi

###### TRAIN ######
echo
echo "# RUNING LAYER-BP TRAINING"

[ ! -d $dir ] && mkdir $dir
[ ! -d $dir/log ] && mkdir $dir/log
[ ! -d $dir/nnet ] && mkdir $dir/nnet

##############################
#start training

# choose mlp to start with
mlp_best=$mlp_init
mlp_base=${mlp_init##*/}; mlp_base=${mlp_base%.*}
mlp_base=nnet

# cross-validation on original network
log=$dir/log/iter00.initial.log; hostname>$log
$train_tool --feature-transform=$feature_transform --cross-validate=true \
 --minibatch-size=$minibatch_size --randomizer-size=$randomizer_size --verbose=$verbose \
 "$feats_cv" "$labels_cv" $mlp_best \
 2>> $log || exit 1;

loss=$(cat $dir/log/iter00.initial.log | grep "AvgLoss:" | tail -n 1 | awk '{ print $4; }')
loss_type=$(cat $dir/log/iter00.initial.log | grep "AvgLoss:" | tail -n 1 | awk '{ print $5; }')
echo "CROSSVAL PRERUN AVG.LOSS $(printf "%.4f" $loss) $loss_type"
#Xent为交叉熵；MSE为最小均方误差；均为loss_type

# training
while [ $iter -lt $max_iters ]; do #依靠最大迭代次数控制循环上限
    
  echo -n "ITERATION $iter: "
  mlp_next=$dir/nnet/${mlp_base}_iter${iter}
  #mlp_next=exp/nnet/nnet_iter01等 
 
  #构建一个插入层
  seed=`date +%s`
  if [ $iter -gt 0 ] && \
      [ $iter -le $[($num_hidden_layers-1)*$add_layers_period] ] && \
      [ $[($iter-1) % $add_layers_period] -eq 0 ]; then #以本脚本中参数必成立，$add=1
      mlp_best="$bin_dir/nnet-initialize --seed=$seed $dir/hidden.conf - | $bin_dir/bd-nnet-insert $mlp_best - - |" 
  fi
  #在初始结构1隐层上再添加1个隐层

  # training
  log=$dir/log/iter${iter}.tr.log; hostname>$log
  $train_tool --feature-transform=$feature_transform \
   --learn-rate=$learn_rate --momentum=$momentum --l1-penalty=$l1_penalty --l2-penalty=$l2_penalty \
   --minibatch-size=$minibatch_size --randomizer-size=$randomizer_size --randomize=true --verbose=$verbose \
   --binary=true \
   --randomizer-seed=$seed \
   "$feats_tr" "$labels_tr" "$mlp_best" $mlp_next \
   2>> $log || exit 1; 
  #利用nnet-train-frmshuff进行训练，存在nnet/nnet_iter$(iter)中 


  tr_loss=$(cat $dir/log/iter${iter}.tr.log | grep "AvgLoss:" | tail -n 1 | awk '{ print $4; }')
  echo -n "TRAIN AVG.LOSS $(printf "%.4f" $tr_loss), (lrate$(printf "%.6g" $learn_rate)), "
  #获得训练集的损失和learn_rate

  # cross-validation
  log=$dir/log/iter${iter}.cv.log; hostname>$log
  $train_tool --feature-transform=$feature_transform --cross-validate=true \
   --minibatch-size=$minibatch_size --randomizer-size=$randomizer_size --verbose=$verbose \
   "$feats_cv" "$labels_cv" $mlp_next \
   2>>$log || exit 1;
  #利用nnet-train-frmshuff进行crossvaliation的集合
  
  loss_new=$(cat $dir/log/iter${iter}.cv.log | grep "AvgLoss:" | tail -n 1 | awk '{ print $4; }')
  echo -n "CROSSVAL AVG.LOSS $(printf "%.4f" $loss_new), "
  #获得交叉集的损失
  
  #train集合的loss为tr_loss;cv集合的loss为loss_new

  #判断是否接受新模型
  # accept or reject new parameters (based on objective function)
  loss_prev=$loss
  if [ $iter -le $[($num_hidden_layers-1)*$add_layers_period] ]; then #判断是否在添加隐层的阶段
      loss=$loss_new
      mlp_best=$mlp_next
      echo  "nnet accepted"
  #在加层阶段每次均将新的NN网络赋给mlp_best
  else #当不再增加层数时
      if [ "1" == "$(awk "BEGIN{print($loss_new<$loss);}")" ]; then
          loss=$loss_new
          mlp_best=$dir/nnet/${mlp_base}_iter${iter}_learnrate${learn_rate}_tr$(printf "%.4f" $tr_loss)_cv$(printf "%.4f" $loss_new)
          mv $mlp_next $mlp_best
          echo "nnet accepted"
	  #当不加层数的时候，将最新的模型$mlp_next中的转移到$mlp_best中，提供给下次迭代使用
      else
          mlp_reject=$dir/nnet/${mlp_base}_iter${iter}_learnrate${learn_rate}_tr$(printf "%.4f" $tr_loss)_cv$(printf "%.4f" $loss_new)_rejected
          mv $mlp_next $mlp_reject
          echo "nnet rejected"
      #当不加层数的时候，将最新模型$mlp_next中保存到$mlp_reject中，而$mlp_best没有修改，没有更改迭代所用模型
      fi
      # stopping criterion
      halving=0
      # start annealing when improvement is low
      if [ "1" == "$(awk "BEGIN{print(($loss_prev-$loss)/$loss_prev < $start_halving_impr)}")" ]; then #（前一次loss-本次loss）/本次loss< 阈值，则learn_rate斩半
          halving=1
          halving_count=$((halving_count+1))
      fi
  fi
   
   #判断斩半次数 
   if [ $halving_count -eq 10 ]; then
       echo "we support to stop training after adjust six times LR"
       break
   fi

   #如果$halving参数为1，对learn_rate斩半
   if [ "1" == "$halving" ]; then
       learn_rate=$(awk "BEGIN{print($learn_rate*$halving_factor)}")
   fi
  iter=$[$iter+1]
done

#本代码的过程是在插入层数的过程中不论cv集的情况一直更新参数增加层数，然后再调节参数。


# select the best network
if [ $mlp_best != $mlp_init ]; then 
  mlp_final=${mlp_best}_final_
  ( cd $dir/nnet; ln -s $(basename $mlp_best) $(basename $mlp_final); )
  ( cd $dir; ln -s nnet/$(basename $mlp_final) final.nnet; )
  echo "Succeeded training the Neural Network : $dir/final.nnet"
else
  "Error training neural network..."
  exit 1
fi



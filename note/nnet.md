# Note on Kaldi Nnet 


## Nnet1


## Nnet2


### steps/nnet2/get_egs.sh
* samples_per_ite=20000
* nnet-subset-egs
* nnet-get-egs
* nnet-copy-egs --random=$random_copy --srand=JOB
* nnet-shuffle-egs


## Nnet3
* component & component node
* Index is a tuple(n, t, x)
    splice context index [ (0, -1, 0)  (0, 0, 0)  (0, 1, 0) (1, -1, 0) (1, 0, 0) (1, 1, 0) ... ]
    shorten form, time context, and x is omited [ (0, -1:1) (1, -1:1) ... ]
* CIndex     
    -A Cindex is a pair (int32, Index), where the int32 corresponds to the index of a node in a neural networ
* ComputationGraph





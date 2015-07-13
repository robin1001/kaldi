#!/bin/env bash

input_file=wav.list
out_file=out #out.scp out.ark

pitch_feat="ark:./bd-compute-kaldi-pitch-feats --sample-frequency=8000 scp,p:${input_file} ark:- | \
./process-kaldi-pitch-feats --add-raw-log-pitch=true  ark:- ark:- |"

#if you want to show the mean var, use below command
#compute-cmvn-stats --binary=false "${pitch_feat}" mean_var.txt 

./compute-cmvn-stats "${pitch_feat}" - | \
./apply-cmvn - "${pitch_feat}" ark,scp:${out_file}.ark,${out_file}.scp
#                            ark,scp,t: for text output

echo "Done"

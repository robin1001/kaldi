# Note on HTK

## Tools
* HCopy
* HCompV 
* HLED 文本编辑，生成单因素和三因素列表
* HHED HMM Edit Tools, 修改hmm文件, sil和sp绑定，决策树
* HINIT 初始化
* HRest 初始估计, 处理HINT
* HERest 迭代重估

## HLED

## HInit
讲句子切分成音素(音素HMM)，在切分内部对该HMM做Viterbi对齐,估计参数
HInit first divides the training observation vectors equally
amongst the model states and then uses equations 1.11 and 1.12 to give initial values for the mean
and variance of each state. It then finds the maximum likelihood state sequence using the Viterbi
algorithm described below, reassigns the observation vectors to states and then uses equations 1.11
and 1.12 again to get better initial values. This process is repeated until the estimates do not
change.
```cpp
if (newModel){
    // 等分初始化
    UniformSegment();
}
totalP=LZERO;
// 迭代maxIter次
for (iter=1; !converged && iter<=maxIter; iter++){
    ZeroAccs(&hset, uFlags);              /* Clear all accumulators */
    numSegs = NumSegs(segStore);
    /* Align on each training segment and accumulate stats */
    for (newP=0.0,i=1;i<=numSegs;i++) {
        segLen = SegLength(segStore,i);
        states = CreateIntVec(&gstack,segLen);
        mixes  = (hset.hsKind==DISCRETEHS)? NULL : CreateMixes(&gstack,segLen);
        // Viterbi对齐
        newP += ViterbiAlign(i,segLen,states,mixes);
        if (trace&T_ALN) ShowAlignment(i,segLen,states,mixes);
        UpdateCounts(i,segLen,states,mixes);
        FreeIntVec(&gstack,states); /* disposes mixes too */
    }    
    /* Update parameters or quit */
    newP /= (float)numSegs;
    delta = newP - totalP;
    converged = ((iter>1) && (fabs(delta) < epsilon)) ? TRUE:FALSE;
    // 参数重估
    if (!converged)
        UpdateParameters();
    //...
}

```

## HRest
在每个HMM内，做基本EM重估, 即单HMM的基本EM算法
HRest performs basic Baum-Welch re-estimation of the parameters of a single HMM using a set
of observation sequences.
```cpp
/* ReEstimateModel: top level of algorithm */
void ReEstimateModel(void)
{
    LogFloat segProb,oldP,newP,delta;
    LogDouble ap,bp;
    int converged,iteration,seg;

    iteration=0; 
    oldP=LZERO;
    do {        /*main re-est loop*/   
        ZeroAccs(&hset, uFlags); newP = 0.0; ++iteration;
        nTokUsed = 0;
        for (seg=1;seg<=nSeg;seg++) {
            T=SegLength(segStore,seg);
            SetOutP(seg);
            if ((ap=SetAlpha(seg)) > LSMALL){
                bp = SetBeta(seg);
                if (trace & T_LGP)
                    printf("%d.  Pa = %e, Pb = %e, Diff = %e\n",seg,ap,bp,ap-bp);
                segProb = (ap + bp) / 2.0;  /* reduce numeric error */
                newP += segProb; ++nTokUsed;
                UpdateCounters(segProb,seg);
            } else
                if (trace&T_TOP) 
                    printf("Example %d skipped\n",seg);
        }
        if (nTokUsed==0)
            HError(2226,"ReEstimateModel: No Usable Training Examples");
        UpdateTheModel();
        newP /= nTokUsed;
        delta=newP-oldP; oldP=newP;
        converged=(fabs(delta)<epsilon); 
        if (trace&T_TOP) {
            printf("Ave LogProb at iter %d = %10.5f using %d examples",
                    iteration,oldP,nTokUsed);
            if (iteration > 1)
                printf("  change = %10.5f",delta);
            printf("\n");
            fflush(stdout);
        }
    } while ((iteration < maxIter) && !converged);
    
}
```
## HERest
对整句话进行前向后向对齐，重估参数。

## HLED

# Personal Kaldi Script & Program & Note

## HMM related
* hmm matlab isolated word recognition: http://sourceforge.net/projects/hmm-asr-matlab/files/temp/


## Directory details
* fanbo: for kaldi alignment and get kaldi align time
    * DONE frame accuracy(nnet-loss.cc Xent)
    * TODO alignment to triphone
* dnn_scripts
* kaldi pitch


## Kaldi program tips TODO

* DONE uint test
* TODO thread wrap
* DONE log assert
* TODO io binary
* TODO memory free

## Some Api
* ConvertStringToInteger 整数转int

## Kadli Matrix Api

### Vector
Vector and SubVector are the child class of VectorBase, and SubVector
can not change size.
* Init, Vector<BaseFloat> vec(dim)
* 置0, vec.SetZero()
* 置为某个值, vec.Set(val)
* 维度， vec.Dim()
* 访问元素 vec(i)
* 子向量 SubVector vec = vec.Range(start, len)
* 除以N vec.scale(1.0 / N)
* 向量内积 VecVec(vec1, vec2)
* 加减均用 add: vec.AddVec(1.0, vec1) sub: vec.AddVec(-1.0, vec1)
* Resize

### Matrix
Matrix and SubMatrix are the child class of MatrixBase, and SubMatrix
can not change size.
* 置0, Matrix<BaseFloat> mat(row, col)
* 置为某值，mat.SetZero()
* 维度， mat.NumRows() mat.NumCols()
* 访问元素 mat(i,j)
* 行向量 SubVector vec = vec.Row(i)
* 列向量 SubVector vec = vec.Col(i)
* 子矩阵 vec.Range(row_offset, num_rows, col_offset, num_cols)
* 子矩阵 vec.RowRange(row_offset, num_rows)
* 子矩阵 vec.ColRange(col_offset, num_cols)
* 除以N vec.scale(1.0 / N)
* Resize
* 加减: mat.AddMat(1.0, mat1); *this += alpha * M [or M^T]
* 加乘: A.AndMatMat(alpha, B, kNoTrans, C, kTrans, beta); // *this = beta* this + alpha * B * C
* 点乘: A.MulElements(B)

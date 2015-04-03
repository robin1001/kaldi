// nnetbin/bd-nnet-delete.cc


#include "base/kaldi-common.h"
#include "util/common-utils.h"
#include "nnet/nnet-nnet.h"
#include "nnet/nnet-affine-transform.h"
#include "hmm/transition-model.h"
#include "tree/context-dep.h"


int main(int argc, char *argv[]) {
  try {
    using namespace kaldi;
    using namespace kaldi::nnet1;
    typedef kaldi::int32 int32;

    const char *usage =
        "Del components in a neural network-based acoustic model.\n"
        "Usage: bd-nnet-delete 1.nnet 2.nnet\n";
    
    ParseOptions po(usage);
    
    bool binary_write = true;
    int32 del_at = -1;
    int32 del_num = 1;
    int32 del_last_num = 1;
    po.Register("binary", &binary_write, "Write output in binary mode");
    po.Register("del-at", &del_at, "Inserts new components before the "
                "specified component (note: indexes are zero-based).  If <0, "
                "inserts before the last component(typically before the softmax).");
    po.Register("del-num", &del_num, "del how many component from del_at");
    po.Register("del-last-num", &del_last_num, "del how many component from del_at");

    po.Read(argc, argv);

    if (po.NumArgs() != 2) {
      po.PrintUsage();
      exit(1);
    }

    std::string nnet_rxfilename = po.GetArg(1),
        nnet_wxfilename = po.GetArg(2);
    
    //TransitionModel trans_model;
    Nnet nnet; 
    {
      bool binary_read;
      Input ki(nnet_rxfilename, &binary_read);
      //trans_model.Read(ki.Stream(), binary_read);
      nnet.Read(ki.Stream(), binary_read);
    }


    if (del_at == -1 && del_last_num == 1) {
        nnet.RemoveLastComponent();
        KALDI_LOG << "Removed last component";
    } else if (del_at != -1 && del_last_num == 1){
        for (int32 i = 0; i < del_num; i++) {
            nnet.RemoveComponent(del_at);
            KALDI_LOG << "Removed component " << del_at;
        }
    } else {
        for (int32 i = 0; i < del_last_num; i++)
            nnet.RemoveLastComponent();
    }
    


    {
      Output ko(nnet_wxfilename, binary_write);
      //trans_model.Write(ko.Stream(), binary_write);
      nnet.Write(ko.Stream(), binary_write);
    }
    KALDI_LOG << "Write neural-net acoustic model to " <<  nnet_wxfilename;
    return 0;
  } catch(const std::exception &e) {
    std::cerr << e.what() << '\n';
    return -1;
  }
}



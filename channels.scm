(list (channel
       (name 'guix)
       (url "https://mirror.nju.edu.cn/git/guix.git")
       (branch "master")
       (commit "65816f01827a951e576ce06162d2aa8bba085bfd")
       (introduction
        (make-channel-introduction
         "9edb3f66fd807b096b48283debdcddccfea34bad"
         (openpgp-fingerprint
          "BBB0 2DDF 2CEA F6A8 0D1D  E643 A2A0 6DF2 A33A 54FA"))))
 (channel
  (name 'grove)
  (url "https://github.com/jetjinser/grove.git")
  (branch "master")
  (commit "2882e1389c9f7a9f57d5f7b5080cc93bb38b2848")
  (introduction
   (make-channel-introduction
    "59ecbbbf4659f49d6953f1de43bcc604ee456dba"
    (openpgp-fingerprint
     "CA5A 2189 12D3 CA70 E689  3FB9 0A9B 84C3 ADD0 A923")))))

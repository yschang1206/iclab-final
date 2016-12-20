#!/bin/bash

./pad_knl ../data/l0.wt.unpad ../data/l0.wt 1 0
./pad_knl ../data/l2.wt.unpad ../data/l2.wt 6 0
./pad_knl ../data/l4.wt.unpad ../data/l4.wt 16 0
./pad_knl ../data/l5.wt.unpad ../data/l5.wt 120 0

./pad_img ../data/img.dat.unpad ../data/img.dat 32 32 65536
./pad_img ../data/out0.dat.unpad ../data/out0.dat 28 28 65536
./pad_img ../data/out1.dat.unpad ../data/out1.dat 14 14 65536

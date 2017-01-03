#!/bin/bash

if [ -z "${1}" ];
then
  echo "usage: ./gen_tp [6,7]"
  exit
fi

FNAME="./img/${1}.img"
  
if [ ! -f ${FNAME} ];
then
  echo "${FNAME} not found"
  exit
fi

./lenet ${FNAME}
./pad_img ../data/unpad/img.dat.unpad ../data/img/img.dat 32 32 65536

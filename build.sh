#!/bin/bash
# gcc & g++ 4.8.5
# make 3.82

path_to_jdk7=/home/yuanyizhe/jdks/jdk1.7.0_80

export DISABLE_HOTSPOT_OS_VERSION_CHECK=ok

bear bash configure --with-boot-jdk=${path_to_jdk7} --with-jvm-variants=server --with-target-bits=64

make images JOBS=$(nproc) CONF=linux-x86_64-normal-server-release 
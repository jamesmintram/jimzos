#!/bin/bash

genext2fs -b 64 -d ./test1/ test1.img
genext2fs -b 512 -d ./test2/ test2.img
genext2fs -b 4096 -d ./test3/ test3.img

genext2fs -B 4096 -b 16 -d ./test1/ test1_4kb.img
genext2fs -B 2048 -b 256 -d ./test2/ test2_2kb.img

genext2fs -B 1024 -b 16384 -d ./test1/ test_huge.img
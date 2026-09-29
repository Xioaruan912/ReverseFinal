#!/bin/bash
B=/root/mmwx/unpacked/mmwx-unpacked
objdump -d --start-address=$1 --stop-address=$2 -M intel $B | sed -n '/>:/,$p' | tail -n +2

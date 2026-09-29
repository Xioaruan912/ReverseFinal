#!/bin/bash
B=/root/mmwx/unpacked/mmwx-unpacked
O=/root/mmwx/dis.txt
: > $O
dis(){ echo "=========== $1  ($2 - $3) ===========" | tee -a $O; objdump -d --start-address=$2 --stop-address=$3 -M intel $B | sed -n '/>:/,$p' | tail -n +2 >> $O; }
dis "(*GONo1c).HasFeature (wrapper)" 0x17b0d20 0x17b0d40
dis "(*BcGS_j).HasFeature"           0x17b4180 0x17b4460
dis "(*BcGS_j).CanUsePremiumTheme"   0x17b2f40 0x17b30e0
dis "(*BcGS_j).EffectiveServerQuota" 0x17b3280 0x17b3360
dis "(*BcGS_j).QuotaEnforced"        0x17b3180 0x17b3240
wc -l $O

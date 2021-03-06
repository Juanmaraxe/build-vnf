#! /bin/bash

echo "# Run testpmd application."
cd "$RTE_SDK/build/app" || exit

EAL_PARAMS="-l 0,1 -n 1 -m 64 \
    --file-prefix testpmd \
    --no-pci \
    --single-file-segments \
    --vdev=virtio_user2,path=/var/run/openvswitch/vhost-user3 \
    --vdev=virtio_user3,path=/var/run/openvswitch/vhost-user4
    "

TESTPMD_PARAMS="--coremask=0x02 -a --burst=1 rxq=1 --txq=1"

./testpmd $EAL_PARAMS -- $TESTPMD_PARAMS

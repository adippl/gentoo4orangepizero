setenv bootargs console=ttyS0,115200 earlyprintk root=/dev/mmcblk0p2 rootflags=compress=zstd,subvol=root rootwait panic=10
load mmc 0:1 0x43000000 ${fdtfile}
load mmc 0:1 0x42000000 uImage
bootm 0x42000000 - 0x43000000

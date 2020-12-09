#!/bin/sh
set -e 

imgSize=1G
img=img
dev=/dev/loop0
linux_dir=linux-5.4.77
mountDir=/mnt/d

mkdir -p /mnt/d

if test -z $MAKEOPTS ; then 
	MAKEOPTS="-j1"
	fi

emergeTools(){
	emerge -a1bkgn dev-embedded/u-boot-tools crossdev
	crossdev --stable -t armv7a-unknown-linux-gnueabihf
	}

img-create(){
	fallocate -l $imgSize $img
	echo ' 1024,32768,c
	,,L
	' | sfdisk ${img}
	}

u-boot-config(){
	if test -f "config-u-boot"; then
		cp config-u-boot u-boot/
	else 
		cd u-boot
		CROSS_COMPILE=armv7a-unknown-linux-gnueabihf-  make orangepi_zero_defconfig
	}

u-boot-git(){
	git clone https://github.com/u-boot/u-boot.git
	}


u-boot-compile(){
	cd u-boot
	CROSS_COMPILE=armv7a-unknown-linux-gnueabihf-  make $MAKEOPTS
	}

linux-config(){

	if test -f "config-linux"; then
		cp config-linux u-boot/
		
	else 
		cd $linux_dir
		if test -z $noclean ; then 
			LOADADDR=0x42000000 ARCH=arm CROSS_COMPILE=armv7a-unknown-linux-gnueabihf- make mrproper
			LOADADDR=0x42000000 ARCH=arm CROSS_COMPILE=armv7a-unknown-linux-gnueabihf- make clean
		fi
		
		LOADADDR=0x42000000 ARCH=arm CROSS_COMPILE=armv7a-unknown-linux-gnueabihf-  make sunxi_defconfig
	fi
	}

linux-compile(){
	cd $linux_dir
	LOADADDR=0x42000000 ARCH=arm CROSS_COMPILE=armv7a-unknown-linux-gnueabihf-  make $MAKEOPTS uImage
	cp arch/arm/boot/uImage
	ARCH=arm CROSS_COMPILE=armv7a-unknown-linux-gnueabihf- make $MAKEOPTS dtbs
	cp arch/arm/boot/dts/sun8i-h2-plus-orangepi-zero.dtb ../
	}

partition(){
	losetup $dev $img
	partx -u $dev
	mkfs.fat ${dev}p1
	mkfs.btrfs ${dev}p2
	mount ${dev}p2 -o compress=zstd /mnt/orangepi/b
	btrfs sub create /mnt/orangepi/b/root
	umount /mnt/orangepi/b
	}

loop(){
	losetup -d $dev $img
	partx -u $dev
	}

loopOff(){
	losetup -d $dev
	}

mkMountDirs(){
	mkdir -p /mnt/orangepi/a
	mkdir -p /mnt/orangepi/b
	}
imageMount(){
	mount ${dev}p1 /mnt/orangepi/a
	mount ${dev}p2 -o compress=zstd /mnt/orangepi/b
	}
imageUMount(){
	umount ${dev}p1 /mnt/orangepi/a
	umount ${dev}p2 /mnt/orangepi/b
	}

instalBoot(){
	cp boot.cmd /mnt/orangepi/a/
	cp uImage /mnt/orangepi/a/
	cp sun8i-h2-plus-orangepi-zero.dtb /mnt/orangepi/a/
	cp boot.cmd /mnt/orangepi/a/
	cp boot.scr /mnt/orangepi/a/
	}

ubootInstall(){
	dd if=./u-boot/u-boot-sunxi-with-spl.bin of=$dev bs=1024 seek=8
	}

mkbootscr(){
	mkimage -C none -A arm -T script -d boot.cmd boot.scr
	}
untar(){
	tar xpvf stage3-*.tar.xz --xattrs-include='*.*' --numeric-owner -C /mnt/orangepi/b/root/
	}

syssetup(){
	echo commenting out all getty from inittab
	sed 's/^c[1-6]/#&/' -i $mountDir/root/etc/inittab
	
	echo removeing password from root
	sed -i '/root/s/x//' $mountDir/root/etc/shadow
	
	echo setting up eth0
	cp net.eth0 $mountDir/root/etc/conf.d/
	/etc/init.d/net.lo $mountDir/root/etc/init.d/net.eth0
	ln -s /etc/init.d/net.eth0 $mountDir/root/etc/runlevels/default/net.eth0
	echo 'hostname="OPI"' > $mountDir/root/etc/conf.d/hostname
	
	echo clock and ntpd
	ln -s /etc/init.d/busybox-ntpd $mountDir/root/etc/runlevels/default/busybox-ntpd
	unlink $mountDir/root/etc/runlevels/boot/hwclock
	echo " copying host timezone config file"
	cp /etc/timezone $mountDir/root/etc/timezone
	cp /etc/localtime $mountDir/root/etc/localtime

	echo portage
	tar xJf portage-latest.tar.xz -C /mnt/d/usr/
	unlink $mountDir/root/etc/portage/make.profile
	ln -s ../../usr/portage/profiles/default/linux/arm/17.0/armv7a $mountDir/root/etc/portage/make.profile
	
	echo fstab
	echo '/dev/mmcblk0p1	/boot	vfat	noauto,noatime 1 2' > $mountDir/root/etc/fstab
	echo '/dev/mmcblk0p2	/	btrfs	compress=zstd,subvol=root 0 0' >> $mountDir/root/etc/fstab 

	echo sshd prohibit-password
	sed -i '/prohibit-password/s/\#//' $mountDir/root/ssh/sshd_config

	}

crossemerge(){
	ROOT=$mountDir/root/ PORTAGE_CONFIGROOT=$mountDir/root/ CHOST=armv7a-unknown-linux-gnueabihf CBUILD=x86_64-pc-linux-gnu emerge -j1 -a1b htop
	}

runall(){
	emergeTools
	img-create
	u-boot-git
	u-boot-config
	u-boot-compile
	mkbootscr
	linux-config
	linux-compile
	loop
	mkMountDirs
	ubootInstall
	imageMount
	instalBoot
	untar
	syssetup
	imageUMount
	}

runall

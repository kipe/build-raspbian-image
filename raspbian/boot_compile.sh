#!/bin/bash

if [ ${EUID} -ne 0 ]; then
  echo "this tool must be run as root"
  exit 1
fi

image=$1
if ! [ -f ${image} ]; then
  echo "${image} is not a file"
  exit 1
fi

if [ "${image}" == "" ]; then
	echo "no disk image given"
	exit 1
fi

set -x

base_path=`pwd`

relative_path=`dirname $0`

# locate path of this script
absolute_path=`cd ${relative_path}; pwd`

# locate path of delivery content
delivery_path=`cd ${absolute_path}/../delivery; pwd`

rootfs="${buildenv}/rootfs"
bootfs="${rootfs}/boot"

device=`kpartx -va ${image} | sed -E 's/.*(loop[0-9])p.*/\1/g' | head -1`
device="/dev/mapper/${device}"
bootp=${device}p1
rootp=${device}p2

mkdir -p ${rootfs}
mount ${rootp} ${rootfs}

mkdir -p ${rootfs}/proc
mkdir -p ${rootfs}/sys
mkdir -p ${rootfs}/dev
mkdir -p ${rootfs}/dev/pts
mkdir -p ${rootfs}/usr/src/delivery

mount -t proc none ${rootfs}/proc
mount -t sysfs none ${rootfs}/sys
mount -o bind /dev ${rootfs}/dev
mount -o bind /dev/pts ${rootfs}/dev/pts
mount -o bind ${delivery_path} ${rootfs}/usr/src/delivery

mount ${bootp} ${bootfs}

cd ${rootfs}

cp /usr/bin/qemu-arm-static usr/bin/
LANG=C chroot ${rootfs}

cd ${rootfs}

sync
sleep 1

umount -l ${bootp}

umount -l ${rootfs}/usr/src/delivery
umount -l ${rootfs}/dev/pts
umount -l ${rootfs}/dev
umount -l ${rootfs}/sys
umount -l ${rootfs}/proc

umount -l ${rootfs}
umount -l ${rootp}

cd ${base_path}

kpartx -vd ${image}

echo "done."


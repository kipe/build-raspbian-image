

# Set locale
sed 


# Setup timezone without interaction

# echo "Europe/Berlin" > /etc/timezone
# dpkg-reconfigure -f noninteractive tzdata


# resize root partion to max. size without interaction
# raspi-config --expand-rootfs



# Workflow?

mv ./build-rasbian-image.sh ./build_pi_image.sh

./build_pi_image.sh PROFIL [block device (/dev/mmcblk0)]
```
# build_pi_image.sh
#!/bin/sh

# Copyright notices
# Refactorying

export LC_ALL="C"

. ./_ERROR_CODES

# Test for run as root
if [ ${EUID} -ne 0 ]; then
	echo "${0} have to be run as root."
	echo "Abort. Error-Code: ${ERR_USER_IS_NOT_ROOT}"
	exit ${ERR_USER_IS_NOT_ROOT}
fi


. shflags-1.0.3/src/shflags

DEFINE_string 'profile' 'default' 'name of profile to apply' p
DEFINE_string 'device' '' 'path the block-device' d

FLAGS "$@" || exit $?

eval set -- "${FLAGS_ARGV}"
#echo "Profile: ${FLAGS_profile}"
#echo "Device:  ${FLAGS_device}"

# If block device was given, then test for existance
if ! [ -z "${FLAGS_device}" ]; then

	if ! [ -b "${FLAGS_device}" ]; then
		echo "${FLAGS_device} is not a block device or is not found."
		echo "Abort. Error-Code: ${ERR_BLOCK_DEVICE_IS_NOT_FOUND}"
		exit ${ERR_BLOCK_DEVICE_IS_NOT_FOUND}
	fi
	_DEVICE="${FLAGS_device}"
else
	_DEVICE=""
fi

# Test existance of profiles
if ! [ -z "${FLAGS_profile}" ]; then

	! [ -e "./profiles/${FLAGS_profile}" ] &&  exit ${ERR_PROFILE_IS_NOT_FOUND}
	_PROFIL="${FLAGS_profile}"
else
	_PROFIL="default"
fi

### Finished all esential tests
#######################################

#######################################
# Load available settings/options
source "./settings"

#######################################
# Init all variables

DEB_RELEASE=""

DEB_ARCHIV=""
DEB_MIRROR="" # TODO Have to be test if set or not?
APT_SOURCE=""
APT_SOURCE_ADDITIONAL_LIST=""

BOOT_PARTION_SIZE="" # 64 MB
FSTAB=""
HOSTNAME=""

NET_CONFIG=""

MODULES=""

KEYMAP=""
TIMEZONE=""

PI_USER=""
PI_PASS=""

DISK_OPTION=""

###

#
# Test existance of profile
# TODO If no profile was given, use default

# Set sane defaults
source "profiles/default"

# Source profil settings / Overwrite defaults
source "profiles/${PROFILE}"

###
# Prepare bootstrap env


relative_path=`dirname $0`

# locate path of this script
absolute_path=`cd ${relative_path}; pwd`

# locate path of delivery content
delivery_path=`cd ${absolute_path}/../delivery; pwd`

# define destination folder where created image file will be stored
buildenv=`cd ${absolute_path}; cd ..; mkdir -p rpi/images; cd rpi; pwd`
# buildenv="/tmp/rpi"

# cd ${absolute_path}

#DEP #bootsize="64M"
#DEP #deb_release="wheezy"


###

rootfs="${buildenv}/rootfs"
bootfs="${rootfs}/boot"

#today=`date +%Y%m%d`
_BUILD_TIME="$(date +%Y%m%d-%H%M%S)"

_IMAGE_PATH=""

# if no block device was given, create image
if [ "${_DEVICE}" == "" ]; then
	echo "no block device given, just creating an image"
	mkdir -p ${buildenv}
	### image="${buildenv}/images/raspbian_basic_${_DEB_RELEASE}_${today}.img"
	_IMAGE_PATH="${buildenv}/images/${_PROFIL}-${_BUILD_TIME}"
	dd if=/dev/zero of=${_IMAGE_PATH} bs=1MB count=1800
	_DEVICE=$(losetup -f --show ${_IMAGE_PATH})
	echo "image ${_IMAGE_PATH} created and mounted as ${_DEVICE}"
else
	dd if=/dev/zero of=${_DEVICE} bs=512 count=1
fi

# prepare block device or image-file (dd)
fdisk ${_DEVICE} << EOF
n
p
1

+${_BOOT_PARTITION_SIZE}
t
c
n
p
2


w
EOF


if [ "${_IMAGE_PATH}" != "" ]; then
  losetup -d ${_DEVICE}
  device=`kpartx -va ${_IMAGE_PATH} | sed -E 's/.*(loop[0-9])p.*/\1/g' | head -1`
  device="/dev/mapper/${_DEVICE}"
  bootp=${_DEVICE}p1
  rootp=${_DEVICE}p2
else
  if ! [ -b ${_DEVICE}1 ]; then
    bootp=${_DEVICE}p1
    rootp=${_DEVICE}p2
    if ! [ -b ${bootp} ]; then
      echo "uh, oh, something went wrong, can't find bootpartition neither as ${_DEVICE}1 nor as ${_DEVICE}p1, exiting."
      exit 1
    fi
  else
    bootp=${_DEVICE}1
    rootp=${_DEVICE}2
  fi
fi

mkfs.vfat ${bootp}
mkfs.ext4 ${rootp}

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

cd ${rootfs}





####
# debootstrap --no-check-gpg --foreign --arch armhf ${DEB_RELEASE} ${ROOTFS} ${DEB_MIRROR}
#
# mount boot partion on bootfs

debootstrap --no-check-gpg --foreign --arch armhf ${_DEB_RELEASE} ${rootfs} ${_DEB_MIRROR_LOCAL}
cp /usr/bin/qemu-arm-static usr/bin/
LANG=C chroot ${rootfs} /debootstrap/debootstrap --second-stage

mount ${bootp} ${bootfs}


# Prevent services from starting during installation.
echo "#!/bin/sh
exit 101
EOF" > usr/sbin/policy-rc.d
chmod +x usr/sbin/policy-rc.d


# write etc/apt/sources.list
_write_apt_source_list ${_FLAVOUR}

# write etc/apt/sources.list.d/*
#
# write boot/cmdline.txt
#
# write etc/fstab
#
# write etc/hostname
#
# write etc/network/interfaces
#
# write etc/modules
#
# get debconf and execute debconf-set-selections
#
# write first boot script
# generate entropy
# generate new ssh host key
# dpkg-reconfigure
#
# chmod 755 first boot script
#
# retrieve apt key and add it
# wget KEYURL -O - | apt-key add -
#
# ###
#
# apt-get install BASIC PACKAGES
# download and install pi bootloader
# apt-get -y install OTHER BASE PACKAGES
#
# apt-get -y install raspi-config
# apt-get -y install rpi-update
# apt-get -y install rng-tools
#
# install raspi-config.sh
#
# delivery dir? # wtf?!
#
# setup root user
#
# udev kernel third stage 
#
# write etc/rc.local
#
# write etc/apt/sources.list again? # TODO
#
# write cleanup
#
#
# sync
# wait
# kill process in chroot
# umount all releated
# sync
# wait
# kpartx script


### EOF build_pi_image.sh
``` 

```
### profiles/default
#!/bin/sh
# TODO Test init of variables?
```


# TODO Firstboot script must 'resize' rootfs
# 1) Expand rootfs
# 2) Create new partional from free space (First, resize rootfs to minimum + buffer)
# TODO Firstboot script must run `raspi-config`
#
#
# 09 Aug 2014 12:34
# - cache fuer firmware: download during secound stage, copy to mounted image, exucute script at third stage

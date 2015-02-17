#!/bin/bash
#set -x

# Usage:
#	./build_pi_image.sh [--profil default] [--device /dev/mmcblk0]
#
# 2014-01-24 jps3 (at) lehigh (dot) edu
# Minor cleanups to /root/firstboot.sh script.
# Debugging output added to /etc/rc.local script.
# (not necessary? still learning about Ansible!) Installs ansible via pip. 
#
# 2014-08
# Rewriting and add settings/profiles support by Bernd Naumann
#
# Modifications by
# Simon Eisenmann <simon@longsleep.org>
#
# 2014-05-25
# Updated to latest changes in Raspbian and added raspberrypi.org repository.
#
# Modifications by
# Andrius Kairiukstis <andrius@kairiukstis.com>, http://andrius.mobi/
#
# 2013-05-05
#	resulting files will be stored in rpi folder of script
#	during installation, delivery contents folder will be mounted and install.sh script within it will be called
#
# 2013-04-20
#	distro replaced from Debian Wheezy to Raspbian (http://raspbian.org)
#	build environment and resulting files not in /tmp/rpi instead of /root/rpi
#	fixed umount issue
#	keymap selection replaced from German (deadkeys) to the US
#	size of resulting image was increased to 2GB
#
#	Install apt-cacher-ng (apt-get install apt-cacher-ng) and use deb_local_mirror
#	more: https://www.unix-ag.uni-kl.de/~bloch/acng/html/config-servquick.html#config-client
#
#
#
# by Klaus M Pfeiffer, http://blog.kmp.or.at/
#
# 2012-06-24
#	just checking for how partitions are called on the system (thanks to Ricky Birtles and Luke Wilkinson)
#	using http.debian.net as debian mirror,
#	see http://rgeissert.blogspot.co.at/2012/06/introducing-httpdebiannet-debians.html
#	tested successfully in debian squeeze and wheezy VirtualBox
#	added hint for lvm2
#	added debconf-set-selections for kezboard
#	corrected bug in writing to etc/modules
#
# 2012-06-16
#	improoved handling of local debian mirror
#	added hint for dosfstools (thanks to Mike)
#	added vchiq & snd_bcm2835 to /etc/modules (thanks to Tony Jones)
#	take the value fdisk suggests for the boot partition to start (thanks to Mike)
#
# 2012-06-02
#       improoved to directly generate an image file with the help of kpartx
#	added deb_local_mirror for generating images with correct sources.list
#
# 2012-05-27
#	workaround for https://github.com/Hexxeh/rpi-update/issues/4
#	just touching /boot/start.elf before running rpi-update
#
# 2012-05-20
#	back to wheezy, http://bugs.debian.org/672851 solved,
#	http://packages.qa.debian.org/i/ifupdown/news/20120519T163909Z.html
#
# 2012-05-19
#	stage3: remove eth* from /lib/udev/rules.d/75-persistent-net-generator.rules
#	initial
#
# you need at least
# apt-get install binfmt-support qemu qemu-user-static debootstrap kpartx lvm2 dosfstools
#
###############################################################################

### Set runtime enviroment and do initial tests
##
#
export LC_ALL="C"

. ./error_codes.sh


# TODO: Implement debug and verbose option
VERBOSE=1
DEBUG=1


. shflags-1.0.3/src/shflags

set -e

# TEST: Run as root
if [ ${EUID} -ne 0 ]; then
	[ "${DEBUG}" ]		&& echo "Error: ${0} have to be run as root."
	[ "${VERBOSE}" ]	&& echo "Abort. Error-Code: ${ERR_USER_IS_NOT_ROOT}"
	exit ${ERR_USER_IS_NOT_ROOT}
fi


# TEST: Dependencies
DEPENDENCIES="binfmt-support qemu qemu-user-static debootstrap kpartx lvm2 dosfstools apt-cacher-ng"
EXIT=0
for TOOL in $DEPENDENCIES; do
	dpkg -l | grep "$TOOL" | grep "^ii" > /dev/null
	if [ $? -ne 0 ]; then
		[ "${DEBUG}" ]		&& echo "Error: Missing dependency: $TOOL"
		EXIT=1
	fi
done

if [ ${EXIT} -eq 1 ]; then
	[ "${VERBOSE}" ]		&& echo "Abort. Error-Code: ${ERR_MISSING_DEPENDENCIES}"
	exit ${ERR_MISSING_DEPENDENCIES}
fi


set +e
# Process given command line arguments and options
DEFINE_string 'profile' 'default' 'name of profile to apply' p
DEFINE_string 'device' '' 'path the block-device' d

FLAGS "$@" || exit $?

eval set -- "${FLAGS_ARGV}"

PROFILE="${FLAGS_profile}"
DEVICE="${FLAGS_device}"

#######################################

set -e
# TEST: Existance of block device, if specified

# if DEVICE is not empty
if ! [ -z "${DEVICE}" ]; then

	# if DEVICE is not a block device
	if ! [ -b "${DEVICE}" ]; then
		[ "${DEBUG}" ]		&& echo "Error: ${DEVICE} is not a block device or is not found."
		[ "${VERBOSE}" ]	&& echo "Abort. Error-Code: ${ERR_BLOCK_DEVICE_IS_NOT_FOUND}"
		exit ${ERR_BLOCK_DEVICE_IS_NOT_FOUND}
	fi

else

	DEVICE=""
fi

[ "${VERBOSE}" ] &&
	if [ "${DEVICE}" ]; then
		echo "Info: Write on device ${DEVICE}"
	else
		echo "Info: Write to disk image."
	fi

# TEST: Existance of profiles, if specified
# if PROFILE is not empty
if ! [ -z "${PROFILE}" ]; then

	# if profile file is not found
	if ! [ -e "./profiles/${PROFILE}" ]; then 
		[ "${DEBUG}" ]		&& echo "Error: ${PROFILE} was not found under ./profiles/."
		[ "${VERBOSE}" ]	&& echo "Abort. Error-Code: ${ERR_PROFILE_IS_NOT_FOUND}"
		exit ${ERR_PROFILE_IS_NOT_FOUND}
	fi

else

	PROFILE="default"
fi
[ "${VERBOSE}" ] && echo "Info: Apply settings from profile: ${PROFILE}"

### Finished all esential tests
#######################################

########################################
# Load available settings/options
. "./settings.sh"
# Overwrite variables with profile settings
. "./profiles/${PROFILE}"

#######################################
## Prepare bootstrap env

relative_path=`dirname $0`

# locate path of this script
absolute_path=`cd ${relative_path}; pwd`

# locate path of delivery content
# delivery_path=`cd ${absolute_path}/delivery; pwd`

# define destination folder where created image file will be stored
buildenv=`cd ${absolute_path}; mkdir -p rpi/images; cd rpi; pwd`
# buildenv="/tmp/rpi"

cd ${absolute_path}


rootfs="${buildenv}/rootfs"
varfs="${buildenv}/varfs"
bootfs="${rootfs}/boot"

BUILD_TIME="$(date +%Y%m%d-%H%M%S)"

IMAGE_PATH=""

# if no block device was given, create image
if [ "${DEVICE}" = "" ]; then

	mkdir -p ${buildenv}
	IMAGE_PATH="${buildenv}/images/${PROFILE}-${BUILD_TIME}.img"
	dd if=/dev/zero of=${IMAGE_PATH} bs=1MB count=2048		# TODO: Decrease value or shrink at the end
	DEVICE=$(losetup -f --show ${IMAGE_PATH})

	[ ${VERBOSE} ] && echo "Image ${IMAGE_PATH} created and mounted as ${DEVICE}."

else
	# Erease MBR of device
	dd if=/dev/zero of=${DEVICE} bs=512 count=1

	[ ${VERBOSE} ] && echo "Ereased block device ${DEVICE}."

fi

# Create partions
set +e
fdisk ${DEVICE} << EOF
n
p
1

+${_BOOT_PARTITION_SIZE}
t
c
n
p
2

+${_ROOT_PARTITION_SIZE}
n
p
3

+${_VAR_PARTITION_SIZE}
n
p


w
EOF

# Find partions on block device or in image file
if [ "${IMAGE_PATH}" != "" ]; then
	
	losetup -d ${DEVICE}
	DEVICE=`kpartx -va ${IMAGE_PATH} | sed -E 's/.*(loop[0-9])p.*/\1/g' | head -1`
	DEVICE="/dev/mapper/${DEVICE}"
	bootp=${DEVICE}p1
	rootp=${DEVICE}p2
	varp=${DEVICE}p3
	homep=${DEVICE}p4
	
else
	
	if ! [ -b ${DEVICE}1 ]; then
		bootp=${DEVICE}p1
		rootp=${DEVICE}p2
		varp=${DEVICE}p3
		homep=${DEVICE}p4
		if ! [ -b ${bootp} ]; then
			[ "${DEBUG}" ]		&& echo "Error: Can't find boot partition neither as ${DEVICE}1 nor as ${DEVICE}p1."
			[ "${VERBOSE}" ]	&& echo "Abort. Error-Code: ${ERR_NO_BOOT_PARTITION_FOUND}"
			exit ${ERR_NO_BOOT_PARTITION_FOUND}
		fi
	else
		bootp=${DEVICE}1
		rootp=${DEVICE}2
		varp=${DEVICE}3
		homep=${DEVICE}4
	fi
	
fi

mkfs.vfat ${bootp}
mkfs.ext4 ${rootp}
mkfs.ext4 ${varp}
mkfs.ext4 ${homep}

#######################################

set -e

mkdir -p ${rootfs}
mkdir -p ${varfs}

mount ${rootp} ${rootfs}
mount ${varp} ${varfs}

mkdir -p ${rootfs}/proc
mkdir -p ${rootfs}/sys
mkdir -p ${rootfs}/dev
mkdir -p ${rootfs}/dev/pts
mkdir -p ${rootfs}/var
#mkdir -p ${rootfs}/usr/src/delivery

mount -t proc none ${rootfs}/proc
mount -t sysfs none ${rootfs}/sys
mount -o bind /dev ${rootfs}/dev
mount -o bind /dev/pts ${rootfs}/dev/pts
mount -o bind ${varfs} ${rootfs}/var
#mount -o bind ${delivery_path} ${rootfs}/usr/src/delivery

cd ${rootfs}

#######################################
# Start installation of base system
#debootstrap --arch armhf --variant=minbase --no-check-gpg --foreign ${_DEB_RELEASE} ${rootfs} $(get_apt_source_mirror_url) # TODO: Research how to use in production
debootstrap --arch armhf --no-check-gpg --foreign ${_DEB_RELEASE} ${rootfs} $(get_apt_source_mirror_url)


# Complete installation process
cp /usr/bin/qemu-arm-static usr/bin/

LANG=C chroot ${rootfs} /debootstrap/debootstrap --second-stage

mount ${bootp} ${bootfs}

# Prevent services from starting during installation.
echo "#!/bin/sh
exit 101
EOF" > usr/sbin/policy-rc.d
chmod +x usr/sbin/policy-rc.d


# etc/apt/sources.list
get_apt_sources_first_stage > etc/apt/sources.list

# boot/cmdline.txt
echo "dwc_otg.lpm_enable=0 console=ttyAMA0,115200 kgdboc=ttyAMA0,115200 console=tty1 root=/dev/mmcblk0p2 rootfstype=ext4 rootwait" > boot/cmdline.txt

# etc/fstab
echo "${_FSTAB}" > etc/fstab

# etc/hostname
echo "${_HOSTNAME}" > etc/hostname


# etc/network/interfaces
set_network_config ${_NET_CONFIG}


# etc/modules
echo "vchiq
snd_bcm2835
bcm2708-rng

i2c-bcm2708
i2c-dev
" >> etc/modules

# debconf.set
echo "console-common	console-data/keymap/policy	select	Select keymap from full list
console-common	console-data/keymap/full	select	${_KEYMAP}
" > debconf.set

## Write firstboot script
echo "#!/bin/bash
#set -x
# This script will run the first time the raspberry pi boots.
# It is run as root.

function debug_msg () {
	echo \$* > /dev/kmsg
}


mount -o remount,rw /
mount -o remount,rw /boot
# Get current date from debian time server
#ntpdate 0.debian.pool.ntp.org

debug_msg  'Starting firstboot.sh'

debug_msg  'Reconfiguring openssh-server'
debug_msg  '  Collecting entropy ...'

# Drain entropy pool to get rid of stored entropy after boot.
dd if=/dev/urandom of=/dev/null bs=1024 count=10 2>/dev/null

while (( \$(cat /proc/sys/kernel/random/entropy_avail) < 200 ))
	do sleep 1
done

rm -f /etc/ssh/ssh_host_*
debug_msg  '  Generating new SSH host keys ...'
dpkg-reconfigure openssh-server
debug_msg  '  Reconfigured openssh-server'


# Set locale
export LANGUAGE=${_LOCALES}.${_ENCODING}
export LANG=${_LOCALES}.${_ENCODING}
export LC_ALL=${_LOCALES}.${_ENCODING}

cat << EOF | debconf-set-selections
locales   locales/locales_to_be_generated multiselect     ${_LOCALES}.${_ENCODING} ${_ENCODING}
EOF

rm /etc/locale.gen
dpkg-reconfigure -f noninteractive locales
update-locale LANG="${_LOCALES}.${_ENCODING}"

cat << EOF | debconf-set-selections
locales   locales/default_environment_locale select       ${_LOCALES}.${_ENCODING}
EOF

debug_msg  'Reconfigured locale'


# Set timezone
echo '${_TIMEZONE}' > /etc/timezone
dpkg-reconfigure -f noninteractive tzdata

debug_msg  'Reconfigured timezone'


# Expand filesystem
#debug_msg  'Expanding rootfs ...'
#raspi-config --expand-rootfs
#debug_msg  'Expand rootfs done'

sleep 5

reboot

" > root/firstboot.sh
chmod 755 root/firstboot.sh

######################################
# enable login on serial console
echo "T0:23:respawn:/sbin/getty -L ttyAMA0 115200 vt100" > etc/inittab
#######################################
# /boot/config.txt defaults
echo "# $(date +"%Y-%m-%d @ %H:%M:%S")
#hdmi_force_hotplug=1
gpu_mem=128
disable_overscan=1
disable_splash=1
" > boot/config.txt

#######################################
echo "#!/bin/bash
debconf-set-selections /debconf.set
rm -f /debconf.set

#cd /usr/src/delivery


apt-get update
apt-get install --reinstall language-pack-en

apt-get -y install aptitude gpgv git-core binutils ca-certificates wget curl # TODO FIXME

# adding Debian Archive Automatic Signing Key (7.0/wheezy) <ftpmaster@debian.org> to apt-keyring
gpg --keyserver pgpkeys.mit.edu --recv-key 8B48AD6246925553
gpg -a --export 8B48AD6246925553 | apt-key add -

wget -q http://archive.raspberrypi.org/debian/raspberrypi.gpg.key -O - | apt-key add -

# install telldus-core
wget -q http://download.telldus.se/debian/telldus-public.key -O- | apt-key add -
echo 'deb http://download.telldus.com/debian/ stable main' >> /etc/apt/sources.list
apt-get update

curl -L --output /usr/bin/rpi-update https://raw.github.com/Hexxeh/rpi-update/master/rpi-update && chmod +x /usr/bin/rpi-update
touch /boot/start.elf
mkdir -p /lib/modules
SKIP_BACKUP=1 /usr/bin/rpi-update

apt-get -y install ${_APT_PACKAGES} # FIXME

rm -f /etc/ssh/ssh_host_*


apt-get -y install lua5.1 triggerhappy
apt-get -y install dmsetup libdevmapper1.02.1 libparted0debian1 parted

wget http://archive.raspberrypi.org/debian/pool/main/r/raspi-config/raspi-config_20131216-1_all.deb
dpkg -i raspi-config_20131216-1_all.deb
rm -f raspi-config_20131216-1_all.deb

apt-get -y install rng-tools

#pip install ansible

# Dont start raspi-config on first login
#cp /usr/share/doc/raspi-config/sample_profile_d.sh /etc/profile.d/raspi-config.sh
#chmod 755 /etc/profile.d/raspi-config.sh

# execute install script at mounted external media (delivery contents folder)
#cd /usr/src/delivery
#./install.sh
#cd /usr/src/delivery

echo \"${_USER_NAME}:${_USER_PASS}\" | chpasswd
sed -i -e 's/KERNEL\!=\"eth\*|/KERNEL\!=\"/' /lib/udev/rules.d/75-persistent-net-generator.rules
rm -f /etc/udev/rules.d/70-persistent-net.rules
rm -f third-stage
" > third-stage
chmod +x third-stage

LANG=C chroot ${rootfs} /third-stage

###################
# Execute firstboot.sh only on first boot
echo "#!/bin/sh -e
. /lib/lsb/init-functions
if [ ! -e /root/firstboot_done ]; then
	if [ -e /root/firstboot.sh ]; then
        log_daemon_msg \"Running /root/firstboot.sh\"
		/root/firstboot.sh 2>&1 >>/root/firstboot.log
	fi
    log_daemon_msg \"Touching file flag /root/firstboot_done\"
	touch /root/firstboot_done
    log_daemon_msg \"Attempting to set ssh to start\"
    update-rc.d ssh remove && update-rc.d ssh defaults && service ssh start
fi

exit 0
" > etc/rc.local

###################
# write apt source list again
get_apt_sources_final_stage > etc/apt/sources.list

###################
# cleanup
echo "#!/bin/bash
aptitude update
aptitude clean
apt-get clean
rm -f /etc/ssl/private/ssl-cert-snakeoil.key
rm -f /etc/ssl/certs/ssl-cert-snakeoil.pem
rm -f /var/lib/urandom/random-seed
rm -f /usr/sbin/policy-rc.d
rm -f cleanup
/usr/sbin/update-rc.d ssh remove 
" > cleanup
chmod +x cleanup

LANG=C chroot ${rootfs} /cleanup

###################

cd ${rootfs}
sync
sleep 30

set +e
# Kill processes still running in chroot.
for rootpath in /proc/*/root; do
	rootlink=$(readlink $rootpath)
	if [ "x${rootlink}" != "x" ]; then
		if [ "x${rootlink:0:${#rootfs}}" = "x${rootfs}" ]; then
			# this process is in the chroot...
			PID=$(basename $(dirname "$rootpath"))
			kill -9 "$PID"
		fi
	fi
done

umount -l ${bootp}

#umount -l ${rootfs}/usr/src/delivery
umount -l ${rootfs}/dev/pts
umount -l ${rootfs}/dev
umount -l ${rootfs}/sys
umount -l ${rootfs}/proc
umount -l ${rootfs}/var

umount -l ${varfs}
umount -l ${varp}

umount -l ${rootfs}
umount -l ${rootp}

sync
sleep 5

if [ "${IMAGE_PATH}" != "" ]; then
	kpartx -vd ${IMAGE_PATH}
	[ "${VERBOSE}" ]		&& echo "Info: Created image ${IMAGE_PATH}."
    zip -j "${IMAGE_PATH#.img}.zip" "${IMAGE_PATH}"
else
	[ "${VERBOSE}" ]		&& echo "Info: Wrote to ${DEVICE}."
fi

[ "${VERBOSE}" ]		&& echo "Info: Done."

exit ${SUCCESS}


#!/usr/bin/env bash

set -euf -o pipefail

MOUNTPOINT="${MOUNTPOINT:-/mnt}"
GRAPHICAL="${GRAPHICAL:-true}"
RELEASE="${RELEASE:-buster}"
BOARD="${BOARD:-pi}"
REVISION="${REVISION:-4}"
SIZE="${3:-3G}"

if [[ $EUID -ne 0 ]]; then
	SUDO="${SUDO:-sudo}"
fi

function download_tegra_driver_package() {
	wget -c https://developer.nvidia.com/embedded/L4T/r32_Release_v4.2/t210ref_release_aarch64/Tegra210_Linux_R32.4.2_aarch64.tbz2
	# wget -c https://developer.nvidia.com/embedded/L4T/r32_Release_v4.2/t210ref_release_aarch64/Tegra_Linux_Sample-Root-Filesystem_R32.4.2_aarch64.tbz2
	mkdir -p /tmp/jetson_driver_package/
	tar xf Tegra210_Linux_R32.4.2_aarch64.tbz2 -C /tmp/jetson_driver_package/
	# tar xf Tegra_Linux_Sample-Root-Filesystem_R32.4.2_aarch64.tbz2 -C /tmp/jetson_driver_package/rootfs/
}

function create_image_jetson-nano() {

	download_tegra_driver_package

}

function finalize_image_jetson-nano() {

	$SUDO cp libjpeg-turbo-dummy_1.0_all.deb "${MOUNTPOINT}"
	$SUDO chroot "${MOUNTPOINT}" dpkg -i libjpeg-turbo-dummy_1.0_all.deb
	$SUDO rm "${MOUNTPOINT}/libjpeg-turbo-dummy_1.0_all.deb"
	$SUDO chroot "${MOUNTPOINT}" apt -f install

	(
		cd /tmp/jetson_driver_package/Linux_for_Tegra/ || exit

		sudo cp "${MOUNTPOINT}/../nv_tegra/l4t_deb_packages/nvidia-l4t-init_32.4.2-20200408182156_arm64.deb" "${MOUNTPOINT}"
		$SUDO chroot "${MOUNTPOINT}" dpkg -i --force-confnew --force-depends --force-overwrite /nvidia-l4t-init_32.4.2-20200408182156_arm64.deb
		$SUDO rm "${MOUNTPOINT}/nvidia-l4t-init_32.4.2-20200408182156_arm64.deb"

		$SUDO chroot "${MOUNTPOINT}" groupdel trusty
		$SUDO chroot "${MOUNTPOINT}" groupdel crypto

		$SUDO ./apply_binaries.sh

	)

	chroot_tear_down

	$SUDO /tmp/jetson_driver_package/Linux_for_Tegra/tools/jetson-disk-image-creator.sh -o "debian-${BOARD}.img" -b "${BOARD}" -r "$REVISION"

}

function create_image_pi() {
	if [[ -f debian-rpi64.img ]]; then
		read -p "debian-rpi64.img already exists, overwrite and start over? " -r yn
		case $yn in
		[Nn]*)
			exit
			;;
		esac
	fi
	qemu-img create debian-rpi64.img "${SIZE}"

	LOOPDEV=$($SUDO losetup -f -P --show debian-rpi64.img)

	if [[ $GRAPHICAL == true ]]; then
		$SUDO gparted "$LOOPDEV"
	else
		$SUDO fdisk "$LOOPDEV"
		$SUDO mkfs.fat -F32 -v -I -n'BOOT' "${LOOPDEV}p1"
		$SUDO mkfs.ext4 -F -O '^64bit' -L 'root' "${LOOPDEV}p2"
	fi

	$SUDO mount "${LOOPDEV}p2" "${MOUNTPOINT}"
	$SUDO mkdir -p "${MOUNTPOINT}/boot"
	$SUDO mount "${LOOPDEV}p1" "${MOUNTPOINT}/boot"

}

function finalize_image_pi() {
	# Install Pi-compatible WiFi drivers to image

	mkdir -p wifi-firmware
	(
		cd wifi-firmware || exit
		wget https://github.com/RPi-Distro/firmware-nonfree/raw/master/brcm/brcmfmac43430-sdio.bin
		wget https://github.com/RPi-Distro/firmware-nonfree/raw/master/brcm/brcmfmac43430-sdio.clm_blob
		wget https://github.com/RPi-Distro/firmware-nonfree/raw/master/brcm/brcmfmac43430-sdio.txt
		wget https://github.com/RPi-Distro/firmware-nonfree/raw/master/brcm/brcmfmac43455-sdio.bin
		wget https://github.com/RPi-Distro/firmware-nonfree/raw/master/brcm/brcmfmac43455-sdio.clm_blob
		wget https://github.com/RPi-Distro/firmware-nonfree/raw/master/brcm/brcmfmac43455-sdio.txt
		cp ./*sdio* "${MOUNTPOINT}/lib/firmware/brcm/"
	)
	rm -rf wifi-firmware

	# Remove stage2.sh from root and unmount filesystem and mount points

	rm "${MOUNTPOINT}/stage2.sh"
	chroot_tear_down
}

function base_bootstrap() {

	$SUDO qemu-debootstrap --arch=arm64 "${RELEASE}" "${MOUNTPOINT}"

	# Make internet available from within the chroot, and setup fstab, hostname, and sources.list

	$SUDO cp /etc/resolv.conf "${MOUNTPOINT}/etc/resolv.conf"
	$SUDO rm "${MOUNTPOINT}/etc/fstab"
	$SUDO rm "${MOUNTPOINT}/etc/hostname"
	$SUDO rm "${MOUNTPOINT}/etc/apt/sources.list"
	echo "proc /proc proc defaults 0 0
	/dev/mmcblk0p1 /boot vfat defaults 0 2
	/dev/mmcblk0p2 / ext4 defaults,noatime 0 1" | $SUDO tee -a "${MOUNTPOINT}/etc/fstab"

	echo "debian-rpi64" | $SUDO tee "${MOUNTPOINT}/etc/hostname"

	echo "deb http://deb.debian.org/debian/ ${RELEASE} main contrib non-free
	#deb-src http://deb.debian.org/debian/ ${RELEASE} main contrib non-free

	deb http://deb.debian.org/debian/ ${RELEASE}-updates main contrib non-free
	#deb-src http://deb.debian.org/debian/ ${RELEASE}-updates main contrib non-free

	deb http://deb.debian.org/debian-security ${RELEASE}/updates main contrib non-free
	#deb-src http://deb.debian.org/debian-security ${RELEASE}/updates main contrib non-free

	deb http://ftp.debian.org/debian ${RELEASE}-backports main
	#deb-src http://ftp.debian.org/debian ${RELEASE}-backports main" | $SUDO tee -a "${MOUNTPOINT}/etc/apt/sources.list"

}

function setup_pi() {
	# Setup bootloader and kernel

	BOOT_VERSION="1.20200212-1"
	BOOT_ARCH="armhf"

	wget -c "http://archive.raspberrypi.org/debian/pool/main/r/raspberrypi-firmware/raspberrypi-bootloader_${BOOT_VERSION}_${BOOT_ARCH}.deb"
	mkdir -p /tmp/pi-bootloader/
	dpkg-deb -x "raspberrypi-bootloader_${BOOT_VERSION}_${BOOT_ARCH}.deb" /tmp/pi-bootloader/
	$SUDO cp /tmp/pi-bootloader/boot/ "${MOUNTPOINT}/boot/"
	rm "raspberrypi-bootloader_${BOOT_VERSION}_${BOOT_ARCH}.deb"

	if [[ $1 == 4 ]]; then

		VERSION='4.19.115.20200421'
		PATCH='-bis'

		wget -c https://github.com/sakaki-/bcm2711-kernel${PATCH}/releases/download/${VERSION}/bcm2711-kernel${PATCH}-${VERSION}.tar.xz
		mkdir /tmp/pi-kernel
		tar xf bcm2711-kernel${PATCH}-${VERSION}.tar.xz -C /tmp/pi-kernel/
		$SUDO cp -r /tmp/pi-kernel/boot/ "${MOUNTPOINT}/boot/"
		$SUDO mv "${MOUNTPOINT}/boot/kernel*.img" "${MOUNTPOINT}/boot/kernel8.img"
		$SUDO mkdir "${MOUNTPOINT}/lib/modules"
		$SUDO cp -r /tmp/pi-kernel/lib/modules "${MOUNTPOINT}/lib/"
		rm bcm2711-kernel${PATCH}-${VERSION}.tar.xz
		rm -r /tmp/pi-kernel

		echo "[pi4]
    # Enable DRM VC4 V3D driver on top of the dispmanx display stack
    dtoverlay=vc4-fkms-v3d
    max_framebuffers=2
    arm_64bit=1
    # differentiate from Pi3 64-bit kernels
    kernel=kernel8-p4.img" | $SUDO tee -a "${MOUNTPOINT}/boot/config.txt"

		echo "dwc_otg.lpm_enable=0 console=ttyAMA0,115200 console=tty1 root=/dev/mmcblk0p2 rootfstype=ext4 elevator=deadline rootwait" | $SUDO tee -a "${MOUNTPOINT}/boot/cmdline.txt"

	elif [[ $1 == 3 ]]; then

		wget -c https://github.com/sakaki-/bcmrpi3-kernel/releases/download/4.19.89.20191224/bcmrpi3-kernel-4.19.89.20191224.tar.xz
		mkdir /tmp/pi-kernel
		tar xf bcmrpi3-kernel-4.19.89.20191224.tar.xz -C /tmp/pi-kernel/
		cp -r /tmp/pi-kernel/boot/ "${MOUNTPOINT}/boot/"
		mkdir "${MOUNTPOINT}/lib/modules"
		cp -r /tmp/pi-kernel/lib/modules "${MOUNTPOINT}/lib/"
		rm bcmrpi3-kernel-4.19.89.20191224.tar.xz
		rm -r /tmp/pi-kernel

		echo "dwc_otg.lpm_enable=0 console=ttyAMA0,115200 console=tty1 root=/dev/mmcblk0p2 rootfstype=ext4 elevator=deadline rootwait" | $SUDO tee -a "${MOUNTPOINT}/boot/cmdline.txt"

	fi
}

function setup_jetson-nano() {
	true
}

function chroot_prepare() {
	$SUDO mount -o bind /proc "${MOUNTPOINT}/proc"
	$SUDO mount -o bind /dev "${MOUNTPOINT}/dev"
	$SUDO mount -o bind /dev/pts "${MOUNTPOINT}/dev/pts"
	$SUDO mount -o bind /sys "${MOUNTPOINT}/sys"
}

function chroot_tear_down() {
	$SUDO umount "${MOUNTPOINT}/proc"
	$SUDO umount "${MOUNTPOINT}/sys"
	$SUDO umount "${MOUNTPOINT}/dev/pts"
	$SUDO umount "${MOUNTPOINT}/dev" -l
	$SUDO umount "${MOUNTPOINT}/boot"
	$SUDO umount "${MOUNTPOINT}" -l
}

function main() {

	"create_image_${BOARD}"

	base_bootstrap "${MOUNTPOINT}"

	"setup_${BOARD}" "${REVISION}"

	# Copy stage2 to chroot environment and execute

	$SUDO cp stage2.sh "${MOUNTPOINT}/"

	echo "Runing stage2.sh in chroot."
	chroot_prepare
	$SUDO chroot "${MOUNTPOINT}" /bin/bash /stage2.sh

	# run stage3 outside of chroot
	"finalize_image_${BOARD}"
}

set +u

([[ -n $ZSH_EVAL_CONTEXT && $ZSH_EVAL_CONTEXT =~ :file$ ]] ||
	[[ -n $BASH_VERSION ]] && (return 0 2>/dev/null)) && sourced=true || sourced=false

if $sourced; then
	echo "Script is being sourced; functions now available at the command line"
	set +euf +o pipefail
else
	set -u
	main
fi

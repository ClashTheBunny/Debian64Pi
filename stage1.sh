#!/usr/bin/env bash

shopt -s failglob
set -euf -o pipefail

MOUNTPOINT="${MOUNTPOINT:-/mnt}"
GRAPHICAL="${GRAPHICAL:-true}"
RELEASE="${RELEASE:-buster}"
BOARD="${BOARD:-pi}"
REVISION="${REVISION:-4}"
SIZE="${3:-3G}"

if [[ $EUID -ne 0 ]]; then
	SUDO="${SUDO:-sudo}"
else
  SUDO=""
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
	$SUDO chroot "${MOUNTPOINT}" dpkg -i libjpeg-turbo-dummy_1.0_all.deb || true
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
	if [[ -f "debian-${BOARD}.img" ]]; then
		read -p "debian-${BOARD}.img already exists, overwrite and start over? " -r yn
		case $yn in
		[Nn]*)
			exit
			;;
		esac
	fi
	qemu-img create "debian-${BOARD}.img" "${SIZE}"

	LOOPDEV=$($SUDO losetup -f -P --show "debian-${BOARD}.img")

	if [[ $GRAPHICAL == true ]]; then
		$SUDO gparted "$LOOPDEV"
	else
		printf "o\nn\np\n1\n\n+70M\nt\n0c\nn\np\n\n\n\n\nw\n" | $SUDO fdisk "$LOOPDEV"
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
		git clone https://github.com/RPi-Distro/firmware-nonfree
		set +f
		$SUDO cp ./firmware-nonfree/brcm/*sdio* "${MOUNTPOINT}/lib/firmware/brcm/"
		set -f
	)
	rm -rf wifi-firmware

	mkdir -p cloud-init
	(
		cd cloud-init || exit
    git clone https://gist.github.com/5c81708b05fb4f68aecba7367b3bf033.git cloud-init/
		set +f
		$SUDO cp ./cloud-init/* "${MOUNTPOINT}/boot/"
		set -f
	)
	rm -rf cloud-init


	# Remove stage2.sh from root and unmount filesystem and mount points

	$SUDO rm "${MOUNTPOINT}/stage2.sh"
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

  echo "
  allow-hotplug wlan0
  iface wlan0 inet dhcp
  wpa-conf
  iface default inet dhcp" | $SUDO tee -a "${MOUNTPOINT}/etc/network/interfaces.d/wlan0" 
}

function setup_pi() {
	# Setup bootloader and kernel

	BOOT_VERSION="1.20200902-1"
	BOOT_ARCH="armhf"

	wget -c "http://archive.raspberrypi.org/debian/pool/main/r/raspberrypi-firmware/raspberrypi-bootloader_${BOOT_VERSION}_${BOOT_ARCH}.deb"
	mkdir -p /tmp/pi-bootloader/
	dpkg-deb -x "raspberrypi-bootloader_${BOOT_VERSION}_${BOOT_ARCH}.deb" /tmp/pi-bootloader/
	$SUDO cp -r /tmp/pi-bootloader/boot/ "${MOUNTPOINT}/"
	rm "raspberrypi-bootloader_${BOOT_VERSION}_${BOOT_ARCH}.deb"


  # kernel setup
	VERSION='5.4.65.20200922'
	PATCH='-bis'

	if [[ $1 == 4 ]]; then
		KERNEL='bcm2711'
	elif [[ $1 == 3 ]]; then
		KERNEL='bcmrpi3'
  fi

	wget -c https://github.com/sakaki-/${KERNEL}-kernel${PATCH}/releases/download/${VERSION}/${KERNEL}-kernel${PATCH}-${VERSION}.tar.xz
	$SUDO tar xf ${KERNEL}-kernel${PATCH}-${VERSION}.tar.xz -C "${MOUNTPOINT}"
	set +f
	$SUDO mv "${MOUNTPOINT}"/boot/kernel*.img "${MOUNTPOINT}/boot/kernel8.img"
	set -f
	rm ${KERNEL}-kernel${PATCH}-${VERSION}.tar.xz


  # It's fine to have this on a pi3, as it will be ignored.
	echo "[pi4]
    # Enable DRM VC4 V3D driver on top of the dispmanx display stack
    dtoverlay=vc4-fkms-v3d
    max_framebuffers=2
    arm_64bit=1
    # differentiate from Pi3 64-bit kernels
    kernel=kernel8-p4.img" | $SUDO tee -a "${MOUNTPOINT}/boot/config.txt"

	echo "dwc_otg.lpm_enable=0 console=ttyAMA0,115200 console=tty1 root=/dev/mmcblk0p2 rootfstype=ext4 elevator=deadline ds=nocloud;s=/boot/ rootwait" | $SUDO tee -a "${MOUNTPOINT}/boot/cmdline.txt"


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

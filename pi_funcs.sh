#!/usr/bin/env bash

function create_image_pi() {
	if [[ -f "debian-${BOARD}.img" ]] && [[ "$CI" == "false" ]]; then
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
		printf "o\nn\np\n1\n\n+256M\nt\n0c\nn\np\n\n\n\n\nw\n" | $SUDO fdisk "$LOOPDEV"
		$SUDO mkfs.fat -F32 -v -I -n'BOOT' "${LOOPDEV}p1"
		$SUDO mkfs.ext4 -F -O '^64bit' -L 'root' "${LOOPDEV}p2"
	fi

	$SUDO mount "${LOOPDEV}p2" "${MOUNTPOINT}"
	$SUDO mkdir -p "${MOUNTPOINT}/boot"
	$SUDO mount "${LOOPDEV}p1" "${MOUNTPOINT}/boot"

}

function finalize_image_pi() {

	common_apt

	LATEST_PI_RELEASE="bookworm"
	$SUDO apt-key --keyring ${MOUNTPOINT}/usr/share/keyrings/rpi.gpg adv --keyserver keyserver.ubuntu.com --recv-keys 82B129927FA3303E

	echo "deb [arch=arm64 signed-by=/usr/share/keyrings/rpi.gpg] https://archive.raspberrypi.org/debian/ ${LATEST_PI_RELEASE} main
	#deb-src [arch=arm64 signed-by=/usr/share/keyrings/rpi.gpg] https://archive.raspberrypi.org/debian/ ${LATEST_PI_RELEASE} main" | $SUDO tee -a "${MOUNTPOINT}/etc/apt/sources.list.d/rpi.list"

	echo "# Never prefer packages from the my-custom-repo repository
	Package: *
	Pin: origin archive.raspberrypi.org
	Pin-Priority: 1

	# Allow upgrading only my-specific-software from my-custom-repo
	Package: raspberrypi-kernel raspberrypi-kernel-headers raspberrypi-bootloader rpi-eeprom
	Pin: origin archive.raspberrypi.org
	Pin-Priority: 500" | $SUDO tee -a "${MOUNTPOINT}/etc/apt/preferences.d/99-rpi"

	$SUDO chroot "${MOUNTPOINT}" apt update

	$SUDO chroot "${MOUNTPOINT}" apt install -t $LATEST_PI_RELEASE raspberrypi-kernel raspberrypi-kernel-headers raspberrypi-bootloader rpi-eeprom -y

	# Install Pi-compatible WiFi drivers to image

	mkdir -p wifi-firmware
	(
		cd wifi-firmware || exit
		git clone https://github.com/RPi-Distro/firmware-nonfree
		set +f
		cp firmware-nonfree/debian/config/brcm80211/cypress/cyfmac43455-sdio{-standard,}.bin
		$SUDO cp ./firmware-nonfree/debian/config/brcm80211/brcm/*sdio* "${MOUNTPOINT}/lib/firmware/brcm/"
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

	chroot_tear_down
}

function setup_pi() {
	# Setup bootloader config

	# It's fine to have this on a pi3, as it will be ignored.
	echo "[pi4]
		# Enable DRM VC4 V3D driver on top of the dispmanx display stack
		dtoverlay=vc4-fkms-v3d
		max_framebuffers=2
		arm_64bit=1
		# differentiate from Pi3 64-bit kernels
		kernel=kernel8-p4.img" | $SUDO tee -a "${MOUNTPOINT}/boot/config.txt"

	ROOTPARTUUID=$($SUDO blkid -s PARTUUID -o export "${LOOPDEV}p2" | grep PARTUUID)
	echo "dwc_otg.lpm_enable=0 console=ttyAMA0,115200 console=tty1 root=$ROOTPARTUUID rootfstype=ext4 elevator=deadline ds=nocloud;s=/boot/ rootwait" | $SUDO tee -a "${MOUNTPOINT}/boot/cmdline.txt"


}

# vim: noexpandtab

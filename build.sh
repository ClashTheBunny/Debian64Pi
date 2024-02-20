#!/usr/bin/env bash

shopt -s failglob
set -euf -o pipefail

MOUNTPOINT="${MOUNTPOINT:-/mnt}"
GRAPHICAL="${GRAPHICAL:-false}"
CI="${CI:-false}"
RELEASE="${RELEASE:-stable}"
BOARD="${BOARD:-pi}"
REVISION="${REVISION:-4}"
SIZE="${3:-3G}"
TEMPDIR="${TEMPDIR:-/tmp}"

if [[ $EUID -ne 0 ]]; then
	SUDO="${SUDO:-sudo}"
else
	SUDO=""
fi

function download_tegra_driver_package() {
	wget -c https://developer.nvidia.com/embedded/L4T/r32_Release_v4.2/t210ref_release_aarch64/Tegra210_Linux_R32.4.2_aarch64.tbz2
	# wget -c https://developer.nvidia.com/embedded/L4T/r32_Release_v4.2/t210ref_release_aarch64/Tegra_Linux_Sample-Root-Filesystem_R32.4.2_aarch64.tbz2
	$SUDO mkdir -p "${TEMPDIR}/jetson_driver_package/"
	$SUDO tar xf Tegra210_Linux_R32.4.2_aarch64.tbz2 -C "${TEMPDIR}/jetson_driver_package/"
	$SUDO chown root:root "${TEMPDIR}/jetson_driver_package/Linux_for_Tegra/rootfs"
}

function create_image_jetson-nano() {

	download_tegra_driver_package

}

function common_apt() {

# Apt install core packages

echo "locales locales/default_environment_locale select en_US.UTF-8
locales locales/locales_to_be_generated multiselect en_US.UTF-8 UTF-8
keyboard-configuration  keyboard-configuration/variantcode      string
keyboard-configuration  keyboard-configuration/xkb-keymap       select  us
keyboard-configuration  keyboard-configuration/toggle   select  No toggling
# Keep current keyboard options in the configuration file?
keyboard-configuration  keyboard-configuration/unsupported_config_options       boolean true
keyboard-configuration  keyboard-configuration/layoutcode       string  us
keyboard-configuration  keyboard-configuration/store_defaults_in_debconf_db     boolean true
keyboard-configuration  keyboard-configuration/switch   select  No temporary switch
keyboard-configuration  keyboard-configuration/variant  select  English (US)
# Country of origin for the keyboard:
keyboard-configuration  keyboard-configuration/layout   select
keyboard-configuration  keyboard-configuration/model    select  Generic 105-key PC (intl.)
# Keep default keyboard options ()?
keyboard-configuration  keyboard-configuration/unsupported_options      boolean true
keyboard-configuration  keyboard-configuration/ctrl_alt_bksp    boolean false
keyboard-configuration  keyboard-configuration/modelcode        string  pc105
# Keep default keyboard layout ()?
keyboard-configuration  keyboard-configuration/unsupported_layout       boolean true
# Choices: The default for the keyboard layout, No AltGr key, Right Alt (AltGr), Right Control, Right Logo key, Menu key, Left Alt, Left Logo key, Keypad Enter key, Both Logo keys, Both Alt keys
keyboard-configuration  keyboard-configuration/altgr    select  The default for the keyboard layout
# Keep the current keyboard layout in the configuration file?
keyboard-configuration  keyboard-configuration/unsupported_config_layout        boolean true
keyboard-configuration  keyboard-configuration/compose  select  No compose key
keyboard-configuration  keyboard-configuration/optionscode      string" | $SUDO chroot "${MOUNTPOINT}" debconf-set-selections

$SUDO chroot "${MOUNTPOINT}" apt update
$SUDO chroot "${MOUNTPOINT}" apt install locales -y
$SUDO chroot "${MOUNTPOINT}" apt install console-setup keyboard-configuration sudo ssh curl wget dbus usbutils ca-certificates less fbset debconf-utils avahi-daemon fake-hwclock nfs-common apt-utils man-db pciutils ntfs-3g apt-listchanges -y
$SUDO chroot "${MOUNTPOINT}" apt install wpasupplicant wireless-tools firmware-atheros firmware-brcm80211 firmware-libertas firmware-misc-nonfree firmware-realtek dhcpcd5 net-tools cloud-init chrony -y
$SUDO chroot "${MOUNTPOINT}" apt install device-tree-compiler fontconfig fontconfig-config fonts-dejavu-core libcairo2 libdatrie1 libfontconfig1 libfreetype6 libfribidi0 libgles2 libglib2.0-0 libglib2.0-data libgraphite2-3 libharfbuzz0b libpango-1.0-0 libpangoft2-1.0-0 libpixman-1-0 libpng16-16 libthai-data libthai0 libxcb-render0 libxcb-shm0 libxrender1 shared-mime-info xdg-user-dirs libdrm-common libdrm2 libegl-mesa0 libegl1 libgbm1 libglapi-mesa libglvnd0 libwayland-client0 libwayland-server0 libx11-xcb1 libxcb-dri2-0 libxcb-dri3-0 libxcb-present0 libxcb-sync1 libxcb-xfixes0 libxshmfence1 -y
}

function finalize_image_jetson-nano() {

	common_apt

	$SUDO cp libjpeg-turbo-dummy_1.0_all.deb "${MOUNTPOINT}"
	$SUDO chroot "${MOUNTPOINT}" dpkg -i libjpeg-turbo-dummy_1.0_all.deb || true
	$SUDO rm "${MOUNTPOINT}/libjpeg-turbo-dummy_1.0_all.deb"
	$SUDO chroot "${MOUNTPOINT}" apt -f install -y

	$SUDO chroot "${MOUNTPOINT}" apt install libwayland-egl1 libxkbcommon0 libasound2 libgstreamer1.0-0 libdw1 libunwind8 libasound2-data libgstreamer-plugins-bad1.0-0 libgstreamer-plugins-base1.0-0 libpangocairo-1.0-0 liborc-0.4-0 python2.7 python2.7-minimal libpython2.7-minimal libpython2.7-stdlib mime-support mailcap perl  libperl5.32 perl-modules-5.32 libgdbm-compat4 libffi-dev -y || true

	(
		cd "${TEMPDIR}/jetson_driver_package/Linux_for_Tegra" || exit

		sudo cp "nv_tegra/l4t_deb_packages/nvidia-l4t-init_32.4.2-20200408182156_arm64.deb" "${MOUNTPOINT}"
		$SUDO chroot "${MOUNTPOINT}" dpkg -i --force-confnew --force-depends --force-overwrite /nvidia-l4t-init_32.4.2-20200408182156_arm64.deb
		$SUDO rm "${MOUNTPOINT}/nvidia-l4t-init_32.4.2-20200408182156_arm64.deb"

		# $SUDO chroot "${MOUNTPOINT}" groupdel trusty
		# $SUDO chroot "${MOUNTPOINT}" groupdel crypto

		$SUDO ./apply_binaries.sh || true

	)

	chroot_tear_down

	$SUDO "${TEMPDIR}/jetson_driver_package/Linux_for_Tegra/tools/jetson-disk-image-creator.sh" -o "debian-${BOARD}.img" -b "${BOARD}" -r "$REVISION"

}

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
		printf "o\nn\np\n1\n\n+70M\nt\n0c\nn\np\n\n\n\n\nw\n" | $SUDO fdisk "$LOOPDEV"
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

function base_bootstrap() {

	$SUDO qemu-debootstrap --components=main,contrib,non-free,non-free-firmware --arch=arm64 "${RELEASE}" "${MOUNTPOINT}"

	# Make internet available from within the chroot, and setup fstab, hostname, and sources.list

	$SUDO cp /etc/resolv.conf "${MOUNTPOINT}/etc/resolv.conf"
	$SUDO rm "${MOUNTPOINT}/etc/fstab"
	$SUDO rm "${MOUNTPOINT}/etc/hostname"
	$SUDO rm "${MOUNTPOINT}/etc/apt/sources.list"
	ROOTUUID=$($SUDO blkid -s UUID -o export "${LOOPDEV}p2" | grep UUID)
	BOOTUUID=$($SUDO blkid -s UUID -o export "${LOOPDEV}p1" | grep UUID)
	echo "proc /proc proc defaults 0 0
	$BOOTUUID /boot vfat defaults 0 2
	$ROOTUUID / ext4 defaults,noatime 0 1" | $SUDO tee -a "${MOUNTPOINT}/etc/fstab"

	echo "debian-rpi64" | $SUDO tee "${MOUNTPOINT}/etc/hostname"

	echo "deb http://deb.debian.org/debian/ ${RELEASE} main contrib non-free non-free-firmware
	#deb-src http://deb.debian.org/debian/ ${RELEASE} main contrib non-free non-free-firmware " | $SUDO tee -a "${MOUNTPOINT}/etc/apt/sources.list"

	if [[ ${RELEASE} == "stable" ]]; then

		echo "deb http://deb.debian.org/debian/ ${RELEASE}-updates main contrib non-free non-free-firmware
		#deb-src http://deb.debian.org/debian/ ${RELEASE}-updates main contrib non-free non-free-firmware

		deb http://deb.debian.org/debian-security ${RELEASE}-security main contrib non-free non-free-firmware
		#deb-src http://deb.debian.org/debian-security ${RELEASE}-security main contrib non-free non-free-firmware

		deb http://deb.debian.org/debian ${RELEASE}-backports main
		#deb-src http://deb.debian.org/debian ${RELEASE}-backports main" | $SUDO tee -a "${MOUNTPOINT}/etc/apt/sources.list"

	fi

	echo "
	allow-hotplug wlan0
	iface wlan0 inet dhcp
	wpa-conf /etc/wpa_supplicant/wpa_supplicant.conf" | $SUDO tee -a "${MOUNTPOINT}/etc/network/interfaces.d/wlan0" 
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
	$SUDO umount "${MOUNTPOINT}/boot" || true
	$SUDO umount "${MOUNTPOINT}" -l || true
}

function main() {

	"create_image_${BOARD}"

	base_bootstrap "${MOUNTPOINT}"

	"setup_${BOARD}" "${REVISION}"

	chroot_prepare

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

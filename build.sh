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
$SUDO chroot "${MOUNTPOINT}" apt install wpasupplicant wireless-tools firmware-atheros firmware-brcm80211 firmware-libertas firmware-misc-nonfree firmware-realtek dhcpcd5 net-tools ssh-import-id cloud-init chrony -y
$SUDO chroot "${MOUNTPOINT}" apt install device-tree-compiler fontconfig fontconfig-config fonts-dejavu-core libcairo2 libdatrie1 libfontconfig1 libfreetype6 libfribidi0 libgles2 libglib2.0-0 libglib2.0-data libgraphite2-3 libharfbuzz0b libpango-1.0-0 libpangoft2-1.0-0 libpixman-1-0 libpng16-16 libthai-data libthai0 libxcb-render0 libxcb-shm0 libxrender1 shared-mime-info xdg-user-dirs libdrm-common libdrm2 libegl-mesa0 libegl1 libgbm1 libglapi-mesa libglvnd0 libwayland-client0 libwayland-server0 libx11-xcb1 libxcb-dri2-0 libxcb-dri3-0 libxcb-present0 libxcb-sync1 libxcb-xfixes0 libxshmfence1 -y
}

function base_bootstrap() {

	$SUDO qemu-debootstrap --components=main,contrib,non-free,non-free-firmware --arch=arm64 "${RELEASE}" "${MOUNTPOINT}"

	# Make internet available from within the chroot, and setup fstab, hostname, and sources.list

	$SUDO cp /etc/resolv.conf "${MOUNTPOINT}/etc/resolv.conf"
	$SUDO rm "${MOUNTPOINT}/etc/fstab"
	$SUDO rm "${MOUNTPOINT}/etc/hostname"
	$SUDO rm "${MOUNTPOINT}/etc/apt/sources.list"
	if [[ -v LOOPDEV ]]; then
		ROOTUUID=$($SUDO blkid -s UUID -o export "${LOOPDEV}p2" | grep UUID)
		BOOTUUID=$($SUDO blkid -s UUID -o export "${LOOPDEV}p1" | grep UUID)
	else
		ROOTUUID=/dev/mmcblk0p2
		BOOTUUID=/dev/mmcblk0p1
	fi
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
	
	source ${BOARD}_funcs.sh

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


# vim: noexpandtab

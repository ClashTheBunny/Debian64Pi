#!/usr/bin/env bash

function download_tegra_driver_package() {
	wget -c https://developer.nvidia.com/embedded/l4t/r32_release_v5.2/t210/jetson-210_linux_r32.5.2_aarch64.tbz2
	# wget -c https://developer.nvidia.com/embedded/L4T/r32_Release_v4.2/t210ref_release_aarch64/Tegra_Linux_Sample-Root-Filesystem_R32.4.2_aarch64.tbz2
	$SUDO mkdir -p "${TEMPDIR}/jetson_driver_package/"
	$SUDO tar xf jetson-210_linux_r32.5.2_aarch64.tbz2 -C "${TEMPDIR}/jetson_driver_package/"
	$SUDO chown root:root "${TEMPDIR}/jetson_driver_package/Linux_for_Tegra/rootfs"
}

function create_image_jetson-nano() {

	download_tegra_driver_package

}

function finalize_image_jetson-nano() {

	common_apt

	$SUDO cp libjpeg-turbo-dummy_1.0_all.deb "${MOUNTPOINT}"
	$SUDO chroot "${MOUNTPOINT}" dpkg -i libjpeg-turbo-dummy_1.0_all.deb || true
	$SUDO rm "${MOUNTPOINT}/libjpeg-turbo-dummy_1.0_all.deb"
	$SUDO chroot "${MOUNTPOINT}" apt -f install -y

	$SUDO chroot "${MOUNTPOINT}" apt install libwayland-egl1 libxkbcommon0 libasound2 libgstreamer1.0-0 libdw1 libunwind8 libasound2-data libgstreamer-plugins-bad1.0-0 libgstreamer-plugins-base1.0-0 libpangocairo-1.0-0 liborc-0.4-0 mime-support mailcap perl libgdbm-compat4 libffi-dev -y || true

	(
		cd "${TEMPDIR}/jetson_driver_package/Linux_for_Tegra" || exit

		sudo cp nv_tegra/l4t_deb_packages/nvidia-l4t-init_*.deb "${MOUNTPOINT}"
		$SUDO chroot "${MOUNTPOINT}" dpkg -i --force-confnew --force-depends --force-overwrite /nvidia-l4t-init_*.deb
		$SUDO rm ${MOUNTPOINT}/nvidia-l4t-init_*.deb

		# $SUDO chroot "${MOUNTPOINT}" groupdel trusty
		# $SUDO chroot "${MOUNTPOINT}" groupdel crypto

		$SUDO ./apply_binaries.sh || true

	)

	chroot_tear_down

	$SUDO "${TEMPDIR}/jetson_driver_package/Linux_for_Tegra/tools/jetson-disk-image-creator.sh" -o "debian-${BOARD}.img" -b "${BOARD}" -r "$REVISION"

}

function setup_jetson-nano() {
	true
}

# vim: noexpandtab

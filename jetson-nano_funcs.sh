#!/usr/bin/env bash

function download_tegra_driver_package() {
	wget -c https://developer.nvidia.com/embedded/l4t/r32_release_v7.1/t210/jetson-210_linux_r32.7.1_aarch64.tbz2
	# wget -c https://developer.nvidia.com/embedded/L4T/r32_Release_v4.2/t210ref_release_aarch64/Tegra_Linux_Sample-Root-Filesystem_R32.4.2_aarch64.tbz2
	$SUDO mkdir -p "${TEMPDIR}/jetson_driver_package/"
	$SUDO tar xf jetson-210_linux_r32.7.1_aarch64.tbz2 -C "${TEMPDIR}/jetson_driver_package/"
	$SUDO chown root:root "${TEMPDIR}/jetson_driver_package/Linux_for_Tegra/rootfs"
}

function create_image_jetson-nano() {

	download_tegra_driver_package

}

function finalize_image_jetson-nano() {

	common_apt

	equivs-build libjpeg-turbo8-dummy
	equivs-build libffi6-dummy
	$SUDO cp libjpeg-turbo-dummy_1.0_all.deb "${MOUNTPOINT}"
	$SUDO cp libffi6-dummy_1.0_all.deb "${MOUNTPOINT}"
	$SUDO chroot "${MOUNTPOINT}" dpkg -i libjpeg-turbo-dummy_1.0_all.deb || true
	$SUDO chroot "${MOUNTPOINT}" dpkg -i libffi6-dummy_1.0_all.deb || true
	$SUDO rm "${MOUNTPOINT}/libjpeg-turbo-dummy_1.0_all.deb"
	$SUDO rm "${MOUNTPOINT}/libffi6-dummy_1.0_all.deb"
	$SUDO chroot "${MOUNTPOINT}" apt -f install -y

	$SUDO chroot "${MOUNTPOINT}" apt install libwayland-egl1 libxkbcommon0 libasound2 libgstreamer1.0-0 libdw1 libunwind8 libasound2-data libgstreamer-plugins-bad1.0-0 libgstreamer-plugins-base1.0-0 libpangocairo-1.0-0 liborc-0.4-0 mime-support mailcap perl libpcre3 libgdbm-compat4 libffi-dev libinput10 libevdev2 libegl1-mesa libgtk-3-0 -y || true

	(
		cd "${TEMPDIR}/jetson_driver_package/Linux_for_Tegra" || exit

		for package in nvidia-l4t-3d-core nvidia-l4t-apt-source nvidia-l4t-camera nvidia-l4t-configs nvidia-l4t-core nvidia-l4t-cuda nvidia-l4t-firmware nvidia-l4t-graphics-demos nvidia-l4t-gstreamer nvidia-l4t-init nvidia-l4t-jetson-io nvidia-l4t-libvulkan nvidia-l4t-multimedia nvidia-l4t-multimedia-utils nvidia-l4t-oem-config nvidia-l4t-tools nvidia-l4t-wayland nvidia-l4t-weston nvidia-l4t-x11; do

			sudo cp "nv_tegra/l4t_deb_packages/${package}_32.7.1-20220219090432_arm64.deb" "${MOUNTPOINT}"
		done
		$SUDO chroot "${MOUNTPOINT}" bash -c "dpkg -i --force-confnew --force-depends --force-overwrite /nvidia-l4t-init*.deb"

		# $SUDO chroot "${MOUNTPOINT}" groupdel trusty
		# $SUDO chroot "${MOUNTPOINT}" groupdel crypto

		$SUDO ./apply_binaries.sh || true

	)

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

	sed -i 's#BUILD_SD_IMAGE=1#BUILD_SD_IMAGE=1 CMDLINE="ds=nocloud;s=/boot/ systemd.unified_cgroup_hierarchy=0 cgroup_enable=cpuset cgroup_enable=cpu cgroup_memory=1 cgroup_enable=memory"#g' "${TEMPDIR}/jetson_driver_package/Linux_for_Tegra/tools/jetson-disk-image-creator.sh"
	$SUDO "${TEMPDIR}/jetson_driver_package/Linux_for_Tegra/tools/jetson-disk-image-creator.sh" -o "debian-${BOARD}.img" -b "${BOARD}" -r "$REVISION"

}

function setup_jetson-nano() {
	true
}

# vim: noexpandtab

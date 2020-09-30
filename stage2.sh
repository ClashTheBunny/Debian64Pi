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
keyboard-configuration  keyboard-configuration/optionscode      string" | debconf-set-selections

apt update
apt install locales -y
apt upgrade -y
apt install console-setup keyboard-configuration sudo ssh curl wget dbus usbutils ca-certificates crda less fbset debconf-utils avahi-daemon fake-hwclock nfs-common apt-utils man-db pciutils ntfs-3g apt-listchanges -y
apt install wpasupplicant wireless-tools firmware-atheros firmware-brcm80211 firmware-libertas firmware-misc-nonfree firmware-realtek dhcpcd5 net-tools cloud-init -y
apt install device-tree-compiler fontconfig fontconfig-config fonts-dejavu-core libcairo2 libdatrie1 libfontconfig1 libfreetype6 libfribidi0 libgles2 libglib2.0-0 libglib2.0-data libgraphite2-3 libharfbuzz0b libpango-1.0-0 libpangoft2-1.0-0 libpixman-1-0 libpng16-16 libthai-data libthai0 libxcb-render0 libxcb-shm0 libxrender1 shared-mime-info xdg-user-dirs libdrm-common libdrm2 libegl-mesa0 libegl1 libgbm1 libglapi-mesa libglvnd0 libwayland-client0 libwayland-server0 libx11-xcb1 libxcb-dri2-0 libxcb-dri3-0 libxcb-present0 libxcb-sync1 libxcb-xfixes0 libxshmfence1

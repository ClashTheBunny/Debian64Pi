# Debian64Pi
64-bit Debian Buster images for the Raspberry Pi 3 and 4.

There is no 'universal' image that supports both the Pi 3 and 4, you must download the Pi 3 image to run it on a Pi 3B/B+/A+ or the Pi 4 image if you want to run it on the Pi 4B.

## Build instructions

<code>sudo ./stage1.sh</code>

By default, this script will setup the Pi 4 kernel, meaning it will not work on the Pi 3. To change it to the Pi 3, comment all the Pi 4 kernel install lines in the script and uncomment all the Pi 3 kernel install lines. This will break Pi 4 functionality however, as there is no current universal build support.

The script will setup a minimal Debian installation as well as the kernel and everything on the image. After that, you can use an image flashing tool to flash to your microSD card.

There is sample userdata in `/boot/user-data`.  You probably want to change the username, password, SSID, and WPA-PSK before you boot.  Don't worry, the boot directory shows up on every OS, so just open that with a code editor and fill in your deets.  The default is `pi:raspberry` just like the normal raspberry pi images.

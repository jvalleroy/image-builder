#!/bin/sh -e
#
# Copyright (c) 2014 Robert Nelson <robertcnelson@gmail.com>
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

export LC_ALL=C

chromium_release="chromium-32.0.1700.102"
u_boot_release="v2013.10"

#chroot_cloud9_git_tag="v2.0.93"
node_prefix="/usr"
#node_release="0.8.26"
#node_build_options="--without-snapshot --shared-openssl --shared-zlib --prefix=${node_prefix}"
node_release="0.10.25"
node_build_options="--without-snapshot --shared-cares --shared-openssl --shared-zlib --prefix=${node_prefix}"

user_name="debian"

. /.project

is_this_qemu () {
	unset warn_qemu_will_fail
	if [ -f /usr/bin/qemu-arm-static ] ; then
		warn_qemu_will_fail=1
	fi
}

qemu_warning () {
	if [ "${warn_qemu_will_fail}" ] ; then
		echo "Log: (chroot) Warning, qemu can fail here... (run on real armv7l hardware for production images)"
		echo "Log: (chroot): [${qemu_command}]"
	fi
}

git_clone () {
	mkdir -p ${git_target_dir} || true
	qemu_command="git clone ${git_repo} ${git_target_dir} --depth 1 || true"
	qemu_warning
	git clone ${git_repo} ${git_target_dir} --depth 1 || true
	sync
	echo "${git_target_dir} : ${git_repo}" >> /opt/source/list.txt
}

system_patches () {
	#For when sed/grep/etc just gets way to complex...
	cd /
	if [ -f /opt/scripts/mods/debian-add-sbin-usr-sbin-to-default-path.diff ] ; then
		patch -p1 < /opt/scripts/mods/debian-add-sbin-usr-sbin-to-default-path.diff
	fi
}

setup_capemgr () {
	echo "CAPE=cape-bone-proto" >> /etc/default/capemgr
}

setup_xorg () {
	if [ -d /etc/X11/ ] ; then
		echo "Section \"Monitor\"" > /etc/X11/xorg.conf
		echo "        Identifier      \"Builtin Default Monitor\"" >> /etc/X11/xorg.conf
		echo "EndSection" >> /etc/X11/xorg.conf
		echo "" >> /etc/X11/xorg.conf
		echo "Section \"Device\"" >> /etc/X11/xorg.conf
		echo "        Identifier      \"Builtin Default fbdev Device 0\"" >> /etc/X11/xorg.conf
		echo "        Driver          \"modesetting\"" >> /etc/X11/xorg.conf
		echo "        Option          \"SWCursor\"      \"true\"" >> /etc/X11/xorg.conf
		echo "EndSection" >> /etc/X11/xorg.conf
		echo "" >> /etc/X11/xorg.conf
		echo "Section \"Screen\"" >> /etc/X11/xorg.conf
		echo "        Identifier      \"Builtin Default fbdev Screen 0\"" >> /etc/X11/xorg.conf
		echo "        Device          \"Builtin Default fbdev Device 0\"" >> /etc/X11/xorg.conf
		echo "        Monitor         \"Builtin Default Monitor\"" >> /etc/X11/xorg.conf
		echo "        DefaultDepth    16" >> /etc/X11/xorg.conf
		echo "EndSection" >> /etc/X11/xorg.conf
		echo "" >> /etc/X11/xorg.conf
		echo "Section \"ServerLayout\"" >> /etc/X11/xorg.conf
		echo "        Identifier      \"Builtin Default Layout\"" >> /etc/X11/xorg.conf
		echo "        Screen          \"Builtin Default fbdev Screen 0\"" >> /etc/X11/xorg.conf
		echo "EndSection" >> /etc/X11/xorg.conf
	fi
}

setup_autologin () {
	if [ -f /etc/lightdm/lightdm.conf ] ; then
		sed -i -e 's:#autologin-user=:autologin-user='$user_name':g' /etc/lightdm/lightdm.conf
		sed -i -e 's:#autologin-session=UNIMPLEMENTED:autologin-session=LXDE:g' /etc/lightdm/lightdm.conf
		if [ -f /opt/scripts/3rdparty/xinput_calibrator_pointercal.sh ] ; then
			sed -i -e 's:#display-setup-script=:display-setup-script=/opt/scripts/3rdparty/xinput_calibrator_pointercal.sh:g' /etc/lightdm/lightdm.conf
		fi
	fi
}

install_desktop_branding () {
	cp /opt/scripts/images/beaglebg.jpg /opt/desktop-background.jpg

	mkdir -p /home/${user_name}/.config/pcmanfm/LXDE/ || true
	echo "[desktop]" > /home/${user_name}/.config/pcmanfm/LXDE/pcmanfm.conf
	echo "wallpaper_mode=1" >> /home/${user_name}/.config/pcmanfm/LXDE/pcmanfm.conf
	echo "wallpaper=/opt/desktop-background.jpg" >> /home/${user_name}/.config/pcmanfm/LXDE/pcmanfm.conf
	chown -R ${user_name}:${user_name} /home/${user_name}/.config/

	#Disable LXDE's screensaver on autostart
	if [ -f /etc/xdg/lxsession/LXDE/autostart ] ; then
		cat /etc/xdg/lxsession/LXDE/autostart | grep -v xscreensaver > /tmp/autostart
		mv /tmp/autostart /etc/xdg/lxsession/LXDE/autostart
		rm -rf /tmp/autostart || true
	fi
}

dogtag () {
	echo "BeagleBoard.org BeagleBone Debian Image ${time}" > /etc/dogtag
}

build_node () {
	if [ ! -d /run/shm ] ; then
		mkdir -p /run/shm
	fi

	mount -t tmpfs shmfs -o size=256M /dev/shm
	df -Th

	cd /opt/source
	wget http://nodejs.org/dist/v${node_release}/node-v${node_release}.tar.gz
	tar xf node-v${node_release}.tar.gz
	cd node-v${node_release}
	./configure ${node_build_options} && make -j5 && make install
	cd /
	rm -rf /opt/source/node-v${node_release}/ || true
	rm -rf /opt/source/node-v${node_release}.tar.gz || true
	echo "node-v${node_release} : http://rcn-ee.net/pkgs/nodejs/node-v${node_release}.tar.gz" >> /opt/source/list.txt

	echo "debug: node: [`node --version`]"
	echo "debug: npm: [`npm --version`]"

	#debug
	#echo "debug: npm config ls -l (before)"
	#echo "--------------------------------"
	#npm config ls -l
	#echo "--------------------------------"

	#fix npm in chroot.. (did i mention i hate npm...)
	npm config set cache /root/.npm
	npm config set group 0
	npm config set init-module /root/.npm-init.js
	npm config set tmp /root/tmp
	npm config set user 0
	npm config set userconfig /root/.npmrc

	#echo "debug: npm config ls -l (after)"
	#echo "--------------------------------"
	#npm config ls -l
	#echo "--------------------------------"

	echo "Installing bonescript"
	NODE_PATH=${node_prefix}/lib/node_modules/ npm install -g bonescript --arch=armhf

	if [ -d /root/tmp/ ] ; then
		rm -rf /root/tmp/ || true
	fi

	sync
	umount -l /dev/shm || true
}

install_builds () {
	cd /opt/
	wget http://rcn-ee.net/pkgs/chromium/${chromium_release}-armhf.tar.xz
	tar xf ${chromium_release}-armhf.tar.xz -C /
	rm -rf ${chromium_release}-armhf.tar.xz || true
	echo "${chromium_release} : http://rcn-ee.net/pkgs/chromium/${chromium_release}.tar.xz" >> /opt/source/list.txt

	#link Chromium to /usr/bin/x-www-browser
	update-alternatives --install /usr/bin/x-www-browser x-www-browser /usr/bin/chromium 200
}

install_repos () {
	git_repo="https://github.com/ajaxorg/cloud9.git"
	git_target_dir="/opt/cloud9"
	if [ "x${chroot_cloud9_git_tag}" = "x" ] ; then
		git_clone
	else
		mkdir -p /opt/cloud9/ || true
		qemu_command="git clone --depth 1 -b ${chroot_cloud9_git_tag} ${git_repo} ${git_target_dir} || true"
		qemu_warning
		git clone --depth 1 -b ${chroot_cloud9_git_tag} ${git_repo} ${git_target_dir} || true
		sync
		echo "${git_target_dir} : ${git_repo}" >> /opt/source/list.txt
	fi
	if [ -f ${git_target_dir}/.git/config ] ; then
		chown -R ${user_name}:${user_name} ${git_target_dir}
	fi

	#cd /opt/cloud9
	#npm install --arch=armhf

	if [ -f /var/www/index.html ] ; then
		rm -rf /var/www/index.html || true
	fi
	git_repo="https://github.com/beagleboard/bone101"
	git_target_dir="/usr/share/bone101/"
	git_clone

	git_repo="https://github.com/beagleboard/bonescript"
	git_target_dir="/var/lib/cloud9"
	git_clone
	if [ -f ${git_target_dir}/.git/config ] ; then
		chown -R ${user_name}:${user_name} ${git_target_dir}
		cd ${git_target_dir}/

		cp -v systemd/* /lib/systemd/system/
		systemctl enable bonescript.socket

		#bonescript.socket takes over port 80, so shove apache/etc to 8080:
		if [ -f /etc/apache2/ports.conf ] ; then
			sed -i -e 's:80:8080:g' /etc/apache2/ports.conf
		fi
		if [ -f /etc/apache2/sites-enabled/000-default ] ; then
			sed -i -e 's:80:8080:g' /etc/apache2/sites-enabled/000-default
		fi

		if [ ! -d ${git_target_dir}/autorun ] ; then
			mkdir -p ${git_target_dir}/autorun || true
		fi
		systemctl enable bonescript-autorun.service
	fi

	git_repo="https://github.com/jackmitch/libsoc"
	git_target_dir="/opt/source/libsoc"
	git_clone
	if [ -f ${git_target_dir}/.git/config ] ; then
		cd ${git_target_dir}/
		./autogen.sh
		./configure
		make
		make install
		make distclean
	fi

	git_repo="https://github.com/prpplague/Userspace-Arduino"
	git_target_dir="/opt/source/Userspace-Arduino"
	git_clone

	git_repo="https://github.com/tias/xinput_calibrator"
	git_target_dir="/opt/source/xinput_calibrator"
	git_clone
	if [ -f ${git_target_dir}/.git/config ] ; then
		cd ${git_target_dir}/
		git pull --no-edit https://github.com/RobertCNelson/xinput_calibrator bb.org-0.7.5-1
		./autogen.sh --with-gui=x11
		make
		make install
		make distclean
	fi

	git_repo="https://github.com/beagleboard/am335x_pru_package.git"
	git_target_dir="/opt/source/am335x_pru_package"
	git_clone
}

install_source_patches () {
	mkdir -p /opt/source/u-boot_${u_boot_release}/
	cd /opt/source/u-boot_${u_boot_release}/
	wget https://raw.github.com/RobertCNelson/Bootloader-Builder/master/patches/${u_boot_release}/0001-am335x_evm-uEnv.txt-bootz-n-fixes.patch
	cd /
	echo "u-boot_${u_boot_release} : /opt/source/u-boot_${u_boot_release}" >> /opt/source/list.txt
}

install_pip_pkgs () {
	echo "Install pip packages"

	#debian@beaglebone:~$ pip install Adafruit_BBIO
	#Downloading/unpacking Adafruit-BBIO
	#  Downloading Adafruit_BBIO-0.0.19.tar.gz
	#  Running setup.py egg_info for package Adafruit-BBIO
	#    The required version of distribute (>=0.6.45) is not available,
	#    and can't be installed while this script is running. Please
	#    install a more recent version first, using
	#    'easy_install -U distribute'.
	#
	#    (Currently using distribute 0.6.24dev-r0 (/usr/lib/python2.7/dist-packages))
	#    Complete output from command python setup.py egg_info:
	#    The required version of distribute (>=0.6.45) is not available,
	#
	#and can't be installed while this script is running. Please
	#
	#install a more recent version first, using
	#
	#'easy_install -U distribute'.
	#
	#
	#
	#(Currently using distribute 0.6.24dev-r0 (/usr/lib/python2.7/dist-packages))

	easy_install -U distribute
	pip install Adafruit_BBIO
}

unsecure_root () {
	root_password=$(cat /etc/shadow | grep root | awk -F ':' '{print $2}')
	sed -i -e 's:'$root_password'::g' /etc/shadow

	#Make ssh root@beaglebone work..
	sed -i -e 's:PermitEmptyPasswords no:PermitEmptyPasswords yes:g' /etc/ssh/sshd_config
	sed -i -e 's:UsePAM yes:UsePAM no:g' /etc/ssh/sshd_config
}

is_this_qemu
system_patches
setup_capemgr
setup_xorg
setup_autologin
install_desktop_branding
dogtag
build_node
install_builds
install_repos
install_source_patches
install_pip_pkgs
unsecure_root
#

#!/bin/sh
#what a Vagrant base box needs beyond minos, in a box made by minos' own installer (scripts/live.sh): run as
#root inside the installed system, a chroot, before its first boot. autoinstall/vagrant.yaml does the same for
#the boxes Packer makes from Ubuntu's installer; what Vagrant expects of a base box:
#https://developer.hashicorp.com/vagrant/docs/boxes/base
#usage: live-vagrant.sh USER   (the user setup created, with the password every base box has)

set -eu
user="${1:?usage: live-vagrant.sh USER}"
export DEBIAN_FRONTEND=noninteractive
_installed() { #dpkg patterns => the installed packages among them
    dpkg-query -W -f='${db:Status-Abbrev} ${Package}\n' "${@}" 2>/dev/null | awk '$1 ~ /^.i/ {print $2}'
}

#a virtual machine loads no firmware and carries no documentation, as in Ubuntu's minimized images: dpkg leaves
#them out of every package from here on (the copyright files and the wireless regulatory database stay); what
#the install already unpacked goes in scripts/box.sh
mkdir -p /etc/dpkg/dpkg.cfg.d
printf '%s\n' 'path-exclude=/lib/firmware/*' 'path-exclude=/usr/lib/firmware/*' \
    'path-include=/lib/firmware/regulatory.db*' 'path-include=/usr/lib/firmware/regulatory.db*' \
    > /etc/dpkg/dpkg.cfg.d/minos-box-firmware
printf '%s\n' 'path-exclude=/usr/share/doc/*' 'path-include=/usr/share/doc/*/copyright' \
    'path-exclude=/usr/share/info/*' > /etc/dpkg/dpkg.cfg.d/minos-box-docs
#the boxes Packer makes start from Ubuntu's minimized base, which leaves out man pages and translations (its
#/etc/dpkg/dpkg.cfg.d/excludes, copied as it is); debootstrap does not: the same rule, and what setup unpacked
#before it goes
printf '%s\n' '# Drop all man pages' 'path-exclude=/usr/share/man/*' '' '# Drop all translations' \
    'path-exclude=/usr/share/locale/*/LC_MESSAGES/*.mo' '' '# Drop all documentation ...' 'path-exclude=/usr/share/doc/*' \
    '' '# ... except copyright files ...' 'path-include=/usr/share/doc/*/copyright' '' \
    '# ... and Debian changelogs for native & non-native packages' 'path-include=/usr/share/doc/*/changelog.*' \
    > /etc/dpkg/dpkg.cfg.d/excludes
find /usr/share/man -mindepth 1 ! -type d -delete
find /usr/share/man -mindepth 1 -depth -type d -empty -delete
find /usr/share/locale -path '*/LC_MESSAGES/*.mo' -delete

#the kernel of a virtual machine, the release's own (GA): linux-image-virtual is the same name on every release,
#and it is the kernel the boxes Packer makes carry. setup installed the generic kernel of the newest hardware
#(HWE) with its firmware and headers; they go now, before the first boot, or GRUB would start the newest
apt-get update -q
apt-get install -y -q --no-install-recommends linux-image-virtual
kernel="$(dpkg-query -W -f='${Depends}' linux-image-virtual | tr ',|' '\n\n' | sed -n 's/^ *linux-image-\([0-9][^ ]*\).*/\1/p' | head -1)"
[ -n "${kernel}" ] || { printf "%s\\n" "live-vagrant: no kernel under linux-image-virtual" >&2; exit 1; }
generic="$( { _installed 'linux-generic*' 'linux-image-generic*' 'linux-headers-*' 'linux-hwe-*' 'linux-tools-*' \
        'linux-modules-extra-*' 'linux-main-modules-*' 'linux-firmware*' intel-microcode amd64-microcode thermald
    _installed 'linux-image-[0-9]*' 'linux-modules-[0-9]*' | grep -vx -e "linux-image-${kernel}" -e "linux-modules-${kernel}"
} | sort -u)" || :
if [ -n "${generic}" ]; then
    printf "live-vagrant: kernel %s; purging %s\\n" "${kernel}" "$(printf "%s " ${generic})"
    # shellcheck disable=SC2086 # a list of packages
    apt-get purge -y -q ${generic}
    apt-get autoremove -y -q --purge
fi
dpkg-query -W -f='${Status}' linux-image-virtual | grep -qx 'install ok installed'

#the user and the password every base box has, plus Vagrant's insecure public keys (RSA for Vagrant before
#2.3.8, ED25519 after), which Vagrant replaces with a key of its own on the first `vagrant up`. Over ssh only the
#keys open it: minos' libpam-captcha asks a captcha of every password login
apt-get install -y -q --no-install-recommends openssh-server
home="$(getent passwd "${user}" | cut -d: -f6)"
[ -d "${home}" ] || { printf "%s\\n" "live-vagrant: no user ${user}" >&2; exit 1; }
mkdir -p "${home}/.ssh"
printf '%s\n' \
    'ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEA6NF8iallvQVp22WDkTkyrtvp9eWW6A8YVr+kz4TjGYe7gHzIw+niNltGEFHzD8+v1I2YJ6oXevct1YeS0o9HZyN1Q9qgCgzUFtdOKLv6IedplqoPkcmF0aYet2PkEDo3MlTBckFXPITAMzF8dJSIFo9D8HfdOV0IAdx4O7PtixWKn5y2hMNG0zQPyUecp4pzC6kivAIhyfHilFR61RGL+GPXQ2MWZWFYbAGjyiYJnAmCP3NOTd0jMZEnDkbUvxhMmBYSdETk1rRgm+R4LOzFUGaHqHDLKLX+FIPKcF96hrucXzcWyLbIbEgE98OHlnVYCzRdK8jlqm8tehUc9c9WhQ== vagrant insecure public key' \
    'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN1YdxBpNlzxDqfJyw/QKow1F+wvG9hXGoqiysfJOn5Y vagrant insecure public key' \
    > "${home}/.ssh/authorized_keys"
chmod 700 "${home}/.ssh"; chmod 600 "${home}/.ssh/authorized_keys"
chown -R "${user}:${user}" "${home}/.ssh"
#vagrant runs sudo without a password
printf '%s\n' "${user} ALL=(ALL) NOPASSWD: ALL" > "/etc/sudoers.d/${user}"
chmod 440 "/etc/sudoers.d/${user}"

#the first network card is eth0 whatever the hypervisor (QEMU builds the box, VirtualBox runs it, and each
#names a card after its own slot) and takes DHCP; Vagrant configures the cards it adds itself
sed -i 's/^GRUB_CMDLINE_LINUX="/&net.ifnames=0 biosdevname=0 /' /etc/default/grub
rm -f /etc/netplan/*.yaml
printf '%s\n' 'network:' '  version: 2' '  ethernets:' '    eth0:' '      dhcp4: true' > /etc/netplan/01-eth0.yaml
chmod 600 /etc/netplan/01-eth0.yaml
#enabled as Ubuntu's installer leaves it, so network-online.target waits for the address (setup's live mode
#does the same on a system without connman)
systemctl enable systemd-networkd.service

#minos mounts /tmp as a tmpfs without exec (minos-core-settings, tmpfs module); Vagrant uploads its scripts
#there and runs them. The mount stays minos', only its options change
mkdir -p /etc/systemd/system/tmp.mount.d
printf '%s\n' '[Mount]' 'Options=defaults,noatime,nosuid,nodev,size=10%' > /etc/systemd/system/tmp.mount.d/exec.conf

#boxes travel: UTC and the us keyboard, not the country of whoever installed them (setup's live mode sets latam
#and America/Mexico_City)
sed -i -e '/^XKBLAYOUT/ s:=.*:="us":' -e '/^XKBVARIANT/ s:=.*:="":' /etc/default/keyboard
ln -fs /usr/share/zoneinfo/Etc/UTC /etc/localtime
dpkg-reconfigure -fnoninteractive tzdata

#grub-pc installs itself again on its upgrades, to the disk setup named: the loop device of the machine that
#built the box. In the box the disk is the first SATA disk VirtualBox gives an imported machine
printf '%s\n' "grub-pc grub-pc/install_devices multiselect /dev/sda" | debconf-set-selections
update-grub

#what any minos install drops, list (a): a COPY of the slimming in autoinstall/user-data's late-commands, which
#only the Packer path runs. setup's live mode now runs the same lists itself for every install (its
#_live_slim_script): with a setup that carries them this finds nothing left to purge. Ubuntu's metapackages
#may go, but what they pulled and every package of priority required, important or standard is marked manual
#first
_used() { df -m --output=used / | tail -1; }
keep="$( { apt-cache depends --recurse --installed --no-recommends --no-suggests --no-conflicts --no-breaks \
        --no-replaces --no-enhances minos-core minos-desktop 2>/dev/null | grep -v '^[ <]'
    dpkg-query -W -f='${db:Status-Abbrev} ${Priority} ${Package}\n' | awk '$1 ~ /^.i/ && $2 == "required" {print $3}'
    _installed dbus sudo openssh-server netplan.io systemd-resolved systemd-timesyncd 'grub*' 'shim*' 'linux-image-*' \
        'linux-modules-*' initramfs-tools kbd console-setup keyboard-configuration locales tzdata ca-certificates \
        dracut dracut-core ubuntu-release-upgrader-core
} | sort -u)"
ubuntu="$(_installed ubuntu-minimal ubuntu-server-minimal ubuntu-standard ubuntu-server)" || :
pulled=""
# shellcheck disable=SC2086 # a list of packages
[ -z "${ubuntu}" ] || pulled="$(dpkg-query -W -f='${Depends}, ${Pre-Depends}, ${Recommends}\n' ${ubuntu} | tr ',' '\n' |
    sed 's/[|(].*//; s/:.*//; s/ //g' | grep .)" || :
# shellcheck disable=SC2086,SC2046 # lists of packages
apt-mark manual $( { [ -z "${pulled}" ] || _installed ${pulled}; printf "%s\n" "${keep}"
    dpkg-query -W -f='${db:Status-Abbrev} ${Priority} ${Package}\n' |
        awk '$1 ~ /^.i/ && $2 ~ /^(required|important|standard)$/ {print $3}'; } | sort -u) > /dev/null
_remove() { #$1 what, then packages: purge the installed ones minos does not need, and what only they pulled
    _remove__what="${1}"; shift
    _remove__pkgs="$(_installed "${@}" | grep -vxF "${keep}")" || :
    for _remove__pkg in ${_remove__pkgs}; do
        if apt-get -s purge "${_remove__pkg}" | awk '/^Purg / {print $2}' | grep -qxF "${keep}"; then
            _remove__pkgs="$(printf "%s\n" ${_remove__pkgs} | grep -vx "${_remove__pkg}")" || :
        fi
    done
    if [ -n "${_remove__pkgs}" ]; then
        # shellcheck disable=SC2086 # a list of packages
        printf "live-vagrant: %s purges %s\\n" "${_remove__what}" "$(apt-get -s purge ${_remove__pkgs} | awk '/^Purg / {printf "%s ", $2}')"
        # shellcheck disable=SC2086
        apt-get -y -q purge ${_remove__pkgs} > /dev/null
        apt-get -y -q autoremove --purge > /dev/null
    fi
    printf "live-vagrant: %s %s\\n" "${_remove__what}" "$(_used)"
}
_remove "reports, advertising and Ubuntu Pro" apport apport-symptoms apport-core-dump-handler python3-apport \
    python3-problem-report whoopsie popularity-contest ubuntu-report landscape-common landscape-client \
    motd-news-config ubuntu-pro-client ubuntu-pro-client-l10n ubuntu-advantage-tools update-notifier-common \
    pollinate sosreport
_remove "cloud tools" cloud-guest-utils cloud-initramfs-copymods cloud-initramfs-dyn-netconf \
    ubuntu-cloudimage-keyring grub-legacy-ec2 lxd-installer lxd-agent-loader open-vm-tools open-iscsi
_remove "tools minos replaces or does not use" byobu screen eatmydata ed pastebinit run-one ltrace lshw \
    info install-info usbutils psmisc ufw uidmap hdparm laptop-detect irqbalance os-prober needrestart \
    software-properties-common python3-software-properties packagekit packagekit-tools iso-codes \
    python3-babel python-babel-localedata xdg-user-dirs shared-mime-info publicsuffix mlocate plocate \
    nano w3m ppp powermgmt-base ethtool vlan ifenslave fakeroot libc6-dev linux-libc-dev eject \
    geoip-database krb5-locales 'language-pack-*' fonts-ubuntu-console accountsservice \
    vim-tiny gawk xauth dmidecode bind9-host bind9-dnsutils dnsutils ftp tnftp inetutils-telnet telnet \
    crash kdump-tools makedumpfile bpftool manpages-dev manpages binutils binutils-common \
    'binutils-x86-64-linux-gnu' libbinutils libgprofng0 'libctf*' 'libsframe*' hwctl python3-setuptools
_remove "servers minos never wanted (app-purge)" xinetd sasl2-bin 'sendmail*' sensible-mda rmail \
    bsd-mailx 'apache2*' bind9 rpcbind postfix cifs-utils 'samba*'

printf "live-vagrant: done, %s MB used\\n" "$(_used)"

# vim: set ts=8 sw=4 tw=0 ft=sh :

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
#(HWE) with its firmware and headers; they go now, before the first boot, or GRUB would start the newest. A
#desktop keeps the release's generic kernel beside it, as the desktop boxes Packer makes do: minos-desktop
#depends on linux-image-generic (or an HWE one), and its modules-extra carry the sound drivers; box.sh keeps
#that group, which the metapackage asks for, and empties the firmware it brings
meta="minos-core"; ga="linux-image-virtual"
if [ -n "$(_installed minos-desktop)" ]; then meta="minos-desktop"; ga="linux-image-virtual linux-image-generic"; fi
[ -n "$(_installed "${meta}")" ] || { printf "%s\\n" "live-vagrant: ${meta} is not installed" >&2; exit 1; }
apt-get update -q
# shellcheck disable=SC2086 # a list of packages
apt-get install -y -q --no-install-recommends ${ga}
kernel="$(dpkg-query -W -f='${Depends}' linux-image-virtual | tr ',|' '\n\n' | sed -n 's/^ *linux-image-\([0-9][^ ]*\).*/\1/p' | head -1)"
[ -n "${kernel}" ] || { printf "%s\\n" "live-vagrant: no kernel under linux-image-virtual" >&2; exit 1; }
#what the GA kernel's metapackages need stays; every other kernel package goes, with its headers, tools and
#firmware (apt never removes a kernel image or linux-firmware on its own)
# shellcheck disable=SC2086 # a list of packages
stays="$(apt-cache depends --recurse --installed --no-recommends --no-suggests --no-conflicts --no-breaks \
    --no-replaces --no-enhances ${ga} | grep -v '^[ <]' | sort -u)"
generic="$(_installed 'linux-generic*' 'linux-image-generic*' 'linux-headers-*' 'linux-hwe-*' 'linux-tools-*' \
        'linux-modules-extra-*' 'linux-main-modules-*' 'linux-firmware*' intel-microcode amd64-microcode thermald \
        'linux-image-[0-9]*' 'linux-modules-[0-9]*' | sort -u | grep -vxF "${stays}")" || :
if [ -n "${generic}" ]; then
    # shellcheck disable=SC2086 # a list of packages
    gone="$(apt-get -s purge ${generic} | awk '/^Purg / {print $2}')"
    if printf "%s\\n" "${gone}" | grep -qx -e "${meta}" -e 'linux-image-virtual' -e 'linux-image-generic'; then
        printf "%s\\n" "live-vagrant: purging the other kernels would take $(printf "%s\\n" "${gone}" | grep -x -e "${meta}" -e 'linux-image-virtual' -e 'linux-image-generic' | tr '\n' ' ')" >&2
        exit 1
    fi
    printf "live-vagrant: kernel %s (%s); purging %s\\n" "${kernel}" "${ga}" "$(printf "%s " ${generic})"
    # shellcheck disable=SC2086 # a list of packages
    apt-get purge -y -q ${generic}
    apt-get autoremove -y -q --purge
fi
for package in ${meta} ${ga}; do
    dpkg-query -W -f='${Status}' "${package}" | grep -qx 'install ok installed' ||
        { printf "%s\\n" "live-vagrant: ${package} is gone after the kernel step" >&2; exit 1; }
done

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

#grub-pc installs itself again on its upgrades, to the disk setup named: the loop device of the machine that
#built the box. In the box the disk is the first SATA disk VirtualBox gives an imported machine
printf '%s\n' "grub-pc grub-pc/install_devices multiselect /dev/sda" | debconf-set-selections
update-grub

#what any minos install drops (list (a) of autoinstall/user-data) setup's live mode purged itself, with the
#services debootstrap brings that no minos package asks for (its _live_slim_script)
_used() { df -m --output=used / | tail -1; }
printf "live-vagrant: done, %s MB used\\n" "$(_used)"

# vim: set ts=8 sw=4 tw=0 ft=sh :

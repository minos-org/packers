#!/bin/sh
#the last steps of a minos Vagrant box, as root on its first boot (packers/minos.pkr.hcl): what the
#install left that a box must not carry, the owner's commands for the vagrant user, and the free space
#handed back so the exported disk holds only what is written

set -eu

#origin bench (autoinstall/bench.yaml): the bench's packages and the hook that pointed setup at them
rm -rf /var/cache/minos-bench /etc/apt/sources.list.d/bench.list /root/.minos/hooks/A01-bench-repository
for dir in /root/.minos/hooks /root/.minos; do
    if [ -d "${dir}" ] && [ -z "$(ls -A "${dir}")" ]; then rmdir "${dir}"; fi
done

#the owner's plugins (vim, tmux, shundle) reach a user through the postinst of the settings packages, for
#the users it finds. On 22.04 the installer's user is created on the first boot, after minos went in (on
#24.04 and 26.04 during the install, and the install log says so): configuring the settings packages
#again gives vagrant what a user present at the install gets. It needs the network. A user created later
#gets them on its first login (minos-core-settings, /etc/profile.d/minos-user-plugins.sh), but a box comes
#with them: the first vagrant ssh neither waits for the clones nor needs the network
if ! grep -q "installing vagrant's vim plugins" /var/log/minos-setup.log; then
    for package in minos-core-settings minos-desktop-settings; do
        if dpkg-query -W -f='${Status}' "${package}" 2>/dev/null | grep -qx 'install ok installed'; then
            DEBIAN_FRONTEND=noninteractive dpkg-reconfigure -fnoninteractive "${package}" >/dev/null
        fi
    done
fi

_used() { #MB in use on the root filesystem
    df -m --output=used / | tail -1
}

_installed() { #dpkg patterns => the installed packages among them
    dpkg-query -W -f='${db:Status-Abbrev} ${Package}\n' "${@}" 2>/dev/null | awk '$1 ~ /^.i/ {print $2}'
}

#what stays whatever a list says: minos and its dependencies (on desktop the generic kernel and its
#firmware), Ubuntu's required packages, the running kernel and what reaches and runs the box
keep="$( { apt-cache depends --recurse --installed --no-recommends --no-suggests --no-conflicts --no-breaks \
        --no-replaces --no-enhances $(_installed minos-core minos-desktop) | grep -v '^[ <]'
    dpkg-query -W -f='${db:Status-Abbrev} ${Priority} ${Package}\n' | awk '$1 ~ /^.i/ && $2 == "required" {print $3}'
    _installed dbus sudo openssh-server netplan.io systemd-resolved systemd-timesyncd 'grub*' initramfs-tools \
        dracut dracut-core ubuntu-release-upgrader-core \
        linux-image-virtual "linux-image-$(uname -r)" "linux-modules-$(uname -r)" kbd console-setup \
        keyboard-configuration locales tzdata ca-certificates
} | sort -u)"
#on a desktop the list holds dbus-user-session, systemd's per-user bus, as one provider of the session bus
#dconf-service asks for (default-dbus-session-bus | dbus-session-bus). The other is dbus-x11, which
#minos-desktop depends on, and it is the one minos' desktop runs: slim starts /etc/X11/Xsession, whose
#75dbus_dbus-launch gives the X session a bus of its own. dbus-user-session goes below
keep="$(printf "%s\n" "${keep}" | grep -vx dbus-user-session)"
#an autoremove takes what nothing manual needs any more (netplan.io once cloud-init goes): what stays is manual
# shellcheck disable=SC2086 # a list of packages
apt-mark manual ${keep} >/dev/null

_remove() { #$1 what, then packages (dpkg patterns): purge the installed ones the box does not need, and
            #what only they pulled; one whose removal would take something kept stays
    _remove__what="${1}"; shift
    #no names at all: dpkg-query would list every package
    if [ "${#}" -eq 0 ]; then printf "slim: %s: none\n" "${_remove__what}"; return 0; fi
    _remove__pkgs="$(_installed "${@}" | grep -vxF "${keep}")" || :
    for _remove__pkg in ${_remove__pkgs}; do
        if apt-get -s purge "${_remove__pkg}" | awk '/^Purg / {print $2}' | grep -qxF "${keep}"; then
            printf "slim: %s: %s kept, the box needs it or what goes with it\n" "${_remove__what}" "${_remove__pkg}"
            _remove__pkgs="$(printf "%s\n" ${_remove__pkgs} | grep -vx "${_remove__pkg}")" || :
        fi
    done
    if [ -n "${_remove__pkgs}" ]; then
        # shellcheck disable=SC2086 # a list of packages
        printf "slim: %s purges %s\n" "${_remove__what}" "$(apt-get -s purge ${_remove__pkgs} | awk '/^Purg / {printf "%s ", $2}')"
        # shellcheck disable=SC2086
        DEBIAN_FRONTEND=noninteractive apt-get -y -q purge ${_remove__pkgs} >/dev/null
        DEBIAN_FRONTEND=noninteractive apt-get -y -q autoremove --purge >/dev/null
    fi
    printf "slim: %s %s\n" "${_remove__what}" "$(_used)"
}

printf "slim: first boot %s\n" "$(_used)"
#a desktop keeps its sound and the kernel's wireless stack (owner); the core boxes do not
desktop=""
if dpkg-query -W -f='${Status}' minos-desktop 2>/dev/null | grep -qx 'install ok installed'; then desktop="yes"; fi

#a virtual machine needs neither the kernel for real hardware nor its headers, firmware or CPU microcode
#(the host loads that). From 26.04 on the minimal image comes with the generic kernel, its headers and
#tools and every firmware package, and the virtual kernel (vagrant.yaml) lands beside them. They are
#named one by one: apt never removes a kernel image, linux-firmware or the running kernel's packages on
#its own (/etc/apt/apt.conf.d/01autoremove*). A group a metapackage asks for stays: minos-desktop wants
#the generic kernel, for zram, and with it the firmware and the microcode
_remove "kernel headers and tools" linux-generic linux-headers-generic linux-tools-generic 'linux-headers-*' \
    'linux-tools-*' linux-perf
_remove "generic kernel, firmware, microcode" linux-image-generic 'linux-modules-extra-*' 'linux-firmware*' \
    intel-microcode amd64-microcode
_remove "sound firmware" firmware-sof-signed
#the firmware files the image brought before dpkg was told to leave them out (vagrant.yaml); the packages
#a metapackage asks for stay installed, empty
if [ -d /usr/lib/firmware ]; then find /usr/lib/firmware -mindepth 1 ! -name 'regulatory.db*' -delete; fi
printf "slim: firmware files %s\n" "$(_used)"
#one ext4 partition, no disk encryption, no RAID, no LVM (vagrant.yaml): the tools for the others
_remove "storage the box does not use" lvm2 cryptsetup cryptsetup-bin cryptsetup-initramfs mdadm \
    multipath-tools thin-provisioning-tools bcache-tools xfsprogs btrfs-progs dosfstools gdisk parted
#no radio, no disk health, no firmware updates, no power or thermal management in a virtual machine
# shellcheck disable=SC2046 # the desktop keeps the database its wireless stack reads
_remove "hardware the box does not have" wpasupplicant iw $([ -n "${desktop}" ] || echo wireless-regdb) crda fwupd fwupd-signed \
    smartmontools nvme-cli thermald usb-modeswitch 'bluez*'
#the packages of a kernel other than the one running; apt keeps the previous kernel on purpose
running="$(uname -r)"
# shellcheck disable=SC2046 # a list of packages
_remove "older kernels" $(dpkg-query -W -f='${db:Status-Abbrev} ${Package}\n' 'linux-*' | awk '$1 ~ /^.i/ {print $2}' |
    grep -E -- '-[0-9]+\.[0-9]+\.[0-9]+-[0-9]+(-generic)?$' | grep -v -- "-${running%-generic}")
dpkg-query -W -f='${Status}' linux-image-virtual | grep -qx 'install ok installed'

#the drivers of hardware a VirtualBox or KVM guest never has (sound, cameras and TV, sensors, physical
#graphics and network cards) leave the box's kernel: dpkg leaves them out of every kernel the box gets
#from now on, and the ones installed go now. What a guest uses stays: virtio, e1000/e1000e, ahci, sd_mod,
#the filesystems, netfilter, zram, vboxguest/vboxsf/vboxvideo, vmwgfx (VirtualBox's VMSVGA), and from
#drivers/media the CEC core and the remote control core it links against (rc, with the IR receivers and
#keymaps the generic kernel puts beside it): up to 22.04's kernel (5.15) drm_kms_helper links against
#CEC, and without them no graphics driver loads (bochs, vmwgfx, vboxvideo), so X has no screen
excludes=/etc/dpkg/dpkg.cfg.d/minos-box-modules
: > "${excludes}"
_trim() { #$1 what, then directories under a kernel's kernel/; keep:DIR keeps one of their subdirectories
    _trim__what="${1}"; shift
    _trim__keep=""
    for _trim__dir; do
        case "${_trim__dir}" in
            keep:*) _trim__keep="${_trim__keep} ${_trim__dir#keep:}" ;;
            *) printf 'path-exclude=%s/*/kernel/%s/*\n' /lib/modules "${_trim__dir}" /usr/lib/modules "${_trim__dir}" >> "${excludes}" ;;
        esac
    done
    for _trim__dir in ${_trim__keep}; do #dpkg: the last pattern that matches decides
        printf 'path-include=%s/*/kernel/%s/*\n' /lib/modules "${_trim__dir}" /usr/lib/modules "${_trim__dir}" >> "${excludes}"
    done
    for _trim__kernel in /lib/modules/*/kernel; do
        for _trim__dir in ${_trim__keep}; do
            if [ -d "${_trim__kernel}/${_trim__dir}" ]; then
                mkdir -p "/var/tmp/minos-keep/${_trim__dir%/*}" && mv "${_trim__kernel}/${_trim__dir}" "/var/tmp/minos-keep/${_trim__dir}"
            fi
        done
        for _trim__dir; do
            case "${_trim__dir}" in keep:*) continue ;; esac
            rm -rf "${_trim__kernel:?}/${_trim__dir}"
        done
        for _trim__dir in ${_trim__keep}; do
            if [ -d "/var/tmp/minos-keep/${_trim__dir}" ]; then
                mkdir -p "${_trim__kernel}/${_trim__dir%/*}" && mv "/var/tmp/minos-keep/${_trim__dir}" "${_trim__kernel}/${_trim__dir}"
            fi
        done
    done
    rm -rf /var/tmp/minos-keep
    printf "slim: kernel modules, %s %s\n" "${_trim__what}" "$(_used)"
}
[ -n "${desktop}" ] || _trim "sound" sound
_trim "cameras and TV" drivers/media keep:drivers/media/cec/core keep:drivers/media/rc
_trim "sensors" drivers/iio
_trim "physical graphics cards" drivers/gpu/drm/amd drivers/gpu/drm/radeon drivers/gpu/drm/nouveau \
    drivers/gpu/drm/i915 drivers/gpu/drm/xe drivers/gpu/drm/gma500 drivers/gpu/drm/mgag200 drivers/gpu/drm/ast
#the kernel's wireless stack (cfg80211, mac80211) goes with them in the core boxes; the desktop keeps it
wireless=""
[ -n "${desktop}" ] || wireless="net/wireless net/mac80211"
# shellcheck disable=SC2086 # a list of directories
_trim "physical network cards" drivers/net/ethernet drivers/net/wireless ${wireless} drivers/net/wwan drivers/net/can \
    drivers/net/usb drivers/net/ieee802154 drivers/net/hamradio drivers/net/arcnet drivers/net/fddi drivers/net/wan \
    keep:drivers/net/ethernet/intel/e1000 keep:drivers/net/ethernet/intel/e1000e
for kernel in /lib/modules/*; do depmod -a "${kernel##*/}"; done

#what any minos install drops (list (a), autoinstall/user-data) but only after the first boot: up to 24.04
#cloud-init creates the user then, and only a running snapd removes its snaps. The snaps the 26.04 image
#comes with installed (core24, hwctl, snapd) go first: applications, then their bases, then snapd itself
if command -v snap >/dev/null 2>&1; then
    snap wait system seed.loaded
    snaps="$(snap list 2>/dev/null | awk 'NR > 1 {print $1}')"
    # shellcheck disable=SC2086 # a list of snaps
    for name in $(printf "%s\n" ${snaps} | grep -v -x -e snapd -e 'core[0-9]*') \
                $(printf "%s\n" ${snaps} | grep -x 'core[0-9]*') $(printf "%s\n" ${snaps} | grep -x snapd); do
        snap remove --purge "${name}" >/dev/null
    done
    printf "slim: installed snaps %s\n" "$(_used)"
fi
_remove "cloud-init, snapd and their confinement" cloud-init snapd squashfs-tools apparmor
#what Ubuntu's server seed brings that no minos package asks for, and that runs on its own, idle: automatic
#upgrades (a python process waiting all along for the shutdown, 27 MB), networkd's hook runner, and
#systemd's per-user bus (a dbus-daemon for each login, an ssh one too; a desktop's bus is dbus-x11's,
#above). The installer marks them manual, so no autoremove takes them
_remove "services no minos package asks for" unattended-upgrades networkd-dispatcher dbus-user-session
#polkit tells a service whether a user may do what only root does: minos-desktop asks for it (udisks2, the
#mounts pcmanfm makes through gvfs). In a core box nothing depends on it (systemd and systemd-resolved only
#suggest it): the installer's layer brought it
[ -n "${desktop}" ] || _remove "polkit, on core" polkitd pkexec policykit-1

#the documentation unpacked before dpkg was told to leave it out (vagrant.yaml): the copyright files stay
find /usr/share/doc -mindepth 1 ! -type d ! -name copyright -delete
find /usr/share/doc -mindepth 1 -depth -type d -empty -delete
printf "slim: documentation %s\n" "$(_used)"
rm -rf /usr/share/info/*
printf "slim: info pages %s\n" "$(_used)"

#what reaches and runs the box after all that: a missing one fails the build here, not on the next boot
for command in netplan sshd sudo; do
    command -v "${command}" >/dev/null 2>&1 || { printf "%s\n" "box.sh: ${command} is gone after the slimming" >&2; exit 1; }
done

#the mirror the installer fetched from (minos.pkr.hcl's mirror, on a GitHub-hosted runner its cloud's): a
#box reads the Ubuntu archive itself, the release and its -updates from archive.ubuntu.com and its
#-security from security.ubuntu.com, as Ubuntu's installer writes them with no mirror. The installer wrote
#the mirror in sources.list (22.04) or ubuntu.sources (24.04 on, a stanza per URI and its suites)
if [ -n "${MIRROR:-}" ]; then
    for file in /etc/apt/sources.list /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; do
        if [ -f "${file}" ] && grep -qF "${MIRROR%/}" "${file}"; then
            awk -v mirror="${MIRROR%/}" -v deb822="$(case "${file}" in *.sources) printf 1 ;; esac)" '
                #a URI that is the mirror becomes the archive itself, the security one for -security suites
                function swap(uri, secure,   bare) { bare = uri; sub(/\/$/, "", bare)
                    return bare != mirror ? uri : secure ? "http://security.ubuntu.com/ubuntu/" : "http://archive.ubuntu.com/ubuntu/" }
                function flush(   i, j, k, field, line) {
                    for (i = 1; i <= n; i++) {
                        if (stanza[i] ~ /^URIs:/) {
                            k = split(stanza[i], field, /[ \t]+/); line = field[1]
                            for (j = 2; j <= k; j++) line = line " " swap(field[j], secure)
                            stanza[i] = line
                        }
                        print stanza[i]
                    }
                    n = 0; secure = 0
                }
                #one-line entries, the commented ones too: [#] deb [options] URI SUITE COMPONENTS...
                !deb822 && /^(#[ \t]*)?deb(-src)?[ \t]/ {
                    i = ($1 == "#" ? 3 : 2); if ($i ~ /^\[/) { while (i < NF && $i !~ /\]$/) i++; i++ }
                    $i = swap($i, $(i + 1) ~ /-security$/); print; next
                }
                !deb822 {print; next}
                #deb822: a stanza is read whole, then its URIs follow its suites
                NF == 0 {flush(); print; next}
                {stanza[++n] = $0}
                $1 == "Suites:" {secure = 1; for (i = 2; i <= NF; i++) if ($i !~ /-security$/) secure = 0}
                END {flush()}' "${file}" > "${file}.minos" && cat "${file}.minos" > "${file}" && rm -f "${file}.minos"
        fi
    done
    #archive.ubuntu.com, named as the mirror, rightly stays
    if [ "${MIRROR%/}" != "http://archive.ubuntu.com/ubuntu" ] && grep -rqF "${MIRROR%/}" /etc/apt/sources.list /etc/apt/sources.list.d; then
        printf "%s\n" "box.sh: the mirror ${MIRROR} is still in the apt sources" >&2; exit 1
    fi
    printf "%s\n" "mirror: ${MIRROR}, replaced by archive.ubuntu.com and security.ubuntu.com in the apt sources"
fi

#what apt, the installer and the first boot leave behind
apt-get clean
rm -rf /var/lib/apt/lists/* /var/log/installer
find /var/log -type f -name '*.log' ! -name minos-setup.log -exec truncate -s 0 {} +
printf "slim: apt lists and caches, logs %s\n" "$(_used)"

#the initramfs carries the modules of the machine it boots, plus the SATA controller VirtualBox gives an
#imported machine (the box is built on virtio); every other driver stays on the disk. Up to 24.04 the
#initramfs is made by initramfs-tools (MODULES=dep), from 26.04 on by dracut (hostonly, strict: Ubuntu's
#default "sloppy" mode keeps whole subsystems, 672 modules)
#A desktop also carries the graphics drivers of the machines a box runs on, for plymouth: VirtualBox's
#VBoxVGA (vboxvideo) and VMSVGA (vmwgfx), QEMU's VGA (bochs) and virtio-gpu. GRUB starts the kernel on a
#text console on VirtualBox's and VMware's cards (/boot/grub/gfxblacklist.txt), so no firmware framebuffer
#is left for simpledrm, and the build machine's own card is not the one VirtualBox gives: without them the
#first screen plymouth finds comes from the root filesystem, after the initramfs is over
video=""
[ -z "${desktop}" ] || video="vboxvideo vmwgfx bochs virtio-gpu"
if [ -d /etc/dracut.conf.d ] && command -v dracut >/dev/null 2>&1; then
    printf '%s\n' 'hostonly="yes"' 'hostonly_mode="strict"' "add_drivers+=\" ahci sd_mod ${video:+${video} }\"" > /etc/dracut.conf.d/minos-box.conf
    dracut --force --regenerate-all >/dev/null
else
    printf '%s\n' 'MODULES=dep' > /etc/initramfs-tools/conf.d/minos-box
    # shellcheck disable=SC2086 # a list of modules
    printf '%s\n' ahci sd_mod ${video} >> /etc/initramfs-tools/modules
    update-initramfs -u -k all >/dev/null
fi
printf "slim: initramfs with the modules in use %s\n" "$(_used)"

#Vagrant mounts the project's folder (/vagrant, vboxsf) from /etc/fstab with _netdev, which puts
#network-online.target ahead of the login: a desktop box sat 19.4 s in VirtualBox (26.04) on
#connman-wait-online, which waits for connman to find the internet. Nothing in a box needs that before the
#login: the boxes go without it, a minos installed by hand keeps it
if systemctl is-enabled --quiet connman-wait-online.service 2>/dev/null; then
    systemctl disable --quiet connman-wait-online.service
fi

#what the build leaves that no image should carry: the journal of the build's boots (a machine made from
#the box starts its own, under its own machine id), compiled python (written again when needed), the
#build's caches, backups and temporary files
#journald keeps its files open: moved to /run until the next boot, it closes them and they can go
journalctl --relinquish-var
rm -rf /var/log/journal/*
printf "slim: journal %s\n" "$(_used)"
find / -xdev -name __pycache__ -type d -prune -exec rm -rf {} +
printf "slim: compiled python %s\n" "$(_used)"
rm -rf /var/cache/man/* /var/cache/debconf/*-old /var/lib/dpkg/*-old /var/backups/* /root/.cache /home/*/.cache \
    /var/tmp/* /var/crash/* /var/lib/systemd/coredump/* /home/*/.wget-hsts
printf "slim: caches, backups, temporary files %s\n" "$(_used)"
#each machine made from the box gets its own id, and with it its own DHCP client id
truncate -s 0 /etc/machine-id
rm -f /var/lib/dbus/machine-id

#the free blocks go back to the disk image (QEMU discards them), so they read as zeros and cost nothing
sync
fstrim -v /

# vim: set ts=8 sw=4 tw=0 ft=sh :

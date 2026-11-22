#!/bin/sh
#a minos box made by minos' own installer instead of Ubuntu's: setup's live mode installs minos onto a disk
#image the way a person installs it onto a partition from a live session (no subiquity, no autoinstall, no
#Ubuntu ISO), then scripts/live-vagrant.sh adds inside it what a Vagrant base box needs, as
#autoinstall/vagrant.yaml does for the boxes Packer makes. ci/boxes boots the image once for scripts/box.sh
#and packs it with scripts/export.sh, as Packer does.
#usage: [STEPS="install vagrant"] [DISK_SIZE=10G] live.sh RELEASE FLAVOUR SETUP OUTPUT     (as root, on a
#       machine booted by BIOS)
#       => OUTPUT/minos-FLAVOUR-RELEASE/minos-FLAVOUR-RELEASE.raw, and beside it install.log: setup's output,
#          each line after the second it was printed at
#       needs losetup, sfdisk, mkfs.ext4, chroot, perl and the network; setup fetches debootstrap when the
#       machine has none

set -eu
release="${1:?usage: live.sh RELEASE FLAVOUR SETUP OUTPUT}"; flavour="${2:?}"; setup="${3:?}"; output="${4:?}"
here="$(cd "$(dirname "${0}")" && pwd)"
name="minos-${flavour}-${release}"
dir="${output}/${name}"; disk="${dir}/${name}.raw"
user="vagrant"
loop=""; mnt=""

_attach_disk() { #the image as a block device with its partitions => loop
    loop="$(losetup -f --show -P "${disk}")"
    command -v udevadm >/dev/null 2>&1 && udevadm settle
    _attach_disk__i=0
    until [ -b "${loop}p2" ]; do
        _attach_disk__i="$((_attach_disk__i + 1))"
        [ "${_attach_disk__i}" -lt 20 ] || { printf "%s\\n" "live: ${loop}p2 never appeared" >&2; return 1; }
        sleep 0.5
    done
}

_detach_disk() { #whatever this script left mounted or attached, also when it stops halfway
    if [ -n "${mnt}" ]; then
        awk -v top="${mnt}" '$2 == top || index($2, top "/") == 1 {print $2}' /proc/mounts | LC_ALL=C sort -r |
            while read -r _detach_disk__point; do umount "${_detach_disk__point}" || umount -l "${_detach_disk__point}"; done
        rmdir "${mnt}" 2>/dev/null || :
        mnt=""
    fi
    if [ -n "${loop}" ]; then losetup -d "${loop}"; loop=""; fi
}
trap '_detach_disk' EXIT
trap 'exit 143' INT TERM HUP

_stamp() { #each line after the second it was printed at
    perl -ne 'BEGIN { $| = 1 } print time(), " ", $_'
}

_since() { #$1 log, $2 $3 two patterns => seconds from the first line matching $2 to the first matching $3
    awk -v from="${2}" -v to="${3}" '
        a == "" && $0 ~ from {a = $1} b == "" && $0 ~ to {b = $1}
        END {if (a != "" && b != "") print b - a; else print "?"}' "${1}"
}

_install() { #setup's live mode onto a new disk image: the disk Packer gives subiquity, GPT with a BIOS boot
             #partition and one ext4 partition for everything (autoinstall/user-data: storage direct)
    #setup installs the boot loader of the firmware the machine it runs on booted with (/sys/firmware/efi), and
    #a box boots by BIOS, as VirtualBox starts an imported machine: on a machine booted by UEFI setup asks for
    #an EFI system partition the disk does not have, and would make a box that boots by UEFI alone
    if [ -d /sys/firmware/efi ]; then
        printf "%s\\n" "live: this machine booted by UEFI, and setup's live mode installs GRUB for the firmware it runs on: a box boots by BIOS" >&2
        return 1
    fi
    printf "%s\\n" "live: this machine booted by BIOS, as the box does"
    rm -rf "${dir}"; mkdir -p "${dir}"
    truncate -s "${DISK_SIZE:-10G}" "${disk}"
    printf '%s\n' 'label: gpt' 'start=2048, size=2048, type=21686148-6449-6E6F-744E-656564454649' \
        'type=0FC63DAF-8483-4772-8E79-3D69D8477DE4' | sfdisk -q "${disk}"
    _attach_disk
    #GRUB embeds itself in the partition of this exact type, and says only "no BIOS Boot Partition" otherwise
    [ "$(lsblk -no PARTTYPENAME "${loop}p1")" = "BIOS boot" ] ||
        { printf "%s\\n" "live: ${loop}p1 is not a BIOS boot partition" >&2; return 1; }
    #the features the release's own mkfs.ext4 gives: 22.04's e2fsck and GRUB know neither of these two, which
    #the mkfs.ext4 of 24.04 on puts on every file system it makes
    _install__features=""
    if [ "${release}" = "22.04" ] && grep -q orphan_file /etc/mke2fs.conf 2>/dev/null; then
        _install__features="-O ^orphan_file,^metadata_csum_seed"
    fi
    # shellcheck disable=SC2086 # a list of options
    mkfs.ext4 -q ${_install__features} "${loop}p2"
    command -v udevadm >/dev/null 2>&1 && udevadm settle
    #setup reads the terminal for nothing and starts at once (--now); boxes travel, so they get the us keyboard
    #and UTC, as the boxes Packer makes, not the keyboard and the zone of the machine that builds them. Its exit
    #status crosses the pipe in a file
    { _install__rc=0
      sh "${setup}" live "${flavour}" "${loop}p2" "${user}" "${user}" --release "${release}" \
          --now --keyboard us --timezone Etc/UTC < /dev/null 2>&1 || _install__rc="${?}"
      printf "%s\\n" "${_install__rc}" > "${dir}/install.status"; } | _stamp > "${dir}/install.log"
    _detach_disk
    _install__status="$(cat "${dir}/install.status")"; rm -f "${dir}/install.status"
    _install__log="${dir}/install.log"
    printf "live: setup live %s %s: exit %s in %ss; before the bootstrap %ss, debootstrap %ss, in the chroot %ss (updates %s, grub %s, kernel %s, user %s, minos %s, upgrade %s, locale %s, boot loader %s)\\n" \
        "${flavour}" "${release}" "${_install__status}" \
        "$(_since "${_install__log}" 'Minos Setup' '(DONE: Reboot|FAILED while)')" \
        "$(_since "${_install__log}" 'Minos Setup' 'Bootstrapping')" \
        "$(_since "${_install__log}" 'Bootstrapping' 'Generating new /etc/fstab')" \
        "$(_since "${_install__log}" '[[][+]] updating' '(DONE: Reboot|FAILED while)')" \
        "$(_since "${_install__log}" '[[][+]] updating' '[[][+]] installing grub')" \
        "$(_since "${_install__log}" '[[][+]] installing grub' '[[][+]] installing the kernel')" \
        "$(_since "${_install__log}" '[[][+]] installing the kernel' '[[][+]] creating the user')" \
        "$(_since "${_install__log}" '[[][+]] creating the user' '[[][+]] installing minos-')" \
        "$(_since "${_install__log}" '[[][+]] installing minos-' '[[][+]] upgrading what')" \
        "$(_since "${_install__log}" '[[][+]] upgrading what' '[[][+]] setting the host name')" \
        "$(_since "${_install__log}" '[[][+]] setting the host name' '[[][+]] installing the boot loader')" \
        "$(_since "${_install__log}" '[[][+]] installing the boot loader' '(DONE: Reboot|FAILED while)')"
    [ "${_install__status}" = "0" ] || { tail -n 30 "${_install__log}" >&2; return 1; }
}

_vagrant() { #inside the installed system, before its first boot: scripts/live-vagrant.sh
    [ -f "${disk}" ] || { printf "%s\\n" "live: no ${disk}, the install step makes it" >&2; return 1; }
    _vagrant__start="$(date +%s)"
    _attach_disk
    mnt="$(mktemp -d "${TMPDIR:-/tmp}/minos-live-box.XXXXXX")"
    mount "${loop}p2" "${mnt}"
    for _vagrant__dir in /dev /dev/pts /proc /sys; do mount --bind "${_vagrant__dir}" "${mnt}${_vagrant__dir}"; done
    #a booted system has /run on a tmpfs, and /etc/resolv.conf may point into it (systemd-resolved): the
    #chroot gets an empty one too, with this machine's resolver where the link points
    mount -t tmpfs tmpfs "${mnt}/run"
    if [ -L "${mnt}/etc/resolv.conf" ]; then
        _vagrant__resolv="$(readlink "${mnt}/etc/resolv.conf")"
        case "${_vagrant__resolv}" in /*) : ;; *) _vagrant__resolv="/etc/${_vagrant__resolv}" ;; esac
        mkdir -p "${mnt}$(dirname "${_vagrant__resolv}")"
        cat /etc/resolv.conf > "${mnt}${_vagrant__resolv}"
    fi
    #the install's log, where box.sh and ci/boxes read it, without the times
    sed 's/^[0-9]* //' "${dir}/install.log" > "${mnt}/var/log/minos-setup.log"
    cp "${here}/live-vagrant.sh" "${mnt}/tmp/live-vagrant.sh"
    chroot "${mnt}" /bin/sh /tmp/live-vagrant.sh "${user}" < /dev/null
    rm -f "${mnt}/tmp/live-vagrant.sh"
    _detach_disk
    printf "live: vagrant step in %ss\\n" "$(($(date +%s) - _vagrant__start))"
}

for step in ${STEPS:-install vagrant}; do
    case "${step}" in
        install) _install ;;
        vagrant) _vagrant ;;
        *) printf "%s\\n" "live: ${step}: the steps are install and vagrant" >&2; exit 2 ;;
    esac
done

# vim: set ts=8 sw=4 tw=0 ft=sh :

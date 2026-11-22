About
-----

Recipes to build the official minos images for [Vagrant](https://www.vagrantup.com/) and for
[VirtualBox](https://www.virtualbox.org) without Vagrant, from 22.04 on.

`minos.pkr.hcl` installs Ubuntu's live-server ISO (22.04, 24.04 or 26.04) with Ubuntu's own installer
(subiquity) in QEMU, told what to do by the install recipe of minos, `autoinstall/user-data`. One build
gives:

- `minos-FLAVOUR-RELEASE.box`, a Vagrant box for VirtualBox (`vagrant box add`, see the
  [vagrant](https://github.com/minos-org/vagrant) repository for the catalogs), which VirtualBox
  without Vagrant imports too, once unpacked: it holds the machine as an OVF, `box.ovf`, and its disk;
- `minos-FLAVOUR-RELEASE.sha256`, its checksum.

The install recipe
------------------

`autoinstall/user-data` is the install recipe of minos that the template gives Ubuntu's installer; the
build's parts add the rest, the user among them. It reads two values from the installer's boot line:

- `minos=core` or `minos=desktop`: which metapackage goes in (`core` when absent);
- `minos.setup=URL`: where the minos installer comes from (`https://minos.io/s` when absent). Only
  `https`, or plain `http` from the same server that served the recipe (a test build's); anything else
  stops the install.

minos goes in the way it goes in on an existing Ubuntu: the installer `s` runs inside the new system,
adds the minos archive and installs the metapackage without recommends.

Then the recipe removes what Ubuntu's server image brings and minos does not use, as minos' first
images did (and the `app-purge` list of `minos-desktop-settings`):
crash reports, Ubuntu Pro and its advertising, cloud tools, the tools minos replaces, the servers minos
never wanted, apt's download cache. What `minos-core`/`minos-desktop` depend on, recursively, never goes:
apt is asked first. Each step's size goes to `/var/log/minos-setup.log` as `slim:` lines.

The parts, merged into the recipe by the template (a key of a part replaces the recipe's; a part's
commands run before the recipe's):

- `autoinstall/vagrant.yaml`: what a Vagrant base box needs. The `vagrant` user (password `vagrant`)
  with Vagrant's insecure keys and sudo without password, an ssh server, the virtual kernel, no swap
  file, `eth0` by DHCP on any hypervisor, `/tmp` with exec for Vagrant's and Packer's scripts;
- `autoinstall/bench.yaml`, test builds only: minos from the packages of minos' bench instead of the
  archive.

`scripts/box.sh` runs on the first boot: the owner's commands for `vagrant`; what only a virtual machine
can drop (the generic kernel and its headers, storage and radio tools, older kernels, and, through dpkg
`path-exclude` so that it holds across kernel upgrades, the firmware tree and the drivers of hardware a
VirtualBox or KVM guest never has: sound, cameras, sensors, physical graphics and network cards); cloud-init
and snapd with their snaps, which can only go once the first boot is over; the services of Ubuntu's server
seed that no minos package asks for (`unattended-upgrades`, `networkd-dispatcher`, `dbus-user-session`:
a desktop's session bus comes from `dbus-x11`; on core, polkit); apt lists and logs; free space discarded.
`scripts/export.sh` turns the disk into the `.box`: it makes zeros of the free blocks the discard missed and
of the ext4 journal, then converts the disk to a sparse VMDK, which holds only the grains with data, and
packs it in a tar compressed with xz.

Usage
-----

    $ packer init .
    $ packer build -var release=24.04 -var flavour=core .
    $ vagrant box add --name minos/core-24.04 output/minos-core-24.04.box

VirtualBox without Vagrant imports the box's own OVF. The box is a tar of four files (`box.ovf`, its
disk `box-disk1.vmdk`, and Vagrant's `metadata.json` and `Vagrantfile`) compressed with xz, which `tar xf`
recognizes on its own, so unpack it in a directory of its own and import `box.ovf`, with
*File → Import Appliance* or:

    $ mkdir minos-core-24.04 && cd minos-core-24.04
    $ tar xf ../minos-core-24.04.box
    $ VBoxManage import box.ovf

Test builds, with minos from a directory of packages (with its `Packages` index) and a local setup:

    $ packer build -var release=24.04 -var origin=bench \
        -var bench=../bench/out/noble -var setup=../minos-org.github.com/setup .

or built and checked like the CI's, from a directory with one directory of packages per release (the
index is written for them):

    $ ORIGIN=bench BENCH=../bench/out SETUP=../minos-org.github.com/setup sh ci/boxes 24.04

Continuous integration
----------------------

`.github/workflows/boxes.yml` builds the boxes and the ISOs on GitHub-hosted runners with KVM and checks
each one. `ci/boxes` builds a box and boots its disk the way VirtualBox and QEMU would, `ci/box-check`
looks at minos inside it. `ci/iso` builds the ISO of a release (`iso/build`), a job for each of 22.04,
24.04 and 26.04, and uses it as a person would: its live session by BIOS from a CD, by UEFI with Secure
Boot from a USB stick, and with the network's cable out (`iso/live-check`), and minos installed from it by
UEFI and by BIOS onto an empty disk, which then boots alone (`iso/install-check`). Both print one line per check, and `ci/verdict` says whether each passed.
What every minos system must show, whatever made it (the metapackage installed, an address and a name
resolved, sudo, tmux's and i3's configurations, slim, no failed unit), is `ci/probe-common`: `box-check`
runs it inside each box and the live session's probe runs it from its CD, and `ci/verdict` judges those
lines alike for both. A push to `master` that changes what they are made of builds them; a scheduled run
builds them when the minos archive or the installer changed (`ci/fingerprint`); another branch builds them
only when run by hand. The boxes and the ISOs are kept as artifacts of the run for three days.

Both fetch Ubuntu's packages from the archive `MIRROR` names (`ci/mirror`; `iso/build -m`, the `mirror`
variable of `minos.pkr.hcl`): the workflow sets `archive.ubuntu.com`, and an empty `MIRROR` takes the
mirror the runner's own apt reads, inside GitHub's cloud. What a box or an ISO keeps in its apt sources is
Ubuntu's archive itself, `archive.ubuntu.com` and `security.ubuntu.com`, whatever mirror built it:
`scripts/box.sh` puts it back in a box, `iso/build` writes it in the live system, and `ci/probe-common`
says it (`apt sources`), which `ci/verdict` checks.

On `master`, once the six boxes and the three ISOs pass, `ci/publish` makes them the one release of this
repository, tagged with the day (`YYYY.MM.DD`): each box's `.box` and `.sha256`, and each ISO's `.iso` and
`.sha256`. Only that release is kept. It is uploaded as a draft first and checked against the files;
only then are the older releases deleted with their tags, and the draft published under the day's tag,
so a publish that fails leaves the release before it in place. A second release the same day takes the
day's tag over, at its own commit. The [vagrant](https://github.com/minos-org/vagrant) repository reads
the release and lists the boxes in the catalogs Vagrant reads, `https://minos.io/vagrant/<box>.json`,
versioned by when the release was published, so a rebuild the same day is still a newer box.

The ISO
-------

`iso/build` makes the minos ISO from scratch, for 22.04, 24.04 or 26.04: a debootstrap of the release
with `minos-desktop` installed by the minos installer (`setup`, from `https://minos.io/s` or `-s FILE`),
the way it goes in on any Ubuntu, made a live session by casper, squashed into one xz squashfs. There
is no installer on it besides `s` itself, and no package pool besides the boot loaders' packages: `s live
desktop`, run in the live session, copies the live system to a disk, with no network. Anything else `s live`
makes there (`core`, another `--release`) it bootstraps from the network, as from any live session, with
the `debootstrap` and `wget` the ISO carries (and a system copied from it keeps).

The live system carries what every system the minos installer's live mode makes carries: it installs
`unattended-upgrades` and `ubuntu-release-upgrader-core`, and purges what Ubuntu's base brings and minos
does not use with the installer's own lists (`setup`'s `_live_slim_script`, read from the `setup` the build
uses and run in the system), so a copy of it is the system live mode would bootstrap.

The live session: casper's user `minos`, whom slim logs into i3; the network is minos-desktop's own,
connman for the wired and the wireless cards, its name server reached through systemd-resolved (the
`connman` module of minos-desktop-settings). In i3, `Win+i` opens the installer in a window of its own
that floats in the middle of the screen, minos' help (`F1`) lists that key, and the menu of the background
has "Install minos" as its first entry. The session's clock is in the time zone an install starts on.

The installer is two files, `iso/installer/minos-installer` and `iso/installer/minos-installer-engine`,
copied to `/usr/local/bin` as they are. The engine knows the machine and writes the disk; it asks nothing
and draws nothing. The installer draws its first screen before it has the disks, which the engine reads in
the background, and keeps what it read in the user's directory of the session (`$XDG_RUNTIME_DIR`, a
tmpfs): the next opening lists them from there, with no process started, while the kernel's partitions
and mounts are the ones they were read with, and `r` on the screen of the disks reads them again. What
writes to a disk never takes them from there: `edit`, `apply` and `empty` read the disk themselves.

    # minos-installer-engine disks                    # the disks, and why minos cannot go to one
    # minos-installer-engine plan whole /dev/sda > plan     # or: plan partitions ROOT [ESP] [keep]
    # minos-installer-engine edit /dev/sda plan use=parts root=free:2349   # or: the plan choices make
    # minos-installer-engine check plan && minos-installer-engine describe plan
    # echo PASSWORD | minos-installer-engine apply plan USER

A plan is text, an action a line (`table`, `partition`, `format`, `esp`, `root`, `home`), applied from the
top and only by `apply`: for a whole disk, a GPT with an EFI system partition of 512 MiB and one for minos
when the session started by UEFI, an MBR with one partition when it started by BIOS (a GPT with GRUB's own
partition on a disk over 2 TiB), the partition for minos of a size or with all the room, and one for
`/home` when asked; for a disk that keeps its table, partitions that exist, formatted or kept, and new
ones in its free room (`sfdisk --append`, each with where it starts), an EFI system partition formatted
only when it is not FAT already. `check` says what stops a plan on this machine (a disk in use or the one
the session runs from, a partition too small, no EFI system partition on UEFI, a GPT with no partition
for GRUB on BIOS), `describe` says it for people, `review` and `edit` say it as rows an interface draws
(the disk now and after, what is done, what is lost, the name of the deed), and `apply` ends with the
installer the medium carries, `sh /cdrom/minos/setup live desktop PARTITION USER - [HOME] [--esp ESP]
[--keyboard LAYOUT[:VARIANT]] [--timezone ZONE] --now`, the password on its standard input. What was said
stays in `/tmp/minos-installer.log`, how far the copy is in `/tmp/minos-installer.progress`, and how it ended
in `/tmp/minos-installer.status`.

`minos-installer` is the interface over it: a wizard this script draws by itself in a terminal of 80 by 24
(escape sequences, keys read one at a time; urxvt, the Linux console, ssh), with the steps along the top
and every step going back and forward. An intro; the disk, asked when there are several; the plan the
engine proposes, the disk as a bar now and after and what is done in words, with the partition table one
key away (`t`); the user and its password; one confirmation, two buttons, the one that goes back holding
the cursor and the other naming what it erases; the install as it happens; the end. `p` changes the plan
line by line without leaving the installer: another disk, the whole disk or its partitions and free room,
a partition to replace or to keep, a size for minos, a partition for `/home`, each change made a new plan
by the engine (`edit DISK FILE CHOICE...`) and checked by it before it is shown; `r` goes back to the one
proposed. Nothing is written before the confirmation, and what the firmware starts from (an EFI system
partition, GRUB's own on a GPT that BIOS starts) is the engine's to see to: it is in every plan that needs
it, kept when it is there, made when there is room. A disk that holds something gets no plan that deletes
it until that is chosen. The password goes to `setup` on its standard input (`live ... USER - --now`), and
`--now` has `setup` skip its own countdown.

The step of the user answers one worry, whether what was typed is what was meant. A name is taken as typed and
judged by the engine (`user NAME`), which refuses it in a sentence that says what a name is: lower case
letters, digits, `-` and `_`, a letter first, 32 at most, and no user or group the copied system has. The
password is asked twice while it is typed blind and once while it is seen (`F5`, or `Ctrl-P` where a
terminal keeps the function keys). The step has five fields, in this order: the name, the password, the same
again, the keyboard and the time zone. `Tab` goes through all five and round again; `Enter` on the three that
are typed goes on to the next of them, and from the last to the next step; `Enter` on the keyboard or the
time zone opens its list, where the arrows and the page keys move, what is typed narrows it by name, `Enter`
takes the one under the cursor and `Esc` leaves it as it was. The step needs no letter to be worked: `Tab`,
the arrows, `Enter` and `Esc` say the same whatever the keyboard. The keyboard shown is the one that is
active, as the X session has it (`setxkbmap -query`, so also after minos' own key, Alt and the right Shift);
its list has every layout xkb knows, minos' own first (`minos-config keyboard-layouts`), narrowed by the
layout's code or its name, and what was typed as a password goes with the old keyboard. On the console the
keyboard is the one the system was set to and is not changed from the installer. The time zone is shown with
the time it is there: minos' own, America/Mexico_City, until another is chosen. Its list has every zone the
session's tzdata has (its `tzdata.zi`), minos' three first (Mexico City, Caracas, New York: the engine names
them, in one place, and the first is the one an install starts on), the zone under the cursor with the time
it is there, in a window and on the console alike. The ISO's live session has its clock in that first zone,
so the bar and the installer tell the same hour. The installed system takes that keyboard and that zone
(`setup ... --keyboard LAYOUT[:VARIANT] --timezone ZONE`), so it asks for the password with the keys it was
typed with.

The installer runs as the session's user and asks sudo for the engine alone; another interface can take
its place without touching the engine.

Both take `--try` on a machine that is not the live session: the disk chosen is partitioned and formatted
for real, the `setup` command is shown, not run, and `--firmware uefi|bios` says which firmware the
plans are for. `iso/installer/Vagrantfile` is that machine: the minos desktop box with a second, empty
disk of 16 GB and `Win+i` bound to the installer of that folder (`/vagrant` in the box), so a change to
either file shows the next time the key is pressed:

    $ cd iso/installer && vagrant up     # log in (vagrant / vagrant), then Win+i

Every file the build changes or adds for the live session alone (casper's configuration, slim's
autologin, the installer's key in i3's configuration and in minos' help, `minos-installer` and
`minos-installer-engine`, the `minos-live` filter and the plugins' links and marks below) is named in
`/var/lib/minos/live-only`,
and what it was before is kept in `/var/lib/minos/live-only.d`. The minos installer, copying the live
system (`/rofs`) to a disk, puts those copies back and removes the files that had none, purges casper,
and installs GRUB from `minos/bootloader`.

The ISO carries the kernel modules and the firmware of the wired and wireless network and of what booting
needs (disks, USB, input, a basic display through `simpledrm`), and the drivers of the cards virtual
machines give it (`vmwgfx`, `vboxvideo`, `virtio-gpu`, `bochs`, `hyperv_drm`, `qxl`, `cirrus`: no
firmware, about 0.7 MB of the ISO), so that a live session in one changes modes, which the firmware's
framebuffer cannot; nothing else: before the kernel is installed, `/etc/dpkg/dpkg.cfg.d/minos-live` tells
dpkg to leave the rest out. The modules kept are named by directory or by file in `_modules_wanted`, with
whatever they need; the firmware kept is what those modules ask for (`modinfo -F firmware`). The packages
whose files it left out are listed in `/var/lib/minos/live-trimmed`. A system copied from the live one
goes without the filter and gets the rest back with the network: `minos-untrim.service` (disabled in the
live session, enabled by the copy) runs `/usr/local/sbin/minos-untrim` once a network is up, which
reinstalls those packages (`apt-get install --reinstall`, or the archive's newer version), and the
archive's current kernel when the one installed can no longer be downloaded; while that fails it tries
again every 10 minutes and at each boot, and once it works it disables itself.

Like Ubuntu's minimized images, the ISO carries no documentation, manual pages or translations of
messages (`/etc/dpkg/dpkg.cfg.d/minos-docs`; the copyright files stay, and so do the locales' definitions,
which `locale-gen` reads). A system copied from the live one keeps that filter.

The ISO carries the vim, tmux and shell plugins minos' configuration names, in `/etc/skel` (about
55 MiB, 15.5 MB of the ISO): minos-core-settings leaves only the plugin managers there and fetches the
plugins at a user's first login, which in a live session is every boot, and needs a network. The build
runs the settings' own `user-plugins` for a user with the live user's name and home, takes that home's
`.vim`, `.tmux` and `.shundle` into `/etc/skel`, and removes the user; so the live user, whom casper
makes from `/etc/skel`, has them. The links shundle made in `~/.bin` and the marks that tell the login
hook nothing is left to install go to `/etc/skel` for the live session alone
(`/var/lib/minos/live-only`). In a copy, the installer makes the user from that `/etc/skel` and
configures minos-core-settings again, which puts its own `/etc/skel` back and runs `user-plugins` for
the user: the vim and tmux plugins stay in the home, with no network. The shell's do not: undoing its
shundle module first, minos-core-settings removes a `~/.shundle` that weighs what `/etc/skel`'s does,
and the copy's user is left with shundle alone, as before. A user made later gets the plugins at login,
as on any minos.

On the medium:

- `casper/filesystem.squashfs` (with its `.size` and `.manifest`), the live system, xz in blocks of 1 MiB
  with x86's branch filter; in the live session casper mounts the medium on `/cdrom` and the squashfs,
  read-only, on `/rofs`: the system as it was built, under the overlay that is the session's root;
- `casper/vmlinuz` and `casper/initrd`, the kernel and a casper initrd made for it (`MODULES=most`, xz),
  whose id is `.disk/casper-uuid-minos`: casper boots from this ISO and no other;
- `boot/grub/` (the menu, GRUB's modules and El Torito image for BIOS, its font) and `EFI/boot/`. The
  kernel draws on the display GRUB leaves it (simpledrm), until the driver of a virtual machine's card
  takes it: on BIOS a graphics mode GRUB sets, on UEFI the firmware's own, which GRUB leaves as it is.
  The menu's entry carries `noprompt`: the session restarts and powers off without casper's wait for the
  medium to be taken out, a question its boot screen does not show;
- `minos/setup`, the minos installer the build used, which has to be one that takes `--now` and a
  password on its standard input (the build refuses an older one); `md5sum.txt`, which casper checks the
  files against;
- `minos/bootloader/`, the boot loaders a system copied from the live one needs, as packages the live
  system does not install (grub-pc and grub-efi-amd64 conflict, so it carries neither): the ones the
  minos installer's live mode installs, with what they need that the live system lacks. `bios.list` names
  those of BIOS (`grub-pc`, `grub2-common`), `uefi.list` those of UEFI and Secure Boot (`grub-efi-amd64`,
  `grub-efi-amd64-signed`, `shim-signed`, `efibootmgr`). In the copied system, with no network:

      # BIOS
      echo "grub-pc grub-pc/install_devices multiselect /dev/disk/by-id/DISK" | debconf-set-selections
      cd DIR && apt-get install -y --no-install-recommends $(sed 's|^|./|' bios.list)
      grub-install /dev/DISK && update-grub
      # UEFI, the EFI partition on /boot/efi
      cd DIR && apt-get install -y --no-install-recommends $(sed 's|^|./|' uefi.list)
      grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=ubuntu && update-grub

  (DIR: a copy of `minos/bootloader`, or the medium itself bind-mounted into the copy.) The live system
  has no initrd in `/boot`, so `update-initramfs -c -k all` comes before `update-grub`.

It boots as Ubuntu's ISOs do, from a CD or written to a USB stick: on BIOS through GRUB's El Torito image
or the hybrid MBR; on UEFI through the EFI partition appended after the ISO 9660 file system (El Torito
and a GPT both name it), where the archive's signed shim and GRUB (`shim-signed`,
`grub-efi-amd64-signed`) boot it with Secure Boot on. The boot files come from the release's own packages,
downloaded for the build, not installed in the live system. It runs as root (debootstrap, chroot, mounts)
and needs the network:

    $ sudo iso/build 24.04       # => output/minos-24.04-amd64.iso, its system and files in output/build

`-m URI` fetches Ubuntu's packages from another mirror (`ci/iso` gives the one `ci/mirror` says); the ISO's
sources say `archive.ubuntu.com` and `security.ubuntu.com` whatever it is.

`iso/live-check` boots the ISO in QEMU with KVM, by BIOS (SeaBIOS), UEFI (OVMF) or UEFI with Secure Boot
(OVMF with Microsoft's keys), as a CD or as a USB stick, and uses the live session as a person would: it
waits for i3 (minos' wallpaper on the screen), opens a terminal and runs a probe from a second CD, which
writes on the serial port what the session says about itself (the boot; the display: the drivers of
virtual machines' cards it carries, the driver of the card and the modes it offers; what slim
waited for, where the medium is mounted, the plugins the image brought and whether the login hook had
any left to install, and `ci/probe-common`, which the CD carries: the network and
whether names resolve among it), then opens the installer with its key (Win+i) and reads off the screen
how long its first screen takes to show (`ci/verdict` wants it under two seconds in the session booted
from the CD), that it was drawn while the disks were read, that `r` reads them again to what was kept, that
the next opening reads none, that a USB stick added through QMP is listed at the opening after, and that a
window closed in the middle of a read (held there by a script typed in a terminal) leaves nothing of it
behind; and, the desktop bare again, a
click on the wallpaper must open the menu of the background with "Install minos" as its first row. With `CABLE=no` the network card's cable is out from power on: the session
must come up all the same, and the probe find no address.
It keeps the screen at GRUB's menu, on the desktop, with the probe and with the installer's terminal:

    $ iso/live-check output/minos-24.04-amd64.iso secureboot usb output/live

`iso/install-check` installs minos from the live session onto an empty disk (SATA or NVMe) with no
network: the installer's key (`Win+i`) must open its window, and a probe has the installer's engine plan
the whole disk and apply that plan (the screens are not answered: their questions are still changing).
Then the disk boots alone, still with no network, to slim, where the user logs in, and to i3, and
stays up until `minos-untrim` has had its try (after connman's 2 minutes of waiting for a network), which
must fail and leave the unit enabled; and, with `PHASES="install boot untrim"`, once more with a network,
until `minos-untrim` is through. After each
boot it reads the disk: the files `dpkg --verify` misses, what the copy left out, the boot loader, the
journal. `PHASES=boot` boots and reads a disk another installer made. `iso/qemu-lib` holds what both
checks do to the machine (keys, screens, the serial port):

    $ iso/install-check output/minos-24.04-amd64.iso uefi nvme output/install

Dependencies
------------

- [Packer](https://developer.hashicorp.com/packer) 1.11 or later, and its QEMU plugin (`packer init`)
- QEMU with KVM (`qemu-system-x86_64`, `qemu-img`); `xorriso` for test builds
- for `scripts/export.sh`: `qemu-nbd` (with the kernel's `nbd` module), `zerofree`, e2fsprogs and `xz`,
  and root for `qemu-nbd`, through `sudo` when the build runs as another user
- the ISO: root, `debootstrap`, `squashfs-tools`, `xorriso`, `dosfstools`, `mtools`, `kmod` and `wget`
  or `curl`; to boot it, QEMU with KVM, OVMF, `socat`, `xorriso` and `netpbm`

The boxes of 14.04 to 18.04 came from older templates, built from `mini.iso`; they live in this
repository's history.

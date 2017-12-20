#!/bin/sh
set -xe

MINOS_EDITION="$(hostname|cut -d- -f2)"
MINOS_VERSION="$(awk -F= '/RELEASE/{print $2}' /etc/lsb-release)"

case "${MINOS_EDITION}" in
    core)
        pkgs="accountsservice acl acpid apparmor apport apport-symptoms
        bcache-tools bind9-host byobu chef chef-zero cloud-guest-utils
        cloud-init cloud-initramfs-copymods cloud-initramfs-dyn-netconf crda
        cryptsetup cryptsetup-bin dbus dconf-service debconf-utils dmidecode
        dnsmasq-base dns-root-data dnsutils dosfstools eatmydata ed eject
        ethtool fakeroot fontconfig fontconfig-config fonts-dejavu-core
        fonts-ubuntu-font-family-console ftp gawk gdisk geoip-database
        gir1.2-glib-2.0 grub-legacy-ec2 hdparm hicolor-icon-theme ifenslave
        info install-info irqbalance iso-codes juju juju-core kbd
        keyboard-configuration krb5-locales landscape-client landscape-common
        language-pack-en language-pack-gnome-en laptop-detect
        libaccountsservice0 libapparmor-perl libarchive-extract-perl libasound2
        libatk1.0-0 libatm1 libaugeas0 libavahi-client3
        libavahi-common3 libc6-dev libcap-ng0 libc-dev-bin
        libclass-accessor-perl libcolord1 libcolorhug1 libcups2 libdatrie1
        libdconf1 libdns100 libdpkg-perl libdrm-intel1 libdrm-nouveau2
        libdrm-radeon1 libdumbnet1 libelf1 libexif12 libfakeroot
        libfile-fcntllock-perl libfontconfig1 libfontenc1 libfribidi0 libgc1c2
        libgcr-3-common libgeoip1 libgirepository-1.0-1 libglapi-mesa
        libglib2.0-0 libglib2.0-data libgphoto2-port10 libgraphite2-3
        libgudev-1.0-0 libgusb2 libharfbuzz0b libice6 libicu52
        libieee1284-3 libio-string-perl libjbig0 libjpeg-turbo8
        libjs-jquery liblcms2-2 libllvm3.4 liblockfile-bin
        liblog-message-simple-perl libltdl7 liblwres90 libmodule-pluggable-perl
        libmspack0 libnetfilter-conntrack3 libnl-3-200 libnss-myhostname
        libnuma1 libogg0 libpam-cap libpango-1.0-0 libpangoft2-1.0-0
        libparse-debianchangelog-perl libparted0debian1 libpciaccess0
        libpixman-1-0 libplymouth4 libpod-latex-perl libpolkit-gobject-1-0
        libreadline6-dev libsasl2-modules libsigsegv2 libsm6 libssl-dev
        libsub-name-perl libsystemd-daemon0 libsystemd-login0 libtdb1
        libterm-ui-perl libtext-soundex-perl libthai0 libtiff5 libtimedate-perl
        libtinfo-dev libtxc-dxtn-s2tc0 libv4l-0 libv4lconvert0 libvorbis0a
        libvorbisfile3 libvpx1 libwayland-client0 libwayland-cursor0
        libx11-data libx11-xcb1 libxau6 libxdmcp6 libxfont1 libxkbcommon0
        libxml2 libxshmfence1 linux-firmware linux-headers-generic
        linux-libc-dev lockfile-progs lshw ltrace lxc-common lxcfs lxd
        lxd-client manpages-dev open-iscsi open-vm-tools os-prober parted
        pastebinit plymouth-theme-ubuntu-text pollinate popularity-contest
        powermgmt-base ppp psmisc python3-apport python3-gi
        python3-newt python3-problem-report python3-pycurl python3-systemd
        python-cheetah python-configobj python-crypto python-gdbm
        python-httplib2 python-jsonpatch python-json-pointer python-keyring
        python-oauth python-openssl python-pam python-pkg-resources
        python-prettytable python-problem-report python-pycurl python-serial
        python-simplejson python-twisted-bin python-twisted-core python-xapian
        python-yaml python-zope.interface rename ruby-diff-lcs ruby-erubis
        ruby-hashie ruby-highline ruby-ipaddress ruby-json ruby-mime-types
        ruby-mixlib-authentication ruby-mixlib-cli ruby-mixlib-config
        ruby-mixlib-log ruby-mixlib-shellout ruby-net-ssh ruby-rack ruby-sigar
        ruby-systemu ruby-yajl run-one screen sgml-base shared-mime-info snapd
        sosreport sound-theme-freedesktop squashfs-tools tcpd
        ubuntu-cloudimage-keyring ufw uidmap ureadahead usbutils uuid-runtime
        vim vim-tiny vlan w3m x11-common xauth xdg-user-dirs xfonts-base
        xfonts-utils xfsprogs xkb-data xserver-common xserver-xorg-core
        zerofree"

        case "${MINOS_VERSION}" in
            14.04*) pkgs="${pkgs} libmpdec2 libcryptsetup4 libapparmor1
                libcap2-bin libcap-ng0 libicu55" ;;
            16.04*) pkgs="${pkgs} libdrm2 libnih1 libslang2 makedev" ;;
        esac
        ;;

    desktop)
        pkgs="accountsservice acl acpid apparmor apport apport-symptoms
        bcache-tools byobu chef chef-zero cloud-guest-utils cloud-init
        cloud-initramfs-copymods cloud-initramfs-dyn-netconf crda cryptsetup
        cryptsetup-bin debconf-utils dmidecode dnsmasq-base dns-root-data
        dnsutils dosfstools eatmydata ed eject ethtool fakeroot
        fonts-ubuntu-font-family-console ftp gawk gdisk geoip-database
        grub-legacy-ec2 hdparm ifenslave info install-info irqbalance iso-codes
        juju juju-core kbd krb5-locales landscape-client landscape-common
        language-pack-en language-pack-gnome-en laptop-detect
        libaccountsservice0 libapparmor-perl libarchive-extract-perl libatm1
        libaugeas0 libc6-dev libc-dev-bin libclass-accessor-perl libcolorhug1
        libdpkg-perl libdumbnet1 libfakeroot libfile-fcntllock-perl libgc1c2
        libglib2.0-data libgusb2 libicu52 libieee1284-3 libio-string-perl
        libjs-jquery liblockfile-bin liblog-message-simple-perl
        libmodule-pluggable-perl libmspack0 libnetfilter-conntrack3
        libnss-myhostname libpam-cap libparse-debianchangelog-perl
        libpod-latex-perl libreadline6-dev libsasl2-modules libsigsegv2
        libssl-dev libsub-name-perl libterm-ui-perl libtext-soundex-perl
        libtimedate-perl libtinfo-dev libtxc-dxtn-s2tc0 libv4l-0 libv4lconvert0
        linux-firmware linux-headers-generic linux-libc-dev lockfile-progs lshw
        ltrace lxc-common lxcfs lxd lxd-client manpages-dev open-iscsi
        open-vm-tools os-prober pastebinit plymouth-theme-ubuntu-text pollinate
        popularity-contest ppp python3-apport python3-gi python3-newt
        python3-problem-report python3-pycurl python3-systemd python-cheetah
        python-configobj python-crypto python-gdbm python-httplib2
        python-jsonpatch python-json-pointer python-keyring python-oauth
        python-openssl python-pam python-pkg-resources python-prettytable
        python-problem-report python-pycurl python-serial python-simplejson
        python-twisted-bin python-twisted-core python-xapian python-yaml
        python-zope.interface rename ruby-diff-lcs ruby-erubis ruby-hashie
        ruby-highline ruby-ipaddress ruby-json ruby-mime-types
        ruby-mixlib-authentication ruby-mixlib-cli ruby-mixlib-config
        ruby-mixlib-log ruby-mixlib-shellout ruby-net-ssh ruby-rack ruby-sigar
        ruby-systemu ruby-yajl run-one screen sgml-base snapd sosreport
        squashfs-tools tcpd ubuntu-cloudimage-keyring ufw uidmap ureadahead
        uuid-runtime vim vim-tiny vlan w3m xdg-user-dirs xfsprogs zerofree"

        case "${MINOS_VERSION}" in
            14.04*) pkgs="${pkgs} libmpdec2 libcryptsetup4 libcap2-bin
                hicolor-icon-theme libgcr-3-common libnuma1 libplymouth4" ;;
            16.04*) pkgs="${pkgs} libnih1 makedev libcolord1 libdns100
                libgphoto2-port10 libjasper1 libllvm3.4 liblwres90
                libparted0debian1 libsystemd-daemon0 libsystemd-login0 libvpx1
                sound-theme-freedesktop" ;;
        esac
        ;;
esac

#remove old kernels
old_kernels="$(dpkg -l | awk '/kernel/ && /^ii/ && $2 ~ /[0-9]+\.[0-9]+\.[0-9]+/ {print $2}' | grep -v "$(uname -r | cut -d- -f-2)")" || :

if [ -n "${old_kernels}" ]; then
    pkgs="${pkgs} ${old_kernels}"
fi

set +x #disable verbose mode temporary, the following loop produces a lot of output
installed_pkgs="$(dpkg --get-selections | grep -v deinstall | awk '{print $1}')"
for pkg in $pkgs; do
    if printf "%s\\n" "${installed_pkgs}" | grep -q "${pkg}"; then
        unnecesary_pkgs="${unnecesary_pkgs} ${pkg}"
    fi
done
set -x #enable back verbose mode

#do not touch sensible packages
sensible_pkgs="linux-image-virtual grub-pc"

for pkg in ${sensible_pkgs}; do
    printf "%s\\n" "${pkg} hold" | dpkg --set-selections
done

if [ -n "${unnecesary_pkgs}" ]; then
    apt-get purge -y $unnecesary_pkgs
    apt-get -y autoremove
fi

if command -v "hostnamectl"; then
    #on ubuntu 16.04 and later hostnamectl is part of the systemd package which
    #is a pita to remove, since hostnamectl depends on dbus we install it, a
    #better alternative could be to remove/rename hostnamectl so vagrant
    #doesn't complain, or replace systemd =D.., work in progress
    case "${MINOS_VERSION}" in
        16.04*) apt-get install --no-install-recommends -y dbus ;;
    esac
fi

#!/bin/sh
set -x

#remove traces of MAC address and UUID from network configuration
sed -E -i '/^(HWADDR|UUID)/d' /etc/sysconfig/network-scripts/ifcfg-e*

if command -v "yum" >/dev/null; then #disable consistent device naming
    sed -i -e '/GRUB_CMDLINE_LINUX/ s:"$: net.ifnames=0":' /etc/default/grub
fi

grub2-mkconfig -o /boot/grub2/grub.cfg || grub-mkconfig -o /boot/grub/grub.cfg

#disable udev network rules
ln -s /dev/null /etc/udev/rules.d/80-net-name-slot.rules

#lock root account
#passwd -d root
#passwd -l root

#clean up yum
rpm --rebuilddb
yum clean all

#cleanup apt-get
apt-get clean
apt-get autoclean
apt-get -qq -y autoremove
rm -rf /var/cache/apt /var/lib/apt/lists

#remove ssh host keys
command -v "yum" >/dev/null && rm -rf /etc/ssh/ssh_host*_key*

#clean up /root
rm -f /root/anaconda-ks.cfg
rm -f /root/install.log
rm -f /root/install.log.syslog
rm -rf /root/.pki

#clean up /var/log
>/var/log/cron
>/var/log/dmesg
>/var/log/lastlog
>/var/log/maillog
>/var/log/messages
>/var/log/secure
>/var/log/wtmp
>/var/log/audit/audit.log
>/var/log/rhsm/rhsm.log
>/var/log/rhsm/rhsmcertd.log
rm -f /var/log/*.old
rm -f /var/log/*.log
rm -f /var/log/*.syslog

#clean /tmp
rm -rf /tmp/*
rm -rf /tmp/*.*
find ~ -maxdepth 1 -iname ".*minos*" -exec rm -rf -- {} +

#zero out the free space to save space in the final image
dd if=/dev/zero of=/EMPTY bs=1M
dd if=/dev/zero of=/boot/EMPTY bs=1M
rm -rf /EMPTY /boot/EMPTY
sync; sync; sync

#clear history
history -c
cat /dev/null > ~/.bash_history

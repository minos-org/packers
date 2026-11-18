#!/bin/sh
#the disk Packer installed, as VirtualBox takes it: a sparse VMDK (only the grains that hold data)
#described by an OVF, packed as a Vagrant box for VirtualBox, a tar compressed with xz. The blocks of the
#disk's ext4 filesystems that hold nothing are made zeros first, and the VMDK leaves them out. VirtualBox
#without Vagrant imports the box's own OVF: tar xf NAME.box, then VBoxManage import box.ovf
#(File > Import Appliance).
#usage: export.sh DISK.qcow2 OUTPUT NAME   =>   OUTPUT/NAME.box, OUTPUT/NAME.sha256
#       needs qemu-img and qemu-nbd (qemu-utils), zerofree, e2fsprogs and xz, and root for qemu-nbd
#       (through sudo when it runs as another user)

set -eu
disk="${1:?usage: export.sh DISK.qcow2 OUTPUT NAME}"; output="${2:?}"; name="${3:?}"
work="${output}/${name}.export"
root=""; [ "$(id -u)" -eq 0 ] || root="sudo"
#the box's network card, in VirtualBox's own range (08:00:27): Vagrant sets it on the machine it imports
mac="080027$(printf "%s" "${name}" | md5sum | cut -c1-6)"

_as_root() { #a command, as root
    # shellcheck disable=SC2086 # root is sudo or nothing
    ${root} "${@}"
}

_root() { #a command, as root, its output added to $work/zero.log; when it fails, the log's end says why
    _as_root "${@}" >> "${work}/zero.log" 2>&1 && return 0
    printf "%s\\n" "export: ${*} failed:" >&2; tail -5 "${work}/zero.log" >&2; return 1
}

_wait() { #$1 what it waits for, then a test: true within 10 s, or it says what did not come
    _wait__what="${1}"; shift; _wait__n=0
    until "${@}"; do
        [ "${_wait__n}" -lt 100 ] || { printf "%s\\n" "export: 10 s without ${_wait__what}" >&2; return 1; }
        sleep 0.1; _wait__n=$((_wait__n + 1))
    done
}

#the qcow2 through qemu-nbd, as a block device: nbd is the device while connected
nbd=""
_nbd_sized() { #true once the kernel has started the device (it has a pid) and given it its size, which
               #recent kernels do last
    [ -e "/sys/block/${nbd#/dev/}/pid" ] && [ "$(cat "/sys/block/${nbd#/dev/}/size")" -gt 0 ]
}

_nbd_release() { #the device let go, and qemu-nbd gone with the qcow2 it held open
    [ -n "${nbd}" ] || return 0
    _root qemu-nbd --disconnect "${nbd}"; nbd=""
    _nbd_release__pid="$(_as_root cat "${work}/nbd.pid")"
    _wait "the end of qemu-nbd ${_nbd_release__pid}" [ ! -d "/proc/${_nbd_release__pid}" ]
}
trap '_nbd_release' EXIT
trap '_nbd_release; exit 143' INT TERM HUP

#the blocks of the disk's ext4 filesystems that hold nothing, as zeros, offline on the qcow2: fstrim
#(box.sh) hands back most free blocks, not all, and the journal keeps the build's last writes. qemu-nbd
#stores zeros as holes; zerofree writes zeros over every free block that is not zero, once the journal
#is taken out (its blocks are free then), and the journal is made again, of its size, empty
_zero_free() { #$1 disk.qcow2 => one "zeros:" line per filesystem
    [ -d /sys/module/nbd ] || _root modprobe nbd max_part=8
    if [ "$(cat /sys/module/nbd/parameters/max_part)" -lt 1 ]; then
        printf "%s\\n" "export: nbd is loaded with max_part=0, which shows no partitions: rmmod nbd first" >&2; return 1
    fi
    _zero_free__dev=""
    for _zero_free__sys in /sys/block/nbd*; do
        [ -e "${_zero_free__sys}/pid" ] || { _zero_free__dev="/dev/${_zero_free__sys##*/}"; break; }
    done
    [ -n "${_zero_free__dev}" ] || { printf "%s\\n" "export: every nbd device is taken" >&2; return 1; }
    _zero_free__before="$(du -k "${1}" | cut -f1)"
    _root qemu-nbd --connect="${_zero_free__dev}" --format=qcow2 --cache=writeback --discard=unmap \
        --detect-zeroes=unmap --pid-file="${work}/nbd.pid" "${1}"
    nbd="${_zero_free__dev}"
    #qemu-nbd returns a moment before the kernel starts the device, which is given its size last, and the
    #kernel reads the partition table at the first open after that, which partx -g is: the partitions it
    #lists, each as a device
    _wait "a size for ${nbd}" _nbd_sized
    _zero_free__parts="$(_as_root partx -g -o NR "${nbd}")"
    for _zero_free__nr in ${_zero_free__parts}; do
        _wait "${nbd}p${_zero_free__nr}" [ -b "${nbd}p${_zero_free__nr}" ]
    done
    _zero_free__found=0
    for _zero_free__nr in ${_zero_free__parts}; do
        _zero_free__part="${nbd}p${_zero_free__nr}"
        [ "$(_as_root blkid -o value -s TYPE "${_zero_free__part}")" = "ext4" ] || continue
        _zero_free__found=$((_zero_free__found + 1))
        #"Total journal size:" from e2fsprogs 1.46 on, "Journal size:" before
        _zero_free__journal="$(_as_root dumpe2fs -h "${_zero_free__part}" 2>> "${work}/zero.log" | sed -En 's/^(Total journal|Journal) size: *([0-9]+)M$/\2/p')"
        [ -n "${_zero_free__journal}" ] || { printf "%s\\n" "export: dumpe2fs gives no journal size in M for partition ${_zero_free__nr}" >&2; return 1; }
        _root tune2fs -O ^has_journal "${_zero_free__part}"
        #zerofree -v ends with modified/free/total blocks, after progress lines that end in \r
        _root sh -c 'zerofree -v "${1}" > "${2}" 2>&1' zerofree "${_zero_free__part}" "${work}/zerofree.log"
        _zero_free__counts="$(tr '\r' '\n' < "${work}/zerofree.log" | awk -F/ '/^[0-9]+\/[0-9]+\/[0-9]+$/ {n = $1; f = $2}
            END {if (f != "") printf "%d of %d free blocks were not zero", n, f; else printf "zerofree gave no counts"}')"
        _root tune2fs -j -J size="${_zero_free__journal}" "${_zero_free__part}"
        _root e2fsck -fn "${_zero_free__part}"
        printf "%s\\n" "zeros: partition ${_zero_free__nr} (ext4), ${_zero_free__counts}; journal ${_zero_free__journal}M made again, empty; e2fsck -fn clean"
    done
    _nbd_release
    [ "${_zero_free__found}" -gt 0 ] || { printf "%s\\n" "export: no ext4 filesystem on ${1}" >&2; return 1; }
    printf "%s\\n" "zeros: the qcow2 held $((_zero_free__before / 1024)) MB, now $(($(du -k "${1}" | cut -f1) / 1024)) MB"
}

_uuid() { #text => a UUID made of its md5: the same box gets the same ones on every build
    printf "%s" "${1}" | md5sum | sed 's/^\(.\{8\}\)\(.\{4\}\)\(.\{4\}\)\(.\{4\}\)\(.\{12\}\).*/\1-\2-\3-\4-\5/'
}

_virtual_size() { #disk => its virtual size in bytes (the disk's own line, not the file layer's under it)
    qemu-img info "${1}" | sed -n 's/^virtual size: .*(\([0-9]*\) bytes).*/\1/p'
}

#a desktop's sound card, as VirtualBox's own OVF tests declare one: ensoniq1371 imports as AC'97, whose
#driver (snd_intel8x0) the desktop boxes keep; without the item VirtualBox gives the machine no sound
_sound() { #name => the OVF item of a sound card for a desktop, nothing for the rest
    case "${1}" in *desktop*) cat << E=O=F
      <Item>
        <rasd:AddressOnParent>3</rasd:AddressOnParent>
        <rasd:AutomaticAllocation>false</rasd:AutomaticAllocation>
        <rasd:Caption>sound</rasd:Caption>
        <rasd:Description>Sound Card</rasd:Description>
        <rasd:ElementName>sound</rasd:ElementName>
        <rasd:InstanceID>6</rasd:InstanceID>
        <rasd:ResourceSubType>ensoniq1371</rasd:ResourceSubType>
        <rasd:ResourceType>35</rasd:ResourceType>
      </Item>
E=O=F
    ;; esac
}

#the machine in VirtualBox's own terms, as VirtualBox 7 writes it in an export (VBoxManage export, settings
#1.19): an import that finds it builds the machine from it, and from the items above only what it is asked
#to change. Without it VirtualBox makes the SATA controller from the item, with 30 ports, and from 26.04 on
#the kernel spends 16.7 s probing the 29 empty ones at every boot; here the controller has the one port its
#disk is on. The rest is what VirtualBox 7.2 makes of the items on its own (an Ubuntu_64 machine), so the
#machine is the same one the items alone gave. The sound card is a desktop's only, as in the items, and its
#output is on there (enabledOut), since VirtualBox otherwise imports the card with its output off
_vbox_machine() { #$1 the machine's name, $2 the disk's uuid
    case "${1}" in *desktop*) _vbox_machine__sound="true" ;; *) _vbox_machine__sound="false" ;; esac
    cat << E=O=F
    <vbox:Machine ovf:required="false" version="1.19-linux" uuid="{$(_uuid "${1}")}" name="${1}" OSType="Ubuntu_64">
      <ovf:Info>Complete VirtualBox machine configuration in VirtualBox format</ovf:Info>
      <Hardware>
        <Memory RAMSize="1024"/>
        <Display VRAMSize="16"/>
        <BIOS>
          <IOAPIC enabled="true"/>
          <SmbiosUuidLittleEndian enabled="true"/>
          <AutoSerialNumGen enabled="true"/>
        </BIOS>
        <Network>
          <Adapter slot="0" enabled="true" MACAddress="${mac}" type="82540EM">
            <NAT localhost-reachable="false"/>
          </Adapter>
        </Network>
        <AudioAdapter useDefault="true" driver="Null" enabled="${_vbox_machine__sound}" enabledOut="${_vbox_machine__sound}"/>
        <StorageControllers>
          <StorageController name="SATA" type="AHCI" PortCount="1" useHostIOCache="false" Bootable="true">
            <AttachedDevice type="HardDisk" hotpluggable="false" port="0" device="0">
              <Image uuid="{${2}}"/>
            </AttachedDevice>
          </StorageController>
        </StorageControllers>
        <RTC localOrUTC="UTC"/>
        <CPU count="2">
          <HardwareVirtExLargePages enabled="true"/>
          <PAE enabled="false"/>
          <LongMode enabled="true"/>
          <X2APIC enabled="true"/>
        </CPU>
      </Hardware>
    </vbox:Machine>
E=O=F
}

_ovf() { #$1 vmdk file name, $2 its size, $3 the disk's virtual size, $4 the machine's name
    cat << E=O=F
<?xml version="1.0" encoding="UTF-8"?>
<Envelope ovf:version="1.0" xml:lang="en-US" xmlns="http://schemas.dmtf.org/ovf/envelope/1" xmlns:ovf="http://schemas.dmtf.org/ovf/envelope/1" xmlns:rasd="http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/CIM_ResourceAllocationSettingData" xmlns:vssd="http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/CIM_VirtualSystemSettingData" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:vbox="http://www.virtualbox.org/ovf/machine">
  <References>
    <File ovf:id="file1" ovf:href="${1}" ovf:size="${2}"/>
  </References>
  <DiskSection>
    <Info>List of the virtual disks used in the package</Info>
    <Disk ovf:capacity="${3}" ovf:capacityAllocationUnits="byte" ovf:diskId="vmdisk1" ovf:fileRef="file1" ovf:format="http://www.vmware.com/specifications/vmdk.html#sparse" vbox:uuid="$(_uuid "${4}-disk1")"/>
  </DiskSection>
  <NetworkSection>
    <Info>Logical networks used in the package</Info>
    <Network ovf:name="NAT">
      <Description>Logical network used by this appliance.</Description>
    </Network>
  </NetworkSection>
  <VirtualSystem ovf:id="${4}">
    <Info>A virtual machine</Info>
    <Name>${4}</Name>
    <ProductSection>
      <Info>Meta-information about the installed software</Info>
      <Product>${4}</Product>
      <Vendor>minos</Vendor>
      <ProductUrl>http://minos.io</ProductUrl>
    </ProductSection>
    <OperatingSystemSection ovf:id="94">
      <Info>The kind of installed guest operating system</Info>
      <Description>Ubuntu_64</Description>
      <vbox:OSType ovf:required="false">Ubuntu_64</vbox:OSType>
    </OperatingSystemSection>
    <VirtualHardwareSection>
      <Info>Virtual hardware requirements for a virtual machine</Info>
      <System>
        <vssd:ElementName>Virtual Hardware Family</vssd:ElementName>
        <vssd:InstanceID>0</vssd:InstanceID>
        <vssd:VirtualSystemIdentifier>${4}</vssd:VirtualSystemIdentifier>
        <vssd:VirtualSystemType>virtualbox-2.2</vssd:VirtualSystemType>
      </System>
      <Item>
        <rasd:Caption>2 virtual CPU</rasd:Caption>
        <rasd:Description>Number of virtual CPUs</rasd:Description>
        <rasd:ElementName>2 virtual CPU</rasd:ElementName>
        <rasd:InstanceID>1</rasd:InstanceID>
        <rasd:ResourceType>3</rasd:ResourceType>
        <rasd:VirtualQuantity>2</rasd:VirtualQuantity>
      </Item>
      <Item>
        <rasd:AllocationUnits>byte * 2^20</rasd:AllocationUnits>
        <rasd:Caption>1024 MB of memory</rasd:Caption>
        <rasd:Description>Memory Size</rasd:Description>
        <rasd:ElementName>1024 MB of memory</rasd:ElementName>
        <rasd:InstanceID>2</rasd:InstanceID>
        <rasd:ResourceType>4</rasd:ResourceType>
        <rasd:VirtualQuantity>1024</rasd:VirtualQuantity>
      </Item>
      <Item>
        <rasd:Address>0</rasd:Address>
        <rasd:Caption>sataController0</rasd:Caption>
        <rasd:Description>SATA Controller</rasd:Description>
        <rasd:ElementName>sataController0</rasd:ElementName>
        <rasd:InstanceID>3</rasd:InstanceID>
        <rasd:ResourceSubType>AHCI</rasd:ResourceSubType>
        <rasd:ResourceType>20</rasd:ResourceType>
      </Item>
      <Item>
        <rasd:AddressOnParent>0</rasd:AddressOnParent>
        <rasd:Caption>disk1</rasd:Caption>
        <rasd:Description>Disk Image</rasd:Description>
        <rasd:ElementName>disk1</rasd:ElementName>
        <rasd:HostResource>ovf:/disk/vmdisk1</rasd:HostResource>
        <rasd:InstanceID>4</rasd:InstanceID>
        <rasd:Parent>3</rasd:Parent>
        <rasd:ResourceType>17</rasd:ResourceType>
      </Item>
      <Item>
        <rasd:AutomaticAllocation>true</rasd:AutomaticAllocation>
        <rasd:Caption>Ethernet adapter on 'NAT'</rasd:Caption>
        <rasd:Connection>NAT</rasd:Connection>
        <rasd:ElementName>Ethernet adapter on 'NAT'</rasd:ElementName>
        <rasd:InstanceID>5</rasd:InstanceID>
        <rasd:ResourceSubType>E1000</rasd:ResourceSubType>
        <rasd:ResourceType>10</rasd:ResourceType>
      </Item>
$(_sound "${4}")
    </VirtualHardwareSection>
$(_vbox_machine "${4}" "$(_uuid "${4}-disk1")")
  </VirtualSystem>
</Envelope>
E=O=F
}

rm -rf "${work}"; mkdir -p "${work}/box"
start="$(date +%s)"
_zero_free "${disk}"
zeroed="$(date +%s)"
#a sparse VMDK keeps the grains that hold data as they are, which xz then compresses far better than
#the deflate of each grain a stream optimized one carries
qemu-img convert -O vmdk -o subformat=monolithicSparse "${disk}" "${work}/box/box-disk1.vmdk"
converted="$(date +%s)"
size="$(_virtual_size "${disk}")"
case "${size}" in ''|*[!0-9]*) printf "%s\\n" "export: no virtual size for ${disk}: ${size}" >&2; exit 1 ;; esac

#the box: the disk and its OVF under the names Vagrant's VirtualBox provider imports, which are also
#all VirtualBox needs to import the OVF on its own once the box is unpacked
(   cd "${work}/box"
    _ovf box-disk1.vmdk "$(stat -c %s box-disk1.vmdk)" "${size}" "${name}" > box.ovf
    printf '%s\n' '{"provider": "virtualbox", "architecture": "amd64"}' > metadata.json
    cat > Vagrantfile << E=O=F
# The defaults of the ${name} box; a project's Vagrantfile overrides them.
Vagrant.configure("2") do |config|
  config.vm.base_mac = "${mac}"
  # Vagrant writes its commands to this shell without a terminal. With the default, bash -l, minos'
  # ~/.bash_profile starts tmux on every ssh login and tmux leaves at once ("not a terminal"), taking
  # the shell with it; a shell that is not a login one does not read that file
  config.ssh.shell = "bash"
end
E=O=F
    #xz -9 (a 64 MiB dictionary) on four threads, a block of 192 MiB each: xz 5.4 asks 5 GB of memory
    #for it, and 65 MiB to decompress. Vagrant's bsdtar decompresses on one thread, whatever the blocks
    XZ_OPT="-9 -T4" tar -cJf "../../${name}.box" metadata.json Vagrantfile box.ovf box-disk1.vmdk
)

(cd "${output}" && sha256sum "${name}.box" > "${name}.sha256")
vmdk="$(stat -c %s "${work}/box/box-disk1.vmdk")"
rm -rf "${work}"
end="$(date +%s)"
printf "%s\\n" "export: ${name}.box $(stat -c %s "${output}/${name}.box") B, xz of a ${vmdk} B sparse VMDK, in $((end - start)) s (zeros $((zeroed - start)), VMDK $((converted - zeroed)), xz $((end - converted)))"

# vim: set ts=8 sw=4 tw=0 ft=sh :

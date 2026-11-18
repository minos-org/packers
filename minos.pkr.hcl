# minos boxes: Ubuntu's live-server ISO installed by its own installer (subiquity) with the install
# recipe of minos (autoinstall/user-data), in QEMU with KVM. One build gives a Vagrant box for
# VirtualBox (scripts/export.sh), which VirtualBox without Vagrant imports too once it is unpacked
# (tar xf NAME.box; VBoxManage import box.ovf).
#
#   packer init .
#   packer build -var release=24.04 -var flavour=core -var ssh_key=PATH/vagrant.key.ed25519 .
#
# Needs packer, qemu-system-x86_64 and qemu-img, and xorriso for origin = "bench"; scripts/export.sh
# needs qemu-nbd, zerofree, e2fsprogs and xz, and root (sudo) for qemu-nbd.

packer {
  required_version = ">= 1.11.0"
  required_plugins {
    qemu = {
      source  = "github.com/hashicorp/qemu"
      version = ">= 1.1.0"
    }
  }
}

variable "release" {
  type        = string
  description = "The Ubuntu LTS release: 22.04, 24.04 or 26.04."
  validation {
    condition     = contains(["22.04", "24.04", "26.04"], var.release)
    error_message = "The release is 22.04, 24.04 or 26.04."
  }
}

variable "flavour" {
  type        = string
  default     = "core"
  description = "What minos installs: core (minos-core, no X) or desktop (minos-desktop, i3)."
  validation {
    condition     = contains(["core", "desktop"], var.flavour)
    error_message = "The flavour is core or desktop."
  }
}

variable "origin" {
  type        = string
  default     = "ppa"
  description = "Where minos comes from. ppa: minos.io/s and the minos archive, the way users install it. bench: the setup script named by `setup` and the packages in `bench`, for releases the archive has nothing for yet."
  validation {
    condition     = contains(["ppa", "bench"], var.origin)
    error_message = "The origin is ppa or bench."
  }
}

variable "bench" {
  type        = string
  default     = ""
  description = "origin bench: a directory of packages with their Packages index (the bench's out/SERIES)."
}

variable "setup" {
  type        = string
  default     = ""
  description = "origin bench: the setup script to install minos with (minos-org.github.com/setup)."
}

variable "mirror" {
  type        = string
  default     = ""
  description = "The Ubuntu archive the installer fetches from, as a URI (ci/mirror: on a GitHub-hosted runner, its cloud's mirror); empty for the installer's own, archive.ubuntu.com. Whatever it is, the box reads archive.ubuntu.com and security.ubuntu.com (scripts/box.sh)."
  validation {
    condition     = var.mirror == "" || can(regex("^https?://[^/]+/", var.mirror))
    error_message = "The mirror is an http or https URI, or empty."
  }
}

variable "ssh_key" {
  type        = string
  description = "Vagrant's insecure private key (ED25519), to log into the new system: https://github.com/hashicorp/vagrant/tree/main/keys. minos (libpam-captcha) asks a captcha of every ssh password login, so Packer, like Vagrant, uses the key."
}

variable "output" {
  type        = string
  default     = "output"
  description = "Where the disk, the box and the serial log of the installer go."
}

variable "cpus" {
  type    = number
  default = 2
}

variable "memory" {
  type        = number
  default     = 3072
  description = "MB for the build; the installer of 26.04 wants about 3 GB. The box asks 1 GB."
}

variable "disk_size" {
  type        = string
  default     = "10G"
  description = "The virtual size of the disk; the image only holds what is written."
}

locals {
  isos = {
    "22.04" = {
      url      = "https://releases.ubuntu.com/jammy/ubuntu-22.04.5-live-server-amd64.iso"
      checksum = "sha256:9bc6028870aef3f74f4e16b900008179e78b130e6b0b9a140635434a46aa98b0"
    }
    "24.04" = {
      url      = "https://releases.ubuntu.com/noble/ubuntu-24.04.5-live-server-amd64.iso"
      checksum = "sha256:97f3d7ffb032c3eb3b23d2c8be9cc76e60c2c1f2c0146ba5ba9fe01cafae0fd8"
    }
    "26.04" = {
      url      = "https://releases.ubuntu.com/resolute/ubuntu-26.04.1-live-server-amd64.iso"
      checksum = "sha256:cc8a95cde20f6ced61a322420de00f10cc3c90ced545daa46cb9c1a117f1d927"
    }
  }
  name = "minos-${var.flavour}-${var.release}"

  # The recipe plus the parts of this build, merged: a key of a part replaces the recipe's, and a
  # part's commands run before the recipe's, in the order the parts are listed.
  recipe = yamldecode(file("${path.root}/autoinstall/user-data")).autoinstall
  parts = concat(
    var.origin == "bench" ? [yamldecode(file("${path.root}/autoinstall/bench.yaml")).autoinstall] : [],
    [yamldecode(file("${path.root}/autoinstall/vagrant.yaml")).autoinstall],
    # the mirror for the release, its -updates and its -security alike, in curtin's form, which every
    # installer from 22.04 on takes; it replaces vagrant.yaml's apt, whose geoip it keeps
    [for uri in(var.mirror == "" ? [] : [var.mirror]) : {
      apt = {
        geoip    = false
        primary  = [{ arches = ["default"], uri = uri }]
        security = [{ arches = ["default"], uri = uri }]
      }
    }],
  )
  commands = {
    for key in ["early-commands", "late-commands", "error-commands"] :
    key => concat(flatten([for part in local.parts : lookup(part, key, [])]), lookup(local.recipe, key, []))
  }
  autoinstall = merge(merge(concat([local.recipe], local.parts)...), local.commands)
  user_data   = "#cloud-config\n${yamlencode({ autoinstall = local.autoinstall })}"

  # origin bench: the boot line names the setup script served beside user-data
  setup_arg = var.origin == "bench" ? " minos.setup=http://{{ .HTTPIP }}:{{ .HTTPPort }}/setup" : ""
}

source "qemu" "minos" {
  iso_url      = local.isos[var.release].url
  iso_checksum = local.isos[var.release].checksum

  vm_name            = "${local.name}.qcow2"
  output_directory   = "${var.output}/${local.name}"
  accelerator        = "kvm"
  cpus               = var.cpus
  memory             = var.memory
  disk_size          = var.disk_size
  format             = "qcow2"
  disk_interface     = "virtio"
  disk_discard       = "unmap"
  disk_detect_zeroes = "unmap"
  net_device         = "virtio-net"
  headless           = true
  # what the installer says when it fails (vagrant.yaml, error-commands)
  qemuargs = [["-serial", "file:${var.output}/${local.name}.serial.log"]]

  http_content = merge(
    { "/user-data" = local.user_data, "/meta-data" = "" },
    { for served, script in { "/setup" = var.setup } : served => file(script) if var.origin == "bench" },
  )
  cd_files = var.origin == "bench" ? ["${var.bench}/*"] : []
  cd_label = "bench"

  # BIOS, as VirtualBox starts an imported machine. GRUB of the ISO: its command line, the installer's
  # kernel with autoinstall, the recipe served by Packer and the flavour. One line of commands: GRUB
  # reads no keys while it loads the kernel from the CD, so a line typed after `linux` can be lost
  # (the kernel then boots without its initrd and cannot find a root)
  boot_wait = "10s"
  boot_command = [
    "c<wait>",
    "linux /casper/vmlinuz autoinstall ds=nocloud-net\\;s=http://{{ .HTTPIP }}:{{ .HTTPPort }}/ minos=${var.flavour}${local.setup_arg} --- ; initrd /casper/initrd ; boot<enter>",
  ]

  communicator     = "ssh"
  ssh_username         = "vagrant"
  ssh_private_key_file = var.ssh_key
  ssh_timeout          = "90m"
  shutdown_command     = "sudo shutdown -P now"
}

build {
  sources = ["source.qemu.minos"]

  # box.sh puts the Ubuntu archive itself back where the installer wrote the mirror
  provisioner "shell" {
    environment_vars = ["MIRROR=${var.mirror}"]
    execute_command  = "sudo env {{ .Vars }} sh '{{ .Path }}'"
    script           = "${path.root}/scripts/box.sh"
  }

  post-processor "shell-local" {
    inline = ["sh '${path.root}/scripts/export.sh' '${var.output}/${local.name}/${local.name}.qcow2' '${var.output}' '${local.name}'"]
  }
}

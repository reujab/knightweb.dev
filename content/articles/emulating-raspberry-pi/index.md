---
title: How to Emulate Raspberry Pi OS
authors: [Christopher Knight]
date: 2024-08-04
updated: 2024-08-11
description: Learn how to emulate a Raspberry Pi (32- or 64-bit) with graphics support using QEMU by
  creating an initrd that loads virtio_gpu.
extra:
  notes: Fixed resizing instructions overwriting <code>$loop</code>
---

I'd like to share my technique on emulating a Raspberry Pi OS image, which involves creating an initrd that loads virtio_gpu, allowing graphical emulation with QEMU.

This technique:

- Does not require access to a Raspberry Pi
- Does not modify the image[^1]
- Does not emulate Raspberry Pi hardware
- Allows GPU emulation
- Works for a backup image or an image downloaded from [the Raspberry Pi website](https://www.raspberrypi.com/software/operating-systems/)

[^1]: Any changes you make in the guest VM will reflect to the .img file. Copy it to preserve the original.

You will learn:

1. How to install Debian (32- or 64-bit arm)
2. How to modify the initrd to include virtio_gpu and other modules
3. How to boot an unmodified Raspberry Pi image using the modified initrd

<!-- more -->

## Setup

### 64-bit

```bash
sudo apt install qemu-system-aarch64 qemu-efi-aarch64
```

If you are not using Debian, you can download the EFI firmware from [packages.debian.org](https://packages.debian.org/sid/all/qemu-efi-aarch64/download).

```bash
alias q64='qemu-system-aarch64 -M virt -cpu cortex-a72 -smp $(nproc) -m 2G -device usb-ehci -device usb-kbd -device virtio-gpu-pci'
```

- `-M virt` uses generic virtual machine hardware
- `-cpu cortex-a72` is a fast and well-supported CPU
- `-smp $(nproc)` uses the maximum number of threads
- `-m 2G` allocates 2 GB of virtual RAM
- `-device usb-ehci -device usb-kbd` enables virtual keyboard
- `-device virtio-gpu-pci` enables virtual GPU

Network emulation should work by default, but if that's not the case for you, you can copy the `-netdev` and `-device` arguments from the following 32-bit section.

### 32-bit

```bash
sudo apt install qemu-system-arm
alias q32='qemu-system-arm -M virt -cpu cortex-a15 -smp $(nproc) -m 2G -netdev user,id=net0 -device virtio-net-device,netdev=net0'
```

- `-M virt` enables generic virtual machine hardware
- `-cpu cortex-a15` is a fast and well-supported cpu
- `-smp $(nproc)` uses the maximum number of threads
- `-m 2G` allocates 2 GB of virtual RAM
- `-netdev ... -device virtio-net-device...` enables network support

## Downloads (optional)

If you're not the DIY type, you can download my kernel and skip to [Resizing the Raspberry Pi image](#resizing-the-raspberry-pi-image-optional):

- [arm64 kernel](/downloads/vmlinuz-6.1.0-23-arm64) and [initrd](/downloads/initrd.img-6.1.0-23-arm64)
- [armmp-lpae kernel](/downloads/vmlinuz-6.1.0-23-armmp-lpae) and [initrd](/downloads/initrd.img-6.1.0-23-armmp-lpae)

## Installing Debian

You cannot boot the Raspberry Pi's kernel and initrd with QEMU, so you have to build your own that play nice with QEMU. (Wim, 2023a; 2023b) To do this, you will be installing Debian arm in a virtual machine.

Create the image to which you will install Debian:

```bash
qemu-img create debian.img 4G
```

### 64-bit

Download [Debian arm64](https://cdimage.debian.org/cdimage/release/current/arm64/iso-cd/). EFI targets are the easiest to emulate; you simply need to provide a firmware file. (Wookey et al., 2023)

```bash
q64 -bios /usr/share/qemu-efi-aarch64/QEMU_EFI.fd \
	-cdrom debian-arm64-netinst.iso \
	-drive format=raw,file=debian.img
```

Install Debian and reboot into the new system. Be careful; if you power off the guest, you will not be able to boot back into the system without extra parameters (`-kernel` and `-initrd`).

### 32-bit

Download [Debian armhf](https://cdimage.debian.org/cdimage/release/current/armhf/iso-cd/) and mount the ISO to access the kernel and initrd.

```bash
sudo mount debian-armhf-netinst.iso /mnt

q32 -drive format=raw,file=debian.img,if=none,id=hd0 \
    -device virtio-blk-device,drive=hd0 \
    -drive format=raw,file=debian-armhf-netinst.iso,if=none,id=hd1 \
    -device virtio-blk-device,drive=hd1 \
    -kernel /mnt/install.ahf/vmlinuz \
    -initrd /mnt/install.ahf/initrd.gz \
    -nographic -serial mon:stdio
```

Adapted from "Run ARM/MIPS Debian on QEMU" (Lazymio, 2021).

Install Debian and reboot. It will reboot back into the installer; to exit, press <kbd>Ctrl+a</kbd> <kbd>x</kbd>. To boot into the new system, you will have to change the kernel and initrd.

```bash
# Host

sudo umount /mnt
loop=$(sudo losetup -fP --show debian.img)
sudo mount ${loop}p1 /mnt

q32 -drive format=raw,file=debian.img,if=none,id=hd0 \
    -device virtio-blk-device,drive=hd0 \
    -kernel /mnt/vmlinuz \
    -initrd /mnt/initrd.img \
    -nographic -serial mon:stdio
```

## Modifying the initrd

Now you need to modify the initrd to load the necessary kernel modules during boot. The virtio_gpu module enables GPU virtualization, while the other modules allow mounting /boot/firmware.

```bash
# Debian guest

echo virtio_gpu >> /etc/initramfs-tools/modules
echo nls_ascii >> /etc/initramfs-tools/modules
echo nls_cp437 >> /etc/initramfs-tools/modules
echo vfat >> /etc/initramfs-tools/modules
update-initramfs -u
shutdown now
```

## Mounting debian.img (64-bit)

```bash
# Host

loop=$(sudo losetup -fP --show debian.img)
sudo mount ${loop}p2 /mnt
```

## Remounting debian.img (32-bit)

You will need to remount the boot partition to use the updated initrd.

```bash
# Host

umount /mnt
sync
mount ${loop}p1 /mnt
```

## Resizing the Raspberry Pi image (optional)

If you downloaded an image file from the Raspberry Pi website, you should expand the root file system, as it won't be done automatically.

```bash
fallocate -l8G raspi.img
parted raspi.img resizepart 2 100%
rpi_loop=$(sudo losetup -fP --show raspi.img)
sudo resize2fs ${rpi_loop}p2
sudo losetup -d $rpi_loop
```

## Booting the Raspberry Pi image

You will see "Display is not active" but within a minute you should have output. You will be prompted to configure the keyboard layout, create a user, etc.

### 64-bit

```bash
q64 -drive format=raw,file=raspi.img \
	-kernel /mnt/boot/vmlinuz \
	-initrd /mnt/boot/initrd.img \
	-append 'root=/dev/vda2 console=tty1'
```

### 32-bit

```bash
q32 -drive format=raw,file=raspi.img,if=none,id=hd0 \
    -device virtio-blk-device,drive=hd0 \
    -kernel /mnt/vmlinuz \
    -initrd /mnt/initrd.img \
    -append 'root=/dev/vda2 console=tty1' \
    -device usb-ehci -device usb-kbd \
    -device virtio-gpu-pci
```

Congratulations, you're emulating Raspberry Pi OS with graphics support.

{{ lazy_img(alt="VM screenshot", src="vm_screenshot.png") }}

## Cleanup

```bash
sudo umount /mnt
sudo losetup -d $loop
```

## "Cannot open access to console, the root account is locked"

This message appears when the boot fails and tries to start an emergency session, but the root account is locked. To figure out what went wrong, you'll have to enable the root account.

```bash
# Host

rpi_loop=$(sudo losetup -fP --show raspi.img)
mkdir /tmp/rpi
sudo mount ${rpi_loop}p2 /tmp/rpi
sudo sed -i '1 s/!//' /tmp/rpi/etc/shadow
sudo umount /tmp/rpi
sudo losetup -d $rpi_loop
```

Reboot into the image, where you will now have access to the emergency shell and can troubleshoot what failed with `systemctl --failed`. To enable network access in the emergency shell, run `ip link set enp0s1 up && dhclient enp0s1`.

# References

- Lazymio. (2021). "Run ARM/MIPS Debian on QEMU." <https://blog.lazym.io/2021/04/16/Run-ARM-MIPS-Debian-on-QEMU/>.
- Wim. (2023a). "Raspberry Pi 4 Emulation with QEMU Virt." <https://blog.grandtrunk.net/2023/03/raspberry-pi-4-emulation-with-qemu/>.
- Wim. (2023b). StackExchange. <https://raspberrypi.stackexchange.com/a/142609>.
- Wookey, Wise P., Walton J., Zhu S., Matsumoto R., Staudt J. C., & Thibault S. (2023). "Arm64Qemu." Debian Wiki. <https://wiki.debian.org/Arm64Qemu>.

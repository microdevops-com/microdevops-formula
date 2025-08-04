# Usage

- Update the pillar if migrating from LXD to Incus:
  - Rename top level key from `lxd` to `incus`
  - Rename pillar file and change top.sls if needed
  - Remove password key - Incus doesn't support password authentication

- Add needed pillar to the target server, see `pillar.example`.

- `state.apply incus.install` - to install or update incus without initializing it

- Sometimes downgrade of LXD is needed, for example when `lxd-to-incus (Error: LXD version is newer than maximum version "5.21.99")`
  - `snap stop --disable lxd`
  - `snap refresh lxd --channel=5.21/stable`
  - `snap start --enable lxd`

- Make migration from LXD manually if needed right after after install and before incus init: https://linuxcontainers.org/incus/docs/main/howto/server_migrate_lxd/
  - Stop containers and VMs manually, sometimes there are issues on stopping them
  - `lxc config unset core.trust_password`
  - `lxd-to-incus`
  - `incus ls` to check if all containers and VMs are migrated
  - Remove snapd optionally:
    - `apt autoremove --purge snapd`
    - `rm -rf ~/snap /var/cache/snapd/`
    - `apt-mark hold snapd`

- `state.apply incus.settings` - to initialize Incus and apply settings, update images and profiles

- Add storage manually and make it default:
  - `incus storage create vg_mdX lvm source=vg_mdX lvm.use_thinpool=false` - thinpool is not recommended for prod, but can be used for dev.
  - `incus profile device remove default root`
  - `incus storage delete default`
  - `incus profile device add default root disk path=/ pool=vg_mdX type=disk size=10GB` - you can set root disk size only after container init, so we need to set default root size in default profile withith created storage pool.
This volume will be resized after pillar apply and it should contain enough space to contain base OS image.

- Apply only specific instances
```
... state.apply incus.instances pillar='{incus: {only: {"instance1.example.com"}}}'
```

- The same with allowance stop and start for changes to apply
```
... state.apply incus.instances pillar='{incus: {only: {"instance1.example.com"}, allow_stop_start: True}}'
```

# Notes on Windows

- If you delete VM and try to create the same, it may fail on "invalid main GPT header".
  You can fix this with just changing the disk size for 1 Gb. With thin provisioning in storage this bug is not reproduced.

- To install Windows from iso you need to have virtio drivers injected into iso:
  - Download ISO to server with VM.
  - `snap install distrobuilder --classic`
  - `apt-get install genisoimage libwin-hivex-perl wimtools`
  - `distrobuilder repack-windows Windows.iso Windows-distrobuilder.iso` - it will download drivers and inject them into iso.

- To attach to VGA console on VM from your PC:
  - `apt-get install virt-viewer` - this will install X11 dependencies, this is OK.
  - Install X11 server on your PC, for example https://github.com/ArcticaProject/vcxsrv.
  - Run X11 server on your PC.
  - SSH from your PC to the server with VM as root and enable X11 forwarding in SSH.
  - Check that `DISPLAY` variable is set in SSH session, like `localhost:10.0`.
  - `incus console xxx --type=vga` - this will open console in X11 window.

- You need to catch with `incus console xxx --type=vga` the first seconds of start to push any key to load from iso.
  If you didn't catch the first seconds, wait while PXE etc timeouts and EUFI shell loads.
  Then type `cls` to clear screen.
  Then type `FS0:\EFI\BOOT\BOOTX64.EFI` to load from iso, you also need to push any key immediately after this command.

- To configure network manually on Windows install:
  - Wait till the screen with "Let's connect you to a network" appears.
  - Push `Shift+F10` to open command prompt.
  - `netsh interface ip set address name="Local Area Connection" static 10.0.0.2 255.255.255.0 10.0.0.1 1`
  - `netsh interface ip set dns "Local Area Connection" static 192.168.0.200`
  - Ofcourse you need to change IP addresses according to your network.

- Useful docs:
  Agent notes: https://discuss.linuxcontainers.org/t/running-windows-vm-in-lxd-is-there-an-lxd-agent-for-winodws/11792
  How to install Windows: https://discuss.linuxcontainers.org/t/how-to-run-a-windows-virtual-machine-on-lxd-on-linux/10397
  Console attach: https://discuss.linuxcontainers.org/t/vga-console-connect/8814/6

- TPM device (needed for Windows 11):
  https://discuss.linuxcontainers.org/t/lxd-4-8-has-been-released/9458
  and maybe (not sure) https://getlabsdone.com/how-to-enable-tpm-and-secure-boot-on-kvm/

- Youtube tutorial on Windows 11: https://www.youtube.com/watch?v=3PDMGwbbk48

- Make sure you have limits.cpu set for Windows 11, it will not allow install with unlimited CPU.

- ISO with Windows drivers: https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/archive-virtio/

# Notes on VMs and Ubuntu

In case an Instance is Virtual-Machine you need to grow internal root partition size:
```
incus stop ...
lvchange --setactivationskip n /dev/vg_md2/virtual-machines_...block
lvchange --activate y /dev/vg_md2/virtual-machines_...block
parted /dev/vg_md2/virtual-machines_...block
  resizepart 2
  100%
  q
kpartx -a /dev/vg_md2/virtual-machines_...block
e2fsck -f  /dev/mapper/vg_md2-virtual--machines_...block2
resize2fs /dev/mapper/vg_md2-virtual--machines_...block2
kpartx -d /dev/vg_md2/virtual-machines_test.block
incus start ...
```

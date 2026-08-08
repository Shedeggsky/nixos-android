#!/usr/bin/env bash
set -e

echo "NixOS install script executed"

pkg update -y
pkg install -y proot curl wget squashfs-tools-ng tar xz-utils

NIXOS_DIR="$HOME/nixos-fs"
mkdir -p "$NIXOS_DIR"

ARCH=$(uname -m)
case "$ARCH" in
    aarch64) ARCH_URL="arm64" ;;
    armv7l|armv8l) ARCH_URL="armhf" ;;
    x86_64) ARCH_URL="amd64" ;;
    *) echo "[-] Unsupported arch: $ARCH"; exit 1 ;;
esac

NIXOS_VERSION="26.05"
BASE_URL="https://images.linuxcontainers.org/images/nixos/${NIXOS_VERSION}/${ARCH_URL}/default"

echo "[+] Finding latest NixOS (${NIXOS_VERSION}) build"
LATEST_BUILD=$(curl -sL "$BASE_URL" | grep -oE '20[0-9]{6}_[0-9]{2}:[0-9]{2}' | tail -n 1 | tr -d '"/' )

if [ -z "$LATEST_BUILD" ]; then
    echo "[-] Error: Couldn't parse latest build timestamp from LXC mirror."
    exit 1
fi

ROOTFS_URL="${BASE_URL}/${LATEST_BUILD}/rootfs.squashfs"

echo "[+] Found version: ${NIXOS_VERSION}, build: ${LATEST_BUILD}"
echo "[+] Downloading NixOS from: ${ROOTFS_URL}"

wget --show-progress -O "$HOME/rootfs.squashfs" "$ROOTFS_URL"
mkdir -p "$NIXOS_DIR"

echo "[+] Extracting rootfs into $NIXOS_DIR"
sqfs2tar -r . "$HOME/rootfs.squashfs" | tar -xf - -C "$NIXOS_DIR"
rm -f "$HOME/rootfs.squashfs"

mkdir -p "$NIXOS_DIR/etc"
rm -rf "$NIXOS_DIR/etc/resolv.conf"
echo "nameserver 8.8.8.8" > "$NIXOS_DIR/etc/resolv.conf"
echo "nameserver 1.1.1.1" >> "$NIXOS_DIR/etc/resolv.conf"

mkdir -p "$NIXOS_DIR/root"
chmod -R 777 "$NIXOS_DIR/root" 2>/dev/null || true
rm -f "$NIXOS_DIR/root/nixfirst_boot.sh"

cat << 'EOF' > "$NIXOS_DIR/root/nixfirst_boot.sh"
#!/bin/sh
if [ ! -f /root/.initialized ]; then
    echo "Installing necessary packages"
    nix-channel --update || true
    nix-env -iA nixos.xterm nixos.tigervnc 2>/dev/null || nix-env -i xterm tigervnc || true
    touch /root/.initialized
fi
EOF

cat << 'EOF' > "$HOME/nixos.sh"
#!/usr/bin/env bash
NIXOS_DIR="$HOME/nixos-fs"

if [ ! -d "$NIXOS_DIR" ]; then
    echo "[-] Error: NixOS filesystem not found at $NIXOS_DIR"
    exit 1
fi

cd $(dirname $0)
unset LD_PRELOAD

# Find the actual bash binary inside the Nix store container
STORE_BASH=$(ls -d "$NIXOS_DIR"/nix/store/*-bash-*/bin/bash 2>/dev/null | head -n 1)
if [ -z "$STORE_BASH" ]; then
    echo "[-] Error: Could not find bash in Nix store."
    exit 1
fi
CONTAINER_BASH="${STORE_BASH#$NIXOS_DIR}"

clear
echo "=================================================="
echo " NixOS                                            "
echo " To install packages: nix-env -iA nixos.(package) "
echo "=================================================="
echo ""

exec proot --link2symlink -i 0:3003 -r nixos-fs \
    -b /dev -b /proc -b nixos-fs/root:/dev/shm -w /root \
    /usr/bin/env -i \
    HOME=/root \
    TERM="$TERM" \
    PATH="/run/current-system/sw/bin:/bin:/usr/bin:/sbin:/usr/sbin" \
    LANG="en_US.UTF-8" \
    LC_ALL="C" \
    "$CONTAINER_BASH"
EOF

chmod +x "$HOME/nixos.sh"

echo ""
echo "=================================================="
echo "  NixOS installed successfully."
echo "  Start NixOS using ./nixos.sh"
echo "=================================================="

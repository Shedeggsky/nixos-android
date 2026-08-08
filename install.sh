#!/usr/bin/env bash
set -e

echo "Currently bugged"
echo "Will be archived if I somehow dont fix this"
sleep 3
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

mkdir -p "$NIXOS_DIR/root" \
         "$NIXOS_DIR/tmp" \
         "$NIXOS_DIR/dev/shm" \
         "$NIXOS_DIR/usr/bin" \
         "$NIXOS_DIR/bin" \
         "$NIXOS_DIR/etc" \
         "$NIXOS_DIR/var/nix/profiles"

STORE_BASH=$(ls -d "$NIXOS_DIR"/nix/store/*-bash-*/bin/bash 2>/dev/null | head -n 1)
STORE_ENV=$(ls -d "$NIXOS_DIR"/nix/store/*-coreutils-*/bin/env 2>/dev/null | head -n 1)
STORE_COREUTILS=$(ls -d "$NIXOS_DIR"/nix/store/*-coreutils-*/bin 2>/dev/null | head -n 1)
STORE_NIX=$(ls -d "$NIXOS_DIR"/nix/store/*-nix-*/bin 2>/dev/null | head -n 1)

if [ -z "$STORE_BASH" ] || [ -z "$STORE_ENV" ]; then
    echo "[-] Error: Could not find required binaries in Nix store."
    exit 1
fi

CONTAINER_BASH="${STORE_BASH#$NIXOS_DIR}"
CONTAINER_ENV="${STORE_ENV#$NIXOS_DIR}"
COREUTILS_BIN_PATH="${STORE_COREUTILS#$NIXOS_DIR}"
NIX_BIN_PATH="${STORE_NIX#$NIXOS_DIR}"

clear
echo "=================================================="
echo " NixOS                                            "
echo " To install packages: nix-env -iA nixos.(package)"
echo "=================================================="
echo ""

unset LD_PRELOAD
exec proot --link2symlink -i 0:3003 -r "$NIXOS_DIR" \
    -b /dev -b /proc -b "$NIXOS_DIR/dev/shm:/dev/shm" -w /root \
    "$CONTAINER_ENV" -i \
    HOME=/root \
    TERM="$TERM" \
    PATH="$NIX_BIN_PATH:$COREUTILS_BIN_PATH:/root/.nix-profile/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/bin:/bin" \
    LANG="en_US.UTF-8" \
    "$CONTAINER_BASH" --login
EOF

chmod +x "$HOME/nixos.sh"


echo ""
echo "=================================================="
echo "  NixOS installed successfully."
echo "  Start NixOS using ./nixos.sh"
echo "=================================================="

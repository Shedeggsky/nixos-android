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

# 1. Create essential directory structure inside rootfs
mkdir -p "$NIXOS_DIR/root" \
         "$NIXOS_DIR/tmp" \
         "$NIXOS_DIR/dev/shm" \
         "$NIXOS_DIR/usr/bin" \
         "$NIXOS_DIR/bin" \
         "$NIXOS_DIR/etc/nix" \
         "$NIXOS_DIR/etc/ssl/certs" \
         "$NIXOS_DIR/var/nix/profiles"

# 2. Mock /proc/stat to fix Android SELinux /proc restrictions
cat << 'STAT' > "$NIXOS_DIR/tmp/fake_proc_stat"
cpu  0 0 0 0 0 0 0 0 0 0
cpu0 0 0 0 0 0 0 0 0 0 0
STAT

# 3. Configure Nix for PRoot (disable sandboxing and multi-user nixbld requirements)
cat << 'NIXCONF' > "$NIXOS_DIR/etc/nix/nix.conf"
build-users-group =
sandbox = false
NIXCONF

touch "$NIXOS_DIR/etc/passwd" "$NIXOS_DIR/etc/group"
grep -q "nixbld" "$NIXOS_DIR/etc/group" 2>/dev/null || echo "nixbld:x:30000:" >> "$NIXOS_DIR/etc/group"

# 4. Locate SSL CA certificates in Nix store and configure symlinks
CERT_PATH=$(ls -d "$NIXOS_DIR"/nix/store/*-cacert-*/etc/ssl/certs/ca-bundle.crt 2>/dev/null | head -n 1)
if [ -n "$CERT_PATH" ]; then
    CONTAINER_CERT="${CERT_PATH#$NIXOS_DIR}"
    ln -sf "$CONTAINER_CERT" "$NIXOS_DIR/etc/ssl/certs/ca-certificates.crt"
    ln -sf "$CONTAINER_CERT" "$NIXOS_DIR/etc/ssl/certs/ca-bundle.crt"
else
    CONTAINER_CERT="/etc/ssl/certs/ca-certificates.crt"
fi

# 5. Find essential container binaries (bash, env)
STORE_BASH=$(ls -d "$NIXOS_DIR"/nix/store/*-bash-*/bin/bash 2>/dev/null | head -n 1)
STORE_ENV=$(ls -d "$NIXOS_DIR"/nix/store/*-coreutils-*/bin/env 2>/dev/null | head -n 1)

if [ -z "$STORE_BASH" ] || [ -z "$STORE_ENV" ]; then
    echo "[-] Error: Could not find required binaries in Nix store."
    exit 1
fi

CONTAINER_BASH="${STORE_BASH#$NIXOS_DIR}"
CONTAINER_ENV="${STORE_ENV#$NIXOS_DIR}"

# 6. Dynamically harvest utility bin paths from the Nix store for PATH
STORE_PATHS=""
for d in "$NIXOS_DIR"/nix/store/*-{coreutils,nix,bash,binutils,findutils,grep,sed,gnumake,cacert,curl}*/bin; do
    if [ -d "$d" ]; then
        STORE_PATHS="${d#$NIXOS_DIR}:$STORE_PATHS"
    fi
done

clear
echo "=================================================="
echo " NixOS Container Launched                         "
echo " To install packages: nix-env -iA nixos.(package) "
echo "=================================================="
echo ""

unset LD_PRELOAD
exec proot --link2symlink -i 0:3003 -r "$NIXOS_DIR" \
    -b /dev \
    -b /proc \
    -b "$NIXOS_DIR/tmp/fake_proc_stat:/proc/stat" \
    -b "$NIXOS_DIR/dev/shm:/dev/shm" \
    -w /root \
    "$CONTAINER_ENV" -i \
    HOME=/root \
    TERM="$TERM" \
    GC_QUIET=1 \
    NIX_SSL_CERT_FILE="$CONTAINER_CERT" \
    SSL_CERT_FILE="$CONTAINER_CERT" \
    PATH="${STORE_PATHS}/root/.nix-profile/bin:/nix/var/nix/profiles/default/bin:/usr/bin:/bin" \
    LANG="en_US.UTF-8" \
    "$CONTAINER_BASH" --login
EOF

chmod +x "$HOME/nixos.sh"


echo ""
echo "=================================================="
echo "  NixOS installed successfully."
echo "  Start NixOS using ./nixos.sh"
echo "=================================================="

#!/usr/bin/env bash
set -Eeuo pipefail

trap 'echo ""; echo "[!] installer failed on line $LINENO"; exit 1' ERR

echo "================================="
echo "NixOS 26.05"
echo "PRoot Android build"
echo "================================="
sleep 2

pkg update -y
pkg install -y proot curl wget squashfs-tools-ng tar xz-utils

NIXOS_DIR="$HOME/nixos-fs"
ROOTFS="$HOME/rootfs.squashfs"
VERSION="26.05"

case "$(uname -m)" in
    aarch64) ARCH="arm64" ;;
    armv7l|armv8l) ARCH="armhf" ;;
    x86_64) ARCH="amd64" ;;
    *) echo "[!] unsupported architecture"; exit 1 ;;
esac

BASE="https://images.linuxcontainers.org/images/nixos/$VERSION/$ARCH/default"

echo "[!] finding latest build"

BUILD=$(curl -fsSL "$BASE/" |
    grep -oE '20[0-9]{6}_[0-9]{2}:[0-9]{2}' |
    sort |
    tail -n 1)

[ -n "$BUILD" ] || {
    echo "[!] could not find a build"
    exit 1
}

URL="$BASE/$BUILD/rootfs.squashfs"

echo "[!] found $BUILD"
echo "[!] downloading rootfs"

wget --show-progress -O "$ROOTFS" "$URL"

echo "[!] extracting"

rm -rf "$NIXOS_DIR"
mkdir -p "$NIXOS_DIR"

sqfs2tar -r . "$ROOTFS" |
    tar -xf - -C "$NIXOS_DIR"

rm -f "$ROOTFS"

echo "[!] setting up"

mkdir -p \
    "$NIXOS_DIR/root" \
    "$NIXOS_DIR/tmp" \
    "$NIXOS_DIR/dev/shm" \
    "$NIXOS_DIR/usr/local/bin" \
    "$NIXOS_DIR/etc/nix" \
    "$NIXOS_DIR/etc/ssl/certs"

chmod 1777 "$NIXOS_DIR/tmp" 2>/dev/null || true

cat > "$NIXOS_DIR/etc/resolv.conf" <<'EOF'
nameserver 1.1.1.1
nameserver 8.8.8.8
EOF

cat > "$NIXOS_DIR/etc/nix/nix.conf" <<'EOF'
sandbox = false
build-users-group =
experimental-features = nix-command flakes
EOF

[ -f "$NIXOS_DIR/etc/passwd" ] || cat > "$NIXOS_DIR/etc/passwd" <<'EOF'
root:x:0:0:root:/root:/bin/bash
nobody:x:65534:65534:nobody:/nonexistent:/bin/sh
EOF

[ -f "$NIXOS_DIR/etc/group" ] || cat > "$NIXOS_DIR/etc/group" <<'EOF'
root:x:0:
users:x:100:
nixbld:x:30000:
nogroup:x:65534:
EOF

grep -q '^nixbld:' "$NIXOS_DIR/etc/group" 2>/dev/null ||
    echo "nixbld:x:30000:" >> "$NIXOS_DIR/etc/group"

CERT=$(find "$NIXOS_DIR/nix/store" \
    -path '*/etc/ssl/certs/ca-bundle.crt' \
    -type f 2>/dev/null | head -n 1 || true)

if [ -n "$CERT" ]; then
    CERT="${CERT#$NIXOS_DIR}"
    ln -sf "$CERT" "$NIXOS_DIR/etc/ssl/certs/ca-certificates.crt"
    ln -sf "$CERT" "$NIXOS_DIR/etc/ssl/certs/ca-bundle.crt"
fi

findbin() {
    find "$NIXOS_DIR/nix/store" \
        -maxdepth 1 \
        -type d \
        -name "*$1*" 2>/dev/null |
        sort |
        head -n 1
}

BASH_PATH=$(findbin "-bash-")
CORE_PATH=$(findbin "-coreutils-")
NIX_PATH=$(findbin "-nix-")
FIND_PATH=$(findbin "-findutils-")
GREP_PATH=$(findbin "-grep-")
SED_PATH=$(findbin "-gnused-")
CURL_PATH=$(findbin "-curl-")

echo "[!] checking packages"

if [ -z "$BASH_PATH" ]; then
    echo "[!] bash not found"
    exit 1
fi

if [ -z "$CORE_PATH" ]; then
    echo "[!] coreutils not found"
    exit 1
fi

if [ -z "$NIX_PATH" ]; then
    echo "[!] nix not found"
    exit 1
fi

addbin() {
    [ -d "$1/bin" ] || return 0

    for x in "$1/bin/"*; do
        [ -e "$x" ] || continue

        n=$(basename "$x")

        [ -e "$NIXOS_DIR/usr/local/bin/$n" ] ||
            ln -s "$x" "$NIXOS_DIR/usr/local/bin/$n"
    done
}

echo "[!] linking packages"

addbin "$CORE_PATH"
addbin "$BASH_PATH"
addbin "$NIX_PATH"
addbin "$FIND_PATH"
addbin "$GREP_PATH"
addbin "$SED_PATH"
addbin "$CURL_PATH"

mkdir -p "$NIXOS_DIR/bin"

ln -sf /usr/local/bin/bash "$NIXOS_DIR/bin/bash"
ln -sf /usr/local/bin/bash "$NIXOS_DIR/bin/sh"

if [ ! -x "$NIXOS_DIR/usr/local/bin/ls" ]; then
    echo "[!] coreutils setup failed"
    exit 1
fi

if [ ! -x "$NIXOS_DIR/usr/local/bin/bash" ]; then
    echo "[!] bash setup failed"
    exit 1
fi

cat > "$NIXOS_DIR/etc/os-release" <<'EOF'
NAME="NixOS"
ID=nixos
VERSION="26.05"
VERSION_ID="26.05"
PRETTY_NAME="NixOS 26.05"
EOF

cat > "$NIXOS_DIR/tmp/fake_proc_stat" <<'EOF'
cpu  0 0 0 0 0 0 0 0 0 0
cpu0 0 0 0 0 0 0 0 0 0
EOF

cat > "$NIXOS_DIR/root/nixfirst_boot.sh" <<'EOF'
#!/bin/sh
echo "[!] nixos userspace ready"
nix --version 2>/dev/null || true
touch /root/.initialized
EOF

chmod +x "$NIXOS_DIR/root/nixfirst_boot.sh"

echo "[!] creating launcher"

cat << 'EOF' > "$HOME/nixos.sh"
#!/usr/bin/env bash

NIXOS_DIR="$HOME/nixos-fs"

[ -d "$NIXOS_DIR" ] || {
    echo "[!] nixos not installed"
    exit 1
}

[ -x "$NIXOS_DIR/usr/local/bin/bash" ] || {
    echo "[!] bash missing"
    exit 1
}

[ -x "$NIXOS_DIR/usr/local/bin/ls" ] || {
    echo "[!] coreutils missing"
    exit 1
}

clear

echo "================================="
echo "NixOS 26.05"
echo "PRoot | Very Unstable"
echo "================================="
echo ""
echo "To install packages"
echo "nix-env -iA nixpkgs.package"
echo ""
echo "Starting"

for x in '|' '/' '-' '\'; do
    printf "\r[%s] starting" "$x"
    sleep 0.15
done

printf "\r[+] started     \n"

unset LD_PRELOAD

exec proot \
    --link2symlink \
    -i 0:3003 \
    -r "$NIXOS_DIR" \
    -b /dev \
    -b /proc \
    -b "$NIXOS_DIR/tmp/fake_proc_stat:/proc/stat" \
    -b "$NIXOS_DIR/dev/shm:/dev/shm" \
    -w /root \
    /usr/local/bin/env \
        HOME=/root \
        TERM="${TERM:-xterm-256color}" \
        PATH="/usr/local/bin:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin" \
        LANG="C.UTF-8" \
        LC_ALL="C.UTF-8" \
        /usr/local/bin/bash \
        --noprofile \
        --norc
EOF

chmod +x "$HOME/nixos.sh"

if [ ! -x "$HOME/nixos.sh" ]; then
    echo "[!] launcher creation failed"
    exit 1
fi

echo ""
echo "================================="
echo "NixOS installed"
echo "Run ./nixos.sh"
echo "================================="

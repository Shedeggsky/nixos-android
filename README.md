# nixos-android
## Testing
### Very unstable (nix doesnt work, fastfetch works [if u modify the whole thing])
NixOS for Android (this time im dumber kool)

<img src="images/Screenshot_20260808_193213_Termux.jpg" width="500">

## Installation

Open Termux and `run` this command:
```bash
wget -qO- "https://raw.githubusercontent.com/Shedeggsky/nixos-android/main/install.sh" | bash
```

## Getting Started
To launch your NixOS container, `run`:
```bash
./nixos.sh
```

To temporarily fix PATH, `run`:
```
export PATH="/nix/store/3sa1v05jzj4qdv3n5r2v9wagpxgw0cxf-nix-2.34.8/bin:/root/.nix-profile/bin:/usr/local/bin:/nix/var/nix/profiles/default/bin:$PATH"
```

To exit the container sessioin, `run`:
```bash
exit
```

To delete NixOS, `run`:
```bash
rm -f nixos.sh
chmod -R +w "nixos-fs" 2>/dev/null || true
rm -rf -f --no-preserve-root nixos-fs
```

To permanently fix PATH, `run`: (i havent tested this yet)
```
NIX_BIN_DIR="$(ls -d "$NIXOS_DIR"/nix/store/*-nix-[0-9]*/bin 2>/dev/null | head -n 1)"
```
```
PATH="/root/.nix-profile/bin:$NIX_BIN_DIR:/usr/local/bin:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin"
```

## General Tips & Commands
Starting the VNC Server
Once inside the NixOS container, you can start the TigerVNC server using:
```bash
vncserver :(display) [for example, :1 for port 5901, :2 for port 5902 and so on.)
```
To kill the TigerVNC server, `run`:
```bash
vncserver :(display)
```

## Reminders
This sucks for beginners, tbh it was hard fixing path and coreutils

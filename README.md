# nixos-android
## Testing
NixOS for Android (this time im smarter kool)
## Installation

Open Termux and `run` this command:
```bash
wget -qO- "https://raw.githubusercontent.com/Shedeggsky/nixos-android/main/install.sh" | bash
```

## Getting Started
To launch your NixOS container, `run`:
```
./nixos.sh
```

To exit the container sessioin, `run`:
```
exit
```
## General Tips & Commands
Starting the VNC Server
Once inside the NixOS container, you can start the TigerVNC server using:
```
vncserver :(display) [for example, :1 for port 5901, :2 for port 5902 and so on.)
```
To kill the TigerVNC server, `run`:
```
vncserver :(display)
```

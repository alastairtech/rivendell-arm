# Rivendell Radio Automation Suite for ARM Devices
Welcome to the Rivendell Radio Automation Suite for ARM Devices repository. Here you will find the latest build, install and upgrade scripts and instructions. 

# Config Script
The rivendell-config.sh script is an all-in-one, menu-driven tool that supersedes the standalone buildlatest.sh and install.sh scripts. Run it on a system with no existing Rivendell install and it launches a guided installer (repositories, packages, database, audio storage). Run it on a system that already has Rivendell installed and it opens an admin menu covering reinstalling, upgrading, uninstalling, database and audio configuration, audio card setup, package holds, and building packages from source.

> **Supported operating systems:** Debian 11 (Bullseye), Debian 13 (Trixie), and Raspberry Pi OS are the only supported operating systems for this script.

#### Make sure curl is installed
```bash
sudo apt install curl
```
#### Download the config script
```bash
curl -o rivendell-config.sh https://raw.githubusercontent.com/alastairtech/rivendell-arm/refs/heads/main/rivendell-config.sh
```
#### Make the config script executable
```
chmod +x rivendell-config.sh
```
#### Run the script to build, install or configure Rivendell
```
sudo ./rivendell-config.sh
```
#### (Optional) Install it as a system command
So you can re-run it later as `rivendell-config` instead of keeping track of the script file:
```bash
sudo cp rivendell-config.sh /usr/local/bin/rivendell-config
sudo chmod +x /usr/local/bin/rivendell-config
sudo rivendell-config
```

# Holding A Rivendell Version
If you plan to use Rivendell in a production situation you should consider holding the installed packages from being upgraded during any system update. This means you'll stay on your currently install Rivendell version until you're ready to upgrade. The rest of your system will be able recieve package and security updates. Follow the commands below to hold your Rivendell packages.

#### Hold the currently installed packages
```bash
sudo apt-mark hold rivendell*
```
#### To release the hold on the installed packages so they can be upgraded
```bash
sudo apt-mark unhold rivendell*
```

# Upgrading Your System
Upgrading your Rivendell install can be done via the Debian package manager. Run the following commands to upgrade

#### Pull the latest packages
```bash
sudo apt update
```
#### Upgrade all Rivendell related packages
```bash
sudo apt upgrade rivendell*
```
#### Upgrade to the latest database version
```bash
sudo rddbmgr --modify
```
# Experimental Web Administration Interface Install Script
Coming soon...

# Debian Package Repository
The Rivendell 4 Debian package repository is avaliable using the details below to add to your system.

#### This repository is for ARM64 based systems. Use this if you're running a Raspberry Pi.
```bash
apt update && apt install -y curl gnupg
curl https://repo.edgeradio.org.au/rivendell-aarch64/public.gpg | gpg --yes --dearmor -o /usr/share/keyrings/openrepo-rivendell-aarch64.gpg
echo "deb [arch=any signed-by=/usr/share/keyrings/openrepo-rivendell-aarch64.gpg] https://repo.edgeradio.org.au/rivendell-aarch64/ stable main" > /etc/apt/sources.list.d/openrepo-rivendell-aarch64.list
apt update
```
#### This repository is for AMD64 based systems. Use this if you're using an Intel or AMD based system.
```bash
apt update && apt install -y curl gnupg
curl https://repo.edgeradio.org.au/rivendell-amd64/public.gpg | gpg --yes --dearmor -o /usr/share/keyrings/openrepo-rivendell-amd64.gpg
echo "deb [arch=any signed-by=/usr/share/keyrings/openrepo-rivendell-amd64.gpg] https://repo.edgeradio.org.au/rivendell-amd64/ stable main" > /etc/apt/sources.list.d/openrepo-rivendell-amd64.list
apt update
```

# Frequently Asked Questions
Coming soon...

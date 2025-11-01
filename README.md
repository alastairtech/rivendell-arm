# Rivendell Radio Automation Suite for ARM Devices
Welcome to the Rivendell Radio Automation Suite for ARM Devices repository. Here you will find the latest build, install and upgrade scripts and instructions. 

# Build Script
The buildlatest.sh script is an automated build system that generates Debian packages. It does not install or setup Rivendell. When running the script it will install all the required packages and ask you which version of Rivendell you wish to build. It will also install the Debian Multimedia Repository to be able to use the latest audio codec packages during the build. At this time the packages will only compile on Debian 12 Bookworm.

#### Make sure curl is installed
```bash
sudo apt install curl
```
#### Download the build script
```bash
curl -o buildlatest.sh https://raw.githubusercontent.com/alastairtech/rivendell-arm/refs/heads/main/buildlatest.sh
```
#### Make the build script executable
```
chmod +x buildlatest.sh
```
#### Run the build script to generate Rivendell Debian 
```
sudo ./buildlatest.sh
```

# Install Script
A fresh Rivendell 4 install script is avalibale for Debian 12 Bullseye systems. Download and install the lastest [Raspberry Pi OS](https://www.raspberrypi.com/software/) or [Armbian](https://www.armbian.com/download/?device_support=Standard%20support) and follow the commands below. At this time the pre-compiled packages only support Debian 12 Bookworm.

#### Make sure curl is installed
```bash
sudo apt install curl
```
#### Download the install script
```bash
curl -o install.sh https://raw.githubusercontent.com/alastairtech/rivendell-arm/refs/heads/main/install.sh
```
#### Make the install script executable
```
chmod +x install.sh
```
#### Run the script to install Rivendell
```
sudo ./install.sh
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

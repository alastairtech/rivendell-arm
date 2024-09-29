# Rivendell Radio Automation Suite for ARM Devices
Welcome to the Rivendell Radio Automation Suite for ARM Devices repository. Here you will find the latest build, install and upgrade scripts. 

# Build Script
The buildlatest.sh script is an automated build system that generates Debian packages. When running the script it will install all the required packages and ask you which version of Rivendell you wish to build. It will also install the Debian Multimedia Repository to be able to use the latest audio codec packages during the build.

```bash
# Make sure curl is installed
sudo apt install curl
```
```bash
# Download the build script
curl -o install.sh https://raw.githubusercontent.com/alastairtech/rivendell-arm/blob/main/buildlatest.sh
```
```
# Make the build script executable
chmod +x buildlatest.sh
```
```
# Run the build script to generate Rivendell Debian 
sudo ./buildlatest.sh
```

# Install Script
A fresh Rivendell 4 install script is avalibale for Debian 12 Bullseye systems. Download and install the lastest [Raspberry Pi OS](https://www.raspberrypi.com/software/) or [Armbian](https://www.armbian.com/download/?device_support=Standard%20support) and follow the commands below.

```bash
# Make sure curl is installed
sudo apt install curl
```
```bash
# Download the install script
curl -o install.sh https://raw.githubusercontent.com/alastairtech/rivendell-arm/blob/main/install.sh
```
```
# Make the install script executable
chmod +x install.sh
```
```
# Run the script to install Rivendell
sudo ./install.sh
```

# Holding A Rivendell Version
If you plan to use Rivendell in a production situation you should consider holding the installed packages from being upgraded during any system update. The means you'll stay on your chosen Rivendell version until you're ready to upgrade while the rest of your system can recieve security updates. Follow the commands below to hold your Rivendell packages.

```bash
# Hold the currently installed packages
sudo apt-mark hold rivendell*
```
```bash
# To release the hold on the installed packages so they can be upgraded
sudo apt-mark unhold rivendell*
```

# Upgrading Your System
Upgrading your Rivendell install can be done via the Debian package manager. Run the following commands to upgrade

```bash
# Pull the latest packages
sudo apt update
```
```bash
# Upgrade all Rivendell related packages
sudo apt upgrade rivendell*
```
```bash
# Upgrade to the latest database version
sudo rddbmgr --modify
```

# Debian Package Repository
The Rivendell 4 Debian package repository is avaliable using the details below to add to your system.

```bash
# This repository is for ARM64 based systems. Use this if you're running a Raspberry Pi.
apt update && apt install -y curl gnupg
curl https://repo.edgeradio.org.au/rivendell-aarch64/public.gpg | gpg --yes --dearmor -o /usr/share/keyrings/openrepo-rivendell-aarch64.gpg
echo "deb [arch=any signed-by=/usr/share/keyrings/openrepo-rivendell-aarch64.gpg] https://repo.edgeradio.org.au/rivendell-aarch64/ stable main" > /etc/apt/sources.list.d/openrepo-rivendell-aarch64.list
apt update
```
```bash
# This repository is for AMD64 based systems. Use this if you're using an Intel or AMD based system.
apt update && apt install -y curl gnupg
curl https://repo.edgeradio.org.au/rivendell-arm/public.gpg | gpg --yes --dearmor -o /usr/share/keyrings/openrepo-rivendell-arm.gpg
echo "deb [arch=any signed-by=/usr/share/keyrings/openrepo-rivendell-arm.gpg] https://repo.edgeradio.org.au/rivendell-arm/ stable main" > /etc/apt/sources.list.d/openrepo-rivendell-arm.list
apt update
```

# Frequently Asked Questions
Coming soon...

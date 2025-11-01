#!/bin/bash

clear

# Check if script is running as the root user
if [ "$(id -u)" -eq 0 ]; then
clear
else
  # Script is not running as the root user
  echo "You need to run this script using sudo or as the root user."
  exit 1
fi

cat << "EOF"
,------. ,--.                           ,--.       ,--.,--.               ,---.      ,---.  ,------. ,--.   ,--.
|  .--. '`--',--.  ,--.,---. ,--,--,  ,-|  | ,---. |  ||  |    ,--.  ,--./    |     /  O  \ |  .--. '|   `.'   |
|  '--'.',--. \  `'  /| .-. :|      \' .-. || .-. :|  ||  |     \  `'  //  '  |    |  .-.  ||  '--'.'|  |'.'|  |
|  |\  \ |  |  \    / \   --.|  ||  |\ `-' |\   --.|  ||  |      \    / '--|  |    |  | |  ||  |\  \ |  |   |  |
`--' '--'`--'   `--'   `----'`--''--' `---'  `----'`--'`--'       `--'     `--'    `--' `--'`--' '--'`--'   `--'
EOF

echo ; echo "Rivendell v4 install script for Raspberry Pi OS and Debian" ; echo "For more information visit github.com/edgeradio993fm/rivendell" ; echo "More information and original project source code at rivendellaudio.org" ; echo

echo "Your System Details"
echo
echo "Operating System: $(cat /etc/os-release | grep 'PRETTY_NAME' | cut -d'"' -f2)"
echo "Kernel:" $(uname) $(uname -r)
echo "User:" ${SUDO_USER:-$USER}
echo "Hostname:" $(hostname)
echo

# Checking if rivendell package is installed
# if dpkg -l | grep -qw rivendell 3
if dpkg --status rivendell 2> /dev/null | grep -qw installed
  then
    echo "Rivendell package version" $(dpkg -s rivendell | grep -i '^Version' | cut -d' ' -f2) "is already installed on this system." ; echo "To upgrade your exsisting installation run the following command:"
    echo
    echo "curl -L https://raw.githubusercontent.com/edgeradio993fm/scripts/master/upgrade.sh | sudo bash"
    echo
  else

echo ; echo "We need to download and install some packages before Rivendell. This process could take a while..."

# Debian multimedia repository
echo ; echo "Adding Debian Multimedia repository to your system..." ; echo

if grep -R -q "deb http://deb-multimedia.org bookworm main non-free" "/etc/apt/sources.list"
  then
    echo "Reopsitory already added. Skipping..."
  else
    cd ~ && wget http://www.deb-multimedia.org/pool/main/d/deb-multimedia-keyring/deb-multimedia-keyring_2024.9.1_all.deb && sudo sudo dpkg -i deb-multimedia-keyring_2024.9.1_all.deb && rm -r deb-multimedia-keyring_2024.9.1_all.deb && sudo echo "deb http://deb-multimedia.org bullseye main non-free" |sudo tee -a /etc/apt/sources.list
fi

# Rivendell repository
echo ; echo "Adding Rivendell on ARM repository to your system..." ; echo

if test -f /etc/apt/sources.list.d/openrepo-rivendell-aarch64.list
  then
    echo "Reopsitory already added. Skipping..."
  else
    sudo apt install -y curl gnupg
    sudo curl https://repo.edgeradio.org.au/rivendell-aarch64/public.gpg | gpg --yes --dearmor -o /usr/share/keyrings/openrepo-rivendell-aarch64.gpg
    echo "deb [arch=any signed-by=/usr/share/keyrings/openrepo-rivendell-aarch64.gpg] https://repo.edgeradio.org.au/rivendell-aarch64/ stable main" > /etc/apt/sources.list.d/openrepo-rivendell-aarch64.list
fi

# Updating the apt database
echo ; echo "Making sure your package database is up to date..." ; echo

sudo apt update -y

# Install build tools
echo ; echo "Installing build tools..." ; echo

sudo apt install -y libtool m4 automake pkg-config make gcc g++ autofs rsync

# Install Rivendell dependencies
echo ; echo "Installing Rivendell dependencies..." ; echo

sudo apt install -y libexpat1-dev libexpat1 libid3-dev libcurl4-gnutls-dev libcoverart-dev libdiscid-dev libmusicbrainz5-dev libcdparanoia-dev libsndfile1-dev libpam0g-dev libvorbis-dev python3 python3-pycurl python3-pymysql python3-serial python3-requests libsamplerate0-dev qtbase5-dev libqt5sql5-mysql libsoundtouch-dev libsystemd-dev libjack-jackd2-dev libasound2-dev libflac-dev libflac++-dev libmp3lame-dev libmad0-dev libtwolame-dev docbook5-xml libxml2-utils docbook-xsl-ns xsltproc fop make g++ libltdl-dev autoconf automake libssl-dev libtag1-dev qttools5-dev-tools debhelper openssh-server autoconf-archive gnupg pbuilder ubuntu-dev-tools apt-file

# Set path
export PATH=/sbin:$PATH

# Install Apache2 web server
echo ; echo "Installing and configuring Apache2..." ; echo

if dpkg -l | grep -qw apache2
  then
    echo "Package apache2 is already installed. Skipping..." ; echo
  else
	sudo apt install -y apache2
fi

# Enable Apache2 mods
sudo a2enmod cgid
sudo systemctl restart apache2

# Install MariaDB server
echo ; echo "Installing and configuring MariaDB..." ; echo

if dpkg -l | grep -qw mariadb-server
  then
    echo "Package mariadb-server is already installed. Skipping..." ; echo
  else
	sudo apt install -y mariadb-server
	sudo systemctl start mariadb
	sudo systemctl enable mariadb
fi

# Create audio storage and add current user as owner
echo "Making audio storage..." ; echo

if [ -d /var/snd ]
  then
    echo "Audio storage already exists. Skipping..."
  else
    sudo adduser --system --group --home=/var/snd rivendell ; sudo adduser $SUDO_USER rivendell ; sudo chmod g+w /var/snd
fi

# Install Rivendell
echo ; echo "Downloading Rivendell..." ; echo

sudo apt install rivendell -y

# Refresh linked libraries
sudo ldconfig

# Download the default Rivendell configuration file
echo ; echo "Downloading default configuration..." ; echo

if [ -f /etc/rd.conf ]
  then
    echo "Configuration already exists. Skipping..." ; echo
  else
    sudo wget -O /etc/rd.conf https://raw.githubusercontent.com/edgeradio993fm/rivendell/master/conf/rd.conf-sample
fi

# Enable the Rivendell Apache2 extentions
sudo ln -sf ../mods-available/cgid.conf /etc/apache2/mods-enabled/cgid.conf
sudo ln -sf ../mods-available/cgid.load /etc/apache2/mods-enabled/cgid.load
sudo systemctl restart apache2

# Create the database and populate tables
echo ; echo "Creating database and populating database tables..." ; echo

if [ -d /var/lib/mysql/Rivendell ]
  then
    echo "Database already exists. Skipping..."
  else
    sudo mysql -e "create database Rivendell;" ; sudo mysql -e "grant Select, Insert, Update, Delete, Create, Drop, References, Index, Alter, Create Temporary Tables, Lock Tables on Rivendell.* to rduser@'%' identified by 'hackme'"
    sudo rddbmgr --create --generate-audio
fi

# Start the Rivendell daemons and enable the service
sudo systemctl start rivendell
sudo systemctl enable rivendell

echo
# Ask the user if they want to reboot their computer
echo "Rivendell Install Complete. Would you like to reboot your computer? (y/n)"
read response

# Check the user's response
if [ "$response" == "n" ]; then
  # If the user says no, exit the script
  exit
fi

# If the user says yes, reboot the computer
reboot
fi

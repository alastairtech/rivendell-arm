#!/bin/bash

set -e

# Check if script is running as the root user
if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root."
  exit 1
fi

# Define color escape codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Debian multimedia repository
echo ; echo -e "${RED}Adding Debian Multimedia repository to your system...${NC}" ; echo

if grep -R -q "deb http://deb-multimedia.org bookworm main non-free" "/etc/apt/sources.list"
  then
    echo -e "${RED}Reopsitory already added. Skipping...${NC}"
  else
    cd ~ && wget http://www.deb-multimedia.org/pool/main/d/deb-multimedia-keyring/deb-multimedia-keyring_2016.8.1_all.deb && sudo dpkg -i deb-multimedia-keyring_2016.8.1_all.deb && rm -r deb-multimedia-keyring_2016.8.1_all.deb && echo "deb http://deb-multimedia.org bookworm main non-free" | tee -a /etc/apt/sources.list
fi

echo ; echo -e "${RED}Updating Packages${NC}" ; echo
apt-get update

echo ; echo -e "${RED}Upgrading Packages${NC}" ; echo
apt-get upgrade -y

echo ; echo -e "${RED}Installing any build packages required${NC}" ; echo
apt-get install -y rsync apache2 build-essential libexpat1-dev libexpat1 libid3-dev libcurl4-gnutls-dev libcoverart-dev libdiscid-dev libmusicbrainz5-dev libcdparanoia-dev libsndfile1-dev libpam0g-dev libvorbis-dev python3 python3-pycurl python3-pymysql python3-serial python3-requests libsamplerate0-dev qtbase5-dev libqt5sql5-mysql libqt5webkit5-dev libsoundtouch-dev libsystemd-dev libjack-jackd2-dev libasound2-dev libflac-dev libflac++-dev libmp3lame-dev libmad0-dev libtwolame-dev docbook5-xml libxml2-utils docbook-xsl-ns xsltproc fop make g++ libltdl-dev autoconf automake libssl-dev libtag1-dev qttools5-dev-tools debhelper openssh-server autoconf-archive gnupg pbuilder ubuntu-dev-tools apt-file libmagick++-dev jq

# Get the latest release name
release_name=$(curl -s "https://api.github.com/repos/ElvishArtisan/rivendell/tags" | jq -r '.[0].name')

echo "Latest release is $release_name"
echo "$release_name" > /mnt/release_name.txt

# Download the latest release
echo "Downloading release $release_name..."
curl -L "https://github.com/ElvishArtisan/rivendell/archive/$release_name.tar.gz" -o "/opt/$release_name.tar.gz"
echo "Release $release_name downloaded successfully."

echo ; echo -e "${RED}Extracting latest release${NC}" ; echo
mkdir -p "/opt/rivendell-${release_name}"
tar -xf "/opt/$release_name.tar.gz" -C "/opt/rivendell-${release_name}" --strip-components=1

cd "/opt/rivendell-${release_name}"

echo ; echo -e "${RED}Autogen Components${NC}" ; echo
./autogen.sh

echo ; echo -e "${RED}Exporting Docbook Components${NC}" ; echo
export DOCBOOK_STYLESHEETS=/usr/share/xml/docbook/stylesheet/docbook-xsl-ns

echo ; echo -e "${RED}Configuring Components${NC}" ; echo
./configure --prefix=/usr --libdir=/usr/lib --libexecdir=/var/www/rd-bin --sysconfdir=/etc/apache2/conf-enabled --enable-rdxport-debug MUSICBRAINZ_LIBS="-ldiscid -lmusicbrainz5cc -lcoverartcc"

echo ; echo -e "${RED}BUILDING RIVENDELL ${release_name}${NC}" ; echo
make -j$(nproc)

echo ; echo -e "${RED}BUILDING RIVENDELL ${release_name} PACKAGES${NC}" ; echo
debuild -us -uc -nc -b


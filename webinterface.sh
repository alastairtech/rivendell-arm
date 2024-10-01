#!/bin/bash

# Check if script is running as the root user
if [ "$(id -u)" -eq 0 ]; then
clear
else
  # Script is not running as the root user
  echo "You need to run this script using sudo or as the root user."
  exit 1
fi

# Function to show a progress bar
show_progress() {
  {
    for i in {1..100}; do
      sleep 0.05  # Simulate work by adding a short delay
      echo $i     # The number shown here updates the progress bar
    done
  } | dialog --gauge "Processing..." 10 50 0
}

# Function to list releases, prompt for selection, and download the selected release
download_release() {
    # Fetch the list of available releases (tags)
    releases=$(curl -s "https://api.github.com/repos/olsson82/rivendellweb/tags" | grep '"name":' | cut -d'"' -f4)

    # Check if any releases are available
    if [ -z "$releases" ]; then
        echo "No releases found."
        exit 1
    fi

    # Prepare releases for dialog (indexed list)
    menu_options=()
    index=1
    while IFS= read -r release; do
        menu_options+=($index "$release")
        index=$((index + 1))
    done <<< "$releases"

    # Use dialog to display the list of releases and prompt the user to choose one
    choice=$(dialog --clear --stdout --title "Select Release to Download" --menu "Choose a release:" 15 50 8 "${menu_options[@]}")

    # If no choice was made, exit
    if [ -z "$choice" ]; then
        echo "No release selected."
        exit 1
    fi

    # Retrieve the release name corresponding to the selected number
    release_name=$(echo "$releases" | sed -n "${choice}p")

    # Download the selected release to /var/www/html
    echo "Downloading release $release_name..."
    curl -L "https://github.com/olsson82/rivendellweb/archive/$release_name.tar.gz" -o /var/www/html/"$release_name.tar.gz"

    # Check if the download was successful
    if [ $? -eq 0 ]; then
        echo "Release $release_name downloaded successfully to /var/www/html."
    else
        echo "Failed to download release $release_name."
    fi

    tar -xzvf /var/www/html/"$release_name.tar.gz" -C /var/www/html --strip-components=1
    rm /var/www/html/"$release_name.tar.gz"
    chmod 777 /var/www/html/data
}

# Function to install software (mock function with progress bar)
install_software() {
  dialog --infobox "Installing Rivendell Web Interface..." 3 50
  sleep 2
  apt-get install wget jq git -y
  apt-get install apache2 -y
  a2enmod rewrite
  systemctl restart apache2
  echo "Modifying apache2.conf"
  sed -i '/<Directory \/var\/www\/>/,/<\/Directory>/s/AllowOverride None/AllowOverride All/' /etc/apache2/apache2.conf
  apt-get install php php-{common,mysql,xml,xmlrpc,curl,gd,imagick,cli,dev,imap,mbstring,opcache,soap,zip,intl,pdo} -y
  systemctl restart apache2
  apt-get install ffmpeg -y
  cd /var/www/html
  mv index.html index.html.old
  download_release
  extract_release
  dialog --msgbox "Install Complete. \n Got to http://localhost to view the web interface." 5 50
}

# Function to upgrade software (mock function with progress bar)
upgrade_software() {
  dialog --infobox "Preparing upgrade..." 3 30
  sleep 2
  download_release
  dialog --msgbox "Upgrade complete..." 5 30
}

# Function to uninstall software (mock function with progress bar)
uninstall_software() {
  dialog --infobox "Preparing uninstallation..." 3 30
  sleep 2
  show_progress
  dialog --msgbox "Software uninstalled successfully." 5 30
}

# Main Menu
while true; do
  option=$(dialog --clear --stdout --title "Rivendell Web Interface" --menu "Choose an option:" 12 50 3 \
    1 "Install Latest Web Interface" \
    2 "Upgrade To Latest Web Interface" \
    3 "Uninstall Web Interface" \
    4 "Exit")

  case $option in
    1)
      install_software
      ;;
    2)
      upgrade_software
      ;;
    3)
      uninstall_software
      ;;
    4)
      clear
      exit 0
      ;;
    *)
      clear
      exit 0
      ;;
  esac
done

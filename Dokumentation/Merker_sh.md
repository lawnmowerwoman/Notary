# Legacy-Hinweis

Diese Datei beschreibt keinen aktuellen Ist-Zustand von Notary.

Sie ist ein historisches Arbeitsdokument aus der Shell-/CIS-Vorgeschichte des Projekts und dient heute nur noch als Referenz für ältere Ideen, Checks und Formulierungen. Die aktive Implementierung von Notary ist inzwischen ein Swift-Projekt unter `Sources/NotaryRunner`.

Wichtig:

- Diese Datei ist keine Betriebsdokumentation.
- Sie beschreibt nicht die aktuelle Architektur.
- Sie ist nicht maßgeblich für den heutigen Runner, Transporter oder die Persistenzlogik.

Für den aktuellen Stand maßgeblich sind stattdessen:

- `Readme.md`
- `ROADMAP.md`
- `Sources/NotaryRunner`
- `Tools/deploy.sh`

---

Nachfolgend bleibt der historische Inhalt als Legacy-Referenz erhalten.

#  <#Title#>

Edit the variable in CIS_macOS.sh at your convenience :

# Variables
## Organisation info
org="ICTrust"
org_contact="hello@ictrust.ch"
ntp="pool.ntp.org"
timezone="Europe/Zurich"

login_screen_msg="If you found this laptop please let $org know at $org_contact. A rewards will be provided.\nSi vous trouvez cet ordinateur, veuillez s'il vous plait contacter $org à $org_contact. Une récomponse sera attribuée."
login_window_banner="* * * * * * * * * * W A R N I N G * * * * * * * * * *
UNAUTHORIZED ACCESS TO THIS DEVICE IS PROHIBITED
You must have explicit, authorized permission to access or configure this device. Unauthorized attempts and actions to access or use this system may result in civil and/or criminal penalties. All activities performed on this device are logged and monitored

L'ACCÈS NON AUTORISÉ À CET APPAREIL EST INTERDIT
Vous devez avoir la permission explicite et autorisée d'accéder à cet appareil ou de le configurer. Les tentatives et actions non autorisées d'accès ou d'utilisation de ce système peuvent entraîner des sanctions civiles et/ou pénales. Toutes les activités effectuées sur cet appareil sont enregistrées et contrôlées.
* * * * * * * * * * * * * * * * * * * * * * * *"



####################################################
# Description: CIS v8 automation for macOS
# Version: 0.1
# Author: A-YATTA (Amine T.)
# Organisation: ICTrust
# Tests: Tested on macOS Monterey 12 (M1 and Intel).
# Date: 27.09.2022
# LICENSE: MIT
####################################################

# Enable debugging by uncommenting the line bellow
#set -x



# Variables
## Organisation info
org="ICTrust"
org_contact="hello@ictrust.ch"
ntp="pool.ntp.org"
timezone="Europe/Zurich"

## Messages
login_screen_msg="If you found this laptop please let $org know at $org_contact. A rewards will be provided.\nSi vous trouvez cet ordinateur, veuillez s'il vous plait contacter $org à $org_contact. Une récomponse sera attribuée."
login_window_banner="* * * * * * * * * * W A R N I N G * * * * * * * * * *
UNAUTHORIZED ACCESS TO THIS DEVICE IS PROHIBITED
You must have explicit, authorized permission to access or configure this device. Unauthorized attempts and actions to access or use this system may result in civil and/or criminal penalties. All activities performed on this device are logged and monitored

L'ACCÈS NON AUTORISÉ À CET APPAREIL EST INTERDIT
Vous devez avoir la permission explicite et autorisée d'accéder à cet appareil ou de le configurer. Les tentatives et actions non autorisées d'accès ou d'utilisation de ce système peuvent entraîner des sanctions civiles et/ou pénales. Toutes les activités effectuées sur cet appareil sont enregistrées et contrôlées.
* * * * * * * * * * * * * * * * * * * * * * * *"

# Printing
RED='\033[0;31m'
GREEN='\033[0;32m'
ORANGE='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_success() {
    printf "${GREEN}$1 ${NC}\n"
}

print_info() {
    printf "${BLUE}[INFO] $1 ${NC}\n"
}

print_fail() {
    printf "${RED}[ERROR] $1 ${NC}\n"
}


print_warn() {
    printf "${RED}[WARNING] $1 ${NC}\n"
}

# List of current users
users_list=$(dscacheutil -q user | grep -A 3 -B 2 -e uid:\ 5'[0-9][0-9]' | grep name | cut -d' ' -f2)

################################################
# 1.1 Verify all Apple-provided software is current
################################################
print_info "Check for system updates"
updates=$(softwareupdate -l 2>&1 | grep "No new software available.")

if [[ $updates =~ "No new software"* ]]; then
    print_success "No software updates available\n"
else
    print_fail "System updates are available\n"
    read -p "Do you wish to install the updates?" yn
    case $yn in
        [Yy]* ) softwareupdate -i -a; break;;
        [Nn]* ) continue;;
        * ) echo "Please answer yes or no.";;
    esac
fi

################################################
# 1.2 Enable Auto Update
################################################
print_info "Enable automatic updates"
sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticDownload -int true

################################################
# 1.3 Enable Download new updates when available
################################################
sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticDownload -bool true


################################################
# 1.4 Enable app update installs
################################################
print_info "Enable Download new updates when available"
sudo defaults write /Library/Preferences/com.apple.commerce AutoUpdate -bool true


################################################
# 1.4 Enable system data files and security updates install
################################################
print_info "Enable system data files and security updates install"
sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate ConfigDataInstall -bool true
sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate ConfigDataInstall -bool true


################################################
# 1.4 Enable macOS update installs
################################################
print_info "Enable system data files and security updates install"
sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticallyInstallMacOSUpdates -bool true

################################################
# 2 System Preferences
################################################

################################################
# 2.1 Bluetooth
################################################
# Skipped

################################################
# 2.2.1 Enable "Set time and date automatically"
################################################
sudo systemsetup -setnetworktimeserver $ntp
print_info "Enable automatic date and time: $ntp"
sudo systemsetup -settimezone $timezone
sudo systemsetup -setusingnetworktime on

################################################
# 2.2.2 Ensure time set is within appropriate limits
################################################
# TO-DO

################################################
# 2.3 Desktop & Screen Saver
################################################
################################################
# 2.3.1 Set an inactivity interval of 20 minutes or less for the screen saver
################################################
print_info "Set inactivity interval to 10 minutes"
sudo defaults -currentHost write com.apple.screensaver idleTime -int 600 2> /dev/null

################################################
# 2.3.2 Secure screen saver corners
################################################
# By default (on macos 12.x) the value does not exist which is compliant

################################################
# 2.4.1 Disable Remote Apple Events
################################################
print_info "Disable Remote Apple Events"
sudo systemsetup -setremoteappleevents off 2> /dev/null

################################################
# 2.4.2 Disable Internet Sharing
################################################
print_info "Disable Internet Sharing"
sudo defaults write /Library/Preferences/SystemConfiguration/com.apple.nat NAT -dict Enabled -int 0 2> /dev/null


################################################
# 2.4.3 Disable Screen Sharing
################################################
print_info "Disable screen sharing"
sudo launchctl disable system/com.apple.screensharing 2> /dev/null

################################################
# 2.4.4 Disable Printer Sharing
################################################
print_info "Disable printer sharing"
sudo cupsctl --no-share-printers 2> /dev/null

################################################
# 2.4.5 Disable Remote Login
################################################
print_info "Disable remote login"
sudo systemsetup -setremotelogin off 2> /dev/null

################################################
# 2.4.6 Disable DVD or CD Sharing
################################################
print_info "Disable DVD or CD Sharing"
sudo launchctl disable system/com.apple.ODSAgent 2> /dev/null

################################################
# 2.4.7 Disable Bluetooth Sharing
################################################
print_info "Disable Bluetooth Sharing for all users"
for user in $users_list; do
    sudo -u "$user" defaults -currentHost write com.apple.Bluetooth PrefKeyServicesEnabled -bool false 2> /dev/null
done

################################################
# 2.4.8 Disable File Sharing
################################################
print_info "Disable file sharing"
sudo launchctl unload -w /System/Library/LaunchDaemons/com.apple.smbd.plist 2> /dev/null

################################################
# 2.4.9 Disable Remote Management
################################################
print_info "Disable remote management"
sudo /System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources /kickstart -deactivate -stop 2> /dev/null

################################################
# 2.4.10 Disable Content Caching
################################################
print_info "Disable content caching"
sudo AssetCacheManagerUtil deactivate 2> /dev/null

################################################
# 2.4.11 Disable Media Sharing
################################################
print_info "Disable Media Sharing"
for user in $users_list; do
    sudo -u "$user" defaults write com.apple.amp.mediasharingd home-sharing-enabled -int 0 2> /dev/null
done

################################################
# 2.4.12 Ensure AirDrop Is Disabled
################################################
print_info "Disable AirDrop"
for user in $users_list; do
    sudo -u "$user" defaults write com.apple.NetworkBrowser DisableAirDrop -bool true 2> /dev/null
done

################################################
# 2.5 Security & Privacy
################################################
################################################
# 2.5.1 Encryption
################################################
################################################
# 2.5.1.1 Enable FileVault
################################################
print_info "Check if FileVault is enabled"
filevault_status=$(sudo fdesetup status)
if [[ $filevault_status == "FileVault is On." ]]; then
    print_success "FileVault is enabled"

#!/bin/bash
# Script to generate a Debian openVZ template.
# v0.0.0 (DO NOT USE YET)
# Currently supports custom locale, mirrors, timezone and Debian release.
# Have a base Debian openvz template and run this script in the hypervisor.

# TODO
# ssh key handling
# remove hostname and resolv.conf
# exit CT and tar the container to a template
# cleanup (destroy temp CT)
# CLI arguments

mirror="http://ftp3.nrc.ca/debian"
debian_version="wheezy"
timezone="America/Montreal"
temp_vm_id="1337"
lang="fr_CA"
encoding="UTF-8"

# Create container with base template and start it
vzctl create $temp_vm_id # TODO add base settings and template
vzctl start $temp_vm_id

# Enter the newly created
vzctl enter $temp_vm_id


#
# generate new locales
#

# Clear /etc/locale
> /etc/locale

# Generate new /etc/locale file
cat > /etc/locale <<EOF
# This file lists locales that you wish to have built. You can find a list
# of valid supported locales at /usr/share/i18n/SUPPORTED, and you can add
# user defined locales to /usr/local/share/i18n/SUPPORTED. If you change
# this file, you need to rerun locale-gen.
${lang}.${encoding} ${encoding}
EOF

# Remove old LANG and LC_CTYPE from /etc/environnement
sed '/^LANG/d' /etc/environnement
sed '/^LC_CTYPE/d' /etc/environnement

# Add new LANG and LC_CTYPE to /etc/environnement
echo "LANG=${lang}" >> /etc/environnement
echo "LC_CTYPE=${lang}.${encoding}" >> /etc/environnement

# Clear default locale
> /etc/default/locale

# Set current default locale
cat > /etc/default/locale <<EOF
LANG=${lang}.${encoding}
EOF

# Generate new locale
locale-gen


#
# Generate new sources
#

# Clear old sources.list
> /etc/sources.list

# Generate new /etc/sources.list file
cat > /etc/sources.list <<EOF
deb ${mirror} ${debian_version} main contrib
deb ${mirror} ${debian_version}-updates main contrib
deb http://security.debian.org ${debian_version}/updates main contrib
EOF

# Update vm with new sources.list
apt-get update
apt-get upgrade --assume-yes
apt-get dist-upgrade --assume-yes

# Install some basic utilities
apt-get install --assume-yes less htop 
# Clean apt-get
apt-get autoremove -y
apt-get clean -y

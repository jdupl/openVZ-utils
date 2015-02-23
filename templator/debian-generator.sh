#!/bin/bash
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
# Author: Justin Duplessis
#
# Script to generate a Debian openVZ template.
# v2.0.0-dev
#
# Currently supports custom locale, mirrors, timezone and Debian release.
#
# Have a base Debian openVZ template or container and run this script as root in
# the hypervisor.
# A full system update will be ran.

DEFAULT_DNS="8.8.8.8"
DEFAULT_IP="192.168.2.170"
DEFAULT_LANG="en_CA"
DEFAULT_ENCODING="UTF-8"
DEFAULT_TMPID="1337"
DEFAULT_MIRROR="http://ftp.debian.org/debian"
DEFAULT_VERSION="wheezy"
DEFAULT_VZ_ROOT="/var/lib/vz/"

help() {
cat <<EOF
usage: $0 --ctid <id> | --template <template> [options]

Required:
  --ctid        Use an existing container and template it.
  OR
  --template    Use an existing template and retemplate it (apply all updates).

Optional parameters:
  --root        VZ root. Default is '${DEFAULT_VZ_ROOT}'.
  --name        Template name to save.
  --version     Debian version to upgrade to. Default is '${DEFAULT_VERSION}'.
  --mirror      Mirror to use while updating. Default is '${DEFAULT_MIRROR}'.
  --lang        Language of the locale to generate. Default is '${DEFAULT_LANG}'.
  --encoding    Language of the locale to generate. Default is '${DEFAULT_ENCODING}'.
  --ip          Temporary IP of the container. Only specify if using --template.
  --dns         Temporary DNS server to use. Only specify if using --template.
                Default is '${DEFAULT_DNS}'.
  --tmpid       Temporary container id to use. Only specify if using --template.
                Default is '${DEFAULT_TMPID}'.
EOF
exit 1
}

ct_exists() {
    local id=$1
    [ $(vzlist -1a | tr -d ' ' | grep "^${id}$") ]
}

ct_running() {
    local id=$1
    [ $(vzlist -1 | tr -d ' ' | grep "^${id}$") ]
}

give_network() {
    # Give basic network access to CT
    vzctl set $temp_vm_id --ipdel all --save
    vzctl set $temp_vm_id --ipadd $temp_ip --save
    vzctl set $temp_vm_id --nameserver $temp_dns --save

    vzctl start $temp_vm_id
    sleep 1s
}


clone_ctid() {
    echo "Backing up base container ${base_ctid} to clone it."
    # vzdump won't accept a file as it creates a log
    backup_dir=$(mktemp -d ${vz_root}/dump/XXXXXXX)
    vzdump ${base_ctid} -dumpdir ${backup_dir} -compress 0
    backup_file=$(ls ${backup_dir}/*.tar)

    # restore the backup to clone the original container provided
    vzrestore ${backup_file} ${temp_vm_id}
    give_network
}


restore_template() {
    # Check if "basic config" exists in current installation
    if [[ ! -f /etc/pve/openvz/ve-basic.conf-sample ]]; then
        cat > /etc/pve/openvz/ve-basic.conf-sample <<EOF
ONBOOT="no"

PHYSPAGES="0:512M"
SWAPPAGES="0:512M"
KMEMSIZE="232M:256M"
DCACHESIZE="116M:128M"
LOCKEDPAGES="256M"
PRIVVMPAGES="unlimited"
SHMPAGES="unlimited"
NUMPROC="unlimited"
VMGUARPAGES="0:unlimited"
OOMGUARPAGES="0:unlimited"
NUMTCPSOCK="unlimited"
NUMFLOCK="unlimited"
NUMPTY="unlimited"
NUMSIGINFO="unlimited"
TCPSNDBUF="unlimited"
TCPRCVBUF="unlimited"
OTHERSOCKBUF="unlimited"
DGRAMRCVBUF="unlimited"
NUMOTHERSOCK="unlimited"
NUMFILE="unlimited"
NUMIPTENT="unlimited"

# Disk quota parameters (in form of softlimit:hardlimit)
DISKSPACE="10G:11G"
DISKINODES="2000000:2200000"
QUOTATIME="0"
QUOTAUGIDLIMIT="0"

CPUUNITS="1000"
EOF
    fi
    if $(ct_exists $temp_vm_id); then
        echo -e "\e[31mError: Container with id ${temp_vm_id} already exists. "\
        "Cannot start template. Please specify different container id.\e[39m"
        exit 2
    fi

    local template_path=${vz_root}/template/cache/${base_template}
    if [[ ! -f $template_path ]]; then
        echo -e "\e[31mError: Template ${base_template} not found. "\
        "Make sure the template exists in ${vz_root}/template/cache/.\e[39m"
        exit 2
    fi

    # Create container with base template
    vzctl create $temp_vm_id --ostemplate ${template_path} --config basic
    give_network
}

temp_ip=$DEFAULT_IP
mirror=$DEFAULT_MIRROR
debian_version=$DEFAULT_VERSION
temp_vm_id=$DEFAULT_TMPID
lang=$DEFAULT_LANG
encoding=$DEFAULT_ENCODING
vz_root=$DEFAULT_VZ_ROOT
temp_dns=$DEFAULT_DNS
name=''

while [[ $# > 0 ]]
do
  key="$1"
  shift
  case $key in
    --ctid)             base_ctid="$1";         shift    ;;
    --name)             name="$1";              shift    ;;
    --template)         base_template="$1";     shift    ;;
    --mirror)           mirror="$1";            shift    ;;
    --root)             vz_root="$1";           shift    ;;
    --version)          debian_version="$1";    shift    ;;
    --ip)               temp_ip="$1";           shift    ;;
    --dns)              temp_dns="$1";          shift    ;;
    --tmpid)            temp_vm_id="$1";        shift    ;;
    --lang)             lang="$1";              shift    ;;
    --encoding)         encoding="$1";          shift    ;;
    *)
        echo -e "\e[31mError: unknown parameter: $key\e[39m"
        echo
        help
        return 1
        ;;
  esac
done

# Use generic name if not provided by user
if [ -d $name ]; then
    name="debian-${debian_version}"
fi

# Check if ctid or template was provided
#echo $base_template
if [[ $base_template ]] && [[ $base_ctid ]]; then
    echo -e "\e[31mError: Please use --template OR --ctid.\e[39m"
    help
elif [[ $base_template ]]; then
    echo "using template"
    #base_ctid=$temp_vm_id
    restore_template
elif [[ $base_ctid ]]; then
    echo "using ctid"
    if ! $(ct_exists $base_ctid); then
        echo -e "\e[31mError: Container with id ${base_ctid} does not exists. "\
        "Please enter an existing container id. \e[39m"
        exit 2
    fi
    clone_ctid
else
    help
fi

# Generate new locale.gen file
cat > ${vz_root}/private/${temp_vm_id}/etc/locale.gen <<EOF
# This file lists locales that you wish to have built. You can find a list
# of valid supported locales at /usr/share/i18n/SUPPORTED, and you can add
# user defined locales to /usr/local/share/i18n/SUPPORTED. If you change
# this file, you need to rerun locale-gen.
${lang}.${encoding} ${encoding}
EOF

# Set default locale
cat > ${vz_root}/private/${temp_vm_id}/etc/default/locale <<EOF
LANG="${lang}.${encoding}"
EOF

# Generate new /etc/apt/sources.list file
cat > ${vz_root}/private/${temp_vm_id}/etc/apt/sources.list <<EOF
deb ${mirror} ${debian_version} main contrib
deb ${mirror} ${debian_version}-updates main contrib
deb http://security.debian.org ${debian_version}/updates main contrib
EOF

# Generate new locale
vzctl exec $temp_vm_id locale-gen

vzctl stop $temp_vm_id
sleep 1s
vzctl start $temp_vm_id
sleep 5s

# Update vm with new sources.list
vzctl exec $temp_vm_id apt-get update
vzctl exec $temp_vm_id DEBIAN_FRONTEND=noninteractive apt-get upgrade -o Dpkg::Options::=--force-confnew --yes --force-yes
vzctl exec $temp_vm_id DEBIAN_FRONTEND=noninteractive apt-get dist-upgrade -o Dpkg::Options::=--force-confnew --yes --force-yes

# Install some basic utilities
vzctl exec $temp_vm_id apt-get install -y less htop

# Clean apt-get
vzctl exec $temp_vm_id apt-get autoremove -y
vzctl exec $temp_vm_id apt-get clean -y

# Script to regenerate new keys at first boot of the template
cat  > ${vz_root}/private/${temp_vm_id}/etc/init.d/ssh_gen_host_keys << EOF
ssh-keygen -f /etc/ssh/ssh_host_rsa_key -t rsa -N ''
ssh-keygen -f /etc/ssh/ssh_host_dsa_key -t dsa -N ''
rm -f \$0
EOF

# Make script executable
vzctl exec $temp_vm_id chmod a+x /etc/init.d/ssh_gen_host_keys

# Enable init script
vzctl exec $temp_vm_id insserv /etc/init.d/ssh_gen_host_keys

# Change timezone
vzctl exec $temp_vm_id ln -sf /usr/share/zoneinfo/$timezone /etc/timezone

# Delete CT's hostname file
rm -f ${vz_root}/private/${temp_vm_id}/etc/hostname

# Reset CT's resolv.conf
> ${vz_root}/private/${temp_vm_id}/etc/resolv.conf

# Delete CT ssh keys
rm -f ${vz_root}/private/${temp_vm_id}/etc/ssh/ssh_host_*

# Delete history
vzctl exec $temp_vm_id history -c

# Stop the CT
vzctl stop $temp_vm_id

# Compress the CT to a template
echo "compressing template..."
cd ${vz_root}/private/${temp_vm_id}/

path=${vz_root}/template/cache/$name-${debian_version}-i386-${lang}.${encoding}-$(date +%F).tar.gz
tar --numeric-owner -zcf $path .
echo "template saved to ${path}"

# Cleanup (delete temp container)
vzctl destroy $temp_vm_id

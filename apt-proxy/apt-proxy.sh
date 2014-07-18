#!/bin/bash
# Script to remove or add apt proxies to OpenVZ containers.
# Author: Justin Duplessis 2014
# Licensed under the GPLv3

# TODO: allow user to change apt config file with args

apt_config_path=" /etc/apt/apt.conf.d/30autoaptcacher"

usage() {
    cat << EOF
usage: $0 -a <http://proxy/path:port>| -d [--help | -h]
EOF
}

help() {
    usage;
    cat << EOF
Script to remove or add apt proxies to openvz containers.
Options :
  -a   Add this apt proxy as the only apt proxy to every container.
  -d   Delete older apt proxy from all containers.
EOF
}

if [ $# -eq 0 ]; then
	usage;
	exit 1;
fi

while getopts "h help a: d" opt; do
    case "$opt" in
  	h | help)
  		help; exit 0;
        ;;
    a)
        proxy_path=$OPTARG;
        ;;
    d)
        echo "Deleting apt proxies..."
        ;;
    :)
        exit 1;
        ;;
    \?)
        exit 1;
        ;;
    esac
done

if [[ -n $proxy_path ]]; then
    proxy_config=$(cat <<EOF
Acquire {
    Retries "0";
    HTTP {
        Proxy "${proxy_path}";
    };
};
EOF
    )

    for ct in $(vzlist -H -o ctid); do
        echo "Configuring CT ${ct} to use proxy ${proxy_path}"
        vzctl exec $ct "echo \"${proxy_config}\" > ${apt_config_path}"
    done;
else
    for ct in $(vzlist -H -o ctid); do
        echo "Deleting CT ${ct}'s proxy at ${apt_config_path}"
        vzctl exec $ct "rm ${apt_config_path}"
    done;
fi

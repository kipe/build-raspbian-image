#!/bin/bash

export LC_ALL="C"

machine=`uname -m`
if [ "${machine}" != "armv7l" ]; then
  echo "This script will be executed at mounted raspbian enviroment (armv7l). Current environment is ${machine}."
  exit 1
fi

deb_release="wheezy"

# Add repository.
echo "deb http://packages.struktur.de/spreed-webrtc/raspbian ${deb_release} main
" > /etc/apt/sources.list.d/spreed-webrtc.list
wget http://packages.struktur.de/spreed-webrtc/raspbian/struktur-debian-package-sign-01.pub -O - | apt-key add -

# Install software.
apt-get update
apt-get install spreed-webrtc ssl-cert

# Create SSL certificate configuration.
mkdir -p /etc/spreed
echo "
#
# SSLeay configuration file for Spreed.
#

RANDFILE                = /dev/random

[ req ]
default_bits            = 2048
default_md              = sha256
default_keyfile         = privkey.pem
distinguished_name      = req_distinguished_name
prompt                  = no
policy                  = policy_anything

[ req_distinguished_name ]
commonName              = raspberrypi
" > /etc/spreed/ssleay.cnf

# Add user to ssl-cert group.
gpasswd -a spreed-webrtc ssl-cert

# Add first boot actions.
echo "
# Generate SSL key and self signed certificate.
openssl req -new -x509 -nodes -keyout /etc/ssl/private/spreed-webrtc.key -out /etc/ssl/certs/spreed-webrtc.pem -days 3650 -config /etc/spreed/ssleay.cnf
chmod 644 /etc/ssl/certs/spreed-webrtc.pem
chmod 640 /etc/ssl/private/spreed-webrtc.key
chown root:ssl-cert /etc/ssl/private/spreed-webrtc.key

# Generate random keys for Spreed WebRTC.
sed -i \"s|sessionSecret = .*|sessionSecret = \$(xxd -ps -l 32 -c 32 /dev/random)|\" /etc/spreed/webrtc.conf
sed -i \"s|encryptionSecret = .*|encryptionSecret = \$(xxd -ps -l 16 -c 16 /dev/random)|\" /etc/spreed/webrtc.conf
sed -i \"s|;serverToken = .*|serverToken = \$(xxd -ps -l 16 -c 16 /dev/random)|\" /etc/spreed/webrtc.conf

# Restart service.
invoke-rc.d spreed-webrtc restart
" >> /root/firstboot.sh

# Enable SSL listener.
sed -i 's|;listen = 127.0.0.1:8443|listen = 0.0.0.0:8443|' /etc/spreed/webrtc.conf
sed -i 's|;certificate = .*|certificate = /etc/ssl/certs/spreed-webrtc.pem|' /etc/spreed/webrtc.conf
sed -i 's|;key = .*|key = /etc/ssl/private/spreed-webrtc.key|' /etc/spreed/webrtc.conf
sed -i 's|;stunURIs = .*|stunURIs = stun:stun.spreed.me:443|' /etc/spreed/webrtc.conf

echo "done."
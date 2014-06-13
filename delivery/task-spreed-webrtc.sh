#!/bin/bash

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

# Add user to ssl-cert group.
gpasswd -a spreed-webrtc ssl-cert

# Add first boot actions.
echo "

# Generate new ssl certificate.
make-ssl-cert generate-default-snakeoil --force-overwrite

# Use random sessionSecret.
sed -i 's|sessionSecret = .*|sessionSecret = `openssl rand -hex 64`|' /etc/spreed/webrtc.conf

# Restart service.
invoke-rc.d spreed-webrtc restart

" >> /root/firstboot.sh

# Enable SSL listener.
sed -i 's|;listen = 127.0.0.1:8443|listen = 0.0.0.0:8443|' /etc/spreed/webrtc.conf
sed -i 's|;certificate = .*|certificate = /etc/ssl/certs/ssl-cert-snakeoil.pem|' /etc/spreed/webrtc.conf
sed -i 's|;key = .*|key = /etc/ssl/private/ssl-cert-snakeoil.key|' /etc/spreed/webrtc.conf
sed -i 's|;stunURIs = .*|stunURIs = stun:stun.spreed.me:443|' /etc/spreed/webrtc.conf


echo "done."
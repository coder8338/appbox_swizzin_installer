#!/bin/bash

export DEBIAN_FRONTEND=noninteractive

OLD_INSTALLS_EXIST=0

check_old_installs() {
    echo "Checking for old installs..."
    # Create array of old installs
    OLD_INSTALLS=(radarr sonarr sickchill jackett couchpotato nzbget sabnzbdplus ombi lidarr organizr nzbhydra2 bazarr flexget filebot synclounge medusa lazylibrarian pyload ngpost komga ombiv4 readarr overseerr requestrr updatetool flood tautulli unpackerr mylar flaresolverr)

    # Loop through array
    for i in "${OLD_INSTALLS[@]}"; do
        # Check if install exists
        if [ -d "/etc/services.d/$i" ]; then
            OLD_INSTALLS_EXIST=1
        fi
    done
}

run_as_root() {
    if ! whoami | grep -q 'root'; then
        echo "This script must be run with sudo, please run:"
        echo "sudo $0"
        exit 1
    fi
}

run_as_root

if [ ! -f /etc/nginx/sites-enabled/appbox.conf ]; then
    rm /etc/nginx/sites-enabled/default
    wget -q https://raw.githubusercontent.com/coder8338/appbox_swizzin_installer/Ubuntu_20.04/nginx_orig.conf -O /etc/nginx/sites-enabled/appbox.conf
fi

echo 'Please enter your Ubuntu password (for the username appbox):'
read -r USER_PASSWORD

userline=$(sudo awk -v u=appbox -F: 'u==$1 {print $2}' /etc/shadow)
IFS='$'
a=($userline)

if [[ ! "$(printf "${USER_PASSWORD}" | openssl passwd -"${a[1]}" -salt "${a[2]}" -stdin)" = "${userline}" ]]; then
    echo "Password does not match"
    exit 1
fi

cd /tmp || exit 1

url_output() {
    echo -e "\n\n\n\n\n
Installation of Swizzin sucessful! Please point your browser to:
\e[4mhttps://${HOSTNAME}/\e[39m\e[0m

This will ask for your login details which are as follows:

\e[4mUsername: appbox\e[39m\e[0m
\e[4mPassword: ${USER_PASSWORD}\e[39m\e[0m

If you want to install/remove apps, please type the following into your terminal:
sudo box

Enjoy!

    \n\n"
}

create_service() {
    NAME=$1
    mkdir -p /etc/services.d/${NAME}/log
    echo "3" >/etc/services.d/${NAME}/notification-fd
    cat <<EOF >/etc/services.d/${NAME}/log/run
#!/bin/sh
exec logutil-service /var/log/appbox/${NAME}
EOF
    chmod +x /etc/services.d/${NAME}/log/run
    echo "${RUNNER}" >/etc/services.d/${NAME}/run
    chmod +x /etc/services.d/${NAME}/run
    cp -R /etc/services.d/${NAME} /var/run/s6/services
    kill -HUP 1
    until [ -d "/run/s6/services/${NAME}/supervise/" ]; do
        echo
        echo "Waiting for s6 to recognize service..."
        sleep 1
    done
    s6-svc -u /run/s6/services/${NAME}
}

cat <<EOF >/usr/lib/os-release
NAME="Ubuntu"
VERSION="20.04.1 LTS (Focal Fossa)"
ID=ubuntu
ID_LIKE=debian
PRETTY_NAME="Ubuntu 20.04.1 LTS"
VERSION_ID="20.04"
HOME_URL="https://www.ubuntu.com/"
SUPPORT_URL="https://help.ubuntu.com/"
BUG_REPORT_URL="https://bugs.launchpad.net/ubuntu/"
PRIVACY_POLICY_URL="https://www.ubuntu.com/legal/terms-and-policies/privacy-policy"
VERSION_CODENAME=focal
UBUNTU_CODENAME=focal
EOF

mkdir -p /run/php/

check_old_installs

if [ $OLD_INSTALLS_EXIST -eq 1 ]; then
    echo "Old installs detected, this will cause a conflict with the new Swizzin services."
    echo "Would you like to remove them (y/n)?"
    read -r REMOVE_OLD_INSTALLS
    if [ "$REMOVE_OLD_INSTALLS" = "y" ] || [ "$REMOVE_OLD_INSTALLS" = "Y" ] || [ "$REMOVE_OLD_INSTALLS" = "yes" ]; then
        echo "Removing old installs..."
        for i in "${OLD_INSTALLS[@]}"; do
            echo "Removing $i..."
            s6-svc -d /run/s6/services/"$i" || true
            if [ -d "/etc/services.d/$i" ]; then
                rm -rf /etc/services.d/"$i"
            fi
            if [ -d "/var/run/s6/services/$i" ]; then
                rm -rf /var/run/s6/services/"$i"
            fi
            if [ -d "/home/appbox/.config/${i^}" ]; then
                rm -rf /home/appbox/.config/"${i^}"
            fi
            if [ -d "/var/log/appbox/$i" ]; then
                rm -rf /var/log/appbox/"$i"
            fi
        done

        rm -rf /home/appbox/appbox_installer
    else
        echo "Please remove the old installs and try again, or use this script to remove them."
        exit 1
    fi
fi

sed -i 's/www-data/appbox/g' /etc/nginx/nginx.conf
echo -e "\nUpdating mono certs..."
cert-sync --quiet /etc/ssl/certs/ca-certificates.crt
echo -e "\nUpdating apt packages..."
echo >>/etc/apt/apt.conf.d/99verify-peer.conf "Acquire { https::Verify-Peer false }"

if [ -f /etc/systemd/system/dbus-fi.w1.wpa_supplicant1.service ] && [ ! -f /etc/systemd/system/panel.service ]; then
    rm -rf /lib/systemd/system/*
    rm -rf /etc/systemd/system/*
fi

echo "Upgrading system..."
apt-get -qq upgrade -y

wget -q https://raw.githubusercontent.com/gdraheim/docker-systemctl-replacement/master/files/docker/systemctl3.py -O /usr/local/bin/systemctl
chmod +x /usr/local/bin/systemctl

systemctl daemon-reload

RUNNER=$(
    cat <<EOF
#!/bin/execlineb -P
# Redirect stderr to stdout.
fdmove -c 2 1
/usr/local/bin/systemctl --init
EOF
)

create_service 'systemd'

echo -e "\nInstalling required packages..."
apt-get -qq install -y git

if [ -d /etc/swizzin ]; then
    rm -rf /etc/swizzin
fi

git clone https://github.com/swizzin/swizzin.git /etc/swizzin &>/dev/null
git fetch origin overseer &>/dev/null
git merge --no-edit origin/overseer &>/dev/null
sed -i '/Continue setting up user/d' /etc/swizzin/scripts/box

/etc/swizzin/setup.sh --unattend nginx panel radarr sonarr --user appbox --pass "$USER_PASSWORD"

cat >/etc/nginx/sites-enabled/default <<NGC
map \$http_host \$port {
        default 80;
        "~^[^:]+:(?<p>d+)$" \$p;
}

server {
	listen 80 default_server;
	listen [::]:80 default_server;
    listen 443 ssl default_server;
    listen [::]:443 ssl default_server;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_stapling on;
    ssl_stapling_verify on;
    resolver 1.1.1.1 1.0.0.1 [2606:4700:4700::1111] [2606:4700:4700::1001] valid=300s; # Cloudflare
    resolver_timeout 5s;
    ssl_session_cache shared:MozSSL:10m;  # about 40000 sessions
    ssl_buffer_size 4k;
    ssl_session_timeout 1d;
    ssl_session_tickets off;
    ssl_certificate /etc/ssl/cert.pem;
    ssl_certificate_key /etc/ssl/key.pem;
    ssl_trusted_certificate /etc/ssl/cert.pem;
    proxy_hide_header Strict-Transport-Security;
    add_header Strict-Transport-Security "max-age=63072000" always;

    server_name _;
    location /.well-known {
        alias /srv/.well-known;
        allow all;
        default_type "text/plain";
        autoindex    on;
    }
    server_tokens off;
    root /srv/;
    include /etc/nginx/apps/*.conf;
    location ~ /\.ht {
        deny all;
    }
}
NGC

sed -i 's/FORMS_LOGIN = True/FORMS_LOGIN = False/g' /opt/swizzin/core/config.py

systemctl restart panel
systemctl restart nginx

url_output

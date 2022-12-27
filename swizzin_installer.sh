#!/bin/bash

export DEBIAN_FRONTEND=noninteractive

run_as_root() {
    if ! whoami | grep -q 'root'; then
        echo "This script must be run with sudo, please run:"
        echo "sudo $0"
        exit 1
    fi
}

run_as_root

cd /tmp || exit 1

echo "Getting packages..."
apt-get -qq update

echo -e "\nInstalling required packages..."
apt-get -qq install -y git expect

echo 'Please enter your Debian password (for the username appbox):'
read -r USER_PASSWORD

cat >/tmp/check.sh <<PWD
#!/bin/bash
expect << EOF
spawn su appbox -c "exit" 
expect "Password:"
send "$USER_PASSWORD\r"
#expect eof
set wait_result  [wait]
if {[lindex \\\$wait_result 2] == 0} {
        exit [lindex \\\$wait_result 3]
} 
else {
        exit 1 
}
EOF
PWD
chmod +x /tmp/check.sh

if ! su -c "/tmp/check.sh" appbox; then
    echo "Password does not match"
    rm /tmp/check.sh
    exit 1
fi
rm /tmp/check.sh

echo "Upgrading system..."
apt-get -qq upgrade -y

url_output() {
    echo -e "\n\n\n\n\n
Installation of Swizzin sucessful! Please point your browser to:
\e[4mhttps://${HOSTNAME}/\e[39m\e[0m

This will ask for your login details which are as follows:

\e[4mUsername: appbox\e[39m\e[0m
\e[4mPassword: ${USER_PASSWORD}\e[39m\e[0m

If you want to install/remove apps, please type the following into your terminal:
sudo box

Some apps will require you to restart the Debian app, so if you find something isn't working, please try that first!

Enjoy!

    \n\n"
}

mkdir -p /run/php/

if [ -d /etc/swizzin ]; then
    rm -rf /etc/swizzin
fi

git clone https://github.com/swizzin/swizzin.git /etc/swizzin &>/dev/null
cd /etc/swizzin || exit 1
git fetch origin overseer &>/dev/null
git merge --no-edit origin/overseer &>/dev/null
sed -i '/Type=exec/d' /etc/swizzin/scripts/install/overseerr.sh
sed -i 's/# _nginx/_nginx/g' /etc/swizzin/scripts/install/overseerr.sh
cat >/etc/swizzin/scripts/nginx/overseerr.sh <<EON
#!/usr/bin/env bash

cat > /etc/nginx/apps/overseerr.conf << EOF
location /overseerr {
    set \\\$app "overseerr";
    # Remove /overseerr path to pass to the app
    rewrite ^/overseerr/?(.*)$ /\\\$1 break;
    proxy_pass http://127.0.0.1:5055; # NO TRAILING SLASH

    # Redirect location headers
    proxy_redirect ^ /\\\$app;
    proxy_redirect /setup /\\\$app/setup;
    proxy_redirect /login /\\\$app/login;

    # Sub filters to replace hardcoded paths
    proxy_set_header Accept-Encoding "";
    sub_filter_once off;
    sub_filter_types *;
    sub_filter 'href="/"' 'href="/\\\$app"';
    sub_filter 'href="/login"' 'href="/\\\$app/login"';
    sub_filter 'href:"/"' 'href:"/\\\$app"';
    sub_filter '\/_next' '/\\\$app\/_next';
    sub_filter '/_next' '/\\\$app/_next';
    sub_filter '/api/v1' '/\\\$app/api/v1';
    sub_filter '/login/plex/loading' '/\\\$app/login/plex/loading';
    sub_filter '/images/' '/\\\$app/images/';
    sub_filter '/apple-' '/\\\$app/apple-';
    sub_filter '/favicon' '/\\\$app/favicon';
    sub_filter '/logo.png' '/\\\$app/logo.png';
    sub_filter '/logo_full.svg' '/\\\$app/logo_full.svg';
    sub_filter '/logo_stacked.svg' '/\\\$app/logo_stacked.svg';
    sub_filter '/site.webmanifest' '/\\\$app/site.webmanifest';
}
EOF

cat > /opt/overseerr/env.conf << EOF

# specify on which interface to listen, by default overseerr listens on all interfaces
HOST=127.0.0.1
EOF

systemctl try-restart overseerr
EON
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

echo "Installing php required by some apps..."
apt install -y php7.4-fpm
sed -i 's/www-data/appbox/g' /etc/php/7.4/fpm/pool.d/www.conf
systemctl restart php7.4-fpm

# Hack: Some apps need permissions fixed, chown every 10 mins
if crontab -l | grep -q '/srv'; then
    echo "Crontab already updated"
else
    (crontab -l; echo "*/10 * * * * chown -R appbox:appbox /srv >/dev/null 2>&1") | crontab
fi

url_output

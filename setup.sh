#!/usr/bin/env bash

writehosts(){
  echo "\
127.0.0.1  auth.$DOMAIN
127.0.0.1  traefik.$DOMAIN" | sudo tee -a /etc/hosts > /dev/null
}

email(){
  read -rep "Enter your email: [must match cloudflare also!] " EMAIL
}

apikey(){
  read -rep "Enter your cloudflare GLOBAL api key " APIKEY
}

zoneid(){
  read -rep "Enter your cloudflare zone id from the overview page: " ZONEID
}

echo "Checking for pre-requisites"

if [[ ! -x "$(command -v docker)" ]]; then
  echo "You must install Docker on your machine";
  exit 1
fi

if [[ ! -x "$(command -v docker-compose)" ]]; then
  echo "You must install Docker Compose on your machine";
  exit 1
fi

if [[ $(id -u)  != 0 ]]; then
  echo "The script requires root access to perform some functions such as modifying your /etc/hosts file"
  read -rp "Would you like to elevate access with sudo? [y/N] " confirmsudo
  if ! [[ "$confirmsudo" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    echo "Sudo elevation denied, exiting"
    exit 1
  fi
fi

read -erp "What is your root domain? (default/no selection is example.com): " DOMAIN

if [[ $DOMAIN == "" ]]; then
  DOMAIN="example.com"
fi

MODIFIED=$(grep $DOMAIN /etc/hosts && echo true || echo false)

if [[ $MODIFIED == "false" ]]; then
  writehosts
fi

if [[ $EMAIL != "" ]]; then
    sed -i "s/<your-email>/$EMAIL/g" {traefik/traefik.yml,traefik/cloudflare.env,cloudflare/cloudflare.env,global.env}
fi

if [[ $APIKEY != "" ]]; then
    sed -i "s/<cloudflare-global-api-key>/$APIKEY/g" {traefik/cloudflare.env,cloudflare/cloudflare.env}
fi

if [[ $ZONEID != "" ]]; then
    sed -i "s/<cloudflare-zone-id>/$APIKEY/g" {traefik/cloudflare.env,cloudflare/cloudflare.env}
fi

if [[ $DOMAIN != "example.com" ]]; then
    sed -i "s/example.com/$DOMAIN/g" {traefik/traefik.yml,traefik/config/cockpit.yml,authelia/configuration.yml,global.env,cockpit/cockpit.conf}
fi

echo "Starting Docker-Socket-Proxy container"
docker-compose -f docker/docker-compose.yml up -d 

echo "End of script. Starting Traefik. Check the logs."
echo "If no issues with traefik then start oAuth container and then start whatever containers you want to use with docker-compose-manager...."
docker-compose -f traefik/docker-compose.yml up -d

if [[ $? != 0 ]]; then
  exit 1
fi

cat << EOF
Setup completed successfully.
EOF
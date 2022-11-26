#              Cockpit

Server Management Panel for headless servers. I install this directly on the host. 

Cockpit pulled docker support in favor of Podman. However you can manually add it as its still available in the ubuntu 20.04 repos.

Install Cockpit first. Then install the docker module

```
sudo apt update 
sudo apt install cockpit -y
sudo systemctl start cockpit
sudo systemctl status cockpit


cd /tmp
wget https://launchpad.net/ubuntu/+source/cockpit/215-1~ubuntu19.10.1/+build/18889196/+files/cockpit-docker_215-1~ubuntu19.10.1_all.deb
sudo dpkg -i cockpit-docker_215-1\~ubuntu19.10.1_all.deb
rm cockpit-docker_215-1\~ubuntu19.10.1_all.deb
```

Cockpit can then be accessed at https://SERVERIP:9090  
Login with your user and password for the server. 


If you want to access cockpit on subdomain youll want to edit the cockpit.conf file with your domain and move it to /etc/cockpit/  

If using traefik, the provided cockpit.yml will go in your dynamic file provider directory. Youll need to edit that with the correct ip from above.

If you want another layer of auth on top and are doing so through traefik forward auth, once you have it setup uncomment the cockpit.yml file. 
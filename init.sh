#!/bin/bash 


#OS config and packages
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -   && [[ $(lsb_release -cs) == "eoan" ]] && ( add-apt-repository "deb [arch=$(dpkg --print-architecture)] https://download.docker.com/linux/ubuntu disco stable" ) || ( add-apt-repository "deb [arch=$(dpkg --print-architecture)] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" )
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io --no-install-recommends 
apt-get install -y git

usermode add -a -G docker ubuntu

#Build and setup the project
export OVPN_DATA="/opt/ovpn-data"
cd /opt/
git clone $PROJECT
cd docker-openvpn
docker build . -t docker/ovpn

#build the nodejs app which Okta connect here to get the config file
cd web-config-serve
docker build . -t ovpn-web-config-serve
cd ..


#config
docker run -v $OVPN_DATA:/etc/openvpn --log-driver=none --rm -it docker/ovpn ovpn_initpki nopass
docker run -v $OVPN_DATA:/etc/openvpn --log-driver=none --rm docker/ovpn ovpn_genconfig -P okta -u udp://$OVPN_HOST


#🏃‍ RUN Images
docker run -v $OVPN_DATA:/etc/openvpn -d -p 443:1194/udp --cap-add=NET_ADMIN --name ovpn --user root -e OKTA_HOST=$OKTA_HOST -e OKTA_TOKEN=$OKTA_TOKEN -e APP_ID=$APP_ID  docker/ovpn

docker run  -v /var/run/docker.sock:/var/run/docker.sock -v $OVPN_DATA:$OVPN_DATA -p 8110:3000 -t -d -e ISSUER=$ISSUER -e VALID_DOMAIN=$VALID_DOMAIN -e OVPN_DOCKER_IMG="docker/ovpn" --name  ovpn-web-config-serve ovpn-web-config-serve

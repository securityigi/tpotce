#!/bin/bash
########################################################
# T-Pot Community Edition post install script          #
# Ubuntu server 14.04, x64                             #
#                                                      #
# v0.46 by mo, DTAG, 2015-03-09                        #
########################################################

# Let's make sure there is a warning if running for a second time
if [ -f install.log ];
  then fuECHO "### Running more than once may complicate things. Erase install.log if you are really sure."
  exit 1;
fi

# Let's log for the beauty of it
set -e
exec 2> >(tee "install.err")
exec > >(tee "install.log")

# Let's create a function for colorful output
fuECHO () {
  local myRED=1
  local myWHT=7
  tput setaf $myRED
  echo $1 "$2"
  tput setaf $myWHT
}

# Let's modify the sources list
sed -i '/cdrom/d' /etc/apt/sources.list

# Let's add the docker repository
fuECHO "### Adding docker repository."
apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 36A1D7869245C8950F966E92D8576A8BA88D21E9
tee /etc/apt/sources.list.d/docker.list <<EOF
deb https://get.docker.io/ubuntu docker main
EOF

# Let's pull some updates
fuECHO "### Pulling Updates."
apt-get update -y
fuECHO "### Installing Updates."
apt-get dist-upgrade -y

# Let's install all the packages we need
fuECHO "### Installing packages."
apt-get install curl ethtool git ntp libpam-google-authenticator lxc-docker-1.5.0 vim -y

# Let's add a new user
fuECHO "### Adding new user."
addgroup --gid 2000 tpot
adduser --system --no-create-home --uid 2000 --disabled-password --disabled-login --gid 2000 tpot

# Let's set the hostname
fuECHO "### Setting a new hostname."
myHOST=ce$(date +%s)$RANDOM
hostnamectl set-hostname $myHOST
sed -i 's#127.0.1.1.*#127.0.1.1\t'"$myHOST"'#g' /etc/hosts

# Let's patch sshd_config
fuECHO "### Patching sshd_config to listen on port 64295 and deny password authentication."
sed -i 's#Port 22#Port 64295#' /etc/ssh/sshd_config
sed -i 's#\#PasswordAuthentication yes#PasswordAuthentication no#' /etc/ssh/sshd_config

# Let's disable ssh service
echo "manual" >> /etc/init/ssh.override

# Let's patch docker defaults, so we can run images as service
fuECHO "### Patching docker defaults."
tee -a /etc/default/docker <<EOF
DOCKER_OPTS="-r=false"
EOF

# Let's load docker images from remote
fuECHO "### Downloading docker images from DockerHub. Please be patient, this may take a while."
for name in $(cat /root/tpotce/data/images.conf) 
do
  docker pull dtagdevsec/$name
done

# Let's add the daily update check with a weekly clean interval
fuECHO "### Modifying update checks."
tee /etc/apt/apt.conf.d/10periodic <<EOF
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "0";
APT::Periodic::AutocleanInterval "7";
EOF

# Let's add some conrjobs
fuECHO "### Adding cronjobs."
tee -a /etc/crontab <<EOF

# Show running containers every 60s via /dev/tty2
*/1 * * * * 	root 	/usr/bin/status.sh > /dev/tty2 

# Check if containers and services are up
*/5 * * * * 	root 	/usr/bin/check.sh

# Check if updated images are available and download them 
27 1 * * *  	root	for i in \$(cat /data/images.conf); do /usr/bin/docker pull dtagdevsec/\$i:latest; done

# Restart docker service and containers
27 3 * * * 	root 	/usr/bin/dcres.sh

# Delete elastic indices older than 30 days
27 4 * * *  root  /usr/bin/docker exec elk bash -c '/usr/local/bin/curator --host 127.0.0.1 delete --older-than 30'
EOF

# Let's take care of some files and permissions
chmod 500 /root/tpotce/bin/*
chmod 600 /root/tpotce/data/*
chmod 644 /root/tpotce/etc/issue
chmod 755 /root/tpotce/etc/rc.local
chmod 700 /root/tpotce/home/*
chown tsec:tsec /root/tpotce/home/*
chmod 644 /root/tpotce/upstart/*

# Let's create some files and folders
fuECHO "### Creating some files and folders."
mkdir -p /data/ews/log /data/ews/conf /data/elk/data /data/elk/log

# Let's move some files
cp -R /root/tpotce/bin/* /usr/bin/
cp -R /root/tpotce/data/* /data/
cp -R /root/tpotce/etc/issue /etc/
cp -R /root/tpotce/home/* /home/tsec/
cp -R /root/tpotce/upstart/* /etc/init/

# Let's take care of some files and permissions
chmod 660 -R /data
chown tpot:tpot -R /data
chown tsec:tsec /home/tsec/*.sh

# Final steps
fuECHO "### Thanks for your patience. Now rebooting."
mv /root/tpotce/etc/rc.local /etc/rc.local && rm -rf /root/tpotce/ && chage -d 0 tsec && sleep 2 && reboot

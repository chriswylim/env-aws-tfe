#!/bin/bash

#####
# Author: Chris Lim < limwei.yew@petronas.com >, updated on 28/02/2022
# When this script is executed as EC2 user data, it will be executed as root
# Ref: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/user-data.html#user-data-shell-scripts
#####

# Install packages
yum update -y && yum install -y docker git tar wget jq vim unzip
chmod 666 /var/run/docker.sock

# Install AWS CLI
curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" --output "/opt/awscliv2.zip" && unzip "/opt/awscliv2.zip" -d "/opt/" && /opt/aws/install

# Complete Uninstall Podman (RHEL-8:Docker-Emulator)
# Reference: http://crunchtools.com/testing-with-podman-complete-uninstall-reinstall/
rm -rf /etc/containers/* /var/lib/containers/* /etc/docker /etc/subuid* /etc/subgid*
yum remove -y buildah skopeo podman containers-common atomic-registries docker
rm -rf /home/fatherlinux/.local/share/containers/

# Install Docker CE on RHEL 8 / CentOS 8
# Reference: https://linuxconfig.org/how-to-install-docker-in-rhel-8
dnf config-manager --add-repo=https://download.docker.com/linux/centos/docker-ce.repo
dnf install -y --nobest --skip-broken docker-ce
dnf install -y https://download.docker.com/linux/centos/7/x86_64/stable/Packages/containerd.io-1.2.6-3.3.el7.x86_64.rpm
systemctl disable firewalld && systemctl enable --now docker
curl -L "https://github.com/docker/compose/releases/download/1.23.2/docker-compose-$(uname -s)-$(uname -m)" -o docker-compose 
mv docker-compose /usr/local/bin && sudo chmod +x /usr/local/bin/docker-compose

# Update and start
systemctl start docker

# Install Session Manager
curl "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/linux_64bit/session-manager-plugin.rpm" -o "session-manager-plugin.rpm" && yum install -y session-manager-plugin.rpm

# Create new OS user
useradd -c "PETRONAS DevOps Admin" -d /home/deoadm -g 100 -m -s /bin/bash deoadm
usermod -G wheel deoadm
mkdir /home/deoadm/.ssh
grep "\-KeyPair" /home/ec2-user/.ssh/authorized_keys >>  /home/deoadm/.ssh/authorized_keys
mkdir /home/deoadm/.ssh
chmod 700 /home/deoadm/.ssh
chmod 600 /home/deoadm/.ssh/authorized_keys
chown -R deoadm:users /home/deoadm/.ssh

# Add awscli $PATH
# Session c2 (deoadm)
runuser -l deoadm -c 'export PATH=$PATH:/usr/local/bin'

# Add awscli $PATH
# Session c3 (root)
runuser -l root -c 'export PATH=$PATH:/usr/local/bin'

# Install replicated and run as a systemd service
# Session c4 (root)
runuser -l root -c 'mkdir /etc/tfe'

# Settings
# Session c5 (root)
runuser -l root -c '/usr/local/bin/aws s3 cp s3://ptawsg-dev-tfebucket/petronas.rli /etc/tfe/petronas.rli'
# Session c6 (root)
runuser -l root -c '/usr/local/bin/aws s3 cp s3://ptawsg-dev-tfebucket/settings.json /etc/tfe/settings.json'
# Session c7 (root)
runuser -l root -c '/usr/local/bin/aws s3 cp s3://ptawsg-dev-tfebucket/replicated.conf /etc/replicated.conf'

# Download
# Session c8 (root)
runuser -l root -c 'curl -o /etc/tfe/install.sh https://install.terraform.io/ptfe/stable && chmod +x /etc/tfe/install.sh'

# Configure
# Session c9 (root)
runuser -l root -c 'declare -r PubIP=$(curl http://checkip.amazonaws.com); declare -r PrvIP=$(curl http://169.254.169.254/latest/meta-data/local-ipv4); /etc/tfe/install.sh no-proxy private-address=$PrvIP public-address=$PubIP'
#!/bin/bash

#####
# Author: Chris Lim < limwei.yew@petronas.com >, updated on 28/02/2022
# When this script is executed as EC2 user data, it will be executed as sudo-ec2user (not-root)
# Ref: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/user-data.html#user-data-shell-scripts
#####

# Install packages
yum update -y && yum install -y docker git tar wget jq vim unzip python36
chmod 666 /var/run/docker.sock

# Install AWS CLI - as sudo 'ec2-user'
curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" --output "/opt/awscliv2.zip" && unzip "/opt/awscliv2.zip" -d "/opt/" && /opt/aws/install
# sudo ./aws/install --bin-dir /usr/local/bin --install-dir /usr/local/aws-cli

# Complete Uninstall Podman (RHEL-8:Docker-Emulator)
# Reference: http://crunchtools.com/testing-with-podman-complete-uninstall-reinstall/
rm -rf /etc/containers/* /var/lib/containers/* /etc/docker /etc/subuid* /etc/subgid*
yum remove -y buildah skopeo podman containers-common atomic-registries docker
# rm -rf /home/fatherlinux/.local/share/containers/
rm -rf /home/ec2-user/.local/share/containers/

# Install Docker CE on RHEL 8 / CentOS 8
# Reference: https://linuxconfig.org/how-to-install-docker-in-rhel-8
dnf config-manager --add-repo=https://download.docker.com/linux/centos/docker-ce.repo
dnf install -y --nobest --skip-broken docker-ce
# included in yum install docker-ce
# dnf install -y https://download.docker.com/linux/centos/7/x86_64/stable/Packages/containerd.io-1.2.6-3.3.el7.x86_64.rpm
systemctl disable firewalld && systemctl enable --now docker

### Installating Docker Compose
curl -L "https://github.com/docker/compose/releases/download/1.23.2/docker-compose-$(uname -s)-$(uname -m)" -o docker-compose 
mv docker-compose /usr/local/bin && sudo chmod +x /usr/local/bin/docker-compose

# Latest docker && containerd
yum update -y 

# Update and start
systemctl start docker

# Install Session Manager
curl "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/linux_64bit/session-manager-plugin.rpm" -o "session-manager-plugin.rpm" && yum install -y session-manager-plugin.rpm

# Create new OS user
useradd -c "PETRONAS DevOps Admin" -d /home/deoadm -m -s /sbin/nologin deoadm
# by default, it will create a group 'deoadm'
usermod -G wheel
# add NOPASSWD: ALL to user deoadm
printf 'deoadm\tALL=(ALL)\tNOPASSWD: ALL\n' | sudo EDITOR='tee -a' visudo
# Start
mkdir /home/deoadm/.ssh
grep "\-KeyPair" /home/ec2-user/.ssh/authorized_keys >>  /home/deoadm/.ssh/authorized_keys
mkdir /home/deoadm/.ssh
chmod 700 /home/deoadm/.ssh
chmod 600 /home/deoadm/.ssh/authorized_keys
chown -R deoadm:users /home/deoadm/.ssh

# Add awscli $PATH
# Session c2 (deoadm)
runuser -l deoadm -c 'jq '.foo.bar=$zeus''

# Add awscli $PATH
# Session c3 (root)
runuser -l root -c 'export PATH=$PATH:/usr/local/bin'

# Install replicated and run as a systemd service
# Session c4 (root)
runuser -l root -c 'mkdir /etc/tfe'

# Settings
# Session c5a (root)
runuser -l root -c '/usr/local/bin/aws s3 cp s3://ptawsg-dev-tfebucket/petronas.rli /etc/tfe/petronas.rli && /usr/local/bin/aws s3 cp s3://ptawsg-dev-tfebucket/settings-stable.json /etc/tfe/settings-stable.json'

# Session c5b (root)
runuser -l root -c 'declare -r PubIP=$(curl http://169.254.169.254/latest/meta-data/public-ipv4); touch /etc/tfe/settings.json | jq --arg variable "${PubIP}" '.hostname.value = $variable' /etc/tfe/settings-stable.json > /etc/tfe/settings.json && echo "done"'

# Session c6 (root)
runuser -l root -c '/usr/local/bin/aws s3 cp s3://ptawsg-dev-tfebucket/server.crt /etc/tfe/server.crt && /usr/local/bin/aws s3 cp s3://ptawsg-dev-tfebucket/server.key /etc/tfe/server.key'

# Session c7 (root)
runuser -l root -c '/usr/local/bin/aws s3 cp s3://ptawsg-dev-tfebucket/replicated.conf /etc/replicated.conf'

# Download
# Session c8 (root)
runuser -l root -c 'curl -o /etc/tfe/install.sh https://install.terraform.io/ptfe/stable && chmod +x /etc/tfe/install.sh'

# Configure
# Session c9 (root)
runuser -l root -c '
declare -r PubIP=$(curl http://169.254.169.254/latest/meta-data/public-ipv4); 
declare -r PrvIP=$(curl http://169.254.169.254/latest/meta-data/local-ipv4); 
/etc/tfe/install.sh no-proxy private-address=${PrvIP} public-address=${PubIP}
'


:'
# Check replicated progress #
systemctl status replicated.service

# Commands to restart TFE #
systemctl stop replicated replicated-ui replicated-operator
declare -r PubIP=$(curl http://169.254.169.254/latest/meta-data/public-ipv4); declare -r PrvIP=$(curl http://169.254.169.254/latest/meta-data/local-ipv4); /etc/tfe/install.sh no-proxy private-address=${PrvIP} public-address=${PubIP}

# Commands to keep TFE alive #
systemctl stop replicated replicated-ui replicated-operator && rm -rf /var/lib/replicated
systemctl start replicated.service
systemctl start replicated replicated-ui replicated-operator

/usr/local/bin/replicatedctl app status
/usr/local/bin/replicatedctl app stop
/usr/local/bin/replicatedctl app start

/usr/local/bin/replicatedctl health-check
/usr/local/bin/replicatedctl system status

## Soft Reboot
/usr/local/bin/replicatedctl app stop && sleep 30 && docker volume rm rabbitmq && sleep 30 && /usr/local/bin/replicatedctl app start
/usr/local/bin/replicatedctl app-config export --hidden | grep hostname -A 5
/usr/local/bin/replicatedctl app-config set hostname --data "123"

## Change hostname
declare -r old_val=$(cat "/etc/tfe/settings.json" | jq '.hostname.value'); echo ${old_val:1:-1}
declare -r new_val=$(/usr/local/bin/aws elbv2 describe-load-balancers --load-balancer-arns arn:aws:elasticloadbalancing:ap-southeast-1:900051432098:loadbalancer/app/PTAWSG-5TFELB01/b1bc848146316134 | jq ".LoadBalancers[].DNSName"); echo ${new_val:1:-1}
sed -i "s/"${old_val:1:-1}"/"${new_val:1:-1}"/g" /etc/tfe/settings.json

/usr/local/bin/replicatedctl app-config set hostname --data ${new_val:1:-1}
/usr/local/bin/replicatedctl app-config export --hidden | grep hostname -A 5
/usr/local/bin/replicatedctl app apply-config

/usr/local/bin/replicatedctl app status

## Reapply settings.json
/usr/local/bin/replicatedctl app
/usr/local/bin/replicatedctl app apply-config 

systemctl --type=service
systemctl --type=service --state=active
systemctl --type=service --state=running

vim ~/.bashrc
alias running_services='systemctl list-units  --type=service  --state=running'

>
docker logs replicated-native
>>
docker logs replicated-nsqd
docker logs replicated-postgres
docker logs replicated-cron
docker logs replicated-processor
docker logs replicated-api
>>
docker logs replicated-ui
docker logs replicated-premkit
docker logs replicated-operator
>>>
docker logs ptfe_base_startup
docker logs ptfe_vault
>>>>
ptfe_atlas
ptfe_sidekiq
ptfe_registry_worker
ptfe_registry_api
ptfe_migrations
ptfe_registry_migrations
ptfe_archivist
ptfe_build_worker
ptfe_build_manager
ptfe_base_workers
ptfe_backup_restore
ptfe_vault
ptfe_base_startup
rabbitmq
ptfe_nginx
ptfe_nomad
ptfe_postgresql_setup
ptfe_slug_ingress
ptfe_outbound_http_proxy
ptfe_state_parser
ptfe_health_check
ptfe_cost_estimation
ptfe_sentinel_worker
ptfe_plan_exporter_worker
build_worker_metadata_firewall

replicatedctl app stop
docker volume rm rabbitmq
replicatedctl app start

dockerd --debug
token=5b9e89ae52d5f5831bd1293e483b05d986f5719918a27fcc3b7fa9f3f440e2e5

declare -r PubIP=13.212.188.35

# replace key variable
jq --arg variable "$PubIP" '.hostname.value = $variable' settings-stable.json > settings-stable2.json

aws s3 cp s3://ptawsg-dev-tfebucket/settings-stable.json settings-stable.json
declare -r PubIP="123.123.123.123"; jq --arg variable "$PubIP" '.hostname.value = $variable' settings-stable.json > settings.json

sed -i '/spark.driver.memory/c\   \"spark.driver.memory\" : \"1gb\",' file.txt
sed -i '/hostname.value/c\ \"hostname.value\" : \"123.123.123.321\",' settings.json
jq --arg variable "${public_ip}" ".hostname.value |= "$variable"" settings.json 

> devaws.tfe.petronas.com - get .CRT .KEY - pull mechanism awaiting for response from any VM
>> ???
> register VM to .CRT and hostname: devaws.tfe.petronas.com
> NGINX -> forward all IP to dev.aws.tfe.petronas.com
>> How do we access the VM in the first place?

>>> VM -> DEVAWS.TFE-A -> CNAME: LB.DNS
>>> LB.DNS -> VM (3 OF 3) -> DEVAWS.TFE
---
>>> NGINX, COUNTER IF A: >1 -> LOCALHOST:80
'
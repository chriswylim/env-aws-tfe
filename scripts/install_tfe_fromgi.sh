#!/bin/bash

#####
# Author: Chris Lim < limwei.yew@petronas.com >, updated on 28/02/2022
# When this script is executed as EC2 user data, it will be executed as root
# Ref: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/user-data.html#user-data-shell-scripts
#####

# Latest docker && containerd
yum update -y 

# Update and start
systemctl start docker

# Install replicated and run as a systemd service
# Session c4 (root)
runuser -l root -c 'mkdir /etc/tfe'

# Settings
# Session c5a (root)
runuser -l root -c '/usr/local/bin/aws s3 cp s3://ptawsg-dev-tfebucket/petronas.rli /etc/tfe/petronas.rli && /usr/local/bin/aws s3 cp s3://ptawsg-dev-tfebucket/settings-stable.json /etc/tfe/settings.json'

# Session c5b (root)
# runuser -l root -c 'declare -r old_val=$(cat "/etc/tfe/settings.json" | jq '.hostname.value'); echo ${old_val:1:-1}; declare -r new_val=$(curl http://169.254.169.254/latest/meta-data/public-ipv4); echo ${new_val}; sed -i "s/"${old_val:1:-1}"/"${new_val}"/g" /etc/tfe/settings.json'
runuser -l root -c 'declare -r old_val=$(cat "/etc/tfe/settings.json" | jq '.hostname.value'); echo ${old_val:1:-1}; declare -r new_val=$(/usr/local/bin/aws elbv2 describe-load-balancers --load-balancer-arns arn:aws:elasticloadbalancing:ap-southeast-1:900051432098:loadbalancer/app/PTAWSG-5TFELB01/b1bc848146316134 | jq ".LoadBalancers[].DNSName"); echo ${new_val:1:-1}; sed -i "s/"${old_val:1:-1}"/"${new_val:1:-1}"/g" /etc/tfe/settings.json'

# Session c6 (root)
runuser -l root -c '/usr/local/bin/aws s3 cp s3://ptawsg-dev-tfebucket/server.crt /etc/tfe/server.crt && /usr/local/bin/aws s3 cp s3://ptawsg-dev-tfebucket/server.key /etc/tfe/server.key'

# Session c7 (root)
runuser -l root -c '/usr/local/bin/aws s3 cp s3://ptawsg-dev-tfebucket/replicated.conf /etc/replicated.conf'

# Download
# Session c8 (root)
runuser -l root -c 'curl -o /etc/tfe/install.sh https://install.terraform.io/ptfe/stable && chmod +x /etc/tfe/install.sh'

# Configure
# Session c9 (root)
runuser -l root -c 'declare -r PubIP=$(curl http://169.254.169.254/latest/meta-data/public-ipv4); declare -r PrvIP=$(curl http://169.254.169.254/latest/meta-data/local-ipv4); /etc/tfe/install.sh no-proxy private-address=$PrvIP public-address=$PubIP'

:'
# working
runuser -l root -c '/usr/local/bin/aws s3 cp s3://ptawsg-dev-tfebucket/settings-stable.json /etc/tfe/settings-stable.json'
runuser -l root -c 'declare -r old_val=$(cat "/etc/tfe/settings-stable.json" | jq '.hostname.value'); echo ${old_val:1:-1}'
runuser -l root -c 'declare -r new_val=$(curl http://169.254.169.254/latest/meta-data/public-ipv4); echo ${new_val}' 
runuser -l root -c 'sed -i "s/"${old_val:1:-1}"/"${new_val}"/g" /etc/tfe/settings-stable.json'

declare -r old_val=$(cat "/etc/tfe/settings.json" | jq '.hostname.value'); echo ${old_val:1:-1}; 
declare -r new_val=$(/usr/local/bin/aws elbv2 describe-load-balancers --load-balancer-arns arn:aws:elasticloadbalancing:ap-southeast-1:900051432098:loadbalancer/app/PTAWSG-5TFELB01/b1bc848146316134 | jq ".LoadBalancers[].DNSName"); echo ${new_val}; 
sed -i "s/"${old_val:1:-1}"/"${new_val:1:-1}"/g" /etc/tfe/settings.json'
'
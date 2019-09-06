#!/usr/bin/env bash

set -xe

# Create user sdn
useradd -m -d /home/sdn -s /bin/bash sdn
usermod -aG sudo sdn
usermod -aG vboxsf sdn
echo "sdn:rocks" | chpasswd
echo "sdn ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/99_sdn
chmod 440 /etc/sudoers.d/99_sdn
update-locale LC_ALL="en_US.UTF-8"

apt-get update

apt-get install -y --no-install-recommends apt-transport-https ca-certificates
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
apt-get update

# Required packages
DEBIAN_FRONTEND=noninteractive apt-get -y --no-install-recommends install \
    avahi-daemon \
    git \
    bash-completion \
    htop \
    python \
    zip unzip \
    make \
    wget \
    curl \
    vim nano emacs \
    docker-ce

# Enable Docker at startup
systemctl start docker
systemctl enable docker
# Add sdn user to docker group
usermod -a -G docker sdn

# Install pip
curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py
python get-pip.py --force-reinstall
rm -f get-pip.py

# Bash autocompletion
echo "source /etc/profile.d/bash_completion.sh" >> ~/.bashrc

# Fix SSH server config
tee -a /etc/ssh/sshd_config <<EOF

UseDNS no
EOF
sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/g' /etc/ssh/sshd_config

# IntelliJ
snap install intellij-idea-community --classic

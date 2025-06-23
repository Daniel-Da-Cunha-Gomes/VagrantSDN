#!/bin/bash

# Activer IP forwarding
sudo sysctl -w net.ipv4.ip_forward=1

# Installer FRR et Open vSwitch
sudo apt-get update
sudo apt-get install -y frr openvswitch-switch

# Configurer interfaces réseau (par défaut Vagrant les configure, ici juste vérif)
ip addr add 192.168.10.12/24 dev eth0
ip addr add 192.168.30.1/24 dev eth1  # Y=20 pour r1, 30 pour r2

# Démarrer et configurer FRR avec OSPF
cat <<EOF > /etc/frr/frr.conf
!
router ospf
 network 192.168.10.0/24 area 0
 network 192.168.20.0/24 area 0
 network 192.168.30.0/24 area 0
!
EOF

sudo systemctl restart frr

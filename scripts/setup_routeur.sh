#!/bin/bash

# Activer IP forwarding
sudo sysctl -w net.ipv4.ip_forward=1

# Installer FRR et Open vSwitch
sudo apt-get update
sudo apt-get install -y frr openvswitch-switch


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

#!/bin/bash

# Installation des paquets nécessaires
apt-get update && apt-get install -y frr frr-pythontools openvswitch-switch

# Configuration OSPF via FRR
cat <<EOF > /etc/frr/frr.conf
!
hostname r2
!
router ospf
 network 192.168.10.0/24 area 0
 network 192.168.30.0/24 area 0
!
line vty
EOF

# Redémarrage du service FRR
systemctl restart frr
systemctl enable frr

# Configuration Open vSwitch
ovs-vsctl add-br br0
ovs-vsctl add-port br0 eth1  # vers net-core
ovs-vsctl add-port br0 eth2  # vers net-clientB
ovs-vsctl set-controller br0 tcp:192.168.10.10:6633

# Activation IP forwarding
sysctl -w net.ipv4.ip_forward=1

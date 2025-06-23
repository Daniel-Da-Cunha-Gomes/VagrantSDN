#!/bin/bash
# Mise à jour et installation dépendances
apt-get update && apt-get install -y python3 python3-pip openvswitch-switch

# Installation Ryu
pip3 install ryu

# Configuration Open vSwitch
ovs-vsctl add-br br0
ovs-vsctl set-controller br0 tcp:127.0.0.1:6633

# Activation IP forwarding (si nécessaire)
sysctl -w net.ipv4.ip_forward=1

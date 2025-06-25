#!/bin/bash

# Mise à jour & installation
apt-get update && apt-get install -y python3 python3-pip openvswitch-switch

# Installation Ryu
pip3 install ryu

# Configuration OVS
ovs-vsctl add-br br0
ovs-vsctl add-port br0 eth1  # Associer la 1ère interface privée

# Contrôle via Ryu sur IP fixe
ovs-vsctl set-controller br0 tcp:192.168.10.10:6633

# Activer le routage IP
sysctl -w net.ipv4.ip_forward=1

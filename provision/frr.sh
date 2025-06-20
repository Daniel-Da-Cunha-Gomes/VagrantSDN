#!/bin/bash
sudo apt update && sudo apt install -y frr frr-pythontools openvswitch-switch

# Activer daemons OSPF
sudo sed -i 's/bgpd=no/bgpd=yes/' /etc/frr/daemons
sudo sed -i 's/ospfd=no/ospfd=yes/' /etc/frr/daemons

sudo systemctl enable frr
sudo systemctl start frr

# Open vSwitch config de base
sudo ovs-vsctl add-br br0

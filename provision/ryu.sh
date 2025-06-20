#!/bin/bash

# Mise à jour des paquets
sudo apt update

# Installation d'Open vSwitch
sudo apt install -y openvswitch-switch

# Installation de pip et de Ryu via pip (car pas dans apt)
sudo apt install -y python3-pip
pip3 install ryu

# Création du bridge OVS
sudo ovs-vsctl add-br br0
sudo ovs-vsctl set-controller br0 tcp:127.0.0.1:6633

# Afficher l’état du bridge
sudo ovs-vsctl show

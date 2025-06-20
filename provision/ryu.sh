#!/bin/bash
sudo apt update && sudo apt install -y python3-ryu openvswitch-switch git
sudo ovs-vsctl add-br br0
sudo ovs-vsctl set-controller br0 tcp:127.0.0.1:6633

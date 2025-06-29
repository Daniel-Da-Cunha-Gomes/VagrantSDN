#!/bin/bash

echo "=== Script de débogage réseau ==="

# Informations système
echo "=== Hostname ==="
hostname

echo "=== Interfaces réseau ==="
ip addr show

echo "=== Table de routage ==="
ip route show

echo "=== Voisins ARP ==="
ip neigh show

# Tests de connectivité
echo "=== Test ping localhost ==="
ping -c 2 127.0.0.1

echo "=== Test ping gateway ==="
GATEWAY=$(ip route | grep default | awk '{print $3}' | head -1)
if [ ! -z "$GATEWAY" ]; then
    echo "Gateway: $GATEWAY"
    ping -c 2 $GATEWAY
else
    echo "Pas de gateway par défaut trouvée"
fi

# Vérification des services
echo "=== Services réseau ==="
if command -v systemctl &> /dev/null; then
    echo "FRR:" $(systemctl is-active frr 2>/dev/null || echo "non installé")
    echo "OVS:" $(systemctl is-active openvswitch-switch 2>/dev/null || echo "non installé")
    echo "Apache:" $(systemctl is-active apache2 2>/dev/null || echo "non installé")
fi

# Configuration OVS si présente
if command -v ovs-vsctl &> /dev/null; then
    echo "=== Configuration Open vSwitch ==="
    ovs-vsctl show
fi

# Configuration FRR si présente
if command -v vtysh &> /dev/null; then
    echo "=== Routes OSPF ==="
    vtysh -c "show ip route ospf" 2>/dev/null || echo "OSPF non configuré"
    echo "=== Voisins OSPF ==="
    vtysh -c "show ip ospf neighbor" 2>/dev/null || echo "Pas de voisins OSPF"
fi

echo "=== Fin du débogage ==="

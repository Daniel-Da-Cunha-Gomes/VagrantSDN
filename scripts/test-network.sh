#!/bin/bash

echo "=== Tests de connectivité réseau ==="

# Afficher la configuration réseau actuelle
echo "=== Configuration réseau locale ==="
ip addr show
echo ""
echo "=== Table de routage ==="
ip route show
echo ""

# Test de base - ping vers les routeurs
echo "1. Test ping vers Router1 (10.0.2.1)"
ping -c 3 10.0.2.1

echo "2. Test ping vers Router2 (10.0.3.1)"
ping -c 3 10.0.3.1

echo "3. Test ping réseau SDN Router1 (10.0.1.1)"
ping -c 3 10.0.1.1

echo "4. Test ping réseau SDN Router2 (10.0.1.2)"
ping -c 3 10.0.1.2

# Test entre clients
HOSTNAME=$(hostname)
if [ "$HOSTNAME" = "client1" ]; then
    echo "5. Test ping client1 -> client2 (10.0.3.10)"
    ping -c 3 10.0.3.10
    
    echo "6. Test HTTP client1 -> client2"
    curl -s --connect-timeout 5 http://10.0.3.10 | head -5 || echo "Échec connexion HTTP"
    
elif [ "$HOSTNAME" = "client2" ]; then
    echo "5. Test ping client2 -> client1 (10.0.2.10)"
    ping -c 3 10.0.2.10
    
    echo "6. Test HTTP client2 -> client1"
    curl -s --connect-timeout 5 http://10.0.2.10 | head -5 || echo "Échec connexion HTTP"
fi

# Test traceroute
echo "7. Traceroute vers l'autre réseau"
if [ "$HOSTNAME" = "client1" ]; then
    traceroute -n 10.0.3.10
elif [ "$HOSTNAME" = "client2" ]; then
    traceroute -n 10.0.2.10
fi

echo "=== Tests terminés ==="

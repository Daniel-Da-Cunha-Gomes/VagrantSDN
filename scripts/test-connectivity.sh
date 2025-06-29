#!/bin/bash

echo "=== Test de connectivité complet ==="

HOSTNAME=$(hostname)
echo "Test depuis: $HOSTNAME"

# Afficher la configuration réseau
echo "=== Configuration réseau ==="
ip addr show | grep -E "(inet |^[0-9]+:)"
echo ""
echo "=== Table de routage ==="
ip route show
echo ""

# Tests de ping
echo "=== Tests de ping ==="

# Test vers les routeurs
echo "1. Ping vers Router1 SDN (10.0.1.1)"
ping -c 2 10.0.1.1 && echo "✓ OK" || echo "✗ ÉCHEC"

echo "2. Ping vers Router2 SDN (10.0.1.2)"
ping -c 2 10.0.1.2 && echo "✓ OK" || echo "✗ ÉCHEC"

echo "3. Ping vers Contrôleur (10.0.1.10)"
ping -c 2 10.0.1.10 && echo "✓ OK" || echo "✗ ÉCHEC"

# Tests spécifiques selon le client
if [ "$HOSTNAME" = "client1" ]; then
    echo "4. Ping vers Router1 Client (10.0.2.1)"
    ping -c 2 10.0.2.1 && echo "✓ OK" || echo "✗ ÉCHEC"
    
    echo "5. Ping vers Client2 (10.0.3.10)"
    ping -c 2 10.0.3.10 && echo "✓ OK" || echo "✗ ÉCHEC"
    
    echo "6. Test HTTP vers Client2"
    curl -s --connect-timeout 5 http://10.0.3.10 | head -2 && echo "✓ OK" || echo "✗ ÉCHEC"
    
elif [ "$HOSTNAME" = "client2" ]; then
    echo "4. Ping vers Router2 Client (10.0.3.1)"
    ping -c 2 10.0.3.1 && echo "✓ OK" || echo "✗ ÉCHEC"
    
    echo "5. Ping vers Client1 (10.0.2.10)"
    ping -c 2 10.0.2.10 && echo "✓ OK" || echo "✗ ÉCHEC"
    
    echo "6. Test HTTP vers Client1"
    curl -s --connect-timeout 5 http://10.0.2.10 | head -2 && echo "✓ OK" || echo "✗ ÉCHEC"
fi

# Traceroute
echo "=== Traceroute ==="
if [ "$HOSTNAME" = "client1" ]; then
    echo "Traceroute vers Client2:"
    traceroute -n 10.0.3.10
elif [ "$HOSTNAME" = "client2" ]; then
    echo "Traceroute vers Client1:"
    traceroute -n 10.0.2.10
fi

echo "=== Tests terminés ==="

#!/bin/bash

echo "=== Diagnostic de connectivité avancé ==="

HOSTNAME=$(hostname)
echo "Machine: $HOSTNAME"
echo "Date: $(date)"
echo ""

# 1. Configuration réseau
echo "=== 1. Configuration réseau ==="
echo "Interfaces:"
ip addr show | grep -E "(^[0-9]+:|inet )" | grep -v "127.0.0.1"
echo ""
echo "Routes:"
ip route show
echo ""

# 2. Test de connectivité locale
echo "=== 2. Tests de connectivité locale ==="
echo "Ping localhost:"
ping -c 1 127.0.0.1 >/dev/null && echo "✓ OK" || echo "✗ ÉCHEC"

# Trouver la gateway
GATEWAY=$(ip route | grep default | awk '{print $3}' | head -1)
if [ ! -z "$GATEWAY" ]; then
    echo "Ping gateway ($GATEWAY):"
    ping -c 2 $GATEWAY >/dev/null && echo "✓ OK" || echo "✗ ÉCHEC"
else
    echo "✗ Pas de gateway par défaut"
fi
echo ""

# 3. Tests spécifiques selon le type de machine
if [[ "$HOSTNAME" == "client1" ]]; then
    echo "=== 3. Tests Client1 → autres machines ==="
    
    # Test ARP pour voir si on peut résoudre les adresses
    echo "Test ARP vers gateway (10.0.2.1):"
    arping -c 2 -I $(ip route get 10.0.2.1 | grep dev | awk '{print $3}') 10.0.2.1 2>/dev/null && echo "✓ ARP OK" || echo "✗ ARP ÉCHEC"
    
    echo "Ping 10.0.2.1 (Router1):"
    ping -c 2 10.0.2.1 >/dev/null && echo "✓ OK" || echo "✗ ÉCHEC"
    
    echo "Ping 10.0.1.1 (Router1 SDN):"
    ping -c 2 10.0.1.1 >/dev/null && echo "✓ OK" || echo "✗ ÉCHEC"
    
    echo "Ping 10.0.1.2 (Router2 SDN):"
    ping -c 2 10.0.1.2 >/dev/null && echo "✓ OK" || echo "✗ ÉCHEC"
    
    echo "Ping 10.0.3.1 (Router2):"
    ping -c 2 10.0.3.1 >/dev/null && echo "✓ OK" || echo "✗ ÉCHEC"
    
    echo "Ping 10.0.3.10 (Client2):"
    ping -c 3 10.0.3.10 >/dev/null && echo "✓ OK" || echo "✗ ÉCHEC"
    
elif [[ "$HOSTNAME" == "client2" ]]; then
    echo "=== 3. Tests Client2 → autres machines ==="
    
    # Test ARP pour voir si on peut résoudre les adresses
    echo "Test ARP vers gateway (10.0.3.1):"
    arping -c 2 -I $(ip route get 10.0.3.1 2>/dev/null | grep dev | awk '{print $3}') 10.0.3.1 2>/dev/null && echo "✓ ARP OK" || echo "✗ ARP ÉCHEC"
    
    echo "Ping 10.0.3.1 (Router2):"
    ping -c 2 10.0.3.1 >/dev/null && echo "✓ OK" || echo "✗ ÉCHEC"
    
    echo "Ping 10.0.1.2 (Router2 SDN):"
    ping -c 2 10.0.1.2 >/dev/null && echo "✓ OK" || echo "✗ ÉCHEC"
    
    echo "Ping 10.0.1.1 (Router1 SDN):"
    ping -c 2 10.0.1.1 >/dev/null && echo "✓ OK" || echo "✗ ÉCHEC"
    
    echo "Ping 10.0.2.1 (Router1):"
    ping -c 2 10.0.2.1 >/dev/null && echo "✓ OK" || echo "✗ ÉCHEC"
    
    echo "Ping 10.0.2.10 (Client1):"
    ping -c 3 10.0.2.10 >/dev/null && echo "✓ OK" || echo "✗ ÉCHEC"
fi

# 4. Vérification des services
echo ""
echo "=== 4. Services réseau ==="
if command -v systemctl >/dev/null; then
    if [[ "$HOSTNAME" == "router"* ]]; then
        echo "FRR: $(systemctl is-active frr 2>/dev/null || echo 'non installé')"
        echo "OVS: $(systemctl is-active openvswitch-switch 2>/dev/null || echo 'non installé')"
    elif [[ "$HOSTNAME" == "client"* ]]; then
        echo "Apache: $(systemctl is-active apache2 2>/dev/null || echo 'non installé')"
    fi
fi

# 5. Table ARP
echo ""
echo "=== 5. Table ARP ==="
ip neigh show | grep -v "FAILED"

echo ""
echo "=== Diagnostic terminé ==="

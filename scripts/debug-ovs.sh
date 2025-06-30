#!/bin/bash

echo "=== Diagnostic Open vSwitch ==="

HOSTNAME=$(hostname)
echo "Machine: $HOSTNAME"
echo "Date: $(date)"
echo ""

# 1. Vérifier le service OVS
echo "=== 1. Service Open vSwitch ==="
systemctl status openvswitch-switch --no-pager
echo ""

# 2. Lister les bridges
echo "=== 2. Bridges OVS ==="
ovs-vsctl list-br
echo ""

# 3. Configuration détaillée
echo "=== 3. Configuration OVS ==="
ovs-vsctl show
echo ""

# 4. Vérifier les contrôleurs
echo "=== 4. Contrôleurs configurés ==="
for bridge in $(ovs-vsctl list-br); do
    echo "Bridge $bridge:"
    ovs-vsctl get-controller $bridge 2>/dev/null || echo "  Pas de contrôleur configuré"
done
echo ""

# 5. Vérifier les flows
echo "=== 5. Flows OpenFlow ==="
for bridge in $(ovs-vsctl list-br); do
    echo "Flows sur $bridge:"
    ovs-ofctl dump-flows $bridge 2>/dev/null || echo "  Impossible de lire les flows"
    echo ""
done

# 6. Vérifier les ports
echo "=== 6. Ports des bridges ==="
for bridge in $(ovs-vsctl list-br); do
    echo "Ports sur $bridge:"
    ovs-vsctl list-ports $bridge 2>/dev/null || echo "  Pas de ports"
    echo ""
done

# 7. Test de connectivité vers le contrôleur
echo "=== 7. Connectivité vers le contrôleur ==="
echo "Ping vers 10.0.1.10:"
ping -c 3 10.0.1.10 && echo "✓ Contrôleur accessible" || echo "✗ Contrôleur inaccessible"

echo "Test port OpenFlow (6633):"
nc -zv 10.0.1.10 6633 2>&1 && echo "✓ Port OpenFlow accessible" || echo "✗ Port OpenFlow inaccessible"
echo ""

# 8. Logs OVS
echo "=== 8. Logs récents OVS ==="
journalctl -u openvswitch-switch --no-pager -n 10
echo ""

# 9. Processus OVS
echo "=== 9. Processus OVS ==="
ps aux | grep ovs | grep -v grep
echo ""

echo "=== Diagnostic terminé ==="

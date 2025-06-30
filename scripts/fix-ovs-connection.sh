#!/bin/bash

echo "=== Script de correction OVS ==="

HOSTNAME=$(hostname)
echo "Correction pour: $HOSTNAME"

# Redémarrer OVS
echo "1. Redémarrage d'Open vSwitch..."
systemctl restart openvswitch-switch
sleep 5

# Vérifier que OVS fonctionne
if ! systemctl is-active openvswitch-switch >/dev/null; then
    echo "ERREUR: OVS ne démarre pas"
    systemctl status openvswitch-switch --no-pager
    exit 1
fi

# Détecter les interfaces
INTERFACES=($(ip link show | grep -E '^[0-9]+: (eth|enp|ens)' | cut -d: -f2 | tr -d ' '))
if [ ${#INTERFACES[@]} -lt 3 ]; then
    echo "ERREUR: Pas assez d'interfaces"
    exit 1
fi

NAT_IFACE=${INTERFACES[0]}
SDN_IFACE=${INTERFACES[1]}
CLIENT_IFACE=${INTERFACES[2]}

echo "Interfaces: NAT=$NAT_IFACE, SDN=$SDN_IFACE, CLIENT=$CLIENT_IFACE"

# Supprimer et recréer les bridges
echo "2. Recréation des bridges OVS..."
ovs-vsctl --if-exists del-br br0
ovs-vsctl --if-exists del-br br-sdn

# Attendre un peu
sleep 2

# Créer les nouveaux bridges
ovs-vsctl add-br br-sdn
ovs-vsctl add-br br0

# Configurer les bridges
ovs-vsctl set bridge br-sdn datapath_type=system
ovs-vsctl set bridge br0 datapath_type=system

# Connecter au contrôleur
echo "3. Connexion au contrôleur SDN..."
ovs-vsctl set-controller br-sdn tcp:10.0.1.10:6633
ovs-vsctl set-controller br0 tcp:10.0.1.10:6633

# Configurer le mode fail
ovs-vsctl set bridge br-sdn fail_mode=secure
ovs-vsctl set bridge br0 fail_mode=secure

# Ajouter les ports
echo "4. Ajout des ports aux bridges..."
ovs-vsctl add-port br-sdn $SDN_IFACE
ovs-vsctl add-port br0 $CLIENT_IFACE

# Configurer les adresses IP sur les bridges
if [ "$HOSTNAME" = "router1" ]; then
    echo "Configuration Router1..."
    ip addr add 10.0.1.1/24 dev br-sdn 2>/dev/null || true
    ip addr add 10.0.2.1/24 dev br0 2>/dev/null || true
    ip link set br-sdn up
    ip link set br0 up
    
elif [ "$HOSTNAME" = "router2" ]; then
    echo "Configuration Router2..."
    ip addr add 10.0.1.2/24 dev br-sdn 2>/dev/null || true
    ip addr add 10.0.3.1/24 dev br0 2>/dev/null || true
    ip link set br-sdn up
    ip link set br0 up
fi

# Attendre que tout soit configuré
sleep 5

# Vérifications
echo "5. Vérifications..."
echo "Bridges créés:"
ovs-vsctl list-br

echo "Configuration OVS:"
ovs-vsctl show

echo "Test des flows:"
for bridge in $(ovs-vsctl list-br); do
    echo "Flows sur $bridge:"
    ovs-ofctl dump-flows $bridge 2>/dev/null || echo "  Erreur lecture flows"
done

echo "Test connectivité contrôleur:"
ping -c 2 10.0.1.10 && echo "✓ OK" || echo "✗ ÉCHEC"

echo "=== Correction terminée ==="

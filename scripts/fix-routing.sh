#!/bin/bash

echo "=== Script de correction du routage ==="

# Vérifier sur quel type de machine on est
HOSTNAME=$(hostname)
echo "Machine: $HOSTNAME"

if [[ "$HOSTNAME" == "router"* ]]; then
    echo "=== Correction routage sur $HOSTNAME ==="
    
    # Vérifier les interfaces
    echo "Interfaces disponibles:"
    ip link show | grep -E '^[0-9]+:'
    
    # Vérifier les routes OSPF
    echo "Routes OSPF:"
    vtysh -c "show ip route ospf" 2>/dev/null || echo "OSPF non disponible"
    
    # Vérifier les voisins OSPF
    echo "Voisins OSPF:"
    vtysh -c "show ip ospf neighbor" 2>/dev/null || echo "Pas de voisins OSPF"
    
    # Redémarrer FRR
    echo "Redémarrage de FRR..."
    systemctl restart frr
    sleep 5
    
    # Ajouter les routes statiques manuellement
    if [ "$HOSTNAME" = "router1" ]; then
        echo "Ajout route statique vers réseau Client2..."
        ip route add 10.0.3.0/24 via 10.0.1.2 2>/dev/null || echo "Route déjà présente"
    elif [ "$HOSTNAME" = "router2" ]; then
        echo "Ajout route statique vers réseau Client1..."
        ip route add 10.0.2.0/24 via 10.0.1.1 2>/dev/null || echo "Route déjà présente"
    fi
    
elif [[ "$HOSTNAME" == "client"* ]]; then
    echo "=== Correction routage sur $HOSTNAME ==="
    
    # Exécuter le script de configuration réseau
    if [ -f /opt/network-config/configure-network.sh ]; then
        echo "Exécution du script de configuration réseau..."
        /opt/network-config/configure-network.sh
    else
        echo "Script de configuration non trouvé"
    fi
    
elif [[ "$HOSTNAME" == "sdn-controller" ]]; then
    echo "=== Vérification contrôleur SDN ==="
    
    # Vérifier les services
    systemctl status ryu --no-pager -l
    systemctl status prometheus --no-pager -l
    systemctl status grafana-server --no-pager -l
    
    # Vérifier les ports
    echo "Ports en écoute:"
    netstat -tlnp | grep -E ':(3000|8080|9090|6633)'
fi

# Afficher la configuration finale
echo "=== Configuration réseau finale ==="
ip addr show | grep -E "(inet |^[0-9]+:)" | grep -v "127.0.0.1"
echo ""
echo "=== Table de routage ==="
ip route show

echo "=== Correction terminée ==="

#!/bin/bash

echo "=== Nettoyage des services ==="

# Arrêter tous les services qui pourraient causer des conflits
echo "Arrêt des services..."

systemctl stop node_exporter 2>/dev/null || true
systemctl stop frr 2>/dev/null || true
systemctl stop quagga 2>/dev/null || true
systemctl stop openvswitch-switch 2>/dev/null || true

# Attendre que les processus se terminent
sleep 5

# Tuer les processus récalcitrants
pkill -f node_exporter 2>/dev/null || true
pkill -f frr 2>/dev/null || true
pkill -f ospfd 2>/dev/null || true
pkill -f zebra 2>/dev/null || true

# Nettoyer les fichiers temporaires
rm -f /tmp/node_exporter-*.tar.gz
rm -f /tmp/prometheus-*.tar.gz

# Supprimer les bridges OVS existants
ovs-vsctl --if-exists del-br br0
ovs-vsctl --if-exists del-br br-sdn

echo "Nettoyage terminé"

# Redémarrer OVS proprement
systemctl start openvswitch-switch
sleep 3

echo "Services nettoyés et prêts pour réinstallation"

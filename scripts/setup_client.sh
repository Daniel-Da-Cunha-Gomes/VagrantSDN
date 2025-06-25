#!/bin/bash

# Mise à jour & installation des utilitaires
apt-get update && apt-get install -y iputils-ping curl

# Supprimer ancienne route par défaut si elle existe
ip route del default || true

# Définir la bonne passerelle selon le nom d'hôte
case "$(hostname)" in
  clientA)
    ip route add default via 192.168.20.1
    ;;
  clientB)
    ip route add default via 192.168.30.1
    ;;
esac

# (Optionnel) Test réseau vers le routeur
ping -c 2 192.168.20.1 || ping -c 2 192.168.30.1 || echo "Ping failed"

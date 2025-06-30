#!/bin/bash

set -e

echo "=== Installation du routeur (FRRouting + OVS) ==="

# Mise à jour du système
apt-get update
apt-get upgrade -y

# Installation des dépendances
apt-get install -y \
    curl \
    wget \
    gnupg \
    lsb-release \
    openvswitch-switch \
    openvswitch-common \
    net-tools \
    tcpdump \
    iperf3 \
    traceroute \
    iproute2 \
    ufw

# Désactiver le firewall
ufw --force disable

# Installation de Node Exporter avec gestion des erreurs
echo "=== Installation Node Exporter ==="

# Arrêter le service s'il existe déjà
systemctl stop node_exporter 2>/dev/null || true

# Vérifier si node_exporter existe déjà
if [ -f /usr/local/bin/node_exporter ]; then
    echo "Node Exporter déjà installé, vérification de la version..."
    /usr/local/bin/node_exporter --version || echo "Version non détectable"
else
    echo "Installation de Node Exporter..."
    
    cd /tmp
    # Nettoyer les téléchargements précédents
    rm -f node_exporter-*.tar.gz
    
    # Télécharger avec retry
    for i in {1..3}; do
        if wget -q https://github.com/prometheus/node_exporter/releases/download/v1.6.0/node_exporter-1.6.0.linux-amd64.tar.gz; then
            break
        else
            echo "Tentative $i échouée, retry..."
            sleep 5
        fi
    done
    
    if [ ! -f node_exporter-1.6.0.linux-amd64.tar.gz ]; then
        echo "ERREUR: Impossible de télécharger Node Exporter"
        echo "Installation via package manager..."
        apt-get install -y prometheus-node-exporter || true
    else
        tar xf node_exporter-1.6.0.linux-amd64.tar.gz
        cp node_exporter-1.6.0.linux-amd64/node_exporter /usr/local/bin/
        chmod +x /usr/local/bin/node_exporter
    fi
fi

# Créer l'utilisateur node_exporter
useradd --no-create-home --shell /bin/false node_exporter 2>/dev/null || true

# Service Node Exporter
cat > /etc/systemd/system/node_exporter.service << 'EOF'
[Unit]
Description=Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter --web.listen-address=0.0.0.0:9100
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Afficher les interfaces disponibles
echo "=== Interfaces réseau disponibles ==="
ip link show

# Détecter les interfaces réseau
INTERFACES=($(ip link show | grep -E '^[0-9]+: (eth|enp|ens)' | cut -d: -f2 | tr -d ' '))
echo "Interfaces détectées: ${INTERFACES[@]}"

if [ ${#INTERFACES[@]} -lt 3 ]; then
    echo "ERREUR: Pas assez d'interfaces réseau détectées (${#INTERFACES[@]})"
    exit 1
fi

NAT_IFACE=${INTERFACES[0]}
SDN_IFACE=${INTERFACES[1]}
CLIENT_IFACE=${INTERFACES[2]}

echo "Interface NAT: $NAT_IFACE"
echo "Interface SDN: $SDN_IFACE"
echo "Interface Client: $CLIENT_IFACE"

# Installation de FRRouting avec gestion d'erreurs robuste
echo "=== Installation FRRouting ==="

# Nettoyer les installations précédentes qui pourraient poser problème
apt-get remove --purge -y frr frr-* quagga quagga-* 2>/dev/null || true
apt-get autoremove -y 2>/dev/null || true

# Méthode 1: Installation via packages Ubuntu (plus fiable)
echo "Tentative 1: Installation FRR via packages Ubuntu..."
apt-get update
if apt-get install -y frr frr-pythontools; then
    echo "✓ FRR installé via packages Ubuntu"
else
    echo "Échec installation standard, tentative alternative..."
    
    # Méthode 2: Via PPA Ubuntu
    echo "Tentative 2: Installation via PPA..."
    apt-get install -y software-properties-common
    add-apt-repository -y ppa:frrouting/frrouting 2>/dev/null || true
    apt-get update
    apt-get install -y frr frr-pythontools 2>/dev/null || {
        
        # Méthode 3: Repository officiel FRRouting
        echo "Tentative 3: Repository officiel FRRouting..."
        
        # Nettoyer les anciennes clés et repos
        rm -f /usr/share/keyrings/frrouting.gpg 2>/dev/null || true
        rm -f /etc/apt/sources.list.d/frr.list 2>/dev/null || true
        
        # Ajouter la clé GPG avec plusieurs méthodes
        if curl -s https://deb.frrouting.org/frr/keys.asc | gpg --dearmor | tee /usr/share/keyrings/frrouting.gpg > /dev/null 2>&1; then
            echo "✓ Clé GPG ajoutée"
            echo "deb [signed-by=/usr/share/keyrings/frrouting.gpg] https://deb.frrouting.org/frr $(lsb_release -s -c) frr-stable" > /etc/apt/sources.list.d/frr.list
        else
            echo "Méthode GPG alternative..."
            curl -s https://deb.frrouting.org/frr/keys.asc | apt-key add - 2>/dev/null || true
            echo "deb https://deb.frrouting.org/frr $(lsb_release -s -c) frr-stable" > /etc/apt/sources.list.d/frr.list
        fi
        
        apt-get update 2>/dev/null || true
        apt-get install -y frr frr-pythontools 2>/dev/null || {
            echo "Toutes les méthodes FRR ont échoué, installation de Quagga..."
            apt-get install -y quagga
        }
    }
fi

# Vérification que vtysh fonctionne
echo "=== Vérification installation FRR ==="
if command -v vtysh >/dev/null 2>&1; then
    echo "✓ vtysh trouvé: $(which vtysh)"
    if vtysh -c "show version" >/dev/null 2>&1; then
        echo "✓ FRR fonctionne correctement"
        vtysh -c "show version" | head -3
    else
        echo "⚠ vtysh trouvé mais ne répond pas, configuration des services..."
        systemctl enable frr 2>/dev/null || systemctl enable quagga 2>/dev/null || true
        systemctl start frr 2>/dev/null || systemctl start quagga 2>/dev/null || true
        sleep 3
    fi
else
    echo "✗ vtysh non trouvé après installation"
    echo "Packages installés:"
    dpkg -l | grep -E "(frr|quagga)" || echo "Aucun package de routage trouvé"
    
    # Dernière tentative: installation manuelle de vtysh
    if [ -f /usr/bin/vtysh ]; then
        ln -sf /usr/bin/vtysh /usr/local/bin/vtysh 2>/dev/null || true
    elif [ -f /usr/sbin/vtysh ]; then
        ln -sf /usr/sbin/vtysh /usr/local/bin/vtysh 2>/dev/null || true
    fi
fi

# Configuration Open vSwitch
echo "=== Configuration Open vSwitch ==="
systemctl enable openvswitch-switch
systemctl start openvswitch-switch

# Attendre que OVS soit complètement démarré
sleep 5

# Vérifier que OVS fonctionne
if ! systemctl is-active openvswitch-switch >/dev/null; then
    echo "ERREUR: Open vSwitch ne démarre pas"
    systemctl status openvswitch-switch --no-pager
    exit 1
fi

echo "=== Vérification OVS ==="
ovs-vsctl show

# Configuration selon le hostname
HOSTNAME=$(hostname)

# Fonction pour configurer OVS
configure_ovs() {
    local hostname=$1
    local sdn_ip=$2
    local client_ip=$3
    
    echo "Configuration OVS pour $hostname..."
    
    # Supprimer les bridges existants s'ils existent
    ovs-vsctl --if-exists del-br br0
    ovs-vsctl --if-exists del-br br-sdn
    
    sleep 2
    
    # Créer les nouveaux bridges
    ovs-vsctl add-br br-sdn
    ovs-vsctl add-br br0
    
    # Configurer les bridges
    ovs-vsctl set bridge br-sdn datapath_type=system
    ovs-vsctl set bridge br0 datapath_type=system
    
    # Attendre que les bridges soient créés
    sleep 2
    
    # Connecter au contrôleur avec retry
    for i in {1..3}; do
        if ovs-vsctl set-controller br-sdn tcp:10.0.1.10:6633 && ovs-vsctl set-controller br0 tcp:10.0.1.10:6633; then
            echo "✓ Contrôleur configuré"
            break
        else
            echo "Tentative $i de connexion au contrôleur..."
            sleep 5
        fi
    done
    
    # Configurer le mode fail
    ovs-vsctl set bridge br-sdn fail_mode=standalone
    ovs-vsctl set bridge br0 fail_mode=standalone
    
    # Ajouter les ports
    ovs-vsctl add-port br-sdn $SDN_IFACE 2>/dev/null || echo "Port SDN déjà ajouté"
    ovs-vsctl add-port br0 $CLIENT_IFACE 2>/dev/null || echo "Port client déjà ajouté"
    
    # Configurer les adresses IP
    ip addr add $sdn_ip/24 dev br-sdn 2>/dev/null || true
    ip addr add $client_ip/24 dev br0 2>/dev/null || true
    ip link set br-sdn up
    ip link set br0 up
}

if [ "$HOSTNAME" = "router1" ]; then
    echo "=== Configuration Router1 ==="
    
    # Configuration des interfaces IP d'abord
    ip addr flush dev $SDN_IFACE 2>/dev/null || true
    ip addr flush dev $CLIENT_IFACE 2>/dev/null || true
    
    ip addr add 10.0.1.1/24 dev $SDN_IFACE
    ip addr add 10.0.2.1/24 dev $CLIENT_IFACE
    ip link set $SDN_IFACE up
    ip link set $CLIENT_IFACE up
    
    sleep 3
    
    # Configuration OVS
    configure_ovs "router1" "10.0.1.1" "10.0.2.1"
    
    # Configuration FRR avec vérification
    echo "=== Configuration FRR ==="

    # Vérifier que FRR est disponible avant de configurer
    if command -v vtysh >/dev/null 2>&1; then
        echo "Configuration avec FRR/vtysh..."
        
        # Activer les démons nécessaires
        if [ -f /etc/frr/daemons ]; then
            echo "Activation des démons FRR..."
            sed -i 's/zebra=no/zebra=yes/' /etc/frr/daemons
            sed -i 's/ospfd=no/ospfd=yes/' /etc/frr/daemons
            sed -i 's/bgpd=no/bgpd=no/' /etc/frr/daemons
            sed -i 's/ripd=no/ripd=no/' /etc/frr/daemons
        elif [ -f /etc/quagga/daemons ]; then
            echo "Configuration Quagga..."
            sed -i 's/zebra=no/zebra=yes/' /etc/quagga/daemons
            sed -i 's/ospfd=no/ospfd=yes/' /etc/quagga/daemons
        fi
        
        # Créer la configuration selon le routeur
        CONFIG_FILE="/etc/frr/frr.conf"
        [ ! -f "$CONFIG_FILE" ] && CONFIG_FILE="/etc/quagga/Quagga.conf"
        
        if [ "$HOSTNAME" = "router1" ]; then
            echo "Configuration Router1..."
            cat > "$CONFIG_FILE" << EOF
!
! FRRouting configuration file - Router 1
!
frr version 8.1
frr defaults traditional
hostname router1
log syslog informational
no ipv6 forwarding
service integrated-vtysh-config
!
! Interface configuration
interface $SDN_IFACE
 ip address 10.0.1.1/24
 ip ospf area 0.0.0.0
!
interface $CLIENT_IFACE
 ip address 10.0.2.1/24
 ip ospf area 0.0.0.0
!
! OSPF configuration
router ospf
 ospf router-id 1.1.1.1
 network 10.0.1.0/24 area 0.0.0.0
 network 10.0.2.0/24 area 0.0.0.0
 passive-interface $CLIENT_IFACE
!
! Routes statiques
ip route 10.0.3.0/24 10.0.1.2
!
line vty
!
EOF
            
        elif [ "$HOSTNAME" = "router2" ]; then
            echo "Configuration Router2..."
            cat > "$CONFIG_FILE" << EOF
!
! FRRouting configuration file - Router 2
!
frr version 8.1
frr defaults traditional
hostname router2
log syslog informational
no ipv6 forwarding
service integrated-vtysh-config
!
! Interface configuration
interface $SDN_IFACE
 ip address 10.0.1.2/24
 ip ospf area 0.0.0.0
!
interface $CLIENT_IFACE
 ip address 10.0.3.1/24
 ip ospf area 0.0.0.0
!
! OSPF configuration
router ospf
 ospf router-id 2.2.2.2
 network 10.0.1.0/24 area 0.0.0.0
 network 10.0.3.0/24 area 0.0.0.0
 passive-interface $CLIENT_IFACE
!
! Routes statiques
ip route 10.0.2.0/24 10.0.1.1
!
line vty
!
EOF
        fi
        
        # Permissions sur le fichier de config
        chown frr:frr "$CONFIG_FILE" 2>/dev/null || chown quagga:quagga "$CONFIG_FILE" 2>/dev/null || true
        chmod 640 "$CONFIG_FILE"
        
        echo "✓ Configuration FRR créée: $CONFIG_FILE"
        
    else
        echo "⚠ FRR non disponible, utilisation du routage système uniquement"
        echo "Routes statiques seront ajoutées manuellement"
    fi

elif [ "$HOSTNAME" = "router2" ]; then
    echo "=== Configuration Router2 ==="
    
    # Configuration des interfaces IP d'abord
    ip addr flush dev $SDN_IFACE 2>/dev/null || true
    ip addr flush dev $CLIENT_IFACE 2>/dev/null || true
    
    ip addr add 10.0.1.2/24 dev $SDN_IFACE
    ip addr add 10.0.3.1/24 dev $CLIENT_IFACE
    ip link set $SDN_IFACE up
    ip link set $CLIENT_IFACE up
    
    sleep 3
    
    # Configuration OVS
    configure_ovs "router2" "10.0.1.2" "10.0.3.1"
    
    # Configuration FRR avec vérification
    echo "=== Configuration FRR ==="

    # Vérifier que FRR est disponible avant de configurer
    if command -v vtysh >/dev/null 2>&1; then
        echo "Configuration avec FRR/vtysh..."
        
        # Activer les démons nécessaires
        if [ -f /etc/frr/daemons ]; then
            echo "Activation des démons FRR..."
            sed -i 's/zebra=no/zebra=yes/' /etc/frr/daemons
            sed -i 's/ospfd=no/ospfd=yes/' /etc/frr/daemons
            sed -i 's/bgpd=no/bgpd=no/' /etc/frr/daemons
            sed -i 's/ripd=no/ripd=no/' /etc/frr/daemons
        elif [ -f /etc/quagga/daemons ]; then
            echo "Configuration Quagga..."
            sed -i 's/zebra=no/zebra=yes/' /etc/quagga/daemons
            sed -i 's/ospfd=no/ospfd=yes/' /etc/quagga/daemons
        fi
        
        # Créer la configuration selon le routeur
        CONFIG_FILE="/etc/frr/frr.conf"
        [ ! -f "$CONFIG_FILE" ] && CONFIG_FILE="/etc/quagga/Quagga.conf"
        
        if [ "$HOSTNAME" = "router1" ]; then
            echo "Configuration Router1..."
            cat > "$CONFIG_FILE" << EOF
!
! FRRouting configuration file - Router 1
!
frr version 8.1
frr defaults traditional
hostname router1
log syslog informational
no ipv6 forwarding
service integrated-vtysh-config
!
! Interface configuration
interface $SDN_IFACE
 ip address 10.0.1.1/24
 ip ospf area 0.0.0.0
!
interface $CLIENT_IFACE
 ip address 10.0.2.1/24
 ip ospf area 0.0.0.0
!
! OSPF configuration
router ospf
 ospf router-id 1.1.1.1
 network 10.0.1.0/24 area 0.0.0.0
 network 10.0.2.0/24 area 0.0.0.0
 passive-interface $CLIENT_IFACE
!
! Routes statiques
ip route 10.0.3.0/24 10.0.1.2
!
line vty
!
EOF
            
        elif [ "$HOSTNAME" = "router2" ]; then
            echo "Configuration Router2..."
            cat > "$CONFIG_FILE" << EOF
!
! FRRouting configuration file - Router 2
!
frr version 8.1
frr defaults traditional
hostname router2
log syslog informational
no ipv6 forwarding
service integrated-vtysh-config
!
! Interface configuration
interface $SDN_IFACE
 ip address 10.0.1.2/24
 ip ospf area 0.0.0.0
!
interface $CLIENT_IFACE
 ip address 10.0.3.1/24
 ip ospf area 0.0.0.0
!
! OSPF configuration
router ospf
 ospf router-id 2.2.2.2
 network 10.0.1.0/24 area 0.0.0.0
 network 10.0.3.0/24 area 0.0.0.0
 passive-interface $CLIENT_IFACE
!
! Routes statiques
ip route 10.0.2.0/24 10.0.1.1
!
line vty
!
EOF
        fi
        
        # Permissions sur le fichier de config
        chown frr:frr "$CONFIG_FILE" 2>/dev/null || chown quagga:quagga "$CONFIG_FILE" 2>/dev/null || true
        chmod 640 "$CONFIG_FILE"
        
        echo "✓ Configuration FRR créée: $CONFIG_FILE"
        
    else
        echo "⚠ FRR non disponible, utilisation du routage système uniquement"
        echo "Routes statiques seront ajoutées manuellement"
    fi
fi

# Configuration FRR
if [ -f /etc/frr/frr.conf ]; then
    chown frr:frr /etc/frr/frr.conf 2>/dev/null || chown quagga:quagga /etc/frr/frr.conf 2>/dev/null || true
    chmod 640 /etc/frr/frr.conf
fi

# Activation des démons FRR
if [ -f /etc/frr/daemons ]; then
    sed -i 's/ospfd=no/ospfd=yes/' /etc/frr/daemons
    sed -i 's/zebra=no/zebra=yes/' /etc/frr/daemons
fi

# Activation et démarrage des services avec vérifications
systemctl daemon-reload
systemctl enable node_exporter 2>/dev/null || true

# Démarrage FRR avec fallback
if command -v vtysh >/dev/null 2>&1; then
    systemctl enable frr 2>/dev/null || systemctl enable quagga 2>/dev/null || true
    systemctl start frr 2>/dev/null || systemctl start quagga 2>/dev/null || true
    sleep 5
    systemctl restart frr 2>/dev/null || systemctl restart quagga 2>/dev/null || true
    sleep 5
    
    # Test final de FRR
    if vtysh -c "show version" >/dev/null 2>&1; then
        echo "✓ FRR opérationnel"
        echo "Version FRR:"
        vtysh -c "show version" | head -2
    else
        echo "⚠ FRR installé mais ne répond pas, utilisation du routage système"
    fi
else
    echo "⚠ Pas de FRR, routage système uniquement"
fi

systemctl start node_exporter 2>/dev/null || echo "Node exporter start failed"

sleep 10

# Redémarrage FRR pour prendre en compte la config
systemctl restart frr 2>/dev/null || systemctl restart quagga 2>/dev/null || true
sleep 5

# Ajouter les routes statiques manuellement
if [ "$HOSTNAME" = "router1" ]; then
    ip route add 10.0.3.0/24 via 10.0.1.2 2>/dev/null || true
elif [ "$HOSTNAME" = "router2" ]; then
    ip route add 10.0.2.0/24 via 10.0.1.1 2>/dev/null || true
fi

# Vérifications finales
echo "=== Vérifications finales ==="

# Vérifier OVS
echo "Configuration OVS:"
ovs-vsctl show

echo "Bridges OVS:"
ovs-vsctl list-br

echo "Test connectivité contrôleur:"
ping -c 2 10.0.1.10 && echo "✓ Contrôleur accessible" || echo "✗ Contrôleur inaccessible"

# Vérifier le statut des services
echo "=== Statut des services ==="
systemctl is-active openvswitch-switch && echo "✓ OVS actif" || echo "✗ OVS inactif"
systemctl is-active frr && echo "✓ FRR actif" || systemctl is-active quagga && echo "✓ Quagga actif" || echo "✗ Routage inactif"
systemctl is-active node_exporter && echo "✓ Node Exporter actif" || echo "✗ Node Exporter inactif"

echo "=== Installation terminée ==="

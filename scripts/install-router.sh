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

# Installation de Node Exporter
cd /tmp
wget -q https://github.com/prometheus/node_exporter/releases/download/v1.6.0/node_exporter-1.6.0.linux-amd64.tar.gz
tar xf node_exporter-1.6.0.linux-amd64.tar.gz
cp node_exporter-1.6.0.linux-amd64/node_exporter /usr/local/bin/
useradd --no-create-home --shell /bin/false node_exporter || true

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

# Installation de FRRouting
curl -s https://deb.frrouting.org/frr/keys.asc | apt-key add -
echo deb https://deb.frrouting.org/frr $(lsb_release -s -c) frr-stable | tee -a /etc/apt/sources.list.d/frr.list
apt-get update
apt-get install -y frr frr-pythontools

# Activation du routage IP
echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
sysctl -p

# Configuration Open vSwitch
systemctl enable openvswitch-switch
systemctl start openvswitch-switch
sleep 3

# Configuration selon le hostname
HOSTNAME=$(hostname)

if [ "$HOSTNAME" = "router1" ]; then
    echo "=== Configuration Router1 ==="
    
    ip addr flush dev $SDN_IFACE
    ip addr flush dev $CLIENT_IFACE
    
    ip addr add 10.0.1.1/24 dev $SDN_IFACE
    ip addr add 10.0.2.1/24 dev $CLIENT_IFACE
    ip link set $SDN_IFACE up
    ip link set $CLIENT_IFACE up
    
    # Configuration FRR
    cat > /etc/frr/frr.conf << EOF
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
    echo "=== Configuration Router2 ==="
    
    ip addr flush dev $SDN_IFACE
    ip addr flush dev $CLIENT_IFACE
    
    ip addr add 10.0.1.2/24 dev $SDN_IFACE
    ip addr add 10.0.3.1/24 dev $CLIENT_IFACE
    ip link set $SDN_IFACE up
    ip link set $CLIENT_IFACE up
    
    # Configuration FRR
    cat > /etc/frr/frr.conf << EOF
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

chown frr:frr /etc/frr/frr.conf
chmod 640 /etc/frr/frr.conf

# Activation des démons FRR
sed -i 's/ospfd=no/ospfd=yes/' /etc/frr/daemons
sed -i 's/zebra=no/zebra=yes/' /etc/frr/daemons

# Activation des services
systemctl daemon-reload
systemctl enable node_exporter
systemctl enable frr

# Démarrage des services
systemctl start node_exporter
systemctl start frr
sleep 10
systemctl restart frr
sleep 5

# Ajouter les routes statiques manuellement
if [ "$HOSTNAME" = "router1" ]; then
    ip route add 10.0.3.0/24 via 10.0.1.2 || true
elif [ "$HOSTNAME" = "router2" ]; then
    ip route add 10.0.2.0/24 via 10.0.1.1 || true
fi

# Vérifier le statut des services
echo "=== Statut des services ==="
systemctl is-active openvswitch-switch && echo "✓ OVS actif" || echo "✗ OVS inactif"
systemctl is-active frr && echo "✓ FRR actif" || echo "✗ FRR inactif"
systemctl is-active node_exporter && echo "✓ Node Exporter actif" || echo "✗ Node Exporter inactif"

echo "=== Installation terminée ==="

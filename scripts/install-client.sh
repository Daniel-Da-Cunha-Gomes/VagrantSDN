#!/bin/bash

set -e

echo "=== Installation du client ==="

# Mise à jour du système
apt-get update
apt-get upgrade -y

# Installation des outils réseau
apt-get install -y \
    net-tools \
    tcpdump \
    iperf3 \
    traceroute \
    curl \
    wget \
    apache2 \
    python3 \
    python3-pip \
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

# Installation d'Apache Exporter
cd /tmp
wget -q https://github.com/Lusitaniae/apache_exporter/releases/download/v0.13.0/apache_exporter-0.13.0.linux-amd64.tar.gz
tar xf apache_exporter-0.13.0.linux-amd64.tar.gz
cp apache_exporter-0.13.0.linux-amd64/apache_exporter /usr/local/bin/
useradd --no-create-home --shell /bin/false apache_exporter || true

# Configuration Apache pour les métriques
a2enmod status
cat > /etc/apache2/conf-available/status.conf << 'EOF'
<Location "/server-status">
    SetHandler server-status
    Require local
    Require ip 127.0.0.1
    Require ip 192.168.100.0/24
    Require ip 10.0.0.0/8
</Location>

<Location "/server-info">
    SetHandler server-info
    Require local
    Require ip 127.0.0.1
    Require ip 192.168.100.0/24
    Require ip 10.0.0.0/8
</Location>
EOF

a2enconf status

# Service Apache Exporter
cat > /etc/systemd/system/apache_exporter.service << 'EOF'
[Unit]
Description=Apache Exporter
Wants=network-online.target
After=network-online.target apache2.service

[Service]
User=apache_exporter
Group=apache_exporter
Type=simple
ExecStart=/usr/local/bin/apache_exporter --web.listen-address=0.0.0.0:9117 --scrape_uri=http://localhost/server-status?auto

[Install]
WantedBy=multi-user.target
EOF

# Afficher les interfaces disponibles pour débogage
echo "=== Interfaces réseau disponibles ==="
ip link show
echo "=== Adresses IP actuelles ==="
ip addr show

# Détecter les interfaces réseau
INTERFACES=($(ip link show | grep -E '^[0-9]+: (eth|enp|ens)' | cut -d: -f2 | tr -d ' '))
echo "Interfaces détectées: ${INTERFACES[@]}"

if [ ${#INTERFACES[@]} -lt 2 ]; then
    echo "ERREUR: Pas assez d'interfaces réseau détectées (${#INTERFACES[@]})"
    exit 1
fi

NAT_IFACE=${INTERFACES[0]}
CLIENT_IFACE=${INTERFACES[1]}

echo "Interface NAT: $NAT_IFACE"
echo "Interface Client: $CLIENT_IFACE"

# Configuration Apache
systemctl enable apache2
systemctl start apache2

# Page web avec métriques
HOSTNAME=$(hostname)
cat > /var/www/html/index.html << EOF
<!DOCTYPE html>
<html>
<head>
    <title>$HOSTNAME - SDN Network Lab</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; background: #f5f5f5; }
        .container { max-width: 800px; margin: 0 auto; background: white; padding: 30px; border-radius: 10px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        .header { text-align: center; color: #333; border-bottom: 2px solid #007bff; padding-bottom: 20px; margin-bottom: 30px; }
        .info-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 20px; margin: 20px 0; }
        .info-card { background: #f8f9fa; padding: 15px; border-radius: 5px; border-left: 4px solid #007bff; }
        .metrics { background: #e8f5e8; padding: 15px; border-radius: 5px; margin: 20px 0; }
        .links { text-align: center; margin-top: 30px; }
        .btn { display: inline-block; background: #007bff; color: white; padding: 10px 20px; text-decoration: none; border-radius: 5px; margin: 5px; }
        .btn:hover { background: #0056b3; }
        .status { color: #28a745; font-weight: bold; }
    </style>
    <script>
        function updateTime() {
            document.getElementById('current-time').innerHTML = new Date().toLocaleString();
        }
        setInterval(updateTime, 1000);
        window.onload = updateTime;
    </script>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🖥️ $HOSTNAME</h1>
            <p class="status">✅ Service Web Actif</p>
        </div>
        
        <div class="info-grid">
            <div class="info-card">
                <h3>📊 Informations Système</h3>
                <p><strong>Hostname:</strong> $HOSTNAME</p>
                <p><strong>Interface:</strong> $CLIENT_IFACE</p>
                <p><strong>Adresse IP:</strong> $(hostname -I)</p>
                <p><strong>Heure:</strong> <span id="current-time"></span></p>
            </div>
            
            <div class="info-card">
                <h3>🌐 Configuration Réseau</h3>
                <p><strong>Interface NAT:</strong> $NAT_IFACE</p>
                <p><strong>Interface Client:</strong> $CLIENT_IFACE</p>
                <p><strong>Statut Apache:</strong> <span class="status">Actif</span></p>
                <p><strong>Node Exporter:</strong> Port 9100</p>
            </div>
        </div>
        
        <div class="metrics">
            <h3>📈 Métriques Disponibles</h3>
            <p>Ce client expose des métriques pour le monitoring :</p>
            <ul>
                <li><strong>Node Exporter:</strong> Métriques système (CPU, RAM, Réseau)</li>
                <li><strong>Apache Exporter:</strong> Métriques du serveur web</li>
                <li><strong>Statut Apache:</strong> <a href="/server-status">/server-status</a></li>
            </ul>
        </div>
        
        <div class="links">
            <h3>🔗 Liens Utiles</h3>
            <a href="/server-status" class="btn">Apache Status</a>
            <a href="http://localhost:9100/metrics" class="btn">Node Metrics</a>
            <a href="http://localhost:9117/metrics" class="btn">Apache Metrics</a>
        </div>
    </div>
</body>
</html>
EOF

# Configuration des interfaces et routes selon le client
if [ "$HOSTNAME" = "client1" ]; then
    echo "=== Configuration Client1 ==="
    
    ip route del default || true
    ip addr flush dev $CLIENT_IFACE
    ip addr add 10.0.2.10/24 dev $CLIENT_IFACE
    ip link set $CLIENT_IFACE up
    sleep 2
    
    ip route add default via 10.0.2.1 dev $CLIENT_IFACE
    ip route add 10.0.1.0/24 via 10.0.2.1 dev $CLIENT_IFACE || true
    ip route add 10.0.3.0/24 via 10.0.2.1 dev $CLIENT_IFACE || true
    
elif [ "$HOSTNAME" = "client2" ]; then
    echo "=== Configuration Client2 ==="
    
    ip route del default || true
    ip addr flush dev $CLIENT_IFACE
    ip addr add 10.0.3.10/24 dev $CLIENT_IFACE
    ip link set $CLIENT_IFACE up
    sleep 2
    
    ip route add default via 10.0.3.1 dev $CLIENT_IFACE
    ip route add 10.0.1.0/24 via 10.0.3.1 dev $CLIENT_IFACE || true
    ip route add 10.0.2.0/24 via 10.0.3.1 dev $CLIENT_IFACE || true
fi

# Script de configuration réseau persistant
mkdir -p /opt/network-config
cat > /opt/network-config/configure-network.sh << EOF
#!/bin/bash
CLIENT_IFACE=$CLIENT_IFACE
HOSTNAME=\$(hostname)

if [ "\$HOSTNAME" = "client1" ]; then
    ip route del default 2>/dev/null || true
    ip addr flush dev \$CLIENT_IFACE
    ip addr add 10.0.2.10/24 dev \$CLIENT_IFACE
    ip link set \$CLIENT_IFACE up
    sleep 2
    ip route add default via 10.0.2.1 dev \$CLIENT_IFACE
    ip route add 10.0.1.0/24 via 10.0.2.1 dev \$CLIENT_IFACE 2>/dev/null || true
    ip route add 10.0.3.0/24 via 10.0.2.1 dev \$CLIENT_IFACE 2>/dev/null || true
elif [ "\$HOSTNAME" = "client2" ]; then
    ip route del default 2>/dev/null || true
    ip addr flush dev \$CLIENT_IFACE
    ip addr add 10.0.3.10/24 dev \$CLIENT_IFACE
    ip link set \$CLIENT_IFACE up
    sleep 2
    ip route add default via 10.0.3.1 dev \$CLIENT_IFACE
    ip route add 10.0.1.0/24 via 10.0.3.1 dev \$CLIENT_IFACE 2>/dev/null || true
    ip route add 10.0.2.0/24 via 10.0.3.1 dev \$CLIENT_IFACE 2>/dev/null || true
fi
EOF

chmod +x /opt/network-config/configure-network.sh

# Service systemd pour la configuration réseau
cat > /etc/systemd/system/network-config.service << EOF
[Unit]
Description=Network Configuration for $HOSTNAME
After=network.target
Before=apache2.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/opt/network-config/configure-network.sh

[Install]
WantedBy=multi-user.target
EOF

# Activation des services
systemctl daemon-reload
systemctl enable network-config
systemctl enable node_exporter
systemctl enable apache_exporter

# Redémarrage d'Apache pour prendre en compte la config
systemctl restart apache2
systemctl start node_exporter
systemctl start apache_exporter

# Attendre que les services démarrent
sleep 5

# Vérifier le statut des services
echo "=== Statut des services ==="
systemctl is-active apache2 && echo "✓ Apache actif" || echo "✗ Apache inactif"
systemctl is-active node_exporter && echo "✓ Node Exporter actif" || echo "✗ Node Exporter inactif"
systemctl is-active apache_exporter && echo "✓ Apache Exporter actif" || echo "✗ Apache Exporter inactif"

# Afficher les ports en écoute
echo "=== Ports en écoute ==="
netstat -tlnp | grep -E ':(80|9100|9117)'

echo "=== Installation terminée ==="
echo "Métriques disponibles sur :"
echo "- Node Exporter: http://$(hostname -I | awk '{print $1}'):9100/metrics"
echo "- Apache Exporter: http://$(hostname -I | awk '{print $1}'):9117/metrics"
echo "- Apache Status: http://$(hostname -I | awk '{print $1}')/server-status"

#!/bin/bash

set -e

echo "=== Installation du contrôleur SDN (Ryu) ==="

# Mise à jour du système
apt-get update
apt-get upgrade -y

# Installation des dépendances complètes pour Ryu
apt-get install -y \
    python3 \
    python3-pip \
    python3-dev \
    python3-setuptools \
    python3-wheel \
    git \
    curl \
    wget \
    openvswitch-switch \
    openvswitch-common \
    net-tools \
    tcpdump \
    iperf3 \
    ufw \
    build-essential \
    python3-eventlet \
    python3-routes \
    python3-webob \
    python3-paramiko \
    python3-netaddr

# Désactiver le firewall pour les tests
ufw --force disable

# Activation du routage IP (nécessaire pour le contrôleur)
echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
sysctl -p

echo "=== Installation de Ryu SDN Controller ==="

# Mise à jour pip
python3 -m pip install --upgrade pip

# Installation de Ryu avec toutes ses dépendances
pip3 install ryu eventlet webob routes paramiko netaddr

# Vérifier l'installation de Ryu
if python3 -c "import ryu; print('Ryu version:', ryu.__version__)" 2>/dev/null; then
    echo "✓ Ryu installé avec succès"
else
    echo "Installation alternative de Ryu..."
    # Installation depuis les sources si pip échoue
    cd /tmp
    git clone https://github.com/faucetsdn/ryu.git
    cd ryu
    pip3 install .
fi

# Créer le répertoire pour les applications Ryu
mkdir -p /opt/ryu/apps
mkdir -p /var/log/ryu

# Application Ryu principale avec interface web
cat > /opt/ryu/apps/sdn_controller.py << 'EOF'
from ryu.base import app_manager
from ryu.controller import ofp_event
from ryu.controller.handler import CONFIG_DISPATCHER, MAIN_DISPATCHER
from ryu.controller.handler import set_ev_cls
from ryu.ofproto import ofproto_v1_3
from ryu.lib.packet import packet
from ryu.lib.packet import ethernet
from ryu.lib.packet import ether_types
from ryu.lib.packet import ipv4
from ryu.lib.packet import icmp
from ryu.lib.packet import tcp
from ryu.app.wsgi import ControllerBase, WSGIApplication, route
from webob import Response
import json
import logging

# Configuration du logging
logging.basicConfig(level=logging.INFO)

sdn_instance_name = 'sdn_api_app'
url = '/sdn'

class SDNController(app_manager.RyuApp):
    OFP_VERSIONS = [ofproto_v1_3.OFP_VERSION]
    _CONTEXTS = {'wsgi': WSGIApplication}

    def __init__(self, *args, **kwargs):
        super(SDNController, self).__init__(*args, **kwargs)
        self.mac_to_port = {}
        self.switches = {}
        self.flows = {}
        
        # Configuration de l'interface web
        wsgi = kwargs['wsgi']
        wsgi.register(SDNRestAPI, {sdn_instance_name: self})
        
        self.logger.info("SDN Controller démarré")

    @set_ev_cls(ofp_event.EventOFPSwitchFeatures, CONFIG_DISPATCHER)
    def switch_features_handler(self, ev):
        datapath = ev.msg.datapath
        ofproto = datapath.ofproto
        parser = datapath.ofproto_parser
        
        # Enregistrer le switch
        self.switches[datapath.id] = {
            'datapath': datapath,
            'ports': {},
            'connected_at': str(ev.timestamp) if hasattr(ev, 'timestamp') else 'unknown'
        }

        self.logger.info("Switch %s connecté", datapath.id)

        # Règle par défaut - envoyer au contrôleur
        match = parser.OFPMatch()
        actions = [parser.OFPActionOutput(ofproto.OFPP_CONTROLLER,
                                          ofproto.OFPCML_NO_BUFFER)]
        self.add_flow(datapath, 0, match, actions)

        # Règle pour autoriser le trafic ARP
        match = parser.OFPMatch(eth_type=ether_types.ETH_TYPE_ARP)
        actions = [parser.OFPActionOutput(ofproto.OFPP_FLOOD)]
        self.add_flow(datapath, 100, match, actions)
        
        # Règle pour autoriser le trafic ICMP (ping)
        match = parser.OFPMatch(eth_type=ether_types.ETH_TYPE_IP, ip_proto=1)
        actions = [parser.OFPActionOutput(ofproto.OFPP_FLOOD)]
        self.add_flow(datapath, 200, match, actions)

        self.logger.info("Règles de base installées sur switch %s", datapath.id)

    def add_flow(self, datapath, priority, match, actions, buffer_id=None):
        ofproto = datapath.ofproto
        parser = datapath.ofproto_parser

        inst = [parser.OFPInstructionActions(ofproto.OFPIT_APPLY_ACTIONS, actions)]
        if buffer_id:
            mod = parser.OFPFlowMod(datapath=datapath, buffer_id=buffer_id,
                                    priority=priority, match=match, instructions=inst)
        else:
            mod = parser.OFPFlowMod(datapath=datapath, priority=priority,
                                    match=match, instructions=inst)
        datapath.send_msg(mod)

    @set_ev_cls(ofp_event.EventOFPPacketIn, MAIN_DISPATCHER)
    def _packet_in_handler(self, ev):
        msg = ev.msg
        datapath = msg.datapath
        ofproto = datapath.ofproto
        parser = datapath.ofproto_parser
        in_port = msg.match['in_port']

        pkt = packet.Packet(msg.data)
        eth = pkt.get_protocols(ethernet.ethernet)[0]

        if eth.ethertype == ether_types.ETH_TYPE_LLDP:
            return

        dst = eth.dst
        src = eth.src
        dpid = datapath.id
        
        self.mac_to_port.setdefault(dpid, {})
        self.mac_to_port[dpid][src] = in_port

        if dst in self.mac_to_port[dpid]:
            out_port = self.mac_to_port[dpid][dst]
        else:
            out_port = ofproto.OFPP_FLOOD

        actions = [parser.OFPActionOutput(out_port)]

        # Installation d'un flow pour éviter packet_in la prochaine fois
        if out_port != ofproto.OFPP_FLOOD:
            match = parser.OFPMatch(in_port=in_port, eth_dst=dst, eth_src=src)
            if msg.buffer_id != ofproto.OFP_NO_BUFFER:
                self.add_flow(datapath, 1, match, actions, msg.buffer_id)
                return
            else:
                self.add_flow(datapath, 1, match, actions)

        data = None
        if msg.buffer_id == ofproto.OFP_NO_BUFFER:
            data = msg.data

        out = parser.OFPPacketOut(datapath=datapath, buffer_id=msg.buffer_id,
                                  in_port=in_port, actions=actions, data=data)
        datapath.send_msg(out)

class SDNRestAPI(ControllerBase):
    def __init__(self, req, link, data, **config):
        super(SDNRestAPI, self).__init__(req, link, data, **config)
        self.sdn_app = data[sdn_instance_name]

    @route('sdn', url + '/switches', methods=['GET'])
    def list_switches(self, req, **kwargs):
        switches = []
        for dpid, info in self.sdn_app.switches.items():
            switches.append({
                'dpid': dpid,
                'connected_at': info.get('connected_at', 'unknown')
            })
        body = json.dumps({'switches': switches})
        return Response(content_type='application/json', body=body)

    @route('sdn', url + '/flows/{dpid}', methods=['GET'])
    def get_flows(self, req, **kwargs):
        dpid = int(kwargs['dpid'])
        flows = self.sdn_app.flows.get(dpid, [])
        body = json.dumps({'flows': flows})
        return Response(content_type='application/json', body=body)

    @route('sdn', url + '/stats', methods=['GET'])
    def get_stats(self, req, **kwargs):
        stats = {
            'switches_count': len(self.sdn_app.switches),
            'mac_table_size': sum(len(table) for table in self.sdn_app.mac_to_port.values()),
            'controller_status': 'active'
        }
        body = json.dumps(stats)
        return Response(content_type='application/json', body=body)

    @route('sdn', '/', methods=['GET'])
    def index(self, req, **kwargs):
        html = '''
        <!DOCTYPE html>
        <html>
        <head>
            <title>Ryu SDN Controller</title>
            <style>
                body { font-family: Arial, sans-serif; margin: 40px; background: #f5f5f5; }
                .container { max-width: 800px; margin: 0 auto; background: white; padding: 30px; border-radius: 10px; }
                .header { text-align: center; color: #333; border-bottom: 2px solid #007bff; padding-bottom: 20px; }
                .card { border: 1px solid #ddd; padding: 20px; margin: 20px 0; border-radius: 5px; }
                .btn { background: #007bff; color: white; padding: 10px 20px; text-decoration: none; border-radius: 3px; margin: 5px; }
                .status { color: green; font-weight: bold; }
            </style>
        </head>
        <body>
            <div class="container">
                <div class="header">
                    <h1>🌐 Ryu SDN Controller</h1>
                    <p class="status">✅ Controller Active</p>
                </div>
                <div class="card">
                    <h2>Status</h2>
                    <p>OpenFlow Port: 6633</p>
                    <p>REST API Port: 8080</p>
                    <p>Switches connectés: ''' + str(len(self.sdn_app.switches)) + '''</p>
                </div>
                <div class="card">
                    <h2>API Endpoints</h2>
                    <ul>
                        <li><a href="/sdn/switches">/sdn/switches</a> - Liste des switches</li>
                        <li><a href="/sdn/stats">/sdn/stats</a> - Statistiques</li>
                        <li><a href="/stats/switches">/stats/switches</a> - Stats switches (REST API)</li>
                    </ul>
                </div>
            </div>
        </body>
        </html>
        '''
        return Response(content_type='text/html', body=html)
EOF

# Service Ryu avec configuration robuste
cat > /etc/systemd/system/ryu.service << 'EOF'
[Unit]
Description=Ryu SDN Controller
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=/opt/ryu
Environment=PYTHONPATH=/opt/ryu
ExecStart=/usr/local/bin/ryu-manager --ofp-tcp-listen-port 6633 --wsapi-host 0.0.0.0 --wsapi-port 8080 --verbose /opt/ryu/apps/sdn_controller.py
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# Vérifier que ryu-manager est disponible
if ! command -v ryu-manager >/dev/null 2>&1; then
    echo "Installation de ryu-manager..."
    # Créer un lien symbolique si nécessaire
    find /usr -name "ryu-manager" 2>/dev/null | head -1 | xargs -I {} ln -sf {} /usr/local/bin/ryu-manager 2>/dev/null || true
    
    # Si toujours pas trouvé, utiliser python directement
    if ! command -v ryu-manager >/dev/null 2>&1; then
        cat > /usr/local/bin/ryu-manager << 'EOF'
#!/bin/bash
python3 -m ryu.cmd.manager "$@"
EOF
        chmod +x /usr/local/bin/ryu-manager
    fi
fi

echo "=== Installation de Prometheus ==="

# Installation de Prometheus
useradd --no-create-home --shell /bin/false prometheus || true
mkdir -p /etc/prometheus /var/lib/prometheus
chown prometheus:prometheus /etc/prometheus /var/lib/prometheus

cd /tmp
wget -q https://github.com/prometheus/prometheus/releases/download/v2.40.0/prometheus-2.40.0.linux-amd64.tar.gz
tar xf prometheus-2.40.0.linux-amd64.tar.gz
cp prometheus-2.40.0.linux-amd64/prometheus /usr/local/bin/
cp prometheus-2.40.0.linux-amd64/promtool /usr/local/bin/
chown prometheus:prometheus /usr/local/bin/prometheus /usr/local/bin/promtool

# Copier les consoles et libraries
cp -r prometheus-2.40.0.linux-amd64/consoles /etc/prometheus/
cp -r prometheus-2.40.0.linux-amd64/console_libraries /etc/prometheus/
chown -R prometheus:prometheus /etc/prometheus/consoles /etc/prometheus/console_libraries

# Configuration Prometheus
cat > /etc/prometheus/prometheus.yml << 'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

rule_files:
  # - "first_rules.yml"

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'ryu-controller'
    static_configs:
      - targets: ['localhost:8080']
    metrics_path: '/sdn/stats'
    scrape_interval: 10s

  - job_name: 'node-exporter-controller'
    static_configs:
      - targets: ['localhost:9100']

  - job_name: 'node-exporter-routers'
    static_configs:
      - targets: ['192.168.100.11:9100', '192.168.100.12:9100']

  - job_name: 'node-exporter-clients'
    static_configs:
      - targets: ['192.168.100.21:9100', '192.168.100.22:9100']
EOF

chown prometheus:prometheus /etc/prometheus/prometheus.yml

# Service Prometheus
cat > /etc/systemd/system/prometheus.service << 'EOF'
[Unit]
Description=Prometheus
Wants=network-online.target
After=network-online.target

[Service]
User=prometheus
Group=prometheus
Type=simple
ExecStart=/usr/local/bin/prometheus \
    --config.file /etc/prometheus/prometheus.yml \
    --storage.tsdb.path /var/lib/prometheus/ \
    --web.console.templates=/etc/prometheus/consoles \
    --web.console.libraries=/etc/prometheus/console_libraries \
    --web.listen-address=0.0.0.0:9090 \
    --web.external-url=http://0.0.0.0:9090

[Install]
WantedBy=multi-user.target
EOF

echo "=== Installation de Node Exporter ==="

# Installation de Node Exporter pour le contrôleur
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

echo "=== Installation de Grafana ==="

# Installation de Grafana
apt-get install -y software-properties-common
wget -q -O - https://packages.grafana.com/gpg.key | apt-key add -
echo "deb https://packages.grafana.com/oss/deb stable main" | tee -a /etc/apt/sources.list.d/grafana.list
apt-get update
apt-get install -y grafana

# Configuration Grafana
cat > /etc/grafana/grafana.ini << 'EOF'
[server]
http_addr = 0.0.0.0
http_port = 3000
domain = 0.0.0.0
root_url = http://0.0.0.0:3000

[security]
admin_user = admin
admin_password = admin

[auth.anonymous]
enabled = false
EOF

echo "=== Activation et démarrage des services ==="

# Activation des services
systemctl daemon-reload
systemctl enable ryu
systemctl enable prometheus
systemctl enable node_exporter
systemctl enable grafana-server

# Démarrage des services dans l'ordre
systemctl start node_exporter
sleep 3
systemctl start prometheus
sleep 3
systemctl start grafana-server
sleep 3
systemctl start ryu
sleep 10

# Vérifications finales
echo "=== Vérifications finales ==="

# Vérifier le statut des services
echo "Statut des services:"
for service in ryu prometheus node_exporter grafana-server; do
    if systemctl is-active $service >/dev/null; then
        echo "✓ $service: ACTIF"
    else
        echo "✗ $service: INACTIF"
        systemctl status $service --no-pager -l
    fi
done

# Vérifier les ports
echo ""
echo "Ports en écoute:"
netstat -tlnp | grep -E ':(3000|6633|8080|9090|9100)' || echo "Certains ports ne sont pas ouverts"

# Test de Ryu
echo ""
echo "Test de Ryu:"
if curl -s http://localhost:8080/sdn/stats >/dev/null; then
    echo "✓ Ryu REST API fonctionne"
    curl -s http://localhost:8080/sdn/stats | python3 -m json.tool 2>/dev/null || echo "API accessible mais réponse non-JSON"
else
    echo "✗ Ryu REST API ne répond pas"
fi

# Test du port OpenFlow
echo ""
echo "Test port OpenFlow:"
if netstat -tln | grep :6633 >/dev/null; then
    echo "✓ Port OpenFlow 6633 ouvert"
else
    echo "✗ Port OpenFlow 6633 fermé"
fi

# Configuration automatique de Grafana
sleep 15
curl -X POST \
  http://admin:admin@localhost:3000/api/datasources \
  -H 'Content-Type: application/json' \
  -d '{
    "name": "Prometheus",
    "type": "prometheus",
    "url": "http://localhost:9090",
    "access": "proxy",
    "isDefault": true
  }' 2>/dev/null || echo "Datasource Grafana déjà configurée"

echo ""
echo "=== Installation terminée ==="
echo "Accès depuis votre machine physique :"
echo "Ryu Web Interface: http://localhost:8080"
echo "Ryu REST API: http://localhost:8080/sdn/stats"
echo "Prometheus: http://localhost:9090"
echo "Grafana: http://localhost:3000 (admin/admin)"
echo ""
echo "Pour tester Ryu:"
echo "curl http://localhost:8080/sdn/switches"
echo "curl http://localhost:8080/sdn/stats"

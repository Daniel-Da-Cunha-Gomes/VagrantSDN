#!/bin/bash

set -e

echo "=== Installation du contrôleur SDN (Ryu) ==="

# Mise à jour du système
apt-get update
apt-get upgrade -y

# Installation des dépendances
apt-get install -y \
    python3 \
    python3-pip \
    python3-dev \
    git \
    curl \
    wget \
    openvswitch-switch \
    openvswitch-common \
    net-tools \
    tcpdump \
    iperf3 \
    ufw

# Désactiver le firewall pour les tests
ufw --force disable

# Installation de Ryu avec les dépendances web
pip3 install ryu eventlet webob routes

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

# Configuration Prometheus avec tous les exporters
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
    metrics_path: '/stats/switches'
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

  - job_name: 'apache-clients'
    static_configs:
      - targets: ['192.168.100.21:9117', '192.168.100.22:9117']
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

[dashboards]
default_home_dashboard_path = /var/lib/grafana/dashboards/network-overview.json
EOF

# Créer le répertoire des dashboards
mkdir -p /var/lib/grafana/dashboards
chown -R grafana:grafana /var/lib/grafana/dashboards

# Dashboard réseau personnalisé
cat > /var/lib/grafana/dashboards/network-overview.json << 'EOF'
{
  "dashboard": {
    "id": null,
    "title": "SDN Network Overview",
    "tags": ["sdn", "network"],
    "timezone": "browser",
    "panels": [
      {
        "id": 1,
        "title": "Network Nodes Status",
        "type": "stat",
        "targets": [
          {
            "expr": "up",
            "legendFormat": "{{instance}}"
          }
        ],
        "gridPos": {"h": 8, "w": 12, "x": 0, "y": 0}
      },
      {
        "id": 2,
        "title": "CPU Usage",
        "type": "graph",
        "targets": [
          {
            "expr": "100 - (avg by (instance) (rate(node_cpu_seconds_total{mode=\"idle\"}[5m])) * 100)",
            "legendFormat": "{{instance}}"
          }
        ],
        "gridPos": {"h": 8, "w": 12, "x": 12, "y": 0}
      },
      {
        "id": 3,
        "title": "Memory Usage",
        "type": "graph",
        "targets": [
          {
            "expr": "(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100",
            "legendFormat": "{{instance}}"
          }
        ],
        "gridPos": {"h": 8, "w": 12, "x": 0, "y": 8}
      },
      {
        "id": 4,
        "title": "Network Traffic",
        "type": "graph",
        "targets": [
          {
            "expr": "rate(node_network_receive_bytes_total[5m])",
            "legendFormat": "RX {{instance}} {{device}}"
          },
          {
            "expr": "rate(node_network_transmit_bytes_total[5m])",
            "legendFormat": "TX {{instance}} {{device}}"
          }
        ],
        "gridPos": {"h": 8, "w": 12, "x": 12, "y": 8}
      }
    ],
    "time": {"from": "now-1h", "to": "now"},
    "refresh": "5s"
  }
}
EOF

# Configuration des applications Ryu
mkdir -p /opt/ryu/apps

# Application Ryu avec interface web
cat > /opt/ryu/apps/sdn_controller.py << 'EOF'
from ryu.base import app_manager
from ryu.controller import ofp_event
from ryu.controller.handler import CONFIG_DISPATCHER, MAIN_DISPATCHER
from ryu.controller.handler import set_ev_cls
from ryu.ofproto import ofproto_v1_3
from ryu.lib.packet import packet
from ryu.lib.packet import ethernet
from ryu.lib.packet import ether_types
from ryu.app.wsgi import ControllerBase, WSGIApplication, route
from webob import Response
import json

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
        
        wsgi = kwargs['wsgi']
        wsgi.register(SDNRestAPI, {sdn_instance_name: self})

    @set_ev_cls(ofp_event.EventOFPSwitchFeatures, CONFIG_DISPATCHER)
    def switch_features_handler(self, ev):
        datapath = ev.msg.datapath
        ofproto = datapath.ofproto
        parser = datapath.ofproto_parser
        
        # Enregistrer le switch
        self.switches[datapath.id] = {
            'datapath': datapath,
            'ports': {}
        }

        # Règle par défaut
        match = parser.OFPMatch()
        actions = [parser.OFPActionOutput(ofproto.OFPP_CONTROLLER,
                                          ofproto.OFPCML_NO_BUFFER)]
        self.add_flow(datapath, 0, match, actions)
        self.logger.info("Switch %s connecté", datapath.id)

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
        switches = list(self.sdn_app.switches.keys())
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
            'mac_table_size': sum(len(table) for table in self.sdn_app.mac_to_port.values())
        }
        body = json.dumps(stats)
        return Response(content_type='application/json', body=body)
EOF

# Interface web simple pour Ryu
cat > /opt/ryu/apps/web_interface.py << 'EOF'
from ryu.app.wsgi import ControllerBase, WSGIApplication, route
from webob import Response
import json

web_instance_name = 'web_api_app'

class WebInterface(ControllerBase):
    def __init__(self, req, link, data, **config):
        super(WebInterface, self).__init__(req, link, data, **config)

    @route('web', '/', methods=['GET'])
    def index(self, req, **kwargs):
        html = '''
        <!DOCTYPE html>
        <html>
        <head>
            <title>Ryu SDN Controller</title>
            <style>
                body { font-family: Arial, sans-serif; margin: 40px; }
                .container { max-width: 800px; margin: 0 auto; }
                .card { border: 1px solid #ddd; padding: 20px; margin: 20px 0; border-radius: 5px; }
                .btn { background: #007bff; color: white; padding: 10px 20px; text-decoration: none; border-radius: 3px; }
                .status { color: green; font-weight: bold; }
            </style>
        </head>
        <body>
            <div class="container">
                <h1>🌐 Ryu SDN Controller</h1>
                <div class="card">
                    <h2>Status</h2>
                    <p class="status">✅ Controller Active</p>
                    <p>OpenFlow Port: 6633</p>
                    <p>REST API Port: 8080</p>
                </div>
                <div class="card">
                    <h2>API Endpoints</h2>
                    <ul>
                        <li><a href="/sdn/switches">/sdn/switches</a> - Liste des switches</li>
                        <li><a href="/sdn/stats">/sdn/stats</a> - Statistiques</li>
                        <li><a href="/stats/switches">/stats/switches</a> - Stats switches (REST API)</li>
                        <li><a href="/stats/flows">/stats/flows</a> - Stats flows (REST API)</li>
                    </ul>
                </div>
                <div class="card">
                    <h2>Monitoring</h2>
                    <p><a href="http://localhost:9090" class="btn">Prometheus</a></p>
                    <p><a href="http://localhost:3000" class="btn">Grafana</a></p>
                </div>
            </div>
        </body>
        </html>
        '''
        return Response(content_type='text/html', body=html)
EOF

# Service Ryu avec interface web
cat > /etc/systemd/system/ryu.service << 'EOF'
[Unit]
Description=Ryu SDN Controller
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/ryu
ExecStart=/usr/local/bin/ryu-manager /opt/ryu/apps/sdn_controller.py /opt/ryu/apps/web_interface.py --ofp-tcp-listen-port 6633 --wsapi-host 0.0.0.0 --wsapi-port 8080
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Activation des services
systemctl daemon-reload
systemctl enable prometheus
systemctl enable node_exporter
systemctl enable grafana-server
systemctl enable ryu

# Démarrage des services
systemctl start node_exporter
systemctl start prometheus
systemctl start grafana-server
systemctl start ryu

# Attendre que les services démarrent
sleep 15

# Configuration automatique de Grafana
curl -X POST \
  http://admin:admin@localhost:3000/api/datasources \
  -H 'Content-Type: application/json' \
  -d '{
    "name": "Prometheus",
    "type": "prometheus",
    "url": "http://localhost:9090",
    "access": "proxy",
    "isDefault": true
  }' 2>/dev/null || echo "Datasource déjà configurée"

# Vérifier le statut des services
echo "=== Statut des services ==="
systemctl is-active prometheus && echo "✓ Prometheus actif" || echo "✗ Prometheus inactif"
systemctl is-active node_exporter && echo "✓ Node Exporter actif" || echo "✗ Node Exporter inactif"
systemctl is-active grafana-server && echo "✓ Grafana actif" || echo "✗ Grafana inactif"
systemctl is-active ryu && echo "✓ Ryu actif" || echo "✗ Ryu inactif"

# Afficher les ports en écoute
echo "=== Ports en écoute ==="
netstat -tlnp | grep -E ':(3000|8080|9090|9100|6633)'

echo "=== Installation terminée ==="
echo "Accès depuis votre machine physique :"
echo "Ryu Web Interface: http://localhost:8080"
echo "Prometheus: http://localhost:9090"
echo "Grafana: http://localhost:3000 (admin/admin)"
echo "Client1 Web: http://localhost:8081"
echo "Client2 Web: http://localhost:8082"

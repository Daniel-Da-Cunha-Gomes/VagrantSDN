#!/bin/bash

set -e

echo "=== Installation du contrôleur SDN (Ryu) - VERSION CORRIGÉE ==="

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

# CORRECTION : Installation de versions compatibles
echo "=== Installation de Ryu avec versions compatibles ==="

# Désinstaller les versions incompatibles
pip3 uninstall -y ryu eventlet webob routes || true

# Installer des versions compatibles spécifiques
pip3 install --upgrade pip
pip3 install eventlet==0.33.3  # Version compatible avec Ryu
pip3 install webob==1.8.7
pip3 install routes==2.5.1
pip3 install ryu==4.34

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

echo "=== Installation de Node Exporter ==="

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

echo "=== Configuration des applications Ryu ==="

# Configuration des applications Ryu
mkdir -p /opt/ryu/apps

# Application Ryu simple et fonctionnelle
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

simple_switch_instance_name = 'simple_switch_api_app'
url = '/simpleswitch'

class SimpleSwitch13(app_manager.RyuApp):
    OFP_VERSIONS = [ofproto_v1_3.OFP_VERSION]
    _CONTEXTS = {'wsgi': WSGIApplication}

    def __init__(self, *args, **kwargs):
        super(SimpleSwitch13, self).__init__(*args, **kwargs)
        self.mac_to_port = {}
        self.switches = {}
        wsgi = kwargs['wsgi']
        wsgi.register(SimpleSwitchController, {simple_switch_instance_name: self})

    @set_ev_cls(ofp_event.EventOFPSwitchFeatures, CONFIG_DISPATCHER)
    def switch_features_handler(self, ev):
        datapath = ev.msg.datapath
        ofproto = datapath.ofproto
        parser = datapath.ofproto_parser
        
        # Store switch info
        self.switches[datapath.id] = datapath

        match = parser.OFPMatch()
        actions = [parser.OFPActionOutput(ofproto.OFPP_CONTROLLER,
                                          ofproto.OFPCML_NO_BUFFER)]
        self.add_flow(datapath, 0, match, actions)
        self.logger.info("Switch %s connected", datapath.id)

    def add_flow(self, datapath, priority, match, actions, buffer_id=None):
        ofproto = datapath.ofproto
        parser = datapath.ofproto_parser

        inst = [parser.OFPInstructionActions(ofproto.OFPIT_APPLY_ACTIONS,
                                             actions)]
        if buffer_id:
            mod = parser.OFPFlowMod(datapath=datapath, buffer_id=buffer_id,
                                    priority=priority, match=match,
                                    instructions=inst)
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

class SimpleSwitchController(ControllerBase):

    def __init__(self, req, link, data, **config):
        super(SimpleSwitchController, self).__init__(req, link, data, **config)
        self.simple_switch_app = data[simple_switch_instance_name]

    @route('simpleswitch', url + '/mactable/{dpid}', methods=['GET'])
    def list_mac_table(self, req, **kwargs):
        simple_switch = self.simple_switch_app
        dpid = int(kwargs['dpid'])
        
        if dpid not in simple_switch.mac_to_port:
            return Response(status=404)

        mac_table = simple_switch.mac_to_port.get(dpid, {})
        body = json.dumps(mac_table)
        return Response(content_type='application/json', body=body)

    @route('simpleswitch', url + '/switches', methods=['GET'])
    def list_switches(self, req, **kwargs):
        simple_switch = self.simple_switch_app
        switches = list(simple_switch.switches.keys())
        body = json.dumps(switches)
        return Response(content_type='application/json', body=body)

    @route('simpleswitch', '/', methods=['GET'])
    def index(self, req, **kwargs):
        simple_switch = self.simple_switch_app
        html = f'''
        <!DOCTYPE html>
        <html>
        <head>
            <title>Ryu SDN Controller</title>
            <style>
                body {{ font-family: Arial, sans-serif; margin: 40px; background: #f5f5f5; }}
                .container {{ max-width: 800px; margin: 0 auto; }}
                .card {{ background: white; border: 1px solid #ddd; padding: 20px; margin: 20px 0; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }}
                .status {{ color: #28a745; font-weight: bold; }}
                h1 {{ text-align: center; color: #333; }}
                .btn {{ background: #007bff; color: white; padding: 10px 20px; text-decoration: none; border-radius: 4px; display: inline-block; margin: 5px; }}
                .btn:hover {{ background: #0056b3; }}
                ul {{ list-style-type: none; padding: 0; }}
                li {{ padding: 8px 0; border-bottom: 1px solid #eee; }}
                a {{ color: #007bff; text-decoration: none; }}
            </style>
        </head>
        <body>
            <div class="container">
                <h1>🌐 Ryu SDN Controller</h1>
                <div class="card">
                    <h2>Status</h2>
                    <p class="status">✅ Controller Active</p>
                    <p><strong>OpenFlow Port:</strong> 6633</p>
                    <p><strong>REST API Port:</strong> 8080</p>
                    <p><strong>Switches connectés:</strong> {len(simple_switch.switches)}</p>
                    <p><strong>Entrées MAC:</strong> {sum(len(table) for table in simple_switch.mac_to_port.values())}</p>
                </div>
                <div class="card">
                    <h2>API Endpoints</h2>
                    <ul>
                        <li><a href="/simpleswitch/switches">/simpleswitch/switches</a> - Liste des switches</li>
                        <li><a href="/simpleswitch/mactable/1">/simpleswitch/mactable/1</a> - Table MAC switch 1</li>
                    </ul>
                </div>
                <div class="card">
                    <h2>Monitoring</h2>
                    <a href="http://{req.host.split(':')[0]}:9090" class="btn" target="_blank">📊 Prometheus</a>
                    <a href="http://{req.host.split(':')[0]}:3000" class="btn" target="_blank">📈 Grafana</a>
                </div>
            </div>
        </body>
        </html>
        '''
        return Response(content_type='text/html', body=html)
EOF

# Service Ryu corrigé
cat > /etc/systemd/system/ryu.service << 'EOF'
[Unit]
Description=Ryu SDN Controller
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/ryu
ExecStart=/usr/local/bin/ryu-manager --ofp-tcp-listen-port 6633 --wsapi-host 0.0.0.0 --wsapi-port 8080 --verbose /opt/ryu/apps/sdn_controller.py
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

echo "=== Activation et démarrage des services ==="

# Activation des services
systemctl daemon-reload
systemctl enable ryu
systemctl enable prometheus
systemctl enable node_exporter
systemctl enable grafana-server

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

echo "=== Vérifications finales ==="

# Test rapide de compatibilité
echo "Test de compatibilité eventlet..."
python3 -c "
try:
    import ryu.app.wsgi
    print('✅ Ryu WSGI fonctionne')
except Exception as e:
    print(f'❌ Erreur: {e}')
"

# Vérifier le statut des services
echo ""
echo "Statut des services:"
systemctl is-active ryu && echo "✅ ryu: ACTIF" || echo "❌ ryu: INACTIF"
systemctl is-active prometheus && echo "✅ Prometheus: ACTIF" || echo "❌ Prometheus: INACTIF"
systemctl is-active node_exporter && echo "✅ Node Exporter: ACTIF" || echo "❌ Node Exporter: INACTIF"
systemctl is-active grafana-server && echo "✅ Grafana: ACTIF" || echo "❌ Grafana: INACTIF"

# Afficher les détails si Ryu ne fonctionne pas
if ! systemctl is-active --quiet ryu; then
    echo ""
    echo "=== Détails du service Ryu ==="
    systemctl status ryu --no-pager
    echo ""
    echo "=== Logs récents ==="
    journalctl -u ryu --no-pager -n 10
fi

# Afficher les ports en écoute
echo ""
echo "=== Ports en écoute ==="
netstat -tlnp | grep -E ':(3000|8080|9090|9100|6633)' || echo "Aucun port trouvé"

echo ""
echo "=== Installation terminée ==="
echo "🌐 Ryu Web Interface: http://localhost:8080"
echo "📊 Prometheus: http://localhost:9090"
echo "📈 Grafana: http://localhost:3000 (admin/admin)"

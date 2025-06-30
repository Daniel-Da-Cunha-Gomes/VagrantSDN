#!/bin/bash

echo "=== CORRECTION SIMPLE RYU ==="

# Arrêter le service
systemctl stop ryu

# Créer une version simplifiée qui fonctionne
cat > /opt/ryu/apps/simple_controller.py << 'EOF'
from ryu.base import app_manager
from ryu.controller import ofp_event
from ryu.controller.handler import CONFIG_DISPATCHER, MAIN_DISPATCHER
from ryu.controller.handler import set_ev_cls
from ryu.ofproto import ofproto_v1_3
from ryu.lib.packet import packet
from ryu.lib.packet import ethernet
from ryu.lib.packet import ether_types

class SimpleSwitch13(app_manager.RyuApp):
    OFP_VERSIONS = [ofproto_v1_3.OFP_VERSION]

    def __init__(self, *args, **kwargs):
        super(SimpleSwitch13, self).__init__(*args, **kwargs)
        self.mac_to_port = {}

    @set_ev_cls(ofp_event.EventOFPSwitchFeatures, CONFIG_DISPATCHER)
    def switch_features_handler(self, ev):
        datapath = ev.msg.datapath
        ofproto = datapath.ofproto
        parser = datapath.ofproto_parser

        # install table-miss flow entry
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
            # ignore lldp packet
            return
        dst = eth.dst
        src = eth.src

        dpid = datapath.id
        self.mac_to_port.setdefault(dpid, {})

        self.logger.info("packet in %s %s %s %s", dpid, src, dst, in_port)

        # learn a mac address to avoid FLOOD next time.
        self.mac_to_port[dpid][src] = in_port

        if dst in self.mac_to_port[dpid]:
            out_port = self.mac_to_port[dpid][dst]
        else:
            out_port = ofproto.OFPP_FLOOD

        actions = [parser.OFPActionOutput(out_port)]

        # install a flow to avoid packet_in next time
        if out_port != ofproto.OFPP_FLOOD:
            match = parser.OFPMatch(in_port=in_port, eth_dst=dst, eth_src=src)
            # verify if we have a valid buffer_id, if yes avoid to send both
            # flow_mod & packet_out
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
EOF

# Créer un service simplifié
cat > /etc/systemd/system/ryu.service << 'EOF'
[Unit]
Description=Ryu SDN Controller
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/ryu
ExecStart=/usr/local/bin/ryu-manager --ofp-tcp-listen-port 6633 --verbose /opt/ryu/apps/simple_controller.py
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# Recharger et tester
systemctl daemon-reload
systemctl start ryu

echo "Attente de 5 secondes..."
sleep 5

echo "Status du service:"
systemctl status ryu --no-pager

if systemctl is-active --quiet ryu; then
    echo "✅ Ryu fonctionne ! Ajout de l'interface web..."
    
    # Si le service simple fonctionne, on peut ajouter l'interface web
    cat > /opt/ryu/apps/web_controller.py << 'EOF'
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
            <title>Ryu Simple Switch</title>
            <style>
                body {{ font-family: Arial, sans-serif; margin: 40px; background: #f5f5f5; }}
                .container {{ max-width: 800px; margin: 0 auto; }}
                .card {{ background: white; border: 1px solid #ddd; padding: 20px; margin: 20px 0; border-radius: 8px; }}
                .status {{ color: #28a745; font-weight: bold; }}
                h1 {{ text-align: center; color: #333; }}
            </style>
        </head>
        <body>
            <div class="container">
                <h1>🌐 Ryu SDN Controller</h1>
                <div class="card">
                    <h2>Status</h2>
                    <p class="status">✅ Controller Active</p>
                    <p><strong>Switches connectés:</strong> {len(simple_switch.switches)}</p>
                    <p><strong>Entrées MAC:</strong> {sum(len(table) for table in simple_switch.mac_to_port.values())}</p>
                </div>
                <div class="card">
                    <h2>API Endpoints</h2>
                    <ul>
                        <li><a href="/simpleswitch/switches">/simpleswitch/switches</a></li>
                        <li><a href="/simpleswitch/mactable/1">/simpleswitch/mactable/1</a></li>
                    </ul>
                </div>
            </div>
        </body>
        </html>
        '''
        return Response(content_type='text/html', body=html)
EOF

    # Mettre à jour le service pour utiliser la version avec web
    cat > /etc/systemd/system/ryu.service << 'EOF'
[Unit]
Description=Ryu SDN Controller
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/ryu
ExecStart=/usr/local/bin/ryu-manager --ofp-tcp-listen-port 6633 --wsapi-host 0.0.0.0 --wsapi-port 8080 --verbose /opt/ryu/apps/web_controller.py
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl restart ryu
    sleep 5
    
    echo "✅ Interface web ajoutée ! Accessible sur http://localhost:8080"
else
    echo "❌ Le service simple ne fonctionne pas non plus. Vérifiez les logs:"
    journalctl -u ryu --no-pager -n 20
fi

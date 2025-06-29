#!/usr/bin/env python3
"""
Script pour injecter des règles OpenFlow via l'API REST de Ryu
"""

import requests
import json

RYU_API_BASE = "http://10.0.1.10:8080"

def get_switches():
    """Récupère la liste des switches connectés"""
    response = requests.get(f"{RYU_API_BASE}/stats/switches")
    return response.json()

def add_flow_rule(dpid, priority, match, actions):
    """Ajoute une règle de flux"""
    flow_data = {
        "dpid": dpid,
        "priority": priority,
        "match": match,
        "actions": actions
    }
    
    response = requests.post(
        f"{RYU_API_BASE}/stats/flowentry/add",
        data=json.dumps(flow_data),
        headers={'Content-Type': 'application/json'}
    )
    return response.status_code == 200

def block_icmp(dpid):
    """Bloque le trafic ICMP"""
    match = {
        "eth_type": 2048,  # IPv4
        "ip_proto": 1      # ICMP
    }
    actions = []  # Drop
    
    return add_flow_rule(dpid, 100, match, actions)

def redirect_http(dpid, output_port):
    """Redirige le trafic HTTP vers un port spécifique"""
    match = {
        "eth_type": 2048,  # IPv4
        "ip_proto": 6,     # TCP
        "tcp_dst": 80      # HTTP
    }
    actions = [{"type": "OUTPUT", "port": output_port}]
    
    return add_flow_rule(dpid, 200, match, actions)

def allow_ssh(dpid):
    """Autorise le trafic SSH"""
    match = {
        "eth_type": 2048,  # IPv4
        "ip_proto": 6,     # TCP
        "tcp_dst": 22      # SSH
    }
    actions = [{"type": "NORMAL"}]
    
    return add_flow_rule(dpid, 300, match, actions)

if __name__ == "__main__":
    print("=== Gestion des règles OpenFlow ===")
    
    # Récupération des switches
    switches = get_switches()
    print(f"Switches connectés: {switches}")
    
    for dpid in switches:
        print(f"\nConfiguration du switch {dpid}:")
        
        # Bloquer ICMP
        if block_icmp(dpid):
            print("✓ Règle ICMP bloquée ajoutée")
        
        # Rediriger HTTP vers port 1
        if redirect_http(dpid, 1):
            print("✓ Règle HTTP redirigée ajoutée")
        
        # Autoriser SSH
        if allow_ssh(dpid):
            print("✓ Règle SSH autorisée ajoutée")

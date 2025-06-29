# Infrastructure Réseau SDN avec Vagrant

## 🎯 Objectif

Cette maquette réseau automatisée déploie une infrastructure complète avec :
- **SDN** via Open vSwitch + contrôleur Ryu
- **Routage dynamique OSPF** avec FRRouting
- **Automatisation complète** avec Vagrant
- **Monitoring** avec Prometheus + Grafana

## 🏗️ Architecture

\`\`\`
                    ┌─────────────────┐
                    │   Controller    │
                    │ (Ryu + Grafana) │
                    │  10.0.1.10      │
                    └─────────┬───────┘
                              │
                    ┌─────────┴───────┐
                    │   Réseau SDN    │
                    │   10.0.1.0/24   │
                    └─────┬─────┬─────┘
                          │     │
                ┌─────────┴─┐ ┌─┴─────────┐
                │  Router1  │ │  Router2  │
                │10.0.1.1   │ │10.0.1.2   │
                │10.0.2.1   │ │10.0.3.1   │
                └─────┬─────┘ └─────┬─────┘
                      │             │
                ┌─────┴─────┐ ┌─────┴─────┐
                │  Client1  │ │  Client2  │
                │10.0.2.10  │ │10.0.3.10  │
                └───────────┘ └───────────┘
\`\`\`

## 🚀 Déploiement

### Prérequis
- Ubuntu 22.04
- VirtualBox
- Vagrant

### Installation
\`\`\`bash
# Cloner le projet
git clone <repo-url>
cd network-sdn-lab

# Démarrer l'infrastructure
vagrant up

# Vérifier le statut
vagrant status
\`\`\`

## 🔧 Configuration

### Accès aux services
- **Prometheus**: http://192.168.100.10:9090
- **Grafana**: http://192.168.100.10:3000 (admin/admin)
- **Ryu REST API**: http://192.168.100.10:8080

### Connexion aux VMs
\`\`\`bash
# Contrôleur SDN
vagrant ssh controller

# Routeurs
vagrant ssh router1
vagrant ssh router2

# Clients
vagrant ssh client1
vagrant ssh client2
\`\`\`

## 🧪 Tests

### Tests de connectivité
\`\`\`bash
# Depuis client1
vagrant ssh client1
sudo /vagrant/scripts/test-network.sh
\`\`\`

### Vérification OSPF
\`\`\`bash
# Sur les routeurs
vagrant ssh router1
sudo vtysh -c "show ip route ospf"
sudo vtysh -c "show ip ospf neighbor"
\`\`\`

### Tests OpenFlow
\`\`\`bash
# Injection de règles
vagrant ssh controller
cd /opt/ryu/apps
python3 flow_manager.py
\`\`\`

### Monitoring
\`\`\`bash
# Vérifier les métriques Prometheus
curl http://192.168.100.10:9090/api/v1/query?query=up

# Accéder à Grafana
# http://192.168.100.10:3000
# Login: admin / admin
\`\`\`

## 📊 Règles OpenFlow implémentées

1. **Blocage ICMP** (priorité 100)
   - Bloque tout le trafic ICMP
   - Action: DROP

2. **Redirection HTTP** (priorité 200)
   - Redirige le trafic HTTP vers un port spécifique
   - Action: OUTPUT vers port 1

3. **Autorisation SSH** (priorité 300)
   - Autorise le trafic SSH
   - Action: NORMAL

## 🔍 Commandes utiles

### Open vSwitch
\`\`\`bash
# Voir les bridges
sudo ovs-vsctl show

# Voir les flux
sudo ovs-ofctl dump-flows br0

# Statistiques
sudo ovs-ofctl dump-ports br0
\`\`\`

### FRRouting
\`\`\`bash
# Interface VTY
sudo vtysh

# Commandes dans vtysh
show ip route
show ip ospf neighbor
show ip ospf database
\`\`\`

### Tests réseau
\`\`\`bash
# Ping
ping 10.0.3.10

# Traceroute
traceroute 10.0.3.10

# Test HTTP
curl http://10.0.3.10

# Test bande passante
iperf3 -s  # Sur le serveur
iperf3 -c 10.0.3.10 -t 10  # Sur le client
\`\`\`

## 🛠️ Dépannage

### Problèmes courants

1. **Contrôleur Ryu non accessible**
   \`\`\`bash
   vagrant ssh controller
   sudo systemctl status ryu
   sudo systemctl restart ryu
   \`\`\`

2. **OSPF ne fonctionne pas**
   \`\`\`bash
   vagrant ssh router1
   sudo systemctl status frr
   sudo vtysh -c "show ip ospf neighbor"
   \`\`\`

3. **Open vSwitch non connecté**
   \`\`\`bash
   sudo ovs-vsctl set-controller br0 tcp:10.0.1.10:6633
   \`\`\`

### Logs
\`\`\`bash
# Logs Ryu
sudo journalctl -u ryu -f

# Logs FRR
sudo journalctl -u frr -f

# Logs système
sudo dmesg | tail
\`\`\`

## 📚 Ressources

- [Documentation Ryu](https://ryu.readthedocs.io/)
- [FRRouting Documentation](https://docs.frrouting.org/)
- [Open vSwitch Manual](http://www.openvswitch.org/support/dist-docs/)
- [OpenFlow Specification](https://opennetworking.org/software-defined-standards/specifications/)

## 🧹 Nettoyage

\`\`\`bash
# Arrêter et supprimer les VMs
vagrant destroy -f

# Nettoyer VirtualBox
VBoxManage list vms
VBoxManage unregistervm "VM-Name" --delete

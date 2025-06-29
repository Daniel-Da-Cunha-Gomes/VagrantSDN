# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure("2") do |config|
  # Configuration globale
  config.vm.box = "ubuntu/jammy64"
  config.vm.box_check_update = false
  
  # Réseau de management
  MGMT_NETWORK = "192.168.100"
  # Réseau de données
  DATA_NETWORK = "10.0"

  # VM Contrôleur SDN (Ryu)
  config.vm.define "controller" do |controller|
    controller.vm.hostname = "sdn-controller"
    controller.vm.network "private_network", ip: "#{MGMT_NETWORK}.10"
    controller.vm.network "private_network", ip: "#{DATA_NETWORK}.1.10"
    
    # Port forwarding pour accès depuis la machine physique
    controller.vm.network "forwarded_port", guest: 9090, host: 9090, host_ip: "0.0.0.0"  # Prometheus
    controller.vm.network "forwarded_port", guest: 3000, host: 3000, host_ip: "0.0.0.0"  # Grafana
    controller.vm.network "forwarded_port", guest: 8080, host: 8080, host_ip: "0.0.0.0"  # Ryu REST API
    controller.vm.network "forwarded_port", guest: 6633, host: 6633, host_ip: "0.0.0.0"  # OpenFlow
    
    controller.vm.provider "virtualbox" do |vb|
      vb.name = "SDN-Controller"
      vb.memory = "2048"
      vb.cpus = 2
    end
  
    controller.vm.provision "shell", path: "scripts/install-controller.sh"
  end

  # VM Routeur 1 (FRRouting + OVS)
  config.vm.define "router1" do |router1|
    router1.vm.hostname = "router1"
    router1.vm.network "private_network", ip: "#{MGMT_NETWORK}.11"
    router1.vm.network "private_network", ip: "#{DATA_NETWORK}.1.1"
    router1.vm.network "private_network", ip: "#{DATA_NETWORK}.2.1"
    
    router1.vm.provider "virtualbox" do |vb|
      vb.name = "Router-1"
      vb.memory = "1024"
      vb.cpus = 1
    end
    
    router1.vm.provision "shell", path: "scripts/install-router.sh"
  end

  # VM Routeur 2 (FRRouting + OVS)
  config.vm.define "router2" do |router2|
    router2.vm.hostname = "router2"
    router2.vm.network "private_network", ip: "#{MGMT_NETWORK}.12"
    router2.vm.network "private_network", ip: "#{DATA_NETWORK}.1.2"
    router2.vm.network "private_network", ip: "#{DATA_NETWORK}.3.1"
    
    router2.vm.provider "virtualbox" do |vb|
      vb.name = "Router-2"
      vb.memory = "1024"
      vb.cpus = 1
    end
    
    router2.vm.provision "shell", path: "scripts/install-router.sh"
  end

  # VM Client 1
  config.vm.define "client1" do |client1|
    client1.vm.hostname = "client1"
    client1.vm.network "private_network", ip: "#{MGMT_NETWORK}.21"
    client1.vm.network "private_network", ip: "#{DATA_NETWORK}.2.10"
    
    # Port forwarding pour le serveur web
    client1.vm.network "forwarded_port", guest: 80, host: 8081, host_ip: "0.0.0.0"
    
    client1.vm.provider "virtualbox" do |vb|
      vb.name = "Client-1"
      vb.memory = "512"
      vb.cpus = 1
    end
    
    client1.vm.provision "shell", path: "scripts/install-client.sh"
  end

  # VM Client 2
  config.vm.define "client2" do |client2|
    client2.vm.hostname = "client2"
    client2.vm.network "private_network", ip: "#{MGMT_NETWORK}.22"
    client2.vm.network "private_network", ip: "#{DATA_NETWORK}.3.10"
    
    # Port forwarding pour le serveur web
    client2.vm.network "forwarded_port", guest: 80, host: 8082, host_ip: "0.0.0.0"
    
    client2.vm.provider "virtualbox" do |vb|
      vb.name = "Client-2"
      vb.memory = "512"
      vb.cpus = 1
    end
    
    client2.vm.provision "shell", path: "scripts/install-client.sh"
  end
end

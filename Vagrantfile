Vagrant.configure("2") do |config|
  config.vm.provider "virtualbox" do |vb|
    vb.memory = "1024"
  end

  # Contrôleur SDN (Ryu)
  config.vm.define "controller" do |controller|
    controller.vm.box = "ubuntu/bionic64"
    controller.vm.hostname = "controller"
    controller.vm.network "private_network", ip: "192.168.10.10"
    controller.vm.provision "shell", path: "scripts/setup_controller.sh"
  end

  # Routeur 1
  config.vm.define "r1" do |r1|
    r1.vm.box = "ubuntu/bionic64"
    r1.vm.hostname = "r1"
    # Interface cœur réseau
    r1.vm.network "private_network", ip: "192.168.10.11", virtualbox__intnet: "net-core"
    # Interface clientA
    r1.vm.network "private_network", ip: "192.168.20.1", virtualbox__intnet: "net-clientA"
    r1.vm.provision "shell", path: "scripts/setup_routeur.sh"
  end

  # Routeur 2
  config.vm.define "r2" do |r2|
    r2.vm.box = "ubuntu/bionic64"
    r2.vm.hostname = "r2"
    # Interface cœur réseau
    r2.vm.network "private_network", ip: "192.168.10.12", virtualbox__intnet: "net-core"
    # Interface clientB
    r2.vm.network "private_network", ip: "192.168.30.1", virtualbox__intnet: "net-clientB"
    r2.vm.provision "shell", path: "scripts/setup_routeur2.sh"
  end

  # Client A
  config.vm.define "clientA" do |clientA|
    clientA.vm.box = "ubuntu/bionic64"
    clientA.vm.hostname = "clientA"
    clientA.vm.network "private_network", ip: "192.168.20.10", virtualbox__intnet: "net-clientA"
    clientA.vm.provision "shell", path: "scripts/setup_client.sh"
  end

  # Client B
  config.vm.define "clientB" do |clientB|
    clientB.vm.box = "ubuntu/bionic64"
    clientB.vm.hostname = "clientB"
    clientB.vm.network "private_network", ip: "192.168.30.10", virtualbox__intnet: "net-clientB"
    clientB.vm.provision "shell", path: "scripts/setup_client.sh"
  end
end

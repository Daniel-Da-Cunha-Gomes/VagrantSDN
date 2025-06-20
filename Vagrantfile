# Vagrantfile - Réseau SDN + OSPF + Monitoring

VAGRANT_API_VERSION = "2"

Vagrant.configure(VAGRANT_API_VERSION) do |config|
  # Box de base
  config.vm.box = "ubuntu/jammy64"

  # Définition des machines
  nodes = [
    { name: "controller", ip: "192.168.56.10", role: "ryu" },
    { name: "router1",    ip: "192.168.56.11", role: "frr" },
    { name: "router2",    ip: "192.168.56.12", role: "frr" },
    { name: "client1",    ip: "192.168.56.13", role: "client" }
  ]

  # Boucle de création
  nodes.each do |node|
    config.vm.define node[:name] do |nodeconfig|
      nodeconfig.vm.hostname = node[:name]
      nodeconfig.vm.network "private_network", ip: node[:ip]

      nodeconfig.vm.provider "virtualbox" do |vb|
        vb.memory = 1024
        vb.cpus = 1
      end

      # Provisionnement (Bash ici, mais remplaçable par Ansible)
      nodeconfig.vm.provision "shell", path: "provision/#{node[:role]}.sh"
    end
  end
end

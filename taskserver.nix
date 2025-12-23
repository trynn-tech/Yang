{ config, pkgs, ... }:

{
  services.taskchampion-sync-server = {
    enable = true;
    # The 'host' attribute is what your version of NixOS 25.11 requires
    host = "0.0.0.0"; 
    port = 8080;
    dataDir = "/var/lib/taskchampion-sync-server";
    # This automatically handles the basic firewall hole for port 8080
    openFirewall = true;
  };

  networking.firewall = {
    enable = true;
    # Keeping these for SSH and Syncthing specifically
    allowedTCPPorts = [ 22 22000 ];
    allowedUDPPorts = [ 22000 21027 ];
    trustedInterfaces = [ "tailscale0" ];
  };

  systemd.services.taskchampion-sync-server.serviceConfig = {
    Restart = "on-failure";
    RestartSec = "5s";
  };
}

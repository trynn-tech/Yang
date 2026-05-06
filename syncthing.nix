# syncthing.nix
{ config, pkgs, ... }:

{
  services.syncthing = {
    enable = true;
    user = "trynn";
    dataDir = "/home/trynn/yang_wiki"; 
    configDir = "/home/trynn/.config/syncthing";
    overrideDevices = true;
    overrideFolders = true;
    
    guiAddress = "0.0.0.0:8384"; 

    settings = {
      devices = {
        "Elsie" = { 
          id = "4T45VJY-X7TXH2T-3NRYFK2-BO6RKMY-6PZS6EH-GLWAPDU-ZKBZBDJ-GQBIEQR";
          # DOUBLE CHECK: Run 'tailscale status' on your phone to get THIS IP
          addresses = [ "tcp://100.90.160.23:22000" ]; 
        };
      };
      folders = {
        "yang_wiki" = {
          path = "/home/trynn/yang_wiki";
          devices = [ "Elsie" ]; 
          versioning = {
            type = "simple";
            params.keep = "5";
          };
        };
      };
      # Move these here to stop the NAT-PMP noise
      options = {
        natEnabled = false;
        urAccepted = -1; # Opt-out of usage reporting
      };
    };
  };

  networking.firewall = {
    enable = true;
    trustedInterfaces = [ "tailscale0" ];
    allowedTCPPorts = [ 22000 ];
    allowedUDPPorts = [ 22000 21027 ];
  };
}

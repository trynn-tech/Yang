{ config, pkgs, ... }:

{
  services.syncthing = {
    enable = true;
    user = "trynn";
    dataDir = "/home/trynn/Documents"; # Default base dir
    configDir = "/home/trynn/.config/syncthing";
    overrideDevices = true;     # Allows Nix to manage device list
    overrideFolders = true;     # Allows Nix to manage folder list
    
    settings = {
      devices = {
        # You will add your Phone/Laptop IDs here later
        # "phone" = { id = "DEVICE-ID-HERE"; };
      };
      folders = {
        "vimwiki" = {
          path = "/home/trynn/vimwiki";
          devices = [ ]; # Add device names here to share
          versioning = {
            type = "simple";
            params.keep = "5";
          };
        };
      };
    };
  };

  # Open Syncthing ports in the firewall
  # (Already partially handled in our taskserver.nix, but good to be explicit)
  networking.firewall.allowedTCPPorts = [ 8384 22000 ];
  networking.firewall.allowedUDPPorts = [ 22000 21027 ];
}

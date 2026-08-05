{ config, pkgs, lib, ... }:

let
  # MASTER AUDIO TOGGLE: Set to false for PipeWire + Scaling fixes. Set to true for legacy PulseAudio.
  _customAudioToggle = false; 
in
{ 
  imports = [ 
    # Include the results of the hardware scan.
    ./hardware-configuration.nix
    # TaskWarrior 3 Synchronize Servers
    ./taskserver.nix
    # TaskWarrior Project Scheduler
    ./carousel.nix 
    # Podman Configurations for Re-L AI
    ./lab.nix
    # Advanced Intrusion Detection Environment Configuration
    ./aide.nix # <--- Add it right here
  ];

  # Bootloader.
  boot.loader.systemd-boot.enable = true; 
  boot.loader.efi.canTouchEfiVariables = true;
  boot.blacklistedKernelModules = [ "nouveau" "nova_core" ];
  boot.kernelParams = [ 
    "nvidia-drm.modeset=1" 
    "pci=realloc"
  ];

  boot.extraModprobeConfig = ''
    options snd_hda_intel power_save=0
  '';

  # Added i915 back so the motherboard HDMI port turns on during boot initialization
  boot.initrd.kernelModules = [ "i915" "nvidia" "nvidia_modeset" "nvidia_uvm" "nvidia_drm" ];

  boot.kernel.sysctl = {
    "vm.overcommit_memory" = 1;
  };

  networking.hostName = "nixos"; 
  networking.networkmanager.enable = true;
  networking.nameservers = [ "1.1.1.1" "8.8.8.8" ];

  # Set your time zone.
  time.timeZone = "America/Chicago";

  # --- Desktop Power Strategy (Always On for Tailscale/AI) ---
  services.logind = {
    settings.Login = {
      HandleLidSwitch = "ignore";
      HandleLidSwitchExternalPower = "ignore";
      IdleAction = "ignore";
    };
  };

  # Completely disable the ability to suspend/sleep
  systemd.targets.sleep.enable = false;
  systemd.targets.suspend.enable = false;
  systemd.targets.hibernate.enable = false;
  systemd.targets.hybrid-sleep.enable = false;

  # Ignore stray sleep/power signals from ASUS ROG Falchion
  services.udev.extraRules = ''
    SUBSYSTEM=="input", ATTRS{idVendor}=="0b05", ATTRS{idProduct}=="193e", ENV{SYSTEMD_WANTS}="", TAG-="power-switch"
  '';

  # 1. Enable the shell system-wide (Critical!)
  programs.zsh.enable = true;

  # 2. Assign it to your user
  users.users.trynn = {
    isNormalUser = true;  
    description = "trynn";
    group = "users";      
    extraGroups = [ "networkmanager" "wheel" "video" "audio" ]; 
    shell = pkgs.zsh;
  };

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = { 
    LC_ADDRESS = "en_US.UTF-8"; 
    LC_IDENTIFICATION = "en_US.UTF-8"; 
    LC_MEASUREMENT = "en_US.UTF-8"; 
    LC_MONETARY = "en_US.UTF-8"; 
    LC_NAME = "en_US.UTF-8"; 
    LC_NUMERIC = "en_US.UTF-8"; 
    LC_PAPER = "en_US.UTF-8"; 
    LC_TELEPHONE = "en_US.UTF-8"; 
    LC_TIME = "en_US.UTF-8";
  };

  # Enable CUPS to print documents.
  services.printing.enable = true;

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # Enables Nix Flakes
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # List packages installed in system profile.
  environment.systemPackages = with pkgs; [
    pciutils
    tailscale 
    syncthing 
    picom          
    nvidia-container-toolkit 
    easyeffects
  ];

  # Ensure proprietary firmware (like SOF for Intel) is available
  hardware.enableAllFirmware = true;

  services.xserver = {
    enable = true;
    windowManager.i3.enable = true;
    
    # FIX: Keep nvidia as the driver instructing the display canvas to avoid sddm hangs
    videoDrivers = [ "nvidia" ];
  };

  # A custom "Caffeine-style" background process to keep displays alive
  systemd.user.services.anti-sleep-poker = {
    description = "Prevents TV/Displays from going to sleep via periodic xset pokes";
    wantedBy = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    serviceConfig = {
      ExecStart = pkgs.writers.writeBash "anti-sleep" ''
        while true; do
          # Disable screensaver/dpms and nudge the display every 4 minutes
          ${pkgs.xorg.xset}/bin/xset s off
          ${pkgs.xorg.xset}/bin/xset -dpms
          ${pkgs.xorg.xset}/bin/xset dpms force on
          sleep 240
        done
      '';
      Restart = "always";
    };
  };

   # Hardware / Nvidia
  hardware.graphics.enable = true;
  hardware.nvidia = {
    open = true; 
    modesetting.enable = true;
    powerManagement.enable = true;
    nvidiaSettings = true;
    nvidiaPersistenced = true;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
    
    # Active PRIME Sync configuration to bind both hardware cards together
    prime = {
      offload.enable = false;
      offload.enableOffloadCmd = false;
      sync.enable = true;
      intelBusId = "PCI:0:2:0";
      nvidiaBusId = "PCI:2:0:0";
    };
  };

  hardware.nvidia-container-toolkit.enable = true;

  # FIX: Forces X11 to bind to the Nvidia card while leaving the sync pipelines active for the motherboard port
  services.xserver.config = ''
    Section "ServerFlags"
        Option "BlankTime" "0"
        Option "StandbyTime" "0"
        Option "SuspendTime" "0"
        Option "OffTime" "0"
    EndSection

    Section "Device"
        Identifier     "Device0"
        Driver         "nvidia"
        VendorName     "NVIDIA Corporation"
    EndSection

    Section "Screen"
        Identifier     "Screen0"
        Device         "Device0"
        Option         "ForceFullCompositionPipeline" "on"
        Option         "TripleBuffer" "on"
        Option         "AllowIndirectGLXProtocol" "off"
    EndSection
  '';

  services.gnome.gnome-keyring.enable = true;
  security.pam.services.sddm.enableGnomeKeyring = true;

  # Display Manager (SDDM with Nvidia delay fix)
  services.displayManager = {
    sddm.enable = true;
    defaultSession = "none+i3";
  };

  # Enable Mouse Over Applications in i3
  services.libinput.enable = true;

  # Configure keymap in X11
  services.xserver.xkb = { 
    layout = "us"; 
    variant = "";
  };

    # =========================================================================
  # Audio Hardware & Server Infrastructure
  # =========================================================================
  
  services.pulseaudio.enable = _customAudioToggle;
  security.rtkit.enable = true; 
  
  services.pipewire = {
    enable = !_customAudioToggle;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true; 
    wireplumber.enable = true; 

    # Override WirePlumber to lock down linear software volume scaling
    wireplumber.extraConfig."50-alsa-software-mixer" = lib.mkIf (!_customAudioToggle) {
      "monitor.alsa.rules" = [
        {
          matches = [ { "device.name" = "~alsa_card.*"; } ];
          actions = {
            update-props = {
              "api.alsa.ignore-dB" = true; 
              "api.alsa.soft-mixer" = true; 
            };
          };
        }
      ];
    };
  };

  systemd.services.NetworkManager-wait-online.enable = false;

  # Keep container initialization safe. Protects against future network/nscd timeouts during startup hooks.
  systemd.services.podman-re-l-core = {
    wantedBy = [ "multi-user.target" ];
    after = [ "display-manager.service" "nvidia-persistenced.service" ];
    serviceConfig.TimeoutStartSec = lib.mkForce "10m";
  };

  programs.dconf.enable = true;

  systemd.user.services.easyeffects = {
    description = "EasyEffects daemon";
    requires = [ "pipewire.service" ];
    after = [ "pipewire.service" ];
    wantedBy = [ "graphical-session.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.easyeffects}/bin/easyeffects --gapplication-service";
      Restart = "on-failure";
    };
  };

  services.picom = {
    enable = true;
    backend = "glx"; 
    vSync = true;
   };

  # Enable Tailscale Mesh
  services.tailscale.enable = true;
  
  # Enable the OpenSSH daemon.
  services.openssh.enable = true;

  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
    defaultNetwork.settings.dns_enabled = true;
  };

  # Minimal Steam Setup
  programs.steam = {
    enable = true;
  };

  # Restored Steam Port Openings & Firewall rules
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 27015 ];
    allowedUDPPortRanges = [
      { from = 27015; to = 27030; }
      { from = 4379;  to = 4380; }
    ];
    extraCommands = ''
      iptables -A OUTPUT -p udp --dport 443 -j DROP
      iptables -A INPUT -p udp --dport 443 -j DROP
    '';
  };

  programs.gamemode.enable = true;
  programs.kdeconnect.enable = true;

  system.stateVersion = "25.11"; 
}


# /etc/nixos/configuration.nix
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
    ./aide.nix
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

  # Load KVM kernel module at system boot
  boot.kernelModules = [ "kvm-intel" ];

  # =========================================================================
  # Consolidated Host & Virtual Bridge Networking (Yuko OpenWrt Integration)
  # =========================================================================
  networking = {
    hostName = "nixos";
    networkmanager.enable = true;
    
    # Global DHCP allowed; NetworkManager manages host interfaces while
    # systemd-networkd/Nix handles the internal Yuko TAP bridge.
    useDHCP = lib.mkDefault true;

    # Yuko Internal Virtual Bridge Infrastructure
    bridges."br-yuko" = {
      interfaces = [ "tap-yuko" ];
    };

    # Set host bridge interface to request IP from OpenWrt's dnsmasq (192.168.1.1)
    interfaces."br-yuko".useDHCP = true;

    # TAP Interface permissions for QEMU user engine
    interfaces."tap-yuko" = {
      virtual = true;
      virtualOwner = "trynn";
    };

    # Firewall Rules
    firewall = {
      enable = true;
      # Trust Tailscale and internal OpenWrt Bridge
      trustedInterfaces = [ "tailscale0" "br-yuko" ];
      # Steam + Syncthing Ports
      allowedTCPPorts = [ 27015 22000 ];
      allowedUDPPorts = [ 41641 22000 21027 ];
      allowedUDPPortRanges = [
        { from = 27015; to = 27030; }
        { from = 4379;  to = 4380; }
      ];
    };
  };

  # Time Zone & Power Management
  time.timeZone = "America/Chicago";

  # Desktop Power Strategy (Always On for Tailscale/AI)
  services.logind = {
    settings.Login = {
      HandleLidSwitch = "ignore";
      HandleLidSwitchExternalPower = "ignore";
      IdleAction = "ignore";
    };
  };

  # Disable sleep/suspend states
  systemd.targets.sleep.enable = false;
  systemd.targets.suspend.enable = false;
  systemd.targets.hibernate.enable = false;
  systemd.targets.hybrid-sleep.enable = false;

  # Ignore stray sleep/power signals from ASUS ROG Falchion
  services.udev.extraRules = ''
    SUBSYSTEM=="input", ATTRS{idVendor}=="0b05", ATTRS{idProduct}=="193e", ENV{SYSTEMD_WANTS}="", TAG-="power-switch"
  '';

  # System User & Shells
  programs.zsh.enable = true;

  users.users.trynn = {
    isNormalUser = true;  
    description = "trynn";
    group = "users";      
    extraGroups = [ 
      "networkmanager"
      "wheel"
      "video"
      "audio"
      "adbusers"
      "kvm"
    ]; 
    shell = pkgs.zsh;
  };

  # Locales & Services
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

  services.printing.enable = true;
  nixpkgs.config.allowUnfree = true;
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  environment.systemPackages = with pkgs; [
    pciutils
    tailscale 
    syncthing 
    picom              
    nvidia-container-toolkit 
    android-tools
    copyq
    podman-tui
    android-tools
    scrcpy
  ];

  hardware.enableAllFirmware = true;

  services.xserver = {
    enable = true;
    windowManager.i3.enable = true;    
    videoDrivers = [ "nvidia" ];
  };

  # Screen Keep-Alive Service
  systemd.user.services.anti-sleep-poker = {
    description = "Prevents TV/Displays from going to sleep via periodic xset pokes";
    wantedBy = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    serviceConfig = {
      ExecStart = pkgs.writers.writeBash "anti-sleep" ''
        while true; do
          ${pkgs.xorg.xset}/bin/xset s off
          ${pkgs.xorg.xset}/bin/xset -dpms
          ${pkgs.xorg.xset}/bin/xset dpms force on
          sleep 240
        done
      '';
      Restart = "always";
    };
  }; 

  # Hardware / Nvidia Config
  hardware.graphics.enable = true;
  hardware.nvidia = {
    open = true; 
    modesetting.enable = true;
    powerManagement.enable = true;
    nvidiaSettings = true;
    nvidiaPersistenced = true;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
    
    prime = {
      offload.enable = false;
      offload.enableOffloadCmd = false;
      sync.enable = true;
      intelBusId = "PCI:0:2:0";
      nvidiaBusId = "PCI:2:0:0";
    };
  };

  hardware.nvidia-container-toolkit.enable = true;
 
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

  services.displayManager = {
    sddm.enable = true;
    defaultSession = "none+i3";
  };

  services.libinput.enable = true;
  services.xserver.xkb = { 
    layout = "us";
    variant = "";
  };


    # Audio Stack
  services.pulseaudio.enable = _customAudioToggle;
  security.rtkit.enable = true; 
  services.pipewire = {
    enable = !_customAudioToggle;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true; 
    wireplumber.enable = true; 

    # 1. Hardware Software-Mixer Configuration
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

    # 2. Modern combine-stream to bridge separate hardware clocks safely
    extraConfig.pipewire."10-abstract-tv-factory" = lib.mkIf (!_customAudioToggle) {
      "context.modules" = [
        {
          name = "libpipewire-module-combine-stream";
          args = {
            "combine.mode" = "sink";
            "node.name" = "Abstract_Dual_TV";
            "node.description" = "Sovereign Abstract Audio Factory";
            "combine.props" = {
              "audio.position" = [ "FL" "FR" ];
              "priority.driver" = 2000;
              "priority.session" = 2000;
            };
            "stream.props" = {
              "stream.dont-remix" = true;
            };
            "stream.rules" = [
              {
                matches = [
                  { "node.name" = "alsa_output.pci-0000_02_00.1.hdmi-stereo"; }
                  { "node.name" = "alsa_output.pci-0000_00_1f.3.hdmi-stereo"; }
                ];
                actions = {
                  "create-stream" = { };
                };
              }
            ];
          };
        }
      ];
    };

    wireplumber.extraConfig."51-disable-hdmi-suspend" = lib.mkIf (!_customAudioToggle) {
      "monitor.alsa.rules" = [
        {
          matches = [
            { "node.name" = "~alsa_output.*hdmi.*"; }
          ];
          actions = {
            update-props = {
              "session.suspend-timeout-seconds" = 0; # Disable auto-suspend on HDMI
            };
          };
        }
      ];
    };

    # 3. Structural Crash Fix: Strip out mod.x11-bell to stop X11 display disconnects from dropping PipeWire
    extraConfig.pipewire."20-stop-x11-bell-crashes" = lib.mkIf (!_customAudioToggle) {
      "context.modules" = [
        { 
          name = "libpipewire-module-x11-bell";
          flags = [ "ifexists" "nofail" ];
          args = { };
          # Disabling execution protects the daemon core from X11 I/O faults
          enabled = false; 
        }
      ];
    };
  };

  #systemd.user.services.set-default-audio-sink = {
  #  description = "Set Sovereign Abstract Audio Factory as default sink";
  #  wantedBy = [ "graphical-session.target" ];
  #  after = [ "pipewire.service" "pipewire-pulse.service" ];
  #  serviceConfig = {
  #    Type = "oneshot";
  #    ExecStart = pkgs.writers.writeBash "set-default-sink" ''
  #      # Wait up to 10 seconds for PipeWire Pulse socket to become responsive
  #      for i in {1..10}; do
  #        if ${pkgs.pulseaudio}/bin/pactl info >/dev/null 2>&1; then
  #          ${pkgs.pulseaudio}/bin/pactl set-default-sink Abstract_Dual_TV
  #          exit 0
  #        fi
  #        sleep 1
  #      done
  #    '';
  #    Restart = "on-failure";
  #    RestartSec = 2;
  #  };
  #};

  systemd.services.NetworkManager-wait-online.enable = false;
  systemd.services.podman-re-l-core = {
    wantedBy = [ "multi-user.target" ];
    after = [ "display-manager.service" "nvidia-persistenced.service" ];
    serviceConfig.TimeoutStartSec = lib.mkForce "10m";
  };

  programs.dconf.enable = true;

  services.picom = {
    enable = true;
    backend = "glx"; 
    vSync = true; 
  };

  services.tailscale.enable = true;
  services.openssh.enable = true;

  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
    defaultNetwork.settings.dns_enabled = true;
  };

  programs.steam.enable = true;
  programs.gamemode.enable = true;
  programs.kdeconnect.enable = true;

  system.stateVersion = "25.11"; 
}

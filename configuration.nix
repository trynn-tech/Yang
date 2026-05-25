{ config, pkgs, lib, ... }:

{ 
  imports = [ 
    # Include the results of the hardware scan.
    ./hardware-configuration.nix
    # TaskWarrior 3 Synchronize Servers
    ./taskserver.nix
    # Podman Configurations for Re-L AI
    ./lab.nix
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

  boot.initrd.kernelModules = ["i915" "nvidia" "nvidia_modeset" "nvidia_uvm" "nvidia_drm" ];

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
    # All settings now live inside this structured block
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
  SUBSYSTEM=="input", ATTRS{idVendor}=="0b05", ATTRS{idProduct}=="193e", ATTRS{name}=="ASUSTeK ROG FALCHION System Control", ENV{LIBINPUT_IGNORE_DEVICE}="1", ATTR{authorized}="0"
'';



  # 1. Enable the shell system-wide (Critical!)
  programs.zsh.enable = true;

  # 2. Assign it to your user
  users.users.trynn = {
    isNormalUser = true;  # This fixes the "isSystemUser/isNormalUser" error
    description = "trynn";
    group = "users";      # This fixes the "group is unset" error
    extraGroups = [ "networkmanager" "wheel" "video" "audio" ]; # 'wheel' for sudo
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
    vim
    git
    curl
    tree
    pciutils
    tailscale
    syncthing
    go-task
    alacritty      # Better terminal
    dmenu          # Program launcher (Mod+D)
    copyq          # Clipboard manager
    feh            # For setting wallpapers
    picom          # For transparency and shadows (prevents screen tearing)
    arandr         # Visual tool to manage multiple monitors
    adwaita-icon-theme # Provides a standard cursor
    brightnessctl   # Control screen brightness
    pavucontrol     # Audio control
    rofi            # Menu For User Applications
    nvidia-container-toolkit # Std interface for Nvidia container configuration
    easyeffects
    sonobus
  ];

  # Ensure proprietary firmware (like SOF for Intel) is available
  hardware.enableAllFirmware = true;

   services.xserver = {
    enable = true;
    
    # Enable i3
    windowManager.i3.enable = true;
    
    # Set the default session to i3
    videoDrivers = [ "nvidia" ];
  };

  # Hardware / Nvidia
  hardware.graphics.enable = true;
  hardware.nvidia = {
    open = true; # Set to false if you experience stability issues with 'open'
    modesetting.enable = true;
    powerManagement.enable = true;
    nvidiaSettings = true;
    nvidiaPersistenced = true;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
    prime = {
      offload.enable = true;
      offload.enableOffloadCmd = true;
      intelBusId = "PCI:0:2:0";
      nvidiaBusId = "PCI:2:0:0";
    };
  };

  hardware.nvidia-container-toolkit.enable = true;

  # common fix for X11/i3/Nvidia artifacts with Steam
  services.xserver.config = ''
  Section "Screen"
    Identifier "Screen0"
    Device "nvidia"
    Option "ForceFullCompositionPipeline" "on"
    Option "AllowIndirectGLXProtocol" "off"
    Option "TripleBuffer" "on"
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


  # Sound
  services.pulseaudio.enable = false;
  security.rtkit.enable = true; # Recommended for better performance
  
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true; # Enable PulseAudio emulation for compatibility
    wireplumber.enable = true; # Use WirePlumber session manager (recommended)
    # jack.enable = true; # Uncomment this if you need JACK application support
  };

  systemd.services.NetworkManager-wait-online.enable = false;
  systemd.services.podman-re-l-core.serviceConfig.TimeoutStartSec = lib.mkForce "10m";

  programs.dconf.enable = true;

  # 3. To make it start automatically for your user:
  # System-wide NixOS doesn't have a 'services.easyeffects'
  # So we tell the system to allow user-level systemd services
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
    # Switching to 'glx' with these specific settings usually solves the lag
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

  # Optional: Enable Gamemode for better performance 
  programs.gamemode.enable = true;

  programs.kdeconnect.enable = true;

  system.stateVersion = "25.11"; 
}

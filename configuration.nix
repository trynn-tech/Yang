# Edit this configuration file to define what should be installed on your system.

{ config, pkgs, lib, ... }:

{ 
  imports = [ 
    # Include the results of the hardware scan.
    ./hardware-configuration.nix
    # TaskWarrior 3 Synchronize Servers
    ./taskserver.nix
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
    options nvidia nvidia-drm-modeset=1
    options snd_hda_intel power_save=0
  '';

  networking.hostName = "nixos"; 
  networking.networkmanager.enable = true;
  networking.nameservers = [ "1.1.1.1" "8.8.8.8" ];

  # Set your time zone.
  time.timeZone = "America/Chicago";

  # 1. Enable the shell system-wide (Critical!)
  programs.zsh.enable = true;

  # 2. Assign it to your user
  users.users.trynn = {
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

  # Enable sound with pipewire.
  services.pulseaudio.enable = false; 
  security.rtkit.enable = true; 
  services.pipewire = {
    enable = true; 
    alsa.enable = true; 
    alsa.support32Bit = true; 
    pulse.enable = true;
  };

  # Define a user account.
  users.users.trynn = { 
    isNormalUser = true; 
    description = "Tristen Threadwalker"; 
    extraGroups = [ "networkmanager" "wheel" "podman" "video" "render"]; 
    packages = with pkgs; [ ];
  };

  # Install firefox.
  programs.firefox.enable = true;

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
    feh             # Wallpaper manager
    adwaita-icon-theme # Provides a standard cursor
    brightnessctl   # Control screen brightness
    pavucontrol     # Audio control
    rofi
  ];

  services.picom = {
    enable = true;
    # Switching to 'glx' with these specific settings usually solves the lag
    backend = "xrender"; 
    vSync = false;
    #commented out because it prevents scratchpad from working properly
    #settings = {
    #  unredir-if-possible = false; # This stops the background from blanking out
    #  # This ensures floating windows are always treated as "on top"
    #  mark-ovredir-focused = true;
    #  xrender-sync-fence = true;
    #  # Prevent Rofi and Scratchpad from being "faded" or "hidden"
    #  focus-exclude = [
    #    "class_g = 'Rofi'"
    #    "class_g = 'scratchpad'"
    #  ];
    #};

  };

  # Enable Tailscale Mesh
  services.tailscale.enable = true;
  
  # Enable the OpenSSH daemon.
  services.openssh.enable = true;

  hardware.graphics.enable = true; # Necessary for GPU acceleration

  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
    defaultNetwork.settings.dns_enabled = true;
  };


   services.xserver = {
    enable = true;
    
    displayManager.lightdm.enable = lib.mkForce false; # Kills the conflict    
    desktopManager.cinnamon.enable = false; 
    

    # Enable i3
    windowManager.i3.enable = true;
    
    # Set the default session to i3
    videoDrivers = [ "nvidia" ];

    deviceSection = ''
      Option "AccelMethod" "sna"
      Option "TearFree" "true"
    '';
  };

  services.displayManager.ly.enable = true;
  services.displayManager.defaultSession = "none+i3";

  # Enable Mouse Over Applications in i3
  services.libinput.enable = true;

  # Configure keymap in X11
  services.xserver.xkb = { 
    layout = "us"; 
    variant = "";
  };

  hardware.nvidia = {
    open = true; 
    
    modesetting.enable = true;
    powerManagement.enable = true;
    powerManagement.finegrained = false;
    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.stable;

    # 2. Hard-coded "Deep Link" (Derived from your lspci)
    prime = {
      offload.enable = true;
      offload.enableOffloadCmd = true;
      intelBusId = "PCI:0:2:0";
      nvidiaBusId = "PCI:2:0:0"; # Matches your '02:00.0' scan
    };
  };

  # Optimization for AI/GPU work in containers
  hardware.nvidia-container-toolkit.enable = true; # Only if using NVIDIA for the AI

  system.stateVersion = "25.11"; 
}

# aide.nix
{ config, pkgs, lib, ... }:

{
  # 1. Install AIDE system-wide with root access
  environment.systemPackages = [ pkgs.aide ];

  # Automatically provision the state storage directory layout on startup
  systemd.tmpfiles.rules = [
    "d /var/lib/aide 0700 root root -"
  ];

  # 2. Declaratively structure the AIDE configuration profile
  environment.etc."aide.conf".text = ''
    # Define verification database destinations
    database_in=file:/var/lib/aide/aide.db
    database_out=file:/var/lib/aide/aide.db.new
    gzip_dbout=yes

    # Define custom monitoring macro rule matrices
    MyCoreRules = p+i+n+u+g+s+m+c+sha256

    # Apply monitoring matrices to key critical system paths
    /boot        MyCoreRules
    /bin         MyCoreRules
    /sbin        MyCoreRules
    /lib         MyCoreRules
    /lib64       MyCoreRules
    /etc         MyCoreRules
    
    # Explicitly ignore highly dynamic system/user runtime spaces 
    !/etc/mtab
    !/var/lib/aide
  '';

  # AUTOMATED INITIALIZATION LOOP
  # This script intercepts activation and safely sets up the baseline database if it's missing.
  system.activationScripts.aide-init = {
    supportsDryActivation = true;
    text = ''
      if [ ! -f /var/lib/aide/aide.db ]; then
        echo "[aide] Initializing baseline integrity signature matrix database..."
        mkdir -p /var/lib/aide
        chmod 700 /var/lib/aide
        ${pkgs.aide}/bin/aide --init --config /etc/aide.conf || true
        if [ -f /var/lib/aide/aide.db.new ]; then
          mv /var/lib/aide/aide.db.new /var/lib/aide/aide.db
          echo "[aide] Baseline integrity verification snapshots captured successfully."
        fi
      fi
    '';
  };

  # 3. Create the automated checking Daemon via Systemd
  systemd.services.aide-check = {
    description = "Intermittent File Integrity Scanner Daemon";
    after = [ "network.target" ];
    
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.aide}/bin/aide --check --config /etc/aide.conf";
      
      # Resource optimization: Run sweeps quietly in the background
      Nice = 19; 
      IOSchedulingClass = "idle"; 
    };
  };

  # 4. Automate the scanning intervals
  systemd.timers.aide-check = {
    description = "Trigger AIDE daily for machine file integrity tracking";
    timerConfig = {
      OnCalendar = "daily"; # Fires every night at midnight
      Persistent = true;    # Catches up immediately if the machine was offline
    };
    wantedBy = [ "timers.target" ];
  };
}


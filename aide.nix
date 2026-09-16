# aide.nix
{ config, pkgs, lib, ... }:

let
  # Compile the config text cleanly into a standalone file directly inside the Nix store
  aideConfig = pkgs.writeText "aide.conf" ''
    # Define verification database destinations
    database_in=file:/var/lib/aide/aide.db
    database_out=file:/var/lib/aide/aide.db.new
    gzip_dbout=yes

    # Define custom monitoring macro rule matrices
    MyCoreRules = p+i+n+u+g+s+m+c+sha256

    # Apply monitoring matrices to key critical system paths
    /boot        MyCoreRules
    /run/current-system/sw/bin MyCoreRules
    /etc         MyCoreRules
    
    # Explicitly ignore highly dynamic system/user runtime spaces 
    !/etc/mtab
    !/var/lib/aide
  '';
in
{
  environment.systemPackages = [ pkgs.aide ];

  # Automatically provision the state storage directory layout on startup
  systemd.tmpfiles.rules = [
    "d /var/lib/aide 0700 root root -"
  ];

  # Optional: Keep this if you still want a copy readable at /etc/aide.conf
  environment.etc."aide.conf".source = aideConfig;

  # AUTOMATED INITIALIZATION LOOP
  system.activationScripts.aide-init = {
    supportsDryActivation = true;
    text = ''
      if [ ! -f /var/lib/aide/aide.db ]; then
        echo "[aide] Initializing baseline integrity signature matrix database..."
        mkdir -p /var/lib/aide
        chmod 700 /var/lib/aide
        
        # Point directly to the immutable Nix store config path
        ${pkgs.aide}/bin/aide --init --config ${aideConfig} || true
        
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
      # Point cleanly to the exact store path definition
      ExecStart = "${pkgs.aide}/bin/aide --check --config ${aideConfig}";
      
      Nice = 19; 
      IOSchedulingClass = "idle"; 
    };
  };

  # 4. Automate the scanning intervals
  systemd.timers.aide-check = {
    description = "Trigger AIDE daily for machine file integrity tracking";
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
    };
    wantedBy = [ "timers.target" ];
  };
}


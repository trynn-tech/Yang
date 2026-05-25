# /etc/nixos/lab.nix
{ config, pkgs, lib, ... }:
let
  userName = "trynn";
  modelDir = "/home/${userName}/models";
  labDir = "/home/${userName}/lab/Re-L";
  primaryModelName = "qwen2.5-coder-7b-instruct-q6_k.gguf";
in {
  networking.firewall.allowedTCPPorts = [ 8081 8888 6379 ];

  environment.systemPackages = with pkgs; [
    podman-compose skopeo git python313 pipenv curl redis
  ];

  systemd.tmpfiles.rules = [
    "d ${labDir} 0755 ${userName} users -"
    "d ${modelDir} 0755 ${userName} users -"
  ];

  # =========================================================================
  # FLYWHEEL OPTIMIZATION: SYSTEMD AUTOMATED STORAGE CLEANING TIMER
  # =========================================================================
  systemd.services."podman-garbage-collector" = {
    description = "Automated Storage Flywheel: Aggressive Container Cache Pruning";
    path = [ pkgs.podman pkgs.coreutils ];
    script = ''
      echo "[*] Initiating automated local storage reclamation..."
      ${pkgs.podman}/bin/podman system prune -a --volumes --force
      echo "[+] System storage returned to base clean boundaries."
    '';
    serviceConfig = {
      Type = "oneshot";
      User = "root";
    };
  };

  systemd.timers."podman-garbage-collector" = {
    description = "Trigger Podman Storage Flywheel Daily at 04:00";
    timerConfig = {
      OnCalendar = "*-*-* 04:00:00";
      Persistent = true;
    };
    wantedBy = [ "timers.target" ];
  };

  # 1. The "Eyes": Local Search Engine (Greedy Lifecycle Management)
  systemd.services.podman-searxng = {
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" "podman-network-re-l.service" ];
    requires = [ "podman-network-re-l.service" ];
    serviceConfig = {
      Restart = "always";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "greedy-searxng-start" ''
        # Check if the container exists in any state (running or stopped)
        if ${pkgs.podman}/bin/podman ps -a --format "{{.Names}}" | grep -q "^searxng$"; then
          # If it exists but is stopped, simply wake it up
          if ! ${pkgs.podman}/bin/podman ps --format "{{.Names}}" | grep -q "^searxng$"; then
            echo "[*] Greedily resurrecting stopped searxng container context..."
            exec ${pkgs.podman}/bin/podman start -a searxng
          else
            echo "[+] Active searxng container already serving requests. Re-routing loop."
            exit 0
          fi
        else
          # Only build the container from scratch if it does not exist at all
          echo "[*] Container context missing. Initializing fresh searxng instance..."
          exec ${pkgs.podman}/bin/podman run --name searxng \
            --log-opt max-size=10m \
            --log-opt max-file=2 \
            --network re-l-net \
            -p 8888:8080 \
            -e "SEARXNG_SETTINGS_URL=/etc/searxng/settings.yml" \
            -e "SEARXNG_SEARCH_FORMATS=json" \
            docker.io/searxng/searxng:latest
        fi
      '';
      ExecStop = "${pkgs.podman}/bin/podman stop searxng";
    };
  };

  # 2. Model Provisioning (Self-Healing Weights Deployment)
  systemd.services.provision-re-l-models = {
    path = [ pkgs.wget pkgs.coreutils ];
    wantedBy = [ "multi-user.target" ];
    script = ''
      mkdir -p /home/${userName}/models/blobs
      if [ ! -f /home/${userName}/models/blobs/Meta-Llama-3.1-8B-Instruct-Q6_K.gguf ]; then
        echo "Downloading Architect weights..."
        wget -O /home/${userName}/models/blobs/Meta-Llama-3.1-8B-Instruct-Q6_K.gguf \
          https://huggingface.co/bartowski/Meta-Llama-3.1-8B-Instruct-GGUF/resolve/main/Meta-Llama-3.1-8B-Instruct-Q6_K.gguf
      fi

      cat <<EOF > /home/${userName}/models/architect.yaml
name: architect
parameters:
  model: blobs/Meta-Llama-3.1-8B-Instruct-Q6_K.gguf
  context_size: 4096
  gpu_layers: 28
  temperature: 0.2
  f16_kv: true
  mmap: true
EOF
    '';
  };

  # Global Hardware Passthrough Layer
  hardware.nvidia-container-toolkit.enable = true;

  #3. Core Ecosystem Containers (Redis, Core Environment, Browser Engine)
  virtualisation.oci-containers = {
    backend = "podman";
    containers = {
      "re-l-redis" = {
        image = "redis:7";
        cmd = [ "redis-server" "--requirepass" "myStrongPass" ];
        ports = [ "6379:6379" ];
        extraOptions = [ "--network=re-l-net" "--log-opt=max-size=10m" ];
      };
      #"re-l-core" = {
      #  image = "re-l-env:latest";
      #  volumes = [ "${labDir}:/app" ];
      #  workdir = "/app";
      #  cmd = [ "tail" "-f" "/dev/null" ];
      #  extraOptions = [ "--network=re-l-net" "--log-opt=max-size=10m" ];
      #};
      #"re-l-browser" = {
      #  image = "re-l-env:latest";
      #  volumes = [
      #    "${labDir}:/app"
      #    "/home/${userName}/.yuko:/home/node/.yuko"
      #    "/tmp/.X11-unix:/tmp/.X11-unix:ro"
      #  ];
      #  environment = {
      #    DISPLAY = ":0";
      #    XAUTHORITY = "/home/${userName}/.Xauthority";
      #  };
      #  workdir = "/app";
      #  cmd = [ "tail" "-f" "/dev/null" ];
      #  extraOptions = [
      #    "--network=re-l-net"
      #    "--ipc=host"
      #    "--device=/dev/dri:/dev/dri"
      #    "--log-opt=max-size=10m"
      #  ];
      #};
    };
  };

  # 4. Local-AI (Greedy Specialized Inference Core)
  systemd.services."podman-local-ai" = {
    description = "Local-AI Specialized GPU Container";
    after = [ "provision-re-l-models.service" "podman-network-re-l.service" ];
    requires = [ "podman-network-re-l.service" ];
    wantedBy = [ "multi-user.target" ];
    path = [ pkgs.podman pkgs.nvidia-container-toolkit pkgs.bash ];
    serviceConfig = {
      Restart = "always";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "greedy-local-ai-start" ''
        # Is the model server already tracking inside the container registry?
        if ${pkgs.podman}/bin/podman ps -a --format "{{.Names}}" | grep -q "^local-ai$"; then
          # If it exists but got knocked offline, warm it up instantly without pulling layers
          if ! ${pkgs.podman}/bin/podman ps --format "{{.Names}}" | grep -q "^local-ai$"; then
            echo "[*] Greedily warming up cold LocalAI engine cache..."
            exec ${pkgs.podman}/bin/podman start -a local-ai
          else
            echo "[+] LocalAI core active on port 8081. Intercepting execution stream."
            exit 0
          fi
        else
          echo "[*] LocalAI instance matrix missing. Initializing hardware boundaries..."
          exec ${pkgs.podman}/bin/podman run --name local-ai \
            --log-opt max-size=50m \
            --log-opt max-file=3 \
            --device nvidia.com/gpu=all \
            --network re-l-net \
            -p 8081:8080 \
            -v ${modelDir}/architect.yaml:/models/architect.yaml \
            -v ${modelDir}/blobs:/models/blobs \
            -e MODELS_PATH=/models \
            -e DEBUG=false \
            -e AUTODETECT_MODEL_CAPABILITIES=false \
            quay.io/go-skynet/local-ai:v2.25.0-cublas-cuda12
        fi
      '';
      ExecStop = "${pkgs.podman}/bin/podman stop local-ai";
    };
  };

  # 5. Shared Network Provisioning Unit
  systemd.services."podman-network-re-l" = {
    path = [ pkgs.podman ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.bash}/bin/bash -c '${pkgs.podman}/bin/podman network create re-l-net || true'";
    };
    wantedBy = [ "multi-user.target" ];
  };

  # 6. Dependency Synchronization Matrix
  systemd.services."podman-re-l-redis".after = [ "podman-network-re-l.service" ];
  #systemd.services."podman-re-l-core" = {
  #  after = [ "podman-re-l-redis.service" "podman-network-re-l.service" ];
  #  requires = [ "podman-re-l-redis.service" ];
  #};
  #systemd.services."podman-re-l-browser" = {
  #  after = [ "podman-re-l-redis.service" "podman-network-re-l.service" ];
  #  requires = [ "podman-network-re-l.service" ];
  #  wantedBy = [ "multi-user.target" ];
  #};
}

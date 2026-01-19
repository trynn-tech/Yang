# /etc/nixos/lab.nix
{ config, pkgs, lib, ... }:

let
  userName = "trynn";
  modelDir = "/home/${userName}/models";
  labDir = "/home/${userName}/lab/Re-L";
  primaryModelName = "qwen2.5-coder-7b-instruct-q6_k.gguf";
in {
  networking.firewall.allowedTCPPorts = [ 8081 8888];

  environment.systemPackages = with pkgs; [
    podman-compose skopeo git python313 pipenv curl
  ];

  systemd.tmpfiles.rules = [
    "d ${labDir} 0755 ${userName} users -"
    "d ${modelDir} 0755 ${userName} users -"
  ];

  # 1. The "Eyes": Local Search Engine
  systemd.services.podman-searxng = {
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    script = ''
      ${pkgs.podman}/bin/podman run --rm --name searxng \
        --network re-l-net \
        -p 8888:8080 \
        -e "SEARXNG_SETTINGS_URL=/etc/searxng/settings.yml" \
        -e "SEARXNG_SEARCH_FORMATS=json" \
        docker.io/searxng/searxng:latest
    '';
  };

  # 2. Model Provisioning (Self-Healing)
  systemd.services.provision-re-l-models = {
    path = [ pkgs.wget pkgs.coreutils ]; # Give the script the tools it needs
    wantedBy = [ "multi-user.target" ];
    script = ''
      mkdir -p /home/trynn/models/blobs
      
      # Download Llama 3.1 Architect (6.6GB) if missing
      if [ ! -f /home/trynn/models/blobs/Meta-Llama-3.1-8B-Instruct-Q6_K.gguf ]; then
        echo "Downloading Architect weights..."
        wget -O /home/trynn/models/blobs/Meta-Llama-3.1-8B-Instruct-Q6_K.gguf \
          https://huggingface.co/bartowski/Meta-Llama-3.1-8B-Instruct-GGUF/resolve/main/Meta-Llama-3.1-8B-Instruct-Q6_K.gguf
      fi

      # Provision the YAML Configs
      cat <<EOF > /home/trynn/models/architect.yaml
name: architect
parameters:
  model: blobs/Meta-Llama-3.1-8B-Instruct-Q6_K.gguf
  context_size: 8192
  gpu_layers: 33
  temperature: 0.7
EOF
    '';
  };

  hardware.nvidia-container-toolkit.enable = true;

  # 3. Redis & Core (Standard OCI Block)
  virtualisation.oci-containers = {
    backend = "podman";
    containers = {
      "re-l-redis" = {
        image = "redis:7";
        cmd = [ "redis-server" "--requirepass" "myStrongPass" ];
        ports = [ "6379:6379" ];
        extraOptions = [ "--network=re-l-net" ];
      };
      "re-l-core" = {
        image = "re-l-env:latest"; 
        volumes = [ "${labDir}:/app" ];
        workdir = "/app";
        cmd = [ "tail" "-f" "/dev/null" ];
        extraOptions = [ "--network=re-l-net" ];
        # We handle dependencies manually in section 5 to avoid "bad unit" errors
      };
    };
  };

  # 4. Local-AI (Manual Service)
  systemd.services."podman-local-ai" = {
    description = "Local-AI Specialized GPU Container";
    after = [ "provision-re-l-models.service" "podman-network-re-l.service" ];
    requires = [ "podman-network-re-l.service" ];
    wantedBy = [ "multi-user.target" ];
    path = [ pkgs.podman pkgs.nvidia-container-toolkit pkgs.bash ];
    serviceConfig = {
      Restart = "always";
      ExecStartPre = "-${pkgs.podman}/bin/podman rm -f local-ai";
      ExecStart = ''
        ${pkgs.podman}/bin/podman run --name local-ai \
          --device nvidia.com/gpu=all \
          --network re-l-net \
          -p 8081:8080 \
          -v ${modelDir}:/models \
          -e MODELS_PATH=/models \
          -e DEBUG=true \
          -e AUTODETECT_MODEL_CAPABILITIES=false \
          quay.io/go-skynet/local-ai:v2.25.0-cublas-cuda12
      '';
      ExecStop = "${pkgs.podman}/bin/podman stop local-ai";
    };
  };

  # 5. Network Service
  systemd.services."podman-network-re-l" = {
    path = [ pkgs.podman ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.bash}/bin/bash -c '${pkgs.podman}/bin/podman network create re-l-net || true'";
    };
    wantedBy = [ "multi-user.target" ];
  };

  # 6. Dependency Sequencing (The "Fix")
  systemd.services."podman-re-l-redis".after = [ "podman-network-re-l.service" ];
  systemd.services."podman-re-l-core" = {
    after = [ "podman-re-l-redis.service" "podman-network-re-l.service" ];
    requires = [ "podman-re-l-redis.service" ];
  };


}

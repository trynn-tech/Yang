# /etc/nixos/lab.nix
{ config, pkgs, lib, ... }:
let
  userName = "trynn";
  modelDir = "/home/${userName}/models";
  labDir = "/home/${userName}/lab/Re-L";

  # Define the configuration models declaratively via Nix
  architectConfig = {
    name = "openai/architect";
    backend = "llama-cpp";
    template = { chat = "llama3"; };
    parameters = {
      model = "blobs/Meta-Llama-3.1-8B-Instruct-Q6_K.gguf";
      context_size = 4096;
      gpu_layers = 28;
      temperature = 0.1;
      f16_kv = true;
      mmap = true;
    };
  };

  hermesConfig = {
    name = "openrouter/hermes-3-llama-3.1-8b";
    alias = [ "hermes" ];
    backend = "llama-cpp";
    template = { chat = "hermes"; };
    parameters = {
      model = "blobs/Hermes-3-Llama-3.1-8B.Q6_K.gguf";
      context_size = 16384;
      gpu_layers = 28;
      temperature = 0.7;
      f16_kv = true;
      mmap = true;
    };
  };

  # Convert the Nix attribute sets directly into clean YAML files in the Nix store
  architectYaml = pkgs.writers.writeYAML "architect.yaml" architectConfig;
  hermesYaml = pkgs.writers.writeYAML "hermes.yaml" hermesConfig;

in {
  networking.firewall.allowedTCPPorts = [ 8081 8888 6379 ];

  environment.systemPackages = with pkgs; [
    podman-compose skopeo git python313 pipenv curl redis
  ];

  systemd.tmpfiles.rules = [
    "d ${labDir} 0755 ${userName} users -"
    "d ${modelDir} 0755 ${userName} users -"
    "d ${modelDir}/blobs 0755 ${userName} users -"
    "d ${modelDir}/configs 0755 ${userName} users -"
  ];

  # 1. Network Provisioning Unit
  systemd.services."podman-network-re-l" = {
    path = [ pkgs.podman ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.bash}/bin/bash -c '${pkgs.podman}/bin/podman network exists re-l-net || ${pkgs.podman}/bin/podman network create re-l-net'";
      ExecStop = "${pkgs.podman}/bin/podman network rm -f re-l-net";
    };
    wantedBy = [ "multi-user.target" ];
  };

  # 2. Model Provisioning (Self-Healing Dual Weights Downloader)
  systemd.services.provision-re-l-models = {
    description = "Declarative Model Provisioning Guard";
    path = [ pkgs.wget pkgs.coreutils ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig.Type = "oneshot";
    script = ''
      # A. Download Architect weights if missing
      if [ ! -f ${modelDir}/blobs/Meta-Llama-3.1-8B-Instruct-Q6_K.gguf ]; then
        echo "Downloading Architect weights..."
        wget -O ${modelDir}/blobs/Meta-Llama-3.1-8B-Instruct-Q6_K.gguf \
          "https://huggingface.co/lmstudio-community/Meta-Llama-3.1-8B-Instruct-GGUF/resolve/main/Meta-Llama-3.1-8B-Instruct-Q6_K.gguf"
      fi

      # B. Download Hermes weights if missing
      if [ ! -f ${modelDir}/blobs/Hermes-3-Llama-3.1-8B.Q6_K.gguf ]; then
        echo "Downloading Hermes weights..."
        wget -O ${modelDir}/blobs/Hermes-3-Llama-3.1-8B.Q6_K.gguf \
          "https://huggingface.co/NousResearch/Hermes-3-Llama-3.1-8B-GGUF/resolve/main/Hermes-3-Llama-3.1-8B.Q6_K.gguf"
      fi

      # C. Safely symlink or copy configurations from the immutable Nix store
      cp -f ${architectYaml} ${modelDir}/configs/architect.yaml
      cp -f ${hermesYaml} ${modelDir}/configs/hermes.yaml

      chown -R ${userName}:users ${modelDir}
      chmod -R 755 ${modelDir}
      find ${modelDir} -type f -exec chmod 644 {} +
    '';
  };

  # Global Hardware Passthrough Layer
  hardware.nvidia-container-toolkit.enable = true;

  # 3. Core Ecosystem Infrastructure Orchestration
  virtualisation.oci-containers = {
    backend = "podman";
    containers = {
      "re-l-redis" = {
        image = "redis:7";
        cmd = [ "redis-server" "--requirepass" "myStrongPass" ];
        ports = [ "6379:6379" ];
        extraOptions = [ "--network=re-l-net" "--log-opt=max-size=10m" ];
      };

      "searxng" = {
        image = "docker.io/searxng/searxng:latest";
        ports = [ "8888:8080" ];
        environment = {
          SEARXNG_SETTINGS_URL = "/etc/searxng/settings.yml";
          SEARXNG_SEARCH_FORMATS = "json";
        };
        extraOptions = [ 
          "--network=re-l-net" 
          "--log-opt=max-size=10m" 
          "--log-opt=max-file=2" 
        ];
      };

      "local-ai" = {
        image = "docker.io/localai/localai:v2.25.0-cublas-cuda12";
        ports = [ "8081:8080" ];
        environment = {
          MODELS_PATH = "/models";
          DEBUG = "true";
          AUTODETECT_MODEL_CAPABILITIES = "false";
        };
        volumes = [
          "${modelDir}/configs:/models"
          "${modelDir}/blobs:/models/blobs"
        ];
        extraOptions = [
          "--network=re-l-net"
          "--log-opt=max-size=50m"
          "--log-opt=max-file=3"
          "--device=nvidia.com/gpu=all" # Purely declarative device toolkit identification
          "--annotation=run.oci.keep_original_groups=1"
          "--security-opt=label=disable"
          "--user=0:0"
        ];
      };
    };
  };

  # 4. Lifecycle Management Layer
  # Adjust order execution constraints & inject automatic configuration hot-reload triggers
  systemd.services."podman-re-l-redis".after = [ "podman-network-re-l.service" ];
  systemd.services."podman-searxng".after    = [ "podman-network-re-l.service" ];

  systemd.services."podman-local-ai" = {
    after = [
      "provision-re-l-models.service"
      "podman-network-re-l.service"
      "podman-re-l-redis.service"
      "podman-searxng.service"
    ];
    requires = [
      "provision-re-l-models.service"
      "podman-network-re-l.service"
    ];
    
    # Automatically triggers a clean restart of the container if your Nix model definitions change
    restartTriggers = [ architectYaml hermesYaml ];
  };
}

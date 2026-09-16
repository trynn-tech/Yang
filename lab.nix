# /etc/nixos/lab.nix
{ config, pkgs, lib, ... }:

let
  userName = "trynn";
  modelDir = "/home/${userName}/models";
  labDir = "/home/${userName}/lab/Re-L";

  # ==========================================
  # TOGGLE: 
  #   - true  = Activate Phi-3.5-mini
  #   - false = Activate Qwen2.5-Coder-7B
  # ==========================================
  runPhiMode = false;

  # Active model configuration based on toggle
  activeConfig = if runPhiMode then {
    name = "gpt-5";
    backend = "llama-cpp";
    parameters = {
      model = "blobs/Phi-3.5-mini-instruct-Q4_K_M.gguf";
      context_size = 8192;
      gpu_layers = -1;
      temperature = 0.2;
      f16_kv = true;
      mmap = true;
    };
  } else {
    name = "gpt-5";
    backend = "llama-cpp";
    parameters = {
      # Point to the first shard; llama.cpp automatically binds 00002-of-00002
      model = "blobs/qwen2.5-coder-7b-instruct-q5_k_m-00001-of-00002.gguf";
      context_size = 8192;
      gpu_layers = -1;
      temperature = 0.1;
      f16_kv = true;
      mmap = true;
    };
  };

  activeYaml = pkgs.writers.writeYAML "gpt-5.yaml" activeConfig;
in {
  networking.firewall.allowedTCPPorts = [ 8081 8888 ];

  environment.systemPackages = with pkgs; [
    podman-compose skopeo git python313 pipenv curl wget
  ];

  systemd.tmpfiles.rules = [
    "d ${labDir} 0755 ${userName} users -"
    "d ${modelDir} 0755 ${userName} users -"
    "d ${modelDir}/blobs 0755 ${userName} users -"
    "d ${modelDir}/configs 0755 ${userName} users -"
  ];

  systemd.services."podman-network-re-l" = {
    path = [ pkgs.podman ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.bash}/bin/bash -c '${pkgs.podman}/bin/podman network exists re-l-net || ${pkgs.podman}/bin/podman network create re-l-net'";
      ExecStop = "${pkgs.bash}/bin/bash -c '${pkgs.podman}/bin/podman network rm -f re-l-net'";
    };
    wantedBy = [ "multi-user.target" ];
  };

  systemd.services.provision-re-l-models = {
    description = "Declarative Model Provisioning Guard";
    path = [ pkgs.curl pkgs.wget pkgs.coreutils ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig.Type = "oneshot";
    script = ''
      mkdir -p ${modelDir}/blobs
      
      # Clean out old configs so LocalAI never sees stale YAMLs
      rm -f ${modelDir}/*.yaml

      # Permanently cache Phi-3.5 if missing
      TARGET_PHI="${modelDir}/blobs/Phi-3.5-mini-instruct-Q4_K_M.gguf"
      if [ ! -s "$TARGET_PHI" ]; then
        echo "Downloading Phi-3.5-mini-instruct GGUF..."
        rm -f "$TARGET_PHI"
        curl -sSL -A "Mozilla/5.0" -o "$TARGET_PHI" \
          "https://huggingface.co/bartowski/Phi-3.5-mini-instruct-GGUF/resolve/main/Phi-3.5-mini-instruct-Q4_K_M.gguf" || true
      fi

      # Provision Qwen2.5-Coder split shards
      SHARD1="${modelDir}/blobs/qwen2.5-coder-7b-instruct-q5_k_m-00001-of-00002.gguf"
      SHARD2="${modelDir}/blobs/qwen2.5-coder-7b-instruct-q5_k_m-00002-of-00002.gguf"

      if [ ! -s "$SHARD1" ]; then
        echo "Downloading Qwen2.5-Coder shard 1 of 2..."
        curl -sSL -A "Mozilla/5.0" -o "$SHARD1" \
          "https://huggingface.co/Qwen/Qwen2.5-Coder-7B-Instruct-GGUF/resolve/main/qwen2.5-coder-7b-instruct-q5_k_m-00001-of-00002.gguf?download=true" || true
      fi

      if [ ! -s "$SHARD2" ]; then
        echo "Downloading Qwen2.5-Coder shard 2 of 2..."
        curl -sSL -A "Mozilla/5.0" -o "$SHARD2" \
          "https://huggingface.co/Qwen/Qwen2.5-Coder-7B-Instruct-GGUF/resolve/main/qwen2.5-coder-7b-instruct-q5_k_m-00002-of-00002.gguf?download=true" || true
      fi

      # Write only the active configuration file for the chosen model
      cp -f ${activeYaml} ${modelDir}/gpt-5.yaml
      chown -R ${userName}:users ${modelDir}
      chmod -R 755 ${modelDir}
      find ${modelDir} -type f -exec chmod 644 {} +
    '';
  };

  hardware.nvidia-container-toolkit.enable = true;

  virtualisation.oci-containers = {
    backend = "podman";
    containers = {
      "searxng" = {
        image = "docker.io/searxng/searxng:latest";
        ports = [ "8888:8080" ];
        environment = {
          SEARXNG_SETTINGS_URL = "/etc/searxng/settings.yml";
          SEARXNG_SEARCH_FORMATS = "json";
        };
        extraOptions = [ "--network=re-l-net" "--log-opt=max-size=10m" "--log-opt=max-file=2" ];
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
          "${modelDir}:/models"
        ];
        extraOptions = [
          "--network=re-l-net"
          "--log-opt=max-size=50m"
          "--log-opt=max-file=3"
          "--device=nvidia.com/gpu=all"
          "--annotation=run.oci.keep_original_groups=1"
          "--security-opt=label=disable"
          "--user=0:0"
        ];
      };
    };
  };

  systemd.services."podman-searxng".after = [ "podman-network-re-l.service" ];

  systemd.services."podman-local-ai" = {
    after = [
      "provision-re-l-models.service"
      "podman-network-re-l.service"
      "podman-searxng.service"
    ];
    requires = [
      "provision-re-l-models.service"
      "podman-network-re-l.service"
    ];
    restartTriggers = [ activeYaml ];
  };
}

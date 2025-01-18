#!/usr/bin/env bash
# set -e




# Usage:
#
# 1. Launch cluster in forever mode:
#    ./run_cluster_compose.sh launch forever [LEADER_CMD] [DATASET_CMD]
#
#    Example:
#    ./run_cluster_compose.sh launch forever "python3 leader_script.py" ""
#    
#    This starts:
#    - vllm container running Ray (head or worker based on IP)
#    - leaderexec container that runs LEADER_CMD if it's the leader
#    - tunnel container that runs start_tunnel.sh if it's the leader 
#    - dataset container that stays idle
#    Containers keep running until you stop them with 'docker compose down'
#
# 2. Launch cluster in dataset mode:
#    ./run_cluster_compose.sh launch dataset [LEADER_CMD] [DATASET_CMD]
#    
#    Example:
#    ./run_cluster_compose.sh launch dataset "echo prep" "python3 dataset_job.py"
#
#    This:
#    - Starts all containers like forever mode
#    - Leader's dataset container runs DATASET_CMD
#    - When dataset container finishes, tears down entire cluster
#
# Environment:
# - HEAD_NODE_ADDRESS: IP of leader node (auto-detected)
# - CURRENT_IP: IP of this node (auto-detected)
# - MODE: 'forever' or 'dataset'
# - LEADER_CMD: Command to run on leader's vllm container
# - DATASET_CMD: Dataset processing command to run
# - HF_TOKEN: Optional Hugging Face token

# Implementation:
# - Single Dockerfile builds base image
# - docker-compose.yml defines 4 services with different roles
# - Each container runs this script with 'entrypoint'
# - Script checks SERVICE_MODE and runs appropriate logic
# - Leader node runs extra commands via docker exec

PATH_TO_HF_HOME=~/.cache/huggingface
export PATH_TO_HF_HOME

check_docker_sudo() {
  if ! docker info >/dev/null 2>&1; then
    if ! sudo docker info >/dev/null 2>&1; then
      echo "Error: Cannot run docker with or without sudo"
      exit 1
    fi
    echo "Using sudo for docker commands"
    DOCKER_CMD="sudo docker"
    COMPOSE_CMD="sudo docker-compose"
  else
    DOCKER_CMD="docker"
    COMPOSE_CMD="docker-compose"
  fi
}

cat << "EOF" > docker-compose.yml
version: '3.7'
services:
  vllm:
    image: tpu-vm-base
    container_name: vllm_container
    network_mode: host
    privileged: true
    shm_size: 10.24g
    entrypoint: ["/bin/bash"]
    environment:
      - SERVICE_MODE=vllm
      - MODE=${MODE}
      - HEAD_NODE_ADDRESS=${HEAD_NODE_ADDRESS}
      - CURRENT_IP=${CURRENT_IP}
      - HF_TOKEN=${HF_TOKEN}
      - GLOO_SOCKET_IFNAME=ens8
      - VLLM_XLA_CACHE_PATH=/mnt/gcs_bucket/xla_cache
    volumes:
      - /home/${USER}/vllm:/workspace/vllm
      - /dev/shm/gcs_cache:/dev/shm/gcs_cache
      - ${PATH_TO_HF_HOME:-~/.cache/huggingface}:/root/.cache/huggingface

  leaderexec:
    image: tpu-vm-base
    container_name: leaderexec_container
    depends_on:
      - vllm
    network_mode: host
    environment:
      - SERVICE_MODE=leaderexec
      - MODE=${MODE}
      - HEAD_NODE_ADDRESS=${HEAD_NODE_ADDRESS}
      - CURRENT_IP=${CURRENT_IP}
      - LEADER_CMD=${LEADER_CMD}
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock

  tunnel:
    image: tpu-vm-base
    container_name: tunnel_container
    depends_on:
      - vllm
    network_mode: host
    environment:
      - SERVICE_MODE=tunnel
      - MODE=${MODE}
      - HEAD_NODE_ADDRESS=${HEAD_NODE_ADDRESS}
      - CURRENT_IP=${CURRENT_IP}
      - PORTR_KEY=${PORTR_KEY}
    volumes:
      - /home/${USER}/vllm:/workspace/vllm

  dataset:
    image: tpu-vm-base
    container_name: dataset_container
    depends_on:
      - vllm
    network_mode: host
    environment:
      - SERVICE_MODE=dataset
      - MODE=${MODE}
      - HEAD_NODE_ADDRESS=${HEAD_NODE_ADDRESS}
      - CURRENT_IP=${CURRENT_IP}
      - DATASET_CMD=${DATASET_CMD}
    volumes:
      - /home/${USER}/vllm:/workspace/vllm
EOF
# Container roles:
# - vllm: Main Ray container
# - leaderexec: Runs leader commands in vllm container 
# - tunnel: Runs tunnel script on leader
# - dataset: Processes dataset on leader

# Environment variables:
# - SERVICE_MODE: Container role (vllm|leaderexec|tunnel|dataset)
# - MODE: Run mode (dataset|forever)

###############################################################################
# Usage:
# ./run_cluster_compose.sh launch (dataset|forever) "[LEADER_CMD]" "[DATASET_CMD]"
#   - Launches containers via Docker Compose
# ./run_cluster_compose.sh entrypoint
#   - Container entrypoint, reads SERVICE_MODE
###############################################################################


sync_devices() {
  # Sync devices if needed
  python3.10 -c "
import jax
from jax.experimental.multihost_utils import sync_global_devices
sync_global_devices('bla')
print('Process index:', jax.process_index())
"
}

maybe_clear_cache() {
  # If gcs_cache is bigger than 150GB
  if [ -d "/dev/shm/gcs_cache" ] && [ "$(sudo du -s /dev/shm/gcs_cache | cut -f1)" -gt 137957972 ]; then
    echo "[vllm] Clearing /dev/shm/gcs_cache ($SIZE kb)"
    sudo rm -rf /dev/shm/gcs_cache
    sudo mkdir -p /dev/shm/gcs_cache
    sudo chmod 777 /dev/shm/gcs_cache
    sudo chown -R "$USER":"$USER" /dev/shm/gcs_cache
  fi
}


build_docker_image() {
  local image="$1"
  if ! sudo docker images | grep -q "$image"; then
    echo "Building image: $image"
    (cd ~/vllm && sudo docker build -t "$image" -f Dockerfile.tpu .)
  fi
}


if [ "$1" = "launch" ]; then
  #############################################################################
  #                            HOST ORCHESTRATION
  #############################################################################
  MODE="$2"
  LEADER_CMD="$3"
  DATASET_CMD="$4"

  if [ -z "$MODE" ]; then
    echo "Usage: $0 launch (dataset|forever) [LEADER_CMD] [DATASET_CMD]"
    exit 1
  fi
  cd ~/vllm
  (cd ~/vllm && git pull)

  # Suppose we discover addresses (head vs. worker). 
  # Example: HEAD_NODE_ADDRESS via a script or from environment:
  source ~/.bashrc
  export HEAD_NODE_ADDRESS="$(python3.10 examples/leader_election.py 2>/dev/null || echo '127.0.0.1')"
  export CURRENT_IP="$(curl -s https://checkip.amazonaws.com)"
  echo "Current IP address: ${CURRENT_IP}"

  # Export to the environment for docker-compose.yml
  export MODE
  export LEADER_CMD
  export DATASET_CMD
  export PORTR_KEY="$(bash -ic 'source ~/.bashrc; echo $PORTR_KEY')"
  export HF_TOKEN="$(bash -ic 'source ~/.bashrc; echo $HF_TOKEN')"
  # Clear /dev/shm/gcs_cache if large
  sync_devices
  maybe_clear_cache
  # Optionally define HF_TOKEN here if needed:

  echo "==========================================="
  echo "[HOST] Launching cluster with Docker Compose"
  echo "MODE=$MODE"
  echo "HEAD_NODE_ADDRESS=$HEAD_NODE_ADDRESS"
  echo "CURRENT_IP=$CURRENT_IP"
  echo "LEADER_CMD=$LEADER_CMD"
  echo "DATASET_CMD=$DATASET_CMD"
  echo "==========================================="

  # Add this line early in the launch section
  check_docker_sudo

  # Start all services in the background
  build_docker_image tpu-vm-base
  $COMPOSE_CMD up -d

  # If dataset mode: wait for the 'dataset' container to finish, then tear down
  if [ "$MODE" = "dataset" ]; then
    echo "[HOST] dataset mode => waiting for dataset_container to finish..."
    echo "[HOST] To view logs from all containers in real-time, run:"
    echo "    $COMPOSE_CMD logs -f"
    $DOCKER_CMD wait dataset_container
    echo "[HOST] dataset_container finished => shutting down entire cluster..."
    $COMPOSE_CMD down
  else
    echo "[HOST] forever mode => containers keep running."
    echo "To view logs from all containers in real-time, run:"
    echo "    $COMPOSE_CMD logs -f"
    echo "To stop all containers, run:"
    echo "    $COMPOSE_CMD down"
  fi
  exit 0

elif [ "$1" = "entrypoint" ]; then
  #############################################################################
  #                          CONTAINER ENTRYPOINT
  #############################################################################
  echo "[CONTAINER] SERVICE_MODE=$SERVICE_MODE  MODE=$MODE"
  # Common environment logic here, e.g., updating / installing in container

  case "$SERVICE_MODE" in
    ###########################################################################
    # 1) vllm container: sets up the VLLM environment, runs Ray, blocks forever
    ###########################################################################
    vllm)
      echo "[vllm] Starting Ray..."
      
      # Setup workspace
      cd /workspace/vllm
      git config --global --add safe.directory /workspace/vllm
      git pull
      bash gcs_fuse_install.sh
      
      
      # Build the Ray command (head vs. worker)
      RAY_CMD="ray start --block --num-cpus=220 --resources='{\"TPU\":4}'"
      if [ "$CURRENT_IP" = "$HEAD_NODE_ADDRESS" ]; then
        RAY_CMD+=" --head --port=6379"
      else
        RAY_CMD+=" --address=${HEAD_NODE_ADDRESS}:6379"
      fi
      echo "[vllm] $RAY_CMD"
      
      # Run Ray (blocks)
      exec $RAY_CMD
      ;;

    ###########################################################################
    # 2) leaderexec container: if I'm leader, run `LEADER_CMD` inside the vllm
    ###########################################################################
    leaderexec)
      # Add docker sudo check
      check_docker_sudo
      
      if [ "$CURRENT_IP" = "$HEAD_NODE_ADDRESS" ] && [ -n "$LEADER_CMD" ]; then
        echo "[leaderexec] I am leader => docker exec in vllm_container: $LEADER_CMD"
        $DOCKER_CMD exec -d vllm_container /bin/bash -c "$LEADER_CMD"
      else
        echo "[leaderexec] Not leader or no LEADER_CMD => do nothing."
      fi
      if [ "$MODE" = "forever" ]; then
        echo "[leaderexec] FOREVER => sleeping..."
        while true; do sleep 3600; done
      else
        echo "[leaderexec] Exiting for MODE=$MODE"
        exit 0
      fi
      ;;

    ###########################################################################
    # 3) tunnel container: if I'm leader, run tunnel script
    ###########################################################################
    tunnel)
      if [ "$CURRENT_IP" = "$HEAD_NODE_ADDRESS" ]; then
        echo "[tunnel] I'm leader => starting tunnel"
        
        /workspace/vllm/portr auth set --token "$PORTR_KEY" --remote ohadrubin.com

        while true; do
          /workspace/vllm/portr http 8000 -s "$HOSTNAME"
          echo "Connection lost, reconnecting in 5 seconds..."
          sleep 5
        done
      else
        echo "[tunnel] Not leader => do nothing."
        while true; do sleep 3600; done
      fi
      ;;

    ###########################################################################
    # 4) dataset container: if leader + dataset mode => run the dataset logic
    ###########################################################################
    dataset)
      if [ "$MODE" != "dataset" ]; then
        echo "[dataset] Not dataset mode => sleep."
        while true; do sleep 3600; done
      fi

      if [ "$CURRENT_IP" != "$HEAD_NODE_ADDRESS" ]; then
        echo "[dataset] Worker => idle, waiting for leader to finish."
        while true; do sleep 3600; done
      fi

      # If we're here => leader + dataset
      echo "[dataset] Leader + dataset => run job."
      if [ -n "$DATASET_CMD" ]; then
        echo "[dataset] Running user DATASET_CMD: $DATASET_CMD"
        /bin/bash -c "$DATASET_CMD"
      fi

      # Example: run your dataset logic
    #   echo "[dataset] Example run_on_dataset_async.py job..."
    #   cd /workspace/vllm
    #   python3 examples/run_on_dataset_async.py \
    #     --dataset_name iohadrubin/reorder_thoughts_v1 \
    #     --config_name default \
    #     --num_workers 16 \
    #     --max_tokens 4096 \
    #     --suffix _v3 \
    #     --verbose True \
    #     --temperature 0 \
    #     --split train \
    #     --drop_last_msg True

      echo "[dataset] Done => exit container."
      exit 0
      ;;

    ###########################################################################
    # Unknown SERVICE_MODE
    ###########################################################################
    *)
      echo "[entrypoint] ERROR: Unknown SERVICE_MODE=$SERVICE_MODE"
      exit 1
      ;;
  esac

else
  # bash run_cluster_compose.sh launch forever "vllm serve /mnt/gcs_bucket/AI2_EasyLM/v48_remat_blockTrue_seq_length4096_stsFalse_size70b  --max-model-len 16384 --tensor-parallel-size 8 --pipeline_parallel_size 1 --distributed-executor-backend ray --max-num-seqs 16 --served-model-name meta-llama/Llama-3.1-70B-Instruct" ""
  #############################################################################
  # If we get here => We didn't call 'launch' or 'entrypoint'
  #############################################################################
  echo "Usage:"
  echo "  $0 launch (dataset|forever) [LEADER_CMD] [DATASET_CMD]"
  echo "  (inside container) => $0 entrypoint"
  exit 1
fi

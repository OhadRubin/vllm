#!/bin/bash
(cd ~/vllm && git pull)
# Get the current IP address
CURRENT_IP=$(curl https://checkip.amazonaws.com)
echo "Current IP address: ${CURRENT_IP}"

# Check for minimum number of required arguments
if [ $# -lt 4 ]; then
    echo "Usage: $0 docker_image head_node_address hf_token path_to_hf_home [additional_args...]"
    exit 1
fi

 

# Assign the first three arguments and shift them away
DOCKER_IMAGE="$1"
HEAD_NODE_ADDRESS="$2"
HF_TOKEN="$3"  # Should be --head or --worker
PATH_TO_HF_HOME="$4"
shift 4

# Additional arguments are passed directly to the Docker command
ADDITIONAL_ARGS=("$@")


# Define a function to cleanup on EXIT signal
cleanup() {
    sudo docker stop node
    sudo docker rm node
}
trap cleanup EXIT

# Command setup for head or worker node
RAY_START_CMD="ray start --block --num-cpus=220 --resources='{\"TPU\": 4}'"
if [ "${CURRENT_IP}" == "${HEAD_NODE_ADDRESS}" ]; then
    RAY_START_CMD+=" --head --port=6379"
else
    RAY_START_CMD+=" --address=${HEAD_NODE_ADDRESS}:6379"
fi

# cmd sudo docker build -t tpu-vm-base2 -f Dockerfile.tpu .
# Run the docker command with the user specified parameters and additional arguments



# docker run -v $(pwd):/workspace/vllm -it your-image-name




# source ~/vllm/gcs_fuse_install.sh
# - name: VLLM_XLA_CACHE_PATH
# value: "/data"
# -it \

sudo mkdir -p /dev/shm/gcs_cache
sudo chmod 777 /dev/shm/gcs_cache
sudo docker run \
    -v /home/$USER/vllm:/workspace/vllm \
    --entrypoint /bin/bash \
    --network host \
    --name node \
    --shm-size 10.24g \
    --privileged \
    -e HF_TOKEN="${HF_TOKEN}" \
    -e GLOO_SOCKET_IFNAME=ens8 \
    -e VLLM_XLA_CACHE_PATH=/mnt/gcs_bucket/xla_cache \
    -v "${PATH_TO_HF_HOME}:/root/.cache/huggingface" \
    -v "/dev/shm/gcs_cache:/dev/shm/gcs_cache" \
    "${ADDITIONAL_ARGS[@]}" \
    "${DOCKER_IMAGE}" -c "cd /workspace/vllm && git config --global --add safe.directory /workspace/vllm  && git pull  &&  bash gcs_fuse_install.sh && ${RAY_START_CMD}"

# git clone https://github.com/pytorch/xla.git

# use this to get into the container
# cmd bash /home/ohadr/vllm/examples/run_cluster.sh tpu-vm-base2 35.186.69.167 <hftoken> /dev/shm/huggingface
# docker exec -it node /bin/bash
# export  PT_XLA_DEBUG_LEVEL=2
# vllm serve meta-llama/Llama-3.1-8B-Instruct  --max-model-len 1024 --max-num-seqs 8  --distributed-executor-backend ray --tensor-parallel-size 4
# vllm serve /mnt/gcs_bucket/models/Llama-3.1-70B-Instruct/  --max-model-len 16384 --tensor-parallel-size 8 --pipeline_parallel_size 1 --distributed-executor-backend ray --max-num-seqs 1 --served-model-name meta-llama/Llama-3.1-70B-Instruct --enable_prefix_caching 

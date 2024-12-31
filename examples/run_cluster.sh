#!/bin/bash
# bash /home/ohadr/vllm/examples/run_cluster.sh
(cd ~/vllm && git pull)
# Get the current IP address
CURRENT_IP=$(curl https://checkip.amazonaws.com)
echo "Current IP address: ${CURRENT_IP}"

 
source ~/.bashrc
# Assign the first three arguments and shift them away
DOCKER_IMAGE=tpu-vm-base
HEAD_NODE_ADDRESS=$(python3.10 examples/leader_election.py)
PATH_TO_HF_HOME=~/.cache/huggingface


# Additional arguments are passed directly to the Docker command
ADDITIONAL_ARGS=("$@")

# rm -rf ~/.cache/huggingface
# Define a function to cleanup on EXIT signal
cleanup() {
    sudo docker stop node
    sudo docker rm node
    # pkill -f -9 portr
    # pkill -f -9 start_tunnel.sh
}
trap cleanup EXIT


# Command setup for head or worker node
RAY_START_CMD="ray start --block --num-cpus=220 --resources='{\"TPU\": 4}'"
if [ "${CURRENT_IP}" == "${HEAD_NODE_ADDRESS}" ]; then
    RAY_START_CMD+=" --head --port=6379"
else
    RAY_START_CMD+=" --address=${HEAD_NODE_ADDRESS}:6379"
fi



# setup cache folder
# sudo mkdir -p /dev/shm/gcs_cache
# sudo chmod 777 /dev/shm/gcs_cache
# sudo chown -R $USER:$USER /dev/shm/gcs_cache
# sudo chown -R $USER:$USER /mnt/gcs_bucket
# source gcs_fuse_install.sh
# -v "${PATH_TO_HF_HOME}:/root/.cache/huggingface" \
# gcs_fuse_install.sh sets up the actual mount point on /mnt/gcs_bucket
sudo docker run  \
    -d \
    -v /home/$USER/vllm:/workspace/vllm \
    --entrypoint /bin/bash \
    --network host \
    --name node \
    --shm-size 10.24g \
    --privileged \
    -e HF_TOKEN="${HF_TOKEN}" \
    -e GLOO_SOCKET_IFNAME=ens8 \
    -e VLLM_XLA_CACHE_PATH=/mnt/gcs_bucket/xla_cache \
    -v "/dev/shm/gcs_cache:/dev/shm/gcs_cache" \
    "${DOCKER_IMAGE}" -c "cd /workspace/vllm && git config --global --add safe.directory /workspace/vllm  && git pull  &&  bash gcs_fuse_install.sh && ${RAY_START_CMD}"
echo "done loading ray process"
# while true; do
#     sleep 60
# done

if [ "${CURRENT_IP}" == "${HEAD_NODE_ADDRESS}" ]; then
    # Wait for container to be ready
    # trap cleanup EXIT
    # bash start_tunnel.sh & 
    # Install requirements and start server
    sleep 10
    # Convert array to space-separated string and wrap in quotes
    COMMAND="${ADDITIONAL_ARGS[*]}"
    
    sudo docker exec -it node /bin/bash -c "$COMMAND"
    # sudo docker exec -it node /bin/bash -c "vllm serve /mnt/gcs_bucket/models/Llama-3.1-70B/  --max-model-len 16384 --tensor-parallel-size 8 --pipeline_parallel_size 1 --distributed-executor-backend ray --max-num-seqs 16 --served-model-name meta-llama/Llama-3.1-70B --chat-template examples/base.jinja"
else
    while true; do
        sleep 60
    done

fi

# git clone https://github.com/pytorch/xla.git

# use this to get into the container
# cmd bash /home/ohadr/vllm/examples/run_cluster.sh tpu-vm-base2 35.186.69.167 <hftoken> /dev/shm/huggingface
# docker exec -it node /bin/bash
# export  PT_XLA_DEBUG_LEVEL=2
# vllm serve meta-llama/Llama-3.1-8B-Instruct  --max-model-len 1024 --max-num-seqs 8  --distributed-executor-backend ray --tensor-parallel-size 4
# vllm serve /mnt/gcs_bucket/models/Llama-3.1-70B-Instruct/  --max-model-len 16384 --tensor-parallel-size 8 --pipeline_parallel_size 1 --distributed-executor-backend ray --max-num-seqs 1 --served-model-name meta-llama/Llama-3.1-70B-Instruct --enable_prefix_caching 



# Download and extract Docker binaries
wget https://download.docker.com/linux/static/stable/x86_64/docker-24.0.7.tgz
tar xzvf docker-24.0.7.tgz

# Remove existing Docker binaries
sudo rm /usr/bin/containerd /usr/bin/containerd-shim-runc-v2 /usr/bin/ctr /usr/bin/docker /usr/bin/dockerd /usr/bin/docker-init /usr/bin/docker-proxy /usr/bin/runc

# Install new Docker binaries
sudo cp docker/* /usr/bin/

# Kill existing Docker processes and clean up
sudo pkill -f -9 docker
sudo rm /var/run/docker.pid

# Download and setup Docker Compose
sudo curl -SL https://github.com/docker/compose/releases/download/v2.23.0/docker-compose-linux-x86_64 -o /usr/local/bin/docker-compose
sudo ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Setup Docker group and permissions
# Add user to docker group if not already a member
if ! groups $USER | grep -q docker; then
  sudo usermod -aG docker $USER
  newgrp docker
fi

# Set permissions if .docker directory exists
if [ -d "$HOME/.docker" ]; then
  sudo chown "$USER":"$USER" "$HOME/.docker" -R
  sudo chmod g+rwx "$HOME/.docker" -R
fi

# Create Docker daemon configuration
sudo mkdir -p /etc/docker
sudo tee /etc/docker/daemon.json <<EOF
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF

# Setup Docker service
sudo tee /etc/systemd/system/docker.service <<EOF
[Unit]
Description=Docker Application Container Engine
Documentation=https://docs.docker.com
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
ExecStart=/usr/bin/dockerd
ExecReload=/bin/kill -s HUP \$MAINPID
TimeoutSec=0
RestartSec=2
Restart=always
StartLimitBurst=3
StartLimitInterval=60s
LimitNOFILE=infinity
LimitNPROC=infinity
LimitCORE=infinity
TasksMax=infinity
Delegate=yes
KillMode=process

[Install]
WantedBy=multi-user.target
EOF

# Enable and start Docker services
sudo systemctl daemon-reload
sudo systemctl enable docker.service
sudo systemctl enable containerd.service
sudo systemctl start docker.service

# Cleanup downloaded files
rm docker-24.0.7.tgz
rm -rf docker/


git clone https://github.com/OhadRubin/vllm.git
cd vllm
sudo docker build -t tpu-vm-base2 -f Dockerfile.tpu .


export HF_TOKEN=


mkdir -p /dev/shm/huggingface


sudo docker run --entrypoint /bin/bash --privileged --net host --shm-size=16G -e HF_TOKEN=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 -v /dev/shm/huggingface:/root/.cache/huggingface -it tpu-vm-base2 /bin/bash -c ray start --block --port=6379 --address=35.186.1.120:6379

 -c "ray start --block --address=10.130.0.187:6379"
 


sudo docker run --entrypoint /bin/bash --privileged --net host --shm-size=16G -e HF_TOKEN=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 -v /dev/shm/huggingface:/root/.cache/huggingface -it tpu-vm-base2
echo $(curl https://checkip.amazonaws.com)

cmd export HF_TOKEN=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
python3 examples/offline_inference_tpu.py

vllm serve google/gemma-2b  --enable-prefix-caching
# this fails: vllm serve meta-llama/Llama-3.1-8B  --enable-prefix-caching --max-num-seqs 1 --max-model-len 8192 --tensor-parallel-size 4
vllm serve meta-llama/Llama-3.1-70B-Instruct  --enable-prefix-caching --max-model-len 16384 --max-num-seqs 8 --tensor-parallel-size 4
vllm serve meta-llama/Llama-3.1-8B  --enable-prefix-caching --max-num-seqs 1 --enable-chunked-prefill

python3 -m vllm.entrypoints.openai.api_server --host=0.0.0.0 --port=8000 --tensor-parallel-size=8 --max-model-len=8192 --model=meta-llama/Llama-3.1-70B-Instruct
#  --download-dir=/data

35.186.1.120

ray start --block --head --port=6379
ray start --block --address=35.186.1.120:6379

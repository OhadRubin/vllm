

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
sudo groupadd docker || true
sudo usermod -aG docker $USER || true
newgrp docker || true
sudo chown "$USER":"$USER" /home/"$USER"/.docker -R || true
sudo chmod g+rwx "$HOME/.docker" -R || true

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


docker run --privileged --net host --shm-size=16G -it tpu-vm-base2 /bin/bash

docker run --privileged \
  --net host \
  --shm-size=16G \
  -v ${HOME}/.cache/huggingface:/root/.cache/huggingface \
  -it tpu-vm-base2 /bin/bash

python3 examples/offline_inference_tpu.py

vllm serve google/gemma-2b  --enable-prefix-caching
# this fails: vllm serve meta-llama/Llama-3.1-8B  --enable-prefix-caching --max-num-seqs 1 --max-model-len 8192 --tensor-parallel-size 4
vllm serve meta-llama/Llama-3.1-8B-Instruct  --enable-prefix-caching --max-model-len 16384 --max-num-seqs 8 --tensor-parallel-size 4
vllm serve meta-llama/Llama-3.1-8B  --enable-prefix-caching --max-num-seqs 1 --enable-chunked-prefill
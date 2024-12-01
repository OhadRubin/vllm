

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


git clone https://github.com/vllm-project/vllm.git
cd vllm
sudo docker build -t tpu-vm-base -f Dockerfile.tpu .
sudo docker run -it tpu-vm-base

export HF_TOKEN=

PJRT_DEVICE=TPU XLA_USE_SPMD=1


pip install --pre --extra-index-url https://download.pytorch.org/whl/nightly/cpu --find-links https://storage.googleapis.com/libtpu-releases/index.html --find-links https://storage.googleapis.com/jax-releases/jax_nightly_releases.html --find-links https://storage.googleapis.com/jax-releases/jaxlib_nightly_releases.html torch==2.6.0.dev20241114+cpu torchvision==0.20.0.dev20241114+cpu "torch_xla[tpu] @ https://storage.googleapis.com/pytorch-xla-releases/wheels/tpuvm/torch_xla-2.6.0.dev20241114-cp310-cp310-linux_x86_64.whl" jaxlib==0.4.32.dev20240829 jax==0.4.32.dev20240829

python3 examples/offline_inference_tpu.py

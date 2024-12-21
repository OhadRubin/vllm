
git clone https://github.com/OhadRubin/vllm.git

cd vllm

# pip install torch_xla[tpu] -f https://storage.googleapis.com/libtpu-releases/index.html
# pip3 install torch==2.5.0.dev20241201+cpu
# sudo apt-get update && sudo apt-get install -y git ffmpeg libsm6 libxext6 libgl1
# python3.10 -m pip install torch==2.6.0.dev20241201+cpu --index-url https://download.pytorch.org/whl/nightly/cpu
# python3.10 -m pip install https://storage.googleapis.com/pytorch-xla-releases/wheels/tpuvm/torch_xla-2.6.0.dev20241201-cp310-cp310-linux_x86_64.whl
# python3.10 -m pip install -r requirements-tpu.txt
# python3.10 -m pip install --upgrade pip setuptools wheel
# VLLM_TARGET_DEVICE="tpu" pip install -e .
# python3.10 -m pip install --find-links https://storage.googleapis.com/libtpu-releases/index.html --find-links https://storage.googleapis.com/jax-releases/jax_nightly_releases.html --find-links https://storage.googleapis.com/jax-releases/jaxlib_nightly_releases.html jaxlib==0.4.36.dev20241122 jax==0.4.36.dev20241122

# python3.10 -m pip install https://storage.googleapis.com/libtpu-nightly-releases/wheels/libtpu-nightly/libtpu_nightly-0.1.dev20241201+nightly-py3-none-linux_x86_64.whl

# mkdir -p /dev/shm/huggingface && rm -rf ~/.cache/huggingface && ln -s /dev/shm/huggingface ~/.cache/huggingface

bash install.sh


# TODO move to install.sh
sudo docker build -t tpu-vm-base -f Dockerfile.tpu .


# Now create the new directory in shared memory


# Finally, create the symbolic link
cmd sudo mkdir -p /dev/shm/huggingface && sudo chown $USER:$USER /dev/shm/huggingface && sudo rm -rf ~/.cache/huggingface && sudo ln -s /dev/shm/huggingface ~/.cache/huggingface
cmd cd vllm
cmd git pull

# cmd sudo docker run --entrypoint /bin/bash --privileged --net host --shm-size=16G -v /dev/shm/huggingface:/root/.cache/huggingface -it tpu-vm-base2


echo $(curl https://checkip.amazonaws.com)

vllm serve meta-llama/Llama-3.1-8B-Instruct  --max-model-len 1024 --tensor-parallel-size 8 --pipeline_parallel_size 1 --distributed-executor-backend ray
vllm serve meta-llama/Llama-3.2-1B-Instruct  --max-model-len 1024 --distributed-executor-backend ray
# --max-num-seqs 8 --tensor-parallel-size 4
# vllm serve meta-llama/Llama-3.1-8B-Instruct  --max-model-len 1024 --max-num-seqs 8 --tensor-parallel-size 4
 

# vllm serve meta-llama/Llama-3.1-70B-Instruct  --enable-prefix-caching --max-model-len 16384  --tensor-parallel-size 8 --distributed-executor-backend ray
# sudo docker exec -it node /bin/bash -c "vllm serve meta-llama/Llama-3.1-8B-Instruct  --max-model-len 1024 --max-num-seqs 8  --distributed-executor-backend ray --tensor-parallel-size 4"
# python3 -m vllm.entrypoints.openai.api_server --model=meta-llama/Llama-3.1-8B-Instruct --max-model-len=1024
# python3.10 -m vllm.entrypoints.openai.api_server --host=0.0.0.0 --port=8000 --tensor-parallel-size=8 --max-model-len=8192 --model=meta-llama/Llama-3.1-70B-Instruct
#  --download-dir=/data

# sudo mkdir -p /dev/shm/huggingface
# sudo chmod 777 /dev/shm/huggingface
# sudo rm -rf ~/.cache/huggingface
# sudo ln -s /dev/shm/huggingface ~/.cache/huggingface

# ohadr@v4-16-node-6:~/vllm$ gsutil -m cp /dev/shm/huggingface/hub/models--meta-llama--Llama-3.1-70B-Instruct/snapshots/1605565b47bb9346c5515c34102e054115b4f98b/* gs://meliad2_us2_backup/models/Llama-3.1-70B-Instruct/
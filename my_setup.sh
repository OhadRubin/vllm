
git clone https://github.com/OhadRubin/vllm.git

cd vllm

# pip install torch_xla[tpu] -f https://storage.googleapis.com/libtpu-releases/index.html
# pip3 install torch==2.5.0.dev20241201+cpu
sudo apt-get update && sudo apt-get install -y git ffmpeg libsm6 libxext6 libgl1
python3.10 -m pip install torch==2.6.0.dev20241201+cpu --index-url https://download.pytorch.org/whl/nightly/cpu
python3.10 -m pip install https://storage.googleapis.com/pytorch-xla-releases/wheels/tpuvm/torch_xla-2.6.0.dev20241201-cp310-cp310-linux_x86_64.whl
python3.10 -m pip install -r requirements-tpu.txt
python3.10 -m pip install --upgrade pip setuptools wheel
VLLM_TARGET_DEVICE="tpu" pip install -e .
python3.10 -m pip install --find-links https://storage.googleapis.com/libtpu-releases/index.html --find-links https://storage.googleapis.com/jax-releases/jax_nightly_releases.html --find-links https://storage.googleapis.com/jax-releases/jaxlib_nightly_releases.html jaxlib==0.4.36.dev20241122 jax==0.4.36.dev20241122



# python3.10 -m pip install https://storage.googleapis.com/libtpu-nightly-releases/wheels/libtpu-nightly/libtpu_nightly-0.1.dev20241201+nightly-py3-none-linux_x86_64.whl




cmd bash /home/ohadr/vllm/examples/start_ray.sh 35.186.1.120


mkdir -p /dev/shm/huggingface && rm -rf ~/.cache/huggingface && ln -s /dev/shm/huggingface ~/.cache/huggingface


sudo mkdir -p /dev/shm/huggingface && sudo rm -rf ~/.cache/huggingface && sudo ln -s /dev/shm/huggingface ~/.cache/huggingface

sudo mkdir -p /dev/shm/huggingface && sudo chown $USER:$USER /dev/shm/huggingface && sudo rm -rf ~/.cache/huggingface && sudo ln -s /dev/shm/huggingface ~/.cache/huggingface

# Now create the new directory in shared memory


# Finally, create the symbolic link


# sudo docker run --entrypoint /bin/bash --privileged --net host --shm-size=16G -v /dev/shm/huggingface:/root/.cache/huggingface -it tpu-vm-base2


python3.10 -m pip uninstall -y tensorflow && python3.10 -m pip install tensorflow-cpu

echo $(curl https://checkip.amazonaws.com)


export RAY_ADDRESS=35.186.1.120:6379

--max-num-seqs 8

vllm serve meta-llama/Llama-3.1-70B-Instruct  --enable-prefix-caching --max-model-len 16384  --tensor-parallel-size 8 --distributed-executor-backend ray
vllm serve meta-llama/Llama-3.1-8B-Instruct  --max-model-len 1024 --max-num-seqs 8 --tensor-parallel-size 4 --distributed-executor-backend ray

python3.10 -m vllm.entrypoints.openai.api_server --host=0.0.0.0 --port=8000 --tensor-parallel-size=8 --max-model-len=8192 --model=meta-llama/Llama-3.1-70B-Instruct
#  --download-dir=/data


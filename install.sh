# wget -qO- https://gist.githubusercontent.com/OhadRubin/a570cf7e828cdfc348beeea80cfa728a/raw/2cee658099f1ed6e7fb340cacbe1dd408844b0ae/setup_doc.sh | sudo bash
sudo apt-get update && sudo apt-get install -y git ffmpeg libsm6 libxext6 libgl1
python3.10 -m pip install torch==2.6.0.dev20241201+cpu --index-url https://download.pytorch.org/whl/nightly/cpu
python3.10 -m pip install https://storage.googleapis.com/pytorch-xla-releases/wheels/tpuvm/torch_xla-2.6.0.dev20241201-cp310-cp310-linux_x86_64.whl
python3.10 -m pip install -r requirements-tpu.txt
python3.10 -m pip install --upgrade pip setuptools wheel
VLLM_TARGET_DEVICE="tpu" pip install -e .
python3.10 -m pip install --find-links https://storage.googleapis.com/libtpu-releases/index.html --find-links https://storage.googleapis.com/jax-releases/jax_nightly_releases.html --find-links https://storage.googleapis.com/jax-releases/jaxlib_nightly_releases.html jaxlib==0.4.36.dev20241122 jax==0.4.36.dev20241122
sudo mkdir -p /dev/shm/huggingface && sudo chown $USER:$USER /dev/shm/huggingface && sudo rm -rf ~/.cache/huggingface && sudo ln -s /dev/shm/huggingface ~/.cache/huggingface
python3.10 -m pip uninstall -y tensorflow && python3.10 -m pip install tensorflow-cpu
sudo apt-get install libopenblas-base libopenmpi-dev libomp-dev


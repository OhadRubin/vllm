bash gcs_fuse_install.sh
huggingface-cli download --token $HF_TOKEN --exclude "*original*" --local-dir /mnt/gcs_bucket/models/Llama-3.3-70B-Instruct  meta-llama/Llama-3.3-70B-Instruct

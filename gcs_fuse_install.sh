if ! command -v gcsfuse &> /dev/null; then
    export GCSFUSE_REPO=gcsfuse-`lsb_release -c -s`
    echo "deb [signed-by=/usr/share/keyrings/cloud.google.asc] https://packages.cloud.google.com/apt $GCSFUSE_REPO main" | sudo tee /etc/apt/sources.list.d/gcsfuse.list
    curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo tee /usr/share/keyrings/cloud.google.asc
    sudo apt-get update
    sudo apt-get install gcsfuse
fi


# mountOptions: "implicit-dirs,file-cache:enable-parallel-downloads:true,file-cache:parallel-downloads-per-file:100,file-cache:max-parallel-downloads:-1,file-cache:download-chunk-size-mb:10,file-cache:max-size-mb:-1"


# Mount GCS bucket with the following options:
# --implicit-dirs (default: disabled): Implicitly define directories based on content
# --sequential-read-size-mb 10 (default: 200): Set file chunk size to read from GCS in one call to 10MB (min 1MB)
# --limit-ops-per-sec -1 (default: -1): No limit on operations per second
# --limit-bytes-per-sec -1 (default: -1): No bandwidth limit for reading data
# א--file-cache-max-parallel-downloads -1 (default: 192): Max concurrent file download requests across all files
# --file-cache-enable-parallel-downloads (default: disabled): Enable parallel downloads
# --file-cache-parallel-downloads-per-file 100 (default: 16): Concurrent download requests per file
# --file-cache-max-size-mb -1 (default: -1): Maximum size of file cache in MiB

if ! mountpoint -q /mnt/gcs_bucket; then
    sudo mkdir -p /dev/shm/gcs_cache
    sudo mkdir -p /mnt/gcs_bucket
    sudo chmod 777 /dev/shm/gcs_cache
    sudo chmod 777 /mnt/gcs_bucket
    gcsfuse \
        --implicit-dirs \
        --file-cache-enable-parallel-downloads \
        --file-cache-parallel-downloads-per-file 100 \
        --file-cache-max-parallel-downloads -1 \
        --file-cache-download-chunk-size-mb 10 \
        --file-cache-max-size-mb -1 \
        --dir-mode 0777 \
        --cache-dir /dev/shm/gcs_cache  \
        meliad2_us2_backup /mnt/gcs_bucket
    export MOUNT_POINT=/mnt/gcs_bucket
    echo 1024 | sudo tee /sys/class/bdi/0:$(stat -c "%d" $MOUNT_POINT)/read_ahead_kb
    ls -R /mnt/gcs_bucket/models/Llama-3.1-70B-Instruct > /dev/null
    sudo mkdir -p /mnt/gcs_bucket/vllm_cache
    sudo chmod 777 /mnt/gcs_bucket/vllm_cache
fi

# --file-cache-download-chunk-size-mb 100 \
# --file-cache-cache-file-for-range-read \
# ls  /gcs_bucket/models/Llama-3.1-70B-Instruct/


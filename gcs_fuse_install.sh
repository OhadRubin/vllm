#  bash gcs_fuse_install.sh
if ! command -v gcsfuse &> /dev/null; then
    echo "Installing gcsfuse"
    export GCSFUSE_REPO=gcsfuse-`lsb_release -c -s`
    echo "deb [signed-by=/usr/share/keyrings/cloud.google.asc] https://packages.cloud.google.com/apt $GCSFUSE_REPO main" | sudo tee /etc/apt/sources.list.d/gcsfuse.list
    curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo tee /usr/share/keyrings/cloud.google.asc
    sudo apt-get update
    # kill the process using apt-get if someone is using it 
    sudo apt-get install gcsfuse
fi

# Create mount point if it doesn't exist
if ! sudo mkdir -p /mnt/gcs_bucket 2>/dev/null; then
    mkdir -p /mnt/gcs_bucket
fi

# Set permissions on mount point
if ! sudo chmod 777 /mnt/gcs_bucket 2>/dev/null; then
    chmod 777 /mnt/gcs_bucket
fi

# Unmount if already mounted
if mountpoint -q /mnt/gcs_bucket; then
    # echo
    echo "Unmounting /mnt/gcs_bucket"
    sudo fusermount -u /mnt/gcs_bucket || sudo umount -f /mnt/gcs_bucket || sudo umount -l /mnt/gcs_bucket
fi

# Mount with proper user permissions
if ! mountpoint -q /mnt/gcs_bucket; then
    gcsfuse \
        --implicit-dirs \
        --file-cache-enable-parallel-downloads \
        --file-cache-parallel-downloads-per-file 100 \
        --file-cache-max-parallel-downloads -1 \
        --file-cache-download-chunk-size-mb 10 \
        --file-cache-max-size-mb -1 \
        --dir-mode 0777 \
        --file-mode 0666 \
        --uid $(id -u) \
        --gid $(id -g) \
        --cache-dir /dev/shm/gcs_cache \
        meliad2_us2_backup /mnt/gcs_bucket

    export MOUNT_POINT=/mnt/gcs_bucket
    echo 1024 | sudo tee /sys/class/bdi/0:$(stat -c "%d" $MOUNT_POINT)/read_ahead_kb
    ls -R /mnt/gcs_bucket/models/Llama-3.3-70B-Instruct > /dev/null
fi


#  chown -R $USER:$USER /mnt/gcs_bucket/models/Llama-3.3-70B-Instruct
#  chmod -R 777 /mnt/gcs_bucket/models/Llama-3.3-70B-Instruct
#  to unmount the gcs bucket
# fusermount -u /mnt/gcs_bucket
# doesn't work?
# sudo umount -f /mnt/gcs_bucket
# still doesn't work?
# sudo umount -l /mnt/gcs_bucket


#  bash gcs_fuse_install.sh


# wget -qO- https://gist.githubusercontent.com/OhadRubin/d070aa56a66246812ece7ce31f438021/raw/ee84decb77b75ad539509a485996ade48d9da27a/actual_gcs_fuse_install.sh | bash
# tail -f ~/gcs_log.log
while ! command -v gcsfuse &> /dev/null; do
    echo "installing gcsfuse"
    export GCSFUSE_REPO=gcsfuse-`lsb_release -c -s`
    echo "deb [signed-by=/usr/share/keyrings/cloud.google.asc] https://packages.cloud.google.com/apt $GCSFUSE_REPO main" | sudo tee /etc/apt/sources.list.d/gcsfuse.list
    curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo tee /usr/share/keyrings/cloud.google.asc
    sudo apt-get update

    if ! sudo apt-get install gcsfuse; then
        # Kill any existing apt/dpkg processes
        sudo pkill -f apt-get
        sudo pkill -f dpkg
        sudo pkill -f apt
        
        # Remove all lock files
        sudo rm -f /var/lib/apt/lists/lock
        sudo rm -f /var/cache/apt/archives/lock
        sudo rm -f /var/lib/dpkg/lock
        sudo rm -f /var/lib/dpkg/lock-frontend
        
        # Wait a moment for processes to fully terminate
        sleep 5
        
        # Clean and reconfigure dpkg if needed
        sudo dpkg --configure -a
    fi
done


# Check if we have sudo access by attempting to run a harmless sudo command
if sudo -n true 2>/dev/null; then
    HAS_SUDO=true
else
    HAS_SUDO=false
fi

if [ "$HAS_SUDO" = true ]; then
    sudo mkdir -p /mnt/gcs_bucket 2>/dev/null
    sudo chmod -R 777 /mnt/gcs_bucket 2>/dev/null
    echo "user_allow_other" | sudo tee /etc/fuse.conf
    sudo mkdir -p /dev/shm/gcs_cache
    sudo chmod 777 /dev/shm/gcs_cache
    sudo chown -R $USER:$USER /dev/shm/gcs_cache
else
    mkdir -p /mnt/gcs_bucket 2>/dev/null
    chmod -R 777 /mnt/gcs_bucket 2>/dev/null
fi

# pkill -f -9 gcsfuse

echo "checking if gcsfuse is mounted"
if [ "$HAS_SUDO" = true ]; then
    if ! mountpoint -q /mnt/gcs_bucket; then
        echo "mounting gcsfuse"
        sudo umount -l /mnt/gcs_bucket
        gcsfuse \
            --implicit-dirs \
            --file-cache-enable-parallel-downloads \
            --file-cache-parallel-downloads-per-file 100 \
            --file-cache-max-parallel-downloads -1 \
            --file-cache-download-chunk-size-mb 10 \
            --file-cache-max-size-mb 153600 \
            --dir-mode 0777 \
            -o allow_other --foreground \
            --cache-dir /dev/shm/gcs_cache  \
            meliad2_us2_backup /mnt/gcs_bucket &> ~/gcs_log.log &
        export MOUNT_POINT=/mnt/gcs_bucket
        echo 1024 | sudo tee /sys/class/bdi/0:$(stat -c "%d" $MOUNT_POINT)/read_ahead_kb
        if [ "$HAS_SUDO" = true ]; then
        else
            echo 1024 | tee /sys/class/bdi/0:$(stat -c "%d" $MOUNT_POINT)/read_ahead_kb
        fi
else
    export MOUNT_POINT=/mnt/gcs_bucket
    gcsfuse \
    --implicit-dirs \
    --file-cache-enable-parallel-downloads \
    --file-cache-parallel-downloads-per-file 100 \
    --file-cache-max-parallel-downloads -1 \
    --file-cache-download-chunk-size-mb 10 \
    --file-cache-max-size-mb 153600 \
    --dir-mode 0777 \
    --cache-dir /dev/shm/gcs_cache
    echo 1024 | tee /sys/class/bdi/0:$(stat -c "%d" $MOUNT_POINT)/read_ahead_kb
fi


#  chown -R $USER:$USER /mnt/gcs_bucket/models/Llama-3.3-70B-Instruct
#  chmod -R 777 /mnt/gcs_bucket/models/Llama-3.3-70B-Instruct
#  to unmount the gcs bucket
# fusermount -u /mnt/gcs_bucket
# doesn't work?
# sudo umount -f /mnt/gcs_bucket
# still doesn't work?
# sudo umount -l /mnt/gcs_bucket




mkdir -p /mnt/gcs_bucket
chmod 777 /mnt/gcs_bucket
if ! mountpoint -q /mnt/gcs_bucket; then
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
    echo 1024 | tee /sys/class/bdi/0:$(stat -c "%d" $MOUNT_POINT)/read_ahead_kb
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


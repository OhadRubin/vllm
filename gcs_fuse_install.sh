#  bash gcs_fuse_install.sh


BUCKET_NAME=${1:-meliad2_us2_backup}
export MOUNT_POINT=/mnt/gcs_bucket
echo "mounting $BUCKET_NAME"
    mkdir -p /mnt/gcs_bucket 2>/dev/null
    chmod -R 777 /mnt/gcs_bucket 2>/dev/null
    gcsfuse \
    --implicit-dirs \
    --file-cache-enable-parallel-downloads \
    --file-cache-parallel-downloads-per-file 100 \
    --file-cache-max-parallel-downloads -1 \
    --file-cache-download-chunk-size-mb 10 \
    --file-cache-max-size-mb 153600 \
    --dir-mode 0777 \
    --cache-dir /dev/shm/gcs_cache \
    $BUCKET_NAME $MOUNT_POINT

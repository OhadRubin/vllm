# if ! command -v gcsfuse &> /dev/null; then
#     export GCSFUSE_REPO=gcsfuse-`lsb_release -c -s`
#     echo "deb [signed-by=/usr/share/keyrings/cloud.google.asc] https://packages.cloud.google.com/apt $GCSFUSE_REPO main" | sudo tee /etc/apt/sources.list.d/gcsfuse.list
#     curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo tee /usr/share/keyrings/cloud.google.asc
#     sudo apt-get update
#     sudo apt-get install gcsfuse
# fi


# mountOptions: "implicit-dirs,file-cache:enable-parallel-downloads:true,file-cache:parallel-downloads-per-file:100,file-cache:max-parallel-downloads:-1,file-cache:download-chunk-size-mb:10,file-cache:max-size-mb:-1"


# Mount GCS bucket with the following options:
# --implicit-dirs (default: disabled): Implicitly define directories based on content
# --sequential-read-size-mb 10 (default: 200): Set file chunk size to read from GCS in one call to 10MB (min 1MB)
# --limit-ops-per-sec -1 (default: -1): No limit on operations per second
# --limit-bytes-per-sec -1 (default: -1): No bandwidth limit for reading data
# --file-cache-max-parallel-downloads -1 (default: 192): Max concurrent file download requests across all files
# --file-cache-enable-parallel-downloads (default: disabled): Enable parallel downloads
# --file-cache-parallel-downloads-per-file 100 (default: 16): Concurrent download requests per file
# --file-cache-max-size-mb -1 (default: -1): Maximum size of file cache in MiB
mkdir -p /gcs_bucket
if ! mountpoint -q /gcs_bucket; then
    gcsfuse \
        --implicit-dirs \
        --sequential-read-size-mb 1024 \
        --limit-ops-per-sec -1 \
        --limit-bytes-per-sec -1 \
        --file-cache-max-parallel-downloads -1 \
        --file-cache-enable-parallel-downloads \
        --file-cache-parallel-downloads-per-file 100 \
        --file-cache-max-size-mb -1 \
        meliad2_us2_backup /gcs_bucket
fi

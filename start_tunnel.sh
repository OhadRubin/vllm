~/ohadr/vllm/portr  auth set --token $PORTR_KEY --remote ohadrubin.com


while true; do
    ~/ohadr/vllm/portr http 8000 -s $HOSTNAME
    echo "Connection lost, reconnecting in 5 seconds..."
    sleep 5
done

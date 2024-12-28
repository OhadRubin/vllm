# it was obtained from:
# wget https://github.com/amalshaji/portr/releases/download/0.0.26-beta/portr_0.0.26-beta_Linux_x86_64.zip
# unzip portr_0.0.26-beta_Linux_x86_64.zip 
source ~/.bashrc
./portr  auth set --token $PORTR_KEY --remote ohadrubin.com


while true; do
    ./portr http 8000 -s $HOSTNAME
    echo "Connection lost, reconnecting in 5 seconds..."
    sleep 5
done

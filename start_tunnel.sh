# it was obtained from:
# wget https://github.com/amalshaji/portr/releases/download/0.0.27-beta/portr_0.0.27-beta_Linux_x86_64.zip && unzip portr_0.0.27-beta_Linux_x86_64.zip 
# 
export PORTR_KEY=$(bash -ic 'source ~/.bashrc; echo $PORTR_KEY')
~/vllm/portr  auth set --token $PORTR_KEY --remote ohadrubin.com


while true; do
    ~/vllm/portr http 8000 -s $HOSTNAME
    echo "Connection lost, reconnecting in 5 seconds..."
    sleep 5
done

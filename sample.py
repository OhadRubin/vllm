
# /// script
# dependencies = [
#   "openai==1.17.0",
# ]
# ///
from openai import OpenAI



client = OpenAI(
    base_url="https://v4-32-node-11.ohadrubin.com/v1",
    api_key="bla",
    # base_url="https://9752-35-186-106-186.ngrok-free.app/v1",
)

# import subprocess

# curl_command = ["curl", "http://0.0.0.0:8000/v1/models"]
# response = subprocess.run(curl_command, capture_output=True, text=True)
# print(response.stdout)

# from transformers import AutoTokenizer
# tokenizer = AutoTokenizer.from_pretrained("meta-llama/Llama-3.1-8B-Instruct")

def generate(messages, verbose=False):
  model = client.chat.completions.create(
      model="meta-llama/Llama-3.1-70B",
    #   model="/mnt/gcs_bucket/models/Llama-3.1-70B-Instruct/",
      temperature=0.9,
      messages=messages,
      max_tokens=100,
  )
  new_thought = model.choices[0].message.content
  if verbose:
    print(new_thought)
  return new_thought

messages=[
        {"role": "system", "content": "You are a helpful assistant." },
        {"role": "user", "content": "What is your name?"}
    ]
generate(messages, verbose=True)
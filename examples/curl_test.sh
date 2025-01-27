curl https://v4-16-node-16.ohadrubin.com/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $OPENROUTER_API_KEY" \
  -d '{
  "model": "meta-llama/Llama-3.1-8B-Instruct",
  "max_tokens": 1000,
  "messages": [
    {
      "role": "user",
      "content": "What is the meaning of life?"
    }
  ]
  
}'


curl https://v4-16-node-11.ohadrubin.com/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
  "model": "meta-llama/Llama-3.1-8B-Instruct",
  "max_tokens": 1000,
  "messages": [
    {
      "role": "user",
      "content": "What is the meaning of life?"
    }
  ]
  
}'


curl https://v4-16-node-41.ohadrubin.com/v1/chat/models \
  -H "Content-Type: application/json" \
  -d '{
  "model": "meta-llama/Llama-3.1-8B-Instruct",
  "max_tokens": 1000,
  "messages": [
    {
      "role": "user",
      "content": "What is the meaning of life?"
    }
  ]
  
}'
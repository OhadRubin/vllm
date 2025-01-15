import subprocess
import os
from urllib.parse import quote
import tempfile
def get_repo_file_sizes(token, repo_path):
    # Encode token for URL
    encoded_token = quote(token)
    repo_url = f"https://iohadrubin:{encoded_token}@huggingface.co/{repo_path}"
    
    try:
        # Create a temporary directory
        # Create a temporary directory that will be automatically cleaned up
        with tempfile.TemporaryDirectory() as temp_dir:
            # Set environment variable for LFS
            env = os.environ.copy()
            env["GIT_LFS_SKIP_SMUDGE"] = "1"
            
            # Clone repository with minimal data
            clone_command = [
                "git", "clone",
                "--filter=blob:none", 
                "--no-checkout",
                repo_url,
                temp_dir
            ]
            subprocess.run(clone_command, env=env, check=True, capture_output=True)
            
            # Change to repo directory and get LFS file info
            original_dir = os.getcwd()
            os.chdir(temp_dir)
            lfs_command = ["git", "lfs", "ls-files", "-s"]
            result = subprocess.run(lfs_command, capture_output=True, text=True, check=True)
            
            # Return to original directory
            os.chdir(original_dir)
        
        return result.stdout
        
    except subprocess.CalledProcessError as e:
        return f"Error: {e.stderr}"
    except Exception as e:
        return f"Error: {str(e)}"

def parse_size(size_str):
    size = size_str.strip("()")
    size, unit = size.split(" ")
    size = float(size)  # Convert to float first to handle decimal numbers
    if unit == "GB":
        return int(size * 1024 * 1024 * 1024)
    elif unit == "MB":
        return int(size * 1024 * 1024)
    elif unit == "KB":
        return int(size * 1024)
    else:
        return int(size)  # Default to bytes

def pretty_print_size(size):
    if size > 1024 * 1024 * 1024:
        return f"{size / (1024 * 1024 * 1024):.2f} GB"
    elif size > 1024 * 1024:
        return f"{size / (1024 * 1024):.2f} MB"
    else:
        return f"{size} bytes"


"""ohadr@v4-128-node-20:~$ ls /mnt/gcs_bucket/models/Llama-3.1-405B/ | grep safetensors | tail
model-00176-of-00191.safetensors
model-00177-of-00191.safetensors
model-00178-of-00191.safetensors
model-00179-of-00191.safetensors
model-00180-of-00191.safetensors
model-00181-of-00191.safetensors
model-00182-of-00191.safetensors
model-00183-of-00191.safetensors
model-00184-of-00191.safetensors"""


def get_safetensors_files(repo_path):
    token = subprocess.check_output("bash -ic 'source ~/.bashrc; echo $HF_TOKEN'", shell=True).decode().strip()
    if not token:
        print("Error: HF_TOKEN environment variable not set")
        exit(1)
    
    all_paths = []
    # Get and print file sizes
    sizes = get_repo_file_sizes(token, repo_path)
    for line in sizes.split("\n"):
        if not line.strip():
            continue
        # print(line)
        hash_str, path_size = line.split(" - ")
        path, size = path_size.split(" ", 1)
        if "safetensors" in path:
            print(f"{path} {size} {pretty_print_size(parse_size(size))}")
            all_paths.append(path)
    return all_paths
# python3.10 list_files.py
if __name__ == "__main__":
    all_paths = get_safetensors_files("meta-llama/Llama-3.1-405B")
    print(all_paths[:10])
    existing_files = os.listdir("/mnt/gcs_bucket/models/Llama-3.1-405B")
    print(existing_files[:10])
    # missing_files = [path for path in all_paths if path not in existing_files]
    # print(missing_files)
    
    # Get token from environment variable

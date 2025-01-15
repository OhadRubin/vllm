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

def get_safetensors_files_with_sizes(repo_path, verbose=False):
    token = subprocess.check_output("bash -ic 'source ~/.bashrc; echo $HF_TOKEN'", shell=True).decode().strip()
    if not token:
        print("Error: HF_TOKEN environment variable not set")
        exit(1)
    
    file_info = {}
    sizes = get_repo_file_sizes(token, repo_path)
    for line in sizes.split("\n"):
        if not line.strip():
            continue
        hash_str, path_size = line.split(" - ")
        path, size = path_size.split(" ", 1)
        if "safetensors" in path:
            expected_size = parse_size(size)
            if verbose:
                print(f"{path} {size} {pretty_print_size(expected_size)}")
            file_info[path] = expected_size
    return file_info

def verify_file_integrity(file_path, expected_size):
    actual_size = os.path.getsize(file_path)
    return actual_size == expected_size

def main(model_name="meta-llama/Llama-3.1-405B",
         model_dir="/mnt/gcs_bucket/models/Llama-3.1-405B",
         verbose=False):
    file_info = get_safetensors_files_with_sizes(model_name, verbose)
    existing_files = os.listdir(model_dir)
    
    corrupted_files = []
    missing_files = []
    
    for filename, expected_size in file_info.items():
        if filename not in existing_files:
            missing_files.append(filename)
        else:
            full_path = os.path.join(model_dir, filename)
            if not verify_file_integrity(full_path, expected_size):
                corrupted_files.append(filename)
                if verbose:
                    actual_size = os.path.getsize(full_path)
                    print(f"Corrupted file: {filename}")
                    print(f"Expected size: {pretty_print_size(expected_size)}")
                    print(f"Actual size: {pretty_print_size(actual_size)}")
    
    if corrupted_files:
        print("\nCorrupted files detected:")
        for file in corrupted_files:
            print(f"- {file}")
        corrupted_str = " ".join(corrupted_files)
        print(f"\nTo re-download corrupted files:")
        print(f"huggingface-cli download --local-dir {model_dir} {model_name} {corrupted_str}")
    
    if missing_files:
        print("\nMissing files detected:")
        for file in missing_files:
            print(f"- {file}")
        missing_str = " ".join(missing_files)
        print(f"\nTo download missing files:")
        print(f"huggingface-cli download --local-dir {model_dir} {model_name} {missing_str}")
    
    if not corrupted_files and not missing_files:
        print("All files present and verified.")

import fire
if __name__ == "__main__":
    fire.Fire(main)
    
    # Get token from environment variable

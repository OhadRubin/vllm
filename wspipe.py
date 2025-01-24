"""

# this creates the server and listens to relay_session
(cd ~/vllm && git pull)

cleanup() {
    pkill -f -9 wspipe
    tmux pipe-pane -t relay_session
}
trap cleanup EXIT INT TERM

python3.10 /home/ohadr/vllm/wspipe.py server  &
tmux pipe-pane -t relay_session -oIO 'cat | python3.10 /home/ohadr/vllm/wspipe.py client'
while true; do sleep 1; done

"""


import asyncio
import websockets
import sys
import signal
import os

async def stdin_reader(websocket):
    """Read from stdin and send to websocket with minimal buffering."""
    loop = asyncio.get_event_loop()
    queue = asyncio.Queue()
    
    # Set stdin to non-blocking mode
    os.set_blocking(sys.stdin.fileno(), False)
    
    def stdin_callback():
        try:
            # Try to read individual characters
            char = sys.stdin.buffer.read(1)
            if char:
                # Immediately queue the character for sending
                asyncio.create_task(queue.put(char.decode('utf-8')))
        except BlockingIOError:
            pass  # No data available right now
    
    loop.add_reader(sys.stdin.fileno(), stdin_callback)
    
    # Buffer for accumulating partial UTF-8 sequences
    buffer = ""
    
    try:
        while True:
            char = await queue.get()
            buffer += char
            
            # If we have a complete UTF-8 sequence, send it
            try:
                buffer.encode('utf-8')
                if buffer:
                    await websocket.send(buffer)
                    buffer = ""
            except UnicodeError:
                # Incomplete UTF-8 sequence, keep accumulating
                continue
                
    finally:
        loop.remove_reader(sys.stdin.fileno())
        os.set_blocking(sys.stdin.fileno(), True)

async def echo(websocket):
    """WebSocket handler that prints received messages immediately."""
    try:
        async for message in websocket:
            print(message, flush=True, end='')
            sys.stdout.flush()
    except websockets.exceptions.ConnectionClosed:
        print("Client disconnected")

async def client_main():
    uri = "ws://localhost:8765"
    try:
        async with websockets.connect(uri) as websocket:
            await stdin_reader(websocket)
    except ConnectionRefusedError:
        print(f"Could not connect to WebSocket server at {uri}")
    except KeyboardInterrupt:
        print("\nShutting down...")

async def echo(websocket):
    """Simple WebSocket handler that prints received messages."""
    try:
        async for message in websocket:
            print(message, end='')
            await websocket.send(f"Server received: {message}")
    except websockets.exceptions.ConnectionClosed:
        print("Client disconnected")

async def server_main():
    async with websockets.serve(echo, "localhost", 8765):
        print("WebSocket server started on ws://localhost:8765")
        await asyncio.Future()  # run forever

def main():
    if len(sys.argv) != 2 or sys.argv[1] not in ['server', 'client']:
        print("Usage: python wspipe.py [server|client]")
        sys.exit(1)

    loop = asyncio.get_event_loop()
    
    def signal_handler():
        loop.stop()
        sys.exit(0)
    
    loop.add_signal_handler(signal.SIGINT, signal_handler)
    
    try:
        if sys.argv[1] == 'server':
            loop.run_until_complete(server_main())
        else:  # client
            loop.run_until_complete(client_main())
    finally:
        loop.close()

if __name__ == "__main__":
    main()
import asyncio
import websockets
import sys
import signal

async def stdin_reader(websocket):
    """Read from stdin and send to websocket."""
    loop = asyncio.get_event_loop()
    queue = asyncio.Queue()
    
    def stdin_callback():
        data = sys.stdin.buffer.read1(8192)  # Read up to 8KB of available data
        if data:
            decoded = data.decode('utf-8').strip()
            if decoded:
                asyncio.create_task(queue.put(decoded))
    
    loop.add_reader(sys.stdin.fileno(), stdin_callback)
    
    try:
        while True:
            line = await queue.get()
            try:
                await websocket.send(line)
                print(f"Sent: {line}")
            except websockets.exceptions.ConnectionClosed:
                print("WebSocket connection closed")
                break
    finally:
        loop.remove_reader(sys.stdin.fileno())

async def client_main():
    uri = "ws://localhost:8765"
    try:
        async with websockets.connect(uri) as websocket:
            print(f"Connected to {uri}")
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

"""
Usage examples:

Server mode:
python3.10 wspipe.py server

Client mode (pipe input):

For tmux:
# Terminal 1: Start server
python3.10 /home/ohadr/vllm/wspipe.py server 

# Terminal 2: Pipe tmux pane to client
tmux pipe-pane -t relay_session -o 'cat >~/mypanelog'
tail ~/mypanelog -f
tmux pipe-pane -t relay_session -oIO 'cat | python3.10 /home/ohadr/vllm/wspipe.py client'
"""
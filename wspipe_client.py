import asyncio
import websockets
import sys
import signal

async def stdin_reader(websocket):
    """Read from stdin and send to websocket."""
    loop = asyncio.get_event_loop()
    
    # Create a queue to handle stdin input
    queue = asyncio.Queue()
    
    def stdin_callback():
        line = sys.stdin.buffer.readline().decode('utf-8').strip()
        if line:  # If we actually got input
            asyncio.create_task(queue.put(line))
    
    # Add the stdin reader to the event loop
    loop.add_reader(sys.stdin.fileno(), stdin_callback)
    
    try:
        while True:
            # Wait for input from stdin
            line = await queue.get()
            
            try:
                await websocket.send(line)
                print(f"Sent: {line}")
            except websockets.exceptions.ConnectionClosed:
                print("WebSocket connection closed")
                break
    finally:
        # Clean up the stdin reader
        loop.remove_reader(sys.stdin.fileno())

async def main():
    # Replace with your WebSocket server URL
    uri = "ws://localhost:8765"
    
    try:
        async with websockets.connect(uri) as websocket:
            print(f"Connected to {uri}")
            await stdin_reader(websocket)
    except ConnectionRefusedError:
        print(f"Could not connect to WebSocket server at {uri}")
    except KeyboardInterrupt:
        print("\nShutting down...")


# usage: cat /dev/urandom | python3.10 wspipe_client.py
if __name__ == "__main__":
    # Handle graceful shutdown
    loop = asyncio.get_event_loop()
    
    def signal_handler():
        loop.stop()
        sys.exit(0)
    
    # Register SIGINT handler
    loop.add_signal_handler(signal.SIGINT, signal_handler)
    
    try:
        loop.run_until_complete(main())
    finally:
        loop.close()
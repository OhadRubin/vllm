import asyncio
import websockets

async def echo(websocket):
    """Simple WebSocket handler that prints received messages."""
    try:
        async for message in websocket:
            print(f"Received message: {message}")
            # Echo back the message
            await websocket.send(f"Server received: {message}")
    except websockets.exceptions.ConnectionClosed:
        print("Client disconnected")

async def main():
    # Start the WebSocket server
    async with websockets.serve(echo, "localhost", 8765):
        print("WebSocket server started on ws://localhost:8765")
        # Run forever
        await asyncio.Future()  # run forever

# usage: python3.10 wspipe_server.py
if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\nShutting down server...")
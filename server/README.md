# Valley Clash — Colyseus Server

LAN multiplayer server for Valley Clash. Room invite code is always **`xxxx`**.

## Run

```bash
cd server
npm start
```

Listens on port **2567** (all interfaces). On start it prints local + LAN WebSocket URLs.

## Flow

1. Host machine runs `npm start`
2. In Godot, set **Server IP** to `127.0.0.1` (same PC) or the host's LAN IP (other PCs)
3. Host clicks **Create Game** (creates room with code `xxxx`)
4. Guest enters the same Server IP, clicks **Join Game** (joins code `xxxx`)

## Monitor

- Playground: http://127.0.0.1:2567/
- Monitor: http://127.0.0.1:2567/monitor

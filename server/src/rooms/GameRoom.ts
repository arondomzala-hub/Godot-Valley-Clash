import { Room, Client, CloseCode } from "colyseus";
import { GameState, Player } from "./schema/GameState.js";

/** Fixed LAN invite code used by Valley Clash. */
export const ROOM_CODE = "xxxx";

interface MovePayload {
  x: number;
  y: number;
  tx: number;
  ty: number;
}

export class GameRoom extends Room {
  maxClients = 4;
  state = new GameState();

  onCreate(options: { code?: string }) {
    const code = (options?.code ?? ROOM_CODE).toLowerCase();
    if (code !== ROOM_CODE) {
      throw new Error(`Invalid room code. Use "${ROOM_CODE}".`);
    }

    this.state.code = ROOM_CODE;
    this.setMetadata({ code: ROOM_CODE });

    this.onMessage("move", (client, data: MovePayload) => {
      const player = this.state.players.get(client.sessionId);
      if (player) {
        player.x = data.tx;
        player.y = data.ty;
      }
      this.broadcast(
        "move",
        { id: client.sessionId, x: data.x, y: data.y, tx: data.tx, ty: data.ty },
        { except: client },
      );
    });

    console.log(`Game room created with code "${ROOM_CODE}" (${this.roomId})`);
  }

  onJoin(client: Client, _options: unknown) {
    // Tell the new client about everyone already in the room (before adding
    // the new player, so the roster never includes the client itself).
    const roster = [...this.state.players.entries()].map(([id, p]) => ({
      id,
      x: p.x,
      y: p.y,
    }));
    if (roster.length > 0) {
      client.send("roster", roster);
    }

    const player = new Player();
    player.name = `Player ${this.clients.length}`;
    this.state.players.set(client.sessionId, player);
    console.log(client.sessionId, "joined room", this.roomId);
  }

  onLeave(client: Client, code: CloseCode) {
    this.state.players.delete(client.sessionId);
    this.broadcast("player_left", { id: client.sessionId });
    console.log(client.sessionId, "left!", code);
  }

  onDispose() {
    console.log("room", this.roomId, "disposing...");
  }
}

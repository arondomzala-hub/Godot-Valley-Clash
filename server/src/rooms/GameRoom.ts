import { Room, Client, CloseCode } from "colyseus";
import { GameState, Player } from "./schema/GameState.js";

/** Fixed LAN invite code used by Valley Clash. */
export const ROOM_CODE = "xxxx";

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
    console.log(`Game room created with code "${ROOM_CODE}" (${this.roomId})`);
  }

  onJoin(client: Client, _options: unknown) {
    const player = new Player();
    player.name = `Player ${this.clients.length}`;
    this.state.players.set(client.sessionId, player);
    console.log(client.sessionId, "joined room", this.roomId);
  }

  onLeave(client: Client, code: CloseCode) {
    this.state.players.delete(client.sessionId);
    console.log(client.sessionId, "left!", code);
  }

  onDispose() {
    console.log("room", this.roomId, "disposing...");
  }
}

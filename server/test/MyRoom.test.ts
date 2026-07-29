import assert from "assert";
import { ColyseusTestServer, boot } from "@colyseus/testing";

import appConfig from "../src/app.config.js";
import { GameState } from "../src/rooms/schema/GameState.js";
import { ROOM_CODE } from "../src/rooms/GameRoom.js";

describe("Valley Clash Colyseus app", () => {
  let colyseus: ColyseusTestServer<typeof appConfig>;

  before(async () => {
    colyseus = await boot(appConfig);
  });
  after(async () => colyseus.shutdown());

  beforeEach(async () => await colyseus.cleanup());

  it("creates and joins a room with code xxxx", async () => {
    const room = await colyseus.createRoom<GameState>("game", { code: ROOM_CODE });
    const client1 = await colyseus.connectTo(room);

    assert.strictEqual(client1.sessionId, room.clients[0].sessionId);

    await room.waitForNextPatch();

    const state = client1.state.toJSON() as { code: string; players: Record<string, unknown> };
    assert.strictEqual(state.code, ROOM_CODE);
    assert.ok(state.players[client1.sessionId]);
  });
});

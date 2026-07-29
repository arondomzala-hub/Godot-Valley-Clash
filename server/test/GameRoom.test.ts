import assert from "assert";
import { ColyseusTestServer, boot } from "@colyseus/testing";

import appConfig from "../src/app.config.js";
import { MatchState } from "../src/rooms/schema/GameState.js";
import { ROOM_CODE } from "../src/rooms/GameRoom.js";

describe("Valley Clash GameRoom", () => {
  let colyseus: ColyseusTestServer<typeof appConfig>;

  before(async () => {
    colyseus = await boot(appConfig);
  });
  after(async () => colyseus.shutdown());

  beforeEach(async () => await colyseus.cleanup());

  it("runs a solo match with config overrides and validated economy intents", async () => {
    const room = await colyseus.createRoom<MatchState>("game", {
      code: ROOM_CODE,
      mode: "solo",
      // mine_income 0 keeps gold deterministic while the simulation runs.
      configOverrides: { starting_gold: 500, mine_income: 0 },
    });
    const client = await colyseus.connectTo(room, { code: ROOM_CODE });
    await room.waitForNextPatch();

    assert.strictEqual(room.state.phase, "playing");
    assert.strictEqual(room.state.teams.get("blue").sessionId, client.sessionId);
    assert.strictEqual(room.state.teams.get("red").sessionId, ""); // bot team
    assert.strictEqual(room.state.teams.get("blue").gold, 500);
    assert.strictEqual(room.state.knights.get("blue").damage, 0); // unarmed
    assert.strictEqual(room.state.config.itemPrices.get("sword"), 50);

    client.send("buy_item", { item: "sword" });
    await room.waitForMessage("buy_item");
    assert.strictEqual(room.state.teams.get("blue").gold, 450);
    assert.strictEqual(room.state.knights.get("blue").damage, 10);
    assert.strictEqual(room.state.knights.get("blue").attackSpeed, 1.5);
    assert.deepStrictEqual([...room.state.knights.get("blue").items], ["sword"]);

    client.send("build_mine", {});
    await room.waitForMessage("build_mine");
    const blue = room.state.teams.get("blue");
    assert.strictEqual(blue.gold, 350);
    assert.strictEqual(blue.mines, 1);
    assert.strictEqual(blue.nextMineCost, 200);

    client.send("spawn_unit", { type: "peasant" });
    await room.waitForMessage("spawn_unit");
    let blueUnits = 0;
    room.state.units.forEach((unit) => {
      if (unit.team === "blue") blueUnits += 1;
    });
    assert.strictEqual(blueUnits, 1);
    assert.strictEqual(room.state.teams.get("blue").gold, 330);

    // Invalid input is ignored without side effects.
    client.send("buy_item", { item: "excalibur" });
    await room.waitForMessage("buy_item");
    client.send("spawn_unit", { type: "dragon" });
    await room.waitForMessage("spawn_unit");
    assert.strictEqual(room.state.teams.get("blue").gold, 330);

    client.send("set_command", { command: "defend" });
    await room.waitForMessage("set_command");
    assert.strictEqual(room.state.teams.get("blue").command, "defend");
  });

  it("separates stacked units and keeps entities out of the castle", async () => {
    const room = await colyseus.createRoom<MatchState>("game", {
      code: ROOM_CODE,
      mode: "solo",
      configOverrides: { starting_gold: 1000, mine_income: 0 },
    });
    const client = await colyseus.connectTo(room, { code: ROOM_CODE });
    await room.waitForNextPatch();

    // "hold" with no enemies in aggro keeps units idle, so any spreading
    // observed below comes purely from the collision separation pass.
    client.send("set_command", { command: "hold" });
    await room.waitForMessage("set_command");
    for (let i = 0; i < 8; i++) {
      client.send("spawn_unit", { type: "peasant" });
      await room.waitForMessage("spawn_unit");
    }

    // Walk the knight into the blue castle center; it must be pushed out.
    client.send("move", { x: 5, y: -1863 });
    await room.waitForMessage("move");

    // Let the simulation run (~30 ticks at 50 ms).
    await new Promise((resolve) => setTimeout(resolve, 1500));

    const positions: { x: number; y: number }[] = [];
    room.state.units.forEach((unit) => positions.push({ x: unit.x, y: unit.y }));
    assert.strictEqual(positions.length, 8);

    let minPairDist = Infinity;
    for (let i = 0; i < positions.length; i++) {
      for (let j = i + 1; j < positions.length; j++) {
        const d = Math.hypot(positions[j].x - positions[i].x, positions[j].y - positions[i].y);
        minPairDist = Math.min(minPairDist, d);
      }
    }
    // Two unit radii = 48; allow slack for convergence still in progress.
    assert.ok(minPairDist >= 46, `units still stacked: min pair distance ${minPairDist}`);

    const knight = room.state.knights.get("blue");
    const knightToCastle = Math.hypot(knight.x - 5, knight.y - -1863);
    // Castle radius 80 + knight radius 28 = 108; the knight must not stand inside.
    assert.ok(knightToCastle >= 104, `knight inside castle: distance ${knightToCastle}`);
    for (const p of positions) {
      const d = Math.hypot(p.x - 5, p.y - -1863);
      assert.ok(d >= 100, `unit inside castle: distance ${d}`);
    }
  });

  it("pvp: waits for two players, then awards the win when one leaves", async () => {
    const room = await colyseus.createRoom<MatchState>("game", { code: ROOM_CODE });
    const client1 = await colyseus.connectTo(room, { code: ROOM_CODE });
    await room.waitForNextPatch();
    assert.strictEqual(room.state.phase, "waiting");

    const client2 = await colyseus.connectTo(room, { code: ROOM_CODE });
    await room.waitForNextPatch();
    assert.strictEqual(room.state.phase, "playing");
    assert.strictEqual(room.state.teams.get("blue").sessionId, client1.sessionId);
    assert.strictEqual(room.state.teams.get("red").sessionId, client2.sessionId);

    await client2.leave();
    await room.waitForNextPatch();
    assert.strictEqual(room.state.phase, "finished");
    assert.strictEqual(room.state.winner, "blue");
  });
});

import { Schema, type, MapSchema } from "@colyseus/schema";

export class Player extends Schema {
  @type("string") name: string = "Player";
  @type("number") x: number = 0;
  @type("number") y: number = 0;
}

export class GameState extends Schema {
  @type("string") code: string = "xxxx";
  @type({ map: Player }) players = new MapSchema<Player>();
}

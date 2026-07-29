import type { GameRoom, TeamId } from "./GameRoom.js";
import type { Knight, Team } from "./schema/GameState.js";
import { UNIT_TYPES } from "./GameConfig.js";

const ITEM_BUILD_ORDER = ["sword", "armor", "boots"] as const;
const MAX_BOT_MINES = 4;
const CASTLE_PANIC_RATIO = 0.35;
/** Issue a knight move intent every N ticks (~6s at a 2s tick). */
const KNIGHT_MOVE_EVERY = 3;

/**
 * Simple solo-mode opponent. It acts exclusively through the room's public
 * intent handlers, so it plays by exactly the same rules as a human client.
 */
export class BotController {
  private ticks = 0;

  constructor(
    private readonly room: GameRoom,
    private readonly teamId: TeamId,
  ) {}

  tick(): void {
    const state = this.room.state;
    if (state.phase !== "playing") return;
    this.ticks += 1;

    const team = state.teams.get(this.teamId);
    const knight = state.knights.get(this.teamId);
    const castle = state.castles.get(this.teamId);
    if (!team || !knight || !castle) return;

    const desiredCommand =
      castle.hp < castle.maxHp * CASTLE_PANIC_RATIO ? "defend" : "attack";
    if (team.command !== desiredCommand) {
      this.room.handleSetCommand(this.teamId, { command: desiredCommand });
    }

    // One economy action per tick: mines first, then knight items, then units.
    if (team.mines < MAX_BOT_MINES && team.gold >= team.nextMineCost) {
      this.room.handleBuildMine(this.teamId);
    } else if (!this.buyNextItem(team, knight)) {
      this.spawnRandomAffordableUnit(team);
    }

    if (this.ticks % KNIGHT_MOVE_EVERY === 0 && knight.alive) {
      this.room.handleMove(this.teamId, this.knightDestination(knight));
    }
  }

  /** Buys the next unowned item in the build order if affordable. */
  private buyNextItem(team: Team, knight: Knight): boolean {
    for (const item of ITEM_BUILD_ORDER) {
      if (knight.items.includes(item)) continue;
      const price = this.room.state.config.itemPrices.get(item);
      if (price === undefined || team.gold < price) return false;
      this.room.handleBuyItem(this.teamId, { item });
      return true;
    }
    return false;
  }

  private spawnRandomAffordableUnit(team: Team): void {
    const costs = this.room.state.config.unitCosts;
    const affordable = UNIT_TYPES.filter((type) => {
      const cost = costs.get(type);
      return cost !== undefined && cost <= team.gold;
    });
    if (affordable.length === 0) return;
    const type = affordable[Math.floor(Math.random() * affordable.length)];
    this.room.handleSpawnUnit(this.teamId, { type });
  }

  /** Nearest enemy combatant's position, or lane center mid-map as fallback. */
  private knightDestination(knight: Knight): { x: number; y: number } {
    const state = this.room.state;
    const enemyTeam: TeamId = this.teamId === "blue" ? "red" : "blue";
    let best: { x: number; y: number } | null = null;
    let bestDist = Infinity;

    const enemyKnight = state.knights.get(enemyTeam);
    if (enemyKnight && enemyKnight.alive) {
      bestDist = Math.hypot(enemyKnight.x - knight.x, enemyKnight.y - knight.y);
      best = { x: enemyKnight.x, y: enemyKnight.y };
    }
    state.units.forEach((unit) => {
      if (unit.team !== enemyTeam) return;
      const d = Math.hypot(unit.x - knight.x, unit.y - knight.y);
      if (d < bestDist) {
        bestDist = d;
        best = { x: unit.x, y: unit.y };
      }
    });
    return best ?? { x: 0, y: 0 };
  }
}

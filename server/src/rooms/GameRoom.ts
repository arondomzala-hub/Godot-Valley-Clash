import { Room, Client, CloseCode } from "colyseus";
import { MatchState, Team, Knight, Unit, Castle } from "./schema/GameState.js";
import {
  DEFAULT_CONFIG,
  applyOverrides,
  isItemId,
  isUnitType,
  GameConfig,
  ItemId,
  ITEM_IDS,
  UNIT_TYPES,
  WEAPON_STATS,
} from "./GameConfig.js";
import { BotController } from "./BotController.js";

/** Fixed LAN invite code used by Valley Clash. */
export const ROOM_CODE = "xxxx";

export type TeamId = "blue" | "red";
export const TEAM_IDS: readonly TeamId[] = ["blue", "red"];

export function enemyOf(team: TeamId): TeamId {
  return team === "blue" ? "red" : "blue";
}

// Map layout (blue on top, red on bottom).
const MAP_MIN_X = -760;
const MAP_MAX_X = 760;
const MAP_MIN_Y = -1980;
const MAP_MAX_Y = 1980;

const KNIGHT_SPAWN: Record<TeamId, { x: number; y: number }> = {
  blue: { x: 0, y: -1600 },
  red: { x: 0, y: 1600 },
};

const CASTLE_POS: Record<TeamId, { x: number; y: number }> = {
  blue: { x: 5, y: -1863 },
  red: { x: 8, y: 1832 },
};

// Combat / movement tuning that is not player-facing config.
const MELEE_RANGE = 60;
const CASTLE_HIT_RANGE = 120;
const AGGRO_RADIUS = 300;
const UNIT_ATTACK_SPEED = 1.0;
const STOP_DISTANCE = 8;
const RALLY_OFFSET = 250;
const UNIT_SPAWN_Y_OFFSET = 150;
const BOT_TICK_MS = 2000;
const FINISHED_DISPOSE_MS = 15_000;

const COMMANDS = ["attack", "hold", "defend"];

interface KnightRuntime {
  hasTarget: boolean;
  targetX: number;
  targetY: number;
  cooldown: number;
}

interface UnitRuntime {
  damage: number;
  speed: number;
  cooldown: number;
}

type CombatTarget =
  | { kind: "knight"; team: TeamId; ref: Knight }
  | { kind: "unit"; team: TeamId; id: string; ref: Unit };

function clamp(value: number, min: number, max: number): number {
  return Math.min(max, Math.max(min, value));
}

function dist(x1: number, y1: number, x2: number, y2: number): number {
  return Math.hypot(x2 - x1, y2 - y1);
}

export class GameRoom extends Room {
  maxClients = 2;
  state = new MatchState();

  private mode: "solo" | "pvp" = "pvp";
  private config: GameConfig = { ...DEFAULT_CONFIG };
  private bot: BotController | null = null;
  private incomeAccumulator = 0;
  private nextUnitId = 1;
  private knightRuntime: Record<TeamId, KnightRuntime> = {
    blue: { hasTarget: false, targetX: 0, targetY: 0, cooldown: 0 },
    red: { hasTarget: false, targetX: 0, targetY: 0, cooldown: 0 },
  };
  private unitRuntime = new Map<string, UnitRuntime>();

  onCreate(options: { code?: string; mode?: string; configOverrides?: unknown }) {
    const code = (options?.code ?? ROOM_CODE).toLowerCase();
    if (code !== ROOM_CODE) {
      throw new Error(`Invalid room code. Use "${ROOM_CODE}".`);
    }

    this.mode = options?.mode === "solo" ? "solo" : "pvp";
    this.maxClients = this.mode === "solo" ? 1 : 2;
    // Overrides are dev/admin tools: only honored in solo matches.
    this.config =
      this.mode === "solo" ? applyOverrides(options?.configOverrides) : { ...DEFAULT_CONFIG };

    this.state.code = ROOM_CODE;
    this.setMetadata({ code: ROOM_CODE, mode: this.mode });

    for (const teamId of TEAM_IDS) {
      this.initTeam(teamId);
    }
    this.fillConfigSnapshot();

    this.bindHandler("move", (teamId, payload) => this.handleMove(teamId, payload));
    this.bindHandler("buy_item", (teamId, payload) => this.handleBuyItem(teamId, payload));
    this.bindHandler("build_mine", (teamId) => this.handleBuildMine(teamId));
    this.bindHandler("spawn_unit", (teamId, payload) => this.handleSpawnUnit(teamId, payload));
    this.bindHandler("set_command", (teamId, payload) => this.handleSetCommand(teamId, payload));

    this.setSimulationInterval((dtMs) => this.update(dtMs / 1000), 50);

    console.log(`Game room created: code "${ROOM_CODE}", mode "${this.mode}" (${this.roomId})`);
  }

  onJoin(client: Client) {
    let assigned: TeamId | null = null;
    if (this.mode === "solo") {
      assigned = "blue";
    } else {
      for (const teamId of TEAM_IDS) {
        if (this.state.teams.get(teamId).sessionId === "") {
          assigned = teamId;
          break;
        }
      }
    }
    if (!assigned) {
      throw new Error("Match is full.");
    }
    this.state.teams.get(assigned).sessionId = client.sessionId;
    console.log(client.sessionId, `joined room ${this.roomId} as team "${assigned}"`);

    const allSeated =
      this.mode === "solo" ||
      TEAM_IDS.every((teamId) => this.state.teams.get(teamId).sessionId !== "");
    if (allSeated) {
      this.startMatch();
    }
  }

  onLeave(client: Client, code: CloseCode) {
    const teamId = this.teamOf(client.sessionId);
    console.log(client.sessionId, "left room", this.roomId, "code", code);
    if (!teamId) {
      return;
    }
    this.state.teams.get(teamId).sessionId = "";

    if (this.state.phase === "playing" && this.mode === "pvp") {
      // Forfeit: the remaining team wins.
      this.finishMatch(enemyOf(teamId));
    }
    // Solo: autoDispose tears the room down once the human is gone.
  }

  onDispose() {
    console.log("room", this.roomId, "disposing...");
  }

  // ---------------------------------------------------------------- intents
  // Public so BotController plays through the exact same code path as humans.

  handleMove(teamId: TeamId, payload: unknown): void {
    if (this.state.phase !== "playing") return;
    const knight = this.state.knights.get(teamId);
    if (!knight || !knight.alive) return;
    const data = payload as { x?: unknown; y?: unknown };
    const x = Number(data?.x);
    const y = Number(data?.y);
    if (!Number.isFinite(x) || !Number.isFinite(y)) return;

    const rt = this.knightRuntime[teamId];
    rt.targetX = clamp(x, MAP_MIN_X, MAP_MAX_X);
    rt.targetY = clamp(y, MAP_MIN_Y, MAP_MAX_Y);
    rt.hasTarget = true;
  }

  handleBuyItem(teamId: TeamId, payload: unknown): void {
    if (this.state.phase !== "playing") return;
    const item = (payload as { item?: unknown })?.item;
    if (typeof item !== "string" || !isItemId(item)) return;

    const team = this.state.teams.get(teamId);
    const knight = this.state.knights.get(teamId);
    const price = this.config[`item_price_${item}`];
    if (knight.items.length >= this.config.max_items) return;
    if (team.gold < price) return;

    team.gold -= price;
    knight.items.push(item);
    this.applyItemEffect(knight, item);
  }

  handleBuildMine(teamId: TeamId): void {
    if (this.state.phase !== "playing") return;
    const team = this.state.teams.get(teamId);
    if (team.gold < team.nextMineCost) return;

    team.gold -= team.nextMineCost;
    team.mines += 1;
    team.income = team.mines * this.config.mine_income;
    team.nextMineCost = this.config.mine_base_cost * Math.pow(2, team.mines);
  }

  handleSpawnUnit(teamId: TeamId, payload: unknown): void {
    if (this.state.phase !== "playing") return;
    const type = (payload as { type?: unknown })?.type;
    if (typeof type !== "string" || !isUnitType(type)) return;

    const team = this.state.teams.get(teamId);
    const cost = this.config[`unit_${type}_cost`];
    if (team.gold < cost) return;
    team.gold -= cost;

    const unit = new Unit();
    unit.team = teamId;
    unit.type = type;
    const castlePos = CASTLE_POS[teamId];
    unit.x = clamp(castlePos.x + (Math.random() * 160 - 80), MAP_MIN_X, MAP_MAX_X);
    unit.y = castlePos.y + (teamId === "blue" ? UNIT_SPAWN_Y_OFFSET : -UNIT_SPAWN_Y_OFFSET);
    unit.hp = unit.maxHp = this.config[`unit_${type}_hp`];

    const id = String(this.nextUnitId++);
    this.unitRuntime.set(id, {
      damage: this.config[`unit_${type}_damage`],
      speed: this.config[`unit_${type}_speed`],
      cooldown: 0,
    });
    this.state.units.set(id, unit);
  }

  handleSetCommand(teamId: TeamId, payload: unknown): void {
    if (this.state.phase !== "playing") return;
    const command = (payload as { command?: unknown })?.command;
    if (typeof command !== "string" || !COMMANDS.includes(command)) return;
    this.state.teams.get(teamId).command = command;
  }

  // ------------------------------------------------------------- simulation

  private update(dt: number): void {
    if (this.state.phase !== "playing") return;
    this.tickIncome(dt);
    for (const teamId of TEAM_IDS) {
      this.tickKnight(teamId, dt);
      if (this.state.phase !== "playing") return;
    }
    this.tickUnits(dt);
  }

  private tickIncome(dt: number): void {
    this.incomeAccumulator += dt;
    while (this.incomeAccumulator >= 1) {
      this.incomeAccumulator -= 1;
      for (const teamId of TEAM_IDS) {
        const team = this.state.teams.get(teamId);
        team.gold += team.mines * this.config.mine_income;
      }
    }
  }

  private tickKnight(teamId: TeamId, dt: number): void {
    const knight = this.state.knights.get(teamId);
    const rt = this.knightRuntime[teamId];

    if (!knight.alive) {
      knight.respawnIn = Math.max(0, knight.respawnIn - dt);
      if (knight.respawnIn === 0) {
        knight.alive = true;
        knight.hp = knight.maxHp;
        knight.x = KNIGHT_SPAWN[teamId].x;
        knight.y = KNIGHT_SPAWN[teamId].y;
        rt.hasTarget = false;
        rt.cooldown = 0;
      }
      return;
    }

    if (knight.regen > 0 && knight.hp < knight.maxHp) {
      knight.hp = Math.min(knight.maxHp, knight.hp + knight.regen * dt);
    }

    rt.cooldown = Math.max(0, rt.cooldown - dt);

    // Armed knights stop and fight anything in melee range, then resume moving.
    if (knight.damage > 0) {
      const enemyTeam = enemyOf(teamId);
      const target = this.nearestEnemy(enemyTeam, knight.x, knight.y, MELEE_RANGE);
      if (target) {
        if (rt.cooldown === 0) {
          this.hitTarget(teamId, target, knight.damage);
          rt.cooldown = 1 / knight.attackSpeed;
        }
        return;
      }
      const castlePos = CASTLE_POS[enemyTeam];
      if (dist(knight.x, knight.y, castlePos.x, castlePos.y) <= CASTLE_HIT_RANGE) {
        if (rt.cooldown === 0) {
          this.hitCastle(teamId, enemyTeam, knight.damage);
          rt.cooldown = 1 / knight.attackSpeed;
        }
        return;
      }
    }

    if (rt.hasTarget) {
      const arrived = this.moveTowards(
        knight,
        rt.targetX,
        rt.targetY,
        knight.moveSpeed,
        dt,
        STOP_DISTANCE,
      );
      if (arrived) {
        rt.hasTarget = false;
      }
    }
  }

  private tickUnits(dt: number): void {
    // Snapshot ids first: units can die (be deleted) while we iterate.
    const ids = [...this.state.units.keys()];
    for (const id of ids) {
      if (this.state.phase !== "playing") return;
      const unit = this.state.units.get(id);
      const rt = this.unitRuntime.get(id);
      if (!unit || !rt) continue;

      rt.cooldown = Math.max(0, rt.cooldown - dt);
      const teamId = unit.team as TeamId;
      const enemyTeam = enemyOf(teamId);
      const command = this.state.teams.get(teamId).command;

      if (command === "hold") {
        const target = this.nearestEnemy(enemyTeam, unit.x, unit.y, AGGRO_RADIUS);
        if (target) {
          this.engage(teamId, unit, rt, target, dt);
        }
        continue;
      }

      if (command === "defend") {
        const rally = this.rallyPoint(teamId);
        const target = this.nearestEnemy(enemyTeam, rally.x, rally.y, AGGRO_RADIUS);
        if (target) {
          this.engage(teamId, unit, rt, target, dt);
        } else {
          this.moveTowards(unit, rally.x, rally.y, rt.speed, dt, STOP_DISTANCE);
        }
        continue;
      }

      // "attack": engage nearby enemies, otherwise march on the enemy castle.
      const target = this.nearestEnemy(enemyTeam, unit.x, unit.y, AGGRO_RADIUS);
      if (target) {
        this.engage(teamId, unit, rt, target, dt);
        continue;
      }
      const castlePos = CASTLE_POS[enemyTeam];
      if (dist(unit.x, unit.y, castlePos.x, castlePos.y) <= CASTLE_HIT_RANGE) {
        if (rt.cooldown === 0) {
          this.hitCastle(teamId, enemyTeam, rt.damage);
          rt.cooldown = 1 / UNIT_ATTACK_SPEED;
        }
      } else {
        // Castle sits at lane center, so marching toward it also drifts x to 0.
        this.moveTowards(unit, castlePos.x, castlePos.y, rt.speed, dt, CASTLE_HIT_RANGE * 0.75);
      }
    }
  }

  private engage(
    attackerTeam: TeamId,
    unit: Unit,
    rt: UnitRuntime,
    target: CombatTarget,
    dt: number,
  ): void {
    const d = dist(unit.x, unit.y, target.ref.x, target.ref.y);
    if (d <= MELEE_RANGE) {
      if (rt.cooldown === 0) {
        this.hitTarget(attackerTeam, target, rt.damage);
        rt.cooldown = 1 / UNIT_ATTACK_SPEED;
      }
    } else {
      this.moveTowards(unit, target.ref.x, target.ref.y, rt.speed, dt, MELEE_RANGE * 0.75);
    }
  }

  /** Nearest living enemy combatant (knight or unit) within maxDist, or null. */
  private nearestEnemy(
    enemyTeam: TeamId,
    x: number,
    y: number,
    maxDist: number,
  ): CombatTarget | null {
    let best: CombatTarget | null = null;
    let bestDist = maxDist;

    const knight = this.state.knights.get(enemyTeam);
    if (knight && knight.alive) {
      const d = dist(x, y, knight.x, knight.y);
      if (d <= bestDist) {
        bestDist = d;
        best = { kind: "knight", team: enemyTeam, ref: knight };
      }
    }
    this.state.units.forEach((unit, id) => {
      if (unit.team !== enemyTeam) return;
      const d = dist(x, y, unit.x, unit.y);
      if (d <= bestDist) {
        bestDist = d;
        best = { kind: "unit", team: enemyTeam, id, ref: unit };
      }
    });
    return best;
  }

  private hitTarget(attackerTeam: TeamId, target: CombatTarget, damage: number): void {
    const armor = target.kind === "knight" ? target.ref.armor : 0;
    target.ref.hp -= Math.max(1, damage - armor);
    if (target.ref.hp > 0) return;

    if (target.kind === "unit") {
      this.state.units.delete(target.id);
      this.unitRuntime.delete(target.id);
      this.state.teams.get(attackerTeam).gold += this.config.unit_kill_reward;
    } else {
      const knight = target.ref;
      knight.hp = 0;
      knight.alive = false;
      knight.respawnIn = this.config.knight_respawn_seconds;
      this.knightRuntime[target.team].hasTarget = false;
      this.state.teams.get(attackerTeam).gold += this.config.knight_kill_reward;
    }
  }

  private hitCastle(attackerTeam: TeamId, castleTeam: TeamId, damage: number): void {
    const castle = this.state.castles.get(castleTeam);
    castle.hp = Math.max(0, castle.hp - Math.max(1, damage));
    if (castle.hp === 0) {
      this.finishMatch(attackerTeam);
    }
  }

  /** Moves entity toward (tx, ty), clamped to map bounds. Returns true when arrived. */
  private moveTowards(
    entity: { x: number; y: number },
    tx: number,
    ty: number,
    speed: number,
    dt: number,
    stopDistance: number,
  ): boolean {
    const dx = tx - entity.x;
    const dy = ty - entity.y;
    const d = Math.hypot(dx, dy);
    if (d <= stopDistance) return true;

    const step = speed * dt;
    if (step >= d) {
      entity.x = tx;
      entity.y = ty;
    } else {
      entity.x += (dx / d) * step;
      entity.y += (dy / d) * step;
    }
    entity.x = clamp(entity.x, MAP_MIN_X, MAP_MAX_X);
    entity.y = clamp(entity.y, MAP_MIN_Y, MAP_MAX_Y);
    return false;
  }

  private rallyPoint(teamId: TeamId): { x: number; y: number } {
    const castlePos = CASTLE_POS[teamId];
    return {
      x: castlePos.x,
      y: castlePos.y + (teamId === "blue" ? RALLY_OFFSET : -RALLY_OFFSET),
    };
  }

  // ------------------------------------------------------------------ setup

  private initTeam(teamId: TeamId): void {
    const team = new Team();
    team.gold = this.config.starting_gold;
    team.nextMineCost = this.config.mine_base_cost;
    this.state.teams.set(teamId, team);

    const knight = new Knight();
    knight.team = teamId;
    knight.x = KNIGHT_SPAWN[teamId].x;
    knight.y = KNIGHT_SPAWN[teamId].y;
    knight.hp = knight.maxHp = this.config.knight_hp;
    knight.moveSpeed = this.config.knight_move_speed;
    knight.armor = this.config.knight_armor;
    this.state.knights.set(teamId, knight);

    const castle = new Castle();
    castle.team = teamId;
    castle.hp = castle.maxHp = this.config.castle_hp;
    this.state.castles.set(teamId, castle);
  }

  private fillConfigSnapshot(): void {
    const snapshot = this.state.config;
    for (const item of ITEM_IDS) {
      snapshot.itemPrices.set(item, this.config[`item_price_${item}`]);
    }
    for (const type of UNIT_TYPES) {
      snapshot.unitCosts.set(type, this.config[`unit_${type}_cost`]);
    }
    snapshot.maxItems = this.config.max_items;
    snapshot.incomePerMine = this.config.mine_income;
    snapshot.unitKillReward = this.config.unit_kill_reward;
    snapshot.knightKillReward = this.config.knight_kill_reward;
  }

  private bindHandler(
    messageType: string,
    handler: (teamId: TeamId, payload: unknown) => void,
  ): void {
    this.onMessage(messageType, (client: Client, payload: unknown) => {
      try {
        const teamId = this.teamOf(client.sessionId);
        if (teamId) {
          handler(teamId, payload);
        }
      } catch (error) {
        // Never let malformed input crash the room.
        console.error(`Error handling "${messageType}" from ${client.sessionId}:`, error);
      }
    });
  }

  private teamOf(sessionId: string): TeamId | null {
    for (const teamId of TEAM_IDS) {
      if (this.state.teams.get(teamId)?.sessionId === sessionId) {
        return teamId;
      }
    }
    return null;
  }

  private startMatch(): void {
    if (this.state.phase !== "waiting") return;
    this.state.phase = "playing";
    if (this.mode === "solo") {
      this.bot = new BotController(this, "red");
      this.clock.setInterval(() => this.bot?.tick(), BOT_TICK_MS);
    }
    console.log(`Match started in room ${this.roomId} (${this.mode})`);
  }

  private finishMatch(winner: TeamId): void {
    if (this.state.phase === "finished") return;
    this.state.phase = "finished";
    this.state.winner = winner;
    console.log(`Match finished in room ${this.roomId}, winner: ${winner}`);
    this.clock.setTimeout(() => {
      try {
        this.disconnect();
      } catch {
        // Room already disposed.
      }
    }, FINISHED_DISPOSE_MS);
  }

  private applyItemEffect(knight: Knight, item: ItemId): void {
    switch (item) {
      case "sword":
      case "hammer": {
        const weapon = WEAPON_STATS[item];
        knight.damage = weapon.damage;
        knight.attackSpeed = weapon.attackSpeed;
        break;
      }
      case "boots":
        knight.moveSpeed *= 1.2;
        break;
      case "armor": {
        const added = knight.maxHp * 0.5;
        knight.maxHp += added;
        knight.hp = Math.min(knight.maxHp, knight.hp + added);
        break;
      }
    }
  }
}

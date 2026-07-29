/**
 * All gameplay tunables in one flat, typed object. The keys below are also
 * the exact keys accepted as `configOverrides` when creating a solo room.
 */

export const UNIT_TYPES = [
  "achilles",
  "executioner",
  "ghost",
  "ninja",
  "peasant",
  "pirate",
  "priest",
  "shaman",
  "viking",
  "zombie",
] as const;
export type UnitType = (typeof UNIT_TYPES)[number];

export const ITEM_IDS = ["sword", "hammer", "boots", "armor"] as const;
export type ItemId = (typeof ITEM_IDS)[number];

export function isUnitType(value: string): value is UnitType {
  return (UNIT_TYPES as readonly string[]).includes(value);
}

export function isItemId(value: string): value is ItemId {
  return (ITEM_IDS as readonly string[]).includes(value);
}

/** Fixed weapon profiles. The last weapon bought sets the knight's damage/attackSpeed. */
export const WEAPON_STATS: Record<"sword" | "hammer", { damage: number; attackSpeed: number }> = {
  sword: { damage: 10, attackSpeed: 1.5 },
  hammer: { damage: 35, attackSpeed: 0.5 },
};

export type GameConfig = Record<string, number>;

/** Per-unit defaults as [cost, hp, damage, speed]. */
const UNIT_STATS: Record<UnitType, [number, number, number, number]> = {
  peasant: [20, 50, 5, 220],
  zombie: [30, 90, 6, 140],
  ghost: [40, 60, 10, 260],
  ninja: [50, 70, 14, 280],
  pirate: [60, 100, 12, 220],
  shaman: [70, 80, 10, 210],
  priest: [70, 70, 8, 210],
  viking: [80, 140, 14, 200],
  executioner: [90, 120, 20, 190],
  achilles: [120, 180, 22, 240],
};

function buildDefaults(): GameConfig {
  const config: GameConfig = {
    starting_gold: 100,
    mine_base_cost: 100,
    mine_income: 10,
    unit_kill_reward: 15,
    knight_kill_reward: 50,
    castle_hp: 1000,
    knight_respawn_seconds: 5,
    knight_hp: 100,
    knight_move_speed: 260,
    knight_armor: 1,
    item_price_sword: 50,
    item_price_hammer: 80,
    item_price_boots: 60,
    item_price_armor: 70,
    max_items: 4,
    // Combat/collision tuning. Keep melee_range >= 2 * unit_radius so units
    // packed against each other can still land hits.
    melee_range: 60,
    unit_radius: 28,
  };
  for (const type of UNIT_TYPES) {
    const [cost, hp, damage, speed] = UNIT_STATS[type];
    config[`unit_${type}_cost`] = cost;
    config[`unit_${type}_hp`] = hp;
    config[`unit_${type}_damage`] = damage;
    config[`unit_${type}_speed`] = speed;
  }
  return config;
}

export const DEFAULT_CONFIG: Readonly<GameConfig> = Object.freeze(buildDefaults());

const MIN_OVERRIDE = 0;
const MAX_OVERRIDE = 100_000;

/**
 * Returns a fresh config with valid overrides applied on top of the defaults.
 * Unknown keys and non-finite / out-of-range values are silently ignored.
 * Callers must only pass client overrides for solo rooms; PvP uses defaults.
 */
export function applyOverrides(overrides: unknown): GameConfig {
  const config: GameConfig = { ...DEFAULT_CONFIG };
  if (overrides === null || typeof overrides !== "object" || Array.isArray(overrides)) {
    return config;
  }
  for (const [key, value] of Object.entries(overrides as Record<string, unknown>)) {
    if (!Object.prototype.hasOwnProperty.call(DEFAULT_CONFIG, key)) continue;
    if (typeof value !== "number" || !Number.isFinite(value)) continue;
    if (value < MIN_OVERRIDE || value > MAX_OVERRIDE) continue;
    config[key] = value;
  }
  return config;
}

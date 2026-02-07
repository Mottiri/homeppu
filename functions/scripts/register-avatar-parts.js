/* eslint-disable no-console */
const fs = require("fs");
const path = require("path");
const admin = require("firebase-admin");

const PARTS = [
  { dir: "hair", listKey: "hairIds" },
  { dir: "eyebrows", listKey: "eyebrowsIds" },
  { dir: "eyes", listKey: "eyesIds" },
  { dir: "mouth", listKey: "mouthIds" },
];
const RARITIES = new Set(["common", "rare", "epic"]);
const COST_SUFFIX_PATTERN = /^(.*)_(common|rare|epic)_(\d+)$/;
const RARITY_SUFFIX_PATTERN = /^(.*)_(common|rare|epic)$/;
const VALID_ID_PATTERN = /^[a-zA-Z_][a-zA-Z0-9_]*$/;
const SETTINGS_DOC_ID = "virtueShop";

function parseArgs(argv) {
  const args = {};
  for (let i = 0; i < argv.length; i += 1) {
    const token = argv[i];
    if (!token.startsWith("--")) continue;
    const key = token.slice(2);
    const next = argv[i + 1];
    if (!next || next.startsWith("--")) {
      args[key] = true;
    } else {
      args[key] = next;
      i += 1;
    }
  }
  return args;
}

function toNumber(value, label) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) {
    throw new Error(`${label} must be a finite number. received=${value}`);
  }
  if (parsed < 0) {
    throw new Error(`${label} must be >= 0. received=${value}`);
  }
  return Math.trunc(parsed);
}

function walkPngFiles(dir) {
  const results = [];
  const stack = [dir];
  while (stack.length > 0) {
    const current = stack.pop();
    const entries = fs.readdirSync(current, { withFileTypes: true });
    for (const entry of entries) {
      const fullPath = path.join(current, entry.name);
      if (entry.isDirectory()) {
        stack.push(fullPath);
        continue;
      }
      if (entry.isFile() && entry.name.toLowerCase().endsWith(".png")) {
        results.push(fullPath);
      }
    }
  }
  return results.sort((a, b) => a.localeCompare(b));
}

function parseDartStringMap(content, mapName) {
  const pattern = new RegExp(
    `static const Map<String, String> ${mapName} = \\{([\\s\\S]*?)\\n\\s*\\};`
  );
  const match = content.match(pattern);
  if (!match) return {};

  const result = {};
  const lines = match[1].split(/\r?\n/);
  for (const rawLine of lines) {
    const line = rawLine.trim();
    if (!line || line.startsWith("//")) continue;
    const entry = line.match(/^'([^']+)':\s*'([^']+)',?$/);
    if (!entry) continue;
    result[entry[1]] = entry[2];
  }
  return result;
}

function replaceDartList(content, listKey, ids) {
  const values = ids.map((id) => `'${id}'`).join(", ");
  const replacement = `static const List<String> ${listKey} = [${values}];`;
  const pattern = new RegExp(`static const List<String> ${listKey} = \\[[^\\]]*\\];`);
  if (!pattern.test(content)) {
    throw new Error(`List block not found for ${listKey}`);
  }
  return content.replace(pattern, replacement);
}

function buildDartMapBlock(mapName, groupedEntries) {
  const lines = [`  static const Map<String, String> ${mapName} = {`];
  for (const group of groupedEntries) {
    lines.push(`    // ${group.part}`);
    for (const entry of group.entries) {
      lines.push(`    '${entry.id}': '${entry.value}',`);
    }
  }
  lines.push("  };");
  return lines.join("\n");
}

function upsertDartMap(content, mapName, groupedEntries) {
  const replacement = buildDartMapBlock(mapName, groupedEntries);
  const pattern = new RegExp(
    `\\s*static const Map<String, String> ${mapName} = \\{[\\s\\S]*?\\n\\s*\\};`
  );
  if (pattern.test(content)) {
    return content.replace(pattern, `\n${replacement}`);
  }

  const insertBefore = "  static String hairPath(String id) =>";
  const insertIndex = content.indexOf(insertBefore);
  if (insertIndex === -1) {
    throw new Error(`Insertion anchor not found for ${mapName}`);
  }
  return (
    content.slice(0, insertIndex) +
    `${replacement}\n\n` +
    content.slice(insertIndex)
  );
}

function replaceAvatarPathHelpers(content) {
  const replacements = [
    {
      from: /static String hairPath\(String id\) => 'assets\/avatars\/hair\/\$id\.png';/,
      to: "static String hairPath(String id) => 'assets/avatars/hair/${partAssetNameById[id] ?? id}.png';",
    },
    {
      from: /static String eyesPath\(String id\) => 'assets\/avatars\/eyes\/\$id\.png';/,
      to: "static String eyesPath(String id) => 'assets/avatars/eyes/${partAssetNameById[id] ?? id}.png';",
    },
    {
      from: /static String mouthPath\(String id\) => 'assets\/avatars\/mouth\/\$id\.png';/,
      to: "static String mouthPath(String id) => 'assets/avatars/mouth/${partAssetNameById[id] ?? id}.png';",
    },
    {
      from: /static String eyebrowsPath\(String id\) => 'assets\/avatars\/eyebrows\/\$id\.png';/,
      to: "static String eyebrowsPath(String id) => 'assets/avatars/eyebrows/${partAssetNameById[id] ?? id}.png';",
    },
  ];

  let next = content;
  for (const item of replacements) {
    if (!item.from.test(next)) continue;
    next = next.replace(item.from, item.to);
  }
  return next;
}

function buildTsRarityMap(groupedEntries) {
  const lines = ["const AVATAR_PART_RARITY: Record<string, string> = {"];
  for (const group of groupedEntries) {
    lines.push(`    // ${group.part}`);
    for (const entry of group.entries) {
      lines.push(`    ${entry.id}: "${entry.value}",`);
    }
  }
  lines.push("};");
  return lines.join("\n");
}

function replaceTsRarityMap(content, groupedEntries) {
  const replacement = buildTsRarityMap(groupedEntries);
  const pattern =
    /const AVATAR_PART_RARITY: Record<string, string> = \{[\s\S]*?\n\};/;
  if (!pattern.test(content)) {
    throw new Error("AVATAR_PART_RARITY block not found in virtue_shop.ts");
  }
  return content.replace(pattern, replacement);
}

function normalizeRarityCosts(raw) {
  const result = {};
  if (!raw || typeof raw !== "object") return result;
  for (const [key, value] of Object.entries(raw)) {
    if (!RARITIES.has(key)) continue;
    if (typeof value !== "number" || !Number.isFinite(value)) continue;
    result[key] = Math.trunc(value);
  }
  return result;
}

async function syncAvatarCostsInFirestore(records, args) {
  const dryRun = !!args["dry-run"] || !!args.dry;
  const skipFirestore = !!args["no-firestore"];
  if (skipFirestore) {
    console.log("Firestore update skipped (--no-firestore).");
    return;
  }

  if (!admin.apps.length) {
    admin.initializeApp();
  }
  const db = admin.firestore();
  const docRef = db.collection("settings").doc(SETTINGS_DOC_ID);
  const snap = await docRef.get();
  if (!snap.exists) {
    throw new Error(`settings/${SETTINGS_DOC_ID} not found`);
  }

  const data = snap.data() || {};
  const fallback = normalizeRarityCosts(data.namePartCostsByRarity);
  const current = Object.keys(normalizeRarityCosts(data.avatarPartCostsByRarity))
    .length
    ? normalizeRarityCosts(data.avatarPartCostsByRarity)
    : fallback;

  if (args["common-cost"] !== undefined) {
    current.common = toNumber(args["common-cost"], "--common-cost");
  }
  if (args["rare-cost"] !== undefined) {
    current.rare = toNumber(args["rare-cost"], "--rare-cost");
  }
  if (args["epic-cost"] !== undefined) {
    current.epic = toNumber(args["epic-cost"], "--epic-cost");
  }

  const detectedRarities = new Set(records.map((record) => record.rarity));
  if (detectedRarities.has("rare") && (current.rare ?? 0) <= 0) {
    throw new Error(
      "Rare avatar parts detected, but avatarPartCostsByRarity.rare is missing or <= 0. Set it in Firestore or pass --rare-cost."
    );
  }

  const nextCosts = {};
  for (const rarity of ["common", "rare", "epic"]) {
    if (current[rarity] === undefined) continue;
    nextCosts[rarity] = current[rarity];
  }

  if (dryRun) {
    console.log("[DryRun] Firestore avatarPartCostsByRarity preview:", nextCosts);
    return;
  }

  await docRef.update({
    avatarPartCostsByRarity: nextCosts,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  console.log("Firestore avatarPartCostsByRarity updated.");
}

function parseStem(stem) {
  const costMatch = stem.match(COST_SUFFIX_PATTERN);
  if (costMatch) {
    return {
      error: "cost_suffix_not_supported",
      id: costMatch[1],
      rarity: costMatch[2],
      cost: Number(costMatch[3]),
    };
  }

  const rarityMatch = stem.match(RARITY_SUFFIX_PATTERN);
  if (!rarityMatch) return null;
  const id = rarityMatch[1];
  const rarity = rarityMatch[2];
  if (!id) return null;
  return { id, rarity };
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const dryRun = !!args["dry-run"] || !!args.dry;
  const strict = !!args.strict;
  const rootDir = path.resolve(__dirname, "..", "..");
  const avatarsDir = path.resolve(rootDir, args.assets || "assets/avatars");
  const avatarAssetsPath = path.resolve(
    rootDir,
    "lib",
    "core",
    "constants",
    "avatar_assets.dart"
  );
  const virtueShopPath = path.resolve(
    rootDir,
    "functions",
    "src",
    "callable",
    "virtue_shop.ts"
  );

  if (!fs.existsSync(avatarsDir)) {
    throw new Error(`Assets directory not found: ${avatarsDir}`);
  }
  if (!fs.existsSync(avatarAssetsPath)) {
    throw new Error(`avatar_assets.dart not found: ${avatarAssetsPath}`);
  }
  if (!fs.existsSync(virtueShopPath)) {
    throw new Error(`virtue_shop.ts not found: ${virtueShopPath}`);
  }

  const avatarAssetsContent = fs.readFileSync(avatarAssetsPath, "utf-8");
  const existingRarityById = parseDartStringMap(avatarAssetsContent, "partRarity");
  const existingAssetNameById = parseDartStringMap(
    avatarAssetsContent,
    "partAssetNameById"
  );

  const records = [];
  const seenIds = new Map();
  const legacyStems = [];

  for (const part of PARTS) {
    const partDir = path.join(avatarsDir, part.dir);
    if (!fs.existsSync(partDir)) {
      throw new Error(`Missing directory: ${partDir}`);
    }

    const pngFiles = walkPngFiles(partDir);
    if (pngFiles.length === 0) {
      throw new Error(`No PNG files found in: ${partDir}`);
    }

    for (const filePath of pngFiles) {
      const stem = path.basename(filePath, ".png");
      const parsed = parseStem(stem);

      let id;
      let rarity;
      if (parsed?.error === "cost_suffix_not_supported") {
        throw new Error(
          `Cost suffix is not supported for avatar assets: ${stem}.png. Use "<id>_<rarity>.png".`
        );
      }

      if (parsed) {
        id = parsed.id;
        rarity = parsed.rarity;
      } else {
        if (strict) {
          throw new Error(
            `Invalid file name: ${stem}.png. Expected "<id>_<common|rare|epic>.png".`
          );
        }
        id = stem;
        rarity = existingRarityById[id] || "common";
        legacyStems.push(stem);
      }

      if (!VALID_ID_PATTERN.test(id)) {
        throw new Error(`Invalid id "${id}" from ${filePath}`);
      }
      if (!RARITIES.has(rarity)) {
        throw new Error(`Invalid rarity "${rarity}" for id "${id}" from ${filePath}`);
      }
      if (!id.startsWith(`${part.dir}_`)) {
        throw new Error(
          `Invalid id prefix for ${filePath}. id="${id}" must start with "${part.dir}_".`
        );
      }

      if (seenIds.has(id)) {
        throw new Error(
          `Duplicate avatar id "${id}":\n- ${seenIds.get(id)}\n- ${filePath}`
        );
      }
      seenIds.set(id, filePath);

      records.push({
        part: part.dir,
        listKey: part.listKey,
        id,
        rarity,
        assetName: stem,
      });
    }
  }

  records.sort((a, b) => {
    const partIndexA = PARTS.findIndex((part) => part.dir === a.part);
    const partIndexB = PARTS.findIndex((part) => part.dir === b.part);
    if (partIndexA !== partIndexB) return partIndexA - partIndexB;
    return a.id.localeCompare(b.id);
  });

  const idsByPart = Object.fromEntries(PARTS.map((part) => [part.dir, []]));
  const rarityByPart = Object.fromEntries(PARTS.map((part) => [part.dir, []]));
  const assetNameByPart = Object.fromEntries(PARTS.map((part) => [part.dir, []]));
  const nextRarityById = {};
  const nextAssetNameById = {};

  for (const record of records) {
    idsByPart[record.part].push(record.id);
    rarityByPart[record.part].push({ id: record.id, value: record.rarity });
    assetNameByPart[record.part].push({ id: record.id, value: record.assetName });
    nextRarityById[record.id] = record.rarity;
    nextAssetNameById[record.id] = record.assetName;
  }

  for (const part of PARTS) {
    idsByPart[part.dir].sort((a, b) => a.localeCompare(b));
    rarityByPart[part.dir].sort((a, b) => a.id.localeCompare(b.id));
    assetNameByPart[part.dir].sort((a, b) => a.id.localeCompare(b.id));
  }

  const existingIds = new Set([
    ...Object.keys(existingRarityById),
    ...Object.keys(existingAssetNameById),
  ]);
  const nextIds = new Set(records.map((record) => record.id));
  const addedIds = [];
  const removedIds = [];
  const updatedIds = [];
  const unchangedIds = [];

  for (const id of Array.from(nextIds).sort()) {
    if (!existingIds.has(id)) {
      addedIds.push(id);
      continue;
    }
    const beforeRarity = existingRarityById[id] || null;
    const beforeAssetName = existingAssetNameById[id] || id;
    const afterRarity = nextRarityById[id] || null;
    const afterAssetName = nextAssetNameById[id] || id;
    if (beforeRarity !== afterRarity || beforeAssetName !== afterAssetName) {
      updatedIds.push(id);
    } else {
      unchangedIds.push(id);
    }
  }

  for (const id of Array.from(existingIds).sort()) {
    if (!nextIds.has(id)) {
      removedIds.push(id);
    }
  }

  const groupedRarityEntries = PARTS.map((part) => ({
    part: part.dir,
    entries: rarityByPart[part.dir],
  }));
  const groupedAssetNameEntries = PARTS.map((part) => ({
    part: part.dir,
    entries: assetNameByPart[part.dir],
  }));

  let nextAvatarAssetsContent = avatarAssetsContent;
  for (const part of PARTS) {
    nextAvatarAssetsContent = replaceDartList(
      nextAvatarAssetsContent,
      part.listKey,
      idsByPart[part.dir]
    );
  }
  nextAvatarAssetsContent = upsertDartMap(
    nextAvatarAssetsContent,
    "partRarity",
    groupedRarityEntries
  );
  nextAvatarAssetsContent = upsertDartMap(
    nextAvatarAssetsContent,
    "partAssetNameById",
    groupedAssetNameEntries
  );
  nextAvatarAssetsContent = replaceAvatarPathHelpers(nextAvatarAssetsContent);

  const virtueShopContent = fs.readFileSync(virtueShopPath, "utf-8");
  const nextVirtueShopContent = replaceTsRarityMap(
    virtueShopContent,
    groupedRarityEntries
  );

  await syncAvatarCostsInFirestore(records, args);

  if (dryRun) {
    console.log("=== Dry Run ===");
    console.log(`Detected records: ${records.length}`);
    console.log(`Added: ${addedIds.length}`);
    if (addedIds.length) console.log(`- ${addedIds.join(", ")}`);
    console.log(`Updated: ${updatedIds.length}`);
    if (updatedIds.length) console.log(`- ${updatedIds.join(", ")}`);
    console.log(`Removed: ${removedIds.length}`);
    if (removedIds.length) console.log(`- ${removedIds.join(", ")}`);
    console.log(`Unchanged: ${unchangedIds.length}`);
    if (unchangedIds.length) console.log(`- ${unchangedIds.join(", ")}`);
    console.log(`Legacy filenames used: ${legacyStems.length}`);
    if (legacyStems.length) console.log(`- ${legacyStems.join(", ")}`);
    return;
  }

  fs.writeFileSync(avatarAssetsPath, nextAvatarAssetsContent, "utf-8");
  fs.writeFileSync(virtueShopPath, nextVirtueShopContent, "utf-8");

  console.log("avatar_assets.dart updated.");
  console.log("virtue_shop.ts updated.");
  console.log("=== Summary ===");
  console.log(`Added: ${addedIds.length}`);
  if (addedIds.length) console.log(`- ${addedIds.join(", ")}`);
  console.log(`Updated: ${updatedIds.length}`);
  if (updatedIds.length) console.log(`- ${updatedIds.join(", ")}`);
  console.log(`Removed: ${removedIds.length}`);
  if (removedIds.length) console.log(`- ${removedIds.join(", ")}`);
  console.log(`Unchanged: ${unchangedIds.length}`);
  if (unchangedIds.length) console.log(`- ${unchangedIds.join(", ")}`);
  console.log(`Legacy filenames used: ${legacyStems.length}`);
  if (legacyStems.length) console.log(`- ${legacyStems.join(", ")}`);
  console.log("Done.");
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});

/* eslint-disable no-console */
const fs = require("fs");
const path = require("path");
const admin = require("firebase-admin");

const DEFAULT_RARE_COST = null;
const BEGIN_MARKER = "// BEGIN AUTO REACTION TYPES";
const END_MARKER = "// END AUTO REACTION TYPES";
const RARITY_COLORS = {
  common: "0xFFB0BEC5",
  rare: "0xFF64B5F6",
  epic: "0xFF9575CD",
};
const DEFAULT_EMOJI = "✨";

function parseArgs(argv) {
  const args = {};
  for (let i = 0; i < argv.length; i += 1) {
    const token = argv[i];
    if (!token.startsWith("--")) continue;
    const key = token.replace(/^--/, "");
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

function isValidId(id) {
  return /^[a-zA-Z_][a-zA-Z0-9_]*$/.test(id);
}

function parseFileName(baseName) {
  const parts = baseName.split("_");
  if (parts.length < 2) return null;

  let cost = null;
  const last = parts[parts.length - 1];
  if (/^\d+$/.test(last)) {
    cost = Number(last);
    parts.pop();
  }

  const rarity = parts[parts.length - 1];
  if (!["common", "rare", "epic"].includes(rarity)) {
    return null;
  }
  parts.pop();

  const id = parts.join("_");
  if (!id) return null;

  return { id, rarity, cost };
}

function parseReactionEntries(block) {
  const entries = [];
  const lines = block.split(/\r?\n/);
  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("//")) continue;

    const baseMatch = trimmed.match(
      /^([a-zA-Z0-9_]+)\('([^']*)',\s*'([^']*)',\s*'([^']*)',\s*(0x[0-9A-Fa-f]+),\s*ReactionRarity\.(common|rare|epic)(.*)\),?$/
    );
    if (!baseMatch) {
      continue;
    }

    const [, name, value, emoji, label, colorValue, rarity, rest] = baseMatch;
    const assetNameMatch = rest.match(/assetName:\s*'([^']+)'/);
    const virtueCostMatch = rest.match(/virtueCost:\s*(\d+)/);

    entries.push({
      name,
      value,
      emoji,
      label,
      colorValue,
      rarity,
      assetName: assetNameMatch ? assetNameMatch[1] : null,
      virtueCost: virtueCostMatch ? Number(virtueCostMatch[1]) : null,
    });
  }
  return entries;
}

function formatEntry(entry) {
  const args = [];
  if (entry.assetName && entry.assetName !== entry.value) {
    args.push(`assetName: '${entry.assetName}'`);
  }
  if (entry.virtueCost !== null && entry.virtueCost !== undefined) {
    args.push(`virtueCost: ${entry.virtueCost}`);
  }

  const tail = args.length ? `, ${args.join(", ")}` : "";
  return `  ${entry.name}('${entry.value}', '${entry.emoji}', '${entry.label}', ${entry.colorValue}, ReactionRarity.${entry.rarity}${tail}),`;
}

async function updateVirtueShopConfig(entries, options) {
  if (options.skipFirestore) {
    console.log("Firestore update skipped (--no-firestore).");
    return;
  }

  if (!admin.apps.length) {
    admin.initializeApp();
  }

  const db = admin.firestore();
  const docRef = db.collection("settings").doc("virtueShop");
  const snap = await docRef.get();
  if (!snap.exists) {
    throw new Error("settings/virtueShop not found");
  }

  const data = snap.data() || {};
  const reactionCostsById = { ...(data.reactionCostsById || {}) };

  for (const entry of entries) {
    if (entry.rarity === "rare") {
      reactionCostsById[entry.value] = entry.virtueCost || 0;
    } else {
      delete reactionCostsById[entry.value];
    }
  }

  if (options.dryRun) {
    console.log("[DryRun] reactionCostsById update preview:", reactionCostsById);
    return;
  }

  await docRef.update({
    reactionCostsById,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  console.log("Firestore reactionCostsById updated.");
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const rootDir = path.resolve(__dirname, "..", "..");
  const assetsDir = path.resolve(rootDir, args.assets || "assets/reactions");
  const appConstantsPath = path.resolve(
    rootDir,
    "lib",
    "core",
    "constants",
    "app_constants.dart"
  );

  const defaultRareCost =
    args["default-rare-cost"] !== undefined
      ? Number(args["default-rare-cost"])
      : DEFAULT_RARE_COST;
  const dryRun = !!args["dry-run"] || !!args["dry"];
  const skipFirestore = !!args["no-firestore"];

  if (!fs.existsSync(assetsDir)) {
    throw new Error(`Assets directory not found: ${assetsDir}`);
  }
  if (!fs.existsSync(appConstantsPath)) {
    throw new Error(`app_constants.dart not found: ${appConstantsPath}`);
  }

  const files = fs
    .readdirSync(assetsDir)
    .filter((file) => file.toLowerCase().endsWith(".png"));

  const parsedAssets = [];
  const skippedAssets = [];
  const seenIds = new Set();

  for (const file of files) {
    const baseName = path.basename(file, ".png");
    const parsed = parseFileName(baseName);
    if (!parsed) {
      skippedAssets.push(baseName);
      continue;
    }

    if (!isValidId(parsed.id)) {
      throw new Error(
        `Invalid id "${parsed.id}". Use [a-zA-Z0-9_]. Source: ${file}`
      );
    }

    if (seenIds.has(parsed.id)) {
      throw new Error(
        `Duplicate id "${parsed.id}". Resolve assets naming conflict.`
      );
    }
    seenIds.add(parsed.id);

    if (parsed.rarity === "rare") {
      if (!parsed.cost && defaultRareCost) {
        parsed.cost = defaultRareCost;
      }
      if (!parsed.cost) {
        throw new Error(
          `Rare stamp "${parsed.id}" requires cost. Add _<cost> to filename or use --default-rare-cost.`
        );
      }
    }

    parsedAssets.push({
      ...parsed,
      assetName: baseName,
    });
  }

  const content = fs.readFileSync(appConstantsPath, "utf-8");
  const beginIndex = content.indexOf(BEGIN_MARKER);
  const endIndex = content.indexOf(END_MARKER);
  if (beginIndex === -1 || endIndex === -1 || endIndex <= beginIndex) {
    throw new Error("Auto reaction markers not found in app_constants.dart");
  }

  const beginLineEnd = content.indexOf("\n", beginIndex) + 1;
  const block = content.slice(beginLineEnd, endIndex);
  const existingEntries = parseReactionEntries(block);
  const existingByValue = new Map();
  for (const entry of existingEntries) {
    existingByValue.set(entry.value, entry);
  }

  const updatedEntries = [];
  const updatedValues = new Set();
  const addedEntries = [];
  const updatedExistingIds = [];

  for (const asset of parsedAssets) {
    const existing = existingByValue.get(asset.id);
    const colorValue = RARITY_COLORS[asset.rarity];
    const virtueCost = asset.rarity === "rare" ? asset.cost : null;

    if (existing) {
      existing.rarity = asset.rarity;
      existing.colorValue = colorValue;
      existing.virtueCost = virtueCost;
      existing.assetName = asset.assetName;
      updatedValues.add(existing.value);
      updatedExistingIds.push(existing.value);
    } else {
      addedEntries.push({
        name: asset.id,
        value: asset.id,
        emoji: DEFAULT_EMOJI,
        label: asset.id,
        colorValue,
        rarity: asset.rarity,
        assetName: asset.assetName,
        virtueCost,
      });
      updatedValues.add(asset.id);
    }
  }

  for (const entry of existingEntries) {
    updatedEntries.push(entry);
  }

  addedEntries.sort((a, b) => a.value.localeCompare(b.value));
  updatedEntries.push(...addedEntries);

  const lines = updatedEntries.map(formatEntry);
  const updatedContent =
    content.slice(0, beginLineEnd) +
    `${lines.join("\n")}\n` +
    content.slice(endIndex);

  if (dryRun) {
    console.log("=== Dry Run ===");
    console.log(`Detected assets: ${parsedAssets.length}`);
    console.log(`Added entries: ${addedEntries.length}`);
    console.log(`Updated entries: ${updatedExistingIds.length}`);
    console.log(`Skipped assets (no rarity suffix): ${skippedAssets.length}`);
    if (skippedAssets.length) {
      console.log(`- ${skippedAssets.join(", ")}`);
    }
    return;
  }

  fs.writeFileSync(appConstantsPath, updatedContent, "utf-8");
  console.log("app_constants.dart updated.");

  await updateVirtueShopConfig(
    updatedEntries.filter((entry) => updatedValues.has(entry.value)),
    { dryRun, skipFirestore }
  );

  const addedIds = addedEntries.map((entry) => entry.value).sort();
  const updatedIds = Array.from(new Set(updatedExistingIds)).sort();
  console.log("=== Summary ===");
  console.log(`Added: ${addedIds.length}`);
  if (addedIds.length) console.log(`- ${addedIds.join(", ")}`);
  console.log(`Updated: ${updatedIds.length}`);
  if (updatedIds.length) console.log(`- ${updatedIds.join(", ")}`);
  console.log(`Skipped (no rarity suffix): ${skippedAssets.length}`);
  if (skippedAssets.length) console.log(`- ${skippedAssets.join(", ")}`);
  console.log("Done.");
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});

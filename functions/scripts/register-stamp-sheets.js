/* eslint-disable no-console */
const fs = require("fs");
const path = require("path");
const admin = require("firebase-admin");
const { execSync } = require("child_process");

function stripBom(text) {
  if (!text) return text;
  return text.charCodeAt(0) === 0xfeff ? text.slice(1) : text;
}

const RARITIES = new Set(["common", "rare", "epic"]);
const FILE_PATTERN = /^(.*)_(common|rare|epic)$/;

const SETTINGS_COLLECTION = "settings";
const CATALOG_DOC_ID = "stampSheetCatalog";
const LAYOUT_DOC_ID = "stampSheetLayoutCatalog";
const VIRTUE_SHOP_DOC_ID = "virtueShop";

function checkMagickAvailable() {
  try {
    execSync("magick --version", { stdio: "ignore" });
  } catch {
    throw new Error(
      "ImageMagick is required for PNG→WebP conversion but 'magick' was not found on PATH.\n" +
      "Install it from https://imagemagick.org/ and ensure 'magick' is available."
    );
  }
}

function convertPngToWebp(pngPath) {
  if (!_magickChecked) {
    checkMagickAvailable();
    _magickChecked = true;
  }
  const alphaCheck = execSync(`magick identify -format "%A" "${pngPath}"`, { encoding: "utf-8" }).trim();
  const hasAlpha = alphaCheck === "True" || alphaCheck === "Blend";

  const webpPath = pngPath.replace(/\.png$/i, ".webp");
  if (hasAlpha) {
    execSync(`magick "${pngPath}" -define webp:lossless=true "${webpPath}"`);
  } else {
    execSync(`magick "${pngPath}" -quality 90 "${webpPath}"`);
  }

  fs.unlinkSync(pngPath);
  console.log(`Converted: ${path.basename(pngPath)} -> ${path.basename(webpPath)}${hasAlpha ? " (lossless)" : " (lossy q90)"}`);
  return webpPath;
}

let _magickChecked = false;

function ensureWebpAssets(dir) {
  const entries = fs.readdirSync(dir, { withFileTypes: true });
  for (const entry of entries) {
    if (entry.isDirectory()) {
      ensureWebpAssets(path.join(dir, entry.name));
      continue;
    }
    if (!entry.isFile() || !entry.name.toLowerCase().endsWith(".png")) continue;

    const pngPath = path.join(dir, entry.name);
    const webpPath = pngPath.replace(/\.png$/i, ".webp");

    if (fs.existsSync(webpPath)) {
      const pngMtime = fs.statSync(pngPath).mtimeMs;
      const webpMtime = fs.statSync(webpPath).mtimeMs;
      if (pngMtime > webpMtime) {
        convertPngToWebp(pngPath);
        console.log(`Re-converted: ${entry.name} (PNG was newer than WebP)`);
      } else {
        fs.unlinkSync(pngPath);
        console.log(`Removed duplicate PNG: ${entry.name} (WebP is up-to-date)`);
      }
    } else {
      convertPngToWebp(pngPath);
    }
  }
}

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

function toNonNegativeInt(value, label) {
  const n = Number(value);
  if (!Number.isFinite(n)) {
    throw new Error(`${label} must be a finite number. received=${value}`);
  }
  if (n < 0) {
    throw new Error(`${label} must be >= 0. received=${value}`);
  }
  return Math.trunc(n);
}

function isValidId(id) {
  return /^[a-zA-Z_][a-zA-Z0-9_]*$/.test(id);
}

function parseStem(stem) {
  const match = stem.match(FILE_PATTERN);
  if (!match) return null;
  const id = match[1];
  const rarity = match[2];
  if (!id || !RARITIES.has(rarity)) return null;
  return { id, rarity };
}

function sortByDisplayOrderThenId(a, b) {
  const orderA = Number.isFinite(a.displayOrder) ? a.displayOrder : 9999;
  const orderB = Number.isFinite(b.displayOrder) ? b.displayOrder : 9999;
  if (orderA !== orderB) return orderA - orderB;
  return String(a.id).localeCompare(String(b.id));
}

function normalizeCostMap(raw) {
  if (!raw || typeof raw !== "object") return {};
  const map = {};
  for (const [key, value] of Object.entries(raw)) {
    if (!RARITIES.has(key)) continue;
    if (typeof value !== "number" || !Number.isFinite(value)) continue;
    map[key] = Math.trunc(value);
  }
  return map;
}

async function updateFirestore(records, args) {
  const dryRun = !!args["dry-run"] || !!args.dry;
  const skipFirestore = !!args["no-firestore"];
  if (skipFirestore) {
    console.log("Firestore update skipped (--no-firestore).");
    return {
      added: [],
      updated: [],
      removed: [],
      unchanged: records.map((r) => r.id),
      noFirestore: true,
    };
  }

  if (!admin.apps.length) {
    admin.initializeApp();
  }

  const db = admin.firestore();
  const catalogRef = db.collection(SETTINGS_COLLECTION).doc(CATALOG_DOC_ID);
  const layoutRef = db.collection(SETTINGS_COLLECTION).doc(LAYOUT_DOC_ID);
  const virtueShopRef = db.collection(SETTINGS_COLLECTION).doc(VIRTUE_SHOP_DOC_ID);

  const [catalogSnap, layoutSnap, virtueShopSnap] = await Promise.all([
    catalogRef.get(),
    layoutRef.get(),
    virtueShopRef.get(),
  ]);

  const existingSheets = Array.isArray(catalogSnap.data()?.sheets)
    ? catalogSnap.data().sheets
    : [];
  const existingLayouts = Array.isArray(layoutSnap.data()?.layouts)
    ? layoutSnap.data().layouts
    : [];
  const existingCostMap = normalizeCostMap(virtueShopSnap.data()?.stampSheetCostsByRarity);

  const existingById = new Map();
  for (const sheet of existingSheets) {
    if (!sheet || typeof sheet !== "object") continue;
    if (typeof sheet.id !== "string") continue;
    existingById.set(sheet.id, sheet);
  }
  const existingLayoutBySheetId = new Map();
  for (const layout of existingLayouts) {
    if (!layout || typeof layout !== "object") continue;
    if (typeof layout.sheetId !== "string") continue;
    existingLayoutBySheetId.set(layout.sheetId, layout);
  }

  const detectedIds = records.map((r) => r.id).sort();
  const existingIds = Array.from(existingById.keys()).sort();

  const added = [];
  const updated = [];
  const removed = [];
  const unchanged = [];

  const maxExistingOrder = existingSheets.reduce((max, sheet) => {
    const order = Number(sheet?.displayOrder);
    return Number.isFinite(order) ? Math.max(max, order) : max;
  }, 0);
  let nextOrder = maxExistingOrder + 10;

  const nextSheets = records.map((record, index) => {
    const existing = existingById.get(record.id);
    let displayOrder;
    if (Number.isFinite(Number(existing?.displayOrder))) {
      displayOrder = Number(existing.displayOrder);
    } else {
      displayOrder = nextOrder;
      nextOrder += 10;
    }

    const next = {
      id: record.id,
      assetPath: record.assetPath,
      rarity: record.rarity,
      displayOrder,
      isActive: true,
    };

    if (!existing) {
      added.push(record.id);
    } else {
      const changed =
        existing.assetPath !== next.assetPath ||
        existing.rarity !== next.rarity ||
        Number(existing.displayOrder) !== next.displayOrder ||
        existing.isActive !== true;
      if (changed) {
        updated.push(record.id);
      } else {
        unchanged.push(record.id);
      }
    }
    return next;
  });

  for (const id of existingIds) {
    if (!detectedIds.includes(id)) {
      removed.push(id);
    }
  }

  const nextLayouts = records.map((record) => {
    const existing = existingLayoutBySheetId.get(record.id);
    return {
      sheetId: record.id,
      layoutAssetPath: record.layoutAssetPath,
      version: Number.isFinite(Number(existing?.version)) ? Number(existing.version) : 1,
      isActive: true,
      validSlotIds: record.validSlotIds,
    };
  });

  const raritiesInUse = new Set(records.map((r) => r.rarity));
  const nextCostMap = { ...existingCostMap };
  if (args["rare-cost"] !== undefined) {
    nextCostMap.rare = toNonNegativeInt(args["rare-cost"], "--rare-cost");
  }
  if (args["epic-cost"] !== undefined) {
    nextCostMap.epic = toNonNegativeInt(args["epic-cost"], "--epic-cost");
  }

  if (raritiesInUse.has("rare") && (nextCostMap.rare ?? 0) <= 0) {
    throw new Error(
      "Rare sheets detected, but stampSheetCostsByRarity.rare is missing or <= 0. Set in Firestore or pass --rare-cost."
    );
  }

  if (dryRun) {
    console.log("[DryRun] stampSheetCatalog.sheets preview:");
    console.log(JSON.stringify(nextSheets.sort(sortByDisplayOrderThenId), null, 2));
    console.log("[DryRun] stampSheetLayoutCatalog.layouts preview:");
    console.log(JSON.stringify(nextLayouts.sort(sortByDisplayOrderThenId), null, 2));
    console.log("[DryRun] virtueShop.stampSheetCostsByRarity preview:");
    console.log(JSON.stringify(nextCostMap, null, 2));
    return { added, updated, removed, unchanged, noFirestore: false };
  }

  await Promise.all([
    catalogRef.set(
      {
        sheets: nextSheets.sort(sortByDisplayOrderThenId),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    ),
    layoutRef.set(
      {
        layouts: nextLayouts.sort(sortByDisplayOrderThenId),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    ),
    virtueShopRef.set(
      {
        stampSheetCostsByRarity: nextCostMap,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    ),
  ]);

  return { added, updated, removed, unchanged, noFirestore: false };
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const rootDir = path.resolve(__dirname, "..", "..");
  const assetsDir = path.resolve(rootDir, args.assets || "assets/stamp_sheets");
  const layoutsDir = path.resolve(rootDir, args.layouts || "assets/stamp_sheets/layouts");

  if (!fs.existsSync(assetsDir)) {
    throw new Error(`Assets directory not found: ${assetsDir}`);
  }
  if (!fs.existsSync(layoutsDir)) {
    throw new Error(`Layouts directory not found: ${layoutsDir}`);
  }

  ensureWebpAssets(assetsDir);
  const files = fs
    .readdirSync(assetsDir)
    .filter((file) => file.toLowerCase().endsWith(".webp"))
    .sort((a, b) => a.localeCompare(b));

  const seen = new Set();
  const records = [];
  const skipped = [];

  for (const file of files) {
    const stem = path.basename(file, ".webp");
    const parsed = parseStem(stem);
    if (!parsed) {
      skipped.push(stem);
      continue;
    }
    if (!isValidId(parsed.id)) {
      throw new Error(`Invalid id "${parsed.id}" from ${file}`);
    }
    if (seen.has(parsed.id)) {
      throw new Error(`Duplicate sheet id "${parsed.id}" detected. Keep one file per sheet id.`);
    }
    seen.add(parsed.id);

    const layoutFile = path.join(layoutsDir, `${parsed.id}.json`);
    if (!fs.existsSync(layoutFile)) {
      throw new Error(`Missing layout JSON: ${layoutFile}`);
    }

    // Extract validSlotIds from layout JSON
    let validSlotIds = [];
    try {
      const rawLayout = fs.readFileSync(layoutFile, "utf-8");
      const layoutJson = JSON.parse(stripBom(rawLayout));
      validSlotIds = (layoutJson.slots || [])
        .map((s) => s.slotId)
        .filter(Boolean);
    } catch (e) {
      throw new Error(`Failed to parse layout JSON ${layoutFile}: ${e.message}`);
    }
    if (validSlotIds.length === 0) {
      throw new Error(`No valid slotIds found in ${layoutFile}. Each slot must have a slotId.`);
    }

    records.push({
      id: parsed.id,
      rarity: parsed.rarity,
      assetPath: `assets/stamp_sheets/${file.replace(/\\/g, "/")}`,
      layoutAssetPath: `assets/stamp_sheets/layouts/${parsed.id}.json`,
      validSlotIds,
    });
  }

  records.sort((a, b) => a.id.localeCompare(b.id));

  const result = await updateFirestore(records, args);

  console.log("=== Summary ===");
  console.log(`Detected: ${records.length}`);
  if (records.length) {
    console.log(`- ${records.map((r) => r.id).join(", ")}`);
  }
  console.log(`Added: ${result.added.length}`);
  if (result.added.length) console.log(`- ${result.added.join(", ")}`);
  console.log(`Updated: ${result.updated.length}`);
  if (result.updated.length) console.log(`- ${result.updated.join(", ")}`);
  console.log(`Removed: ${result.removed.length}`);
  if (result.removed.length) console.log(`- ${result.removed.join(", ")}`);
  console.log(`Unchanged: ${result.unchanged.length}`);
  if (result.unchanged.length) console.log(`- ${result.unchanged.join(", ")}`);
  if (result.noFirestore) {
    console.log("Note: --no-firestore mode cannot diff against remote state.");
  }
  console.log(`Skipped (invalid naming): ${skipped.length}`);
  if (skipped.length) console.log(`- ${skipped.join(", ")}`);
  console.log("Done.");
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});




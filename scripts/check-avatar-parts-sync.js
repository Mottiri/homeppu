const fs = require("fs");
const path = require("path");

const ROOT = path.resolve(__dirname, "..");
const DART_PATH = path.join(ROOT, "lib", "core", "constants", "avatar_assets.dart");
const TS_PATH = path.join(ROOT, "functions", "src", "config", "avatar-parts.ts");
const PART_LIST_KEYS = ["hairIds", "eyesIds", "mouthIds", "eyebrowsIds"];

function readUtf8(filePath) {
  return fs.readFileSync(filePath, "utf-8");
}

function parseDartList(content, listKey) {
  const pattern = new RegExp(`static const List<String> ${listKey} = \\[([\\s\\S]*?)\\];`);
  const match = content.match(pattern);
  if (!match) {
    throw new Error(`List block not found: ${listKey}`);
  }

  const ids = [];
  const idPattern = /'([^']+)'/g;
  let idMatch;
  while ((idMatch = idPattern.exec(match[1])) !== null) {
    ids.push(idMatch[1]);
  }
  return ids;
}

function parseDartStringMap(content, mapName) {
  const pattern = new RegExp(`static const Map<String, String> ${mapName} = \\{([\\s\\S]*?)\\n\\s*\\};`);
  const match = content.match(pattern);
  if (!match) {
    throw new Error(`Map block not found: ${mapName}`);
  }

  const result = {};
  const entryPattern = /'([^']+)':\s*'([^']+)'/g;
  let entryMatch;
  while ((entryMatch = entryPattern.exec(match[1])) !== null) {
    result[entryMatch[1]] = entryMatch[2];
  }
  return result;
}

function parseTsRarityMap(content) {
  const pattern = /export const AVATAR_PART_RARITY: Record<string, "common" \| "rare" \| "epic"> = \{([\s\S]*?)\n\};/;
  const match = content.match(pattern);
  if (!match) {
    throw new Error("Map block not found: AVATAR_PART_RARITY");
  }

  const result = {};
  const entryPattern = /([a-zA-Z0-9_]+):\s*"([^"]+)"/g;
  let entryMatch;
  while ((entryMatch = entryPattern.exec(match[1])) !== null) {
    result[entryMatch[1]] = entryMatch[2];
  }
  return result;
}

function sorted(values) {
  return [...values].sort((a, b) => a.localeCompare(b));
}

function diffKeys(sourceKeys, targetKeys) {
  const source = new Set(sourceKeys);
  const target = new Set(targetKeys);
  return {
    missingInTarget: sorted([...source].filter((key) => !target.has(key))),
    extraInTarget: sorted([...target].filter((key) => !source.has(key))),
  };
}

function main() {
  const dartContent = readUtf8(DART_PATH);
  const tsContent = readUtf8(TS_PATH);

  const listIds = PART_LIST_KEYS.flatMap((key) => parseDartList(dartContent, key));
  const uniqueListIds = sorted(new Set(listIds));
  const dartRarity = parseDartStringMap(dartContent, "partRarity");
  const tsRarity = parseTsRarityMap(tsContent);

  const issues = [];

  const listVsDart = diffKeys(uniqueListIds, Object.keys(dartRarity));
  if (listVsDart.missingInTarget.length) {
    issues.push(`partRarity missing ids: ${listVsDart.missingInTarget.join(", ")}`);
  }
  if (listVsDart.extraInTarget.length) {
    issues.push(`partRarity has extra ids: ${listVsDart.extraInTarget.join(", ")}`);
  }

  const dartVsTs = diffKeys(Object.keys(dartRarity), Object.keys(tsRarity));
  if (dartVsTs.missingInTarget.length) {
    issues.push(`avatar-parts.ts missing ids: ${dartVsTs.missingInTarget.join(", ")}`);
  }
  if (dartVsTs.extraInTarget.length) {
    issues.push(`avatar-parts.ts has extra ids: ${dartVsTs.extraInTarget.join(", ")}`);
  }

  const differingRarity = sorted(
    Object.keys(dartRarity).filter(
      (id) => tsRarity[id] !== undefined && dartRarity[id] !== tsRarity[id]
    )
  );
  if (differingRarity.length) {
    issues.push(
      `rarity mismatch: ${differingRarity
        .map((id) => `${id} (dart=${dartRarity[id]}, functions=${tsRarity[id]})`)
        .join(", ")}`
    );
  }

  if (issues.length) {
    console.error("Avatar part definitions are out of sync.");
    for (const issue of issues) {
      console.error(`- ${issue}`);
    }
    process.exit(1);
  }

  console.log(
    `Avatar part definitions are in sync. ids=${uniqueListIds.length} functionsIds=${Object.keys(tsRarity).length}`
  );
}

main();

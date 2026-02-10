#!/usr/bin/env node
/* eslint-disable no-console */
const fs = require("fs");
const path = require("path");

const DEFAULT_TARGETS = [
  "lib",
  "functions/src",
  "functions/package.json",
  "docs",
  "scripts",
  "firebase",
  "AGENTS.md",
  "package.json",
];
const ALLOWED_EXTENSIONS = new Set([
  ".ts",
  ".js",
  ".json",
  ".dart",
  ".md",
  ".yaml",
  ".yml",
  ".rules",
  ".txt",
]);

const IGNORE_DIRS = new Set([
  ".git",
  "node_modules",
  "build",
  ".dart_tool",
  ".idea",
  ".vscode",
  ".firebase",
  "ios",
  "android",
  "linux",
  "macos",
  "windows",
  "web",
]);

const IGNORE_FILES = new Set(["scripts/check-mojibake.js"]);

const SUSPICIOUS_PATTERNS = [
  { name: "replacement-char", regex: /\uFFFD/ },
  { name: "halfwidth-katakana", regex: /[\uFF66-\uFF9F]/ },
  { name: "classic-mojibake-token", regex: /(繝|鬯|郢|蟷|隴|蜿|驛|髫|鬮|陝|邵|闕|縺ｮ|縺ｨ|譛)/ },
];

function shouldScanFile(filePath) {
  const normalizedPath = path.relative(process.cwd(), filePath).split(path.sep).join("/");
  if (IGNORE_FILES.has(normalizedPath)) return false;
  const ext = path.extname(filePath).toLowerCase();
  return ALLOWED_EXTENSIONS.has(ext);
}

function walk(currentPath, results) {
  if (!fs.existsSync(currentPath)) return;
  const stat = fs.statSync(currentPath);
  if (stat.isFile()) {
    if (shouldScanFile(currentPath)) {
      results.push(currentPath);
    }
    return;
  }

  const base = path.basename(currentPath);
  if (IGNORE_DIRS.has(base)) return;

  for (const entry of fs.readdirSync(currentPath)) {
    walk(path.join(currentPath, entry), results);
  }
}

function scanFile(filePath) {
  const text = fs.readFileSync(filePath, "utf8");
  const lines = text.split(/\r?\n/);
  const findings = [];

  lines.forEach((line, index) => {
    for (const pattern of SUSPICIOUS_PATTERNS) {
      if (pattern.regex.test(line)) {
        findings.push({
          line: index + 1,
          pattern: pattern.name,
          preview: line.trim().slice(0, 120),
        });
        break;
      }
    }
  });

  return findings;
}

function main() {
  const targets = process.argv.slice(2);
  const scanTargets = targets.length > 0 ? targets : DEFAULT_TARGETS;

  const files = [];
  for (const target of scanTargets) {
    walk(path.resolve(process.cwd(), target), files);
  }

  let hasError = false;
  for (const filePath of files) {
    const findings = scanFile(filePath);
    if (findings.length === 0) continue;

    hasError = true;
    const relativePath = path.relative(process.cwd(), filePath);
    for (const finding of findings) {
      console.error(
        `[mojibake] ${relativePath}:${finding.line} (${finding.pattern}) ${finding.preview}`
      );
    }
  }

  if (hasError) {
    console.error(
      "\n文字化けの疑いがある行が見つかりました。UTF-8( BOMなし )で保存し直してください。"
    );
    process.exit(1);
  }

  console.log("OK: 文字化けパターンは検出されませんでした。");
}

main();

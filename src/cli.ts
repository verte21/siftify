import { execFileSync } from "node:child_process";
import {
  existsSync,
  mkdirSync,
  readdirSync,
  readFileSync,
  renameSync,
  rmdirSync,
  statSync,
  writeFileSync,
} from "node:fs";
import { homedir } from "node:os";
import { basename, dirname, extname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const XRAY_BIN = join(REPO_ROOT, "bin", "file-xray");
const CONFIG_PATH = join(REPO_ROOT, "siftify.config.json");
const HISTORY_DIR = join(REPO_ROOT, ".siftify-history");
const LATEST_HISTORY = join(HISTORY_DIR, "latest.json");

const BOLD = "\x1b[1m";
const DIM = "\x1b[2m";
const GREEN = "\x1b[32m";
const YELLOW = "\x1b[33m";
const CYAN = "\x1b[36m";
const RED = "\x1b[31m";
const RESET = "\x1b[0m";

interface SubfolderRule {
  path: string;
  description: string;
  enabled?: boolean;
  order?: number;
}

interface FolderRule {
  path: string;
  description: string;
  enabled?: boolean;
  icon?: string;
  color?: string;
  order?: number;
  subCostWrong?: number;
  subfolders?: Record<string, SubfolderRule>;
}

interface SiftifyConfig {
  engineUrl?: string;
  basalUrl?: string;
  costs: { wrong: number; defer: number };
  folders: Record<string, FolderRule>;
}

interface FileXRay {
  path: string;
  filename: string;
  ext: string;
  sizeBytes: number;
  uti?: string | null;
  downloadedFrom: string[];
  spotlightTitle?: string | null;
  authors?: string[];
  subject?: string | null;
  pageCount?: number | null;
  durationSeconds?: number | null;
  dimensions?: string | null;
  visionTags: string[];
  archiveEntries: string[];
  extractionMethod?: string | null;
  textPreview?: string | null;
}

interface ClassifierActAnswer {
  action?: string;
  answer?: string;
  choice?: string;
  deferred?: boolean;
  refused?: string;
  confidence?: number;
  probabilities?: Record<string, number>;
}

interface MoveRecord {
  from: string;
  to: string;
  folderKey: string;
  folderPath: string;
  confidence: number;
}

const IGNORED_EXTENSIONS = new Set(["crdownload", "part", "download", "tmp"]);

function expandHome(p: string): string {
  if (p === "~") return homedir();
  if (p.startsWith("~/")) return join(homedir(), p.slice(2));
  return p;
}

function ensureXRayBinary() {
  if (!existsSync(XRAY_BIN)) {
    console.log(`${DIM}Compiling native macOS FileXRay helper...${RESET}`);
    mkdirSync(dirname(XRAY_BIN), { recursive: true });
    execFileSync("swiftc", ["-O", join(REPO_ROOT, "swift", "FileXRay.swift"), "-o", XRAY_BIN], {
      stdio: "inherit",
    });
  }
}

function buildCompactState(x: FileXRay): Record<string, unknown> {
  const state: Record<string, unknown> = {
    filename: x.filename,
    extension: x.ext ? `.${x.ext}` : "(none)",
    size_kb: Math.round((x.sizeBytes / 1024) * 10) / 10,
  };
  if (x.uti) state.macos_type = x.uti;
  if (x.downloadedFrom.length > 0) state.downloaded_from_urls = x.downloadedFrom;
  if (x.spotlightTitle) state.document_title = x.spotlightTitle;
  if (x.authors && x.authors.length > 0) state.authors = x.authors;
  if (x.subject) state.document_subject = x.subject;
  if (typeof x.pageCount === "number") state.page_or_slide_count = x.pageCount;
  if (x.dimensions) state.dimensions = x.dimensions;
  if (typeof x.durationSeconds === "number") state.duration_sec = Math.round(x.durationSeconds * 10) / 10;
  if (x.visionTags.length > 0) state.visual_scene_tags = x.visionTags;
  if (x.archiveEntries.length > 0) state.archive_contents = x.archiveEntries;
  if (x.textPreview) state.extracted_content_preview = x.textPreview;
  return state;
}

function summarizeSignals(x: FileXRay): string {
  const parts: string[] = [];
  if (x.downloadedFrom.length > 0) {
    try {
      const host = new URL(x.downloadedFrom[0]).hostname.replace(/^www\./, "");
      parts.push(`URL:${host}`);
    } catch {
      parts.push("URL");
    }
  }
  const len = x.textPreview?.length ?? 0;
  const pg = typeof x.pageCount === "number" ? `${x.pageCount}p,` : "";
  if (x.extractionMethod === "apple_vision_ocr" && len > 0) {
    parts.push(`VisionOCR(${len}c)`);
  } else if (x.extractionMethod?.startsWith("pdf") && len > 0) {
    parts.push(`PDF(${pg}${len}c)`);
  } else if (x.extractionMethod === "office_textutil" && len > 0) {
    parts.push(`${x.ext.toUpperCase()}(${len}c)`);
  } else if (x.extractionMethod === "pptx_slides" && len > 0) {
    parts.push(`PPTX(${pg}${len}c)`);
  } else if (x.extractionMethod === "xlsx_sheets" && len > 0) {
    parts.push(`XLSX(${pg}${len}c)`);
  } else if (x.extractionMethod === "epub_content" && len > 0) {
    parts.push(`EPUB(${len}c)`);
  } else if (x.extractionMethod === "iwork_vision_ocr" && len > 0) {
    parts.push(`iWorkOCR(${len}c)`);
  } else if (len > 0) {
    parts.push(`Text(${len}c)`);
  }
  if (x.visionTags.length > 0) {
    parts.push(`Tags:${x.visionTags.slice(0, 2).join(",")}`);
  }
  if (x.archiveEntries.length > 0) {
    parts.push(`Zip(${x.archiveEntries.length} items)`);
  }
  return parts.length > 0 ? parts.join(" · ") : "Filename/UTI only";
}

function parseActDecision<T extends { path: string }>(
  ans: ClassifierActAnswer,
  rules: Record<string, T>
): { isDeferred: boolean; effectiveKey: string; confidence: number } {
  const probs = ans.probabilities || {};
  const sortedProbs = Object.entries(probs).sort((a, b) => b[1] - a[1]);
  const topKey = sortedProbs[0]?.[0] || Object.keys(rules)[0];
  const topProb = sortedProbs[0]?.[1] ?? ans.confidence ?? 0;

  const chosenRaw = ans.action ?? ans.answer ?? ans.choice ?? topKey;
  const isDeferred = Boolean(ans.deferred || chosenRaw === "defer" || !rules[chosenRaw]);
  const effectiveKey = isDeferred ? (ans.refused && rules[ans.refused] ? ans.refused : topKey) : chosenRaw;
  const confidence = isDeferred ? topProb : (probs[effectiveKey] ?? ans.confidence ?? topProb);
  return { isDeferred, effectiveKey, confidence };
}

function uniqueDestPath(destDir: string, filename: string): string {
  const ext = extname(filename);
  const stem = basename(filename, ext);
  let candidate = join(destDir, filename);
  let counter = 1;
  while (existsSync(candidate)) {
    candidate = join(destDir, `${stem} (${counter})${ext}`);
    counter++;
  }
  return candidate;
}

function pruneEmptyDirsUpTo(leafDir: string, stopAtDir: string) {
  let cur = resolve(leafDir);
  const root = resolve(stopAtDir);
  while (cur !== root && cur.startsWith(root + "/")) {
    try {
      if (existsSync(cur) && readdirSync(cur).length === 0) {
        rmdirSync(cur);
        cur = dirname(cur);
      } else {
        break;
      }
    } catch {
      break;
    }
  }
}

function runUndo() {
  if (!existsSync(LATEST_HISTORY)) {
    console.error(`${YELLOW}No move history found at ${LATEST_HISTORY}.${RESET}`);
    process.exit(1);
  }
  const batch = JSON.parse(readFileSync(LATEST_HISTORY, "utf8")) as {
    timestamp: string;
    targetDir: string;
    moves: MoveRecord[];
  };
  let restored = 0;
  const touchedDirs = new Set<string>();
  for (const m of batch.moves) {
    if (existsSync(m.to) && !existsSync(m.from)) {
      touchedDirs.add(dirname(m.to));
      renameSync(m.to, m.from);
      console.log(`${GREEN}↩ Restored${RESET} ${basename(m.from)}`);
      restored++;
    } else {
      console.log(`${YELLOW}⚠ Skipped${RESET} ${basename(m.from)} (already moved or missing)`);
    }
  }
  for (const dir of touchedDirs) {
    pruneEmptyDirsUpTo(dir, batch.targetDir);
  }
  console.log(`\n${BOLD}Restored ${restored}/${batch.moves.length} files from ${batch.timestamp}.${RESET}`);
}

function printHelp() {
  console.log(`
${BOLD}siftify${RESET} — 100% Offline macOS File & Folder Organizer (Apple Vision + PDFKit + Local Metal GPU)

${BOLD}Usage:${RESET}
  bun run sift <folder> [options]
  bun run sift --undo

${BOLD}Options:${RESET}
  --all                Inspect all top-level files in <folder> (no 40-file cap)
  --limit <N>          Max files to inspect (default: 40 unless --all is set)
  --sort <newest|name> File inspection order (default: newest)
  --apply              Actually move high-confidence files (default is safe dry-run)
  --strictness <cost>  Cost of a wrong move vs defer=1 (default from siftify.config.json: 2.2 => >=54.5%)
  --url <http://...>   Override local classifier URL (default: SIFTIFY_URL or siftify.config.json)
  --json               Print structured JSON report (for UI integration)
  --undo               Revert the most recent --apply move batch
`);
}

const XRAY_BATCH_SIZE = 20;

async function main() {
  const argv = process.argv.slice(2);
  if (argv.length === 0 || argv.includes("--help") || argv.includes("-h")) {
    printHelp();
    process.exit(0);
  }
  if (argv.includes("--undo")) {
    runUndo();
    return;
  }

  const apply = argv.includes("--apply");
  const allFiles = argv.includes("--all");
  const jsonOut = argv.includes("--json");
  const limitIdx = argv.indexOf("--limit");
  const limit = allFiles ? Infinity : limitIdx !== -1 ? Number(argv[limitIdx + 1]) : 40;
  const sortIdx = argv.indexOf("--sort");
  const sortMode = sortIdx !== -1 ? argv[sortIdx + 1] : "newest";
  const strictIdx = argv.indexOf("--strictness");
  const urlIdx = argv.indexOf("--url");

  const positional = argv.filter((arg, i) => {
    if (arg.startsWith("-")) return false;
    const prev = argv[i - 1];
    if (prev === "--limit" || prev === "--strictness" || prev === "--url" || prev === "--sort") return false;
    return true;
  });

  if (positional.length === 0) {
    printHelp();
    process.exit(1);
  }

  const targetDir = resolve(expandHome(positional[0]));
  if (!existsSync(targetDir) || !statSync(targetDir).isDirectory()) {
    console.error(`${RED}Directory not found:${RESET} ${targetDir}`);
    process.exit(1);
  }

  const config = JSON.parse(readFileSync(CONFIG_PATH, "utf8")) as SiftifyConfig;
  const baseUrl = (
    (urlIdx !== -1 ? argv[urlIdx + 1] : undefined) ||
    process.env.SIFTIFY_URL ||
    process.env.BASAL_URL ||
    config.engineUrl ||
    config.basalUrl ||
    "http://127.0.0.1:8765"
  ).replace(/\/+$/, "");

  const wrongCost = strictIdx !== -1 ? Number(argv[strictIdx + 1]) : config.costs.wrong;
  const deferCost = config.costs.defer;
  const impliedThresholdPct = Math.max(0, (1 - deferCost / wrongCost) * 100).toFixed(1);

  try {
    const h = await fetch(`${baseUrl}/health`);
    if (!h.ok) throw new Error(`HTTP ${h.status}`);
  } catch {
    console.error(
      `${RED}Cannot reach local classifier engine at ${baseUrl}/health.${RESET}\n` +
        `Start native Apple Silicon MLX server in another tab with:\n  ${CYAN}bun run serve${RESET}`
    );
    process.exit(1);
  }

  const configuredFolderNames = new Set(Object.values(config.folders).map((f) => f.path));
  const allCandidates = readdirSync(targetDir, { withFileTypes: true })
    .filter((d) => {
      if (!d.isFile()) return false;
      if (d.name.startsWith(".")) return false;
      if (configuredFolderNames.has(d.name)) return false;
      const ext = extname(d.name).slice(1).toLowerCase();
      if (IGNORED_EXTENSIONS.has(ext)) return false;
      return true;
    })
    .map((d) => {
      const fullPath = join(targetDir, d.name);
      let mtimeMs = 0;
      try {
        mtimeMs = statSync(fullPath).mtimeMs;
      } catch {
        mtimeMs = 0;
      }
      return { name: d.name, fullPath, mtimeMs };
    })
    .sort((a, b) =>
      sortMode === "name" ? a.name.localeCompare(b.name) : b.mtimeMs - a.mtimeMs || a.name.localeCompare(b.name)
    );

  const totalFiles = allCandidates.length;
  const entries = allCandidates.slice(0, limit).map((c) => c.fullPath);

  if (entries.length === 0) {
    console.log(`${YELLOW}No top-level files to classify in ${targetDir}.${RESET}`);
    return;
  }

  ensureXRayBinary();

  const criteria: Record<string, string> = {};
  const subCriteriaByParent: Record<string, Record<string, string>> = {};
  for (const [key, rule] of Object.entries(config.folders)) {
    criteria[key] = `${rule.path}: ${rule.description}`;
    if (rule.subfolders && Object.keys(rule.subfolders).length > 0) {
      const sc: Record<string, string> = {};
      for (const [subKey, subRule] of Object.entries(rule.subfolders)) {
        sc[subKey] = `${subRule.path}: ${subRule.description}`;
      }
      subCriteriaByParent[key] = sc;
    }
  }

  if (!jsonOut) {
    const scopeNote =
      entries.length < totalFiles
        ? `Inspecting ${BOLD}${entries.length} of ${totalFiles}${RESET}${DIM} top-level files (${sortMode} first · pass ${RESET}${CYAN}--all${RESET}${DIM} for all ${totalFiles})`
        : `Inspecting all ${BOLD}${totalFiles}${RESET}${DIM} top-level files`;
    console.log(
      `\n${BOLD}${CYAN}siftify${RESET} ${apply ? `${GREEN}[APPLY MODE]` : `${YELLOW}[DRY-RUN]`} ${RESET}` +
        `${DIM}Folder: ${targetDir}${RESET}`
    );
    console.log(
      `${DIM}${scopeNote} · Auto-move threshold: >= ${impliedThresholdPct}% (wrong=${wrongCost}, defer=${deferCost})${RESET}\n`
    );
  }

  const results: Array<{
    file: string;
    signals: string;
    deferred: boolean;
    folderKey: string;
    subfolderKey?: string;
    folderPath: string;
    confidence: number;
    elapsedMs: number;
    movedTo?: string;
  }> = [];

  const movesToRecord: MoveRecord[] = [];
  let xrayMs = 0;
  let processed = 0;
  const countWidth = String(entries.length).length;

  for (let offset = 0; offset < entries.length; offset += XRAY_BATCH_SIZE) {
    const chunk = entries.slice(offset, offset + XRAY_BATCH_SIZE);
    const xrayT0 = performance.now();
    const xrayRaw = execFileSync(XRAY_BIN, chunk, { encoding: "utf8", maxBuffer: 32 * 1024 * 1024 });
    const xrays = JSON.parse(xrayRaw) as FileXRay[];
    xrayMs += Math.round(performance.now() - xrayT0);

    for (const x of xrays) {
      processed++;
      const state = buildCompactState(x);
      const t0 = performance.now();
      const res = await fetch(`${baseUrl}/v1/systemone`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          state,
          questions: {
            destination: {
              type: "act",
              instructions:
                "Select the single destination folder where this macOS file clearly belongs based on its filename, download URL, OCR/text preview, and metadata.",
              criteria,
              costs: {
                wrong: wrongCost,
                defer: deferCost,
              },
            },
          },
        }),
      });

      if (!res.ok) {
        throw new Error(`Classifier HTTP ${res.status}: ${await res.text()}`);
      }
      const data = (await res.json()) as {
        answers: Record<string, ClassifierActAnswer>;
      };

      const topDecision = parseActDecision(data.answers.destination, config.folders);
      let isDeferred = topDecision.isDeferred;
      const effectiveKey = topDecision.effectiveKey;
      const parentRule = config.folders[effectiveKey];
      if (parentRule && parentRule.enabled === false) {
        isDeferred = true;
      }
      let folderPath = parentRule?.path ?? effectiveKey;
      let conf = topDecision.confidence;
      let subfolderKey: string | undefined;

      // Stage 2: Deep content sub-classification only when routed into a folder that defines subfolders
      if (!isDeferred && parentRule?.subfolders && subCriteriaByParent[effectiveKey]) {
        const subQName = `sub_${effectiveKey}`;
        const subRes = await fetch(`${baseUrl}/v1/systemone`, {
          method: "POST",
          headers: { "content-type": "application/json" },
          body: JSON.stringify({
            state,
            questions: {
              [subQName]: {
                type: "act",
                instructions:
                  "Analyze the extracted document text, title, page count, and structure to select the single most accurate content subfolder.",
                criteria: subCriteriaByParent[effectiveKey],
                costs: {
                  wrong: parentRule.subCostWrong ?? 1.8,
                  defer: deferCost,
                },
              },
            },
          }),
        });
        if (subRes.ok) {
          const subData = (await subRes.json()) as { answers: Record<string, ClassifierActAnswer> };
          const subAns = subData.answers[subQName];
          if (subAns) {
            const subDecision = parseActDecision(subAns, parentRule.subfolders);
            if (!subDecision.isDeferred) {
              subfolderKey = subDecision.effectiveKey;
              const chosenSub = parentRule.subfolders[subfolderKey];
              const subPath = chosenSub?.path ?? subfolderKey;
              folderPath = join(parentRule.path, subPath);
              conf = Math.min(topDecision.confidence, subDecision.confidence);
              if (chosenSub && chosenSub.enabled === false) {
                isDeferred = true;
              }
            } else {
              const allSubsEnabled = Object.values(parentRule.subfolders).every((s) => s.enabled !== false);
              if (allSubsEnabled) {
                subfolderKey = "general";
                folderPath = join(parentRule.path, "General");
              } else {
                isDeferred = true;
              }
            }
          }
        }
      }

      const elapsedMs = Math.round(performance.now() - t0);
      const signals = summarizeSignals(x);

      let movedTo: string | undefined;
      if (apply && !isDeferred) {
        const destFolderAbs = join(targetDir, folderPath);
        mkdirSync(destFolderAbs, { recursive: true });
        movedTo = uniqueDestPath(destFolderAbs, x.filename);
        renameSync(x.path, movedTo);
        movesToRecord.push({
          from: x.path,
          to: movedTo,
          folderKey: subfolderKey ? `${effectiveKey}/${subfolderKey}` : effectiveKey,
          folderPath,
          confidence: conf,
        });
      }

      results.push({
        file: x.filename,
        signals,
        deferred: isDeferred,
        folderKey: effectiveKey,
        subfolderKey,
        folderPath,
        confidence: conf,
        elapsedMs,
        movedTo,
      });

      if (!jsonOut) {
        const idxPrefix =
          entries.length > 20 ? `${DIM}[${String(processed).padStart(countWidth)}/${entries.length}]${RESET} ` : "  ";
        const pct = `${(conf * 100).toFixed(1)}%`.padStart(6);
        const fileCol = (x.filename.length > 32 ? x.filename.slice(0, 29) + "..." : x.filename).padEnd(32);
        const sigCol = (signals.length > 34 ? signals.slice(0, 31) + "..." : signals).padEnd(34);
        const verdictCol = isDeferred
          ? `${YELLOW}⏸ DEFER${RESET} ${DIM}(leaned: ${folderPath})${RESET}`
          : `${GREEN}✓ ${apply ? "MOVED" : "MOVE "} → ${BOLD}${folderPath}${RESET}`;

        console.log(`${idxPrefix}${fileCol}  ${DIM}${sigCol}${RESET}  ${pct}  ${DIM}${String(elapsedMs).padStart(4)}ms${RESET}  ${verdictCol}`);
      }
    }
  }

  if (apply && movesToRecord.length > 0) {
    mkdirSync(HISTORY_DIR, { recursive: true });
    const record = {
      timestamp: new Date().toISOString(),
      targetDir,
      moves: movesToRecord,
    };
    writeFileSync(LATEST_HISTORY, JSON.stringify(record, null, 2));
    writeFileSync(join(HISTORY_DIR, `run-${Date.now()}.json`), JSON.stringify(record, null, 2));
  }

  if (jsonOut) {
    console.log(JSON.stringify({ targetDir, totalFiles, inspectedFiles: entries.length, apply, xrayMs, results }, null, 2));
    return;
  }

  const moveCount = results.filter((r) => !r.deferred).length;
  const deferCount = results.length - moveCount;
  const avgMs = Math.round(results.reduce((s, r) => s + r.elapsedMs, 0) / results.length);

  const byFolder = new Map<string, number>();
  for (const r of results) {
    if (!r.deferred) {
      byFolder.set(r.folderPath, (byFolder.get(r.folderPath) || 0) + 1);
    }
  }

  console.log(`\n${"─".repeat(114)}`);
  if (byFolder.size > 0) {
    const folderSummary = [...byFolder.entries()]
      .sort((a, b) => b[1] - a[1])
      .map(([folder, count]) => `${BOLD}${folder}${RESET} (${GREEN}${count}${RESET})`)
      .join(" · ");
    console.log(`${DIM}Folders:${RESET} ${folderSummary}`);
  }
  console.log(
    `${BOLD}Summary:${RESET} ${GREEN}${moveCount} confident${RESET} · ` +
      `${YELLOW}${deferCount} deferred (untouched)${RESET} · ` +
      `Signals: ${DIM}${xrayMs} ms${RESET} · ` +
      `Avg MLX: ${CYAN}${avgMs} ms/file${RESET}`
  );
  if (entries.length < totalFiles) {
    console.log(
      `${DIM}Scope:   Inspected ${entries.length} of ${totalFiles} files — pass ${RESET}${CYAN}--all${RESET}${DIM} (or ${RESET}${CYAN}--limit ${totalFiles}${RESET}${DIM}) to scan everything.${RESET}`
    );
  }
  if (!apply && moveCount > 0) {
    console.log(`${DIM}Tip:     Add ${RESET}${CYAN}--apply${RESET}${DIM} to move the ${moveCount} confident files (revert anytime with ${RESET}${CYAN}bun run sift --undo${RESET}${DIM}).${RESET}\n`);
  } else if (apply && movesToRecord.length > 0) {
    console.log(`${DIM}Saved undo receipt to .siftify-history/latest.json — run ${RESET}${CYAN}bun run sift --undo${RESET}${DIM} to revert.${RESET}\n`);
  }
}

main().catch((err) => {
  console.error(`${RED}Error:${RESET}`, err);
  process.exit(1);
});

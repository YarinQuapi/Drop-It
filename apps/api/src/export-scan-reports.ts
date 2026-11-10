import { mkdir, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { prisma } from "./db.js";

// Writes every open scan report to a folder (photo, recognized text, parsed
// values) so it can be copied off the server and turned into a parser test.
const dir = process.argv[2];
if (!dir) {
  console.error("usage: npm run export-scan-reports -- <folder>");
  process.exit(1);
}
await mkdir(dir, { recursive: true });
const reports = await prisma.scanReport.findMany({
  where: { resolvedAt: null },
  orderBy: { createdAt: "asc" },
});
for (const report of reports) {
  const base = join(dir, report.id);
  await writeFile(`${base}.jpg`, Buffer.from(report.photo));
  await writeFile(`${base}.txt`, report.rawText);
  await writeFile(
    `${base}.json`,
    JSON.stringify(
      { note: report.note, language: report.language, parsed: report.parsed, createdAt: report.createdAt },
      null,
      2,
    ),
  );
}
console.log(`exported ${reports.length} report(s) to ${dir}`);
await prisma.$disconnect();

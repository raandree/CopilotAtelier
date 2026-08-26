// Dump all cookies across all domains in the profile.
import fs from 'node:fs';
import path from 'node:path';

export default async function dumpAllCookies({ context, outDir }) {
  const all = await context.cookies();
  console.log(`Total cookies: ${all.length}`);

  const byDomain = new Map();
  for (const c of all) {
    const d = c.domain.replace(/^\./, '');
    if (!byDomain.has(d)) byDomain.set(d, []);
    byDomain.get(d).push(c);
  }

  const sortedDomains = [...byDomain.keys()].sort();
  for (const d of sortedDomains) {
    const list = byDomain.get(d);
    console.log(`\n${d}  (${list.length})`);
    for (const c of list) {
      const exp = c.expires === -1 ? 'session' : new Date(c.expires * 1000).toISOString();
      console.log(`  ${c.name.padEnd(35)} expires=${exp}  path=${c.path}`);
    }
  }

  const outPath = path.join(outDir, 'all-cookies.json');
  fs.writeFileSync(outPath, JSON.stringify(all, null, 2), 'utf8');
  console.log(`\nWrote ${outPath}`);
}

#!/usr/bin/env bun
import { getCodogotchiHome } from "../src/config";
import { runHookFromStdin } from "../src/hook-binary";

async function readStdin(): Promise<string> {
  if (process.stdin.isTTY) return "";
  const chunks: Buffer[] = [];
  for await (const chunk of process.stdin) {
    chunks.push(chunk as Buffer);
  }
  return Buffer.concat(chunks).toString("utf8");
}

const raw = await readStdin();
const home = getCodogotchiHome();
await runHookFromStdin(raw, { home, now: new Date() });
// Observe-only contract: Codogotchi consumes hook events and never writes to
// stdout. It takes no part in the agent's decision path (no decision/deny/ask,
// no injectSteps) on any platform. Silence is intentional; adding stdout
// passthrough would be a deliberate future opt-in.
process.exit(0);

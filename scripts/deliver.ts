import { runDeliveryOrchestrator } from '../tools/delivery/orchestrator';

const exitCode = await runDeliveryOrchestrator(
  process.argv.slice(2),
  process.cwd(),
);
process.exit(exitCode);

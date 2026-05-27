import { runCloseoutStack } from '../tools/delivery/closeout-stack';

const exitCode = await runCloseoutStack(process.argv.slice(2), process.cwd());
process.exit(exitCode);

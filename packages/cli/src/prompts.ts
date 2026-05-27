export type Prompter = {
  ask(question: string): Promise<string>;
  notice(message: string): void;
};

export function terminalPrompter(): Prompter {
  const stdin = process.stdin;
  const stdout = process.stdout;

  async function readLine(): Promise<string> {
    return await new Promise<string>((resolve, reject) => {
      let buffer = "";
      const onData = (chunk: Buffer | string) => {
        buffer += chunk.toString("utf8");
        const newline = buffer.indexOf("\n");
        if (newline !== -1) {
          stdin.removeListener("data", onData);
          stdin.removeListener("error", onError);
          stdin.pause();
          resolve(buffer.slice(0, newline).replace(/\r$/, ""));
        }
      };
      const onError = (err: Error) => {
        stdin.removeListener("data", onData);
        stdin.removeListener("error", onError);
        reject(err);
      };
      stdin.on("data", onData);
      stdin.on("error", onError);
      stdin.resume();
    });
  }

  return {
    async ask(question: string): Promise<string> {
      stdout.write(question);
      return await readLine();
    },
    notice(message: string): void {
      stdout.write(`${message}\n`);
    },
  };
}

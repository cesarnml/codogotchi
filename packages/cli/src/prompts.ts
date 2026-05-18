export type Prompter = {
	ask(question: string): Promise<string>;
	notice(message: string): void;
};

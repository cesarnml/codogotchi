export type VacationDeps = {
	home: string;
	now: () => Date;
};

export type VacationOnOptions = {
	until?: string;
};

export const VACATION_DEFAULT_DAYS = 30;

export async function vacationOn(
	_deps: VacationDeps,
	_opts: VacationOnOptions = {},
): Promise<string> {
	throw new Error("not implemented");
}

export async function vacationOff(_deps: VacationDeps): Promise<string> {
	throw new Error("not implemented");
}

export async function vacationStatus(_deps: VacationDeps): Promise<string> {
	throw new Error("not implemented");
}

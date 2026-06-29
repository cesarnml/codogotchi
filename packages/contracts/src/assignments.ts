import { z } from "zod";

export const assignmentsJsonSchema = z.object({
  schema_version: z.literal(1),
  default: z.string().min(1),
  claude_code: z.string().min(1).optional(),
  vscode: z.string().min(1).optional(),
  codex: z.string().min(1).optional(),
  cursor: z.string().min(1).optional(),
  antigravity: z.string().min(1).optional(),
});

export type AssignmentsJson = z.infer<typeof assignmentsJsonSchema>;

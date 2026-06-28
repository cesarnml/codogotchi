import { z } from "zod";

// Zod v4 z.record(enumSchema, …) requires all enum keys to be present; we
// need a partial record that also tolerates unknown origins, so use z.string().
export const customizationJsonSchema = z.object({
  schema_version: z.literal(1),
  platform_modes: z
    .record(z.string(), z.enum(["own", "combined", "off"]))
    .default({}),
  idle_dismiss_ttl_seconds: z.number().int().min(0).default(300),
  menubar_icon_monochrome: z.boolean().default(false),
});

export type CustomizationJson = z.infer<typeof customizationJsonSchema>;

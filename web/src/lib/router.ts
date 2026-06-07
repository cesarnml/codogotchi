export type View =
  | { type: "gallery" }
  | { type: "detail"; petId: string };

/** Maps a URL hash string (e.g. "#maew" or "") to an app view. */
export function hashToView(hash: string): View {
  const petId = hash.replace(/^#/, "").trim();
  if (petId) return { type: "detail", petId };
  return { type: "gallery" };
}

/** Maps a view back to a URL hash string. */
export function viewToHash(view: View): string {
  if (view.type === "detail") return `#${view.petId}`;
  return "";
}

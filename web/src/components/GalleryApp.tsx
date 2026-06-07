import { ConvexProvider, ConvexReactClient } from "convex/react";
import { useEffect, useState } from "react";
import { hashToView, viewToHash, type View } from "../lib/router";
import GalleryGrid from "./GalleryGrid";
import PetDetail from "./PetDetail";

const CONVEX_URL = "https://careful-bat-587.convex.cloud";
export const API_BASE = "https://careful-bat-587.convex.site";

const convex = new ConvexReactClient(CONVEX_URL);

export default function GalleryApp() {
  const [view, setView] = useState<View>(() =>
    typeof window !== "undefined" ? hashToView(window.location.hash) : { type: "gallery" },
  );

  useEffect(() => {
    const handler = () => setView(hashToView(window.location.hash));
    window.addEventListener("hashchange", handler);
    return () => window.removeEventListener("hashchange", handler);
  }, []);

  const navigate = (v: View) => {
    window.location.hash = viewToHash(v);
    setView(v);
  };

  return (
    <ConvexProvider client={convex}>
      {view.type === "gallery" ? (
        <GalleryGrid onSelectPet={(petId) => navigate({ type: "detail", petId })} />
      ) : (
        <PetDetail
          petId={view.petId}
          apiBase={API_BASE}
          onBack={() => navigate({ type: "gallery" })}
        />
      )}
    </ConvexProvider>
  );
}

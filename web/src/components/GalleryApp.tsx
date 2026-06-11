import { ConvexAuthProvider } from "@convex-dev/auth/react";
import { useEffect, useState } from "react";
import { API_BASE, convex } from "../lib/convex";
import { hashToView, viewToHash, type View } from "../lib/router";
import GalleryGrid from "./GalleryGrid";
import PetDetail from "./PetDetail";

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
    <ConvexAuthProvider client={convex}>
      {view.type === "gallery" ? (
        <GalleryGrid
          apiBase={API_BASE}
          onSelectPet={(petId) => navigate({ type: "detail", petId })}
        />
      ) : (
        <PetDetail
          petId={view.petId}
          apiBase={API_BASE}
          onBack={() => navigate({ type: "gallery" })}
        />
      )}
    </ConvexAuthProvider>
  );
}

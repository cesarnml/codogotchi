import { ConvexAuthProvider, useAuthActions } from "@convex-dev/auth/react";
import { useConvexAuth, useMutation, useQuery } from "convex/react";
import { useEffect, useRef, useState } from "react";
import { createPortal } from "react-dom";
import { api } from "~convex/_generated/api";
import { convex } from "../lib/convex";
import { validateUsername } from "../lib/username";
import AuthModal from "./AuthModal";

// Cached last-known auth state so the widget can paint the right UI instantly
// on each full page load, instead of a blank gap while Convex re-validates.
const AUTH_CACHE_KEY = "codogotchi:authCache";

type AuthCache = { username: string };

function readAuthCache(): AuthCache | null {
  try {
    const raw = localStorage.getItem(AUTH_CACHE_KEY);
    if (!raw) return null;
    const parsed = JSON.parse(raw) as Partial<AuthCache>;
    return typeof parsed.username === "string" ? { username: parsed.username } : null;
  } catch {
    return null;
  }
}

function writeAuthCache(cache: AuthCache | null) {
  try {
    if (cache) {
      localStorage.setItem(AUTH_CACHE_KEY, JSON.stringify(cache));
    } else {
      localStorage.removeItem(AUTH_CACHE_KEY);
    }
  } catch {
    // Storage unavailable (private mode) — fall back to loading placeholder.
  }
}

function mutationError(err: unknown): string {
  if (err !== null && typeof err === "object" && "data" in err) {
    const data = (err as { data: unknown }).data;
    if (typeof data === "string") return data;
  }
  return "Could not save username. Please try again.";
}

// Shown after social sign-up, where no username was captured at the OAuth step.
// Blocks the user menu until they confirm a public handle.
function UsernamePrompt({ suggested }: { suggested: string }) {
  const setUsername = useMutation(api.users.setUsername);
  const [value, setValue] = useState(suggested);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function submit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError(null);
    const result = validateUsername(value);
    if (!result.ok) {
      setError(result.error);
      return;
    }
    setBusy(true);
    try {
      await setUsername({ username: result.value });
    } catch (err) {
      setError(mutationError(err));
    } finally {
      setBusy(false);
    }
  }

  return createPortal(
    <div className="fixed inset-0 z-[100] overflow-y-auto bg-charcoal-ink/50">
      <div className="flex min-h-full items-start justify-center p-4 sm:pt-[15vh] sm:pb-12">
        <form
          onSubmit={submit}
          className="w-full max-w-md bg-surface-container-lowest border-2 border-charcoal-ink rounded-2xl shadow-[0_8px_0_0_var(--color-charcoal-ink)] p-6 flex flex-col gap-4"
        >
          <h2 className="font-display text-2xl font-extrabold">Choose your username</h2>
          <p className="text-sm text-on-surface-variant">
            This is your public handle on pets you publish.
          </p>
          {error && (
            <p className="text-sm bg-error-container text-on-error-container border border-charcoal-ink/30 rounded-lg px-3 py-2">
              {error}
            </p>
          )}
          <input
            value={value}
            onChange={(e) => setValue(e.target.value)}
            placeholder="Username"
            autoComplete="username"
            className="bg-surface-container-lowest border-2 border-charcoal-ink rounded-xl py-3 px-4 focus:outline-none focus:border-secondary-container"
          />
          <button
            type="submit"
            disabled={busy}
            className="squishy-btn bg-primary-container text-on-primary-container font-display font-bold py-3 rounded-xl disabled:opacity-60"
          >
            {busy ? "Saving…" : "Save username"}
          </button>
        </form>
      </div>
    </div>,
    document.body,
  );
}

function AuthWidgetInner() {
  const { isAuthenticated, isLoading } = useConvexAuth();
  const { signOut } = useAuthActions();
  const currentUser = useQuery(api.users.currentUser, isAuthenticated ? {} : "skip");
  const [modalOpen, setModalOpen] = useState(false);
  const [menuOpen, setMenuOpen] = useState(false);
  const [cache] = useState(readAuthCache);
  const menuRef = useRef<HTMLDivElement>(null);

  // Close the account menu on any click outside it, or Escape. A document-level
  // listener — not a fixed overlay — because the nav's backdrop-blur makes it a
  // containing block for fixed descendants, so a `fixed inset-0` overlay only
  // covers the nav strip, not the viewport.
  useEffect(() => {
    if (!menuOpen) return;
    function onPointerDown(event: MouseEvent) {
      if (menuRef.current && !menuRef.current.contains(event.target as Node)) {
        setMenuOpen(false);
      }
    }
    function onKeyDown(event: KeyboardEvent) {
      if (event.key === "Escape") setMenuOpen(false);
    }
    document.addEventListener("mousedown", onPointerDown);
    document.addEventListener("keydown", onKeyDown);
    return () => {
      document.removeEventListener("mousedown", onPointerDown);
      document.removeEventListener("keydown", onKeyDown);
    };
  }, [menuOpen]);

  // Keep the cache in sync once auth actually resolves, so the next page
  // load paints the correct state immediately.
  useEffect(() => {
    if (isLoading) return;
    if (!isAuthenticated) {
      writeAuthCache(null);
    } else if (currentUser && currentUser.usernameSet !== false) {
      writeAuthCache({ username: currentUser.username });
    }
  }, [isLoading, isAuthenticated, currentUser]);

  // While auth is resolving, optimistically render the last-known state.
  const showSignedIn = isLoading ? cache !== null : isAuthenticated;
  const username = currentUser?.username ?? cache?.username ?? null;

  if (!showSignedIn) {
    return (
      <>
        <button
          type="button"
          onClick={() => setModalOpen(true)}
          className="squishy-btn bg-surface-container-lowest border-2 border-charcoal-ink font-display font-bold text-sm px-4 md:px-5 py-2 rounded-full flex items-center gap-1.5 whitespace-nowrap"
        >
          <span className="material-symbols-outlined text-[18px]">login</span>
          Sign in
        </button>
        {modalOpen && <AuthModal onClose={() => setModalOpen(false)} />}
      </>
    );
  }

  // Authenticated but username not yet chosen (social sign-up) — prompt for it.
  if (!isLoading && currentUser && currentUser.usernameSet === false) {
    return <UsernamePrompt suggested={currentUser.username} />;
  }

  return (
    <div ref={menuRef} className="relative flex items-center gap-2">
      <a
        href="/upload"
        className="squishy-btn bg-secondary-container text-on-secondary-container border-2 border-charcoal-ink font-display font-bold text-sm px-4 py-2 rounded-full hidden sm:flex items-center gap-1.5 whitespace-nowrap"
      >
        <span className="material-symbols-outlined text-[18px]">upload</span>
        Upload pet
      </a>
      <button
        type="button"
        onClick={() => setMenuOpen((o) => !o)}
        className="squishy-btn bg-surface-container-lowest border-2 border-charcoal-ink font-display font-bold text-sm px-4 py-2 rounded-full flex items-center gap-1.5 whitespace-nowrap"
      >
        <span className="material-symbols-outlined text-[18px]">person</span>
        {username ? `@${username}` : "Account"}
      </button>
      {menuOpen && (
        <div className="absolute right-0 top-full mt-2 w-44 z-10 bg-surface-container-lowest border-2 border-charcoal-ink rounded-xl shadow-[0_4px_0_0_var(--color-charcoal-ink)] py-2 flex flex-col">
            <a
              href="/upload"
              className="px-4 py-2 text-sm font-medium hover:bg-surface-container flex items-center gap-2"
            >
              <span className="material-symbols-outlined text-[18px]">upload</span>
              Upload a pet
            </a>
            <button
              type="button"
              onClick={() => {
                setMenuOpen(false);
                void signOut();
              }}
              className="px-4 py-2 text-sm font-medium text-left hover:bg-surface-container flex items-center gap-2"
            >
              <span className="material-symbols-outlined text-[18px]">logout</span>
              Sign out
            </button>
        </div>
      )}
    </div>
  );
}

export default function AuthWidget() {
  return (
    <ConvexAuthProvider client={convex}>
      <AuthWidgetInner />
    </ConvexAuthProvider>
  );
}

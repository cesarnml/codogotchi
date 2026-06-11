import { ConvexAuthProvider, useAuthActions } from "@convex-dev/auth/react";
import { useConvexAuth, useMutation, useQuery } from "convex/react";
import { useState } from "react";
import { createPortal } from "react-dom";
import { api } from "~convex/_generated/api";
import { convex } from "../lib/convex";
import { validateUsername } from "../lib/username";
import AuthModal from "./AuthModal";

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

  if (isLoading) {
    return <div className="w-20 h-9" aria-hidden="true" />;
  }

  if (!isAuthenticated) {
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
  if (currentUser && currentUser.usernameSet === false) {
    return <UsernamePrompt suggested={currentUser.username} />;
  }

  return (
    <div className="relative flex items-center gap-2">
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
        {currentUser ? `@${currentUser.username}` : "Account"}
      </button>
      {menuOpen && (
        <>
          <div
            className="fixed inset-0 z-0"
            onClick={() => setMenuOpen(false)}
            aria-hidden="true"
          />
          <div className="absolute right-0 mt-2 w-44 z-10 bg-surface-container-lowest border-2 border-charcoal-ink rounded-xl shadow-[0_4px_0_0_var(--color-charcoal-ink)] py-2 flex flex-col">
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
        </>
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

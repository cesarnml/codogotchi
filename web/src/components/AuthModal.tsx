import { useAuthActions } from "@convex-dev/auth/react";
import { useConvex } from "convex/react";
import { useState } from "react";
import { api } from "~convex/_generated/api";
import { validateUsername } from "../lib/username";

type Mode = "signIn" | "register";

function errorMessage(err: unknown): string {
  if (err !== null && typeof err === "object" && "data" in err) {
    const data = (err as { data: unknown }).data;
    if (typeof data === "string") return data;
  }
  if (err instanceof Error && err.message) {
    // Convex Auth surfaces generic "InvalidSecret"/"InvalidAccountId" strings;
    // translate the common ones into something a human can act on.
    if (/InvalidSecret|InvalidAccountId/i.test(err.message)) {
      return "Incorrect email or password.";
    }
    return err.message;
  }
  return "Something went wrong. Please try again.";
}

/**
 * Sign in / Register modal. Offers Google, GitHub, and email/password. Register
 * captures a unique public username and sends an email verification code via the
 * Resend OTP provider before the account is usable. Browsing/downloading never
 * open this modal — only authoring actions do.
 */
export default function AuthModal({ onClose }: { onClose: () => void }) {
  const { signIn } = useAuthActions();
  const convex = useConvex();
  const [mode, setMode] = useState<Mode>("signIn");
  const [verifyEmail, setVerifyEmail] = useState<string | null>(null);

  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [username, setUsername] = useState("");
  const [code, setCode] = useState("");

  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function handleOAuth(provider: "google" | "github") {
    setError(null);
    setBusy(true);
    try {
      await signIn(provider);
      // signIn(provider) redirects the browser; nothing runs after this.
    } catch (err) {
      setError(errorMessage(err));
      setBusy(false);
    }
  }

  async function handleEmailPassword(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError(null);

    if (mode === "register") {
      const result = validateUsername(username);
      if (!result.ok) {
        setError(result.error);
        return;
      }
      setBusy(true);
      try {
        // Surface collisions up front rather than silently suffixing the handle.
        const taken = await convex.query(api.users.getUserByUsername, {
          username: result.value,
        });
        if (taken !== null) {
          setError(`Username "${result.value}" is already taken`);
          setBusy(false);
          return;
        }
        await signIn("password", {
          email,
          password,
          username: result.value,
          flow: "signUp",
        });
        // Account created (unverified) — an OTP email was sent.
        setVerifyEmail(email);
      } catch (err) {
        setError(errorMessage(err));
      } finally {
        setBusy(false);
      }
      return;
    }

    setBusy(true);
    try {
      await signIn("password", { email, password, flow: "signIn" });
      onClose();
    } catch (err) {
      setError(errorMessage(err));
    } finally {
      setBusy(false);
    }
  }

  async function handleVerify(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError(null);
    setBusy(true);
    try {
      await signIn("password", {
        email: verifyEmail as string,
        code,
        flow: "email-verification",
      });
      onClose();
    } catch (err) {
      setError(errorMessage(err));
    } finally {
      setBusy(false);
    }
  }

  async function resendCode() {
    if (!verifyEmail) return;
    setError(null);
    setBusy(true);
    try {
      await signIn("password", {
        email: verifyEmail,
        password,
        username,
        flow: "signUp",
      });
    } catch (err) {
      setError(errorMessage(err));
    } finally {
      setBusy(false);
    }
  }

  return (
    <div
      className="fixed inset-0 z-[100] overflow-y-auto bg-charcoal-ink/50"
      onClick={onClose}
      role="presentation"
    >
      <div className="flex min-h-full items-start justify-center p-4 sm:pt-[15vh] sm:pb-12">
        <div
          className="w-full max-w-md bg-surface-container-lowest border-2 border-charcoal-ink rounded-2xl shadow-[0_8px_0_0_var(--color-charcoal-ink)] p-6 flex flex-col gap-4"
          onClick={(e) => e.stopPropagation()}
          role="dialog"
          aria-modal="true"
          aria-label="Sign in or register"
        >
        <div className="flex justify-between items-center">
          <h2 className="font-display text-2xl font-extrabold text-on-surface">
            {verifyEmail
              ? "Check your email"
              : mode === "signIn"
                ? "Welcome back"
                : "Create your account"}
          </h2>
          <button
            type="button"
            onClick={onClose}
            aria-label="Close"
            className="text-on-surface-variant hover:text-on-surface"
          >
            <span className="material-symbols-outlined">close</span>
          </button>
        </div>

        {error && (
          <p className="text-sm bg-error-container text-on-error-container border border-charcoal-ink/30 rounded-lg px-3 py-2">
            {error}
          </p>
        )}

        {verifyEmail ? (
          <form onSubmit={handleVerify} className="flex flex-col gap-3">
            <p className="text-sm text-on-surface-variant">
              We sent an 8-digit code to <strong>{verifyEmail}</strong>. Enter it
              to finish creating your account.
            </p>
            <input
              name="code"
              value={code}
              onChange={(e) => setCode(e.target.value)}
              placeholder="Verification code"
              inputMode="numeric"
              autoComplete="one-time-code"
              className="bg-surface-container-lowest border-2 border-charcoal-ink rounded-xl py-3 px-4 tracking-widest focus:outline-none focus:border-secondary-container"
            />
            <button
              type="submit"
              disabled={busy}
              className="squishy-btn bg-primary-container text-on-primary-container font-display font-bold py-3 rounded-xl disabled:opacity-60"
            >
              {busy ? "Verifying…" : "Verify & continue"}
            </button>
            <button
              type="button"
              onClick={resendCode}
              disabled={busy}
              className="text-sm text-primary hover:underline disabled:opacity-60"
            >
              Resend code
            </button>
          </form>
        ) : (
          <>
            <div className="flex flex-col gap-2">
              <button
                type="button"
                onClick={() => handleOAuth("google")}
                disabled={busy}
                className="squishy-btn bg-surface-container-lowest border-2 border-charcoal-ink font-bold py-2.5 rounded-xl flex items-center justify-center gap-2 disabled:opacity-60"
              >
                <span className="material-symbols-outlined text-[18px]">
                  account_circle
                </span>
                Continue with Google
              </button>
              <button
                type="button"
                onClick={() => handleOAuth("github")}
                disabled={busy}
                className="squishy-btn bg-charcoal-ink text-surface font-bold py-2.5 rounded-xl flex items-center justify-center gap-2 disabled:opacity-60"
              >
                <span className="material-symbols-outlined text-[18px]">code</span>
                Continue with GitHub
              </button>
            </div>

            <div className="flex items-center gap-3 text-xs text-on-surface-variant">
              <span className="flex-1 h-px bg-outline-variant" />
              or
              <span className="flex-1 h-px bg-outline-variant" />
            </div>

            <form onSubmit={handleEmailPassword} className="flex flex-col gap-3">
              {mode === "register" && (
                <input
                  name="username"
                  value={username}
                  onChange={(e) => setUsername(e.target.value)}
                  placeholder="Username (public handle)"
                  autoComplete="username"
                  className="bg-surface-container-lowest border-2 border-charcoal-ink rounded-xl py-3 px-4 focus:outline-none focus:border-secondary-container"
                />
              )}
              <input
                name="email"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                placeholder="Email"
                type="email"
                autoComplete="email"
                className="bg-surface-container-lowest border-2 border-charcoal-ink rounded-xl py-3 px-4 focus:outline-none focus:border-secondary-container"
              />
              <input
                name="password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                placeholder="Password"
                type="password"
                autoComplete={
                  mode === "signIn" ? "current-password" : "new-password"
                }
                className="bg-surface-container-lowest border-2 border-charcoal-ink rounded-xl py-3 px-4 focus:outline-none focus:border-secondary-container"
              />
              <button
                type="submit"
                disabled={busy}
                className="squishy-btn bg-primary-container text-on-primary-container font-display font-bold py-3 rounded-xl disabled:opacity-60"
              >
                {busy
                  ? "Working…"
                  : mode === "signIn"
                    ? "Sign in"
                    : "Create account"}
              </button>
            </form>

            <button
              type="button"
              onClick={() => {
                setMode(mode === "signIn" ? "register" : "signIn");
                setError(null);
              }}
              className="text-sm text-primary hover:underline"
            >
              {mode === "signIn"
                ? "Need an account? Register"
                : "Already have an account? Sign in"}
            </button>
          </>
        )}
        </div>
      </div>
    </div>
  );
}

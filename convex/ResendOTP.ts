import Resend from "@auth/core/providers/resend";
import { generateRandomString, type RandomReader } from "@oslojs/crypto/random";
import { Resend as ResendAPI } from "resend";

// Email-verification OTP provider for the Password flow. On signup, Convex Auth
// calls this to email an 8-digit code; the user confirms it via the
// "email-verification" flow before the account is usable.
//
// Secrets come from deployment env vars (never the client bundle):
//   AUTH_RESEND_KEY   — Resend API key
//   AUTH_EMAIL_FROM   — verified sender address on the codogotchi.app domain
export const ResendOTP = Resend({
  id: "resend-otp",
  apiKey: process.env.AUTH_RESEND_KEY,
  async generateVerificationToken() {
    const random: RandomReader = {
      read(bytes) {
        crypto.getRandomValues(bytes);
      },
    };
    return generateRandomString(random, "0123456789", 8);
  },
  async sendVerificationRequest({ identifier: email, provider, token }) {
    const resend = new ResendAPI(provider.apiKey);
    const from = process.env.AUTH_EMAIL_FROM ?? "noreply@codogotchi.app";
    const { error } = await resend.emails.send({
      from: `Codogotchi <${from}>`,
      to: [email],
      subject: "Verify your Codogotchi account",
      text: `Welcome to Codogotchi! Your verification code is ${token}\n\nEnter it on the sign-up screen to finish creating your account. If you didn't request this, you can ignore this email.`,
    });
    if (error) {
      throw new Error(
        `Could not send verification email: ${JSON.stringify(error)}`,
      );
    }
  },
});

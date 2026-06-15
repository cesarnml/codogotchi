/* eslint-disable */
/**
 * Generated `api` utility.
 *
 * THIS CODE IS AUTOMATICALLY GENERATED.
 *
 * To regenerate, run `npx convex dev`.
 * @module
 */

import type * as ResendOTP from "../ResendOTP.js";
import type * as actions_uploadPet from "../actions/uploadPet.js";
import type * as auth from "../auth.js";
import type * as http from "../http.js";
import type * as migrations_p11_02 from "../migrations/p11_02.js";
import type * as migrations_p11_04 from "../migrations/p11_04.js";
import type * as mutations_operatorUpload from "../mutations/operatorUpload.js";
import type * as mutations_syncProfile from "../mutations/syncProfile.js";
import type * as mutations_trackDmgDownload from "../mutations/trackDmgDownload.js";
import type * as pets from "../pets.js";
import type * as users from "../users.js";

import type {
  ApiFromModules,
  FilterApi,
  FunctionReference,
} from "convex/server";

declare const fullApi: ApiFromModules<{
  ResendOTP: typeof ResendOTP;
  "actions/uploadPet": typeof actions_uploadPet;
  auth: typeof auth;
  http: typeof http;
  "migrations/p11_02": typeof migrations_p11_02;
  "migrations/p11_04": typeof migrations_p11_04;
  "mutations/operatorUpload": typeof mutations_operatorUpload;
  "mutations/syncProfile": typeof mutations_syncProfile;
  "mutations/trackDmgDownload": typeof mutations_trackDmgDownload;
  pets: typeof pets;
  users: typeof users;
}>;

/**
 * A utility for referencing Convex functions in your app's public API.
 *
 * Usage:
 * ```js
 * const myFunctionReference = api.myModule.myFunction;
 * ```
 */
export declare const api: FilterApi<
  typeof fullApi,
  FunctionReference<any, "public">
>;

/**
 * A utility for referencing Convex functions in your app's internal API.
 *
 * Usage:
 * ```js
 * const myFunctionReference = internal.myModule.myFunction;
 * ```
 */
export declare const internal: FilterApi<
  typeof fullApi,
  FunctionReference<any, "internal">
>;

export declare const components: {};

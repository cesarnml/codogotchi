#!/usr/bin/env bun
import { dispatch } from "../src/router";

const { exitCode } = await dispatch(process.argv.slice(2));
process.exit(exitCode);

# codogotchi

Install [Codogotchi](https://codogotchi.app) pets from the [community marketplace](https://codogotchi.app/gallery).

Codogotchi is a macOS menubar pet that reacts to your coding sessions across Claude Code, Codex, Cursor, and more. This CLI downloads community-made pets into `~/.codogotchi/pets/` so you can switch to them in the app.

## Usage

Browse the [pet gallery](https://codogotchi.app/gallery), pick a pet, then:

```sh
npx codogotchi add <pet-id>
```

Then open **Codogotchi.app → Settings → Pet** to switch to it.

## Commands

| Command | Description |
| --- | --- |
| `add <pet-id> [--force]` | Download and install a pet from the marketplace. Existing files are left intact unless `--force` is passed. Downloads are validated before anything is written to disk. |
| `status` | Print the cached pet profile and HP. |
| `version` | Print the CLI version. |

## Environment

| Variable | Description |
| --- | --- |
| `CODOGOTCHI_HOME` | Override the install root (defaults to `~/.codogotchi`). |
| `CODOGOTCHI_API_URL` | Override the marketplace API URL (for testing or self-hosting). |

## Links

- [Codogotchi app](https://codogotchi.app) — download the macOS menubar app
- [Pet gallery](https://codogotchi.app/gallery) — browse community pets
- [Source](https://github.com/cesarnml/codogotchi) — monorepo (this package lives in `packages/cli-npm`)

## License

MIT

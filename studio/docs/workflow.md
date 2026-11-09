# Working on WYRM Studio, step by step

From a fresh machine to the first merged phase. The plan itself (what each phase builds) is [`docs/studio.md`](../../docs/studio.md); the design is in [`design/`](design/README.md).

## 1. Tools, once

```sh
flutter --version          # stable, Dart >= 3.12; else: flutter upgrade
flutter doctor             # Xcode for macOS, Android SDK only if you build for it
curl -fsSL https://raw.githubusercontent.com/pro100andrey/flutter_redux_templates/main/tools/scripts/install.sh | sh -s -- --version 0.3.7
frx --version              # frx 0.3.7 (open a new shell if it is not found)
gh auth status             # GitHub CLI, for pull requests
cargo --version            # Rust, only to run the demo brokers
```

Optional: the **FRX** extension for VS Code (Command Palette, tree of substates and routes, F2 rename, `frx doctor` in Problems).

## 2. The branch

```sh
git clone https://github.com/gencto/wyrm && cd wyrm      # or, in a clone you have:
git fetch origin && git switch studio/frx-template
```

## 3. First run (checks the bootstrap)

```sh
cd studio
flutter pub get
dart run build_runner build --workspace   # writes the generated parts
frx doctor                                 # expect: no issues
flutter analyze
cd app && flutter run -d macos             # Splash → Log in → Home (the template, not WYRM yet)
```

If one of these fails, the bootstrap needs a fix before any phase: report the output.

## 4. The demo brokers (for phase 1 onwards)

In a second terminal, from the repository root:

```sh
examples/demo/run.sh       # first run builds wyrmd: several minutes
```

Gateways: central `http://127.0.0.1:8445`, edge `:8444`, plant `:8446`; user `admin`, password `wyrm-demo-1`.

## 5. CI job

Add the `studio` job of `docs/studio.md` §9 under `jobs:` in `.github/workflows/ci.yml`, commit, push, and look at the run (`gh run watch`). Then:

```sh
gh pr ready 10
gh pr merge 10 --merge     # keeps the three commits
```

## 6. One phase = one branch = one pull request

```sh
git switch main && git pull
git switch -c studio/phase-1-login
cd studio
frx watch                  # terminal A: leave it running (codegen in ~2 s)
```

In terminal B, the phase's commands from `docs/studio.md` §4, each one first with `--dry-run`:

```sh
frx remove registration --kind page --dry-run    # look at the plan
frx remove registration --kind page --apply      # apply
# … the rest of the phase …
```

Then the hand edits the phase lists, and before every commit:

```sh
frx doctor                 # wiring, codegen, placement
flutter analyze
flutter test               # in each package that has tests
frx flow --md              # refresh docs/flows (doctor checks it)
git add -A && git commit -m "studio: phase 1, log in through the gateway"
git push -u origin HEAD
gh pr create --fill --draft
```

Branch names: `studio/phase-<n>-<topic>` (`phase-2-state`, `phase-3-connection`, `phase-6-links`, …). Commit messages in English, starting with `studio:`.

## 7. With Claude Code

Start it in `studio/`, not at the repository root: that is where the frx `CLAUDE.md`, the 30 skills and the hook that guards wired files load.

```sh
cd studio && claude
```

A good first prompt for a phase:

> Do phase 1 of `../docs/studio.md`. Make every artifact with `frx` (dry-run first), write only bodies by hand, take labels and states from `docs/design/canvas/` (`Main.dc.html` for the shell), and finish with `frx doctor`, `flutter analyze` and `flutter test` clean. Do not commit.

Review the diff yourself, then commit and open the pull request (§6).

## 8. When the design changes

The canvas in Claude Design is the source. After a change there, refresh `studio/docs/design/canvas/` in the pull request that implements it (ask Claude in the design conversation to export the boards into the branch, or copy them), and update the golden tests of the frames that changed (`flutter test --update-goldens`, then look at every changed image).

## 9. When something breaks

| Symptom | Do |
|---|---|
| `frx doctor`: part `….freezed.dart` missing | codegen has not run: `frx watch` or `dart run build_runner build --workspace` |
| a route class is missing after a page was removed or added | `cd app && dart run build_runner clean && dart run build_runner build` |
| analyzer errors after `frx remove` | something dispatched or showed what was removed; `frx remove` prints what it could not unwire; fix those lines by hand |
| `frx add-nav` refuses a connector | that connector was not made by frx (Splash): change its navigation by hand |
| the app cannot reach a gateway on macOS | `network.client` entitlement (already in this branch); a gateway on another host needs TLS |

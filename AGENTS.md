# AGENTS.md

Niri + Quickshell desktop modules, consumed by `nixcfg` (via
`--override-input nixcfg-niri ~/Code/nixcfg-niri`). This file is mostly about
**keeping the vendored Quickshell shells up to date**, which is fiddly: they're
upstream Hyprland shells rewritten at build time to run under niri.

## Builds

- **Never** run `nixos-rebuild` / `home-manager switch` / `nix run .#switch`
  without asking. Activation is the consumer's job — the user runs
  `! nix run .#switch` in `~/Code/nixcfg`. (The agent's sudo isn't real root, so
  profile activation fails anyway.)
- You **can** build an individual package to validate changes (no activation, no
  root). This is the core loop: build the package → give the user the store path
  to run foreground → fix → repeat. Only the final activation needs their switch.

Validation build (one package, against the consumer's pinned nixpkgs so the
quickshell/Qt versions match runtime — adjust paths to your checkout):

```sh
nix build --impure --no-link --print-out-paths --expr '
  let pkgs = import (builtins.getFlake "/home/erahhal/Code/nixcfg").inputs.nixpkgs {
        system = builtins.currentSystem; config.allowUnfree = true;
      };
  in pkgs.callPackage /home/erahhal/Code/nixcfg-niri/pkgs/hypr-comp-shell { }'
```

Then run the printed `…/bin/<wrapper>` in a **foreground** terminal (it overlays
the running shell; Ctrl+C to stop) to confirm the QML loads. Parse-check Nix with
`nix-instantiate --parse <file>`. New files must be `git add`ed to be visible to
the flake (do not commit — the user handles commits).

## The vendored shells

Three Quickshell shells coexist under niri, **mutually exclusive** (only one runs
at a time); DankMaterialShell is the session default.

| Shell | Where | Keybind | Notes |
|-------|-------|---------|-------|
| DankMaterialShell (DMS) | upstream `dms-shell` input (not vendored) | — | session default |
| persona-quickshell | `pkgs/persona-quickshell/` | **Mod+D** toggles DMS ↔ Persona | Persona 3 shell |
| hypr-comp-shell | `pkgs/hypr-comp-shell/` | **Mod+Shift+D** rotates DMS → A → B → DMS | ilyamiro's shell, 3 variants |

hypr-comp variants (wrapper → entry QML):
- `hypr-comp`   → `Shell.qml`        — daily shell (bar + popups), no earth.
- `hypr-comp-a` → `ShellHybrid.qml`  — A: daily shell + Stars/Moon (earth) backgrounds.
- `hypr-comp-b` → `ShellFull.qml`    — B: competition layout (Moon dashboard + Stars + 3D launcher).

Wiring: options `nixcfg-niri.desktop.{persona,hyprComp}.{enable,…}` in
`modules/options.nix`; home modules `modules/desktop/{persona-quickshell,hypr-comp}/home.nix`
(imported from `modules/desktop/niri/home.nix`); enabled via
`hostParams.desktop.{persona,hyprComp}.enable` mirrored in nixcfg's
`modules/desktop/niri/user-overrides.nix`. **Mod+P** is a launcher dispatcher
(`hypr-comp-launcher`, `lib.mkOverride 30`) that opens whichever shell is active.
**Lifecycle / mutual exclusion:** the hypr-comp variants run as transient
`systemd --user` units (`hypr-comp-a` / `hypr-comp-b`, via `systemd-run --collect`)
so stopping one tears down its whole cgroup — no orphaned watcher subprocesses
(`niri msg event-stream`, `inotifywait`, …). Persona runs daemonized
(`persona -d`, stopped via `qs kill` / `pkill -f share/persona-quickshell`). DMS
via `systemctl --user {stop,restart} dms`, always `reset-failed` first — rapid
cycles otherwise trip systemd's start-rate-limit (`start-limit-hit`) and DMS
won't restart. Each toggle/rotate stops the others.

## Why these are patched (read before updating)

Both upstream shells are written for **Hyprland** and hardcode personal paths. We
`fetchFromGitHub` them (pinned `rev` + `hash`) and rewrite at build time:
- niri ships no Quickshell module → all `hyprctl` / `.socket2` coupling becomes
  `niri msg` (`--json workspaces`/`keyboard-layouts`/`event-stream`, `action …`).
- Hardcoded `~/.config/hypr/…` and `/home/ilyamiro/…` paths → store / `~/.config/hypr-comp`.
- Qt6 QtMultimedia/Qt5Compat are forced onto quickshell's Qt: the wrapper
  `--unset`s the session's Qt5-leaking `QML2_IMPORT_PATH`/`QML_IMPORT_PATH` and
  `--prefix`es `NIXPKGS_QT6_QML_IMPORT_PATH`/`QT_PLUGIN_PATH`.

Most rewrites use `substituteInPlace --replace-fail '<exact upstream string>' '…'`.
**`--replace-fail` errors the build if the upstream string is gone** — this is
intentional fail-fast. On a bump, a failure like *"could not find … in …"* means
that string moved/renamed upstream: open the file at the new `rev`, find the new
equivalent, and update the pattern. `--replace-quiet` patches are best-effort
(won't fail) — re-check them by eye after a bump.

## Updating persona-quickshell

Source `Yujonpradhananga/Persona-Quickshell` in `pkgs/persona-quickshell/default.nix`.

1. Bump `src.rev` to the latest commit.
2. Update `src.hash`: `nix-prefetch-github Yujonpradhananga Persona-Quickshell --rev <rev>`
   (or set `hash = lib.fakeHash;`, build, copy the printed hash).
3. Re-verify the only upstream-coupled bits:
   - **CavaVisualizer stub** — `postPatch` copies `CavaVisualizer-stub.qml` over
     `Widgets/CavaVisualizer.qml` (drops the native Qt6-Cava-plugin dep). Confirm
     that file still exists and is still instantiated by `WallpaperEngine.qml`.
   - **`searchapp` IPC** — `persona-launcher.sh` calls
     `qs ipc -p <config> call searchapp toggle`; confirm `Layers/Searchapp.qml`
     still has `IpcHandler { target: "searchapp"; function toggle() … }`.
4. Validation-build, run `…/bin/persona` foreground.

## Updating hypr-comp-shell

**Two** sources in `pkgs/hypr-comp-shell/default.nix`:
- `src` = `ilyamiro/nixos-configuration` — daily framework + shell (`config/sessions/hyprland/scripts`).
- `srcComp` = `ilyamiro/hypr-comp` — competition pieces (`Stars.qml`, `moon.qml`, `applauncher.qml`, `earth.jpg`, `moon.jpg`).

1. Bump both `.rev`s; update both `.hash`es:
   `nix-prefetch-github ilyamiro nixos-configuration --rev <rev>` and
   `nix-prefetch-github ilyamiro hypr-comp --rev <rev>`.
2. Validation-build; fix every `--replace-fail` failure (the error names the file
   + missing pattern — find the new string upstream).
3. Run `…/bin/hypr-comp-a` and `…/bin/hypr-comp-b` foreground; toggle B's launcher:
   `qs ipc -p …/share/hypr-comp/scripts/quickshell/ShellFull.qml call applauncher toggle`.

### Patch inventory (what installPhase rewrites — re-check on a bump)

Framework (`quickshell/`, from `src`):
- `Config.qml` — `homeDir + "/.config/hypr"` → `…/.config/hypr-comp` (writable settings);
  `hyprDir + "/scripts/quickshell"` → store path.
- Global path repoint (`--replace-quiet`) — `~/.config/hypr/scripts` → store;
  `~/.config/hypr/settings.json` → `~/.config/hypr-comp/settings.json`.
- `qs_manager.sh` — Hyprland `dispatch workspace` → `niri msg action focus-workspace`
  / `move-window-to-workspace`; `SHELL_QML_PATH` made dynamic (detect the live
  `ShellX.qml` so A/B in-shell pills hit the right instance).
- `TopBar.qml` — `hyprctl switchxkblayout` → `niri msg action switch-layout`;
  bottom-bar tweaks: `top: true`→`bottom: true`, `margins {…}`,
  `exclusiveZone: barHeight`→`+ s(6)` (bar at bottom, s(4) below / s(2) above).
- niri script overwrites (from `niri/`) — `workspaces.sh`,
  `quickshell/watchers/{kb_fetch,kb_wait}.sh`. Re-verify upstream still consumes
  the same contract: `workspaces.json` = `[{id,state,tooltip}]` written to
  `getRunDir("workspaces")`; `kb_fetch` prints a 2-letter layout code.

Competition pieces (copied from `srcComp` into `quickshell/`, PascalCased):
- `Moon.qml` (from `moon.qml`) — `paths.qsDir`/`paths.serpantinumDir` → store;
  `file:///home/ilyamiro/Downloads/{earth,moon,hyprland}.*` → bundled `earth.jpg`/`moon.jpg`;
  `hyprctl switchxkblayout` → niri.
- `AppLauncher.qml` (from `applauncher.qml`) — `import "../"`→`import "."`;
  Escape-close `qs_manager.sh close` exec → `qs ipc -p <ShellFull.qml> call applauncher close`;
  `paths.qsDir`/`paths.serpantinumDir` → store.

Our own files (in `pkgs/hypr-comp-shell/`, copied/installed in):
- Entry points `ShellHybrid.qml` (A) / `ShellFull.qml` (B) instantiate component
  **types by filename** — `Stars`, `Moon`, `Main`, `TopBar`, `Floating`,
  `AppLauncher`. If upstream renames any of those QML files, update these entries.
- `hypr-comp-rotate.sh` (Mod+Shift+D) and `hypr-comp-launcher.sh` (Mod+P), plus
  `niri/{workspaces,kb_fetch,kb_wait}.sh`. They use `@token@` placeholders filled
  by `substituteInPlace` in installPhase — adding a placeholder means adding its
  `--replace-fail`.

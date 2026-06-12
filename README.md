# Claude + MATLAB MCP Setup (Windows)

Connect Claude Desktop to MATLAB using the official [MATLAB MCP Core Server from MathWorks](https://github.com/matlab/matlab-mcp-core-server) — including a workaround for the **Microsoft Store version of Claude Desktop**, where the normal one-click `.mcpb` extension installer is broken.

Once connected, Claude can run MATLAB code, create and execute `.m` scripts, lint code, run unit tests, and build/simulate Simulink models — anything scriptable in MATLAB.

## Prerequisites

- MATLAB **R2021a or later** installed
- Claude Desktop installed
- Windows 10/11 (macOS/Linux users: the official `.mcpb` installer usually just works — see [official instructions](https://github.com/matlab/matlab-mcp-core-server#readme))

## Normal install (try this first)

1. Download `matlab-mcp-core-server.mcpb` from the [official releases page](https://github.com/matlab/matlab-mcp-core-server/releases/latest)
2. Double-click it → Claude Desktop opens an install prompt → click **Install**
3. Restart Claude Desktop. Done.

If that worked, you don't need anything else in this repo.

## Manual install (Microsoft Store version of Claude / broken installer)

On the Store-packaged Claude Desktop, the `.mcpb` file may not be associated with Claude, and the *Settings → Extensions → Install Extension* dialog may fail silently (the file picker shows "Preview" and nothing happens). Symptoms also include empty `Claude Extensions` folders and leftover `dxt-install-*` temp folders.

The workaround: run the MCP server as a plain **local MCP server** instead of an extension.

### Step 1 — Get the server binary

Download `matlab-mcp-core-server-win64.exe` from the [official releases](https://github.com/matlab/matlab-mcp-core-server/releases/latest) and place it in a permanent folder, e.g.:

```
C:\Users\<you>\matlab-mcp\matlab-mcp-core-server-win64.exe
```

Optionally verify the SHA-256 checksum shown on the releases page:

```powershell
Get-FileHash C:\Users\<you>\matlab-mcp\matlab-mcp-core-server-win64.exe -Algorithm SHA256
```

> **Note (June 2026):** the project is being renamed to `matlab-mcp-server`; binary names change to `matlab-mcp-server-windows-x64.exe`. Adjust paths accordingly if you download a newer release.

### Step 2 — Run the fix script

**Critical gotcha:** the Store version of Claude Desktop rewrites its config file from memory while running and on exit — *any edit made while Claude is open gets wiped*. The config must be edited while Claude is **fully closed**.

1. Download `fix-matlab-mcp.bat` and `fix-matlab-mcp.ps1` from this repo into the **same folder**
2. **Unblock both files**: right-click → Properties → check **Unblock** → OK (Windows blocks downloaded scripts)
3. **Quit Claude completely**: right-click the Claude tray icon (near the clock) → Quit. Just closing the window is not enough.
4. Double-click `fix-matlab-mcp.bat`
5. Wait for the green **SUCCESS** message, then let it relaunch Claude

The script:

- Refuses to run while Claude is open (prevents the config-wipe problem)
- Auto-detects your Claude config location (Store and non-Store installs)
- Auto-detects your MATLAB installation
- Backs up the config before touching it
- Validates the JSON before writing

### Step 3 — Verify

Open Claude Desktop → **Settings → Developer** → you should see **MATLAB** listed. Then ask Claude in a new chat:

> Run 2+2 in MATLAB

The first call takes ~30 s while it attaches to (or starts) a MATLAB session.

## What you can do with it

| Capability | How |
|---|---|
| Run MATLAB code inline | Claude executes any expression/statements |
| Create and run `.m` files | Claude writes the file, then runs it |
| Lint code | MATLAB Code Analyzer via MCP |
| Run unit tests | `runtests` integration |
| Simulink | Build models programmatically (`add_block`, `set_param`, `add_line`, `sim`) |
| Toolboxes | Anything installed is usable; Claude can list them |

Note: MCP-executed code does **not** echo into your Command Window history, but figures, workspace variables, and saved files appear normally in your MATLAB session.

## Demos

The `demos/` folder contains two toolbox-free examples that Claude built and tested end-to-end through this MCP connection:

- **`four_wheel_robot.m`** — animated 4-wheel differential-drive robot following waypoints with a proportional heading controller
- **`four_wheel_robot_lidar.m`** — the same robot with a ray-cast lidar model (25 beams, 240° FOV), obstacles, and gap-seeking collision avoidance with an emergency-turn reflex

Run either directly in MATLAB, or ask Claude to run and modify them.

## Troubleshooting

| Problem | Fix |
|---|---|
| "These files can't be opened" when running the .bat | Right-click → Properties → Unblock (both files) |
| Script says Claude is still running | Quit via the tray icon, not the window X |
| MATLAB server missing after restart | You edited the config while Claude was open — rerun the fix script with Claude closed |
| Server shows an error in Settings → Developer | Check MATLAB path: the script writes `--matlab-root` pointing at your auto-detected install; edit the config if you have multiple MATLABs |
| `.mcpb` double-click asks "How do you want to open this file?" | You have the Store version — use the manual install above |

## Credits

- [MathWorks MATLAB MCP Core Server](https://github.com/matlab/matlab-mcp-core-server) (official — see their repo for its license)
- Setup procedure and scripts developed with Claude (Anthropic)

## License

MIT — see [LICENSE](LICENSE). The MATLAB MCP server binary is **not** included in this repo; download it from MathWorks' official releases.

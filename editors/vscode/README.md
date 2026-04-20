# VSCode Config Backup Instructions

This repository helps you back up your Visual Studio Code (VSCode) configuration files—settings, keybindings, and snippets—so you can keep your environment consistent across machines or restore it if needed.

---

## How to Back Up Your VSCode Config

**Step 1: Open a Command Prompt**

Press `Win + R`, type `cmd`, and hit `Enter` to open the Command Prompt.

**Step 2: Navigate to Your Repo Folder**

Use the `cd` command to go to the folder where this repository is located. For example:
```bash
cd C:\path\to\your\repo
```

**Step 3: Copy Your VSCode Config Files**

Run the following commands to copy your settings, keybindings, and snippets into the repository:

```bash
copy "%APPDATA%\Code\User\settings.json" .\
copy "%APPDATA%\Code\User\keybindings.json" .\
xcopy "%APPDATA%\Code\User\snippets" ".\snippets" /E /I
```

- `settings.json` — your editor settings
- `keybindings.json` — your custom keyboard shortcuts
- `snippets` — your personal code snippets (copied recursively)

**Step 4: Commit and Push Your Changes**

After copying, add, commit, and push them to your remote repository:

```bash
git add .
git commit -m "Update VSCode config backup"
git push
```

---

## How to Restore Your Config

**WARNING:** This will overwrite your current settings, keybindings, and snippets. Make a backup first if you need to!

```bash
copy .\settings.json "%APPDATA%\Code\User\settings.json"
copy .\keybindings.json "%APPDATA%\Code\User\keybindings.json"
xcopy ".\snippets" "%APPDATA%\Code\User\snippets" /E /I
```

Restore extensions:

```bash
cat extensions.txt | xargs -L 1 code --install-extension
```

---

## Tips

- Repeat these steps whenever you want to update your backup.
- If you use extensions, consider backing those up separately (see [Extension: Settings Sync](https://marketplace.visualstudio.com/items?itemName=Shan.code-settings-sync)).

---

**Enjoy your portable VSCode setup!**

# 📋 Manual Post-Setup Guide (macOS)

While `bootstrap_mac.sh` and `macos-settings.sh` automate ~95% of machine provisioning (packages, dotfiles, SSH, Dock, and Finder behavior), Apple locks down certain GUI, security, and hardware features behind SIP (System Integrity Protection) and TCC (Privacy & Security).

Follow this quick **3-minute checklist** on any newly provisioned Mac.

---

## 1. 📂 Finder Sidebar & Organization

> **Why Manual?** Apple isolates the Finder Sidebar in `sharedfilelistd` and blocks command-line modification via SIP.

1. Open **Finder**.
2. Press **`Cmd + ,`** (or menu: **Finder → Settings...**) and select the **Sidebar** tab.
3. **Uncheck Unwanted Sections:**
   - [ ] Uncheck **Recents** (under Favorites).
   - [ ] Uncheck **Connected servers** (under Locations / Shared).
   - [ ] Uncheck **Bonjour computers** / network shares (under Locations / Shared).
   - [ ] Uncheck **Recent Tags** (under Tags).
4. **Pin Custom Folders:**
   - Open your Home directory in Finder (`Cmd + Shift + H`).
   - Select your **`src`** folder (or any key directory) and press:
     ```text
     Command + Control + T
     ```
     *(This instantly pins it to your Favorites sidebar).*
5. **Reorder Favorites:**
   - Click and drag the folders in the sidebar to match your preferred order:
     1. `~` (Home / kmassada)
     2. `src`
     3. `Downloads`
     4. `Desktop`
     5. `Applications`

---

## 2. 🆔 Apple ID & Mac App Store (`mas`)

> **Why Manual?** Mac App Store purchases are tied to your Apple account and require a GUI sign-in before `mas` CLI can install/update apps.

1. Open **System Settings → Sign in to Apple Account** (or open the **App Store** app).
2. Sign into your Apple ID.
3. Once signed in, run:
   ```bash
   brew bundle --file=~/src/dotfiles/Brewfile
   ```
   *(This ensures any Mac App Store apps like WhatsApp, Canva, etc. sync automatically).*

---

## 3. 🔤 Terminal Font & Apprentice Colors

> **Why Manual?** Terminal emulators store their UI profiles in sandboxed application containers.

1. **Install Font:**
   - Ensure a Powerlevel10k-compatible Nerd Font is selected (e.g. `MesloLGS NF` or `JetBrainsMono Nerd Font`).
   - If using iTerm2: **Preferences (`Cmd + ,`) → Profiles → Text → Font** → Select `MesloLGS NF` (13pt or 14pt).
2. **Apprentice Theme:**
   - Import the **Apprentice** color palette:
     - iTerm2: **Preferences → Profiles → Colors → Color Presets... → Import** (Apprentice scheme).
3. **Natural Text Editing (Optional):**
   - In iTerm2: **Preferences → Profiles → Keys → Key Mappings → Presets... → Natural Text Editing** (allows `Option + Arrow` word jumps).

---

## 4. 👆 Touch ID for `sudo` (Optional)

> **Why Manual?** Requires local sudo elevation to write to `/etc/pam.d/sudo_local`. Persists across macOS system updates.

To use Touch ID / Apple Watch to authorize `sudo` commands in Terminal:

```bash
sudo cp /etc/pam.d/sudo_local.template /etc/pam.d/sudo_local
sudo sed -i '' 's/#auth/auth/' /etc/pam.d/sudo_local
```

Test it by opening a new terminal window and running `sudo true`.

---

## 5. 🛡️ System Permissions (Security & Privacy)

In **System Settings → Privacy & Security**:
- **Full Disk Access:** Grant to **Terminal** (or **iTerm2**) if you need CLI tools to inspect system logs, backups, or launchctl daemons without permission prompts.
- **Accessibility:** Grant to window managers (e.g., Rectangle, Raycast, AeroSpace) if installed.

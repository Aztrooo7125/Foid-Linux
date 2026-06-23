#!/bin/bash
# ================================================================
#  VOID LINUX — GNOME POST-INSTALL SETUP  (MacTahoe Edition)
#  Polished, Windows-user-friendly, production-ready.
# ================================================================

# ── COLOR & LOGGING ──────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log()  { echo -e "\n${GREEN}${BOLD}━━ $1 ━━${NC}"; }
info() { echo -e "  ${CYAN}→${NC}  $1"; }
ok()   { echo -e "  ${GREEN}✓${NC}  $1"; }
warn() { echo -e "  ${YELLOW}⚠${NC}  $1"; }

# ── PACKAGE HELPERS ──────────────────────────────────────────────
# Always sync repos + auto-confirm installs
xi() { sudo xbps-install -Sy "$@"; }
# Recursive + auto-confirm removes; silently skip if not installed
xr() { sudo xbps-remove -Ry "$@" 2>/dev/null || true; }

# Enable a runit service safely (skips if symlink already exists)
svc_enable() {
    for svc in "$@"; do
        if [ ! -e "/var/service/$svc" ]; then
            sudo ln -s "/etc/sv/$svc" /var/service/
            ok "Service enabled: $svc"
        else
            warn "Already enabled:  $svc"
        fi
    done
}

# ================================================================
# 1. SYSTEM UPDATE & REPOSITORIES
# ================================================================
log "System update & repositories"

sudo xbps-install -Syu
xi void-repo-nonfree void-repo-multilib void-repo-multilib-nonfree
sudo xbps-install -Syu      # re-sync after new repos

# ================================================================
# 2. INTEL HARDWARE SUPPORT
# ================================================================
log "Intel firmware & GPU acceleration"

xi linux-firmware intel-ucode

if grep -q "GenuineIntel" /proc/cpuinfo; then
    info "Intel CPU detected — configuring i915 power features"
    sudo tee /etc/modprobe.d/i915.conf > /dev/null << 'EOF'
options i915 enable_guc=3 enable_psr=1 enable_fbc=1
EOF
fi

KVER=$(uname -r | grep -oP '^\d+\.\d+')
info "Reconfiguring linux${KVER}..."
sudo xbps-reconfigure -f "linux${KVER}"

xi vulkan-loader mesa-vulkan-intel intel-video-accel

# ================================================================
# 3. AUDIO — PipeWire (replaces PulseAudio)
# ================================================================
log "Audio: PipeWire (replaces PulseAudio)"

# Remove PulseAudio first — silently ignored if not present
xr pulseaudio pulseaudio-utils alsa-plugins-pulseaudio

xi pipewire rtkit alsa-pipewire

# Enable PulseAudio compatibility layer (most apps speak PA, not PW)
sudo mkdir -p /etc/pipewire/pipewire.conf.d
sudo ln -sf /usr/share/examples/pipewire/20-pipewire-pulse.conf \
    /etc/pipewire/pipewire.conf.d/ 2>/dev/null || true

# Autostart PipeWire + WirePlumber on GNOME login
sudo mkdir -p /etc/xdg/autostart
sudo ln -sf /usr/share/applications/pipewire.desktop \
    /etc/xdg/autostart/ 2>/dev/null || true
sudo ln -sf /usr/share/applications/wireplumber.desktop \
    /etc/xdg/autostart/ 2>/dev/null || true

svc_enable rtkit

# ================================================================
# 4. GRUB — silent, fast boot
# ================================================================
log "GRUB configuration"

sudo tee /etc/default/grub > /dev/null << 'EOF'
GRUB_TIMEOUT=0
GRUB_TIMEOUT_STYLE=hidden
GRUB_DISTRIBUTOR="Void Linux"
GRUB_DEFAULT=0
GRUB_CMDLINE_LINUX_DEFAULT="quiet loglevel=3 nowatchdog intel_pstate=active"
GRUB_DISABLE_RECOVERY=true
EOF

# BUG FIX: original script forgot this — without it the config change is never applied
sudo grub-mkconfig -o /boot/grub/grub.cfg
ok "GRUB config regenerated"

# ================================================================
# 5. GNOME DESKTOP ENVIRONMENT
# ================================================================
log "GNOME desktop environment"

# Core GNOME metapackage (shell, nautilus, mutter, gdm, etc.)
xi gnome

# Extras not included in the metapackage
xi gnome-tweaks
xi gnome-disk-utility
xi gnome-system-monitor
xi gnome-screenshot
xi gnome-calculator
xi gnome-calendar
xi gnome-weather
xi gnome-logs
xi gnome-font-viewer
xi gnome-software
xi gedit
xi file-roller
xi evince
xi eog
xi cheese

# ================================================================
# 6. DISPLAY MANAGER, SESSION & CORE SERVICES
# ================================================================
log "Display manager & session services"

# elogind = logind for non-systemd systems — GNOME needs this for
# user sessions, seat management, idle detection, etc.
xi gdm elogind polkit polkit-gnome dbus NetworkManager avahi

# Replace TTY autologin with GDM
[ -d /etc/sv/agetty-tty1 ] && sudo touch /etc/sv/agetty-tty1/down
sudo rm -f /var/service/agetty-tty1

svc_enable dbus elogind avahi-daemon NetworkManager gdm

# ================================================================
# 7. FLATPAK, FLATHUB & APPS
# ================================================================
log "Flatpak, Flathub & applications"

# BUG FIX: original had "xi-Sy flatpak" (missing space — would fail)
xi flatpak
flatpak remote-add --if-not-exists flathub \
    https://flathub.org/repo/flathub.flatpakrepo

info "Installing Spotify..."
flatpak install -y flathub com.spotify.Client

# Graphical GNOME extension manager (browse/install/toggle extensions)
info "Installing Extension Manager..."
flatpak install -y flathub com.mattjakeman.ExtensionManager

# ================================================================
# 8. FONTS
# ================================================================
log "Fonts — open-source + Microsoft core fonts"

# Open-source typefaces
xi dejavu-fonts-ttf
xi noto-fonts-ttf
xi noto-fonts-ttf-extra
xi noto-fonts-cjk
xi noto-fonts-emoji
xi fonts-roboto-ttf
xi fonts-droid-ttf
xi ttf-ubuntu-font-family
xi font-adobe-source-code-pro
xi cantarell-fonts

# Microsoft fonts: Arial, Times New Roman, Verdana, Tahoma, Courier New, etc.
# Requires void-repo-nonfree (added above)
xi msttcorefonts

# Rebuild system font cache
sudo fc-cache -fv
ok "Font cache rebuilt"

# ================================================================
# 9. GVFS — Nautilus file manager integration
# ================================================================
log "GVFS (full Nautilus/file manager functionality)"

# gvfs enables mounting, network shares, MTP devices (Android phones),
# camera access, optical drives, etc. — like Windows Explorer integration
xi gvfs
xi gvfs-mtp        # Android phones via USB
xi gvfs-afc        # Apple iOS devices
xi gvfs-smb        # Windows network shares (SMB/CIFS)
xi gvfs-gphoto2    # Digital cameras
xi gvfs-cdda       # Audio CDs

# Thumbnail generation (like Windows thumbnail cache)
xi tumbler
xi ffmpegthumbnailer

# ================================================================
# 10. MEDIA & CODECS
# ================================================================
log "Media apps & codec support"

xi mpv
xi imv
xi ffmpeg
xi yt-dlp
xi gstreamer1
xi gst-plugins-base1
xi gst-plugins-good1
xi gst-plugins-bad1
xi gst-plugins-ugly1    # MP3, H.264, etc. (patent-encumbered)
xi gst-libav            # FFmpeg-backed codec bridge

# ================================================================
# 11. BLUETOOTH
# ================================================================
log "Bluetooth"

xi bluez blueman
svc_enable bluetoothd

# ================================================================
# 12. PRINTING (CUPS)
# ================================================================
log "Printing support (CUPS)"

xi cups cups-pk-helper system-config-printer
svc_enable cupsd

# ================================================================
# 13. ARCHIVE TOOLS (like 7-Zip / WinRAR on Windows)
# ================================================================
log "Archive tools"

xi p7zip zip unzip unrar

# ================================================================
# 14. QoL TOOLS & UTILITIES
# ================================================================
log "Quality-of-life tools & dependencies"

# Browser + core CLI
xi firefox curl wget htop bash-completion

# MacTahoe theme build dependencies
xi gcc git make sassc glib-devel libxml2

# Optional but improve MacTahoe rendering quality
xi imagemagick dialog optipng inkscape

# XDG integration (sets up Desktop, Downloads, Documents, etc. folders)
xi xdg-utils xdg-user-dirs xdg-user-dirs-gtk

# Desktop portals (needed for Flatpak apps to open files, share screen, etc.)
xi xdg-desktop-portal xdg-desktop-portal-gtk

# Power & battery reporting
xi upower power-profiles-daemon
svc_enable power-profiles-daemon

# Brightness control (for laptops)
xi brightnessctl

# Create XDG user directories (Downloads, Documents, Pictures, etc.)
xdg-user-dirs-update
ok "User directories created"

# ================================================================
# 15. MacTahoe GTK THEME + ICON THEME
# ================================================================
log "MacTahoe GTK + Icon theme"

THEME_TMP=$(mktemp -d)
ICON_TMP=$(mktemp -d)

# ── GTK Theme ────────────────────────────────────────────────────
info "Cloning MacTahoe GTK theme..."
git clone --depth=1 https://github.com/vinceliuice/MacTahoe-gtk-theme.git \
    "$THEME_TMP"

info "Installing theme (all variants + libadwaita patch)..."
pushd "$THEME_TMP" > /dev/null
# --libadwaita patches GTK4/libadwaita apps (Nautilus, Calendar, etc.)
# --silent-mode skips interactive prompts — safe for scripted installs
./install.sh --libadwaita --silent-mode
popd > /dev/null

# ── Icon Theme ───────────────────────────────────────────────────
info "Cloning MacTahoe icon theme..."
git clone --depth=1 https://github.com/vinceliuice/MacTahoe-icon-theme.git \
    "$ICON_TMP"

info "Installing icon theme..."
pushd "$ICON_TMP" > /dev/null
./install.sh
popd > /dev/null

rm -rf "$THEME_TMP" "$ICON_TMP"
ok "MacTahoe theme + icons installed to ~/.themes and ~/.local/share/icons"

# ================================================================
# 16. GNOME SETTINGS — polished, Windows-user-friendly defaults
# ================================================================
log "Applying GNOME defaults"

# ── Window control buttons (Minimize + Maximize + Close, like Windows) ──
gsettings set org.gnome.desktop.wm.preferences button-layout \
    "appmenu:minimize,maximize,close"

# ── Apply MacTahoe theme ──────────────────────────────────────────
gsettings set org.gnome.desktop.interface gtk-theme      "MacTahoe-Dark"
gsettings set org.gnome.desktop.interface icon-theme     "MacTahoe"
gsettings set org.gnome.desktop.wm.preferences theme     "MacTahoe-Dark"
gsettings set org.gnome.desktop.interface cursor-theme   "Adwaita"

# ── Fonts (clean, modern — matches macOS Tahoe aesthetic) ────────
gsettings set org.gnome.desktop.interface font-name          "Cantarell 11"
gsettings set org.gnome.desktop.interface document-font-name "Cantarell 11"
gsettings set org.gnome.desktop.interface monospace-font-name "Source Code Pro 10"
gsettings set org.gnome.desktop.wm.preferences titlebar-font "Cantarell Bold 11"

# ── Mouse & touchpad ──────────────────────────────────────────────
gsettings set org.gnome.desktop.peripherals.mouse natural-scroll false
gsettings set org.gnome.desktop.peripherals.touchpad natural-scroll true
gsettings set org.gnome.desktop.peripherals.touchpad two-finger-scrolling-enabled true
gsettings set org.gnome.desktop.peripherals.touchpad tap-to-click true
gsettings set org.gnome.desktop.peripherals.touchpad click-method "fingers"

# ── Taskbar / clock ───────────────────────────────────────────────
gsettings set org.gnome.desktop.interface show-battery-percentage true
gsettings set org.gnome.desktop.interface clock-show-weekday true
gsettings set org.gnome.desktop.interface clock-show-date true
gsettings set org.gnome.desktop.interface clock-format "12h"

# ── Night Light (warm screen at night — easy on eyes) ────────────
gsettings set org.gnome.settings-daemon.plugins.color night-light-enabled true
gsettings set org.gnome.settings-daemon.plugins.color night-light-temperature 4000

# ── Screenshot shortcut = Print Screen key (just like Windows) ───
gsettings set org.gnome.shell.keybindings show-screenshot-ui "['Print']"

# ── Disable hot corner (surprising for Windows users) ────────────
gsettings set org.gnome.desktop.interface enable-hot-corners false

# ── Power / idle ──────────────────────────────────────────────────
gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-timeout 3600
gsettings set org.gnome.settings-daemon.plugins.power idle-dim true

# ── Nautilus (file manager) ───────────────────────────────────────
gsettings set org.gnome.nautilus.preferences default-folder-viewer "list-view"
gsettings set org.gnome.nautilus.icon-view default-zoom-level "small"
gsettings set org.gnome.nautilus.preferences show-create-link true
gsettings set org.gnome.nautilus.preferences show-delete-permanently true

# ── Text editor (gedit) ───────────────────────────────────────────
gsettings set org.gnome.gedit.preferences.ui show-line-numbers true
gsettings set org.gnome.gedit.preferences.editor wrap-last-split-mode "word"
gsettings set org.gnome.gedit.preferences.editor display-right-margin false

ok "GNOME defaults applied"

# ================================================================
# DONE
# ================================================================
echo ""
echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}${BOLD}║           All done!  Reboot to enter your desktop.          ║${NC}"
echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BOLD}After rebooting, do these 3 quick things:${NC}"
echo ""
echo -e "  ${CYAN}1.${NC} Open ${BOLD}Extension Manager${NC} (in your app grid) and install:"
echo -e "       • ${BOLD}User Themes${NC}     — lets GNOME Shell use MacTahoe's panel/shell theme"
echo -e "       • ${BOLD}Dash to Dock${NC}    — macOS-style dock at the bottom"
echo -e "       • ${BOLD}Blur my Shell${NC}   — frosted-glass panel & overview effect"
echo ""
echo -e "  ${CYAN}2.${NC} Open ${BOLD}GNOME Tweaks${NC} → Appearance → Shell → pick ${BOLD}MacTahoe-Dark${NC}"
echo ""
echo -e "  ${CYAN}3.${NC} Open ${BOLD}GNOME Software${NC} to browse & install Flatpak apps graphically"
echo -e "       (Spotify is already installed — find it in the app grid)"
echo ""
warn "If Bluetooth doesn't appear: sudo sv restart bluetoothd"
warn "If printing isn't detected:  sudo sv restart cupsd"
echo ""

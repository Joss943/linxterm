#!/bin/bash
# LinXterm installer: builds the application and creates the launchers
# (applications menu + desktop shortcut). No administrator rights needed.
set -e
APPDIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
APPID="dev.linxterm.LinXterm"
cd "$APPDIR"

echo "==> Building LinXterm"
./build.sh

echo "==> Installing the icon"
ICONDIR="$HOME/.local/share/icons/hicolor/scalable/apps"
mkdir -p "$ICONDIR"
cp icons/linxterm.svg "$ICONDIR/$APPID.svg"
command -v gtk-update-icon-cache >/dev/null && gtk-update-icon-cache -q -f -t "$HOME/.local/share/icons/hicolor" 2>/dev/null || true

echo "==> Installing the command line launcher (~/.local/bin/linxterm)"
mkdir -p "$HOME/.local/bin"
ln -sf "$APPDIR/bin/linxterm" "$HOME/.local/bin/linxterm"

DESKTOP_ENTRY="[Desktop Entry]
Type=Application
Version=1.0
Name=LinXterm
GenericName=Enhanced terminal (SSH, X11, RDP, VNC, SFTP)
Comment=Tabbed SSH client, X11 forwarding, RDP, VNC, SFTP/FTP browser and network tools
Exec=$APPDIR/bin/linxterm
Icon=$APPID
Terminal=false
StartupNotify=true
StartupWMClass=$APPID
Categories=Network;RemoteAccess;
Keywords=ssh;sftp;ftp;telnet;rdp;vnc;serial;x11;terminal;mobaxterm;
Actions=NewTerminal;TextEditor;

[Desktop Action NewTerminal]
Name=New local terminal
Exec=$APPDIR/bin/linxterm --local

[Desktop Action TextEditor]
Name=Text editor
Exec=$APPDIR/bin/linxterm --edit \"\"
"

echo "==> Installing the applications menu entry"
mkdir -p "$HOME/.local/share/applications"
printf '%s' "$DESKTOP_ENTRY" > "$HOME/.local/share/applications/$APPID.desktop"
command -v update-desktop-database >/dev/null && update-desktop-database -q "$HOME/.local/share/applications" 2>/dev/null || true

DESK="$(xdg-user-dir DESKTOP 2>/dev/null || true)"
[ -z "$DESK" ] && DESK="$HOME/Desktop"
if [ -d "$DESK" ]; then
  echo "==> Creating the desktop shortcut in $DESK"
  printf '%s' "$DESKTOP_ENTRY" > "$DESK/LinXterm.desktop"
  chmod +x "$DESK/LinXterm.desktop"
  # allow launching from the desktop (GNOME / Desktop Icons NG)
  gio set "$DESK/LinXterm.desktop" metadata::trusted true 2>/dev/null || true
fi
echo "==> Done. Start LinXterm from the desktop icon, the applications menu or with: linxterm"

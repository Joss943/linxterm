{ LinXterm - packages manager (MobApt equivalent): optional tools, installed
  with the distribution package manager in a terminal tab. }
unit lxpackages;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, BaseUnix, lxgtk, lxutil, lxconfig, lxtabs;

procedure ShowPackagesWindow;

implementation

uses
  StrUtils;

type
  TPkg = record
    Name, Check, Dnf, Apt, Pacman, Desc: string;
  end;

const
  Packages: array[0..31] of TPkg = (
    (Name: 'FreeRDP'; Check: 'xfreerdp|sdl-freerdp|xfreerdp3|wlfreerdp'; Dnf: 'freerdp'; Apt: 'freerdp2-x11'; Pacman: 'freerdp'; Desc: 'RDP client used by RDP sessions'),
    (Name: 'GTK-VNC'; Check: '@libgtk-vnc-2.0.so.0'; Dnf: 'gtk-vnc2'; Apt: 'libgtk-vnc-2.0-0'; Pacman: 'gtk-vnc'; Desc: 'embedded VNC viewer of VNC sessions'),
    (Name: 'WebKitGTK'; Check: '@libwebkit2gtk-4.1.so.0'; Dnf: 'webkit2gtk4.1'; Apt: 'libwebkit2gtk-4.1-0'; Pacman: 'webkit2gtk-4.1'; Desc: 'web engine of Browser sessions'),
    (Name: 'GtkSourceView 4'; Check: '@libgtksourceview-4.so.0'; Dnf: 'gtksourceview4'; Apt: 'libgtksourceview-4-0'; Pacman: 'gtksourceview4'; Desc: 'syntax highlighting of the text editor'),
    (Name: 'libsecret'; Check: '@libsecret-1.so.0'; Dnf: 'libsecret'; Apt: 'libsecret-1-0'; Pacman: 'libsecret'; Desc: 'stores the passwords in the GNOME keyring'),
    (Name: 'OpenSSH client'; Check: 'ssh'; Dnf: 'openssh-clients'; Apt: 'openssh-client'; Pacman: 'openssh'; Desc: 'SSH, SFTP sessions and tunnels'),
    (Name: 'OpenSSH server'; Check: '/usr/sbin/sshd'; Dnf: 'openssh-server'; Apt: 'openssh-server'; Pacman: 'openssh'; Desc: 'SSH/SFTP server of the Servers window'),
    (Name: 'Mosh'; Check: 'mosh'; Dnf: 'mosh'; Apt: 'mosh'; Pacman: 'mosh'; Desc: 'mobile shell sessions'),
    (Name: 'iperf3'; Check: 'iperf3'; Dnf: 'iperf3'; Apt: 'iperf3'; Pacman: 'iperf3'; Desc: 'network bandwidth measurement (Servers window)'),
    (Name: 'Nmap'; Check: 'nmap'; Dnf: 'nmap'; Apt: 'nmap'; Pacman: 'nmap'; Desc: 'advanced network scanner'),
    (Name: 'htop'; Check: 'htop'; Dnf: 'htop'; Apt: 'htop'; Pacman: 'htop'; Desc: 'interactive process viewer'),
    (Name: 'traceroute'; Check: 'traceroute'; Dnf: 'traceroute'; Apt: 'traceroute'; Pacman: 'traceroute'; Desc: 'network path discovery'),
    (Name: 'tcpdump'; Check: 'tcpdump'; Dnf: 'tcpdump'; Apt: 'tcpdump'; Pacman: 'tcpdump'; Desc: 'network packets capture'),
    (Name: 'Wireshark'; Check: 'wireshark'; Dnf: 'wireshark'; Apt: 'wireshark'; Pacman: 'wireshark-qt'; Desc: 'graphical network packets analyzer'),
    (Name: 'whois'; Check: 'whois'; Dnf: 'whois'; Apt: 'whois'; Pacman: 'whois'; Desc: 'domain name registration lookup'),
    (Name: 'dig / nslookup'; Check: 'dig'; Dnf: 'bind-utils'; Apt: 'dnsutils'; Pacman: 'bind'; Desc: 'DNS lookup tools'),
    (Name: 'telnet'; Check: 'telnet'; Dnf: 'telnet'; Apt: 'telnet'; Pacman: 'inetutils'; Desc: 'classic telnet client (LinXterm has its own)'),
    (Name: 'picocom'; Check: 'picocom'; Dnf: 'picocom'; Apt: 'picocom'; Pacman: 'picocom'; Desc: 'minimal serial terminal'),
    (Name: 'minicom'; Check: 'minicom'; Dnf: 'minicom'; Apt: 'minicom'; Pacman: 'minicom'; Desc: 'serial terminal emulator'),
    (Name: 'tmux'; Check: 'tmux'; Dnf: 'tmux'; Apt: 'tmux'; Pacman: 'tmux'; Desc: 'terminal multiplexer'),
    (Name: 'GNU screen'; Check: 'screen'; Dnf: 'screen'; Apt: 'screen'; Pacman: 'screen'; Desc: 'terminal multiplexer'),
    (Name: 'Midnight Commander'; Check: 'mc'; Dnf: 'mc'; Apt: 'mc'; Pacman: 'mc'; Desc: 'text mode file manager'),
    (Name: 'sshpass'; Check: 'sshpass'; Dnf: 'sshpass'; Apt: 'sshpass'; Pacman: 'sshpass'; Desc: 'non interactive SSH password provider'),
    (Name: 'lftp'; Check: 'lftp'; Dnf: 'lftp'; Apt: 'lftp'; Pacman: 'lftp'; Desc: 'command line FTP / SFTP client'),
    (Name: 'socat'; Check: 'socat'; Dnf: 'socat'; Apt: 'socat'; Pacman: 'socat'; Desc: 'multipurpose relay (sockets, serial ports)'),
    (Name: 'X11 test applications'; Check: 'xeyes'; Dnf: 'xorg-x11-apps'; Apt: 'x11-apps'; Pacman: 'xorg-xeyes'; Desc: 'xeyes, xclock... to test X11 forwarding'),
    (Name: 'Meld'; Check: 'meld'; Dnf: 'meld'; Apt: 'meld'; Pacman: 'meld'; Desc: 'graphical diff and merge tool'),
    (Name: 'Git'; Check: 'git'; Dnf: 'git'; Apt: 'git'; Pacman: 'git'; Desc: 'version control system'),
    (Name: 'Vim'; Check: 'vim'; Dnf: 'vim-enhanced'; Apt: 'vim'; Pacman: 'vim'; Desc: 'text editor'),
    (Name: 'lsof'; Check: 'lsof'; Dnf: 'lsof'; Apt: 'lsof'; Pacman: 'lsof'; Desc: 'list open files and sockets'),
    (Name: 'iftop'; Check: 'iftop'; Dnf: 'iftop'; Apt: 'iftop'; Pacman: 'iftop'; Desc: 'bandwidth usage per connection'),
    (Name: 'ncdu'; Check: 'ncdu'; Dnf: 'ncdu'; Apt: 'ncdu'; Pacman: 'ncdu'; Desc: 'disk usage analyzer'));

type
  TPkgUi = class
  public
    Win, Store, View, ShowInst, ShowAvail, Filter, Info: Pointer;
    Manager: string;
    procedure Refresh;
    function SelectedPackages(Installed: Boolean): TStringArray;
  end;

var
  Ui: TPkgUi = nil;

function IsInstalled(const P: TPkg): Boolean;
var
  alts: TStringArray;
  a: string;
begin
  Result := False;
  alts := SplitString(P.Check, '|');
  for a in alts do
  begin
    if a = '' then Continue;
    if a[1] = '@' then
    begin
      if FileExists('/usr/lib64/' + Copy(a, 2, MaxInt)) or FileExists('/usr/lib/' + Copy(a, 2, MaxInt)) or
        FileExists('/usr/lib/x86_64-linux-gnu/' + Copy(a, 2, MaxInt)) then Exit(True);
    end
    else if a[1] = '/' then
    begin
      if FileExists(a) then Exit(True);
    end
    else if FindProgram(a) <> '' then
      Exit(True);
  end;
end;

function DetectManager: string;
begin
  if FindProgram('dnf') <> '' then Result := 'dnf'
  else if FindProgram('apt-get') <> '' then Result := 'apt'
  else if FindProgram('pacman') <> '' then Result := 'pacman'
  else if FindProgram('zypper') <> '' then Result := 'zypper'
  else Result := '';
end;

function PkgName(const P: TPkg; const Manager: string): string;
begin
  if Manager = 'apt' then Result := P.Apt
  else if Manager = 'pacman' then Result := P.Pacman
  else Result := P.Dnf;
end;

procedure TPkgUi.Refresh;
var
  i: Integer;
  it: TGtkTreeIter;
  inst: Boolean;
  flt: string;
begin
  gtk_list_store_clear(Store);
  flt := LowerCase(Trim(EntryText(Filter)));
  for i := 0 to High(Packages) do
  begin
    inst := IsInstalled(Packages[i]);
    if inst and not gtk_toggle_button_get_active(ShowInst) then Continue;
    if not inst and not gtk_toggle_button_get_active(ShowAvail) then Continue;
    if (flt <> '') and (Pos(flt, LowerCase(Packages[i].Name + ' ' + Packages[i].Desc + ' ' + PkgName(Packages[i], Manager))) = 0) then
      Continue;
    gtk_list_store_append(Store, @it);
    gtk_list_store_set(Store, @it, 0, IconPixbuf(IfThen(inst, 'lx-check', 'lx-cancel'), 16),
      1, PChar(Packages[i].Name), 2, PChar(PkgName(Packages[i], Manager)), 3, PChar(Packages[i].Desc),
      4, PChar(IfThen(inst, 'installed', 'not installed')), 5, GBool(inst), -1);
  end;
end;

function TPkgUi.SelectedPackages(Installed: Boolean): TStringArray;
var
  rows, it: PGList;
  iter: TGtkTreeIter;
  model: Pointer;
  p: PChar;
  inst: gboolean;
  n: Integer;
begin
  Result := nil;
  n := 0;
  model := nil;
  rows := gtk_tree_selection_get_selected_rows(gtk_tree_view_get_selection(View), @model);
  it := rows;
  while it <> nil do
  begin
    if gtk_tree_model_get_iter(model, @iter, it^.data) then
    begin
      p := nil;
      gtk_tree_model_get(model, @iter, 2, @p, 5, @inst, -1);
      if (not Installed) or inst then
      begin
        SetLength(Result, n + 1);
        Result[n] := TakeStr(p);
        Inc(n);
      end
      else
        g_free(p);
    end;
    gtk_tree_path_free(it^.data);
    it := it^.next;
  end;
  g_list_free(rows);
end;

procedure RunManager(const Action: string; const Pkgs: TStringArray);
var
  args: array of string;
  i: Integer;
begin
  if Length(Pkgs) = 0 then
  begin
    MsgInfo('No package selected', 'Select one or more packages in the list first.');
    Exit;
  end;
  if Ui.Manager = '' then
  begin
    MsgError('No supported package manager found', 'dnf, apt, pacman or zypper is required.');
    Exit;
  end;
  args := nil;
  SetLength(args, 3);
  args[0] := 'sudo';
  if Ui.Manager = 'apt' then
  begin
    args[1] := 'apt-get';
    if Action = 'install' then args[2] := 'install' else args[2] := 'remove';
  end
  else if Ui.Manager = 'pacman' then
  begin
    args[1] := 'pacman';
    if Action = 'install' then args[2] := '-S' else args[2] := '-R';
  end
  else
  begin
    args[1] := Ui.Manager;
    args[2] := Action;
  end;
  for i := 0 to High(Pkgs) do
  begin
    SetLength(args, Length(args) + 1);
    args[High(args)] := Pkgs[i];
  end;
  App.RunCommandTab(IfThen(Action = 'install', 'Install ', 'Remove ') + Pkgs[0] + IfThen(Length(Pkgs) > 1, '...', ''),
    'system-software-install', args);
  MsgInfo('Package manager started', 'Type your password in the terminal tab when "sudo" asks for it.'#10 +
    'The list is refreshed when you come back to this window.');
end;

procedure BInstall(b: Pointer; data: gpointer); cdecl;
begin
  RunManager('install', Ui.SelectedPackages(False));
end;

procedure BRemove(b: Pointer; data: gpointer); cdecl;
begin
  if AskYesNo('Uninstall the selected packages?', 'Other programs may depend on them.') then
    RunManager('remove', Ui.SelectedPackages(True));
end;

procedure BClose(b: Pointer; data: gpointer); cdecl;
begin
  gtk_widget_hide(Ui.Win);
end;

procedure FilterChanged(w: Pointer; data: gpointer); cdecl;
begin
  Ui.Refresh;
end;

function FocusIn(w: Pointer; ev: Pointer; data: gpointer): gboolean; cdecl;
begin
  Ui.Refresh;
  Result := False;
end;

function WinDelete(w: Pointer; ev: Pointer; data: gpointer): gboolean; cdecl;
begin
  gtk_widget_hide(w);
  Result := True;
end;

procedure ShowPackagesWindow;
var
  vbox, hb, b, col, cell, title: Pointer;
  types: array[0..5] of GType;
  i: Integer;
  titles: array[1..4] of string = ('Package', 'Package name', 'Description', 'Status');
begin
  if Ui = nil then
  begin
    Ui := TPkgUi.Create;
    Ui.Manager := DetectManager;
    Ui.Win := gtk_window_new(GTK_WINDOW_TOPLEVEL);
    gtk_window_set_title(Ui.Win, 'LinXterm packages manager');
    gtk_window_set_default_size(Ui.Win, 900, 560);
    gtk_window_set_icon(Ui.Win, IconPixbuf('system-software-install', 64));
    gtk_window_set_transient_for(Ui.Win, MainWindowWidget);
    AddClass(Ui.Win, 'lx-main');
    vbox := gtk_box_new(GTK_ORIENTATION_VERTICAL, 8);
    SetMargins(vbox, 12);
    title := NewMarkupLabel('<b>LinXterm packages manager</b>'#10'Optional tools installed with ' +
      IfThen(Ui.Manager = '', 'your package manager', '<b>' + Ui.Manager + '</b>') + ' (administrator password required)', 0.5);
    gtk_label_set_justify(title, GTK_JUSTIFY_CENTER);
    gtk_box_pack_start(vbox, title, False, False, 0);
    hb := gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 12);
    Ui.ShowInst := gtk_check_button_new_with_label('Show installed packages');
    gtk_toggle_button_set_active(Ui.ShowInst, True);
    Connect(Ui.ShowInst, 'toggled', @FilterChanged, nil);
    gtk_box_pack_start(hb, Ui.ShowInst, False, False, 0);
    Ui.ShowAvail := gtk_check_button_new_with_label('Show available packages');
    gtk_toggle_button_set_active(Ui.ShowAvail, True);
    Connect(Ui.ShowAvail, 'toggled', @FilterChanged, nil);
    gtk_box_pack_start(hb, Ui.ShowAvail, False, False, 0);
    Ui.Filter := gtk_search_entry_new;
    gtk_entry_set_placeholder_text(Ui.Filter, 'Filter packages');
    Connect(Ui.Filter, 'search-changed', @FilterChanged, nil);
    gtk_box_pack_end(hb, Ui.Filter, False, False, 0);
    gtk_box_pack_start(vbox, hb, False, False, 0);
    types[0] := gdk_pixbuf_get_type;
    for i := 1 to 4 do types[i] := G_TYPE_STRING;
    types[5] := G_TYPE_BOOLEAN;
    Ui.Store := gtk_list_store_newv(6, @types[0]);
    Ui.View := gtk_tree_view_new_with_model(Ui.Store);
    g_object_unref(Ui.Store);
    gtk_tree_selection_set_mode(gtk_tree_view_get_selection(Ui.View), GTK_SELECTION_MULTIPLE);
    col := gtk_tree_view_column_new;
    cell := gtk_cell_renderer_pixbuf_new;
    gtk_tree_view_column_pack_start(col, cell, False);
    gtk_tree_view_column_add_attribute(col, cell, 'pixbuf', 0);
    gtk_tree_view_append_column(Ui.View, col);
    for i := 1 to 4 do
    begin
      col := gtk_tree_view_column_new;
      gtk_tree_view_column_set_title(col, PChar(titles[i]));
      cell := gtk_cell_renderer_text_new;
      gtk_tree_view_column_pack_start(col, cell, True);
      gtk_tree_view_column_add_attribute(col, cell, 'text', i);
      gtk_tree_view_column_set_resizable(col, True);
      gtk_tree_view_column_set_sort_column_id(col, i);
      gtk_tree_view_append_column(Ui.View, col);
    end;
    gtk_box_pack_start(vbox, NewScrolled(Ui.View), True, True, 0);
    hb := gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 12);
    gtk_widget_set_halign(hb, GTK_ALIGN_CENTER);
    b := NewIconButton('system-software-install', '_Install / update', '', 16);
    Connect(b, 'clicked', @BInstall, nil);
    gtk_box_pack_start(hb, b, False, False, 0);
    b := NewIconButton('lx-cancel', '_Uninstall', '', 16);
    Connect(b, 'clicked', @BRemove, nil);
    gtk_box_pack_start(hb, b, False, False, 0);
    b := NewIconButton('window-close', '_Close', '', 16);
    Connect(b, 'clicked', @BClose, nil);
    gtk_box_pack_start(hb, b, False, False, 0);
    gtk_box_pack_start(vbox, hb, False, False, 0);
    gtk_container_add(Ui.Win, vbox);
    Connect(Ui.Win, 'delete-event', @WinDelete, nil);
    Connect(Ui.Win, 'focus-in-event', @FocusIn, nil);
  end;
  Ui.Refresh;
  gtk_widget_show_all(Ui.Win);
  gtk_window_present(Ui.Win);
end;

initialization
  ShowPackagesProc := @ShowPackagesWindow;

end.

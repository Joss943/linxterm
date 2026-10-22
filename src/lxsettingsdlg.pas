{ LinXterm - "LinXterm Configuration" dialog and passwords management. }
unit lxsettingsdlg;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, lxgtk, lxutil, lxconfig, lxtabs, lxterminal;

procedure ShowSettingsDialog;
procedure ShowPasswordManager;

implementation

uses
  StrUtils, fpjson;

function TabLabel(const Text, Icon: string): Pointer;
var
  box: Pointer;
begin
  box := gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 4);
  gtk_box_pack_start(box, NewIcon(Icon, 16), False, False, 0);
  gtk_box_pack_start(box, NewLabel(Text), False, False, 0);
  gtk_widget_show_all(box);
  Result := box;
end;

function NewPage: Pointer;
begin
  Result := gtk_grid_new;
  gtk_grid_set_row_spacing(Result, 8);
  gtk_grid_set_column_spacing(Result, 12);
  SetMargins(Result, 16);
end;

function Check(Grid: Pointer; Row: Integer; const Caption: string; Value: Boolean): Pointer;
begin
  Result := gtk_check_button_new_with_label(PChar(Caption));
  gtk_toggle_button_set_active(Result, Value);
  gtk_grid_attach(Grid, Result, 0, Row, 3, 1);
end;

function Labeled(Grid: Pointer; Row: Integer; const Caption: string; W: Pointer): Pointer;
begin
  gtk_grid_attach(Grid, NewLabel(Caption, 1), 0, Row, 1, 1);
  gtk_grid_attach(Grid, W, 1, Row, 2, 1);
  Result := W;
end;

procedure PasswordsBtn(b: Pointer; data: gpointer); cdecl;
begin
  ShowPasswordManager;
end;

procedure ShortcutsBtn(b: Pointer; data: gpointer); cdecl;
begin
  MsgInfo('Keyboard shortcuts', 'See Help > Keyboard shortcuts.');
end;

procedure ConfigFolderBtn(b: Pointer; data: gpointer); cdecl;
begin
  OpenPath(ConfigDir);
end;

procedure SensitiveWith(check: Pointer; data: gpointer); cdecl;
begin
  gtk_widget_set_sensitive(data, gtk_toggle_button_get_active(check));
end;

procedure OpenLogDirBtn(b: Pointer; data: gpointer); cdecl;
var
  d: string;
begin
  d := Trim(EntryText(data));
  if d = '' then d := Settings.LogDir;
  ForceDirectories(d);
  OpenPath(d);
end;

procedure BrowseDir(b: Pointer; data: gpointer); cdecl;
var
  d, start: string;
begin
  start := EntryText(data);
  if not DirectoryExists(start) then start := HomeDir;
  if ChooseFolder('Choose a folder', start, d) then SetEntryText(data, d);
end;

procedure ShowSettingsDialog;
var
  dlg, area, nb, g, hb, b: Pointer;
  shellC, startDir, restore, localStart, confirm: Pointer;
  font, scheme, cursor, blink, scroll, copySel, pasteRight, bell, scrollOut, scrollKey, bksp, bold, words: Pointer;
  mobaPrompt, pasteWarn, activity, logOn, logDir, logStamps, reconnect, hilite, notify, notifyAfter: Pointer;
  x11, xinfo: Pointer;
  keepalive, compress, hostkey, sftpAuto, follow, monitor, dlDir: Pointer;
  skinC, showMenu, showTool, showSide, showStatus: Pointer;
  keyring, pwFile: Pointer;
  shells: TStringArray;
  i, r: Integer;
  disp: string;
begin
  dlg := gtk_dialog_new_with_buttons('LinXterm Configuration', MainWindowWidget,
    GTK_DIALOG_MODAL or GTK_DIALOG_DESTROY_WITH_PARENT, nil);
  gtk_window_set_default_size(dlg, 720, 620);
  area := gtk_dialog_get_content_area(dlg);
  nb := gtk_notebook_new;
  SetMargins(nb, 8);

  { ---- General ---- }
  g := NewPage;
  r := 0;
  shellC := gtk_combo_box_text_new;
  gtk_combo_box_text_append(shellC, '', PChar('<Login shell: ' + DefaultShellPath + '>'));
  shells := AvailableShells;
  for i := 0 to High(shells) do gtk_combo_box_text_append(shellC, PChar(shells[i]), PChar(shells[i]));
  if not gtk_combo_box_set_active_id(shellC, PChar(Settings.DefaultShell)) then gtk_combo_box_set_active(shellC, 0);
  Labeled(g, r, 'Local terminal shell', shellC);
  Inc(r);
  hb := gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 4);
  startDir := gtk_entry_new;
  SetEntryText(startDir, Settings.StartDir);
  gtk_entry_set_placeholder_text(startDir, PChar(HomeDir));
  gtk_widget_set_hexpand(startDir, True);
  gtk_box_pack_start(hb, startDir, True, True, 0);
  b := NewFlatIconButton('folder-open', 'Browse...', 16);
  Connect(b, 'clicked', @BrowseDir, startDir);
  gtk_box_pack_start(hb, b, False, False, 0);
  Labeled(g, r, 'Local terminal start folder', hb);
  Inc(r);
  restore := Check(g, r, 'Recover the previous sessions at startup', Settings.RestoreSessions);
  Inc(r);
  localStart := Check(g, r, 'Open a local terminal at startup', Settings.StartLocalTerminal);
  Inc(r);
  confirm := Check(g, r, 'Ask for confirmation before exiting with open sessions', Settings.ConfirmExit);
  Inc(r);
  hb := gtk_box_new(GTK_ORIENTATION_VERTICAL, 4);
  gtk_widget_set_halign(hb, GTK_ALIGN_START);
  gtk_widget_set_margin_top(hb, 12);
  b := NewIconButton('seahorse', 'LinXterm _passwords management', '', 16);
  Connect(b, 'clicked', @PasswordsBtn, nil);
  gtk_box_pack_start(hb, b, False, False, 0);
  b := NewIconButton('folder', 'Open the _configuration folder', '', 16);
  Connect(b, 'clicked', @ConfigFolderBtn, nil);
  gtk_box_pack_start(hb, b, False, False, 0);
  gtk_grid_attach(g, hb, 0, r, 3, 1);
  gtk_notebook_append_page(nb, g, TabLabel('General', 'preferences-system'));

  { ---- Terminal ---- }
  g := NewPage;
  r := 0;
  font := gtk_font_button_new_with_font(PChar(Settings.FontName));
  gtk_font_button_set_use_font(font, True);
  Labeled(g, r, 'Terminal font', font);
  Inc(r);
  scheme := gtk_combo_box_text_new;
  for i := 0 to ColorSchemeCount - 1 do
    gtk_combo_box_text_append(scheme, PChar(ColorSchemes[i].Name), PChar(ColorSchemes[i].Name));
  if not gtk_combo_box_set_active_id(scheme, PChar(Settings.ColorScheme)) then gtk_combo_box_set_active(scheme, 0);
  Labeled(g, r, 'Default terminal colors', scheme);
  Inc(r);
  cursor := gtk_combo_box_text_new;
  gtk_combo_box_text_append_text(cursor, 'Block');
  gtk_combo_box_text_append_text(cursor, 'I-beam');
  gtk_combo_box_text_append_text(cursor, 'Underline');
  gtk_combo_box_set_active(cursor, Settings.CursorShape);
  Labeled(g, r, 'Cursor type', cursor);
  Inc(r);
  scroll := gtk_spin_button_new_with_range(100, 1000000, 100);
  gtk_spin_button_set_value(scroll, Settings.Scrollback);
  Labeled(g, r, 'Scrollback lines', scroll);
  Inc(r);
  bell := gtk_combo_box_text_new;
  gtk_combo_box_text_append(bell, 'none', 'No sound');
  gtk_combo_box_text_append(bell, 'sound', 'System beep');
  if not gtk_combo_box_set_active_id(bell, PChar(Settings.Bell)) then gtk_combo_box_set_active(bell, 0);
  Labeled(g, r, 'Terminal bell', bell);
  Inc(r);
  words := gtk_entry_new;
  SetEntryText(words, Settings.WordChars);
  Labeled(g, r, 'Word characters (double-click)', words);
  Inc(r);
  hilite := Check(g, r, 'Syntax highlighting: errors in red, warnings in orange, success (OK) in green', Settings.SyntaxHighlight);
  gtk_widget_set_tooltip_text(hilite, 'Keywords of the terminal output are coloured (failed, denied, warning, deprecated, ok, success...). ' +
    'Text already coloured by a program and full-screen programs are left as they are. ' +
    'It can be changed per session (Terminal settings) or per tab (right-click menu).');
  Inc(r);
  blink := Check(g, r, 'Blinking cursor', Settings.CursorBlink);
  Inc(r);
  copySel := Check(g, r, 'Copy on select', Settings.CopyOnSelect);
  Inc(r);
  pasteRight := Check(g, r, 'Paste using right-click (Ctrl+right-click shows the menu)', Settings.PasteRightClick);
  Inc(r);
  scrollOut := Check(g, r, 'Scroll to the bottom on output', Settings.ScrollOnOutput);
  Inc(r);
  scrollKey := Check(g, r, 'Scroll to the bottom on key press', Settings.ScrollOnKeystroke);
  Inc(r);
  bksp := Check(g, r, 'Backspace sends ^H', Settings.BackspaceSendsCtrlH);
  Inc(r);
  bold := Check(g, r, 'Show bold text in bright colors', Settings.BoldIsBright);
  Inc(r);
  mobaPrompt := Check(g, r, 'MobaXterm prompt in local bash terminals ([date]  folder / [user.host] ➤)', Settings.MobaPrompt);
  Inc(r);
  pasteWarn := Check(g, r, 'Ask for confirmation before pasting several lines', Settings.PasteWarnMultiline);
  Inc(r);
  activity := Check(g, r, 'Highlight the tabs of terminals that print new output in the background', Settings.TabActivity);
  Inc(r);
  notify := Check(g, r, 'Desktop notifications when LinXterm is not in front: terminal bell, end of a long command', Settings.Notifications);
  gtk_widget_set_tooltip_text(notify, 'A click on the notification shows the tab. The end of the commands is known in the ' +
    'local bash terminals and, when "Follow terminal folder" is on, in the remote bash / zsh shells. ' +
    'Any program can also ring the bell, e.g. make; printf ''\a''');
  Inc(r);
  hb := gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 6);
  notifyAfter := gtk_spin_button_new_with_range(1, 86400, 5);
  gtk_spin_button_set_value(notifyAfter, Settings.NotifyAfter);
  gtk_box_pack_start(hb, notifyAfter, False, False, 0);
  gtk_box_pack_start(hb, NewLabel('seconds or more'), False, False, 0);
  Connect(notify, 'toggled', @SensitiveWith, hb);
  gtk_widget_set_sensitive(hb, Settings.Notifications);
  Labeled(g, r, 'Notify the commands that ran', hb);
  Inc(r);
  xinfo := NewMarkupLabel('<b>Session logs</b>', 0);
  gtk_widget_set_margin_top(xinfo, 10);
  gtk_grid_attach(g, xinfo, 0, r, 3, 1);
  Inc(r);
  logOn := Check(g, r, 'Log the output of every terminal session to a text file', Settings.LogTerminal);
  Inc(r);
  hb := gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 4);
  logDir := gtk_entry_new;
  SetEntryText(logDir, Settings.LogFolder);
  gtk_entry_set_placeholder_text(logDir, PChar(Settings.LogDir));
  gtk_widget_set_hexpand(logDir, True);
  gtk_box_pack_start(hb, logDir, True, True, 0);
  b := NewFlatIconButton('folder-open', 'Browse...', 16);
  Connect(b, 'clicked', @BrowseDir, logDir);
  gtk_box_pack_start(hb, b, False, False, 0);
  b := NewFlatIconButton('system-file-manager', 'Open the logs folder', 16);
  Connect(b, 'clicked', @OpenLogDirBtn, logDir);
  gtk_box_pack_start(hb, b, False, False, 0);
  Labeled(g, r, 'Logs folder', hb);
  Inc(r);
  logStamps := Check(g, r, 'Start each logged line with the date and time', Settings.LogTimestamps);
  Inc(r);
  xinfo := NewMarkupLabel('<small>Logs are plain text: colours and full-screen programs (vi, top, less...) are left out. ' +
    'Logging can also be enabled for a single session in its "Terminal settings".</small>', 0);
  gtk_label_set_line_wrap(xinfo, True);
  gtk_label_set_max_width_chars(xinfo, 80);
  gtk_grid_attach(g, xinfo, 0, r, 3, 1);
  gtk_notebook_append_page(nb, NewScrolled(g, GTK_POLICY_NEVER), TabLabel('Terminal', 'utilities-terminal'));

  { ---- X11 ---- }
  g := NewPage;
  disp := GetEnvironmentVariable('DISPLAY');
  xinfo := NewMarkupLabel('<b>X server</b>: ' + IfThen(disp <> '', 'running, DISPLAY=' + MarkupEscape(disp),
    'not available') + #10 + '<small>' + APP_NAME + ' uses the X server of your desktop (Xorg or Xwayland).</small>', 0);
  gtk_label_set_line_wrap(xinfo, True);
  gtk_label_set_max_width_chars(xinfo, 70);
  gtk_grid_attach(g, xinfo, 0, 0, 3, 1);
  x11 := Check(g, 1, 'Enable X11-forwarding for new SSH sessions', Settings.X11Default);
  gtk_notebook_append_page(nb, g, TabLabel('X11', 'xorg'));

  { ---- SSH ---- }
  g := NewPage;
  r := 0;
  keepalive := gtk_spin_button_new_with_range(0, 3600, 5);
  gtk_spin_button_set_value(keepalive, Settings.KeepAlive);
  Labeled(g, r, 'SSH keepalive (seconds, 0 = off)', keepalive);
  Inc(r);
  hostkey := gtk_combo_box_text_new;
  gtk_combo_box_text_append(hostkey, 'ask', 'Ask for unknown host keys');
  gtk_combo_box_text_append(hostkey, 'accept-new', 'Accept new host keys automatically');
  gtk_combo_box_text_append(hostkey, 'no', 'Never check host keys (insecure)');
  if not gtk_combo_box_set_active_id(hostkey, PChar(Settings.HostKeyPolicy)) then gtk_combo_box_set_active(hostkey, 0);
  Labeled(g, r, 'Host key checking', hostkey);
  Inc(r);
  hb := gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 4);
  dlDir := gtk_entry_new;
  SetEntryText(dlDir, Settings.DownloadFolder);
  gtk_entry_set_placeholder_text(dlDir, PChar(DownloadDir));
  gtk_widget_set_hexpand(dlDir, True);
  gtk_box_pack_start(hb, dlDir, True, True, 0);
  b := NewFlatIconButton('folder-open', 'Browse...', 16);
  Connect(b, 'clicked', @BrowseDir, dlDir);
  gtk_box_pack_start(hb, b, False, False, 0);
  Labeled(g, r, 'SFTP download folder', hb);
  Inc(r);
  compress := Check(g, r, 'Enable SSH compression for new sessions', Settings.CompressionDefault);
  Inc(r);
  sftpAuto := Check(g, r, 'Automatically switch to the SSH-browser tab after login', Settings.SftpBrowserAuto);
  Inc(r);
  follow := Check(g, r, 'SSH-browser follows the terminal folder (when the shell reports it)', Settings.FollowTerminalFolder);
  Inc(r);
  monitor := Check(g, r, 'Remote monitoring bar (CPU, RAM, network, disk) for SSH sessions', Settings.RemoteMonitoring);
  Inc(r);
  reconnect := Check(g, r, 'Reconnect automatically when an SSH connection is lost', Settings.AutoReconnect);
  gtk_notebook_append_page(nb, g, TabLabel('SSH', 'putty'));

  { ---- Display ---- }
  g := NewPage;
  r := 0;
  skinC := gtk_combo_box_text_new;
  gtk_combo_box_text_append(skinC, 'light', 'Light (classic)');
  gtk_combo_box_text_append(skinC, 'dark', 'Dark');
  gtk_combo_box_text_append(skinC, 'system', 'Automatic (follows the light / dark mode of the desktop)');
  if not gtk_combo_box_set_active_id(skinC, PChar(Settings.Skin)) then gtk_combo_box_set_active(skinC, 0);
  Labeled(g, r, 'Skin', skinC);
  Inc(r);
  showMenu := Check(g, r, 'Show the menu bar', Settings.ShowMenubar);
  Inc(r);
  showTool := Check(g, r, 'Show the toolbar', Settings.ShowToolbar);
  Inc(r);
  showSide := Check(g, r, 'Show the side panel', Settings.ShowSidebar);
  Inc(r);
  showStatus := Check(g, r, 'Show the status bar', Settings.ShowStatusbar);
  gtk_notebook_append_page(nb, g, TabLabel('Display', 'preferences-desktop-display'));

  { ---- Misc ---- }
  g := NewPage;
  keyring := Check(g, 0, 'Store passwords in the GNOME keyring (libsecret, encrypted with your session password)', Settings.UseKeyring);
  pwFile := Check(g, 1, 'When the keyring is not available, keep the passwords in a file (not recommended)', Settings.PasswordFile);
  xinfo := NewMarkupLabel('<small>That file (' + MarkupEscape(ConfigDir) + '/passwords.json, readable by your user only) ' +
    'is only <b>obfuscated, not encrypted</b>. Without keyring and without this option, passwords are never written ' +
    'to disk: they are asked at each connection. Passwords found in that file move to the keyring as soon as it is ' +
    'available.</small>', 0);
  gtk_label_set_line_wrap(xinfo, True);
  gtk_label_set_max_width_chars(xinfo, 80);
  gtk_grid_attach(g, xinfo, 0, 2, 3, 1);
  gtk_notebook_append_page(nb, g, TabLabel('Misc', 'applications-utilities'));

  gtk_box_pack_start(area, nb, True, True, 0);
  hb := gtk_dialog_add_button(dlg, '_Cancel', GTK_RESPONSE_CANCEL);
  gtk_button_set_image(hb, NewIcon('lx-cancel', 16));
  gtk_button_set_always_show_image(hb, True);
  hb := gtk_dialog_add_button(dlg, '_OK', GTK_RESPONSE_OK);
  gtk_button_set_image(hb, NewIcon('lx-check', 16));
  gtk_button_set_always_show_image(hb, True);
  gtk_dialog_set_default_response(dlg, GTK_RESPONSE_OK);
  gtk_widget_show_all(dlg);
  if gtk_dialog_run(dlg) = GTK_RESPONSE_OK then
  begin
    Settings.DefaultShell := CStr(gtk_combo_box_get_active_id(shellC));
    Settings.StartDir := Trim(EntryText(startDir));
    Settings.RestoreSessions := gtk_toggle_button_get_active(restore);
    Settings.StartLocalTerminal := gtk_toggle_button_get_active(localStart);
    Settings.ConfirmExit := gtk_toggle_button_get_active(confirm);
    Settings.FontName := TakeStr(gtk_font_chooser_get_font(font));
    Settings.ColorScheme := CStr(gtk_combo_box_get_active_id(scheme));
    Settings.CursorShape := gtk_combo_box_get_active(cursor);
    gtk_spin_button_update(scroll);
    Settings.Scrollback := gtk_spin_button_get_value_as_int(scroll);
    Settings.Bell := CStr(gtk_combo_box_get_active_id(bell));
    Settings.WordChars := EntryText(words);
    Settings.CursorBlink := gtk_toggle_button_get_active(blink);
    Settings.CopyOnSelect := gtk_toggle_button_get_active(copySel);
    Settings.PasteRightClick := gtk_toggle_button_get_active(pasteRight);
    Settings.ScrollOnOutput := gtk_toggle_button_get_active(scrollOut);
    Settings.ScrollOnKeystroke := gtk_toggle_button_get_active(scrollKey);
    Settings.BackspaceSendsCtrlH := gtk_toggle_button_get_active(bksp);
    Settings.BoldIsBright := gtk_toggle_button_get_active(bold);
    Settings.MobaPrompt := gtk_toggle_button_get_active(mobaPrompt);
    Settings.PasteWarnMultiline := gtk_toggle_button_get_active(pasteWarn);
    Settings.SyntaxHighlight := gtk_toggle_button_get_active(hilite);
    Settings.Notifications := gtk_toggle_button_get_active(notify);
    gtk_spin_button_update(notifyAfter);
    Settings.NotifyAfter := gtk_spin_button_get_value_as_int(notifyAfter);
    Settings.TabActivity := gtk_toggle_button_get_active(activity);
    Settings.LogTerminal := gtk_toggle_button_get_active(logOn);
    Settings.LogFolder := Trim(EntryText(logDir));
    Settings.LogTimestamps := gtk_toggle_button_get_active(logStamps);
    Settings.AutoReconnect := gtk_toggle_button_get_active(reconnect);
    Settings.X11Default := gtk_toggle_button_get_active(x11);
    gtk_spin_button_update(keepalive);
    Settings.KeepAlive := gtk_spin_button_get_value_as_int(keepalive);
    Settings.HostKeyPolicy := CStr(gtk_combo_box_get_active_id(hostkey));
    Settings.DownloadFolder := Trim(EntryText(dlDir));
    Settings.CompressionDefault := gtk_toggle_button_get_active(compress);
    Settings.SftpBrowserAuto := gtk_toggle_button_get_active(sftpAuto);
    Settings.FollowTerminalFolder := gtk_toggle_button_get_active(follow);
    Settings.RemoteMonitoring := gtk_toggle_button_get_active(monitor);
    Settings.Skin := CStr(gtk_combo_box_get_active_id(skinC));
    Settings.ShowMenubar := gtk_toggle_button_get_active(showMenu);
    Settings.ShowToolbar := gtk_toggle_button_get_active(showTool);
    Settings.ShowSidebar := gtk_toggle_button_get_active(showSide);
    Settings.ShowStatusbar := gtk_toggle_button_get_active(showStatus);
    Settings.UseKeyring := gtk_toggle_button_get_active(keyring);
    Settings.PasswordFile := gtk_toggle_button_get_active(pwFile);
    if Settings.Scrollback < 100 then Settings.Scrollback := 100;
    Settings.Save;
    App.SettingsChanged;
  end;
  gtk_widget_destroy(dlg);
end;

{ ---------------------------------------------------------------- passwords }

type
  TPwUi = class
    Win, Store, View: Pointer;
    procedure Refresh;
  end;

var
  PwUi: TPwUi = nil;

function DescribeKey(const Key: string; out Kind: string): string;
var
  s: TSession;
  d: TJSONData;
  a: TJSONArray;
  i: Integer;
begin
  Result := Key;
  Kind := '';
  if Copy(Key, 1, 8) = 'session:' then
  begin
    s := Store.FindById(Copy(Key, 9, MaxInt));
    if s <> nil then
    begin
      Kind := SessionKindNames[s.Kind] + ' session';
      Result := s.DisplayName + '  (' + s.Target + ')';
    end
    else
      Kind := 'deleted session';
  end
  else if Copy(Key, 1, 7) = 'tunnel:' then
  begin
    Kind := 'SSH tunnel';
    d := LoadJsonFile(ConfigDir + '/tunnels.json');
    if (d <> nil) and (d.JSONType = jtArray) then
    begin
      a := TJSONArray(d);
      for i := 0 to a.Count - 1 do
        if (a[i].JSONType = jtObject) and (JStr(TJSONObject(a[i]), 'id', '') = Copy(Key, 8, MaxInt)) then
          Result := JStr(TJSONObject(a[i]), 'name', Key);
    end;
    d.Free;
  end
  else if Copy(Key, 1, 7) = 'server:' then
  begin
    Kind := 'Server';
    Result := Copy(Key, 8, MaxInt) + ' server';
  end;
end;

procedure TPwUi.Refresh;
var
  keys: TStringArray;
  i: Integer;
  it: TGtkTreeIter;
  kind, desc: string;
begin
  gtk_list_store_clear(Store);
  keys := ListStoredPasswordKeys;
  for i := 0 to High(keys) do
  begin
    desc := DescribeKey(keys[i], kind);
    gtk_list_store_append(Store, @it);
    gtk_list_store_set(Store, @it, 0, PChar(kind), 1, PChar(desc), 2, PChar('••••••••'), 3, PChar(keys[i]), -1);
  end;
end;

procedure PwDelete(b: Pointer; data: gpointer); cdecl;
var
  it: TGtkTreeIter;
  model: Pointer;
  p: PChar;
  key: string;
  s: TSession;
begin
  if not gtk_tree_selection_get_selected(gtk_tree_view_get_selection(PwUi.View), @model, @it) then Exit;
  p := nil;
  gtk_tree_model_get(model, @it, 3, @p, -1);
  key := TakeStr(p);
  if not AskYesNo('Delete this saved password?', '') then Exit;
  ForgetPassword(key);
  if Copy(key, 1, 8) = 'session:' then
  begin
    s := Store.FindById(Copy(key, 9, MaxInt));
    if s <> nil then
    begin
      s.HasPassword := False;
      Store.Save;
    end;
  end;
  PwUi.Refresh;
end;

procedure PwDeleteAll(b: Pointer; data: gpointer); cdecl;
var
  keys: TStringArray;
  i: Integer;
begin
  if not AskYesNo('Delete every saved password?', 'Sessions will ask for their password again.') then Exit;
  keys := ListStoredPasswordKeys;
  for i := 0 to High(keys) do ForgetPassword(keys[i]);
  for i := 0 to Store.Sessions.Count - 1 do Store.Sessions[i].HasPassword := False;
  Store.Save;
  PwUi.Refresh;
end;

function PwDeleteEvent(w: Pointer; ev: Pointer; data: gpointer): gboolean; cdecl;
begin
  gtk_widget_hide(w);
  Result := True;
end;

procedure ShowPasswordManager;
var
  vbox, hb, b, col, cell: Pointer;
  types: array[0..3] of GType;
  i: Integer;
  titles: array[0..2] of string = ('Type', 'Account', 'Password');
begin
  if PwUi = nil then
  begin
    PwUi := TPwUi.Create;
    PwUi.Win := gtk_window_new(GTK_WINDOW_TOPLEVEL);
    gtk_window_set_title(PwUi.Win, 'LinXterm passwords management');
    gtk_window_set_default_size(PwUi.Win, 640, 400);
    gtk_window_set_icon(PwUi.Win, IconPixbuf('dialog-password', 64));
    gtk_window_set_transient_for(PwUi.Win, MainWindowWidget);
    gtk_window_set_modal(PwUi.Win, True);
    vbox := gtk_box_new(GTK_ORIENTATION_VERTICAL, 8);
    SetMargins(vbox, 12);
    gtk_box_pack_start(vbox, NewMarkupLabel('Saved passwords are stored in the <b>GNOME keyring</b> ' +
      '(or, when the keyring is not available, obfuscated in a configuration file readable by your user only).', 0), False, False, 0);
    for i := 0 to 3 do types[i] := G_TYPE_STRING;
    PwUi.Store := gtk_list_store_newv(4, @types[0]);
    PwUi.View := gtk_tree_view_new_with_model(PwUi.Store);
    g_object_unref(PwUi.Store);
    for i := 0 to 2 do
    begin
      col := gtk_tree_view_column_new;
      gtk_tree_view_column_set_title(col, PChar(titles[i]));
      cell := gtk_cell_renderer_text_new;
      gtk_tree_view_column_pack_start(col, cell, True);
      gtk_tree_view_column_add_attribute(col, cell, 'text', i);
      gtk_tree_view_column_set_resizable(col, True);
      gtk_tree_view_append_column(PwUi.View, col);
    end;
    gtk_box_pack_start(vbox, NewScrolled(PwUi.View), True, True, 0);
    hb := gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
    b := NewIconButton('lx-cancel', '_Delete', '', 16);
    Connect(b, 'clicked', @PwDelete, nil);
    gtk_box_pack_start(hb, b, False, False, 0);
    b := NewIconButton('edit-clear-all', 'Delete _all', '', 16);
    Connect(b, 'clicked', @PwDeleteAll, nil);
    gtk_box_pack_start(hb, b, False, False, 0);
    gtk_box_pack_start(vbox, hb, False, False, 0);
    gtk_container_add(PwUi.Win, vbox);
    Connect(PwUi.Win, 'delete-event', @PwDeleteEvent, nil);
  end;
  PwUi.Refresh;
  gtk_widget_show_all(PwUi.Win);
  gtk_window_present(PwUi.Win);
end;

initialization
  ShowSettingsProc := @ShowSettingsDialog;
  ShowPasswordsProc := @ShowPasswordManager;

end.

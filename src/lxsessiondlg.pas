{ LinXterm - "Session settings" dialog (MobaXterm-style session editor). }
unit lxsessiondlg;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, lxgtk, lxutil, lxconfig;

{ Edits S in place. Returns True when the user pressed OK.
  When IsNew is True the dialog starts on "Choose a session type...". }
function EditSessionDialog(Sess: TSession; IsNew: Boolean): Boolean;
procedure CreateDesktopShortcut(Sess: TSession);
function DetectSerialPorts: TStringArray;

var
  MacroNamesProvider: function: TStringArray = nil;

implementation

uses
  BaseUnix, lxtabs, lxterminal;

type
  TKindPage = record
    Root: Pointer;
    Host, UserCheck, User, Port, Password, SavePw: Pointer;
    X11, Compression, Agent, RemoteCmd, StayCmd, Browser, FollowPath, KeyCheck, KeyFile, Macro: Pointer;
    FontCheck, Font, Scheme, LogCheck, Hilite: Pointer;
    JumpCheck, JumpHost, JumpUser, JumpPort, KeepCheck, KeepAlive, Extra: Pointer;
    Domain, Resolution, Clip, HomeDrive, Sound, RdpExtra: Pointer;
    ViewOnly, Scaling: Pointer;
    Passive: Pointer;
    Device, Baud, DataBits, StopBits, Parity, Flow: Pointer;
    ShellCombo, StartDir, Command: Pointer;
    Url: Pointer;
    Name, Folder, Comment, Shortcut, TabColor: Pointer;
  end;

  TSessionDialog = class
  public
    Dlg: Pointer;
    Stack: Pointer;
    Buttons: array[TSessionKind] of Pointer;
    NoneRadio: Pointer;
    Pages: array[TSessionKind] of TKindPage;
    Current: TSessionKind;
    HasKind: Boolean;
    Sess: TSession;
    procedure Build(IsNew: Boolean);
    procedure SelectKind(K: TSessionKind);
    function BuildPage(K: TSessionKind): Pointer;
    procedure LoadValues(K: TSessionKind; Src: TSession);
    function Validate: Boolean;
    procedure StoreValues;
  end;

const
  TabColorDots: array[0..TabColorCount - 1] of string =
    ('', '🔴', '🟠', '🟡', '🟢', '🔵', '🟣', '⚫');
  ResolutionIds: array[0..8] of string =
    ('dynamic', 'fullscreen', '1920x1080', '1680x1050', '1600x900', '1366x768', '1280x1024', '1280x720', '1024x768');
  ResolutionLabels: array[0..8] of string =
    ('Fit to window (dynamic)', 'Fullscreen', '1920 x 1080', '1680 x 1050', '1600 x 900', '1366 x 768',
     '1280 x 1024', '1280 x 720', '1024 x 768');
  BaudRates: array[0..11] of string =
    ('300', '1200', '2400', '4800', '9600', '19200', '38400', '57600', '115200', '230400', '460800', '921600');

function DetectSerialPorts: TStringArray;
var
  sr: TSearchRec;
  n: Integer;
  lst: TStringList;
  procedure Scan(const Mask, Dir: string);
  begin
    if FindFirst(Mask, faAnyFile, sr) = 0 then
    begin
      repeat
        lst.Add(Dir + sr.Name);
      until FindNext(sr) <> 0;
      FindClose(sr);
    end;
  end;
begin
  Result := nil;
  lst := TStringList.Create;
  try
    Scan('/dev/serial/by-id/*', '/dev/serial/by-id/');
    Scan('/dev/ttyUSB*', '/dev/');
    Scan('/dev/ttyACM*', '/dev/');
    Scan('/dev/ttyAMA*', '/dev/');
    for n := 0 to 3 do
      if FileExists('/dev/ttyS' + IntToStr(n)) then lst.Add('/dev/ttyS' + IntToStr(n));
    SetLength(Result, lst.Count);
    for n := 0 to lst.Count - 1 do
      Result[n] := lst[n];
  finally
    lst.Free;
  end;
end;

procedure CreateDesktopShortcut(Sess: TSession);
var
  desk, fn, txt, nm, o: string;
  i: Integer;
begin
  desk := CStr(g_get_user_special_dir(0));  { G_USER_DIRECTORY_DESKTOP }
  if (desk = '') or not DirectoryExists(desk) then desk := HomeDir + '/Desktop';
  if not DirectoryExists(desk) then ForceDirectories(desk);
  nm := Sess.DisplayName;
  { one line only: a name must not add keys (Exec=...) to the launcher }
  for i := 1 to Length(nm) do
    if nm[i] < ' ' then nm[i] := ' ';
  fn := '';
  for i := 1 to Length(nm) do
    if nm[i] in ['A'..'Z', 'a'..'z', '0'..'9', '-', '_', '.'] then fn := fn + nm[i] else fn := fn + '_';
  fn := desk + '/linxterm-' + fn + '.desktop';
  txt := '[Desktop Entry]'#10 +
    'Type=Application'#10 +
    'Name=' + nm + #10 +
    'Comment=' + SessionKindNames[Sess.Kind] + ' session (' + APP_NAME + ')'#10 +
    'Exec="' + AppDir + '/bin/linxterm" --session ' + Sess.Id + #10 +
    'Icon=' + AppDir + '/icons/linxterm.svg'#10 +
    'Terminal=false'#10 +
    'Categories=Network;'#10;
  if WriteFileText(fn, txt) then
  begin
    fpChmod(fn, &755);
    RunCapture(['gio', 'set', fn, 'metadata::trusted', 'true'], o);
    MsgInfo('Desktop shortcut created', fn);
  end
  else
    MsgError('Unable to create the desktop shortcut', fn);
end;

{ ---------------------------------------------------------------- callbacks }

procedure KindToggled(button: Pointer; data: gpointer); cdecl;
var
  d: TSessionDialog;
  k: TSessionKind;
begin
  if not gtk_toggle_button_get_active(button) then Exit;
  d := TSessionDialog(data);
  k := TSessionKind(PtrInt(g_object_get_data(button, 'kind')));
  d.SelectKind(k);
end;

procedure ButtonResponse(button: Pointer; data: gpointer); cdecl;
begin
  gtk_dialog_response(data, gint(PtrInt(g_object_get_data(button, 'resp'))));
end;

procedure CheckSensitivity(check: Pointer; data: gpointer); cdecl;
begin
  gtk_widget_set_sensitive(data, gtk_toggle_button_get_active(check));
end;

procedure BrowseKeyFile(button: Pointer; data: gpointer); cdecl;
var
  fn: string;
begin
  if ChooseOpenFile('Choose a private key', HomeDir + '/.ssh', fn) then
    SetEntryText(data, fn);
end;

procedure BrowseFolder(button: Pointer; data: gpointer); cdecl;
var
  fn, start: string;
begin
  start := EntryText(data);
  if not DirectoryExists(start) then start := HomeDir;
  if ChooseFolder('Choose a folder', start, fn) then
    SetEntryText(data, fn);
end;

{ ---------------------------------------------------------------- helpers }

function Row(Grid: Pointer; R: Integer; const Caption: string; W: Pointer; Span: Integer = 1): Pointer;
var
  l: Pointer;
begin
  l := NewLabel(Caption, 1);
  gtk_grid_attach(Grid, l, 0, R, 1, 1);
  gtk_widget_set_hexpand(W, Span > 1);
  gtk_grid_attach(Grid, W, 1, R, Span, 1);
  Result := W;
end;

function NewGrid: Pointer;
begin
  Result := gtk_grid_new;
  gtk_grid_set_row_spacing(Result, 8);
  gtk_grid_set_column_spacing(Result, 10);
  SetMargins(Result, 12);
end;

function NewFrame(const Caption: string; Child: Pointer): Pointer;
var
  lbl: Pointer;
begin
  Result := gtk_frame_new(nil);
  lbl := NewMarkupLabel('<b>' + MarkupEscape(Caption) + '</b>');
  g_object_set(Result, 'label-widget', lbl, nil);
  AddClass(Result, 'lx-group');
  gtk_container_add(Result, Child);
end;

function NewEntry(Width: Integer; const Placeholder: string = ''): Pointer;
begin
  Result := gtk_entry_new;
  gtk_entry_set_width_chars(Result, Width);
  if Placeholder <> '' then
    gtk_entry_set_placeholder_text(Result, PChar(Placeholder));
  gtk_entry_set_activates_default(Result, True);
end;

function NewSpin(Min, Max, Value: Integer): Pointer;
begin
  Result := gtk_spin_button_new_with_range(Min, Max, 1);
  gtk_spin_button_set_value(Result, Value);
  gtk_spin_button_set_digits(Result, 0);
end;

function NewCheck(const Caption: string; Active: Boolean): Pointer;
begin
  Result := gtk_check_button_new_with_label(PChar(Caption));
  gtk_toggle_button_set_active(Result, Active);
end;

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

function ComboWithItems(const Items: array of string; WithEntry: Boolean = False): Pointer;
var
  s: string;
begin
  if WithEntry then
    Result := gtk_combo_box_text_new_with_entry
  else
    Result := gtk_combo_box_text_new;
  for s in Items do
    gtk_combo_box_text_append_text(Result, PChar(s));
end;

procedure SetComboText(Combo: Pointer; const Value: string);
var
  entry: Pointer;
begin
  entry := gtk_bin_get_child(Combo);
  if entry <> nil then
    gtk_entry_set_text(entry, PChar(Value));
end;

function ComboEntryText(Combo: Pointer): string;
var
  entry: Pointer;
begin
  entry := gtk_bin_get_child(Combo);
  if entry <> nil then
    Result := Trim(EntryText(entry))
  else
    Result := ComboText(Combo);
end;

{ ---------------------------------------------------------------- dialog }

procedure TSessionDialog.Build(IsNew: Boolean);
var
  area, vbox, row, btn, prev, placeholder, ph, okb, cancelb, actionArea: Pointer;
  k: TSessionKind;
begin
  Dlg := gtk_dialog_new_with_buttons('Session settings', MainWindowWidget,
    GTK_DIALOG_MODAL or GTK_DIALOG_DESTROY_WITH_PARENT, nil);
  AddClass(Dlg, 'lx-session-dialog');
  gtk_window_set_default_size(Dlg, 900, 600);
  area := gtk_dialog_get_content_area(Dlg);
  vbox := gtk_box_new(GTK_ORIENTATION_VERTICAL, 6);
  SetMargins(vbox, 6);
  gtk_box_pack_start(area, vbox, True, True, 0);

  { row of session types }
  row := gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 2);
  gtk_widget_set_halign(row, GTK_ALIGN_CENTER);
  AddClass(row, 'lx-kind-row');
  { hidden group leader so that no visible type is pre-selected }
  NoneRadio := gtk_radio_button_new_with_label(nil, 'none');
  g_object_ref_sink(NoneRadio);
  prev := NoneRadio;
  for k := Low(TSessionKind) to High(TSessionKind) do
  begin
    btn := gtk_radio_button_new_with_label_from_widget(prev, PChar(SessionKindNames[k]));
    gtk_toggle_button_set_mode(btn, False);
    gtk_button_set_image(btn, NewIcon(SessionKindIcons[k], 32));
    gtk_button_set_image_position(btn, GTK_POS_TOP);
    gtk_button_set_always_show_image(btn, True);
    gtk_button_set_relief(btn, GTK_RELIEF_NONE);
    AddClass(btn, 'lx-kind-button');
    g_object_set_data(btn, 'kind', Pointer(PtrInt(Ord(k))));
    gtk_box_pack_start(row, btn, False, False, 0);
    Buttons[k] := btn;
    prev := btn;
  end;
  gtk_box_pack_start(vbox, row, False, False, 4);
  gtk_box_pack_start(vbox, gtk_separator_new(GTK_ORIENTATION_HORIZONTAL), False, False, 0);

  Stack := gtk_stack_new;
  gtk_stack_set_homogeneous(Stack, False);
  placeholder := gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 18);
  gtk_widget_set_halign(placeholder, GTK_ALIGN_CENTER);
  gtk_widget_set_valign(placeholder, GTK_ALIGN_CENTER);
  gtk_box_pack_start(placeholder, NewIcon('preferences-desktop-remote-desktop', 96), False, False, 0);
  ph := NewMarkupLabel('<span size="large" foreground="#9a9a9a">Choose a session type...</span>');
  gtk_box_pack_start(placeholder, ph, False, False, 0);
  gtk_stack_add_named(Stack, placeholder, 'none');
  for k := Low(TSessionKind) to High(TSessionKind) do
  begin
    Pages[k].Root := BuildPage(k);
    gtk_stack_add_named(Stack, Pages[k].Root, PChar(SessionKindIds[k]));
  end;
  gtk_box_pack_start(vbox, Stack, True, True, 0);

  actionArea := gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 60);
  gtk_widget_set_halign(actionArea, GTK_ALIGN_CENTER);
  gtk_widget_set_margin_bottom(actionArea, 8);
  gtk_widget_set_margin_top(actionArea, 6);
  okb := NewIconButton('lx-check', '_OK', '', 16);
  gtk_widget_set_size_request(okb, 110, -1);
  cancelb := NewIconButton('lx-cancel', '_Cancel', '', 16);
  gtk_widget_set_size_request(cancelb, 110, -1);
  gtk_box_pack_start(actionArea, okb, False, False, 0);
  gtk_box_pack_start(actionArea, cancelb, False, False, 0);
  gtk_box_pack_start(vbox, actionArea, False, False, 0);
  { wire the custom buttons to dialog responses }
  g_object_set_data(okb, 'resp', Pointer(PtrInt(GTK_RESPONSE_OK)));
  g_object_set_data(cancelb, 'resp', Pointer(PtrInt(GTK_RESPONSE_CANCEL)));
  Connect(okb, 'clicked', @ButtonResponse, Dlg);
  Connect(cancelb, 'clicked', @ButtonResponse, Dlg);

  for k := Low(TSessionKind) to High(TSessionKind) do
    Connect(Buttons[k], 'clicked', @KindToggled, Self);

  HasKind := not IsNew;
  if IsNew then
  begin
    { no type selected yet: show the placeholder }
    gtk_stack_set_visible_child_name(Stack, 'none');
    gtk_widget_show_all(Dlg);
    gtk_stack_set_visible_child_name(Stack, 'none');
  end
  else
  begin
    gtk_widget_show_all(Dlg);
  end;
end;

procedure TSessionDialog.SelectKind(K: TSessionKind);
begin
  Current := K;
  HasKind := True;
  gtk_stack_set_visible_child_name(Stack, PChar(SessionKindIds[K]));
  if gtk_widget_get_visible(Pages[K].Root) then ;
  if Pages[K].Host <> nil then
    gtk_widget_grab_focus(Pages[K].Host)
  else if Pages[K].Device <> nil then
    gtk_widget_grab_focus(Pages[K].Device)
  else if Pages[K].Url <> nil then
    gtk_widget_grab_focus(Pages[K].Url);
end;

function TSessionDialog.BuildPage(K: TSessionKind): Pointer;
var
  root, basic, grid, nb, g2, hb, b: Pointer;
  p: ^TKindPage;
  i, r: Integer;
  names: TStringArray;
  shells: TStringArray;
  basicTitle: string;
begin
  p := @Pages[K];
  root := gtk_box_new(GTK_ORIENTATION_VERTICAL, 8);
  gtk_widget_set_margin_start(root, 8);
  gtk_widget_set_margin_end(root, 8);
  basicTitle := 'Basic ' + SessionKindNames[K] + ' settings';

  { ---- basic settings ---- }
  grid := gtk_grid_new;
  gtk_grid_set_row_spacing(grid, 8);
  gtk_grid_set_column_spacing(grid, 8);
  SetMargins(grid, 12);
  case K of
    skSSH, skTelnet, skRDP, skVNC, skFTP, skSFTP, skMosh:
      begin
        gtk_grid_attach(grid, NewMarkupLabel('Remote host <span foreground="red">*</span>', 1), 0, 0, 1, 1);
        p^.Host := NewEntry(24, 'hostname or IP');
        gtk_grid_attach(grid, p^.Host, 1, 0, 1, 1);
        if K <> skVNC then
        begin
          p^.UserCheck := NewCheck('Specify username', False);
          gtk_grid_attach(grid, p^.UserCheck, 2, 0, 1, 1);
          p^.User := NewEntry(14);
          gtk_widget_set_sensitive(p^.User, False);
          Connect(p^.UserCheck, 'toggled', @CheckSensitivity, p^.User);
          gtk_grid_attach(grid, p^.User, 3, 0, 1, 1);
        end;
        gtk_grid_attach(grid, NewLabel('Port', 1), 4, 0, 1, 1);
        p^.Port := NewSpin(1, 65535, SessionKindDefaultPorts[K]);
        gtk_grid_attach(grid, p^.Port, 5, 0, 1, 1);
        if K <> skMosh then
        begin
          gtk_grid_attach(grid, NewLabel('Password', 1), 0, 1, 1, 1);
          p^.Password := NewEntry(24, 'optional');
          gtk_entry_set_visibility(p^.Password, False);
          gtk_entry_set_input_purpose(p^.Password, GTK_INPUT_PURPOSE_PASSWORD);
          gtk_grid_attach(grid, p^.Password, 1, 1, 1, 1);
          p^.SavePw := NewCheck('Save password', True);
          gtk_widget_set_tooltip_text(p^.SavePw, 'Stored in the GNOME keyring (or in a private file when it is not available)');
          gtk_grid_attach(grid, p^.SavePw, 2, 1, 3, 1);
        end;
      end;
    skSerial:
      begin
        gtk_grid_attach(grid, NewMarkupLabel('Serial port <span foreground="red">*</span>', 1), 0, 0, 1, 1);
        p^.Device := ComboWithItems(DetectSerialPorts, True);
        gtk_widget_set_size_request(p^.Device, 280, -1);
        gtk_grid_attach(grid, p^.Device, 1, 0, 1, 1);
        gtk_grid_attach(grid, NewLabel('Speed (bps)', 1), 2, 0, 1, 1);
        p^.Baud := ComboWithItems(BaudRates, True);
        gtk_grid_attach(grid, p^.Baud, 3, 0, 1, 1);
      end;
    skFile:
      begin
        gtk_grid_attach(grid, NewMarkupLabel('Folder <span foreground="red">*</span>', 1), 0, 0, 1, 1);
        p^.StartDir := NewEntry(40);
        gtk_widget_set_hexpand(p^.StartDir, True);
        gtk_grid_attach(grid, p^.StartDir, 1, 0, 1, 1);
        b := NewIconButton('folder-open', '', 'Browse...', 16);
        Connect(b, 'clicked', @BrowseFolder, p^.StartDir);
        gtk_grid_attach(grid, b, 2, 0, 1, 1);
      end;
    skShell:
      begin
        gtk_grid_attach(grid, NewLabel('Terminal shell', 1), 0, 0, 1, 1);
        shells := AvailableShells;
        p^.ShellCombo := gtk_combo_box_text_new;
        gtk_combo_box_text_append(p^.ShellCombo, '', '<Default shell>');
        for i := 0 to High(shells) do
          gtk_combo_box_text_append(p^.ShellCombo, PChar(shells[i]), PChar(shells[i]));
        gtk_combo_box_set_active(p^.ShellCombo, 0);
        gtk_grid_attach(grid, p^.ShellCombo, 1, 0, 1, 1);
        gtk_grid_attach(grid, NewLabel('Startup directory', 1), 2, 0, 1, 1);
        p^.StartDir := NewEntry(26, HomeDir);
        gtk_grid_attach(grid, p^.StartDir, 3, 0, 1, 1);
        b := NewIconButton('folder-open', '', 'Browse...', 16);
        Connect(b, 'clicked', @BrowseFolder, p^.StartDir);
        gtk_grid_attach(grid, b, 4, 0, 1, 1);
      end;
    skBrowser:
      begin
        gtk_grid_attach(grid, NewMarkupLabel('Website URL <span foreground="red">*</span>', 1), 0, 0, 1, 1);
        p^.Url := NewEntry(50, 'https://');
        gtk_widget_set_hexpand(p^.Url, True);
        gtk_grid_attach(grid, p^.Url, 1, 0, 1, 1);
      end;
  end;
  basic := NewFrame(basicTitle, grid);
  gtk_box_pack_start(root, basic, False, False, 4);

  { ---- notebook with advanced settings ---- }
  nb := gtk_notebook_new;
  AddClass(nb, 'lx-settings-tabs');

  case K of
    skSSH:
      begin
        g2 := NewGrid;
        p^.X11 := NewCheck('X11-Forwarding', True);
        gtk_grid_attach(g2, p^.X11, 0, 0, 1, 1);
        p^.Compression := NewCheck('Compression', False);
        gtk_grid_attach(g2, p^.Compression, 1, 0, 1, 1);
        p^.Agent := NewCheck('Forward SSH agent', False);
        gtk_grid_attach(g2, p^.Agent, 2, 0, 1, 1);
        gtk_grid_attach(g2, NewLabel('Execute command', 1), 0, 1, 1, 1);
        p^.RemoteCmd := NewEntry(36);
        gtk_grid_attach(g2, p^.RemoteCmd, 1, 1, 2, 1);
        p^.StayCmd := NewCheck('Do not exit after command ends', False);
        gtk_grid_attach(g2, p^.StayCmd, 3, 1, 1, 1);
        gtk_grid_attach(g2, NewLabel('SSH-browser type', 1), 0, 2, 1, 1);
        p^.Browser := ComboWithItems(['SFTP protocol', 'None']);
        gtk_grid_attach(g2, p^.Browser, 1, 2, 1, 1);
        p^.FollowPath := NewCheck('Follow SSH path', True);
        gtk_grid_attach(g2, p^.FollowPath, 2, 2, 1, 1);
        p^.KeyCheck := NewCheck('Use private key', False);
        gtk_grid_attach(g2, p^.KeyCheck, 0, 3, 1, 1);
        hb := gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 4);
        p^.KeyFile := NewEntry(32);
        gtk_box_pack_start(hb, p^.KeyFile, True, True, 0);
        b := NewIconButton('document-open', '', 'Browse...', 16);
        Connect(b, 'clicked', @BrowseKeyFile, p^.KeyFile);
        gtk_box_pack_start(hb, b, False, False, 0);
        gtk_widget_set_sensitive(hb, False);
        Connect(p^.KeyCheck, 'toggled', @CheckSensitivity, hb);
        gtk_grid_attach(g2, hb, 1, 3, 2, 1);
        gtk_grid_attach(g2, NewLabel('Execute macro at session start', 1), 0, 4, 1, 1);
        p^.Macro := gtk_combo_box_text_new;
        gtk_combo_box_text_append(p^.Macro, '', '<none>');
        if Assigned(MacroNamesProvider) then
        begin
          names := MacroNamesProvider();
          for i := 0 to High(names) do
            gtk_combo_box_text_append(p^.Macro, PChar(names[i]), PChar(names[i]));
        end;
        gtk_combo_box_set_active(p^.Macro, 0);
        gtk_grid_attach(g2, p^.Macro, 1, 4, 1, 1);
        gtk_notebook_append_page(nb, g2, TabLabel('Advanced SSH settings', 'putty'));
      end;
    skRDP:
      begin
        g2 := NewGrid;
        gtk_grid_attach(g2, NewLabel('Domain', 1), 0, 0, 1, 1);
        p^.Domain := NewEntry(20);
        gtk_grid_attach(g2, p^.Domain, 1, 0, 1, 1);
        gtk_grid_attach(g2, NewLabel('Resolution', 1), 0, 1, 1, 1);
        p^.Resolution := ComboWithItems(ResolutionLabels);
        gtk_combo_box_set_active(p^.Resolution, 0);
        gtk_grid_attach(g2, p^.Resolution, 1, 1, 1, 1);
        p^.Clip := NewCheck('Redirect clipboard', True);
        gtk_grid_attach(g2, p^.Clip, 0, 2, 1, 1);
        p^.HomeDrive := NewCheck('Share my home folder', False);
        gtk_grid_attach(g2, p^.HomeDrive, 1, 2, 1, 1);
        p^.Sound := NewCheck('Redirect audio', True);
        gtk_grid_attach(g2, p^.Sound, 2, 2, 1, 1);
        gtk_grid_attach(g2, NewLabel('Additional FreeRDP options', 1), 0, 3, 1, 1);
        p^.RdpExtra := NewEntry(40, 'e.g. /gfx +fonts');
        gtk_grid_attach(g2, p^.RdpExtra, 1, 3, 2, 1);
        gtk_notebook_append_page(nb, g2, TabLabel('Advanced RDP settings', 'krdc'));
      end;
    skVNC:
      begin
        g2 := NewGrid;
        p^.ViewOnly := NewCheck('View only (no keyboard / mouse input)', False);
        gtk_grid_attach(g2, p^.ViewOnly, 0, 0, 2, 1);
        p^.Scaling := NewCheck('Scale remote display to the tab size', True);
        gtk_grid_attach(g2, p^.Scaling, 0, 1, 2, 1);
        gtk_notebook_append_page(nb, g2, TabLabel('Advanced VNC settings', 'tigervnc'));
      end;
    skFTP:
      begin
        g2 := NewGrid;
        p^.Passive := NewCheck('Passive mode', True);
        gtk_grid_attach(g2, p^.Passive, 0, 0, 1, 1);
        gtk_grid_attach(g2, NewMarkupLabel('<small>Leave the username empty for an anonymous connection.</small>'), 0, 1, 2, 1);
        gtk_notebook_append_page(nb, g2, TabLabel('Advanced FTP settings', 'filezilla'));
      end;
    skSFTP, skMosh:
      begin
        g2 := NewGrid;
        p^.KeyCheck := NewCheck('Use private key', False);
        gtk_grid_attach(g2, p^.KeyCheck, 0, 0, 1, 1);
        hb := gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 4);
        p^.KeyFile := NewEntry(32);
        gtk_box_pack_start(hb, p^.KeyFile, True, True, 0);
        b := NewIconButton('document-open', '', 'Browse...', 16);
        Connect(b, 'clicked', @BrowseKeyFile, p^.KeyFile);
        gtk_box_pack_start(hb, b, False, False, 0);
        gtk_widget_set_sensitive(hb, False);
        Connect(p^.KeyCheck, 'toggled', @CheckSensitivity, hb);
        gtk_grid_attach(g2, hb, 1, 0, 2, 1);
        if K = skMosh then
          gtk_notebook_append_page(nb, g2, TabLabel('Advanced Mosh settings', 'lx-mosh'))
        else
          gtk_notebook_append_page(nb, g2, TabLabel('Advanced SFTP settings', 'gftp'));
      end;
    skSerial:
      begin
        g2 := NewGrid;
        gtk_grid_attach(g2, NewLabel('Data bits', 1), 0, 0, 1, 1);
        p^.DataBits := ComboWithItems(['5', '6', '7', '8']);
        gtk_combo_box_set_active(p^.DataBits, 3);
        gtk_grid_attach(g2, p^.DataBits, 1, 0, 1, 1);
        gtk_grid_attach(g2, NewLabel('Stop bits', 1), 2, 0, 1, 1);
        p^.StopBits := ComboWithItems(['1', '2']);
        gtk_combo_box_set_active(p^.StopBits, 0);
        gtk_grid_attach(g2, p^.StopBits, 3, 0, 1, 1);
        gtk_grid_attach(g2, NewLabel('Parity', 1), 0, 1, 1, 1);
        p^.Parity := ComboWithItems(['None', 'Odd', 'Even']);
        gtk_combo_box_set_active(p^.Parity, 0);
        gtk_grid_attach(g2, p^.Parity, 1, 1, 1, 1);
        gtk_grid_attach(g2, NewLabel('Flow control', 1), 2, 1, 1, 1);
        p^.Flow := ComboWithItems(['None', 'RTS/CTS', 'Xon/Xoff']);
        gtk_combo_box_set_active(p^.Flow, 0);
        gtk_grid_attach(g2, p^.Flow, 3, 1, 1, 1);
        gtk_grid_attach(g2, NewMarkupLabel('<small>Your user must belong to the <b>dialout</b> group to open serial ports.</small>'), 0, 2, 4, 1);
        gtk_notebook_append_page(nb, g2, TabLabel('Advanced Serial settings', 'cutecom'));
      end;
    skShell:
      begin
        g2 := NewGrid;
        gtk_grid_attach(g2, NewLabel('Execute command', 1), 0, 0, 1, 1);
        p^.Command := NewEntry(40, 'leave empty for an interactive shell');
        gtk_grid_attach(g2, p^.Command, 1, 0, 1, 1);
        gtk_notebook_append_page(nb, g2, TabLabel('Advanced Shell settings', 'utilities-terminal'));
      end;
  end;

  { terminal settings }
  if K in [skSSH, skTelnet, skSerial, skShell, skMosh] then
  begin
    g2 := NewGrid;
    p^.FontCheck := NewCheck('Use a specific terminal font', False);
    gtk_grid_attach(g2, p^.FontCheck, 0, 0, 1, 1);
    p^.Font := gtk_font_button_new_with_font(PChar(Settings.FontName));
    gtk_widget_set_sensitive(p^.Font, False);
    Connect(p^.FontCheck, 'toggled', @CheckSensitivity, p^.Font);
    gtk_grid_attach(g2, p^.Font, 1, 0, 1, 1);
    gtk_grid_attach(g2, NewLabel('Colors scheme', 1), 0, 1, 1, 1);
    p^.Scheme := gtk_combo_box_text_new;
    gtk_combo_box_text_append(p^.Scheme, '', '<Default terminal colors>');
    for i := 0 to ColorSchemeCount - 1 do
      gtk_combo_box_text_append(p^.Scheme, PChar(ColorSchemes[i].Name), PChar(ColorSchemes[i].Name));
    gtk_combo_box_set_active(p^.Scheme, 0);
    gtk_grid_attach(g2, p^.Scheme, 1, 1, 1, 1);
    gtk_grid_attach(g2, NewLabel('Syntax highlighting', 1), 0, 2, 1, 1);
    p^.Hilite := gtk_combo_box_text_new;
    gtk_combo_box_text_append(p^.Hilite, '', '<Default (Settings > Terminal)>');
    gtk_combo_box_text_append(p^.Hilite, 'on', 'Standard keywords (errors, warnings, OK)');
    gtk_combo_box_text_append(p^.Hilite, 'off', 'None');
    gtk_combo_box_set_active(p^.Hilite, 0);
    gtk_grid_attach(g2, p^.Hilite, 1, 2, 1, 1);
    p^.LogCheck := NewCheck('Log the terminal output to a text file', False);
    gtk_widget_set_tooltip_text(p^.LogCheck, PChar('Logs are written to ' + Settings.LogDir +
      ' (Settings > Configuration > Terminal)'));
    gtk_grid_attach(g2, p^.LogCheck, 0, 3, 2, 1);
    gtk_notebook_append_page(nb, g2, TabLabel('Terminal settings', 'utilities-terminal'));
  end;

  { network settings }
  if K in [skSSH, skSFTP] then
  begin
    g2 := NewGrid;
    p^.JumpCheck := NewCheck('Connect through SSH gateway (jump host)', False);
    gtk_grid_attach(g2, p^.JumpCheck, 0, 0, 4, 1);
    hb := gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 6);
    gtk_box_pack_start(hb, NewLabel('Gateway host'), False, False, 0);
    p^.JumpHost := NewEntry(18);
    gtk_box_pack_start(hb, p^.JumpHost, False, False, 0);
    gtk_box_pack_start(hb, NewLabel('Username'), False, False, 0);
    p^.JumpUser := NewEntry(10);
    gtk_box_pack_start(hb, p^.JumpUser, False, False, 0);
    gtk_box_pack_start(hb, NewLabel('Port'), False, False, 0);
    p^.JumpPort := NewSpin(1, 65535, 22);
    gtk_box_pack_start(hb, p^.JumpPort, False, False, 0);
    gtk_widget_set_sensitive(hb, False);
    Connect(p^.JumpCheck, 'toggled', @CheckSensitivity, hb);
    gtk_grid_attach(g2, hb, 0, 1, 4, 1);
    if K = skSSH then
    begin
      p^.KeepCheck := NewCheck('SSH keepalive (seconds)', True);
      gtk_grid_attach(g2, p^.KeepCheck, 0, 2, 1, 1);
      p^.KeepAlive := NewSpin(5, 3600, 60);
      Connect(p^.KeepCheck, 'toggled', @CheckSensitivity, p^.KeepAlive);
      gtk_grid_attach(g2, p^.KeepAlive, 1, 2, 1, 1);
      gtk_grid_attach(g2, NewLabel('Expert SSH options', 1), 0, 3, 1, 1);
      p^.Extra := NewEntry(40, 'e.g. -o Ciphers=aes256-ctr -L 8080:localhost:80');
      gtk_grid_attach(g2, p^.Extra, 1, 3, 3, 1);
    end;
    gtk_notebook_append_page(nb, g2, TabLabel('Network settings', 'network-workgroup'));
  end;

  { bookmark settings }
  g2 := NewGrid;
  r := 0;
  gtk_grid_attach(g2, NewLabel('Session name', 1), 0, r, 1, 1);
  p^.Name := NewEntry(30, 'optional');
  gtk_grid_attach(g2, p^.Name, 1, r, 1, 1);
  Inc(r);
  gtk_grid_attach(g2, NewLabel('Folder', 1), 0, r, 1, 1);
  p^.Folder := gtk_combo_box_text_new_with_entry;
  gtk_combo_box_text_append_text(p^.Folder, '');
  for i := 0 to Store.Folders.Count - 1 do
    gtk_combo_box_text_append_text(p^.Folder, PChar(Store.Folders[i]));
  gtk_grid_attach(g2, p^.Folder, 1, r, 1, 1);
  Inc(r);
  gtk_grid_attach(g2, NewLabel('Comment', 1), 0, r, 1, 1);
  p^.Comment := NewEntry(40);
  gtk_grid_attach(g2, p^.Comment, 1, r, 2, 1);
  Inc(r);
  gtk_grid_attach(g2, NewLabel('Tab color', 1), 0, r, 1, 1);
  p^.TabColor := gtk_combo_box_text_new;
  for i := 0 to TabColorCount - 1 do
    if i = 0 then
      gtk_combo_box_text_append(p^.TabColor, '', PChar(TabColorNames[i]))
    else
      gtk_combo_box_text_append(p^.TabColor, PChar(TabColorIds[i]), PChar(TabColorDots[i] + '  ' + TabColorNames[i]));
  gtk_combo_box_set_active(p^.TabColor, 0);
  gtk_widget_set_tooltip_text(p^.TabColor, 'Colour mark shown on the tab of this session (e.g. red for production servers)');
  gtk_widget_set_halign(p^.TabColor, GTK_ALIGN_START);
  gtk_grid_attach(g2, p^.TabColor, 1, r, 1, 1);
  Inc(r);
  p^.Shortcut := NewCheck('Create a desktop shortcut to this session', False);
  gtk_grid_attach(g2, p^.Shortcut, 1, r, 2, 1);
  gtk_notebook_append_page(nb, g2, TabLabel('Bookmark settings', 'starred'));

  gtk_box_pack_start(root, nb, True, True, 0);
  Result := root;
end;

procedure TSessionDialog.LoadValues(K: TSessionKind; Src: TSession);
var
  p: ^TKindPage;
  i: Integer;
  s: TSession;
begin
  s := Src;
  p := @Pages[K];
  if p^.Host <> nil then SetEntryText(p^.Host, s.Host);
  if p^.User <> nil then
  begin
    SetEntryText(p^.User, s.User);
    gtk_toggle_button_set_active(p^.UserCheck, s.User <> '');
  end;
  if p^.Port <> nil then gtk_spin_button_set_value(p^.Port, s.Port);
  if (p^.Password <> nil) and s.HasPassword then
    gtk_entry_set_placeholder_text(p^.Password, '(saved - leave empty to keep it)');
  if p^.SavePw <> nil then gtk_toggle_button_set_active(p^.SavePw, True);
  if p^.X11 <> nil then gtk_toggle_button_set_active(p^.X11, s.X11);
  if p^.Compression <> nil then gtk_toggle_button_set_active(p^.Compression, s.Compression);
  if p^.Agent <> nil then gtk_toggle_button_set_active(p^.Agent, s.AgentForward);
  if p^.RemoteCmd <> nil then SetEntryText(p^.RemoteCmd, s.RemoteCommand);
  if p^.StayCmd <> nil then gtk_toggle_button_set_active(p^.StayCmd, s.StayAfterCommand);
  if p^.Browser <> nil then
    if s.SftpBrowser then gtk_combo_box_set_active(p^.Browser, 0) else gtk_combo_box_set_active(p^.Browser, 1);
  if p^.FollowPath <> nil then gtk_toggle_button_set_active(p^.FollowPath, s.FollowPath);
  if p^.KeyFile <> nil then
  begin
    SetEntryText(p^.KeyFile, s.KeyFile);
    gtk_toggle_button_set_active(p^.KeyCheck, s.KeyFile <> '');
  end;
  if (p^.Macro <> nil) and (s.StartMacro <> '') then
    gtk_combo_box_set_active_id(p^.Macro, PChar(s.StartMacro));
  if p^.FontCheck <> nil then
  begin
    gtk_toggle_button_set_active(p^.FontCheck, s.TermFont <> '');
    if s.TermFont <> '' then gtk_font_chooser_set_font(p^.Font, PChar(s.TermFont));
  end;
  if p^.Scheme <> nil then
    if not gtk_combo_box_set_active_id(p^.Scheme, PChar(s.ColorScheme)) then
      gtk_combo_box_set_active(p^.Scheme, 0);
  if p^.LogCheck <> nil then gtk_toggle_button_set_active(p^.LogCheck, s.LogOutput);
  if p^.Hilite <> nil then
    if not gtk_combo_box_set_active_id(p^.Hilite, PChar(s.Highlight)) then
      gtk_combo_box_set_active(p^.Hilite, 0);
  if not gtk_combo_box_set_active_id(p^.TabColor, PChar(s.TabColor)) then
    gtk_combo_box_set_active(p^.TabColor, 0);
  if p^.JumpCheck <> nil then
  begin
    gtk_toggle_button_set_active(p^.JumpCheck, s.JumpHost <> '');
    if s.JumpHost <> '' then
    begin
      i := Pos('@', s.JumpHost);
      if i > 0 then
      begin
        SetEntryText(p^.JumpUser, Copy(s.JumpHost, 1, i - 1));
        SetEntryText(p^.JumpHost, Copy(s.JumpHost, i + 1, MaxInt));
      end
      else
        SetEntryText(p^.JumpHost, s.JumpHost);
      i := LastDelimiter(':', EntryText(p^.JumpHost));
      if i > 0 then
      begin
        gtk_spin_button_set_value(p^.JumpPort, StrToIntSafe(Copy(EntryText(p^.JumpHost), i + 1, 10), 22));
        SetEntryText(p^.JumpHost, Copy(EntryText(p^.JumpHost), 1, i - 1));
      end;
    end;
  end;
  if p^.KeepCheck <> nil then
  begin
    gtk_toggle_button_set_active(p^.KeepCheck, s.KeepAlive > 0);
    if s.KeepAlive > 0 then gtk_spin_button_set_value(p^.KeepAlive, s.KeepAlive);
  end;
  if p^.Extra <> nil then SetEntryText(p^.Extra, s.ExtraOptions);
  if p^.Domain <> nil then SetEntryText(p^.Domain, s.Domain);
  if p^.Resolution <> nil then
    for i := 0 to High(ResolutionIds) do
      if ResolutionIds[i] = s.Resolution then gtk_combo_box_set_active(p^.Resolution, i);
  if p^.Clip <> nil then gtk_toggle_button_set_active(p^.Clip, s.RdpClipboard);
  if p^.HomeDrive <> nil then gtk_toggle_button_set_active(p^.HomeDrive, s.RdpHomeDrive);
  if p^.Sound <> nil then gtk_toggle_button_set_active(p^.Sound, s.RdpSound);
  if p^.RdpExtra <> nil then SetEntryText(p^.RdpExtra, s.RdpExtra);
  if p^.ViewOnly <> nil then gtk_toggle_button_set_active(p^.ViewOnly, s.ViewOnly);
  if p^.Scaling <> nil then gtk_toggle_button_set_active(p^.Scaling, s.Scaling);
  if p^.Passive <> nil then gtk_toggle_button_set_active(p^.Passive, s.FtpPassive);
  if p^.Device <> nil then SetComboText(p^.Device, s.Device);
  if p^.Baud <> nil then SetComboText(p^.Baud, IntToStr(s.Baud));
  if p^.DataBits <> nil then gtk_combo_box_set_active(p^.DataBits, s.DataBits - 5);
  if p^.StopBits <> nil then gtk_combo_box_set_active(p^.StopBits, s.StopBits - 1);
  if p^.Parity <> nil then
    if s.Parity = 'odd' then gtk_combo_box_set_active(p^.Parity, 1)
    else if s.Parity = 'even' then gtk_combo_box_set_active(p^.Parity, 2)
    else gtk_combo_box_set_active(p^.Parity, 0);
  if p^.Flow <> nil then
    if s.FlowControl = 'rtscts' then gtk_combo_box_set_active(p^.Flow, 1)
    else if s.FlowControl = 'xonxoff' then gtk_combo_box_set_active(p^.Flow, 2)
    else gtk_combo_box_set_active(p^.Flow, 0);
  if p^.ShellCombo <> nil then
    if not gtk_combo_box_set_active_id(p^.ShellCombo, PChar(s.ShellPath)) then
      gtk_combo_box_set_active(p^.ShellCombo, 0);
  if p^.StartDir <> nil then SetEntryText(p^.StartDir, s.StartDir);
  if p^.Command <> nil then SetEntryText(p^.Command, s.Command);
  if p^.Url <> nil then SetEntryText(p^.Url, s.Url);
  SetEntryText(p^.Name, s.Name);
  SetComboText(p^.Folder, s.Folder);
  SetEntryText(p^.Comment, s.Comment);
end;

function TSessionDialog.Validate: Boolean;
var
  p: ^TKindPage;
  folder: string;
begin
  Result := False;
  if not HasKind then
  begin
    MsgWarning('Please choose a session type', 'Click on one of the icons at the top of the window.');
    Exit;
  end;
  p := @Pages[Current];
  if (p^.Host <> nil) and (Trim(EntryText(p^.Host)) = '') then
  begin
    MsgWarning('The remote host is missing', 'Please enter a host name or an IP address.');
    gtk_widget_grab_focus(p^.Host);
    Exit;
  end;
  if (p^.Host <> nil) and (Pos(' ', Trim(EntryText(p^.Host))) > 0) then
  begin
    MsgWarning('Invalid remote host', 'The host name must not contain spaces.');
    gtk_widget_grab_focus(p^.Host);
    Exit;
  end;
  if (p^.Device <> nil) and (ComboEntryText(p^.Device) = '') then
  begin
    MsgWarning('The serial port is missing', 'Please choose a serial port (e.g. /dev/ttyUSB0).');
    Exit;
  end;
  if (p^.Baud <> nil) and (StrToIntDef(ComboEntryText(p^.Baud), 0) <= 0) then
  begin
    MsgWarning('Invalid serial speed', 'Please choose a valid speed in bits per second.');
    Exit;
  end;
  if (Current = skFile) and (Trim(EntryText(p^.StartDir)) = '') then
  begin
    MsgWarning('The folder is missing', 'Please choose a local folder.');
    Exit;
  end;
  if (p^.Url <> nil) and (Trim(EntryText(p^.Url)) = '') then
  begin
    MsgWarning('The URL is missing', 'Please enter a website address.');
    Exit;
  end;
  folder := ComboEntryText(p^.Folder);
  if (folder <> '') and ((folder[1] = '/') or (Pos('//', folder) > 0)) then
  begin
    MsgWarning('Invalid folder name', 'Use names like "Servers" or "Servers/Production".');
    Exit;
  end;
  Result := True;
end;

procedure TSessionDialog.StoreValues;
var
  p: ^TKindPage;
  s: TSession;
  pw, j, url, folder: string;
begin
  s := Sess;
  if s.Kind <> Current then
  begin
    s.Kind := Current;
    s.Port := SessionKindDefaultPorts[Current];
  end;
  p := @Pages[Current];
  if p^.Host <> nil then s.Host := Trim(EntryText(p^.Host));
  if p^.User <> nil then
  begin
    if gtk_toggle_button_get_active(p^.UserCheck) then s.User := Trim(EntryText(p^.User)) else s.User := '';
  end;
  if p^.Port <> nil then
  begin
    gtk_spin_button_update(p^.Port);
    s.Port := gtk_spin_button_get_value_as_int(p^.Port);
  end;
  if p^.Password <> nil then
  begin
    pw := EntryText(p^.Password);
    if not gtk_toggle_button_get_active(p^.SavePw) then
    begin
      if s.HasPassword then ForgetPassword(s.PasswordKey);
      s.HasPassword := False;
    end
    else if pw <> '' then
    begin
      s.HasPassword := StorePassword(s.PasswordKey, pw);
      if not s.HasPassword then
        MsgWarning('Password not saved', 'The GNOME keyring is not available: the password will be asked at each ' +
          'connection. (Settings > Configuration > Misc can allow an obfuscated password file instead.)');
    end;
  end;
  if p^.X11 <> nil then s.X11 := gtk_toggle_button_get_active(p^.X11);
  if p^.Compression <> nil then s.Compression := gtk_toggle_button_get_active(p^.Compression);
  if p^.Agent <> nil then s.AgentForward := gtk_toggle_button_get_active(p^.Agent);
  if p^.RemoteCmd <> nil then s.RemoteCommand := Trim(EntryText(p^.RemoteCmd));
  if p^.StayCmd <> nil then s.StayAfterCommand := gtk_toggle_button_get_active(p^.StayCmd);
  if p^.Browser <> nil then s.SftpBrowser := gtk_combo_box_get_active(p^.Browser) = 0;
  if p^.FollowPath <> nil then s.FollowPath := gtk_toggle_button_get_active(p^.FollowPath);
  if p^.KeyFile <> nil then
  begin
    if gtk_toggle_button_get_active(p^.KeyCheck) then s.KeyFile := Trim(EntryText(p^.KeyFile)) else s.KeyFile := '';
  end;
  if p^.Macro <> nil then s.StartMacro := CStr(gtk_combo_box_get_active_id(p^.Macro));
  if p^.FontCheck <> nil then
  begin
    if gtk_toggle_button_get_active(p^.FontCheck) then
      s.TermFont := TakeStr(gtk_font_chooser_get_font(p^.Font))
    else
      s.TermFont := '';
  end;
  if p^.Scheme <> nil then s.ColorScheme := CStr(gtk_combo_box_get_active_id(p^.Scheme));
  if p^.LogCheck <> nil then s.LogOutput := gtk_toggle_button_get_active(p^.LogCheck);
  if p^.Hilite <> nil then s.Highlight := CStr(gtk_combo_box_get_active_id(p^.Hilite));
  s.TabColor := CStr(gtk_combo_box_get_active_id(p^.TabColor));
  if p^.JumpCheck <> nil then
  begin
    if gtk_toggle_button_get_active(p^.JumpCheck) and (Trim(EntryText(p^.JumpHost)) <> '') then
    begin
      j := Trim(EntryText(p^.JumpHost));
      if Trim(EntryText(p^.JumpUser)) <> '' then j := Trim(EntryText(p^.JumpUser)) + '@' + j;
      if gtk_spin_button_get_value_as_int(p^.JumpPort) <> 22 then
        j := j + ':' + IntToStr(gtk_spin_button_get_value_as_int(p^.JumpPort));
      s.JumpHost := j;
    end
    else
      s.JumpHost := '';
  end;
  if p^.KeepCheck <> nil then
  begin
    if gtk_toggle_button_get_active(p^.KeepCheck) then
      s.KeepAlive := gtk_spin_button_get_value_as_int(p^.KeepAlive)
    else
      s.KeepAlive := 0;
  end;
  if p^.Extra <> nil then s.ExtraOptions := Trim(EntryText(p^.Extra));
  if p^.Domain <> nil then s.Domain := Trim(EntryText(p^.Domain));
  if p^.Resolution <> nil then s.Resolution := ResolutionIds[gtk_combo_box_get_active(p^.Resolution)];
  if p^.Clip <> nil then s.RdpClipboard := gtk_toggle_button_get_active(p^.Clip);
  if p^.HomeDrive <> nil then s.RdpHomeDrive := gtk_toggle_button_get_active(p^.HomeDrive);
  if p^.Sound <> nil then s.RdpSound := gtk_toggle_button_get_active(p^.Sound);
  if p^.RdpExtra <> nil then s.RdpExtra := Trim(EntryText(p^.RdpExtra));
  if p^.ViewOnly <> nil then s.ViewOnly := gtk_toggle_button_get_active(p^.ViewOnly);
  if p^.Scaling <> nil then s.Scaling := gtk_toggle_button_get_active(p^.Scaling);
  if p^.Passive <> nil then s.FtpPassive := gtk_toggle_button_get_active(p^.Passive);
  if p^.Device <> nil then s.Device := ComboEntryText(p^.Device);
  if p^.Baud <> nil then s.Baud := StrToIntDef(ComboEntryText(p^.Baud), 115200);
  if p^.DataBits <> nil then s.DataBits := gtk_combo_box_get_active(p^.DataBits) + 5;
  if p^.StopBits <> nil then s.StopBits := gtk_combo_box_get_active(p^.StopBits) + 1;
  if p^.Parity <> nil then
    case gtk_combo_box_get_active(p^.Parity) of
      1: s.Parity := 'odd';
      2: s.Parity := 'even';
    else
      s.Parity := 'none';
    end;
  if p^.Flow <> nil then
    case gtk_combo_box_get_active(p^.Flow) of
      1: s.FlowControl := 'rtscts';
      2: s.FlowControl := 'xonxoff';
    else
      s.FlowControl := 'none';
    end;
  if p^.ShellCombo <> nil then s.ShellPath := CStr(gtk_combo_box_get_active_id(p^.ShellCombo));
  if p^.StartDir <> nil then s.StartDir := Trim(EntryText(p^.StartDir));
  if p^.Command <> nil then s.Command := Trim(EntryText(p^.Command));
  if p^.Url <> nil then
  begin
    url := Trim(EntryText(p^.Url));
    if (url <> '') and (Pos('://', url) = 0) then url := 'https://' + url;
    s.Url := url;
  end;
  s.Name := Trim(EntryText(p^.Name));
  folder := ComboEntryText(p^.Folder);
  while (folder <> '') and (folder[Length(folder)] = '/') do Delete(folder, Length(folder), 1);
  s.Folder := folder;
  s.Comment := Trim(EntryText(p^.Comment));
end;

function EditSessionDialog(Sess: TSession; IsNew: Boolean): Boolean;
var
  d: TSessionDialog;
  resp: Integer;
  shortcut: Boolean;
  k: TSessionKind;
  tmp: TSession;
begin
  Result := False;
  d := TSessionDialog.Create;
  try
    d.Sess := Sess;
    d.Build(IsNew);
    for k := Low(TSessionKind) to High(TSessionKind) do
      if (not IsNew) and (k = Sess.Kind) then
        d.LoadValues(k, Sess)
      else
      begin
        tmp := TSession.Create(k);
        try
          if not IsNew then
          begin
            { keep the common fields when the user switches the type }
            tmp.Host := Sess.Host;
            tmp.User := Sess.User;
            tmp.Name := Sess.Name;
            tmp.Folder := Sess.Folder;
            tmp.Comment := Sess.Comment;
          end;
          d.LoadValues(k, tmp);
        finally
          tmp.Free;
        end;
      end;
    if not IsNew then
    begin
      gtk_toggle_button_set_active(d.Buttons[Sess.Kind], True);
      d.SelectKind(Sess.Kind);
    end
    else
    begin
      { no type pre-selected: the first radio button is active by default,
        so the placeholder stays visible until the user clicks a type }
      d.HasKind := False;
      gtk_stack_set_visible_child_name(d.Stack, 'none');
    end;
    repeat
      resp := gtk_dialog_run(d.Dlg);
      if resp <> GTK_RESPONSE_OK then Break;
      if d.Validate then
      begin
        shortcut := gtk_toggle_button_get_active(d.Pages[d.Current].Shortcut);
        d.StoreValues;
        Result := True;
        if shortcut then
        begin
          gtk_widget_hide(d.Dlg);
          CreateDesktopShortcut(Sess);
        end;
        Break;
      end;
    until False;
    gtk_widget_destroy(d.Dlg);
    g_object_unref(d.NoneRadio);
  finally
    d.Free;
  end;
end;

end.

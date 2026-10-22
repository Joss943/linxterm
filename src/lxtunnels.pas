{ LinXterm - graphical SSH tunnels manager (local, remote and dynamic port
  forwarding), the equivalent of MobaSSHTunnel. }
unit lxtunnels;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, BaseUnix, fpjson, lxgtk, lxutil, lxconfig, lxtabs, lxterminal;

procedure ShowTunnelsWindow;

implementation

uses
  StrUtils;

type
  TTunnelState = (tsStopped, tsStarting, tsRunning, tsFailed);

  TTunnel = class
  public
    Id, Name, Kind: string;      { Kind: L, R or D }
    BindAddr: string;
    FwdPort: Integer;
    RemoteHost: string;
    RemotePort: Integer;
    SshHost, SshUser, KeyFile: string;
    ExtraOptions: string;
    SshPort: Integer;
    AutoStart, HasPassword: Boolean;
    Proc: TChildProcess;
    State: TTunnelState;
    LastError: string;
    Errors: TStringList;
    PassFile: string;
    StartTimer: guint;
    constructor Create;
    destructor Destroy; override;
    function KindText: string;
    function Describe: string;
    procedure Start;
    procedure Stop;
    procedure ProcLine(Sender: TChildProcess; const Line: string; IsErr: Boolean);
    procedure ProcExit(Sender: TChildProcess; Status: Integer);
  end;

  TTunnelsUi = class
  public
    Win, Store, View: Pointer;
    procedure Refresh;
    function Selected: TTunnel;
  end;

var
  Tunnels: TList;
  Ui: TTunnelsUi = nil;

{ ---------------------------------------------------------------- storage }

procedure SaveTunnels;
var
  a: TJSONArray;
  o: TJSONObject;
  i: Integer;
  t: TTunnel;
begin
  a := TJSONArray.Create;
  try
    for i := 0 to Tunnels.Count - 1 do
    begin
      t := TTunnel(Tunnels[i]);
      o := TJSONObject.Create;
      o.Add('id', t.Id);
      o.Add('name', t.Name);
      o.Add('kind', t.Kind);
      o.Add('bind', t.BindAddr);
      o.Add('forwarded_port', t.FwdPort);
      o.Add('remote_host', t.RemoteHost);
      o.Add('remote_port', t.RemotePort);
      o.Add('ssh_host', t.SshHost);
      o.Add('ssh_user', t.SshUser);
      o.Add('ssh_port', t.SshPort);
      o.Add('key_file', t.KeyFile);
      o.Add('extra_options', t.ExtraOptions);
      o.Add('autostart', t.AutoStart);
      o.Add('has_password', t.HasPassword);
      a.Add(o);
    end;
    SaveJsonFile(ConfigDir + '/tunnels.json', a);
  finally
    a.Free;
  end;
end;

procedure LoadTunnels;
var
  d: TJSONData;
  o: TJSONObject;
  i: Integer;
  t: TTunnel;
begin
  Tunnels := TList.Create;
  d := LoadJsonFile(ConfigDir + '/tunnels.json');
  if d = nil then Exit;
  try
    if d.JSONType <> jtArray then Exit;
    for i := 0 to TJSONArray(d).Count - 1 do
    begin
      if TJSONArray(d)[i].JSONType <> jtObject then Continue;
      o := TJSONObject(TJSONArray(d)[i]);
      t := TTunnel.Create;
      t.Id := JStr(o, 'id', NewId);
      t.Name := JStr(o, 'name', 'tunnel');
      t.Kind := JStr(o, 'kind', 'L');
      t.BindAddr := JStr(o, 'bind', '127.0.0.1');
      t.FwdPort := JInt(o, 'forwarded_port', 8080);
      t.RemoteHost := JStr(o, 'remote_host', 'localhost');
      t.RemotePort := JInt(o, 'remote_port', 80);
      t.SshHost := JStr(o, 'ssh_host', '');
      t.SshUser := JStr(o, 'ssh_user', '');
      t.SshPort := JInt(o, 'ssh_port', 22);
      t.KeyFile := JStr(o, 'key_file', '');
      t.ExtraOptions := JStr(o, 'extra_options', '');
      t.AutoStart := JBool(o, 'autostart', False);
      t.HasPassword := JBool(o, 'has_password', False);
      Tunnels.Add(t);
    end;
  finally
    d.Free;
  end;
end;

{ ---------------------------------------------------------------- TTunnel }

constructor TTunnel.Create;
begin
  inherited Create;
  Id := NewId;
  Kind := 'L';
  BindAddr := '127.0.0.1';
  FwdPort := 8080;
  RemoteHost := 'localhost';
  RemotePort := 80;
  SshPort := 22;
  Errors := TStringList.Create;
end;

destructor TTunnel.Destroy;
begin
  Stop;
  Errors.Free;
  inherited Destroy;
end;

function TTunnel.KindText: string;
begin
  case Kind of
    'R': Result := 'Remote';
    'D': Result := 'Dynamic (SOCKS)';
  else
    Result := 'Local';
  end;
end;

function TTunnel.Describe: string;
begin
  case Kind of
    'R': Result := 'port ' + IntToStr(FwdPort) + ' of ' + SshHost + ' -> ' + RemoteHost + ':' + IntToStr(RemotePort);
    'D': Result := 'SOCKS proxy on ' + BindAddr + ':' + IntToStr(FwdPort) + ' through ' + SshHost;
  else
    Result := BindAddr + ':' + IntToStr(FwdPort) + ' -> ' + RemoteHost + ':' + IntToStr(RemotePort) + ' through ' + SshHost;
  end;
end;

function StartedCb(data: gpointer): gboolean; cdecl;
var
  t: TTunnel;
begin
  t := TTunnel(data);
  t.StartTimer := 0;
  if (t.State = tsStarting) and (t.Proc <> nil) and t.Proc.Running then
  begin
    t.State := tsRunning;
    SecureDelete(t.PassFile);
    t.PassFile := '';
    if Ui <> nil then Ui.Refresh;
  end;
  Result := False;
end;

procedure TTunnel.Start;
var
  args, env: TStringArray;
  pw, err, spec: string;
  argc: gint;
  argv: PPChar;
  gerr: PGError;
  i: Integer;
  procedure Add(const S: string);
  begin
    SetLength(args, Length(args) + 1);
    args[High(args)] := S;
  end;
begin
  if (Proc <> nil) and Proc.Running then Exit;
  if Trim(SshHost) = '' then
  begin
    State := tsFailed;
    LastError := 'No SSH server';
    Exit;
  end;
  Errors.Clear;
  LastError := '';
  args := nil;
  Add('ssh');
  Add('-N');
  Add('-o');
  Add('ExitOnForwardFailure=yes');
  Add('-o');
  Add('ServerAliveInterval=30');
  Add('-o');
  Add('ServerAliveCountMax=3');
  if (Settings.HostKeyPolicy = 'accept-new') or (Settings.HostKeyPolicy = 'no') then
  begin
    Add('-o');
    Add('StrictHostKeyChecking=' + Settings.HostKeyPolicy);
  end;
  if SshPort <> 22 then
  begin
    Add('-p');
    Add(IntToStr(SshPort));
  end;
  if SshUser <> '' then
  begin
    Add('-l');
    Add(SshUser);
  end;
  if KeyFile <> '' then
  begin
    Add('-i');
    Add(KeyFile);
  end;
  case Kind of
    'R':
      begin
        Add('-R');
        spec := IntToStr(FwdPort) + ':' + RemoteHost + ':' + IntToStr(RemotePort);
      end;
    'D':
      begin
        Add('-D');
        spec := BindAddr + ':' + IntToStr(FwdPort);
      end;
  else
    begin
      Add('-L');
      spec := BindAddr + ':' + IntToStr(FwdPort) + ':' + RemoteHost + ':' + IntToStr(RemotePort);
    end;
  end;
  Add(spec);
  if Trim(ExtraOptions) <> '' then
  begin
    gerr := nil;
    argv := nil;
    if g_shell_parse_argv(PChar(ExtraOptions), @argc, @argv, @gerr) then
    begin
      for i := 0 to argc - 1 do Add(AnsiString(argv[i]));
      g_strfreev(argv);
    end
    else
      ErrMsg(gerr);
  end;
  Add('--');
  Add(SshHost);
  pw := '';
  if HasPassword then LookupPassword('tunnel:' + Id, pw);
  SecureDelete(PassFile);
  PassFile := '';
  if pw <> '' then PassFile := WriteSecretFile(pw);
  env := nil;
  AddAskPassEnv(env, PassFile);
  if Proc <> nil then
  begin
    Proc.OnLine := nil;
    Proc.OnExit := nil;
    FreeLater(Proc);
  end;
  Proc := TChildProcess.Create;
  Proc.OnLine := @ProcLine;
  Proc.OnExit := @ProcExit;
  if not Proc.Start(args, env, HomeDir, False, err) then
  begin
    State := tsFailed;
    LastError := err;
    Exit;
  end;
  State := tsStarting;
  if StartTimer <> 0 then g_source_remove(StartTimer);
  StartTimer := g_timeout_add(2500, @StartedCb, Self);
end;

procedure TTunnel.Stop;
begin
  if StartTimer <> 0 then
  begin
    g_source_remove(StartTimer);
    StartTimer := 0;
  end;
  if Proc <> nil then
  begin
    Proc.OnLine := nil;
    Proc.OnExit := nil;
    FreeAndNil(Proc);
  end;
  SecureDelete(PassFile);
  PassFile := '';
  State := tsStopped;
end;

procedure TTunnel.ProcLine(Sender: TChildProcess; const Line: string; IsErr: Boolean);
begin
  if Trim(Line) = '' then Exit;
  Errors.Add(Trim(Line));
  if Errors.Count > 20 then Errors.Delete(0);
end;

procedure TTunnel.ProcExit(Sender: TChildProcess; Status: Integer);
begin
  if StartTimer <> 0 then
  begin
    g_source_remove(StartTimer);
    StartTimer := 0;
  end;
  SecureDelete(PassFile);
  PassFile := '';
  State := tsFailed;
  if Errors.Count > 0 then LastError := Errors[Errors.Count - 1]
  else LastError := 'ssh exited with code ' + IntToStr(Status);
  Sender.OnLine := nil;
  Sender.OnExit := nil;
  if Proc = Sender then
  begin
    FreeLater(Proc);
    Proc := nil;
  end;
  if App <> nil then App.SetStatus('SSH tunnel "' + Name + '" stopped: ' + LastError);
  if Ui <> nil then Ui.Refresh;
end;

{ ---------------------------------------------------------------- editor dialog }

type
  TTunnelDialog = class
  public
    Dlg, RadioL, RadioR, RadioD, Explain, NameE, Fwd, Bind, SshH, SshU, SshP, RemH, RemP, Key, Pass, SavePw, Auto, Extra: Pointer;
    RemoteBox, BindBox, FwdLabel: Pointer;
    procedure KindChanged;
  end;

procedure KindToggledCb(b: Pointer; data: gpointer); cdecl;
begin
  if gtk_toggle_button_get_active(b) then TTunnelDialog(data).KindChanged;
end;

procedure BrowseKey(b: Pointer; data: gpointer); cdecl;
var
  fn: string;
begin
  if ChooseOpenFile('Choose a private key', HomeDir + '/.ssh', fn) then SetEntryText(data, fn);
end;

procedure TTunnelDialog.KindChanged;
begin
  if gtk_toggle_button_get_active(RadioR) then
  begin
    gtk_label_set_markup(Explain, '<b>Remote port forwarding</b>: connections to a port of the SSH server are ' +
      'forwarded to a computer reachable from this one.');
    gtk_label_set_text(FwdLabel, 'Port opened on the SSH server');
    gtk_widget_set_sensitive(RemoteBox, True);
    gtk_widget_set_sensitive(BindBox, False);
  end
  else if gtk_toggle_button_get_active(RadioD) then
  begin
    gtk_label_set_markup(Explain, '<b>Dynamic port forwarding</b>: a SOCKS proxy on this computer sends ' +
      'every connection through the SSH server.');
    gtk_label_set_text(FwdLabel, 'SOCKS proxy port (this computer)');
    gtk_widget_set_sensitive(RemoteBox, False);
    gtk_widget_set_sensitive(BindBox, True);
  end
  else
  begin
    gtk_label_set_markup(Explain, '<b>Local port forwarding</b>: connections from local clients to the forwarded ' +
      'port reach the remote server through the SSH server.');
    gtk_label_set_text(FwdLabel, 'Forwarded port (this computer)');
    gtk_widget_set_sensitive(RemoteBox, True);
    gtk_widget_set_sensitive(BindBox, True);
  end;
end;

function Column(const Icon, Caption: string; Size: Integer): Pointer;
begin
  Result := gtk_box_new(GTK_ORIENTATION_VERTICAL, 4);
  gtk_box_pack_start(Result, NewIcon(Icon, Size), False, False, 0);
  gtk_box_pack_start(Result, NewMarkupLabel('<b>' + Caption + '</b>', 0.5), False, False, 0);
end;

function EditTunnel(T: TTunnel; IsNew: Boolean): Boolean;
var
  d: TTunnelDialog;
  area, vbox, hb, row, col, g, b, frame: Pointer;
  pw: string;
begin
  Result := False;
  d := TTunnelDialog.Create;
  try
    d.Dlg := gtk_dialog_new_with_buttons(PChar(IfThen(IsNew, 'New SSH tunnel', 'Edit SSH tunnel')), Ui.Win,
      GTK_DIALOG_MODAL or GTK_DIALOG_DESTROY_WITH_PARENT, nil);
    gtk_window_set_default_size(d.Dlg, 860, 520);
    area := gtk_dialog_get_content_area(d.Dlg);
    vbox := gtk_box_new(GTK_ORIENTATION_VERTICAL, 10);
    SetMargins(vbox, 12);
    hb := gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 24);
    gtk_widget_set_halign(hb, GTK_ALIGN_CENTER);
    d.RadioL := gtk_radio_button_new_with_label(nil, 'Local port forwarding');
    d.RadioR := gtk_radio_button_new_with_label_from_widget(d.RadioL, 'Remote port forwarding');
    d.RadioD := gtk_radio_button_new_with_label_from_widget(d.RadioL, 'Dynamic port forwarding (SOCKS proxy)');
    gtk_box_pack_start(hb, d.RadioL, False, False, 0);
    gtk_box_pack_start(hb, d.RadioR, False, False, 0);
    gtk_box_pack_start(hb, d.RadioD, False, False, 0);
    frame := gtk_frame_new(nil);
    gtk_container_add(frame, hb);
    SetMargins(hb, 6);
    gtk_box_pack_start(vbox, frame, False, False, 0);
    d.Explain := NewMarkupLabel('', 0.5);
    gtk_label_set_line_wrap(d.Explain, True);
    gtk_box_pack_start(vbox, d.Explain, False, False, 0);

    { the diagram: my computer -> firewall -> SSH server -> remote server }
    row := gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 18);
    gtk_widget_set_halign(row, GTK_ALIGN_CENTER);
    col := Column('computer', 'My computer'#10'with LinXterm', 64);
    d.BindBox := gtk_box_new(GTK_ORIENTATION_VERTICAL, 4);
    d.FwdLabel := NewLabel('Forwarded port', 0.5);
    gtk_box_pack_start(col, d.FwdLabel, False, False, 6);
    d.Fwd := gtk_spin_button_new_with_range(1, 65535, 1);
    gtk_spin_button_set_value(d.Fwd, T.FwdPort);
    gtk_box_pack_start(col, d.Fwd, False, False, 0);
    d.Bind := gtk_combo_box_text_new;
    gtk_combo_box_text_append(d.Bind, '127.0.0.1', 'this computer only');
    gtk_combo_box_text_append(d.Bind, '0.0.0.0', 'all network interfaces');
    if not gtk_combo_box_set_active_id(d.Bind, PChar(T.BindAddr)) then gtk_combo_box_set_active(d.Bind, 0);
    gtk_box_pack_start(d.BindBox, d.Bind, False, False, 0);
    gtk_box_pack_start(col, d.BindBox, False, False, 0);
    gtk_box_pack_start(row, col, False, False, 0);
    gtk_box_pack_start(row, NewMarkupLabel('<span size="xx-large" foreground="#e53935">━━▶</span>', 0.5), False, False, 0);
    col := Column('gufw', 'Firewall', 48);
    gtk_box_pack_start(row, col, False, False, 0);
    gtk_box_pack_start(row, NewMarkupLabel('<span size="xx-large" foreground="#43a047">━━▶</span>', 0.5), False, False, 0);
    col := Column('utilities-terminal', 'SSH server', 64);
    g := gtk_grid_new;
    gtk_grid_set_row_spacing(g, 4);
    gtk_grid_set_column_spacing(g, 4);
    gtk_grid_attach(g, NewLabel('Host', 1), 0, 0, 1, 1);
    d.SshH := gtk_entry_new;
    gtk_entry_set_width_chars(d.SshH, 16);
    SetEntryText(d.SshH, T.SshHost);
    gtk_grid_attach(g, d.SshH, 1, 0, 1, 1);
    gtk_grid_attach(g, NewLabel('Login', 1), 0, 1, 1, 1);
    d.SshU := gtk_entry_new;
    gtk_entry_set_width_chars(d.SshU, 16);
    SetEntryText(d.SshU, T.SshUser);
    gtk_grid_attach(g, d.SshU, 1, 1, 1, 1);
    gtk_grid_attach(g, NewLabel('Port', 1), 0, 2, 1, 1);
    d.SshP := gtk_spin_button_new_with_range(1, 65535, 1);
    gtk_spin_button_set_value(d.SshP, T.SshPort);
    gtk_grid_attach(g, d.SshP, 1, 2, 1, 1);
    gtk_box_pack_start(col, g, False, False, 6);
    gtk_box_pack_start(row, col, False, False, 0);
    gtk_box_pack_start(row, NewMarkupLabel('<span size="xx-large" foreground="#43a047">━━▶</span>', 0.5), False, False, 0);
    col := Column('network-server', 'Remote server', 64);
    d.RemoteBox := gtk_grid_new;
    gtk_grid_set_row_spacing(d.RemoteBox, 4);
    gtk_grid_set_column_spacing(d.RemoteBox, 4);
    gtk_grid_attach(d.RemoteBox, NewLabel('Host', 1), 0, 0, 1, 1);
    d.RemH := gtk_entry_new;
    gtk_entry_set_width_chars(d.RemH, 16);
    SetEntryText(d.RemH, T.RemoteHost);
    gtk_grid_attach(d.RemoteBox, d.RemH, 1, 0, 1, 1);
    gtk_grid_attach(d.RemoteBox, NewLabel('Port', 1), 0, 1, 1, 1);
    d.RemP := gtk_spin_button_new_with_range(1, 65535, 1);
    gtk_spin_button_set_value(d.RemP, T.RemotePort);
    gtk_grid_attach(d.RemoteBox, d.RemP, 1, 1, 1, 1);
    gtk_box_pack_start(col, d.RemoteBox, False, False, 6);
    gtk_box_pack_start(row, col, False, False, 0);
    gtk_box_pack_start(vbox, row, False, False, 8);

    g := gtk_grid_new;
    gtk_grid_set_row_spacing(g, 6);
    gtk_grid_set_column_spacing(g, 8);
    gtk_widget_set_halign(g, GTK_ALIGN_CENTER);
    gtk_grid_attach(g, NewLabel('Tunnel name', 1), 0, 0, 1, 1);
    d.NameE := gtk_entry_new;
    gtk_entry_set_width_chars(d.NameE, 30);
    SetEntryText(d.NameE, T.Name);
    gtk_grid_attach(g, d.NameE, 1, 0, 2, 1);
    gtk_grid_attach(g, NewLabel('Private key', 1), 0, 1, 1, 1);
    d.Key := gtk_entry_new;
    SetEntryText(d.Key, T.KeyFile);
    gtk_entry_set_placeholder_text(d.Key, 'optional');
    gtk_grid_attach(g, d.Key, 1, 1, 1, 1);
    b := NewFlatIconButton('document-open', 'Browse...', 16);
    Connect(b, 'clicked', @BrowseKey, d.Key);
    gtk_grid_attach(g, b, 2, 1, 1, 1);
    gtk_grid_attach(g, NewLabel('SSH password', 1), 0, 2, 1, 1);
    d.Pass := gtk_entry_new;
    gtk_entry_set_visibility(d.Pass, False);
    if T.HasPassword then gtk_entry_set_placeholder_text(d.Pass, '(saved - leave empty to keep it)')
    else gtk_entry_set_placeholder_text(d.Pass, 'optional (asked when needed)');
    gtk_grid_attach(g, d.Pass, 1, 2, 1, 1);
    d.SavePw := gtk_check_button_new_with_label('Save password');
    gtk_toggle_button_set_active(d.SavePw, True);
    gtk_grid_attach(g, d.SavePw, 2, 2, 1, 1);
    gtk_grid_attach(g, NewLabel('Expert SSH options', 1), 0, 3, 1, 1);
    d.Extra := gtk_entry_new;
    SetEntryText(d.Extra, T.ExtraOptions);
    gtk_entry_set_placeholder_text(d.Extra, 'e.g. -o Compression=yes');
    gtk_grid_attach(g, d.Extra, 1, 3, 2, 1);
    d.Auto := gtk_check_button_new_with_label('Start this tunnel automatically when LinXterm starts');
    gtk_toggle_button_set_active(d.Auto, T.AutoStart);
    gtk_grid_attach(g, d.Auto, 1, 4, 2, 1);
    gtk_box_pack_start(vbox, g, False, False, 0);

    gtk_container_add(area, vbox);
    gtk_dialog_add_button(d.Dlg, '_Cancel', GTK_RESPONSE_CANCEL);
    gtk_dialog_add_button(d.Dlg, '_Save', GTK_RESPONSE_OK);
    case T.Kind of
      'R': gtk_toggle_button_set_active(d.RadioR, True);
      'D': gtk_toggle_button_set_active(d.RadioD, True);
    else
      gtk_toggle_button_set_active(d.RadioL, True);
    end;
    Connect(d.RadioL, 'toggled', @KindToggledCb, d);
    Connect(d.RadioR, 'toggled', @KindToggledCb, d);
    Connect(d.RadioD, 'toggled', @KindToggledCb, d);
    d.KindChanged;
    gtk_widget_show_all(d.Dlg);
    while gtk_dialog_run(d.Dlg) = GTK_RESPONSE_OK do
    begin
      if Trim(EntryText(d.SshH)) = '' then
      begin
        MsgWarning('The SSH server is missing', '');
        Continue;
      end;
      if not gtk_toggle_button_get_active(d.RadioD) and (Trim(EntryText(d.RemH)) = '') then
      begin
        MsgWarning('The remote host is missing', '');
        Continue;
      end;
      if gtk_toggle_button_get_active(d.RadioR) then T.Kind := 'R'
      else if gtk_toggle_button_get_active(d.RadioD) then T.Kind := 'D'
      else T.Kind := 'L';
      gtk_spin_button_update(d.Fwd);
      gtk_spin_button_update(d.SshP);
      gtk_spin_button_update(d.RemP);
      T.FwdPort := gtk_spin_button_get_value_as_int(d.Fwd);
      T.BindAddr := CStr(gtk_combo_box_get_active_id(d.Bind));
      T.SshHost := Trim(EntryText(d.SshH));
      T.SshUser := Trim(EntryText(d.SshU));
      T.SshPort := gtk_spin_button_get_value_as_int(d.SshP);
      T.RemoteHost := Trim(EntryText(d.RemH));
      T.RemotePort := gtk_spin_button_get_value_as_int(d.RemP);
      T.KeyFile := Trim(EntryText(d.Key));
      T.ExtraOptions := Trim(EntryText(d.Extra));
      T.AutoStart := gtk_toggle_button_get_active(d.Auto);
      T.Name := Trim(EntryText(d.NameE));
      if T.Name = '' then T.Name := T.KindText + ' ' + IntToStr(T.FwdPort);
      pw := EntryText(d.Pass);
      if not gtk_toggle_button_get_active(d.SavePw) then
      begin
        if T.HasPassword then ForgetPassword('tunnel:' + T.Id);
        T.HasPassword := False;
      end
      else if pw <> '' then
        T.HasPassword := StorePassword('tunnel:' + T.Id, pw);
      Result := True;
      Break;
    end;
    gtk_widget_destroy(d.Dlg);
  finally
    d.Free;
  end;
end;

{ ---------------------------------------------------------------- window }

procedure TTunnelsUi.Refresh;
var
  i: Integer;
  t: TTunnel;
  it: TGtkTreeIter;
  icon, st: string;
  sel: TTunnel;
begin
  if Win = nil then Exit;
  sel := Selected;
  gtk_list_store_clear(Store);
  for i := 0 to Tunnels.Count - 1 do
  begin
    t := TTunnel(Tunnels[i]);
    case t.State of
      tsRunning: begin icon := 'lx-check'; st := 'running'; end;
      tsStarting: begin icon := 'lx-refresh'; st := 'starting...'; end;
      tsFailed: begin icon := 'dialog-warning'; st := 'failed: ' + t.LastError; end;
    else
      begin icon := 'lx-cancel'; st := 'stopped'; end;
    end;
    gtk_list_store_append(Store, @it);
    gtk_list_store_set(Store, @it, 0, IconPixbuf(icon, 16), 1, PChar(t.Name), 2, PChar(t.KindText),
      3, PChar(IntToStr(t.FwdPort)), 4, PChar(IfThen(t.SshUser <> '', t.SshUser + '@', '') + t.SshHost + ':' + IntToStr(t.SshPort)),
      5, PChar(IfThen(t.Kind = 'D', '-', t.RemoteHost + ':' + IntToStr(t.RemotePort))),
      6, PChar(IfThen(t.AutoStart, 'yes', '')), 7, PChar(st), 8, PChar(t.Id), -1);
    if t = sel then gtk_tree_selection_select_iter(gtk_tree_view_get_selection(View), @it);
  end;
end;

function TTunnelsUi.Selected: TTunnel;
var
  it: TGtkTreeIter;
  model: Pointer;
  p: PChar;
  id: string;
  i: Integer;
begin
  Result := nil;
  if View = nil then Exit;
  if not gtk_tree_selection_get_selected(gtk_tree_view_get_selection(View), @model, @it) then Exit;
  p := nil;
  gtk_tree_model_get(model, @it, 8, @p, -1);
  id := TakeStr(p);
  for i := 0 to Tunnels.Count - 1 do
    if TTunnel(Tunnels[i]).Id = id then Exit(TTunnel(Tunnels[i]));
end;

procedure BNew(b: Pointer; data: gpointer); cdecl;
var
  t: TTunnel;
begin
  t := TTunnel.Create;
  if EditTunnel(t, True) then
  begin
    Tunnels.Add(t);
    SaveTunnels;
    Ui.Refresh;
  end
  else
    t.Free;
end;

procedure BEdit(b: Pointer; data: gpointer); cdecl;
var
  t: TTunnel;
  wasRunning: Boolean;
begin
  t := Ui.Selected;
  if t = nil then Exit;
  wasRunning := t.State in [tsRunning, tsStarting];
  if EditTunnel(t, False) then
  begin
    SaveTunnels;
    if wasRunning then
    begin
      t.Stop;
      t.Start;
    end;
    Ui.Refresh;
  end;
end;

procedure BDelete(b: Pointer; data: gpointer); cdecl;
var
  t: TTunnel;
begin
  t := Ui.Selected;
  if (t = nil) or not AskYesNo('Delete the tunnel "' + t.Name + '"?', '') then Exit;
  t.Stop;
  if t.HasPassword then ForgetPassword('tunnel:' + t.Id);
  Tunnels.Remove(t);
  t.Free;
  SaveTunnels;
  Ui.Refresh;
end;

procedure BStart(b: Pointer; data: gpointer); cdecl;
var
  t: TTunnel;
begin
  t := Ui.Selected;
  if t <> nil then t.Start;
  Ui.Refresh;
end;

procedure BStop(b: Pointer; data: gpointer); cdecl;
var
  t: TTunnel;
begin
  t := Ui.Selected;
  if t <> nil then t.Stop;
  Ui.Refresh;
end;

procedure BStartAll(b: Pointer; data: gpointer); cdecl;
var
  i: Integer;
begin
  for i := 0 to Tunnels.Count - 1 do TTunnel(Tunnels[i]).Start;
  Ui.Refresh;
end;

procedure BStopAll(b: Pointer; data: gpointer); cdecl;
var
  i: Integer;
begin
  for i := 0 to Tunnels.Count - 1 do TTunnel(Tunnels[i]).Stop;
  Ui.Refresh;
end;

procedure RowActivated(view: Pointer; path: Pointer; col: Pointer; data: gpointer); cdecl;
begin
  BEdit(nil, nil);
end;

function WinDelete(w: Pointer; ev: Pointer; data: gpointer): gboolean; cdecl;
begin
  gtk_widget_hide(w);
  Result := True;
end;

function RefreshTimer(data: gpointer): gboolean; cdecl;
begin
  if (Ui <> nil) and gtk_widget_get_visible(Ui.Win) then Ui.Refresh;
  Result := True;
end;

procedure ShowTunnelsWindow;
var
  vbox, tb, b, col, cell: Pointer;
  types: array[0..8] of GType;
  i: Integer;
  titles: array[1..7] of string = ('Name', 'Type', 'Forwarded port', 'SSH server', 'Remote server', 'Autostart', 'Status');
  procedure Tool(const Icon, Text: string; Cb: Pointer);
  begin
    b := NewIconButton(Icon, Text, '', 16);
    Connect(b, 'clicked', Cb, nil);
    gtk_box_pack_start(tb, b, False, False, 0);
  end;
begin
  if Ui = nil then
  begin
    Ui := TTunnelsUi.Create;
    Ui.Win := gtk_window_new(GTK_WINDOW_TOPLEVEL);
    gtk_window_set_title(Ui.Win, 'MobaSSHTunnel - SSH tunnels (port forwarding)');
    gtk_window_set_default_size(Ui.Win, 960, 440);
    gtk_window_set_icon(Ui.Win, IconPixbuf('network-vpn', 64));
    gtk_window_set_transient_for(Ui.Win, MainWindowWidget);
    AddClass(Ui.Win, 'lx-main');
    vbox := gtk_box_new(GTK_ORIENTATION_VERTICAL, 8);
    SetMargins(vbox, 10);
    tb := gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 6);
    Tool('list-add', '_New SSH tunnel', @BNew);
    Tool('document-edit', '_Edit', @BEdit);
    Tool('lx-cancel', '_Delete', @BDelete);
    Tool('media-playback-start', 'S_tart', @BStart);
    Tool('media-playback-stop', 'St_op', @BStop);
    Tool('media-seek-forward', 'Start _all', @BStartAll);
    Tool('process-stop', 'Stop a_ll', @BStopAll);
    gtk_box_pack_start(vbox, tb, False, False, 0);
    types[0] := gdk_pixbuf_get_type;
    for i := 1 to 8 do types[i] := G_TYPE_STRING;
    Ui.Store := gtk_list_store_newv(9, @types[0]);
    Ui.View := gtk_tree_view_new_with_model(Ui.Store);
    g_object_unref(Ui.Store);
    col := gtk_tree_view_column_new;
    cell := gtk_cell_renderer_pixbuf_new;
    gtk_tree_view_column_pack_start(col, cell, False);
    gtk_tree_view_column_add_attribute(col, cell, 'pixbuf', 0);
    gtk_tree_view_append_column(Ui.View, col);
    for i := 1 to 7 do
    begin
      col := gtk_tree_view_column_new;
      gtk_tree_view_column_set_title(col, PChar(titles[i]));
      cell := gtk_cell_renderer_text_new;
      gtk_tree_view_column_pack_start(col, cell, True);
      gtk_tree_view_column_add_attribute(col, cell, 'text', i);
      gtk_tree_view_column_set_resizable(col, True);
      gtk_tree_view_append_column(Ui.View, col);
    end;
    Connect(Ui.View, 'row-activated', @RowActivated, nil);
    gtk_box_pack_start(vbox, NewScrolled(Ui.View), True, True, 0);
    gtk_box_pack_start(vbox, NewMarkupLabel('<small>Tunnels keep running when this window is closed. ' +
      'Double-click a tunnel to edit it.</small>', 0), False, False, 0);
    gtk_container_add(Ui.Win, vbox);
    Connect(Ui.Win, 'delete-event', @WinDelete, nil);
    g_timeout_add(1000, @RefreshTimer, nil);
  end;
  Ui.Refresh;
  gtk_widget_show_all(Ui.Win);
  gtk_window_present(Ui.Win);
end;

procedure AutoStartTunnels;
var
  i: Integer;
begin
  for i := 0 to Tunnels.Count - 1 do
    if TTunnel(Tunnels[i]).AutoStart then TTunnel(Tunnels[i]).Start;
end;

procedure StopAllTunnels;
var
  i: Integer;
begin
  for i := 0 to Tunnels.Count - 1 do TTunnel(Tunnels[i]).Stop;
end;

function TestHook(const Cmd, Arg: string): Boolean;
var
  t: TTunnel;
begin
  Result := False;
  if Cmd = 'tunnelnew' then
  begin
    { tunnelnew L|R|D fwdport sshhost sshport sshuser remotehost remoteport keyfile }
    t := TTunnel.Create;
    t.Kind := ExtractWord(1, Arg, [' ']);
    t.FwdPort := StrToIntDef(ExtractWord(2, Arg, [' ']), 8080);
    t.SshHost := ExtractWord(3, Arg, [' ']);
    t.SshPort := StrToIntDef(ExtractWord(4, Arg, [' ']), 22);
    t.SshUser := ExtractWord(5, Arg, [' ']);
    t.RemoteHost := ExtractWord(6, Arg, [' ']);
    t.RemotePort := StrToIntDef(ExtractWord(7, Arg, [' ']), 80);
    t.KeyFile := ExtractWord(8, Arg, [' ']);
    t.ExtraOptions := Trim(Copy(Arg, Pos(' -o ', Arg) + 1, MaxInt));
    if Pos(' -o ', Arg) = 0 then t.ExtraOptions := '';
    t.Name := 'Test ' + t.Kind + ' ' + IntToStr(t.FwdPort);
    Tunnels.Add(t);
    t.Start;
    if Ui <> nil then Ui.Refresh;
    Result := True;
  end;
end;

initialization
  LoadTunnels;
  ShowTunnelsProc := @ShowTunnelsWindow;
  RegisterStartup(@AutoStartTunnels);
  RegisterShutdown(@StopAllTunnels);
  SetLength(TestHooks, Length(TestHooks) + 1);
  TestHooks[High(TestHooks)] := @TestHook;

end.

{ LinXterm - VNC (embedded GTK-VNC display), RDP (FreeRDP client window)
  and web browser (WebKit2GTK) session tabs. }
unit lxremote;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, BaseUnix, lxgtk, lxutil, lxconfig, lxtabs, lxdyn;

type
  TVncTab = class(TTabPage)
  private
    FDisplay, FScroll, FStatus, FScaleBtn, FViewBtn, FOverlayMsg: Pointer;
    FError: string;
    FAskedPassword: Boolean;
    FClosing: Boolean;
    FReconnect: Boolean;     { reopen once the current connection is closed }
    procedure SetStatus(const Msg: string);
  public
    constructor Create(ASession: TSession);
    procedure Connect_;
    procedure Disconnect;
    procedure OnConnected;
    procedure OnInitialized;
    procedure OnDisconnected;
    procedure OnError(const Msg: string);
    procedure OnAuthFailure(const Msg: string);
    procedure OnCredential(Creds: PGValueArray);
    procedure SendCtrlAltDel;
    procedure Screenshot;
    procedure ToggleScaling;
    procedure ToggleViewOnly;
    procedure Shutdown; override;
    procedure FocusContent; override;
    function CanRestart: Boolean; override;
    procedure Restart; override;
  end;

  TRdpTab = class(TTabPage)
  private
    FProc: TChildProcess;
    FStatus, FLog, FTitle: Pointer;
    FLines: TStringList;
    FUserStopped: Boolean;
    procedure ProcLine(Sender: TChildProcess; const Line: string; IsErr: Boolean);
    procedure ProcExit(Sender: TChildProcess; Status: Integer);
  public
    constructor Create(ASession: TSession);
    destructor Destroy; override;
    procedure Launch;
    procedure Stop;
    procedure Shutdown; override;
    function CanRestart: Boolean; override;
    procedure Restart; override;
  end;

  TWebTab = class(TTabPage)
  private
    FView, FUrl, FBack, FForward: Pointer;
  public
    constructor Create(ASession: TSession);
    procedure Go(const Url: string);
    procedure Changed;
    procedure Shutdown; override;
    procedure FocusContent; override;
    function CanRestart: Boolean; override;
    procedure Restart; override;
  end;

implementation

uses
  StrUtils;

{ ---------------------------------------------------------------- VNC callbacks }

procedure VncConnectedCb(w: Pointer; data: gpointer); cdecl;
begin
  TVncTab(data).OnConnected;
end;

procedure VncInitializedCb(w: Pointer; data: gpointer); cdecl;
begin
  TVncTab(data).OnInitialized;
end;

procedure VncDisconnectedCb(w: Pointer; data: gpointer); cdecl;
begin
  TVncTab(data).OnDisconnected;
end;

procedure VncErrorCb(w: Pointer; msg: PChar; data: gpointer); cdecl;
begin
  TVncTab(data).OnError(CStr(msg));
end;

procedure VncAuthFailureCb(w: Pointer; msg: PChar; data: gpointer); cdecl;
begin
  TVncTab(data).OnAuthFailure(CStr(msg));
end;

procedure VncCredentialCb(w: Pointer; creds: PGValueArray; data: gpointer); cdecl;
begin
  TVncTab(data).OnCredential(creds);
end;

procedure VncCadCb(b: Pointer; data: gpointer); cdecl; begin TVncTab(data).SendCtrlAltDel; end;
procedure VncShotCb(b: Pointer; data: gpointer); cdecl; begin TVncTab(data).Screenshot; end;
procedure VncScaleCb(b: Pointer; data: gpointer); cdecl; begin TVncTab(data).ToggleScaling; end;
procedure VncViewCb(b: Pointer; data: gpointer); cdecl; begin TVncTab(data).ToggleViewOnly; end;
procedure VncReconnectCb(b: Pointer; data: gpointer); cdecl; begin TVncTab(data).Restart; end;
procedure VncDisconnectCb(b: Pointer; data: gpointer); cdecl; begin TVncTab(data).Disconnect; end;

{ ---------------------------------------------------------------- TVncTab }

constructor TVncTab.Create(ASession: TSession);
var
  tb, b, overlay: Pointer;
begin
  inherited Create(ASession);
  Page := gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
  tb := gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 2);
  AddClass(tb, 'lx-browser-toolbar');
  SetMargins(tb, 2);
  b := NewIconButton('preferences-desktop-keyboard', 'Ctrl+Alt+Del', 'Send Ctrl+Alt+Del to the remote computer', 16);
  gtk_button_set_relief(b, GTK_RELIEF_NONE);
  Connect(b, 'clicked', @VncCadCb, Self);
  gtk_box_pack_start(tb, b, False, False, 0);
  FScaleBtn := gtk_toggle_button_new_with_label('Fit to window');
  gtk_button_set_image(FScaleBtn, NewIcon('zoom-fit-best', 16));
  gtk_button_set_always_show_image(FScaleBtn, True);
  gtk_button_set_relief(FScaleBtn, GTK_RELIEF_NONE);
  gtk_toggle_button_set_active(FScaleBtn, Session.Scaling);
  Connect(FScaleBtn, 'toggled', @VncScaleCb, Self);
  gtk_box_pack_start(tb, FScaleBtn, False, False, 0);
  FViewBtn := gtk_toggle_button_new_with_label('View only');
  gtk_button_set_image(FViewBtn, NewIcon('lx-eye', 16));
  gtk_button_set_always_show_image(FViewBtn, True);
  gtk_button_set_relief(FViewBtn, GTK_RELIEF_NONE);
  gtk_toggle_button_set_active(FViewBtn, Session.ViewOnly);
  Connect(FViewBtn, 'toggled', @VncViewCb, Self);
  gtk_box_pack_start(tb, FViewBtn, False, False, 0);
  b := NewIconButton('camera-photo', 'Screenshot', 'Save a screenshot of the remote display', 16);
  gtk_button_set_relief(b, GTK_RELIEF_NONE);
  Connect(b, 'clicked', @VncShotCb, Self);
  gtk_box_pack_start(tb, b, False, False, 0);
  b := NewIconButton('lx-refresh', 'Reconnect', '', 16);
  gtk_button_set_relief(b, GTK_RELIEF_NONE);
  Connect(b, 'clicked', @VncReconnectCb, Self);
  gtk_box_pack_start(tb, b, False, False, 0);
  b := NewIconButton('lx-cancel', 'Disconnect', '', 16);
  gtk_button_set_relief(b, GTK_RELIEF_NONE);
  Connect(b, 'clicked', @VncDisconnectCb, Self);
  gtk_box_pack_start(tb, b, False, False, 0);
  FStatus := NewLabel('', 1);
  gtk_label_set_ellipsize(FStatus, PANGO_ELLIPSIZE_END);
  gtk_box_pack_end(tb, FStatus, True, True, 6);
  gtk_box_pack_start(Page, tb, False, False, 0);

  overlay := gtk_overlay_new;
  FScroll := gtk_scrolled_window_new(nil, nil);
  if Session.Scaling then
    gtk_scrolled_window_set_policy(FScroll, GTK_POLICY_NEVER, GTK_POLICY_NEVER)
  else
    gtk_scrolled_window_set_policy(FScroll, GTK_POLICY_AUTOMATIC, GTK_POLICY_AUTOMATIC);
  gtk_container_add(overlay, FScroll);
  FOverlayMsg := NewMarkupLabel('', 0.5);
  gtk_widget_set_halign(FOverlayMsg, GTK_ALIGN_CENTER);
  gtk_widget_set_valign(FOverlayMsg, GTK_ALIGN_CENTER);
  gtk_widget_set_no_show_all(FOverlayMsg, True);
  gtk_overlay_add_overlay(overlay, FOverlayMsg);
  gtk_box_pack_start(Page, overlay, True, True, 0);

  if VncAvailable then
  begin
    FDisplay := vnc_display_new();
    gtk_container_add(FScroll, FDisplay);
    Connect(FDisplay, 'vnc-connected', @VncConnectedCb, Self);
    Connect(FDisplay, 'vnc-initialized', @VncInitializedCb, Self);
    Connect(FDisplay, 'vnc-disconnected', @VncDisconnectedCb, Self);
    Connect(FDisplay, 'vnc-error', @VncErrorCb, Self);
    Connect(FDisplay, 'vnc-auth-failure', @VncAuthFailureCb, Self);
    Connect(FDisplay, 'vnc-auth-credential', @VncCredentialCb, Self);
  end;
  gtk_widget_show_all(Page);
  Connect_;
end;

procedure TVncTab.SetStatus(const Msg: string);
begin
  gtk_label_set_text(FStatus, PChar(Msg));
end;

procedure TVncTab.Connect_;
begin
  if FDisplay = nil then
  begin
    gtk_label_set_markup(FOverlayMsg, '<span size="large"><b>GTK-VNC is not installed</b></span>'#10 +
      'Install the "gtk-vnc2" package with the Packages button of the toolbar.');
    gtk_widget_show(FOverlayMsg);
    Exit;
  end;
  FError := '';
  FAskedPassword := False;
  FClosing := False;
  FReconnect := False;
  gtk_widget_hide(FOverlayMsg);
  vnc_display_set_scaling(FDisplay, Session.Scaling);
  vnc_display_set_read_only(FDisplay, Session.ViewOnly);
  vnc_display_set_keyboard_grab(FDisplay, True);
  vnc_display_set_pointer_grab(FDisplay, False);
  vnc_display_set_shared_flag(FDisplay, True);
  SetStatus('Connecting to ' + Session.Host + ':' + IntToStr(Session.Port) + '...');
  SetDisconnected(False);
  if not vnc_display_open_host(FDisplay, PChar(Session.Host), PChar(IntToStr(Session.Port))) then
    OnError('Unable to start the connection');
end;

procedure TVncTab.Disconnect;
begin
  if (FDisplay <> nil) and vnc_display_is_open(FDisplay) then
  begin
    FClosing := True;
    vnc_display_close(FDisplay);
  end;
end;

procedure TVncTab.OnConnected;
begin
  SetStatus('Connected, negotiating...');
end;

procedure TVncTab.OnInitialized;
var
  nm: string;
begin
  nm := CStr(vnc_display_get_name(FDisplay));
  SetStatus('Connected to "' + nm + '"  (' + IntToStr(vnc_display_get_width(FDisplay)) + 'x' +
    IntToStr(vnc_display_get_height(FDisplay)) + ')');
  gtk_widget_grab_focus(FDisplay);
end;

procedure TVncTab.OnDisconnected;
var
  msg: string;
begin
  if FReconnect then
  begin
    { "Reconnect" was clicked while connected: GTK-VNC closes asynchronously }
    FReconnect := False;
    Connect_;
    Exit;
  end;
  SetDisconnected(True);
  SetStatus('Disconnected');
  if FClosing then
    msg := '<span size="large"><b>VNC session closed</b></span>'
  else
  begin
    msg := '<span size="large"><b>VNC session to ' + MarkupEscape(Session.Host) + ' closed</b></span>';
    if FError <> '' then msg := msg + #10 + MarkupEscape(FError);
  end;
  msg := msg + #10#10'<span foreground="#888888">Click "Reconnect" to open the session again.</span>';
  gtk_label_set_markup(FOverlayMsg, PChar(msg));
  gtk_widget_show(FOverlayMsg);
  if App <> nil then App.TabChanged(Self);
end;

procedure TVncTab.OnError(const Msg: string);
begin
  FError := Msg;
  SetStatus('Error: ' + Msg);
end;

procedure TVncTab.OnAuthFailure(const Msg: string);
begin
  FError := 'Authentication failed' + IfThen(Msg <> '', ': ' + Msg, '');
  { the stored password is wrong: ask next time }
  FAskedPassword := True;
end;

procedure TVncTab.OnCredential(Creds: PGValueArray);
var
  i: Integer;
  typ: gint;
  pw, user: string;
  v: PGValue;
begin
  if Creds = nil then Exit;
  for i := 0 to Creds^.n_values - 1 do
  begin
    v := PGValue(PByte(Creds^.values) + i * SizeOf(TGValue));
    typ := g_value_get_enum(v);
    case typ of
      VNC_DISPLAY_CREDENTIAL_PASSWORD:
        begin
          pw := '';
          if Session.HasPassword and not FAskedPassword then
            LookupPassword(Session.PasswordKey, pw)
          else if not InputQuery('VNC authentication', 'Password for ' + Session.Host + ':', pw, True) then
          begin
            FClosing := True;
            vnc_display_close(FDisplay);
            Exit;
          end;
          FAskedPassword := True;
          vnc_display_set_credential(FDisplay, VNC_DISPLAY_CREDENTIAL_PASSWORD, PChar(pw));
        end;
      VNC_DISPLAY_CREDENTIAL_USERNAME:
        begin
          user := Session.User;
          if user = '' then
            if not InputQuery('VNC authentication', 'User name for ' + Session.Host + ':', user) then
            begin
              FClosing := True;
              vnc_display_close(FDisplay);
              Exit;
            end;
          vnc_display_set_credential(FDisplay, VNC_DISPLAY_CREDENTIAL_USERNAME, PChar(user));
        end;
      VNC_DISPLAY_CREDENTIAL_CLIENTNAME:
        vnc_display_set_credential(FDisplay, VNC_DISPLAY_CREDENTIAL_CLIENTNAME, 'linxterm');
    end;
  end;
end;

procedure TVncTab.SendCtrlAltDel;
var
  keys: array[0..2] of guint;
begin
  if (FDisplay = nil) or not vnc_display_is_open(FDisplay) then Exit;
  keys[0] := GDK_KEY_Control_L;
  keys[1] := GDK_KEY_Alt_L;
  keys[2] := GDK_KEY_Delete;
  vnc_display_send_keys(FDisplay, @keys[0], 3);
end;

procedure TVncTab.Screenshot;
var
  pb: Pointer;
  fn: string;
  err: PGError;
begin
  if (FDisplay = nil) or not vnc_display_is_open(FDisplay) then Exit;
  pb := vnc_display_get_pixbuf(FDisplay);
  if pb = nil then Exit;
  if ChooseSaveFile('Save screenshot', HomeDir, Session.Host + '-screenshot.png', fn) then
  begin
    err := nil;
    if not gdk_pixbuf_save(pb, PChar(fn), 'png', @err, nil) then
      MsgError('Unable to save the screenshot', ErrMsg(err));
  end;
  g_object_unref(pb);
end;

procedure TVncTab.ToggleScaling;
begin
  Session.Scaling := gtk_toggle_button_get_active(FScaleBtn);
  if FDisplay <> nil then vnc_display_set_scaling(FDisplay, Session.Scaling);
  if Session.Scaling then
    gtk_scrolled_window_set_policy(FScroll, GTK_POLICY_NEVER, GTK_POLICY_NEVER)
  else
    gtk_scrolled_window_set_policy(FScroll, GTK_POLICY_AUTOMATIC, GTK_POLICY_AUTOMATIC);
end;

procedure TVncTab.ToggleViewOnly;
begin
  Session.ViewOnly := gtk_toggle_button_get_active(FViewBtn);
  if FDisplay <> nil then vnc_display_set_read_only(FDisplay, Session.ViewOnly);
end;

procedure TVncTab.Shutdown;
begin
  if FDisplay <> nil then
  begin
    g_signal_handlers_disconnect_matched(FDisplay, G_SIGNAL_MATCH_DATA, 0, 0, nil, nil, Self);
    if vnc_display_is_open(FDisplay) then vnc_display_close(FDisplay);
  end;
end;

procedure TVncTab.FocusContent;
begin
  if FDisplay <> nil then gtk_widget_grab_focus(FDisplay);
end;

function TVncTab.CanRestart: Boolean;
begin
  Result := True;
end;

procedure TVncTab.Restart;
begin
  if (FDisplay <> nil) and vnc_display_is_open(FDisplay) then
  begin
    FClosing := True;
    FReconnect := True;
    SetStatus('Reconnecting...');
    vnc_display_close(FDisplay);
    Exit;
  end;
  Connect_;
end;

{ ---------------------------------------------------------------- RDP }

procedure RdpReconnectCb(b: Pointer; data: gpointer); cdecl; begin TRdpTab(data).Restart; end;
procedure RdpStopCb(b: Pointer; data: gpointer); cdecl; begin TRdpTab(data).Stop; end;

constructor TRdpTab.Create(ASession: TSession);
var
  col, hb, b, exp, scroll: Pointer;
begin
  inherited Create(ASession);
  FLines := TStringList.Create;
  Page := gtk_event_box_new;
  AddClass(Page, 'lx-home');
  col := gtk_box_new(GTK_ORIENTATION_VERTICAL, 12);
  gtk_widget_set_halign(col, GTK_ALIGN_CENTER);
  gtk_widget_set_valign(col, GTK_ALIGN_CENTER);
  gtk_widget_set_size_request(col, 600, -1);
  gtk_box_pack_start(col, NewIcon('krdc', 96), False, False, 0);
  FTitle := NewMarkupLabel('<span size="x-large"><b>Remote desktop: ' + MarkupEscape(Session.Target) + '</b></span>', 0.5);
  gtk_box_pack_start(col, FTitle, False, False, 0);
  FStatus := NewMarkupLabel('', 0.5);
  gtk_label_set_line_wrap(FStatus, True);
  gtk_box_pack_start(col, FStatus, False, False, 0);
  hb := gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 12);
  gtk_widget_set_halign(hb, GTK_ALIGN_CENTER);
  b := NewIconButton('lx-refresh', '_Reconnect', '', 16);
  Connect(b, 'clicked', @RdpReconnectCb, Self);
  gtk_box_pack_start(hb, b, False, False, 0);
  b := NewIconButton('lx-cancel', '_Disconnect', '', 16);
  Connect(b, 'clicked', @RdpStopCb, Self);
  gtk_box_pack_start(hb, b, False, False, 0);
  gtk_box_pack_start(col, hb, False, False, 0);
  exp := gtk_expander_new('Connection log');
  FLog := gtk_text_view_new;
  gtk_text_view_set_editable(FLog, False);
  gtk_text_view_set_monospace(FLog, True);
  gtk_text_view_set_wrap_mode(FLog, GTK_WRAP_CHAR);
  scroll := NewScrolled(FLog);
  gtk_widget_set_size_request(scroll, 600, 200);
  gtk_container_add(exp, scroll);
  gtk_box_pack_start(col, exp, False, False, 0);
  gtk_container_add(Page, col);
  gtk_widget_show_all(Page);
  Launch;
end;

destructor TRdpTab.Destroy;
begin
  FLines.Free;
  inherited Destroy;
end;

var
  RdpVersionClient: string = '';
  RdpVersionMajor: Integer = 0;

{ major version of the FreeRDP client (FreeRDP 3 reads its arguments from
  the environment, which keeps the password out of the process list) }
function RdpMajorVersion(const Client: string): Integer;
var
  o: string;
  p: Integer;
begin
  if Client <> RdpVersionClient then
  begin
    RdpVersionClient := Client;
    RdpVersionMajor := 0;
    RunCapture([Client, '/version'], o);
    p := Pos('version ', LowerCase(o));
    if p > 0 then RdpVersionMajor := StrToIntDef(Copy(o, p + 8, 1), 0);
  end;
  Result := RdpVersionMajor;
end;

function FindRdpClient: string;
begin
  Result := FindProgram('xfreerdp3');
  if Result = '' then Result := FindProgram('xfreerdp');
  if Result = '' then Result := FindProgram('sdl-freerdp3');
  if Result = '' then Result := FindProgram('sdl-freerdp');
  if Result = '' then Result := FindProgram('wlfreerdp');
end;

procedure TRdpTab.Launch;
var
  client, pw, err, res, list: string;
  args, env: TStringArray;
  argc: gint;
  argv: PPChar;
  gerr: PGError;
  i: Integer;
  procedure Add(const A: string);
  begin
    SetLength(args, Length(args) + 1);
    args[High(args)] := A;
  end;
begin
  FUserStopped := False;
  client := FindRdpClient;
  if client = '' then
  begin
    gtk_label_set_markup(FStatus, '<span foreground="#c62828"><b>FreeRDP is not installed.</b></span>'#10 +
      'Install the "freerdp" package with the Packages button of the toolbar.');
    SetDisconnected(True);
    Exit;
  end;
  pw := '';
  if Session.HasPassword then
    LookupPassword(Session.PasswordKey, pw)
  else if not InputQuery('Remote desktop', 'Password for ' + IfThen(Session.User <> '', Session.User + '@', '') +
    Session.Host + ' (leave empty to type it in the remote login screen):', pw, True) then
  begin
    gtk_label_set_markup(FStatus, 'Connection cancelled.');
    SetDisconnected(True);
    Exit;
  end;
  args := nil;
  Add(client);
  Add('/v:' + Session.Host + ':' + IntToStr(Session.Port));
  if Session.User <> '' then Add('/u:' + Session.User);
  if Session.Domain <> '' then Add('/d:' + Session.Domain);
  if pw <> '' then Add('/p:' + pw);
  Add('/cert:tofu');
  Add('/title:' + APP_NAME + ' - ' + Session.DisplayName);
  res := Session.Resolution;
  if res = 'fullscreen' then Add('/f')
  else if (res <> '') and (res <> 'dynamic') then Add('/size:' + res)
  else
  begin
    Add('/dynamic-resolution');
    Add('/size:1366x768');
  end;
  if Session.RdpClipboard then Add('+clipboard') else Add('-clipboard');
  if Session.RdpHomeDrive then Add('/drive:home,' + HomeDir);
  if Session.RdpSound then Add('/sound');
  Add('+auto-reconnect');
  if Trim(Session.RdpExtra) <> '' then
  begin
    gerr := nil;
    argv := nil;
    if g_shell_parse_argv(PChar(Session.RdpExtra), @argc, @argv, @gerr) then
    begin
      for i := 0 to argc - 1 do Add(AnsiString(argv[i]));
      g_strfreev(argv);
    end
    else
      ErrMsg(gerr);
  end;
  FLines.Clear;
  gtk_text_buffer_set_text(gtk_text_view_get_buffer(FLog), '', 0);
  if FProc <> nil then
  begin
    FProc.OnExit := nil;
    FProc.OnLine := nil;
    FreeAndNil(FProc);
  end;
  FProc := TChildProcess.Create;
  FProc.OnLine := @ProcLine;
  FProc.OnExit := @ProcExit;
  env := nil;
  if RdpMajorVersion(client) >= 3 then
  begin
    { one argument per line in a private environment variable instead of
      the command line, where any local user could read the password }
    list := '';
    for i := 1 to High(args) do
      list := list + StringReplace(StringReplace(args[i], #13, '', [rfReplaceAll]), #10, '', [rfReplaceAll]) + #10;
    SetLength(env, 1);
    env[0] := 'LINXTERM_RDP_ARGS=' + list;
    SetLength(args, 2);
    args[1] := '/args-from:env:LINXTERM_RDP_ARGS';
  end;
  if not FProc.Start(args, env, HomeDir, False, err) then
  begin
    gtk_label_set_markup(FStatus, PChar('<span foreground="#c62828"><b>Unable to start ' + MarkupEscape(client) +
      '</b></span>'#10 + MarkupEscape(err)));
    SetDisconnected(True);
    Exit;
  end;
  SetDisconnected(False);
  gtk_label_set_markup(FStatus, PChar('<span foreground="#2e7d32"><b>Session started</b></span> - the remote desktop ' +
    'opens in its own window (' + MarkupEscape(ExtractFileName(client)) + ').'#10 +
    '<span foreground="#888888">Closing that window ends the session.</span>'));
end;

procedure TRdpTab.ProcLine(Sender: TChildProcess; const Line: string; IsErr: Boolean);
begin
  if Trim(Line) = '' then Exit;
  FLines.Add(Line);
  if FLines.Count > 500 then FLines.Delete(0);
  TextViewAppend(FLog, Line + #10);
end;

procedure TRdpTab.ProcExit(Sender: TChildProcess; Status: Integer);
var
  all, hint: string;
begin
  SetDisconnected(True);
  all := UpperCase(FLines.Text);
  hint := '';
  if Pos('LOGON_FAILURE', all) > 0 then hint := 'Authentication failed: check the user name and the password.'
  else if (Pos('CONNECT_TRANSPORT_FAILED', all) > 0) or (Pos('ERRCONNECT_CONNECT_FAILED', all) > 0) then
    hint := 'Unable to reach ' + Session.Host + ':' + IntToStr(Session.Port) + '.'
  else if Pos('DNS', all) > 0 then hint := 'Unable to resolve the host name.'
  else if Pos('CERTIFICATE', all) > 0 then hint := 'Certificate problem (see the connection log).';
  if FUserStopped then
    gtk_label_set_markup(FStatus, '<b>Session closed.</b>')
  else if (Status = 0) or (Status = 12) then
    gtk_label_set_markup(FStatus, '<b>The remote desktop session has ended.</b>')
  else
    gtk_label_set_markup(FStatus, PChar('<span foreground="#c62828"><b>The RDP client stopped (code ' + IntToStr(Status) +
      ').</b></span>' + IfThen(hint <> '', #10 + MarkupEscape(hint), '') +
      #10'<span foreground="#888888">Open "Connection log" for details.</span>'));
  if App <> nil then App.TabChanged(Self);
end;

procedure TRdpTab.Stop;
begin
  if (FProc <> nil) and FProc.Running then
  begin
    FUserStopped := True;
    FProc.Signal(SIGTERM);
  end;
end;

procedure TRdpTab.Shutdown;
begin
  if FProc <> nil then
  begin
    FProc.OnExit := nil;
    FProc.OnLine := nil;
    FreeAndNil(FProc);
  end;
end;

function TRdpTab.CanRestart: Boolean;
begin
  Result := True;
end;

procedure TRdpTab.Restart;
begin
  if (FProc <> nil) and FProc.Running then
  begin
    FProc.OnExit := nil;
    FProc.OnLine := nil;
    FreeAndNil(FProc);
  end;
  Launch;
end;

{ ---------------------------------------------------------------- Web }

procedure WebBackCb(b: Pointer; data: gpointer); cdecl;
begin
  if TWebTab(data).FView <> nil then webkit_web_view_go_back(TWebTab(data).FView);
end;

procedure WebForwardCb(b: Pointer; data: gpointer); cdecl;
begin
  if TWebTab(data).FView <> nil then webkit_web_view_go_forward(TWebTab(data).FView);
end;

procedure WebReloadCb(b: Pointer; data: gpointer); cdecl;
begin
  if TWebTab(data).FView <> nil then webkit_web_view_reload(TWebTab(data).FView);
end;

procedure WebExternalCb(b: Pointer; data: gpointer); cdecl;
begin
  OpenUri(EntryText(TWebTab(data).FUrl));
end;

procedure WebUrlActivate(e: Pointer; data: gpointer); cdecl;
begin
  TWebTab(data).Go(Trim(EntryText(e)));
end;

procedure WebLoadChanged(v: Pointer; ev: gint; data: gpointer); cdecl;
begin
  TWebTab(data).Changed;
end;

procedure WebTitleChanged(v: Pointer; spec: Pointer; data: gpointer); cdecl;
begin
  TWebTab(data).Changed;
end;

constructor TWebTab.Create(ASession: TSession);
var
  tb, b: Pointer;
begin
  inherited Create(ASession);
  Page := gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
  tb := gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 2);
  SetMargins(tb, 3);
  FBack := NewFlatIconButton('go-previous', 'Back', 16);
  Connect(FBack, 'clicked', @WebBackCb, Self);
  gtk_box_pack_start(tb, FBack, False, False, 0);
  FForward := NewFlatIconButton('go-next', 'Forward', 16);
  Connect(FForward, 'clicked', @WebForwardCb, Self);
  gtk_box_pack_start(tb, FForward, False, False, 0);
  b := NewFlatIconButton('lx-refresh', 'Reload', 16);
  Connect(b, 'clicked', @WebReloadCb, Self);
  gtk_box_pack_start(tb, b, False, False, 0);
  FUrl := gtk_entry_new;
  Connect(FUrl, 'activate', @WebUrlActivate, Self);
  gtk_box_pack_start(tb, FUrl, True, True, 4);
  b := NewFlatIconButton('web-browser', 'Open in the default web browser', 16);
  Connect(b, 'clicked', @WebExternalCb, Self);
  gtk_box_pack_start(tb, b, False, False, 0);
  gtk_box_pack_start(Page, tb, False, False, 0);
  if WebKitAvailable then
  begin
    FView := webkit_web_view_new();
    Connect(FView, 'load-changed', @WebLoadChanged, Self);
    Connect(FView, 'notify::title', @WebTitleChanged, Self);
    gtk_box_pack_start(Page, FView, True, True, 0);
  end
  else
    gtk_box_pack_start(Page, NewMarkupLabel('<b>WebKit2GTK is not installed.</b>'#10 +
      'The page was opened in your default web browser.', 0.5), True, True, 0);
  gtk_widget_show_all(Page);
  Go(Session.Url);
end;

procedure TWebTab.Go(const Url: string);
var
  u: string;
begin
  u := Url;
  if u = '' then Exit;
  if Pos('://', u) = 0 then u := 'https://' + u;
  SetEntryText(FUrl, u);
  if FView <> nil then
    webkit_web_view_load_uri(FView, PChar(u))
  else
    OpenUri(u);
end;

procedure TWebTab.Changed;
var
  t: string;
begin
  if FView = nil then Exit;
  SetEntryText(FUrl, CStr(webkit_web_view_get_uri(FView)));
  gtk_widget_set_sensitive(FBack, webkit_web_view_can_go_back(FView));
  gtk_widget_set_sensitive(FForward, webkit_web_view_can_go_forward(FView));
  t := CStr(webkit_web_view_get_title(FView));
  if (t <> '') and not UserTitle and (Session.Name = '') then SetTitle(t);
end;

procedure TWebTab.Shutdown;
begin
  if FView <> nil then
  begin
    g_signal_handlers_disconnect_matched(FView, G_SIGNAL_MATCH_DATA, 0, 0, nil, nil, Self);
    webkit_web_view_stop_loading(FView);
  end;
end;

procedure TWebTab.FocusContent;
begin
  if FView <> nil then gtk_widget_grab_focus(FView);
end;

function TWebTab.CanRestart: Boolean;
begin
  Result := True;
end;

procedure TWebTab.Restart;
begin
  if FView <> nil then webkit_web_view_reload(FView);
end;

function CreateVnc(S: TSession): TTabPage;
begin
  Result := TVncTab.Create(S);
end;

function CreateRdp(S: TSession): TTabPage;
begin
  Result := TRdpTab.Create(S);
end;

function CreateWeb(S: TSession): TTabPage;
begin
  Result := TWebTab.Create(S);
end;

initialization
  CreateVncTabProc := @CreateVnc;
  CreateRdpTabProc := @CreateRdp;
  CreateWebTabProc := @CreateWeb;

end.

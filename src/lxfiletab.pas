{ LinXterm - SFTP, FTP and File session tabs: dual-pane file manager with
  the local computer on the left and the server on the right. }
unit lxfiletab;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, BaseUnix, lxgtk, lxutil, lxconfig, lxtabs, lxterminal, lxfs, lxbrowser;

type
  TFileTab = class(TTabPage)
  private
    FLocal, FRemote: TFileBrowser;
    FMaster: TChildProcess;
    FControlPath: string;
    FPassFile: string;
    FWaitTimer: guint;
    FErrors: string;
    FRemoteLabel: Pointer;
    procedure StartRemote;
    procedure MasterLine(Sender: TChildProcess; const Line: string; IsErr: Boolean);
    procedure MasterExit(Sender: TChildProcess; Status: Integer);
    procedure StopMaster;
  public
    constructor Create(ASession: TSession);
    procedure CheckMaster;
    procedure Shutdown; override;
    procedure FocusContent; override;
    function CanRestart: Boolean; override;
    procedure Restart; override;
  end;

implementation

function WaitCb(data: gpointer): gboolean; cdecl;
begin
  TFileTab(data).CheckMaster;
  Result := TFileTab(data).FWaitTimer <> 0;
end;

procedure ToRemoteCb(b: Pointer; data: gpointer); cdecl;
var
  t: TFileTab;
begin
  t := TFileTab(data);
  if (t.FRemote <> nil) and t.FRemote.Connected then
    t.FRemote.UploadFiles(nil, '');
end;

procedure ToLocalCb(b: Pointer; data: gpointer); cdecl;
var
  t: TFileTab;
begin
  t := TFileTab(data);
  if (t.FRemote <> nil) and t.FRemote.Connected and (t.FLocal <> nil) then
    t.FRemote.DownloadSelected(t.FLocal.Path);
end;

function PaneHeader(const Icon, Markup: string; out Lbl: Pointer): Pointer;
begin
  Result := gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 6);
  AddClass(Result, 'lx-panel-title');
  gtk_box_pack_start(Result, NewIcon(Icon, 16), False, False, 0);
  Lbl := NewMarkupLabel(Markup, 0);
  gtk_label_set_ellipsize(Lbl, PANGO_ELLIPSIZE_END);
  gtk_box_pack_start(Result, Lbl, True, True, 0);
end;

constructor TFileTab.Create(ASession: TSession);
var
  paned, left, right, mid, b, hdr, dummy: Pointer;
  start: string;
begin
  inherited Create(ASession);
  Page := gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
  FLocal := TFileBrowser.Create(False);
  if Session.Kind = skFile then
  begin
    hdr := PaneHeader('computer', '<b>Local folder</b>', dummy);
    gtk_box_pack_start(Page, hdr, False, False, 0);
    gtk_box_pack_start(Page, FLocal.Widget, True, True, 0);
    start := Session.StartDir;
    if (start = '') or not DirectoryExists(start) then start := HomeDir;
    FLocal.SetBackend(TLocalFs.Create, start, 0);
  end
  else
  begin
    paned := gtk_paned_new(GTK_ORIENTATION_HORIZONTAL);
    { left column: local computer }
    hdr := gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
    gtk_box_pack_start(hdr, PaneHeader('computer', '<b>My computer</b>', dummy), False, False, 0);
    gtk_box_pack_start(hdr, FLocal.Widget, True, True, 0);
    { transfer arrows }
    mid := gtk_box_new(GTK_ORIENTATION_VERTICAL, 8);
    gtk_widget_set_valign(mid, GTK_ALIGN_CENTER);
    SetMargins(mid, 4);
    b := NewIconButton('go-next', '', 'Upload the selected local files', 24);
    Connect(b, 'clicked', @ToRemoteCb, Self);
    gtk_box_pack_start(mid, b, False, False, 0);
    b := NewIconButton('go-previous', '', 'Download the selected remote files', 24);
    Connect(b, 'clicked', @ToLocalCb, Self);
    gtk_box_pack_start(mid, b, False, False, 0);
    left := gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0);
    gtk_box_pack_start(left, hdr, True, True, 0);
    gtk_box_pack_start(left, mid, False, False, 0);
    { right column: the server }
    FRemote := TFileBrowser.Create(False);
    right := gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
    gtk_box_pack_start(right, PaneHeader(Session.IconName, '<b>' + MarkupEscape(SessionKindNames[Session.Kind] +
      '://' + Session.Target) + '</b>', FRemoteLabel), False, False, 0);
    gtk_box_pack_start(right, FRemote.Widget, True, True, 0);
    FLocal.Peer := FRemote;
    FRemote.Peer := FLocal;
    gtk_paned_pack1(paned, left, True, False);
    gtk_paned_pack2(paned, right, True, False);
    gtk_paned_set_position(paned, 560);
    gtk_box_pack_start(Page, paned, True, True, 0);
    FLocal.SetBackend(TLocalFs.Create, HomeDir, 0);
  end;
  gtk_widget_show_all(Page);
  if Session.Kind <> skFile then
    StartRemote;
end;

procedure TFileTab.StartRemote;
var
  pw, err: string;
  s: TSession;
  args, env: TStringArray;
begin
  FErrors := '';
  SetDisconnected(False);
  pw := '';
  if Session.HasPassword then LookupPassword(Session.PasswordKey, pw);
  if Session.Kind = skFTP then
  begin
    FRemote.SetBackend(TFtpFs.Create(Session.Host, Session.Port, Session.User, pw, Session.FtpPassive), '', 0);
    Exit;
  end;
  { SFTP: open a background SSH master connection, then browse through it }
  StopMaster;
  FControlPath := RuntimeDir + '/cm-' + RandomToken(10);
  s := Session.Clone;
  try
    s.X11 := False;
    s.AgentForward := False;
    s.RemoteCommand := '';
    args := BuildSshArgs(s, FControlPath, True);
  finally
    s.Free;
  end;
  env := nil;
  if pw <> '' then FPassFile := WriteSecretFile(pw);
  SetLength(env, 3);
  env[0] := 'SSH_ASKPASS=' + HelperPath('lxaskpass');
  env[1] := 'SSH_ASKPASS_REQUIRE=force';
  env[2] := 'LINXTERM_PASSFILE=' + FPassFile;
  FMaster := TChildProcess.Create;
  FMaster.OnLine := @MasterLine;
  FMaster.OnExit := @MasterExit;
  FRemote.ShowMessage('<span foreground="#888888">Connecting to ' + MarkupEscape(Session.Target) + '...</span>');
  if not FMaster.Start(args, env, HomeDir, False, err) then
  begin
    FRemote.ShowMessage('<span foreground="#c62828"><b>Unable to start ssh</b></span>'#10 + MarkupEscape(err));
    Exit;
  end;
  FWaitTimer := g_timeout_add(300, @WaitCb, Self);
end;

procedure TFileTab.MasterLine(Sender: TChildProcess; const Line: string; IsErr: Boolean);
begin
  if Trim(Line) <> '' then
    FErrors := FErrors + Trim(Line) + #10;
end;

procedure TFileTab.MasterExit(Sender: TChildProcess; Status: Integer);
var
  msg: string;
begin
  if FWaitTimer <> 0 then
  begin
    g_source_remove(FWaitTimer);
    FWaitTimer := 0;
  end;
  SecureDelete(FPassFile);
  FPassFile := '';
  SetDisconnected(True);
  msg := Trim(FErrors);
  if msg = '' then msg := 'ssh exited with code ' + IntToStr(Status);
  FRemote.ShowMessage('<span foreground="#c62828"><b>SFTP connection closed</b></span>'#10 + MarkupEscape(msg) +
    #10#10'<span foreground="#888888">Right-click the tab and choose "Restart session" to reconnect.</span>');
  if App <> nil then App.TabChanged(Self);
end;

procedure TFileTab.CheckMaster;
var
  args: TStringArray;
begin
  if (FMaster = nil) or not FMaster.Running then Exit;
  if fpAccess(FControlPath, F_OK) <> 0 then Exit;
  g_source_remove(FWaitTimer);
  FWaitTimer := 0;
  SecureDelete(FPassFile);
  FPassFile := '';
  args := SshMuxArgs(Session, FControlPath);
  SetLength(args, Length(args) + 4);
  args[High(args) - 3] := '-s';
  args[High(args) - 2] := '--';
  args[High(args) - 1] := Session.Host;
  args[High(args)] := 'sftp';
  FRemote.SetBackend(TSftpFs.Create(args, 'sftp://' + Session.Target), '', 0);
end;

procedure TFileTab.StopMaster;
begin
  if FWaitTimer <> 0 then
  begin
    g_source_remove(FWaitTimer);
    FWaitTimer := 0;
  end;
  if FMaster <> nil then
  begin
    FMaster.OnExit := nil;
    FMaster.OnLine := nil;
    FMaster.Free;   { terminates the ssh master if still running }
    FMaster := nil;
  end;
  SecureDelete(FPassFile);
  FPassFile := '';
end;

procedure TFileTab.Shutdown;
begin
  StopMaster;
  if FLocal <> nil then FLocal.Peer := nil;
  if FRemote <> nil then FRemote.Peer := nil;
  FreeAndNil(FRemote);
  FreeAndNil(FLocal);
end;

procedure TFileTab.FocusContent;
begin
end;

function TFileTab.CanRestart: Boolean;
begin
  Result := Session.Kind <> skFile;
end;

procedure TFileTab.Restart;
begin
  if Session.Kind = skFile then
  begin
    FLocal.Refresh;
    Exit;
  end;
  StartRemote;
end;

function CreateFileTab(S: TSession): TTabPage;
begin
  Result := TFileTab.Create(S);
end;

initialization
  CreateFileTabProc := @CreateFileTab;

end.

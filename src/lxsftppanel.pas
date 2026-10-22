{ LinXterm - "Sftp" side panel: graphical SFTP browser bound to the current
  SSH terminal (reuses the authenticated SSH connection), or a local file
  browser for local terminals. }
unit lxsftppanel;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, StrUtils, lxgtk, lxutil, lxconfig, lxtabs, lxterminal, lxfs, lxbrowser;

implementation

type
  TSftpPanel = class
  public
    Widget: Pointer;
    Stack: Pointer;
    Message: Pointer;
    Browsers: TList;
    Current: TTabPage;
    Guard: Boolean;
    constructor Create;
    function BrowserFor(Tab: TTabPage): TFileBrowser;
    procedure ShowMsg(const Markup: string);
    procedure ShowTab(Tab: TTabPage);
    procedure TabClosed(Tab: TTabPage);
    procedure DropBrowser(B: TFileBrowser);
  end;

var
  Panel: TSftpPanel = nil;

procedure FollowToggled(check: Pointer; data: gpointer); cdecl;
var
  b: TFileBrowser;
  t: TTerminalTab;
begin
  b := TFileBrowser(data);
  Settings.FollowTerminalFolder := gtk_toggle_button_get_active(check);
  Settings.Save;
  if Settings.FollowTerminalFolder and (TObject(b.Tag) is TTerminalTab) then
  begin
    t := TTerminalTab(b.Tag);
    if t.IsSsh and (t.RemoteDir <> '') then b.Navigate(t.RemoteDir, True)
    else if t.IsLocalShell and (t.CurrentDir <> '') then b.Navigate(t.CurrentDir, True);
  end;
end;

procedure MonitorToggled(check: Pointer; data: gpointer); cdecl;
var
  b: TFileBrowser;
begin
  if Panel.Guard then Exit;
  b := TFileBrowser(data);
  Settings.RemoteMonitoring := gtk_toggle_button_get_active(check);
  Settings.Save;
  if TObject(b.Tag) is TTerminalTab then
    TTerminalTab(b.Tag).SetMonitoring(Settings.RemoteMonitoring);
end;

constructor TSftpPanel.Create;
begin
  inherited Create;
  Browsers := TList.Create;
  Widget := gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
  Stack := gtk_stack_new;
  Message := NewMarkupLabel('', 0.5);
  gtk_label_set_line_wrap(Message, True);
  gtk_label_set_justify(Message, GTK_JUSTIFY_CENTER);
  gtk_widget_set_valign(Message, GTK_ALIGN_CENTER);
  SetMargins(Message, 14);
  gtk_stack_add_named(Stack, Message, 'message');
  gtk_box_pack_start(Widget, Stack, True, True, 0);
  ShowMsg('<span foreground="#888888">Open an SSH session to browse the remote files here.</span>');
  gtk_widget_show_all(Widget);
end;

procedure TSftpPanel.ShowMsg(const Markup: string);
begin
  gtk_label_set_markup(Message, PChar(Markup));
  gtk_stack_set_visible_child_name(Stack, 'message');
end;

function TSftpPanel.BrowserFor(Tab: TTabPage): TFileBrowser;
var
  i: Integer;
begin
  for i := 0 to Browsers.Count - 1 do
    if TFileBrowser(Browsers[i]).Tag = Pointer(Tab) then
      Exit(TFileBrowser(Browsers[i]));
  Result := nil;
end;

procedure TSftpPanel.DropBrowser(B: TFileBrowser);
begin
  Browsers.Remove(B);
  if gtk_widget_get_parent(B.Widget) = Stack then
    gtk_container_remove(Stack, B.Widget);
  B.Free;
end;

procedure TSftpPanel.ShowTab(Tab: TTabPage);
var
  t: TTerminalTab;
  b: TFileBrowser;
  args: TStringArray;
  name, start: string;
  isNew: Boolean;
begin
  Current := Tab;
  if not (Tab is TTerminalTab) then
  begin
    ShowMsg('<span foreground="#888888">Open an SSH session to browse the remote files here.</span>');
    Exit;
  end;
  t := TTerminalTab(Tab);
  b := BrowserFor(Tab);
  if t.IsSsh then
  begin
    if not t.Session.SftpBrowser then
    begin
      ShowMsg('<span foreground="#888888">The SSH-browser is disabled for this session.</span>');
      Exit;
    end;
    if not t.MasterReady then
    begin
      if b <> nil then DropBrowser(b);
      if t.Alive then
        ShowMsg('<span foreground="#888888">Waiting for the SSH authentication...</span>')
      else
        ShowMsg('<span foreground="#888888">The SSH session is closed.</span>');
      Exit;
    end;
  end
  else if not t.IsLocalShell then
  begin
    ShowMsg('<span foreground="#888888">No file browser for this kind of session.</span>');
    Exit;
  end;
  isNew := b = nil;
  if isNew then
  begin
    b := TFileBrowser.Create(True);
    b.Tag := Tab;
    Browsers.Add(b);
    name := 'b' + IntToHex(PtrUInt(b), 16);
    gtk_stack_add_named(Stack, b.Widget, PChar(name));
    gtk_toggle_button_set_active(b.FollowCheck, Settings.FollowTerminalFolder);
    Connect(b.FollowCheck, 'toggled', @FollowToggled, b);
    Connect(b.MonitorCheck, 'toggled', @MonitorToggled, b);
    if t.IsSsh then
    begin
      args := SshMuxArgs(t.Session, t.ControlPath);
      SetLength(args, Length(args) + 4);
      args[High(args) - 3] := '-s';
      args[High(args) - 2] := '--';
      args[High(args) - 1] := t.Session.Host;
      args[High(args)] := 'sftp';
      start := '';
      if Settings.FollowTerminalFolder and (t.RemoteDir <> '') then start := t.RemoteDir;
      b.SetBackend(TSftpFs.Create(args, 'sftp://' + t.Session.Target), start, 2000);
    end
    else
    begin
      gtk_widget_hide(b.MonitorCheck);
      b.SetBackend(TLocalFs.Create, t.CurrentDir, 0);
    end;
  end
  else if Settings.FollowTerminalFolder then
  begin
    { follow the folder reported by the shell (OSC 7) }
    if t.IsSsh and (t.RemoteDir <> '') and (t.RemoteDir <> b.Path) then
      b.Navigate(t.RemoteDir, True)
    else if t.IsLocalShell and (t.CurrentDir <> '') and (t.CurrentDir <> b.Path) then
      b.Navigate(t.CurrentDir, True);
  end;
  Guard := True;
  gtk_toggle_button_set_active(b.MonitorCheck, Settings.RemoteMonitoring);
  Guard := False;
  gtk_widget_show(b.Widget);
  gtk_stack_set_visible_child(Stack, b.Widget);
end;

procedure TSftpPanel.TabClosed(Tab: TTabPage);
var
  b: TFileBrowser;
begin
  b := BrowserFor(Tab);
  if b <> nil then DropBrowser(b);
  if Current = Tab then
  begin
    Current := nil;
    ShowMsg('<span foreground="#888888">Open an SSH session to browse the remote files here.</span>');
  end;
end;

function TestHook(const Cmd, Arg: string): Boolean;
var
  b: TFileBrowser;
begin
  Result := Cmd = 'sftp';
  if not Result or (Panel = nil) or (Panel.Current = nil) then Exit;
  b := Panel.BrowserFor(Panel.Current);
  if b <> nil then
    b.TestOp(ExtractWord(1, Arg, [' ']), ExtractWord(2, Arg, [' ']), ExtractWord(3, Arg, [' ']));
end;

function BuildPanel: Pointer;
begin
  if Panel = nil then Panel := TSftpPanel.Create;
  Result := Panel.Widget;
end;

procedure ShowTabHook(Tab: TTabPage);
begin
  if Panel <> nil then Panel.ShowTab(Tab);
end;

procedure TabClosedHook(Tab: TTabPage);
begin
  if Panel <> nil then Panel.TabClosed(Tab);
end;

initialization
  BuildSftpPanelProc := @BuildPanel;
  SftpShowTabProc := @ShowTabHook;
  SftpTabClosedProc := @TabClosedHook;
  SetLength(TestHooks, Length(TestHooks) + 1);
  TestHooks[High(TestHooks)] := @TestHook;

end.

{ LinXterm - terminal tabs (local shell, SSH, Telnet, Serial, Mosh, commands)
  built on the VTE terminal widget. }
unit lxterminal;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, BaseUnix, lxgtk, lxutil, lxconfig, lxtabs;

type
  TColorScheme = record
    Name: string;
    Fg, Bg, Cursor: string;
    Palette: array[0..15] of string;
  end;

const
  ColorSchemeCount = 13;
  ColorSchemes: array[0..ColorSchemeCount - 1] of TColorScheme = (
    (Name: 'MobaXterm'; Fg: '#ececec'; Bg: '#000000'; Cursor: '#e8e8e8';
     Palette: ('#000000', '#cd0000', '#00cd00', '#cdcd00', '#1e90ff', '#cd00cd', '#00cdcd', '#e5e5e5',
               '#7f7f7f', '#ff3030', '#00ff00', '#ffff00', '#5c9cff', '#ff00ff', '#00ffff', '#ffffff')),
    (Name: 'Black on white'; Fg: '#000000'; Bg: '#ffffff'; Cursor: '#000000';
     Palette: ('#000000', '#cc0000', '#4e9a06', '#c4a000', '#3465a4', '#75507b', '#06989a', '#d3d7cf',
               '#555753', '#ef2929', '#8ae234', '#fce94f', '#729fcf', '#ad7fa8', '#34e2e2', '#eeeeec')),
    (Name: 'Tango dark'; Fg: '#d3d7cf'; Bg: '#2e3436'; Cursor: '#d3d7cf';
     Palette: ('#2e3436', '#cc0000', '#4e9a06', '#c4a000', '#3465a4', '#75507b', '#06989a', '#d3d7cf',
               '#555753', '#ef2929', '#8ae234', '#fce94f', '#729fcf', '#ad7fa8', '#34e2e2', '#eeeeec')),
    (Name: 'Solarized dark'; Fg: '#839496'; Bg: '#002b36'; Cursor: '#93a1a1';
     Palette: ('#073642', '#dc322f', '#859900', '#b58900', '#268bd2', '#d33682', '#2aa198', '#eee8d5',
               '#002b36', '#cb4b16', '#586e75', '#657b83', '#839496', '#6c71c4', '#93a1a1', '#fdf6e3')),
    (Name: 'Solarized light'; Fg: '#657b83'; Bg: '#fdf6e3'; Cursor: '#586e75';
     Palette: ('#073642', '#dc322f', '#859900', '#b58900', '#268bd2', '#d33682', '#2aa198', '#eee8d5',
               '#002b36', '#cb4b16', '#586e75', '#657b83', '#839496', '#6c71c4', '#93a1a1', '#fdf6e3')),
    (Name: 'Monokai'; Fg: '#f8f8f2'; Bg: '#272822'; Cursor: '#f8f8f0';
     Palette: ('#272822', '#f92672', '#a6e22e', '#f4bf75', '#66d9ef', '#ae81ff', '#a1efe4', '#f8f8f2',
               '#75715e', '#f92672', '#a6e22e', '#f4bf75', '#66d9ef', '#ae81ff', '#a1efe4', '#f9f8f5')),
    (Name: 'Dracula'; Fg: '#f8f8f2'; Bg: '#282a36'; Cursor: '#f8f8f2';
     Palette: ('#21222c', '#ff5555', '#50fa7b', '#f1fa8c', '#bd93f9', '#ff79c6', '#8be9fd', '#f8f8f2',
               '#6272a4', '#ff6e6e', '#69ff94', '#ffffa5', '#d6acff', '#ff92df', '#a4ffff', '#ffffff')),
    (Name: 'Nord'; Fg: '#d8dee9'; Bg: '#2e3440'; Cursor: '#d8dee9';
     Palette: ('#3b4252', '#bf616a', '#a3be8c', '#ebcb8b', '#81a1c1', '#b48ead', '#88c0d0', '#e5e9f0',
               '#4c566a', '#bf616a', '#a3be8c', '#ebcb8b', '#81a1c1', '#b48ead', '#8fbcbb', '#eceff4')),
    (Name: 'Gruvbox dark'; Fg: '#ebdbb2'; Bg: '#282828'; Cursor: '#ebdbb2';
     Palette: ('#282828', '#cc241d', '#98971a', '#d79921', '#458588', '#b16286', '#689d6a', '#a89984',
               '#928374', '#fb4934', '#b8bb26', '#fabd2f', '#83a598', '#d3869b', '#8ec07c', '#ebdbb2')),
    (Name: 'One dark'; Fg: '#abb2bf'; Bg: '#282c34'; Cursor: '#528bff';
     Palette: ('#282c34', '#e06c75', '#98c379', '#e5c07b', '#61afef', '#c678dd', '#56b6c2', '#abb2bf',
               '#5c6370', '#e06c75', '#98c379', '#e5c07b', '#61afef', '#c678dd', '#56b6c2', '#ffffff')),
    (Name: 'Ubuntu'; Fg: '#eeeeec'; Bg: '#300a24'; Cursor: '#eeeeec';
     Palette: ('#2e3436', '#cc0000', '#4e9a06', '#c4a000', '#3465a4', '#75507b', '#06989a', '#d3d7cf',
               '#555753', '#ef2929', '#8ae234', '#fce94f', '#729fcf', '#ad7fa8', '#34e2e2', '#eeeeec')),
    (Name: 'Green on black'; Fg: '#33ff33'; Bg: '#000000'; Cursor: '#33ff33';
     Palette: ('#000000', '#cd0000', '#00cd00', '#cdcd00', '#1e90ff', '#cd00cd', '#00cdcd', '#e5e5e5',
               '#7f7f7f', '#ff3030', '#00ff00', '#ffff00', '#5c9cff', '#ff00ff', '#00ffff', '#ffffff')),
    (Name: 'Amber retro'; Fg: '#ffb000'; Bg: '#1a1000'; Cursor: '#ffb000';
     Palette: ('#1a1000', '#cd0000', '#00cd00', '#cdcd00', '#1e90ff', '#cd00cd', '#00cdcd', '#e5e5e5',
               '#7f7f7f', '#ff3030', '#00ff00', '#ffff00', '#5c9cff', '#ff00ff', '#00ffff', '#ffffff'))
  );

type
  TTermState = (tsIdle, tsStarting, tsRunning, tsExited);

  PSpawnCtx = ^TSpawnCtx;
  TSpawnCtx = record
    Owner: TObject;
  end;

  TTerminalTab = class(TTabPage)
  private
    FState: TTermState;
    FPid: GPid;
    FSpawnCtx: PSpawnCtx;
    FPassFile: string;
    FControlPath: string;
    FMasterReady: Boolean;
    FReadyTimer: guint;
    FSearchRevealer, FSearchEntry, FSearchCase: Pointer;
    FUrlTag, FIpTag: gint;     { VTE match regexes: links and IPv4 addresses }
    FCustomArgv: TStringArray;
    FCurrentDir: string;
    FRemoteDir: string;
    FMonitorBar, FMonitorLabel: Pointer;
    FMonCpu, FMonRam, FMonNet, FMonDisk, FMonUsers, FMonUptime: Pointer;
    FMonCpuBar, FMonRamBar, FMonDiskBar: Pointer;
    FMonItems: array of Pointer;   { item boxes hidden until the first sample }
    FMonitorTimer: guint;
    FMonitorProc: TChildProcess;
    FPrevCpuTotal, FPrevCpuIdle: Int64;
    FPrevRx, FPrevTx: Int64;
    FPrevNetTime: Int64;
    FMacroTimer: guint;
    FFontScale: Double;
    FFeeding: Boolean;    { programmatic input in progress: not user typing }
    FUserTyped: Boolean;
    FFollowProc: TChildProcess;
    FFollowShell: string;
    FFollowTimer: guint;
    FFollowTries: Integer;
    FLogName: string;         { session log file ('' = not logged) }
    FQuietUntil: Int64;       { output before this time is not tab activity }
    FScrollAccum: Double;     { smooth Ctrl+scroll zoom }
    FWasConnected: Boolean;   { the SSH connection of this run was established }
    FAutoRetry: Boolean;      { this run is an automatic reconnection }
    FReconnectTimer: guint;
    FReconnectLeft: Integer;
    FReconnectTries: Integer;
    FExitStatus: Integer;
    FRelay: Boolean;          { this run goes through lxrelay (colours / log) }
    FAtPrompt: Boolean;       { the shell waits for a command (vte.ext.linxterm.prompt) }
    FCmdStart: Int64;         { command running since (Return pressed at the prompt), 0 = none }
    FCmdText: string;
    FLastBellNotify: Int64;
    FHighlight: Boolean;      { keyword colouring of this run }
    procedure StartFollowPath;
    procedure MaybeFollowPath;
    procedure FollowShellKnown(Sender: TChildProcess; Status: Integer);
    procedure TryInjectFollow;
    function CursorLineText(out Col: Integer): string;
    procedure Spawn;
    function BuildArgv(out Argv: TStringArray; out Env: TStringArray; out Cwd: string; out Err: string): Boolean;
    procedure ShowExitMessage(Status: Integer);
    procedure CheckMaster;
    procedure SetupSearchBar;
    procedure DoSearch(Backward: Boolean);
    procedure MonitorTick;
    procedure MonitorOutput(Sender: TChildProcess; Status: Integer);
    function MonitorItem(Box: Pointer; const Icon, Tip: string; Gauge: PPointer): Pointer;
    procedure CleanupConnection;
    procedure PlayStartMacro;
    procedure ShowBanner;
    function WantLog: Boolean;
    function PrepareLog: Boolean;
    function UserWatching: Boolean;
    function CommandAtCursor(const Typed: string): string;
    procedure NoteEnter(const Data: string);
    function AddMatch(const Pattern: string): gint;
    function MatchAt(Event: Pointer; out Tag: gint): string;
    procedure AddAddressItems(Menu: Pointer; const Addr: string);
    procedure AddLinkItems(Menu: Pointer; const Url: string);
    procedure WrapWithRelay(var Argv: TStringArray);
    procedure ScheduleReconnect;
    procedure ShowReconnectLine;
    procedure CancelReconnect;
  public
    Term: Pointer;
    MultiExecOff: Boolean; { left out of MultiExec: neither sends nor receives keystrokes }
    Container: Pointer;    { reparentable widget: search bar + terminal + monitor bar }
    Holder: Pointer;       { box inside Page that hosts Container }
    constructor Create(ASession: TSession);
    constructor CreateCommand(const ATitle, AIcon: string; const Argv: array of string);
    destructor Destroy; override;
    procedure Start;
    procedure ApplySettings;
    procedure Restart; override;
    function CanRestart: Boolean; override;
    procedure Shutdown; override;
    procedure FocusContent; override;
    function IsTerminal: Boolean; override;
    function CanDuplicate: Boolean; override;
    procedure SaveState(List: TStrings); override;
    procedure CopySelection;
    procedure Paste;
    procedure PasteText(const T: string);
    procedure SelectAll;
    procedure ClearScrollback;
    procedure ResetTerminal;
    procedure ZoomIn;
    procedure ZoomOut;
    procedure ZoomReset;
    procedure ShowSearch;
    procedure HideSearch;
    procedure SaveOutput;
    procedure SendInput(const Data: string);
    procedure TypeInput(const Data: string);
    procedure SetColorScheme(const Name: string);
    procedure SetMonitoring(Enabled: Boolean);
    procedure ShowContextMenu(Event: Pointer);
    procedure NoteActivity(Bell: Boolean);
    procedure TermpropChanged(const Name: string);
    procedure OpenLink(const Url: string; Confirm: Boolean);
    procedure QuietFor(Ms: Integer);
    procedure ReconnectTick;
    function ScrollZoom(Event: Pointer): Boolean;
    procedure OpenLog;
    function WantHighlight: Boolean;
    procedure SetHighlight(V: Boolean; Remember: Boolean = True);
    procedure SpawnFinished(Pid: GPid; Err: string);
    procedure ChildExited(Status: Integer);
    function KeyPress(Event: Pointer): Boolean;
    function ButtonPress(Event: Pointer): Boolean;
    function IsSsh: Boolean;
    function IsLocalShell: Boolean;
    function Alive: Boolean;
    property State: TTermState read FState;
    property ControlPath: string read FControlPath;
    property MasterReady: Boolean read FMasterReady;
    property CurrentDir: string read FCurrentDir;
    property RemoteDir: string read FRemoteDir;
    property LogName: string read FLogName;
    property Relayed: Boolean read FRelay;
    property Highlighting: Boolean read FHighlight;
  end;

var
  MacroTextByName: function(const Name: string): string = nil;

{ to be called before the first terminal is created }
procedure InstallTermprops;

function FindColorScheme(const Name: string): Integer;
function BuildSshArgs(S: TSession; const ControlPath: string; Master: Boolean): TStringArray;
function SshMuxArgs(S: TSession; const ControlPath: string): TStringArray;
procedure AddAskPassEnv(var Env: TStringArray; const PassFile: string);

implementation

uses
  StrUtils, Math, lxdyn;

function FindColorScheme(const Name: string): Integer;
var
  i: Integer;
begin
  for i := 0 to ColorSchemeCount - 1 do
    if SameText(ColorSchemes[i].Name, Name) then Exit(i);
  Result := 0;
end;

procedure AppendArg(var A: TStringArray; const V: string);
begin
  SetLength(A, Length(A) + 1);
  A[High(A)] := V;
end;

procedure AppendArgs(var A: TStringArray; const V: array of string);
var
  s: string;
begin
  for s in V do
    AppendArg(A, s);
end;

procedure AddAskPassEnv(var Env: TStringArray; const PassFile: string);
begin
  AppendArg(Env, 'SSH_ASKPASS=' + HelperPath('lxaskpass'));
  AppendArg(Env, 'SSH_ASKPASS_REQUIRE=force');
  if PassFile <> '' then
    AppendArg(Env, 'LINXTERM_PASSFILE=' + PassFile);
end;

function ParseExtraOptions(const S: string): TStringArray;
var
  argc: gint;
  argv: PPChar;
  err: PGError;
  i: Integer;
begin
  Result := nil;
  if Trim(S) = '' then Exit;
  err := nil;
  argv := nil;
  if g_shell_parse_argv(PChar(S), @argc, @argv, @err) then
  begin
    SetLength(Result, argc);
    for i := 0 to argc - 1 do
      Result[i] := AnsiString(argv[i]);
    g_strfreev(argv);
  end
  else
    ErrMsg(err);
end;

function BuildSshArgs(S: TSession; const ControlPath: string; Master: Boolean): TStringArray;
var
  policy: string;
begin
  Result := nil;
  AppendArg(Result, 'ssh');
  if S.KeepAlive > 0 then
    AppendArgs(Result, ['-o', 'ServerAliveInterval=' + IntToStr(S.KeepAlive)]);
  policy := Settings.HostKeyPolicy;
  if (policy = 'accept-new') or (policy = 'no') then
    AppendArgs(Result, ['-o', 'StrictHostKeyChecking=' + policy]);
  if S.X11 then AppendArg(Result, '-X');
  if S.Compression then AppendArg(Result, '-C');
  if S.AgentForward then AppendArg(Result, '-A');
  if S.KeyFile <> '' then AppendArgs(Result, ['-i', S.KeyFile]);
  if S.JumpHost <> '' then AppendArgs(Result, ['-J', S.JumpHost]);
  if (S.Port > 0) and (S.Port <> 22) then AppendArgs(Result, ['-p', IntToStr(S.Port)]);
  if S.User <> '' then AppendArgs(Result, ['-l', S.User]);
  if ControlPath <> '' then
    AppendArgs(Result, ['-o', 'ControlMaster=yes', '-o', 'ControlPath=' + ControlPath, '-o', 'ControlPersist=no']);
  AppendArgs(Result, ParseExtraOptions(S.ExtraOptions));
  if Master then
    AppendArg(Result, '-N')
  else if S.RemoteCommand <> '' then
    AppendArg(Result, '-t');
  AppendArg(Result, '--');
  AppendArg(Result, S.Host);
  if (not Master) and (S.RemoteCommand <> '') then
  begin
    if S.StayAfterCommand then
      AppendArg(Result, S.RemoteCommand + '; exec "${SHELL:-/bin/sh}" -l')
    else
      AppendArg(Result, S.RemoteCommand);
  end;
end;

function SshMuxArgs(S: TSession; const ControlPath: string): TStringArray;
begin
  Result := nil;
  AppendArgs(Result, ['ssh', '-o', 'ControlMaster=no', '-o', 'ControlPath=' + ControlPath,
    '-o', 'BatchMode=yes', '-o', 'ClearAllForwardings=yes', '-o', 'ForwardX11=no',
    '-o', 'ForwardAgent=no', '-o', 'RemoteCommand=none', '-o', 'RequestTTY=no',
    '-o', 'PermitLocalCommand=no', '-o', 'LogLevel=ERROR', '-T']);
  if (S.Port > 0) and (S.Port <> 22) then AppendArgs(Result, ['-p', IntToStr(S.Port)]);
  if S.User <> '' then AppendArgs(Result, ['-l', S.User]);
end;

{ ---------------------------------------------------------------- callbacks }

procedure SpawnCb(terminal: Pointer; pid: GPid; error: PGError; data: gpointer); cdecl;
var
  ctx: PSpawnCtx;
  e: string;
begin
  ctx := PSpawnCtx(data);
  e := '';
  if error <> nil then e := CStr(error^.message);
  if ctx^.Owner <> nil then
  begin
    TTerminalTab(ctx^.Owner).FSpawnCtx := nil;
    TTerminalTab(ctx^.Owner).SpawnFinished(pid, e);
  end;
  Dispose(ctx);
end;

procedure ChildExitedCb(terminal: Pointer; status: gint; data: gpointer); cdecl;
begin
  TTerminalTab(data).ChildExited(status);
end;

function KeyPressCb(widget: Pointer; event: Pointer; data: gpointer): gboolean; cdecl;
begin
  Result := TTerminalTab(data).KeyPress(event);
end;

function ButtonPressCb(widget: Pointer; event: Pointer; data: gpointer): gboolean; cdecl;
begin
  Result := TTerminalTab(data).ButtonPress(event);
end;

procedure CommitCb(terminal: Pointer; text: PChar; size: guint; data: gpointer); cdecl;
var
  s: string;
begin
  if (App = nil) or (text = nil) or (size = 0) then Exit;
  { VTE also emits "commit" for vte_terminal_feed_child(): only the input
    really typed (or pasted) by the user is broadcast or recorded }
  if TTerminalTab(data).FFeeding then Exit;
  TTerminalTab(data).FUserTyped := True;
  SetString(s, text, size);
  if Pos(#13, s) > 0 then TTerminalTab(data).NoteEnter(s);
  App.TerminalInput(TTabPage(data), s);
end;

procedure SelectionChangedCb(terminal: Pointer; data: gpointer); cdecl;
begin
  if Settings.CopyOnSelect and vte_terminal_get_has_selection(terminal) then
    vte_terminal_copy_clipboard_format(terminal, VTE_FORMAT_TEXT);
end;

function FocusInCb(widget: Pointer; event: Pointer; data: gpointer): gboolean; cdecl;
begin
  if App <> nil then App.TabFocused(TTabPage(data));
  Result := False;
end;

procedure DirChangedCb(terminal: Pointer; data: gpointer); cdecl;
var
  tab: TTerminalTab;
  uri, host, path: string;
  ph: PChar;
  err: PGError;
begin
  tab := TTerminalTab(data);
  uri := CStr(vte_terminal_get_current_directory_uri(terminal));
  if uri = '' then Exit;
  ph := nil;
  err := nil;
  path := TakeStr(g_filename_from_uri(PChar(uri), @ph, @err));
  host := TakeStr(ph);
  if err <> nil then ErrMsg(err);
  if path = '' then Exit;
  if tab.IsSsh then
    tab.FRemoteDir := path
  else
    tab.FCurrentDir := path;
  if App <> nil then App.TabChanged(tab);
  if host = '' then ;
end;

procedure ContentsChangedCb(terminal: Pointer; data: gpointer); cdecl;
begin
  TTerminalTab(data).NoteActivity(False);
end;

procedure TermpropChangedCb(terminal: Pointer; name: PChar; data: gpointer); cdecl;
begin
  TTerminalTab(data).TermpropChanged(CStr(name));
end;

procedure BellCb(terminal: Pointer; data: gpointer); cdecl;
begin
  TTerminalTab(data).NoteActivity(True);
end;

procedure TermSizeAllocateCb(widget: Pointer; alloc: Pointer; data: gpointer); cdecl;
begin
  { a resize reflows the text: not new output }
  TTerminalTab(data).QuietFor(1000);
end;

function ScrollCb(widget: Pointer; event: Pointer; data: gpointer): gboolean; cdecl;
begin
  Result := TTerminalTab(data).ScrollZoom(event);
end;

function ReconnectTimerCb(data: gpointer): gboolean; cdecl;
begin
  TTerminalTab(data).ReconnectTick;
  Result := False;
end;

procedure TitleChangedCb(terminal: Pointer; data: gpointer); cdecl;
var
  tab: TTerminalTab;
  t: string;
begin
  tab := TTerminalTab(data);
  t := CStr(vte_terminal_get_window_title(terminal));
  if (t <> '') and (tab.LabelBox <> nil) then
    gtk_widget_set_tooltip_text(tab.LabelBox, PChar(tab.FullTitle + #10 + t));
end;

function MasterTimerCb(data: gpointer): gboolean; cdecl;
var
  tab: TTerminalTab;
begin
  tab := TTerminalTab(data);
  tab.CheckMaster;
  Result := (tab.FReadyTimer <> 0);
end;

function MonitorTimerCb(data: gpointer): gboolean; cdecl;
begin
  TTerminalTab(data).MonitorTick;
  Result := True;
end;

function MacroTimerCb(data: gpointer): gboolean; cdecl;
var
  tab: TTerminalTab;
begin
  tab := TTerminalTab(data);
  tab.FMacroTimer := 0;
  tab.PlayStartMacro;
  if tab.IsSsh then tab.MaybeFollowPath;
  Result := False;
end;

{ search bar }
procedure SearchChangedCb(entry: Pointer; data: gpointer); cdecl;
begin
  TTerminalTab(data).DoSearch(False);
end;

procedure SearchNextCb(w: Pointer; data: gpointer); cdecl;
begin
  TTerminalTab(data).DoSearch(False);
end;

procedure SearchPrevCb(w: Pointer; data: gpointer); cdecl;
begin
  TTerminalTab(data).DoSearch(True);
end;

procedure SearchCloseCb(w: Pointer; data: gpointer); cdecl;
begin
  TTerminalTab(data).HideSearch;
end;

function SearchKeyCb(widget: Pointer; event: Pointer; data: gpointer): gboolean; cdecl;
var
  kv: guint;
begin
  Result := False;
  kv := EventKeyval(event);
  if kv = GDK_KEY_Escape then
  begin
    TTerminalTab(data).HideSearch;
    Result := True;
  end
  else if ((kv = GDK_KEY_Return) or (kv = GDK_KEY_KP_Enter)) and ((EventState(event) and GDK_SHIFT_MASK) <> 0) then
  begin
    TTerminalTab(data).DoSearch(True);
    Result := True;
  end;
end;

{ context menu actions }
procedure MenuCopy(item: Pointer; data: gpointer); cdecl;
begin TTerminalTab(data).CopySelection; end;
procedure MenuPaste(item: Pointer; data: gpointer); cdecl;
begin TTerminalTab(data).Paste; end;
procedure MenuSelectAll(item: Pointer; data: gpointer); cdecl;
begin TTerminalTab(data).SelectAll; end;
procedure MenuFind(item: Pointer; data: gpointer); cdecl;
begin TTerminalTab(data).ShowSearch; end;
procedure MenuClear(item: Pointer; data: gpointer); cdecl;
begin TTerminalTab(data).ClearScrollback; end;
procedure MenuReset(item: Pointer; data: gpointer); cdecl;
begin TTerminalTab(data).ResetTerminal; end;
procedure MenuSave(item: Pointer; data: gpointer); cdecl;
begin TTerminalTab(data).SaveOutput; end;
procedure MenuZoomIn(item: Pointer; data: gpointer); cdecl;
begin TTerminalTab(data).ZoomIn; end;
procedure MenuZoomOut(item: Pointer; data: gpointer); cdecl;
begin TTerminalTab(data).ZoomOut; end;
procedure MenuZoomReset(item: Pointer; data: gpointer); cdecl;
begin TTerminalTab(data).ZoomReset; end;
procedure MenuDuplicate(item: Pointer; data: gpointer); cdecl;
begin App.DuplicateTab(TTabPage(data)); end;
procedure MenuRename(item: Pointer; data: gpointer); cdecl;
begin App.RenameTab(TTabPage(data)); end;
procedure MenuDetach(item: Pointer; data: gpointer); cdecl;
begin App.DetachTab(TTabPage(data)); end;
procedure MenuRestart(item: Pointer; data: gpointer); cdecl;
begin TTerminalTab(data).Restart; end;
procedure MenuClose(item: Pointer; data: gpointer); cdecl;
begin App.CloseTabLater(TTabPage(data)); end;

procedure MenuScheme(item: Pointer; data: gpointer); cdecl;
var
  tab: TTerminalTab;
  idx: PtrInt;
begin
  if not gtk_check_menu_item_get_active(item) then Exit;
  tab := TTerminalTab(data);
  idx := PtrInt(g_object_get_data(item, 'scheme'));
  if (idx >= 0) and (idx < ColorSchemeCount) then
    tab.SetColorScheme(ColorSchemes[idx].Name);
end;

function ItemText(Item: Pointer; const Key: string): string;
begin
  Result := CStr(PChar(g_object_get_data(Item, PChar(Key))));
end;

procedure MenuConnectTo(item: Pointer; data: gpointer); cdecl;
var
  addr, host: string;
  s: TSession;
  p: Integer;
begin
  addr := ItemText(item, 'addr');
  s := TSession.Create(KindFromId(ItemText(item, 'kind')));
  try
    host := addr;
    p := Pos(':', addr);
    if p > 0 then
    begin
      host := Copy(addr, 1, p - 1);
      s.Port := StrToIntDef(Copy(addr, p + 1, 6), s.Port);
    end;
    s.Host := host;
    App.OpenSession(s);
  finally
    s.Free;
  end;
end;

procedure MenuPing(item: Pointer; data: gpointer); cdecl;
var
  host: string;
begin
  host := ItemText(item, 'addr');
  if Pos(':', host) > 0 then host := Copy(host, 1, Pos(':', host) - 1);
  App.RunCommandTab('Ping ' + host, 'network-workgroup', ['ping', host]);
end;

procedure MenuOpenUrl(item: Pointer; data: gpointer); cdecl;
begin
  OpenUri(ItemText(item, 'addr'));
end;

procedure MenuOpenLink(item: Pointer; data: gpointer); cdecl;
begin
  TTerminalTab(data).OpenLink(ItemText(item, 'addr'), False);
end;

procedure MenuCopyText(item: Pointer; data: gpointer); cdecl;
var
  t: string;
begin
  t := ItemText(item, 'addr');
  gtk_clipboard_set_text(gtk_clipboard_get(GDK_SELECTION_CLIPBOARD), PChar(t), -1);
end;

function AddrItem(Menu: Pointer; const Text, Icon: string; Cb: Pointer; const Addr, Kind: string;
  Data: Pointer = nil): Pointer;
begin
  Result := NewImageMenuItem(Menu, Text, Icon, Cb, Data);
  g_object_set_data_full(Result, 'addr', g_strdup(PChar(Addr)), @g_free);
  g_object_set_data_full(Result, 'kind', g_strdup(PChar(Kind)), @g_free);
end;

procedure MenuMonitoring(item: Pointer; data: gpointer); cdecl;
begin
  TTerminalTab(data).SetMonitoring(gtk_check_menu_item_get_active(item));
end;

procedure MenuHighlight(item: Pointer; data: gpointer); cdecl;
begin
  TTerminalTab(data).SetHighlight(gtk_check_menu_item_get_active(item));
end;

procedure MenuOpenLog(item: Pointer; data: gpointer); cdecl;
begin
  TTerminalTab(data).OpenLog;
end;

procedure MenuLogFolder(item: Pointer; data: gpointer); cdecl;
begin
  ForceDirectories(Settings.LogDir);
  OpenPath(Settings.LogDir);
end;

{ ---------------------------------------------------------------- TTerminalTab }

{ one item of the monitoring bar: icon [+ gauge] + value }
function TTerminalTab.MonitorItem(Box: Pointer; const Icon, Tip: string; Gauge: PPointer): Pointer;
var
  item, bar: Pointer;
begin
  item := gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 4);
  gtk_box_pack_start(item, NewIcon(Icon, 16), False, False, 0);
  if Gauge <> nil then
  begin
    bar := gtk_level_bar_new_for_interval(0, 1);
    { green / orange / red instead of the theme colours }
    gtk_level_bar_remove_offset_value(bar, 'low');
    gtk_level_bar_remove_offset_value(bar, 'high');
    gtk_level_bar_remove_offset_value(bar, 'full');
    gtk_level_bar_add_offset_value(bar, 'lx-ok', 0.70);
    gtk_level_bar_add_offset_value(bar, 'lx-warn', 0.90);
    gtk_level_bar_add_offset_value(bar, 'lx-crit', 1.0);
    gtk_widget_set_size_request(bar, 54, -1);
    gtk_widget_set_valign(bar, GTK_ALIGN_CENTER);
    gtk_box_pack_start(item, bar, False, False, 0);
    Gauge^ := bar;
  end;
  Result := NewLabel('', 0);
  gtk_box_pack_start(item, Result, False, False, 0);
  gtk_widget_set_tooltip_text(item, PChar(Tip));
  gtk_box_pack_start(Box, item, False, False, 0);
  SetLength(FMonItems, Length(FMonItems) + 1);
  FMonItems[High(FMonItems)] := item;
end;

constructor TTerminalTab.Create(ASession: TSession);
var
  hbox, sb: Pointer;
begin
  inherited Create(ASession);
  FFontScale := 1.0;
  Page := gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
  Holder := Page;
  Container := gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
  g_object_ref_sink(Container);
  SetupSearchBar;
  hbox := gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0);
  Term := vte_terminal_new;
  gtk_widget_set_hexpand(Term, True);
  gtk_widget_set_vexpand(Term, True);
  gtk_box_pack_start(hbox, Term, True, True, 0);
  sb := gtk_scrollbar_new(GTK_ORIENTATION_VERTICAL, gtk_scrollable_get_vadjustment(Term));
  AddClass(sb, 'lx-term-scroll');
  gtk_box_pack_start(hbox, sb, False, False, 0);
  gtk_box_pack_start(Container, hbox, True, True, 0);
  { remote monitoring bar (MobaXterm style: icon, gauge and value per item) }
  FMonitorBar := gtk_event_box_new;
  AddClass(FMonitorBar, 'lx-monitor');
  hbox := gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 14);
  SetMargins(hbox, 2);
  gtk_widget_set_margin_start(hbox, 8);
  FMonitorLabel := MonitorItem(hbox, 'lx-mon-host', 'Remote server', nil);
  FMonCpu := MonitorItem(hbox, 'lx-mon-cpu', 'CPU usage', @FMonCpuBar);
  FMonRam := MonitorItem(hbox, 'lx-mon-ram', 'Memory used / total', @FMonRamBar);
  FMonNet := MonitorItem(hbox, 'lx-mon-net', 'Network traffic (download / upload)', nil);
  FMonDisk := MonitorItem(hbox, 'lx-mon-disk', 'Disk usage of the root file system', @FMonDiskBar);
  FMonUsers := MonitorItem(hbox, 'lx-mon-users', 'Connected users', nil);
  FMonUptime := MonitorItem(hbox, 'lx-mon-uptime', 'Uptime', nil);
  { the items are clipped in narrow terminals (split view) instead of
    widening the window: no scrollbar, no minimum width }
  sb := gtk_scrolled_window_new(nil, nil);
  gtk_scrolled_window_set_policy(sb, GTK_POLICY_EXTERNAL, GTK_POLICY_NEVER);
  gtk_container_add(sb, hbox);
  gtk_container_add(FMonitorBar, sb);
  gtk_widget_set_no_show_all(FMonitorBar, True);
  gtk_box_pack_end(Container, FMonitorBar, False, False, 0);
  gtk_box_pack_start(Page, Container, True, True, 0);
  AddClass(Term, 'lx-terminal');

  vte_terminal_set_mouse_autohide(Term, True);
  vte_terminal_set_allow_hyperlink(Term, True);
  FUrlTag := AddMatch('(?:\b(?:https?|ftps?|sftp|ssh|telnet|rdp|vnc|file)://|\bwww\.)' +
    '[^\s<>"''`\x7f]*[^\s<>"''`\x7f.,;:!?)\]}]');
  FIpTag := AddMatch('(?<![\w.])(?:(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)\.){3}' +
    '(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(?::\d{1,5})?(?!\.?\w)');
  Connect(Term, 'child-exited', @ChildExitedCb, Self);
  Connect(Term, 'key-press-event', @KeyPressCb, Self);
  Connect(Term, 'button-press-event', @ButtonPressCb, Self);
  Connect(Term, 'commit', @CommitCb, Self);
  Connect(Term, 'selection-changed', @SelectionChangedCb, Self);
  Connect(Term, 'focus-in-event', @FocusInCb, Self);
  Connect(Term, 'current-directory-uri-changed', @DirChangedCb, Self);
  Connect(Term, 'window-title-changed', @TitleChangedCb, Self);
  Connect(Term, 'contents-changed', @ContentsChangedCb, Self);
  Connect(Term, 'bell', @BellCb, Self);
  Connect(Term, 'size-allocate', @TermSizeAllocateCb, Self);
  Connect(Term, 'scroll-event', @ScrollCb, Self);
  { VTE >= 0.78: start / end of the commands of the local shells }
  if TermpropsAvailable then
    Connect(Term, 'termprop-changed', @TermpropChangedCb, Self);
  ApplySettings;
  gtk_widget_show_all(Page);
end;

constructor TTerminalTab.CreateCommand(const ATitle, AIcon: string; const Argv: array of string);
var
  i: Integer;
  s: TSession;
begin
  s := TSession.Create(skShell);
  s.Name := ATitle;
  Create(s);
  SetLength(FCustomArgv, Length(Argv));
  for i := 0 to High(Argv) do
    FCustomArgv[i] := Argv[i];
  IconName := AIcon;
end;

destructor TTerminalTab.Destroy;
begin
  CancelReconnect;
  CleanupConnection;
  if FSpawnCtx <> nil then
    FSpawnCtx^.Owner := nil;
  if Container <> nil then
    g_object_unref(Container);
  inherited Destroy;
end;

procedure TTerminalTab.SetupSearchBar;
var
  box, b, sw: Pointer;
begin
  FSearchRevealer := gtk_revealer_new;
  gtk_revealer_set_transition_type(FSearchRevealer, GTK_REVEALER_TRANSITION_TYPE_SLIDE_DOWN);
  box := gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 4);
  AddClass(box, 'lx-searchbar');
  SetMargins(box, 3);
  gtk_box_pack_start(box, NewIcon('edit-find', 16), False, False, 2);
  FSearchEntry := gtk_search_entry_new;
  gtk_entry_set_width_chars(FSearchEntry, 30);
  gtk_entry_set_placeholder_text(FSearchEntry, 'Find in terminal...');
  Connect(FSearchEntry, 'search-changed', @SearchChangedCb, Self);
  Connect(FSearchEntry, 'activate', @SearchNextCb, Self);
  Connect(FSearchEntry, 'key-press-event', @SearchKeyCb, Self);
  gtk_box_pack_start(box, FSearchEntry, False, False, 0);
  b := NewIconButton('go-up', '', 'Previous match (Shift+Enter)', 16);
  Connect(b, 'clicked', @SearchPrevCb, Self);
  gtk_box_pack_start(box, b, False, False, 0);
  b := NewIconButton('go-down', '', 'Next match (Enter)', 16);
  Connect(b, 'clicked', @SearchNextCb, Self);
  gtk_box_pack_start(box, b, False, False, 0);
  FSearchCase := gtk_check_button_new_with_label('Match case');
  Connect(FSearchCase, 'toggled', @SearchChangedCb, Self);
  gtk_box_pack_start(box, FSearchCase, False, False, 6);
  b := NewFlatIconButton('window-close', 'Close (Esc)', 16);
  Connect(b, 'clicked', @SearchCloseCb, Self);
  gtk_box_pack_end(box, b, False, False, 0);
  { a hidden search bar must not impose its width on narrow split tiles }
  sw := gtk_scrolled_window_new(nil, nil);
  gtk_scrolled_window_set_policy(sw, GTK_POLICY_EXTERNAL, GTK_POLICY_NEVER);
  gtk_container_add(sw, box);
  gtk_container_add(FSearchRevealer, sw);
  gtk_box_pack_start(Container, FSearchRevealer, False, False, 0);
end;

procedure TTerminalTab.ApplySettings;
var
  sch: Integer;
  fg, bg, cur: TGdkRGBA;
  pal: array[0..15] of TGdkRGBA;
  i: Integer;
  font: string;
  fd: Pointer;
  name: string;
begin
  font := Settings.FontName;
  if (Session <> nil) and (Session.TermFont <> '') then font := Session.TermFont;
  fd := pango_font_description_from_string(PChar(font));
  vte_terminal_set_font(Term, fd);
  pango_font_description_free(fd);
  vte_terminal_set_font_scale(Term, FFontScale);
  name := Settings.ColorScheme;
  if (Session <> nil) and (Session.ColorScheme <> '') then name := Session.ColorScheme;
  sch := FindColorScheme(name);
  gdk_rgba_parse(@fg, PChar(ColorSchemes[sch].Fg));
  gdk_rgba_parse(@bg, PChar(ColorSchemes[sch].Bg));
  gdk_rgba_parse(@cur, PChar(ColorSchemes[sch].Cursor));
  for i := 0 to 15 do
    gdk_rgba_parse(@pal[i], PChar(ColorSchemes[sch].Palette[i]));
  vte_terminal_set_colors(Term, @fg, @bg, @pal[0], 16);
  vte_terminal_set_color_cursor(Term, @cur);
  vte_terminal_set_color_cursor_foreground(Term, @bg);
  vte_terminal_set_cursor_shape(Term, Settings.CursorShape);
  if Settings.CursorBlink then
    vte_terminal_set_cursor_blink_mode(Term, VTE_CURSOR_BLINK_ON)
  else
    vte_terminal_set_cursor_blink_mode(Term, VTE_CURSOR_BLINK_OFF);
  vte_terminal_set_scrollback_lines(Term, Settings.Scrollback);
  vte_terminal_set_audible_bell(Term, Settings.Bell = 'sound');
  vte_terminal_set_scroll_on_output(Term, Settings.ScrollOnOutput);
  vte_terminal_set_scroll_on_keystroke(Term, Settings.ScrollOnKeystroke);
  if Settings.BackspaceSendsCtrlH then
    vte_terminal_set_backspace_binding(Term, VTE_ERASE_ASCII_BACKSPACE)
  else
    vte_terminal_set_backspace_binding(Term, VTE_ERASE_AUTO);
  vte_terminal_set_bold_is_bright(Term, Settings.BoldIsBright);
  vte_terminal_set_word_char_exceptions(Term, PChar(Settings.WordChars));
end;

procedure TTerminalTab.SetColorScheme(const Name: string);
begin
  if Session <> nil then
    Session.ColorScheme := Name;
  ApplySettings;
end;

function TTerminalTab.IsSsh: Boolean;
begin
  Result := (Session <> nil) and (Session.Kind = skSSH) and (Length(FCustomArgv) = 0);
end;

function TTerminalTab.IsLocalShell: Boolean;
begin
  Result := (Session <> nil) and (Session.Kind = skShell) and (Length(FCustomArgv) = 0);
end;

function TTerminalTab.Alive: Boolean;
begin
  Result := FState in [tsStarting, tsRunning];
end;

function TTerminalTab.IsTerminal: Boolean;
begin
  Result := True;
end;

function TTerminalTab.CanDuplicate: Boolean;
begin
  Result := Length(FCustomArgv) = 0;
end;

function TTerminalTab.CanRestart: Boolean;
begin
  Result := True;
end;

procedure TTerminalTab.SaveState(List: TStrings);
begin
  if Length(FCustomArgv) = 0 then
    inherited SaveState(List);
end;

function TTerminalTab.BuildArgv(out Argv: TStringArray; out Env: TStringArray; out Cwd: string; out Err: string): Boolean;
var
  s: TSession;
  pw, sh, sshcmd: string;
  i: Integer;
begin
  Result := False;
  Argv := nil;
  Env := nil;
  Cwd := '';
  Err := '';
  s := Session;
  AppendArg(Env, 'LINXTERM=1');
  AppendArg(Env, 'COLORTERM=truecolor');
  if Length(FCustomArgv) > 0 then
  begin
    for i := 0 to High(FCustomArgv) do
      AppendArg(Argv, FCustomArgv[i]);
    Cwd := HomeDir;
    Exit(True);
  end;
  pw := '';
  if s.HasPassword then
    LookupPassword(s.PasswordKey, pw);
  case s.Kind of
    skShell:
      begin
        sh := s.ShellPath;
        if sh = '' then sh := Settings.DefaultShell;
        if (sh = '') or not FileExists(sh) then sh := DefaultShellPath;
        if s.Command <> '' then
          Argv := [sh, '-c', s.Command]
        else if Settings.MobaPrompt and (ExtractFileName(sh) = 'bash') and
          FileExists(AppDir + '/share/linxterm.bashrc') then
          { the user's ~/.bashrc is read first, then the MobaXterm prompt is set }
          Argv := [sh, '--rcfile', AppDir + '/share/linxterm.bashrc', '-i']
        else
          Argv := [sh];
        Cwd := s.StartDir;
        if Cwd = '' then Cwd := Settings.StartDir;
        if (Cwd = '') or not DirectoryExists(Cwd) then Cwd := HomeDir;
        FCurrentDir := Cwd;
      end;
    skSSH:
      begin
        if Trim(s.Host) = '' then
        begin
          Err := 'No remote host specified.';
          Exit;
        end;
        FControlPath := RuntimeDir + '/cm-' + RandomToken(10);
        Argv := BuildSshArgs(s, FControlPath, False);
        if pw <> '' then
        begin
          FPassFile := WriteSecretFile(pw);
          AddAskPassEnv(Env, FPassFile);
        end;
        Cwd := HomeDir;
      end;
    skTelnet:
      begin
        if Trim(s.Host) = '' then
        begin
          Err := 'No remote host specified.';
          Exit;
        end;
        Argv := [HelperPath('lxtelnet'), s.Host, IntToStr(s.Port), s.User];
        if pw <> '' then
        begin
          FPassFile := WriteSecretFile(pw);
          AppendArg(Env, 'LINXTERM_PASSFILE=' + FPassFile);
        end;
        Cwd := HomeDir;
      end;
    skSerial:
      begin
        if Trim(s.Device) = '' then
        begin
          Err := 'No serial port specified.';
          Exit;
        end;
        Argv := [HelperPath('lxserial'), s.Device, IntToStr(s.Baud), IntToStr(s.DataBits),
          s.Parity, IntToStr(s.StopBits), s.FlowControl];
        Cwd := HomeDir;
      end;
    skMosh:
      begin
        if FindProgram('mosh') = '' then
        begin
          Err := 'The "mosh" client is not installed on this computer.'#13#10 +
            'Use the "Packages" button of the toolbar to install it.';
          Exit;
        end;
        sshcmd := 'ssh';
        if (s.Port > 0) and (s.Port <> 22) then sshcmd := sshcmd + ' -p ' + IntToStr(s.Port);
        if s.KeyFile <> '' then sshcmd := sshcmd + ' -i ' + ShellQuote(s.KeyFile);
        if s.User <> '' then
          Argv := ['mosh', '--ssh=' + sshcmd, s.User + '@' + s.Host]
        else
          Argv := ['mosh', '--ssh=' + sshcmd, s.Host];
        if pw <> '' then
        begin
          FPassFile := WriteSecretFile(pw);
          AddAskPassEnv(Env, FPassFile);
        end;
        Cwd := HomeDir;
      end;
  else
    begin
      Err := 'This session type cannot run in a terminal.';
      Exit;
    end;
  end;
  Result := True;
end;

procedure TTerminalTab.Start;
begin
  Spawn;
end;

function Utf8Width(const S: string): Integer;
var
  i: Integer;
  inEsc: Boolean;
begin
  Result := 0;
  inEsc := False;
  for i := 1 to Length(S) do
  begin
    if inEsc then
    begin
      if S[i] in ['A'..'Z', 'a'..'z'] then inEsc := False;
      Continue;
    end;
    if S[i] = #27 then
    begin
      inEsc := True;
      Continue;
    end;
    if (Ord(S[i]) and $C0) <> $80 then Inc(Result);
  end;
end;

{ cuts S to Max visible characters (ANSI sequences kept) }
function Utf8Truncate(const S: string; Max: Integer): string;
var
  i, w: Integer;
  inEsc: Boolean;
begin
  Result := '';
  w := 0;
  inEsc := False;
  for i := 1 to Length(S) do
  begin
    if inEsc then
    begin
      Result := Result + S[i];
      if S[i] in ['A'..'Z', 'a'..'z'] then inEsc := False;
      Continue;
    end;
    if S[i] = #27 then
    begin
      inEsc := True;
      Result := Result + S[i];
      Continue;
    end;
    if (Ord(S[i]) and $C0) <> $80 then
    begin
      if w >= Max then Break;
      Inc(w);
    end;
    Result := Result + S[i];
  end;
end;

{ Builds the MobaXterm-like framed welcome banner. Lines starting with '^'
  are centered. ANSI colour sequences are allowed inside the lines. }
function FramedBanner(const Lines: array of string; Cols: Integer): string;
const
  BORDER = #27'[0;37m';
  RESET = #27'[0m';
var
  i, pad, left, W: Integer;
  line, body: string;
begin
  { adapt the frame to narrow terminals (split view) }
  W := Cols - 8;
  if W > 72 then W := 72;
  if W < 40 then W := 40;
  Result := #13#10'    ' + BORDER + '┌' + StringOfChar('-', 0);
  for i := 1 to W do Result := Result + '─';
  Result := Result + '┐' + RESET + #13#10;
  for i := 0 to High(Lines) do
  begin
    line := Lines[i];
    if (line <> '') and (line[1] = '^') then
    begin
      body := Copy(line, 2, MaxInt);
      left := (W - Utf8Width(body)) div 2;
      if left < 0 then left := 0;
      body := StringOfChar(' ', left) + body;
    end
    else
      body := ' ' + line;
    if Utf8Width(body) > W then body := Utf8Truncate(body, W);
    pad := W - Utf8Width(body);
    if pad < 0 then pad := 0;
    Result := Result + '    ' + BORDER + '│' + RESET + body + RESET + StringOfChar(' ', pad) + BORDER + '│' + RESET + #13#10;
  end;
  Result := Result + '    ' + BORDER + '└';
  for i := 1 to W do Result := Result + '─';
  Result := Result + '┘' + RESET + #13#10#13#10;
end;

function YesNo(B: Boolean): string;
begin
  if B then Result := #27'[1;32m✔'#27'[0m' else Result := #27'[1;31m✘'#27'[0m';
end;

procedure TTerminalTab.ShowBanner;
const
  TITLE_C = #27'[1;32m';
  SUB_C = #27'[0;33m';
  ARROW = #27'[1;37m➤'#27'[0m ';
  HOST_C = #27'[1;35m';
var
  disp, target: string;
  s: TSession;
  Cols: Integer;
begin
  if (Session = nil) or (Length(FCustomArgv) > 0) then Exit;
  Cols := vte_terminal_get_column_count(Term);
  s := Session;
  disp := GetEnvironmentVariable('DISPLAY');
  case s.Kind of
    skShell:
      vte_terminal_feed(Term, PChar(FramedBanner([
        '^' + TITLE_C + '• ' + APP_NAME + ' ' + APP_VERSION + ' •',
        '^' + SUB_C + '(X server, SSH client and network tools)',
        '',
        ARROW + 'Your DISPLAY is set to ' + #27'[1;36m' + IfThen(disp = '', '(none)', disp),
        ARROW + 'When using SSH, your remote DISPLAY is automatically forwarded',
        ARROW + 'Your home folder is ' + #27'[1;36m' + HomeDir,
        ARROW + 'Right-click pastes, selecting text copies it',
        '',
        #27'[1;37m• ' + #27'[0mMore info: Help menu or the README in ' + AppDir], Cols)), -1);
    skSSH:
      begin
        target := s.Host;
        if s.User <> '' then target := s.User + '@' + target;
        vte_terminal_feed(Term, PChar(FramedBanner([
          '^' + TITLE_C + '• ' + APP_NAME + ' ' + APP_VERSION + ' •',
          '^' + SUB_C + '(SSH client, X server and network tools)',
          '',
          ARROW + 'SSH session to ' + HOST_C + target + #27'[0m' + IfThen(s.Port <> 22, '  (port ' + IntToStr(s.Port) + ')', ''),
          '  • Direct SSH      :  ' + YesNo(s.JumpHost = '') + IfThen(s.JumpHost <> '', '  (through ' + s.JumpHost + ')', ''),
          '  • SSH compression :  ' + YesNo(s.Compression),
          '  • SSH-browser     :  ' + YesNo(s.SftpBrowser),
          '  • X11-forwarding  :  ' + YesNo(s.X11 and (disp <> '')) +
            IfThen(s.X11 and (disp <> ''), '  (remote display is forwarded through SSH)', ''),
          '',
          ARROW + 'For more info, open the Help menu.'], Cols)), -1);
      end;
    skTelnet, skSerial, skMosh:
      vte_terminal_feed(Term, PChar(FramedBanner([
        '^' + TITLE_C + '• ' + APP_NAME + ' ' + APP_VERSION + ' •',
        '^' + SUB_C + '(' + SessionKindNames[s.Kind] + ' client)',
        '',
        ARROW + SessionKindNames[s.Kind] + ' session to ' + HOST_C + s.Target], Cols)), -1);
  end;
end;

procedure TTerminalTab.Spawn;
var
  argv, env: TStringArray;
  cwd, err: string;
  pargs, penv: array of PChar;
  i: Integer;
begin
  CleanupConnection;
  FMasterReady := False;
  if not BuildArgv(argv, env, cwd, err) then
  begin
    vte_terminal_feed(Term, PChar(#13#10#27'[1;31m' + StringReplace(err, #10, #13#10, [rfReplaceAll]) + #27'[0m'#13#10), -1);
    FState := tsExited;
    ShowExitMessage(-1);
    Exit;
  end;
  ShowBanner;
  FRelay := False;
  FHighlight := False;
  FAtPrompt := False;
  FCmdStart := 0;
  if (Length(FCustomArgv) = 0) and (WantLog or WantHighlight) and FileExists(HelperPath('lxrelay')) then
    WrapWithRelay(argv);
  FWasConnected := False;
  QuietFor(3000);
  SetLength(pargs, Length(argv) + 1);
  for i := 0 to High(argv) do
    pargs[i] := PChar(argv[i]);
  pargs[Length(argv)] := nil;
  SetLength(penv, Length(env) + 1);
  for i := 0 to High(env) do
    penv[i] := PChar(env[i]);
  penv[Length(env)] := nil;
  FState := tsStarting;
  FUserTyped := False;
  New(FSpawnCtx);
  FSpawnCtx^.Owner := Self;
  vte_terminal_spawn_async(Term, VTE_PTY_DEFAULT, PChar(cwd), @pargs[0], @penv[0], G_SPAWN_SEARCH_PATH,
    nil, nil, nil, -1, nil, @SpawnCb, FSpawnCtx);
  SetDisconnected(False);
end;

procedure TTerminalTab.SpawnFinished(Pid: GPid; Err: string);
begin
  if Err <> '' then
  begin
    FState := tsExited;
    vte_terminal_feed(Term, PChar(#13#10#27'[1;31mUnable to start the session: ' + Err + #27'[0m'#13#10), -1);
    ShowExitMessage(-1);
    Exit;
  end;
  FPid := Pid;
  FState := tsRunning;
  if IsSsh then
  begin
    if FReadyTimer <> 0 then g_source_remove(FReadyTimer);
    FReadyTimer := g_timeout_add(400, @MasterTimerCb, Self);
  end
  else if (Session <> nil) and (Session.StartMacro <> '') then
    FMacroTimer := g_timeout_add(1200, @MacroTimerCb, Self);
  if App <> nil then App.TabChanged(Self);
end;

procedure TTerminalTab.CheckMaster;
begin
  if (FState <> tsRunning) or (FControlPath = '') then
  begin
    if FReadyTimer <> 0 then g_source_remove(FReadyTimer);
    FReadyTimer := 0;
    Exit;
  end;
  if FileExists(FControlPath) or (fpAccess(FControlPath, F_OK) = 0) then
  begin
    FMasterReady := True;
    FWasConnected := True;
    FAutoRetry := False;
    FReconnectTries := 0;
    { the master is authenticated: the one-shot password file is no longer needed }
    SecureDelete(FPassFile);
    FPassFile := '';
    g_source_remove(FReadyTimer);
    FReadyTimer := 0;
    if Settings.RemoteMonitoring then
      SetMonitoring(True);
    if (Session <> nil) and (Session.StartMacro <> '') then
      FMacroTimer := g_timeout_add(800, @MacroTimerCb, Self)   { follows the path afterwards }
    else
      MaybeFollowPath;
    if App <> nil then App.TabChanged(Self);
  end;
end;

{ "Follow SSH path": ask the remote login shell, then (bash / zsh only) make
  it report its working directory with OSC 7 sequences, like VTE does locally }
procedure TTerminalTab.StartFollowPath;
var
  args: TStringArray;
  err: string;
begin
  if FFollowProc <> nil then Exit;
  FFollowProc := TChildProcess.Create;
  FFollowProc.CollectOutput := True;
  FFollowProc.OnExit := @FollowShellKnown;
  args := SshMuxArgs(Session, FControlPath);
  AppendArgs(args, ['--', Session.Host, 'echo "$SHELL"']);
  if not FFollowProc.Start(args, [], HomeDir, False, err) then
  begin
    FreeAndNil(FFollowProc);
    Exit;
  end;
end;

procedure TTerminalTab.MaybeFollowPath;
begin
  if (Session <> nil) and Session.FollowPath and Session.SftpBrowser and Settings.FollowTerminalFolder and FMasterReady then
    StartFollowPath;
end;

function FollowTimerCb(data: gpointer): gboolean; cdecl;
var
  t: TTerminalTab;
begin
  t := TTerminalTab(data);
  t.TryInjectFollow;
  Result := t.FFollowTimer <> 0;
end;

procedure TTerminalTab.FollowShellKnown(Sender: TChildProcess; Status: Integer);
var
  sh: string;
begin
  sh := ExtractFileName(Trim(Sender.Output));
  Sender.OnExit := nil;
  FreeLater(Sender);
  FFollowProc := nil;
  if (Status <> 0) or not Alive then Exit;
  if (sh = 'bash') or (sh = 'zsh') then
  begin
    FFollowShell := sh;
    FFollowTries := 0;
    if FFollowTimer = 0 then
      FFollowTimer := g_timeout_add(400, @FollowTimerCb, Self);
  end;
end;

function TTerminalTab.CursorLineText(out Col: Integer): string;
var
  c, r: glong;
  len: PtrUInt;
begin
  c := 0;
  r := 0;
  vte_terminal_get_cursor_position(Term, @c, @r);
  Col := c;
  len := 0;
  Result := TakeStr(vte_terminal_get_text_range_format(Term, VTE_FORMAT_TEXT, r, 0, r, c, @len));
end;

procedure TTerminalTab.TryInjectFollow;
var
  line, cmd: string;
  col, cols, lines: Integer;
  last: Char;
begin
  Inc(FFollowTries);
  if (not Alive) or FUserTyped or (FFollowTries > 30) then
  begin
    if FFollowTimer <> 0 then g_source_remove(FFollowTimer);
    FFollowTimer := 0;
    Exit;
  end;
  line := TrimRight(CursorLineText(col));
  if line = '' then Exit;
  last := line[Length(line)];
  { only when the shell prompt is displayed }
  if not (last in ['$', '#', '%', '>']) then Exit;
  g_source_remove(FFollowTimer);
  FFollowTimer := 0;
  { OSC 7 tells the current folder, the vte.ext.linxterm.prompt property the
    end of each command with its exit status (desktop notifications) }
  if FFollowShell = 'zsh' then
    cmd := ' _lxosc7() { local s=$?; printf ''\033]7;file://%s%s\033\\\033]666;vte.ext.linxterm.prompt=%s\033\\'' ' +
      '"$HOST" "$PWD" "$s"; return $s; }; precmd_functions=(_lxosc7 $precmd_functions); '
  else
    cmd := ' _lxosc7() { local s=$?; printf ''\033]7;file://%s%s\033\\\033]666;vte.ext.linxterm.prompt=%s\033\\'' ' +
      '"${HOSTNAME:-}" "$PWD" "$s"; return $s; }; PROMPT_COMMAND="_lxosc7${PROMPT_COMMAND:+;$PROMPT_COMMAND}"; ';
  { erase the prompt and the echoed command, the shell prints a fresh prompt }
  cols := vte_terminal_get_column_count(Term);
  if cols < 20 then cols := 80;
  lines := (col + Length(cmd) + 40) div cols + 1;
  cmd := cmd + 'printf ''\r\033[' + IntToStr(lines) + 'A\033[J''' + #13;
  SendInput(cmd);
end;

procedure TTerminalTab.PlayStartMacro;
var
  txt: string;
begin
  if (Session = nil) or (Session.StartMacro = '') or not Alive then Exit;
  if not Assigned(MacroTextByName) then Exit;
  txt := MacroTextByName(Session.StartMacro);
  if txt <> '' then SendInput(txt);
end;

procedure TTerminalTab.ChildExited(Status: Integer);
begin
  if FState = tsExited then Exit;
  FState := tsExited;
  FPid := 0;
  FMasterReady := False;
  SetMonitoring(False);
  CleanupConnection;
  SetDisconnected(True);
  FExitStatus := Status;
  { ssh exits with 255 when the connection is lost: reconnect like a
    network-aware client would (not after a normal logout) }
  if IsSsh and Settings.AutoReconnect and (ExitStatusCode(Status) = 255) and
    (FWasConnected or FAutoRetry) and (FReconnectTries < 10) then
    ScheduleReconnect
  else
    ShowExitMessage(Status);
  if App <> nil then App.TabChanged(Self);
end;

procedure TTerminalTab.ShowExitMessage(Status: Integer);
var
  msg: string;
begin
  msg := #13#10#27'[0m'#27'[1;33m';
  msg := msg + '──────────────────────────────────────────────────────────────' + #13#10;
  if Status >= 0 then
    msg := msg + 'Session stopped' + IfThen(ExitStatusCode(Status) <> 0,
      ' (exit code ' + IntToStr(ExitStatusCode(Status)) + ')', '') + #13#10
  else
    msg := msg + 'Session could not be started' + #13#10;
  msg := msg + '    - Press <Return> to exit tab' + #13#10;
  msg := msg + '    - Press R to restart session' + #13#10;
  msg := msg + '    - Press S to save terminal output to file' + #13#10;
  msg := msg + #27'[0m';
  vte_terminal_feed(Term, PChar(msg), -1);
end;

procedure TTerminalTab.CleanupConnection;
begin
  if FFollowTimer <> 0 then
  begin
    g_source_remove(FFollowTimer);
    FFollowTimer := 0;
  end;
  if FFollowProc <> nil then
  begin
    FFollowProc.OnExit := nil;
    FreeAndNil(FFollowProc);
  end;
  if FReadyTimer <> 0 then
  begin
    g_source_remove(FReadyTimer);
    FReadyTimer := 0;
  end;
  if FMacroTimer <> 0 then
  begin
    g_source_remove(FMacroTimer);
    FMacroTimer := 0;
  end;
  SecureDelete(FPassFile);
  FPassFile := '';
end;

procedure TTerminalTab.Restart;
begin
  CancelReconnect;
  FAutoRetry := False;
  FReconnectTries := 0;
  if Alive and (FPid > 0) then
  begin
    { kill the running process first; ChildExited will be called }
    fpKill(FPid, SIGHUP);
    FState := tsExited;
    FPid := 0;
  end;
  SetMonitoring(False);
  vte_terminal_feed(Term, #13#10, -1);
  Spawn;
  FocusContent;
end;

procedure TTerminalTab.Shutdown;
begin
  { no callback may reach this object once the tab is being destroyed }
  g_signal_handlers_disconnect_matched(Term, G_SIGNAL_MATCH_DATA, 0, 0, nil, nil, Self);
  CancelReconnect;
  SetMonitoring(False);
  if FMonitorProc <> nil then
  begin
    FMonitorProc.Free;
    FMonitorProc := nil;
  end;
  if Alive and (FPid > 0) then
    fpKill(FPid, SIGHUP);
  FState := tsExited;
  CleanupConnection;
end;

procedure TTerminalTab.FocusContent;
begin
  gtk_widget_grab_focus(Term);
end;

function TTerminalTab.KeyPress(Event: Pointer): Boolean;
var
  kv, st: guint;
  ctrlshift: Boolean;
begin
  Result := False;
  kv := EventKeyval(Event);
  st := EventState(Event) and (GDK_SHIFT_MASK or GDK_CONTROL_MASK or GDK_MOD1_MASK or GDK_SUPER_MASK);
  if FReconnectTimer <> 0 then
  begin
    if kv = GDK_KEY_Escape then
    begin
      CancelReconnect;
      vte_terminal_feed(Term, #13#27'[K', -1);
      ShowExitMessage(FExitStatus);
      Exit(True);
    end;
    if ((st = 0) or (st = GDK_SHIFT_MASK)) and ((kv = Ord('r')) or (kv = Ord('R'))) then
    begin
      vte_terminal_feed(Term, #13#27'[K', -1);
      Restart;
      Exit(True);
    end;
    if (kv = GDK_KEY_Return) or (kv = GDK_KEY_KP_Enter) then
    begin
      CancelReconnect;
      App.CloseTabLater(Self);
      Exit(True);
    end;
  end;
  if FState = tsExited then
  begin
    if (kv = GDK_KEY_Return) or (kv = GDK_KEY_KP_Enter) then
    begin
      App.CloseTabLater(Self);
      Exit(True);
    end;
    if (st = 0) or (st = GDK_SHIFT_MASK) then
    begin
      if (kv = Ord('r')) or (kv = Ord('R')) then
      begin
        Restart;
        Exit(True);
      end;
      if (kv = Ord('s')) or (kv = Ord('S')) then
      begin
        SaveOutput;
        Exit(True);
      end;
    end;
  end;
  ctrlshift := st = (GDK_SHIFT_MASK or GDK_CONTROL_MASK);
  if ctrlshift then
  begin
    case gdk_keyval_to_lower(kv) of
      Ord('c'):
        begin
          CopySelection;
          Exit(True);
        end;
      Ord('v'):
        begin
          Paste;
          Exit(True);
        end;
      Ord('f'):
        begin
          ShowSearch;
          Exit(True);
        end;
      Ord('a'):
        begin
          SelectAll;
          Exit(True);
        end;
    end;
  end;
  if (st = GDK_SHIFT_MASK) and (kv = GDK_KEY_Insert) then
  begin
    Paste;
    Exit(True);
  end;
  if st = GDK_CONTROL_MASK then
  begin
    if (kv = GDK_KEY_plus) or (kv = GDK_KEY_equal) or (kv = GDK_KEY_KP_Add) then
    begin
      ZoomIn;
      Exit(True);
    end;
    if (kv = GDK_KEY_minus) or (kv = GDK_KEY_KP_Subtract) then
    begin
      ZoomOut;
      Exit(True);
    end;
    if (kv = GDK_KEY_0) or (kv = GDK_KEY_KP_0) then
    begin
      ZoomReset;
      Exit(True);
    end;
  end;
end;

function TTerminalTab.ButtonPress(Event: Pointer): Boolean;
var
  btn, st: guint;
  tag: gint;
  url: string;
  menu: Pointer;
  hyper: Boolean;
begin
  Result := False;
  if gdk_event_get_event_type(Event) <> GDK_BUTTON_PRESS then Exit;
  btn := EventButton(Event);
  st := EventState(Event);
  if btn = 3 then
  begin
    gtk_widget_grab_focus(Term);
    if Settings.PasteRightClick and ((st and GDK_CONTROL_MASK) = 0) then
      Paste
    else
      ShowContextMenu(Event);
    Exit(True);
  end;
  if (btn = 1) and ((st and GDK_CONTROL_MASK) <> 0) then
  begin
    url := TakeStr(vte_terminal_hyperlink_check_event(Term, Event));
    { the text of an OSC 8 hyperlink can differ from its target: confirm }
    hyper := url <> '';
    tag := -1;
    if url = '' then
      url := MatchAt(Event, tag);
    if url = '' then Exit;
    if (tag = FIpTag) and (tag >= 0) then
    begin
      { an address: choose what to do with it }
      menu := gtk_menu_new;
      AddAddressItems(menu, url);
      PopupMenuAtPointer(menu, Term, Event);
    end
    else
      OpenLink(url, hyper);
    Exit(True);
  end;
end;

procedure TTerminalTab.AddAddressItems(Menu: Pointer; const Addr: string);
var
  host: string;
begin
  host := Addr;
  if Pos(':', host) > 0 then host := Copy(host, 1, Pos(':', host) - 1);
  AddrItem(Menu, 'SSH to ' + Addr, 'putty', @MenuConnectTo, Addr, 'ssh');
  AddrItem(Menu, 'SFTP browser on ' + Addr, 'gftp', @MenuConnectTo, Addr, 'sftp');
  AddrItem(Menu, 'RDP to ' + Addr, 'krdc', @MenuConnectTo, Addr, 'rdp');
  AddrItem(Menu, 'VNC to ' + Addr, 'tigervnc', @MenuConnectTo, Addr, 'vnc');
  AddrItem(Menu, 'Telnet to ' + Addr, 'gtkterm', @MenuConnectTo, Addr, 'telnet');
  NewMenuSeparator(Menu);
  AddrItem(Menu, 'Ping ' + host, 'network-workgroup', @MenuPing, Addr, '');
  AddrItem(Menu, 'Open http://' + Addr + ' in the web browser', 'web-browser', @MenuOpenUrl, 'http://' + Addr, '');
  AddrItem(Menu, 'Copy ' + Addr, 'edit-copy', @MenuCopyText, Addr, '');
end;

procedure TTerminalTab.AddLinkItems(Menu: Pointer; const Url: string);
var
  shown: string;
begin
  { the real target is shown (underscores doubled: menu mnemonics) }
  shown := Url;
  if Length(shown) > 70 then shown := Copy(shown, 1, 67) + '...';
  AddrItem(Menu, 'Open ' + StringReplace(shown, '_', '__', [rfReplaceAll]), 'web-browser', @MenuOpenLink, Url, '', Self);
  AddrItem(Menu, 'Copy the link address', 'edit-copy', @MenuCopyText, Url, '');
end;

{ a link of the terminal output: web and mail links open in the browser,
  ssh / sftp / telnet / rdp / vnc addresses in LinXterm (checked like any
  session), local files only from local shells; anything else (javascript:,
  data:, smb:...) is refused }
procedure TTerminalTab.OpenLink(const Url: string; Confirm: Boolean);
var
  scheme, rest, user, host: string;
  p: Integer;
  s: TSession;
begin
  p := Pos(':', Url);
  if p < 2 then Exit;
  scheme := LowerCase(Copy(Url, 1, p - 1));
  if (scheme = 'http') or (scheme = 'https') or (scheme = 'ftp') or (scheme = 'ftps') or (scheme = 'mailto') or
    ((scheme = 'file') and IsLocalShell) then
  begin
    if (Confirm or (scheme = 'file')) and not AskYesNo('Open this link?', Url) then Exit;
    OpenUri(Url);
    Exit;
  end;
  if (scheme = 'ssh') or (scheme = 'sftp') or (scheme = 'telnet') or (scheme = 'rdp') or (scheme = 'vnc') then
  begin
    rest := Copy(Url, p + 1, MaxInt);
    if Copy(rest, 1, 2) = '//' then Delete(rest, 1, 2);
    p := Pos('/', rest);
    if p > 0 then rest := Copy(rest, 1, p - 1);
    user := '';
    p := LastDelimiter('@', rest);
    if p > 0 then
    begin
      user := Copy(rest, 1, p - 1);
      rest := Copy(rest, p + 1, MaxInt);
      { ssh://user;fingerprint=...@host }
      if Pos(';', user) > 0 then user := Copy(user, 1, Pos(';', user) - 1);
    end;
    s := TSession.Create(KindFromId(scheme));
    try
      host := rest;
      p := LastDelimiter(':', rest);
      if (p > 0) and (p > Pos(']', rest)) and (StrToIntDef(Copy(rest, p + 1, 6), -1) > 0) then
      begin
        host := Copy(rest, 1, p - 1);
        s.Port := StrToInt(Copy(rest, p + 1, 6));
      end;
      if (Length(host) > 2) and (host[1] = '[') and (host[Length(host)] = ']') then
        host := Copy(host, 2, Length(host) - 2);
      if host = '' then Exit;
      s.Host := host;
      s.User := user;
      if Confirm and not AskYesNo('Open this connection?', Url) then Exit;
      App.OpenSession(s);
    finally
      s.Free;
    end;
    Exit;
  end;
  if App <> nil then
    App.SetStatus('Link not opened: "' + scheme + ':" addresses are not allowed from a terminal');
end;

function TTerminalTab.AddMatch(const Pattern: string): gint;
var
  rx: Pointer;
  err: PGError;
begin
  Result := -1;
  err := nil;
  rx := vte_regex_new_for_match(PChar(Pattern), -1, PCRE2_MULTILINE or PCRE2_UTF, @err);
  if rx = nil then
  begin
    WriteLn(StdErr, 'terminal match: ', ErrMsg(err));
    Exit;
  end;
  Result := vte_terminal_match_add_regex(Term, rx, 0);
  vte_regex_unref(rx);
  vte_terminal_match_set_cursor_name(Term, Result, 'pointer');
end;

{ link or address under the mouse ('' when none) }
function TTerminalTab.MatchAt(Event: Pointer; out Tag: gint): string;
begin
  Tag := -1;
  Result := TakeStr(vte_terminal_match_check_event(Term, Event, @Tag));
  if (Result <> '') and (Tag = FUrlTag) and (Pos('://', Result) = 0) then
    Result := 'https://' + Result;
end;

procedure TTerminalTab.ShowContextMenu(Event: Pointer);
var
  menu, sub, item: Pointer;
  i, cur: Integer;
  curname, url: string;
  tag: gint;
begin
  menu := gtk_menu_new;
  url := TakeStr(vte_terminal_hyperlink_check_event(Term, Event));
  tag := FUrlTag;
  if url = '' then url := MatchAt(Event, tag);
  if url <> '' then
  begin
    if (tag = FIpTag) and (tag >= 0) then AddAddressItems(menu, url) else AddLinkItems(menu, url);
    NewMenuSeparator(menu);
  end;
  item := NewImageMenuItem(menu, '_Copy        Ctrl+Shift+C', 'edit-copy', @MenuCopy, Self);
  gtk_widget_set_sensitive(item, vte_terminal_get_has_selection(Term));
  NewImageMenuItem(menu, '_Paste       Ctrl+Shift+V', 'edit-paste', @MenuPaste, Self);
  NewImageMenuItem(menu, 'Select _all', 'edit-select-all', @MenuSelectAll, Self);
  NewMenuSeparator(menu);
  NewImageMenuItem(menu, '_Find...     Ctrl+Shift+F', 'edit-find', @MenuFind, Self);
  NewImageMenuItem(menu, 'C_lear scrollback', 'edit-clear', @MenuClear, Self);
  NewImageMenuItem(menu, 'R_eset terminal', 'view-refresh', @MenuReset, Self);
  NewImageMenuItem(menu, '_Save terminal text to file...', 'document-save', @MenuSave, Self);
  NewMenuSeparator(menu);
  sub := NewSubMenu(menu, 'Font si_ze', 'preferences-desktop-font');
  NewMenuItem(sub, 'Increase   Ctrl++', @MenuZoomIn, Self);
  NewMenuItem(sub, 'Decrease   Ctrl+-', @MenuZoomOut, Self);
  NewMenuItem(sub, 'Reset        Ctrl+0', @MenuZoomReset, Self);
  sub := NewSubMenu(menu, 'Color _scheme', 'preferences-desktop-theme');
  curname := Settings.ColorScheme;
  if (Session <> nil) and (Session.ColorScheme <> '') then curname := Session.ColorScheme;
  cur := FindColorScheme(curname);
  for i := 0 to ColorSchemeCount - 1 do
  begin
    item := gtk_check_menu_item_new_with_label(PChar(ColorSchemes[i].Name));
    gtk_check_menu_item_set_draw_as_radio(item, True);
    gtk_check_menu_item_set_active(item, i = cur);
    g_object_set_data(item, 'scheme', Pointer(PtrInt(i)));
    Connect(item, 'toggled', @MenuScheme, Self);
    gtk_menu_shell_append(sub, item);
  end;
  if IsSsh and FMasterReady then
    NewCheckMenuItem(menu, 'Remote _monitoring', FMonitorTimer <> 0, @MenuMonitoring, Self);
  item := NewCheckMenuItem(menu, 'Syntax _highlighting (errors, warnings, OK)', FRelay and FHighlight, @MenuHighlight, Self);
  if not (FRelay and Alive) then
  begin
    gtk_widget_set_sensitive(item, False);
    gtk_widget_set_tooltip_text(item, 'Enable it in Settings > Configuration > Terminal: it applies to the sessions started afterwards');
  end;
  if FLogName <> '' then
    NewImageMenuItem(menu, 'Open the session _log', 'text-x-generic', @MenuOpenLog, Self);
  NewImageMenuItem(menu, 'Open the logs folder', 'folder', @MenuLogFolder, Self);
  NewMenuSeparator(menu);
  if CanDuplicate then
    NewImageMenuItem(menu, '_Duplicate tab', 'tab-new', @MenuDuplicate, Self);
  NewImageMenuItem(menu, 'Re_name tab', 'document-edit', @MenuRename, Self);
  NewImageMenuItem(menu, '_Restart session', 'view-refresh', @MenuRestart, Self);
  NewImageMenuItem(menu, 'De_tach tab', 'window-new', @MenuDetach, Self);
  NewImageMenuItem(menu, 'Close _tab', 'window-close', @MenuClose, Self);
  PopupMenuAtPointer(menu, Term, Event);
end;

procedure TTerminalTab.CopySelection;
begin
  if vte_terminal_get_has_selection(Term) then
    vte_terminal_copy_clipboard_format(Term, VTE_FORMAT_TEXT);
end;

function ConfirmMultilinePaste(const Text, Where: string): Boolean;
var
  dlg, area, box, lbl, view, scroll, never, b: Pointer;
  lines: TStringArray;
  preview: string;
  i, n: Integer;
begin
  lines := SplitString(StringReplace(StringReplace(Text, #13#10, #10, [rfReplaceAll]), #13, #10, [rfReplaceAll]), #10);
  n := Length(lines);
  if (n > 1) and (lines[n - 1] = '') then Dec(n);
  preview := '';
  for i := 0 to Min(n, 12) - 1 do
    preview := preview + lines[i] + #10;
  if n > 12 then preview := preview + '... (' + IntToStr(n - 12) + ' more lines)';
  dlg := gtk_dialog_new_with_buttons('Paste several lines?', MainWindowWidget,
    GTK_DIALOG_MODAL or GTK_DIALOG_DESTROY_WITH_PARENT, nil);
  gtk_window_set_default_size(dlg, 560, -1);
  area := gtk_dialog_get_content_area(dlg);
  box := gtk_box_new(GTK_ORIENTATION_VERTICAL, 8);
  SetMargins(box, 12);
  lbl := NewMarkupLabel('<b>You are about to paste ' + IntToStr(n) + ' line' + IfThen(n > 1, 's', '') +
    ' into "' + MarkupEscape(Where) + '".</b>'#10 +
    'Each line break may run a command immediately.', 0);
  gtk_box_pack_start(box, lbl, False, False, 0);
  view := gtk_text_view_new;
  gtk_text_view_set_editable(view, False);
  gtk_text_view_set_monospace(view, True);
  gtk_text_view_set_cursor_visible(view, False);
  gtk_text_view_set_left_margin(view, 6);
  gtk_text_buffer_set_text(gtk_text_view_get_buffer(view), PChar(preview), -1);
  scroll := NewScrolled(view);
  gtk_scrolled_window_set_min_content_height(scroll, 140);
  gtk_box_pack_start(box, scroll, True, True, 0);
  never := gtk_check_button_new_with_label('Do not ask again (Settings > Terminal)');
  gtk_box_pack_start(box, never, False, False, 0);
  gtk_box_pack_start(area, box, True, True, 0);
  b := gtk_dialog_add_button(dlg, '_Cancel', GTK_RESPONSE_CANCEL);
  gtk_button_set_image(b, NewIcon('lx-cancel', 16));
  gtk_button_set_always_show_image(b, True);
  b := gtk_dialog_add_button(dlg, '_Paste', GTK_RESPONSE_OK);
  gtk_button_set_image(b, NewIcon('edit-paste', 16));
  gtk_button_set_always_show_image(b, True);
  gtk_dialog_set_default_response(dlg, GTK_RESPONSE_OK);
  gtk_widget_show_all(dlg);
  Result := gtk_dialog_run(dlg) = GTK_RESPONSE_OK;
  if Result and gtk_toggle_button_get_active(never) then
  begin
    Settings.PasteWarnMultiline := False;
    Settings.Save;
  end;
  gtk_widget_destroy(dlg);
end;

procedure TTerminalTab.Paste;
var
  txt: string;
begin
  { the pasted text goes through the "commit" signal, so MultiExec and
    macro recording see it like typed text }
  if not Settings.PasteWarnMultiline then
  begin
    vte_terminal_paste_clipboard(Term);
    Exit;
  end;
  txt := TakeStr(gtk_clipboard_wait_for_text(gtk_clipboard_get(GDK_SELECTION_CLIPBOARD)));
  if txt = '' then Exit;
  if (Pos(#10, txt) > 0) or (Pos(#13, txt) > 0) then
  begin
    if not ConfirmMultilinePaste(txt, FullTitle) then
    begin
      FocusContent;
      Exit;
    end;
    FocusContent;
  end;
  vte_terminal_paste_text(Term, PChar(txt));
end;

procedure TTerminalTab.PasteText(const T: string);
begin
  if T <> '' then
    vte_terminal_paste_text(Term, PChar(T));
end;

procedure TTerminalTab.SelectAll;
begin
  vte_terminal_select_all(Term);
end;

procedure TTerminalTab.ClearScrollback;
begin
  vte_terminal_reset(Term, False, True);
  if Alive then SendInput(#12);
end;

procedure TTerminalTab.ResetTerminal;
begin
  vte_terminal_reset(Term, True, False);
  if Alive then SendInput(#12);
end;

procedure TTerminalTab.ZoomIn;
begin
  FFontScale := FFontScale * 1.1;
  if FFontScale > 4 then FFontScale := 4;
  vte_terminal_set_font_scale(Term, FFontScale);
end;

procedure TTerminalTab.ZoomOut;
begin
  FFontScale := FFontScale / 1.1;
  if FFontScale < 0.3 then FFontScale := 0.3;
  vte_terminal_set_font_scale(Term, FFontScale);
end;

procedure TTerminalTab.ZoomReset;
begin
  FFontScale := 1.0;
  vte_terminal_set_font_scale(Term, FFontScale);
end;

procedure TTerminalTab.ShowSearch;
begin
  gtk_revealer_set_reveal_child(FSearchRevealer, True);
  gtk_widget_grab_focus(FSearchEntry);
end;

procedure TTerminalTab.HideSearch;
begin
  gtk_revealer_set_reveal_child(FSearchRevealer, False);
  vte_terminal_search_set_regex(Term, nil, 0);
  gtk_widget_grab_focus(Term);
end;

procedure TTerminalTab.DoSearch(Backward: Boolean);
var
  txt, pat: string;
  flags: guint32;
  rx: Pointer;
  err: PGError;
begin
  txt := EntryText(FSearchEntry);
  if txt = '' then
  begin
    vte_terminal_search_set_regex(Term, nil, 0);
    Exit;
  end;
  pat := TakeStr(g_regex_escape_string(PChar(txt), -1));
  flags := PCRE2_MULTILINE or PCRE2_UTF;
  if not gtk_toggle_button_get_active(FSearchCase) then
    flags := flags or PCRE2_CASELESS;
  err := nil;
  rx := vte_regex_new_for_search(PChar(pat), -1, flags, @err);
  if rx = nil then
  begin
    ErrMsg(err);
    Exit;
  end;
  vte_terminal_search_set_regex(Term, rx, 0);
  vte_regex_unref(rx);
  vte_terminal_search_set_wrap_around(Term, True);
  if Backward then
    vte_terminal_search_find_previous(Term)
  else
    vte_terminal_search_find_next(Term);
end;

procedure TTerminalTab.SaveOutput;
var
  fn: string;
  f, stream: Pointer;
  err: PGError;
begin
  if not ChooseSaveFile('Save terminal output', HomeDir,
    StringReplace(Title, '/', '_', [rfReplaceAll]) + '.txt', fn) then Exit;
  err := nil;
  f := g_file_new_for_path(PChar(fn));
  stream := g_file_replace(f, nil, False, G_FILE_CREATE_NONE, nil, @err);
  if stream <> nil then
  begin
    vte_terminal_write_contents_sync(Term, stream, VTE_WRITE_DEFAULT, nil, @err);
    g_output_stream_close(stream, nil, nil);
    g_object_unref(stream);
  end;
  g_object_unref(f);
  if err <> nil then
    MsgError('Unable to save the terminal output', ErrMsg(err))
  else if App <> nil then
    App.SetStatus('Terminal output saved to ' + fn);
end;

procedure TTerminalTab.SendInput(const Data: string);
begin
  if (Data = '') or not Alive then Exit;
  if Pos(#13, Data) > 0 then NoteEnter(Data);
  FFeeding := True;
  try
    vte_terminal_feed_child(Term, PChar(Data), Length(Data));
  finally
    FFeeding := False;
  end;
end;

procedure TTerminalTab.TypeInput(const Data: string);
begin
  { behaves like keyboard input (used by automated tests) }
  if (Data <> '') and Alive then
    vte_terminal_feed_child(Term, PChar(Data), Length(Data));
end;

{ ---------------------------------------------------------------- session log }

function TTerminalTab.WantLog: Boolean;
begin
  Result := (Length(FCustomArgv) = 0) and (Session <> nil) and
    (Settings.LogTerminal or Session.LogOutput);
end;

function TTerminalTab.WantHighlight: Boolean;
begin
  Result := (Length(FCustomArgv) = 0) and (Session <> nil);
  if not Result then Exit;
  if Session.Highlight = 'on' then Result := True
  else if Session.Highlight = 'off' then Result := False
  else Result := Settings.SyntaxHighlight;
end;

{ runs the session through "lxrelay", which colours the keywords of the
  output and / or copies it to a text file }
procedure TTerminalTab.WrapWithRelay(var Argv: TStringArray);
var
  i: Integer;
  wrapped: TStringArray;
  logArg: string;
begin
  logArg := '-';
  if WantLog and PrepareLog then logArg := FLogName;
  FHighlight := WantHighlight;
  wrapped := nil;
  AppendArgs(wrapped, [HelperPath('lxrelay'), logArg, IfThen(Settings.LogTimestamps, '1', '0'),
    IfThen(FHighlight, '1', '0')]);
  for i := 0 to High(Argv) do
    AppendArg(wrapped, Argv[i]);
  Argv := wrapped;
  FRelay := True;
end;

{ creates the log file (a restarted session goes on writing to the same file) }
function TTerminalTab.PrepareLog: Boolean;
var
  dir, base, hdr: string;
  i: Integer;
  fd: cint;
begin
  Result := False;
  dir := Settings.LogDir;
  if not ForceDirectories(dir) then
  begin
    if App <> nil then App.SetStatus('Unable to create the log folder ' + dir);
    Exit;
  end;
  { the logs may show confidential output: the default folder is private }
  if Settings.LogFolder = '' then fpChmod(dir, &700);
  if FLogName = '' then
  begin
    base := Session.Name;
    if base = '' then base := Title;
    if base = '' then base := 'terminal';
    for i := 1 to Length(base) do
      if not (base[i] in ['A'..'Z', 'a'..'z', '0'..'9', '.', '-', '_', '@']) then base[i] := '_';
    FLogName := dir + '/' + base + '_' + FormatDateTime('yyyymmdd_hhnnss', Now) + '.log';
    hdr := '==== ' + APP_NAME + ' ' + APP_VERSION + ' - ' + SessionKindNames[Session.Kind] + ' session';
    if Session.Kind <> skShell then hdr := hdr + ' to ' + Session.Target;
    hdr := hdr + ' - started ' + FormatDateTime('yyyy-mm-dd hh:nn:ss', Now) + ' ====' + #10;
  end
  else
    hdr := #10'==== session restarted ' + FormatDateTime('yyyy-mm-dd hh:nn:ss', Now) + ' ====' + #10;
  fd := fpOpen(FLogName, O_WRONLY or O_CREAT or O_APPEND, &600);
  if fd < 0 then Exit;
  fpWrite(fd, hdr[1], Length(hdr));
  fpClose(fd);
  Result := True;
end;

{ switches the keyword colouring of the running session (lxrelay signals) }
procedure TTerminalTab.SetHighlight(V: Boolean; Remember: Boolean);
begin
  { Remember: the choice made for this tab survives a restart }
  if Remember and (Session <> nil) then
    if V then Session.Highlight := 'on' else Session.Highlight := 'off';
  if FRelay and Alive and (FPid > 0) then
  begin
    if V then fpKill(FPid, SIGUSR1) else fpKill(FPid, SIGUSR2);
    FHighlight := V;
  end;
end;

procedure TTerminalTab.OpenLog;
begin
  if FLogName <> '' then
  begin
    if Assigned(OpenEditorProc) then OpenEditorProc(FLogName) else OpenPath(FLogName);
  end;
end;

{ ---------------------------------------------------------------- tab activity / zoom }

procedure TTerminalTab.QuietFor(Ms: Integer);
var
  t: Int64;
begin
  t := g_get_monotonic_time + Int64(Ms) * 1000;
  if t > FQuietUntil then FQuietUntil := t;
end;

procedure TTerminalTab.NoteActivity(Bell: Boolean);
begin
  if (App = nil) or (FState <> tsRunning) then Exit;
  if Bell and (MainWindowWidget <> nil) and not gtk_window_is_active(gtk_widget_get_toplevel(Term)) then
    gtk_window_set_urgency_hint(gtk_widget_get_toplevel(Term), True);
  if Bell and Settings.Notifications and not UserWatching and
    (g_get_monotonic_time - FLastBellNotify > 10000000) then
  begin
    FLastBellNotify := g_get_monotonic_time;
    App.NotifyTab(Self, '🔔 ' + FullTitle, 'The terminal rang the bell.');
  end;
  if not Settings.TabActivity or HasActivity then Exit;
  if (not Bell) and (g_get_monotonic_time < FQuietUntil) then Exit;
  if App.TabVisible(Self) then Exit;
  SetActivity(True);
end;

{ the user is looking at this terminal right now }
function TTerminalTab.UserWatching: Boolean;
var
  top: Pointer;
begin
  top := gtk_widget_get_toplevel(Term);
  Result := (top <> nil) and gtk_window_is_active(top) and (App <> nil) and App.TabVisible(Self);
end;

function Utf8Cut(const S: string; Max: Integer): string;
var
  n: Integer;
begin
  if Length(S) <= Max then Exit(S);
  n := Max;
  { do not cut a character in two }
  while (n > 0) and ((Ord(S[n + 1]) and $C0) = $80) do Dec(n);
  Result := Copy(S, 1, n) + '…';
end;

{ the command line being validated: the cursor line without the prompt,
  followed by Typed (text sent with the Return key, not displayed yet) }
function TTerminalTab.CommandAtCursor(const Typed: string): string;
const
  Marks: array[0..4] of string = ('➤ ', '$ ', '# ', '% ', '> ');
var
  line: string;
  col, i, p, best, blen: Integer;
begin
  line := CursorLineText(col) + Typed;
  best := 0;
  blen := 0;
  for i := 0 to High(Marks) do
  begin
    p := Pos(Marks[i], line);
    if (p > 0) and ((best = 0) or (p < best)) then
    begin
      best := p;
      blen := Length(Marks[i]);
    end;
  end;
  if best > 0 then line := Copy(line, best + blen, MaxInt);
  Result := Utf8Cut(Trim(line), 60);
end;

{ Return pressed (or sent) while the shell shows its prompt: a command starts }
procedure TTerminalTab.NoteEnter(const Data: string);
var
  typed: string;
  i: Integer;
begin
  if not FAtPrompt then Exit;
  FAtPrompt := False;
  FCmdStart := g_get_monotonic_time;
  { the text before the first Return, without control characters }
  typed := Copy(Data, 1, Pos(#13, Data) - 1);
  for i := Length(typed) downto 1 do
    if typed[i] < ' ' then Delete(typed, i, 1);
  FCmdText := CommandAtCursor(typed);
end;

function FormatDuration(Secs: Int64): string;
begin
  if Secs < 60 then Result := IntToStr(Secs) + ' s'
  else if Secs < 3600 then Result := Format('%d min %.2d s', [Secs div 60, Secs mod 60])
  else Result := Format('%d h %.2d min', [Secs div 3600, (Secs mod 3600) div 60]);
end;

{ the LinXterm prompt (local bash, remote bash / zsh) sets the
  vte.ext.linxterm.prompt property with the exit status of the last command:
  a desktop notification tells when a long command ends while nobody looks }
procedure TTerminalTab.TermpropChanged(const Name: string);
var
  v: QWord;
  secs: Int64;
  head: string;
  status: Integer;
begin
  if Name <> 'vte.ext.linxterm.prompt' then Exit;
  v := 0;
  if not vte_terminal_get_termprop_uint(Term, 'vte.ext.linxterm.prompt', @v) then Exit;
  status := Integer(v and $FFFF);
  FAtPrompt := True;
  if FCmdStart = 0 then Exit;
  secs := (g_get_monotonic_time - FCmdStart) div 1000000;
  FCmdStart := 0;
  if (App = nil) or not Settings.Notifications or (Settings.NotifyAfter <= 0) or
    (secs < Settings.NotifyAfter) or (FCmdText = '') or UserWatching then Exit;
  if status = 0 then
    head := '✔ ' + FCmdText
  else
    head := '✘ ' + FCmdText + '  (exit code ' + IntToStr(status) + ')';
  App.NotifyTab(Self, head, IfThen(status = 0, 'Finished', 'Failed') + ' after ' + FormatDuration(secs) +
    '  -  ' + FullTitle);
end;

{ the property must exist before the first terminal is created }
procedure InstallTermprops;
const
  VTE_PROPERTY_UINT = 3;
  VTE_PROPERTY_FLAG_EPHEMERAL = 1;
begin
  if TermpropsAvailable then
    vte_install_termprop('vte.ext.linxterm.prompt', VTE_PROPERTY_UINT, VTE_PROPERTY_FLAG_EPHEMERAL);
end;

function TTerminalTab.ScrollZoom(Event: Pointer): Boolean;
var
  dir: gint;
  dx, dy: gdouble;
begin
  Result := False;
  if (EventState(Event) and (GDK_CONTROL_MASK or GDK_SHIFT_MASK or GDK_MOD1_MASK)) <> GDK_CONTROL_MASK then Exit;
  dir := -1;
  if gdk_event_get_scroll_direction(Event, @dir) then
  begin
    if dir = GDK_SCROLL_UP then ZoomIn
    else if dir = GDK_SCROLL_DOWN then ZoomOut;
  end
  else if gdk_event_get_scroll_deltas(Event, @dx, @dy) then
  begin
    { touchpads send many small steps }
    FScrollAccum := FScrollAccum + dy;
    while FScrollAccum <= -1 do
    begin
      ZoomIn;
      FScrollAccum := FScrollAccum + 1;
    end;
    while FScrollAccum >= 1 do
    begin
      ZoomOut;
      FScrollAccum := FScrollAccum - 1;
    end;
  end;
  Result := True;
end;

{ ---------------------------------------------------------------- automatic reconnection }

const
  ReconnectDelays: array[0..9] of Integer = (3, 5, 10, 15, 20, 30, 30, 30, 30, 30);
  ReconnectMax = 10;

procedure TTerminalTab.ShowReconnectLine;
begin
  vte_terminal_feed(Term, PChar(#13#27'[K'#27'[1;33m↻ Reconnecting in ' + IntToStr(FReconnectLeft) + ' s' +
    '  (attempt ' + IntToStr(FReconnectTries) + '/' + IntToStr(ReconnectMax) + ')' + #27'[0m' +
    '   R: reconnect now   Esc: cancel   Return: close tab'), -1);
end;

procedure TTerminalTab.ScheduleReconnect;
begin
  CancelReconnect;
  FReconnectLeft := ReconnectDelays[Min(FReconnectTries, High(ReconnectDelays))];
  Inc(FReconnectTries);
  if FReconnectTries = 1 then
    vte_terminal_feed(Term, PChar(#13#10#27'[0m'#27'[1;31m✘ Connection to ' + Session.Host + ' lost.' + #27'[0m'#13#10), -1)
  else
    vte_terminal_feed(Term, PChar(#13#10#27'[1;31m✘ ' + Session.Host + ' is not reachable yet.' + #27'[0m'#13#10), -1);
  ShowReconnectLine;
  FReconnectTimer := g_timeout_add(1000, @ReconnectTimerCb, Self);
end;

procedure TTerminalTab.CancelReconnect;
begin
  if FReconnectTimer <> 0 then
  begin
    g_source_remove(FReconnectTimer);
    FReconnectTimer := 0;
  end;
end;

procedure TTerminalTab.ReconnectTick;
var
  tries: Integer;
begin
  FReconnectTimer := 0;   { one-shot source: it is removed after this call }
  Dec(FReconnectLeft);
  if FReconnectLeft > 0 then
  begin
    ShowReconnectLine;
    FReconnectTimer := g_timeout_add(1000, @ReconnectTimerCb, Self);
    Exit;
  end;
  vte_terminal_feed(Term, #13#27'[K', -1);
  tries := FReconnectTries;
  Restart;
  { Restart resets the counters of a manual restart }
  FAutoRetry := True;
  FReconnectTries := tries;
end;

{ ---------------------------------------------------------------- remote monitoring }

const
  MonitorScript =
    'LC_ALL=C; head -n1 /proc/stat; ' +
    'grep -E "^(MemTotal|MemAvailable):" /proc/meminfo; ' +
    'cat /proc/loadavg; cut -d" " -f1 /proc/uptime | sed "s/^/UP /"; ' +
    'df -P / | tail -n1 | sed "s/^/DF /"; ' +
    'awk ''NR>2 && $1 !~ /^lo:/ {sub(/^[^:]*:/,""); rx+=$1; tx+=$9} END {print "NET", rx+0, tx+0}'' /proc/net/dev; ' +
    'echo "USERS $(who 2>/dev/null | wc -l)"';

procedure TTerminalTab.SetMonitoring(Enabled: Boolean);
var
  i: Integer;
begin
  if Enabled and IsSsh and FMasterReady then
  begin
    if FMonitorTimer = 0 then
    begin
      FPrevCpuTotal := 0;
      FPrevCpuIdle := 0;
      FPrevNetTime := 0;
      gtk_label_set_markup(FMonitorLabel, PChar('<b>' + MarkupEscape(Session.Host) + '</b>   ' +
        '<span foreground="#808080">remote monitoring: collecting data...</span>'));
      gtk_widget_set_no_show_all(FMonitorBar, False);
      gtk_widget_show_all(FMonitorBar);
      for i := 1 to High(FMonItems) do
        gtk_widget_hide(FMonItems[i]);
      FMonitorTimer := g_timeout_add(3000, @MonitorTimerCb, Self);
      MonitorTick;
    end;
  end
  else
  begin
    if FMonitorTimer <> 0 then
    begin
      g_source_remove(FMonitorTimer);
      FMonitorTimer := 0;
    end;
    gtk_widget_hide(FMonitorBar);
  end;
end;

procedure TTerminalTab.MonitorTick;
var
  args: TStringArray;
  err: string;
begin
  if not (IsSsh and FMasterReady and Alive) then
  begin
    SetMonitoring(False);
    Exit;
  end;
  if (FMonitorProc <> nil) and FMonitorProc.Running then Exit;
  if FMonitorProc = nil then
  begin
    FMonitorProc := TChildProcess.Create;
    FMonitorProc.CollectOutput := True;
    FMonitorProc.OnExit := @MonitorOutput;
  end;
  args := SshMuxArgs(Session, FControlPath);
  AppendArgs(args, ['--', Session.Host, MonitorScript]);
  FMonitorProc.Start(args, [], HomeDir, False, err);
end;

procedure TTerminalTab.MonitorOutput(Sender: TChildProcess; Status: Integer);
var
  lines, f: TStringArray;
  line, txt: string;
  total, idle, memTotal, memAvail, rx, tx, now_: Int64;
  i: Integer;
  cpu: Double;
  load, disk, users, up, net: string;
  upsec: Int64;
  dt: Double;
begin
  if (FMonitorTimer = 0) or (Status <> 0) then Exit;
  lines := SplitString(Sender.Output, #10);
  cpu := -1;
  memTotal := 0;
  memAvail := 0;
  load := '';
  disk := '';
  users := '';
  up := '';
  net := '';
  for line in lines do
  begin
    if line = '' then Continue;
    f := SplitString(DelSpace1(Trim(line)), ' ');
    if Length(f) = 0 then Continue;
    if (f[0] = 'cpu') and (Length(f) >= 5) then
    begin
      total := 0;
      for i := 1 to High(f) do
        total := total + StrToInt64Def(f[i], 0);
      idle := StrToInt64Def(f[4], 0);
      if Length(f) > 5 then idle := idle + StrToInt64Def(f[5], 0);
      if (FPrevCpuTotal > 0) and (total > FPrevCpuTotal) then
        cpu := 100.0 * (1 - (idle - FPrevCpuIdle) / (total - FPrevCpuTotal));
      FPrevCpuTotal := total;
      FPrevCpuIdle := idle;
    end
    else if f[0] = 'MemTotal:' then memTotal := StrToInt64Def(f[1], 0)
    else if f[0] = 'MemAvailable:' then memAvail := StrToInt64Def(f[1], 0)
    else if f[0] = 'UP' then
    begin
      upsec := Trunc(StrToFloatDef(StringReplace(f[1], '.', DefaultFormatSettings.DecimalSeparator, []), 0));
      if upsec >= 86400 then
        up := Format('%dd %.2dh', [upsec div 86400, (upsec mod 86400) div 3600])
      else
        up := Format('%.2dh %.2dm', [upsec div 3600, (upsec mod 3600) div 60]);
    end
    else if (f[0] = 'DF') and (Length(f) >= 6) then disk := f[5]
    else if (f[0] = 'NET') and (Length(f) >= 3) then
    begin
      rx := StrToInt64Def(f[1], 0);
      tx := StrToInt64Def(f[2], 0);
      now_ := g_get_monotonic_time;
      if FPrevNetTime > 0 then
      begin
        dt := (now_ - FPrevNetTime) / 1000000;
        if dt > 0 then
          net := Format('▼ %s/s  ▲ %s/s', [HumanSize(Round((rx - FPrevRx) / dt)), HumanSize(Round((tx - FPrevTx) / dt))]);
      end;
      FPrevRx := rx;
      FPrevTx := tx;
      FPrevNetTime := now_;
    end
    else if (f[0] = 'USERS') and (Length(f) >= 2) then users := f[1]
    else if (Length(f) >= 5) and (Pos('/', f[3]) > 0) then load := f[0];
  end;
  gtk_label_set_markup(FMonitorLabel, PChar('<b>' + MarkupEscape(Session.Host) + '</b>'));
  for i := 1 to High(FMonItems) do
    gtk_widget_show(FMonItems[i]);
  if cpu >= 0 then
  begin
    gtk_label_set_markup(FMonCpu, PChar(Format('CPU <b>%.0f%%</b>', [cpu])));
    gtk_level_bar_set_value(FMonCpuBar, Min(1.0, Max(0.0, cpu / 100)));
  end
  else
    gtk_label_set_markup(FMonCpu, 'CPU <b>…</b>');
  if load <> '' then
    gtk_widget_set_tooltip_text(FMonItems[1], PChar('CPU usage - load average: ' + load));
  if memTotal > 0 then
  begin
    gtk_label_set_markup(FMonRam, PChar('RAM <b>' + HumanSize((memTotal - memAvail) * 1024) + '</b> / ' +
      HumanSize(memTotal * 1024)));
    gtk_level_bar_set_value(FMonRamBar, Min(1.0, Max(0.0, (memTotal - memAvail) / memTotal)));
  end;
  if net <> '' then
    gtk_label_set_markup(FMonNet, PChar(MarkupEscape(net)))
  else
    gtk_label_set_markup(FMonNet, '…');
  if disk <> '' then
  begin
    gtk_label_set_markup(FMonDisk, PChar('/ <b>' + MarkupEscape(disk) + '</b>'));
    gtk_level_bar_set_value(FMonDiskBar, Min(1.0, Max(0.0, StrToIntDef(StringReplace(disk, '%', '', []), 0) / 100)));
  end;
  if users <> '' then
    gtk_label_set_markup(FMonUsers, PChar('<b>' + MarkupEscape(users) + '</b> ' + IfThen(users = '1', 'user', 'users')));
  if up <> '' then
    gtk_label_set_markup(FMonUptime, PChar('<b>' + MarkupEscape(up) + '</b>'));
end;

end.

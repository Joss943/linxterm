{ LinXterm - settings, saved sessions and password storage. }
unit lxconfig;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpjson, jsonparser, lxgtk, lxutil;

type
  TSessionKind = (skSSH, skTelnet, skRDP, skVNC, skFTP, skSFTP, skSerial, skFile, skShell, skBrowser, skMosh);

const
  SessionKindNames: array[TSessionKind] of string =
    ('SSH', 'Telnet', 'RDP', 'VNC', 'FTP', 'SFTP', 'Serial', 'File', 'Shell', 'Browser', 'Mosh');
  SessionKindIds: array[TSessionKind] of string =
    ('ssh', 'telnet', 'rdp', 'vnc', 'ftp', 'sftp', 'serial', 'file', 'shell', 'browser', 'mosh');
  SessionKindIcons: array[TSessionKind] of string =
    ('putty', 'gtkterm', 'krdc', 'tigervnc', 'filezilla', 'gftp', 'cutecom', 'system-file-manager',
     'utilities-terminal', 'web-browser', 'lx-mosh');
  SessionKindDefaultPorts: array[TSessionKind] of Integer =
    (22, 23, 3389, 5900, 21, 22, 0, 0, 0, 0, 22);

type
  { A saved (bookmarked) or ad-hoc session. }
  TSession = class
  public
    Id: string;
    Name: string;
    Folder: string;
    Kind: TSessionKind;
    Host: string;
    User: string;
    Port: Integer;
    HasPassword: Boolean;
    Comment: string;
    { SSH / SFTP / Mosh }
    X11: Boolean;
    Compression: Boolean;
    AgentForward: Boolean;
    SftpBrowser: Boolean;
    FollowPath: Boolean;
    KeyFile: string;
    RemoteCommand: string;
    StayAfterCommand: Boolean;
    JumpHost: string;
    KeepAlive: Integer;
    ExtraOptions: string;
    StartMacro: string;
    { terminal }
    ColorScheme: string;
    TermFont: string;
    LogOutput: Boolean;        { save the terminal output to a log file }
    Highlight: string;         { keyword colouring: '' = configuration, 'on', 'off' }
    TabColor: string;          { '' or #rrggbb: colour mark of the tab }
    { RDP }
    Domain: string;
    Resolution: string;
    RdpClipboard: Boolean;
    RdpHomeDrive: Boolean;
    RdpSound: Boolean;
    RdpExtra: string;
    { VNC }
    ViewOnly: Boolean;
    Scaling: Boolean;
    { FTP }
    FtpPassive: Boolean;
    { Serial }
    Device: string;
    Baud: Integer;
    DataBits: Integer;
    Parity: string;
    StopBits: Integer;
    FlowControl: string;
    { Shell / File }
    ShellPath: string;
    StartDir: string;
    Command: string;
    { Browser }
    Url: string;
    constructor Create(AKind: TSessionKind = skSSH);
    function Clone: TSession;
    procedure Assign(Src: TSession);
    function ToJSON: TJSONObject;
    procedure FromJSON(O: TJSONObject);
    function DisplayName: string;
    function TabTitle: string;
    function IconName: string;
    function Target: string;
    function PasswordKey: string;
    function FullPath: string;
  end;

  TSessionList = class(TList)
  private
    function GetItem(Index: Integer): TSession;
  public
    property Items[Index: Integer]: TSession read GetItem; default;
  end;

  TSessionStore = class
  public
    Sessions: TSessionList;
    Folders: TStringList;
    constructor Create;
    destructor Destroy; override;
    procedure Load;
    procedure Save;
    function FindById(const AId: string): TSession;
    function FindByName(const AName: string): TSession;
    procedure Add(S: TSession);
    procedure Remove(S: TSession);
    procedure AddFolder(const F: string);
    procedure RemoveFolder(const F: string);
    procedure RenameFolder(const OldName, NewName: string);
    function UniqueName(const Base: string): string;
    function ExportTo(const FileName: string): Boolean;
    function ImportFrom(const FileName: string; out Count: Integer): Boolean;
  end;

  TSettings = class
  public
    { general / display }
    Skin: string;              { light | dark }
    ConfirmExit: Boolean;
    RestoreSessions: Boolean;
    StartLocalTerminal: Boolean;
    ShowToolbar, ShowMenubar, ShowSidebar, ShowStatusbar: Boolean;
    SidebarWidth: Integer;
    WindowWidth, WindowHeight: Integer;
    Maximized: Boolean;
    SidebarPage: string;
    DefaultShell: string;
    StartDir: string;
    { terminal }
    FontName: string;
    ColorScheme: string;
    CursorShape: Integer;
    CursorBlink: Boolean;
    Scrollback: Integer;
    CopyOnSelect: Boolean;
    PasteRightClick: Boolean;
    Bell: string;              { none | sound }
    ScrollOnOutput: Boolean;
    ScrollOnKeystroke: Boolean;
    BackspaceSendsCtrlH: Boolean;
    BoldIsBright: Boolean;
    MobaPrompt: Boolean;       { MobaXterm-like prompt in local bash terminals }
    WordChars: string;
    PasteWarnMultiline: Boolean; { confirm before pasting several lines }
    SyntaxHighlight: Boolean;  { colour errors / warnings / OK in the terminal output }
    Notifications: Boolean;    { desktop notifications: bell, end of a long command }
    NotifyAfter: Integer;      { seconds a local command must run to be notified }
    TabActivity: Boolean;      { mark background tabs that print new output }
    LogTerminal: Boolean;      { save the output of every terminal session }
    LogFolder: string;         { '' = <Documents>/LinXterm/logs }
    LogTimestamps: Boolean;    { prefix each logged line with the time }
    { ssh }
    X11Default: Boolean;
    KeepAlive: Integer;
    CompressionDefault: Boolean;
    HostKeyPolicy: string;     { ask | accept-new | no }
    SftpBrowserAuto: Boolean;
    FollowTerminalFolder: Boolean;
    RemoteMonitoring: Boolean;
    DownloadFolder: string;
    AutoReconnect: Boolean;    { restart SSH sessions whose connection was lost }
    { passwords }
    SavePasswords: string;     { always | ask | never }
    UseKeyring: Boolean;
    { misc }
    Recent: TStringList;       { session ids or "ssh://user@host:port" }
    OpenTabs: TStringList;     { serialized sessions open at exit }
    constructor Create;
    destructor Destroy; override;
    procedure Defaults;
    procedure Load;
    procedure Save;
    procedure AddRecent(const Key: string);
    function LogDir: string;
  end;

var
  Settings: TSettings;
  Store: TSessionStore;

function KindFromId(const Id: string; Def: TSessionKind = skSSH): TSessionKind;
function LoadJsonFile(const FileName: string; BackupDamaged: Boolean = True): TJSONData;
function SaveJsonFile(const FileName: string; D: TJSONData): Boolean;
function JStr(O: TJSONObject; const Key, Def: string): string;
function JInt(O: TJSONObject; const Key: string; Def: Integer): Integer;
function JBool(O: TJSONObject; const Key: string; Def: Boolean): Boolean;

{ passwords }
procedure StorePassword(const Key, Password: string);
function LookupPassword(const Key: string; out Password: string): Boolean;
procedure ForgetPassword(const Key: string);
function ListStoredPasswordKeys: TStringArray;
function DefaultShellPath: string;
function AvailableShells: TStringArray;

implementation

uses
  BaseUnix, base64, lxdyn;

function KindFromId(const Id: string; Def: TSessionKind): TSessionKind;
var
  k: TSessionKind;
begin
  for k := Low(TSessionKind) to High(TSessionKind) do
    if SameText(SessionKindIds[k], Id) then Exit(k);
  Result := Def;
end;

function LoadJsonFile(const FileName: string; BackupDamaged: Boolean): TJSONData;
var
  txt, backup: string;
begin
  Result := nil;
  if not FileExists(FileName) then Exit;
  if not ReadFileText(FileName, txt) then Exit;
  if Trim(txt) = '' then Exit;
  try
    Result := GetJSON(txt);
  except
    Result := nil;
  end;
  if (Result = nil) and BackupDamaged then
  begin
    { never overwrite a damaged file silently: keep a copy for the user }
    backup := FileName + '.damaged-' + FormatDateTime('yyyymmdd-hhnnss', Now);
    if RenameFile(FileName, backup) then
      WriteLn(StdErr, APP_NAME, ': ', FileName, ' is not valid JSON, saved as ', backup);
  end;
end;

function SaveJsonFile(const FileName: string; D: TJSONData): Boolean;
begin
  Result := WriteFileText(FileName, D.FormatJSON, True);
end;

function JStr(O: TJSONObject; const Key, Def: string): string;
var
  d: TJSONData;
begin
  Result := Def;
  if O = nil then Exit;
  d := O.Find(Key);
  if (d <> nil) and (d.JSONType in [jtString, jtNumber, jtBoolean]) then
    Result := d.AsString;
end;

function JInt(O: TJSONObject; const Key: string; Def: Integer): Integer;
var
  d: TJSONData;
begin
  Result := Def;
  if O = nil then Exit;
  d := O.Find(Key);
  if d = nil then Exit;
  try
    case d.JSONType of
      jtNumber: Result := d.AsInteger;
      jtString: Result := StrToIntDef(d.AsString, Def);
      jtBoolean: Result := Ord(d.AsBoolean);
    end;
  except
    Result := Def;
  end;
end;

function JBool(O: TJSONObject; const Key: string; Def: Boolean): Boolean;
var
  d: TJSONData;
begin
  Result := Def;
  if O = nil then Exit;
  d := O.Find(Key);
  if d = nil then Exit;
  case d.JSONType of
    jtBoolean: Result := d.AsBoolean;
    jtNumber: Result := d.AsInteger <> 0;
    jtString: Result := SameText(d.AsString, 'true') or (d.AsString = '1');
  end;
end;

function DefaultShellPath: string;
var
  sh: string;
begin
  sh := GetEnvironmentVariable('SHELL');
  if (sh = '') or not FileExists(sh) then
    sh := '/bin/bash';
  if not FileExists(sh) then
    sh := '/bin/sh';
  Result := sh;
end;

function AvailableShells: TStringArray;
var
  txt, line: string;
  lines: TStringArray;
  n: Integer;
begin
  Result := nil;
  n := 0;
  if ReadFileText('/etc/shells', txt) then
  begin
    lines := SplitString(txt, #10);
    for line in lines do
      if (Trim(line) <> '') and (Trim(line)[1] = '/') and FileExists(Trim(line))
        and (Pos('/usr/', Trim(line)) = 1) then
      begin
        SetLength(Result, n + 1);
        Result[n] := Trim(line);
        Inc(n);
      end;
  end;
  if n = 0 then
  begin
    SetLength(Result, 1);
    Result[0] := DefaultShellPath;
  end;
end;

{ ---------------------------------------------------------------- TSession }

constructor TSession.Create(AKind: TSessionKind);
begin
  inherited Create;
  Id := NewId;
  Kind := AKind;
  Port := SessionKindDefaultPorts[AKind];
  X11 := True;
  if Settings <> nil then
  begin
    X11 := Settings.X11Default;
    Compression := Settings.CompressionDefault;
    KeepAlive := Settings.KeepAlive;
  end
  else
    KeepAlive := 60;
  SftpBrowser := True;
  FollowPath := True;
  Resolution := 'dynamic';
  RdpClipboard := True;
  RdpHomeDrive := False;
  RdpSound := True;
  Scaling := True;
  FtpPassive := True;
  Baud := 115200;
  DataBits := 8;
  Parity := 'none';
  StopBits := 1;
  FlowControl := 'none';
  ColorScheme := '';
end;

function TSession.Clone: TSession;
begin
  Result := TSession.Create(Kind);
  Result.Assign(Self);
end;

procedure TSession.Assign(Src: TSession);
var
  o: TJSONObject;
begin
  o := Src.ToJSON;
  try
    FromJSON(o);
  finally
    o.Free;
  end;
end;

function TSession.ToJSON: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.Add('id', Id);
  Result.Add('name', Name);
  Result.Add('folder', Folder);
  Result.Add('type', SessionKindIds[Kind]);
  Result.Add('host', Host);
  Result.Add('user', User);
  Result.Add('port', Port);
  Result.Add('has_password', HasPassword);
  Result.Add('comment', Comment);
  Result.Add('x11', X11);
  Result.Add('compression', Compression);
  Result.Add('agent_forward', AgentForward);
  Result.Add('sftp_browser', SftpBrowser);
  Result.Add('follow_path', FollowPath);
  Result.Add('key_file', KeyFile);
  Result.Add('remote_command', RemoteCommand);
  Result.Add('stay_after_command', StayAfterCommand);
  Result.Add('jump_host', JumpHost);
  Result.Add('keepalive', KeepAlive);
  Result.Add('extra_options', ExtraOptions);
  Result.Add('start_macro', StartMacro);
  Result.Add('color_scheme', ColorScheme);
  Result.Add('term_font', TermFont);
  Result.Add('log_output', LogOutput);
  Result.Add('highlight', Highlight);
  Result.Add('tab_color', TabColor);
  Result.Add('domain', Domain);
  Result.Add('resolution', Resolution);
  Result.Add('rdp_clipboard', RdpClipboard);
  Result.Add('rdp_home_drive', RdpHomeDrive);
  Result.Add('rdp_sound', RdpSound);
  Result.Add('rdp_extra', RdpExtra);
  Result.Add('view_only', ViewOnly);
  Result.Add('scaling', Scaling);
  Result.Add('ftp_passive', FtpPassive);
  Result.Add('device', Device);
  Result.Add('baud', Baud);
  Result.Add('data_bits', DataBits);
  Result.Add('parity', Parity);
  Result.Add('stop_bits', StopBits);
  Result.Add('flow_control', FlowControl);
  Result.Add('shell', ShellPath);
  Result.Add('start_dir', StartDir);
  Result.Add('command', Command);
  Result.Add('url', Url);
end;

procedure TSession.FromJSON(O: TJSONObject);
begin
  Id := JStr(O, 'id', Id);
  if Id = '' then Id := NewId;
  Name := JStr(O, 'name', '');
  Folder := JStr(O, 'folder', '');
  Kind := KindFromId(JStr(O, 'type', 'ssh'));
  Host := JStr(O, 'host', '');
  User := JStr(O, 'user', '');
  Port := JInt(O, 'port', SessionKindDefaultPorts[Kind]);
  HasPassword := JBool(O, 'has_password', False);
  Comment := JStr(O, 'comment', '');
  X11 := JBool(O, 'x11', True);
  Compression := JBool(O, 'compression', False);
  AgentForward := JBool(O, 'agent_forward', False);
  SftpBrowser := JBool(O, 'sftp_browser', True);
  FollowPath := JBool(O, 'follow_path', True);
  KeyFile := JStr(O, 'key_file', '');
  RemoteCommand := JStr(O, 'remote_command', '');
  StayAfterCommand := JBool(O, 'stay_after_command', False);
  JumpHost := JStr(O, 'jump_host', '');
  KeepAlive := JInt(O, 'keepalive', 60);
  ExtraOptions := JStr(O, 'extra_options', '');
  StartMacro := JStr(O, 'start_macro', '');
  ColorScheme := JStr(O, 'color_scheme', '');
  TermFont := JStr(O, 'term_font', '');
  LogOutput := JBool(O, 'log_output', False);
  Highlight := JStr(O, 'highlight', '');
  TabColor := JStr(O, 'tab_color', '');
  Domain := JStr(O, 'domain', '');
  Resolution := JStr(O, 'resolution', 'dynamic');
  RdpClipboard := JBool(O, 'rdp_clipboard', True);
  RdpHomeDrive := JBool(O, 'rdp_home_drive', False);
  RdpSound := JBool(O, 'rdp_sound', True);
  RdpExtra := JStr(O, 'rdp_extra', '');
  ViewOnly := JBool(O, 'view_only', False);
  Scaling := JBool(O, 'scaling', True);
  FtpPassive := JBool(O, 'ftp_passive', True);
  Device := JStr(O, 'device', '');
  Baud := JInt(O, 'baud', 115200);
  DataBits := JInt(O, 'data_bits', 8);
  Parity := JStr(O, 'parity', 'none');
  StopBits := JInt(O, 'stop_bits', 1);
  FlowControl := JStr(O, 'flow_control', 'none');
  ShellPath := JStr(O, 'shell', '');
  StartDir := JStr(O, 'start_dir', '');
  Command := JStr(O, 'command', '');
  Url := JStr(O, 'url', '');
end;

function TSession.Target: string;
begin
  case Kind of
    skShell:
      if ShellPath <> '' then Result := ShellPath else Result := DefaultShellPath;
    skFile:
      Result := StartDir;
    skSerial:
      Result := Device + ' (' + IntToStr(Baud) + ')';
    skBrowser:
      Result := Url;
  else
    begin
      Result := Host;
      if User <> '' then Result := User + '@' + Result;
      if (Port <> 0) and (Port <> SessionKindDefaultPorts[Kind]) then
        Result := Result + ':' + IntToStr(Port);
    end;
  end;
end;

function TSession.DisplayName: string;
begin
  if Name <> '' then Exit(Name);
  case Kind of
    skShell: Result := 'Local terminal';
    skFile:
      if StartDir <> '' then Result := StartDir else Result := HomeDir;
    skSerial: Result := Device;
    skBrowser: Result := Url;
  else
    begin
      Result := Host;
      if User <> '' then Result := Result + ' (' + User + ')';
    end;
  end;
end;

function TSession.TabTitle: string;
begin
  if Name <> '' then Exit(Name);
  case Kind of
    skShell:
      if StartDir <> '' then Result := StartDir else Result := HomeDir;
  else
    Result := DisplayName;
  end;
end;

function TSession.IconName: string;
begin
  Result := SessionKindIcons[Kind];
end;

function TSession.PasswordKey: string;
begin
  Result := 'session:' + Id;
end;

function TSession.FullPath: string;
begin
  if Folder <> '' then Result := Folder + '/' + DisplayName else Result := DisplayName;
end;

function TSessionList.GetItem(Index: Integer): TSession;
begin
  Result := TSession(inherited Items[Index]);
end;

{ ---------------------------------------------------------------- TSessionStore }

constructor TSessionStore.Create;
begin
  inherited Create;
  Sessions := TSessionList.Create;
  Folders := TStringList.Create;
  Folders.Sorted := True;
  Folders.Duplicates := dupIgnore;
  Folders.CaseSensitive := True;
end;

destructor TSessionStore.Destroy;
var
  i: Integer;
begin
  for i := 0 to Sessions.Count - 1 do
    Sessions[i].Free;
  Sessions.Free;
  Folders.Free;
  inherited Destroy;
end;

procedure TSessionStore.Load;
var
  d: TJSONData;
  o: TJSONObject;
  a: TJSONArray;
  i: Integer;
  s: TSession;
begin
  for i := 0 to Sessions.Count - 1 do
    Sessions[i].Free;
  Sessions.Clear;
  Folders.Clear;
  d := LoadJsonFile(ConfigDir + '/sessions.json');
  if d = nil then Exit;
  try
    if d.JSONType <> jtObject then Exit;
    o := TJSONObject(d);
    a := o.Find('folders', jtArray) as TJSONArray;
    if a <> nil then
      for i := 0 to a.Count - 1 do
        if a[i].JSONType = jtString then
          AddFolder(a[i].AsString);
    a := o.Find('sessions', jtArray) as TJSONArray;
    if a <> nil then
      for i := 0 to a.Count - 1 do
        if a[i].JSONType = jtObject then
        begin
          s := TSession.Create;
          s.FromJSON(TJSONObject(a[i]));
          if FindById(s.Id) <> nil then
            s.Id := NewId;
          Sessions.Add(s);
          if s.Folder <> '' then AddFolder(s.Folder);
        end;
  finally
    d.Free;
  end;
end;

procedure TSessionStore.Save;
var
  o: TJSONObject;
  a, f: TJSONArray;
  i: Integer;
begin
  o := TJSONObject.Create;
  try
    f := TJSONArray.Create;
    for i := 0 to Folders.Count - 1 do
      f.Add(Folders[i]);
    o.Add('folders', f);
    a := TJSONArray.Create;
    for i := 0 to Sessions.Count - 1 do
      a.Add(Sessions[i].ToJSON);
    o.Add('sessions', a);
    SaveJsonFile(ConfigDir + '/sessions.json', o);
  finally
    o.Free;
  end;
end;

function TSessionStore.FindById(const AId: string): TSession;
var
  i: Integer;
begin
  for i := 0 to Sessions.Count - 1 do
    if Sessions[i].Id = AId then Exit(Sessions[i]);
  Result := nil;
end;

function TSessionStore.FindByName(const AName: string): TSession;
var
  i: Integer;
begin
  for i := 0 to Sessions.Count - 1 do
    if SameText(Sessions[i].DisplayName, AName) then Exit(Sessions[i]);
  Result := nil;
end;

procedure TSessionStore.Add(S: TSession);
begin
  Sessions.Add(S);
  if S.Folder <> '' then AddFolder(S.Folder);
end;

procedure TSessionStore.Remove(S: TSession);
begin
  Sessions.Remove(S);
  if S.HasPassword then
    ForgetPassword(S.PasswordKey);
  S.Free;
end;

procedure TSessionStore.AddFolder(const F: string);
var
  parts: TStringArray;
  i: Integer;
  acc: string;
begin
  if Trim(F) = '' then Exit;
  parts := SplitString(F, '/');
  acc := '';
  for i := 0 to High(parts) do
  begin
    if parts[i] = '' then Continue;
    if acc = '' then acc := parts[i] else acc := acc + '/' + parts[i];
    Folders.Add(acc);
  end;
end;

procedure TSessionStore.RemoveFolder(const F: string);
var
  i: Integer;
begin
  for i := Sessions.Count - 1 downto 0 do
    if (Sessions[i].Folder = F) or (Pos(F + '/', Sessions[i].Folder) = 1) then
      Remove(Sessions[i]);
  for i := Folders.Count - 1 downto 0 do
    if (Folders[i] = F) or (Pos(F + '/', Folders[i]) = 1) then
      Folders.Delete(i);
end;

procedure TSessionStore.RenameFolder(const OldName, NewName: string);
var
  i: Integer;
  lst: TStringList;
  fixed: string;
begin
  for i := 0 to Sessions.Count - 1 do
    if Sessions[i].Folder = OldName then
      Sessions[i].Folder := NewName
    else if Pos(OldName + '/', Sessions[i].Folder) = 1 then
      Sessions[i].Folder := NewName + Copy(Sessions[i].Folder, Length(OldName) + 1, MaxInt);
  lst := TStringList.Create;
  try
    for i := 0 to Folders.Count - 1 do
    begin
      fixed := Folders[i];
      if fixed = OldName then fixed := NewName
      else if Pos(OldName + '/', fixed) = 1 then
        fixed := NewName + Copy(fixed, Length(OldName) + 1, MaxInt);
      lst.Add(fixed);
    end;
    Folders.Clear;
    for i := 0 to lst.Count - 1 do
      AddFolder(lst[i]);
  finally
    lst.Free;
  end;
end;

function TSessionStore.UniqueName(const Base: string): string;
var
  n: Integer;
begin
  Result := Base;
  n := 1;
  while FindByName(Result) <> nil do
  begin
    Inc(n);
    Result := Base + ' (' + IntToStr(n) + ')';
  end;
end;

function TSessionStore.ExportTo(const FileName: string): Boolean;
var
  o: TJSONObject;
  a: TJSONArray;
  i: Integer;
begin
  o := TJSONObject.Create;
  try
    o.Add('format', 'linxterm-sessions');
    o.Add('version', 1);
    a := TJSONArray.Create;
    for i := 0 to Sessions.Count - 1 do
      a.Add(Sessions[i].ToJSON);
    o.Add('sessions', a);
    a := TJSONArray.Create;
    for i := 0 to Folders.Count - 1 do
      a.Add(Folders[i]);
    o.Add('folders', a);
    Result := WriteFileText(FileName, o.FormatJSON);
  finally
    o.Free;
  end;
end;

function TSessionStore.ImportFrom(const FileName: string; out Count: Integer): Boolean;
var
  d: TJSONData;
  a: TJSONArray;
  i: Integer;
  s: TSession;
begin
  Count := 0;
  Result := False;
  d := LoadJsonFile(FileName, False);
  if (d = nil) or (d.JSONType <> jtObject) then
  begin
    d.Free;
    Exit;
  end;
  try
    a := TJSONObject(d).Find('folders', jtArray) as TJSONArray;
    if a <> nil then
      for i := 0 to a.Count - 1 do
        if a[i].JSONType = jtString then
          AddFolder(a[i].AsString);
    a := TJSONObject(d).Find('sessions', jtArray) as TJSONArray;
    if a = nil then Exit;
    for i := 0 to a.Count - 1 do
      if a[i].JSONType = jtObject then
      begin
        s := TSession.Create;
        s.FromJSON(TJSONObject(a[i]));
        s.Id := NewId;
        s.HasPassword := False;
        Add(s);
        Inc(Count);
      end;
    Result := True;
  finally
    d.Free;
  end;
end;

{ ---------------------------------------------------------------- TSettings }

constructor TSettings.Create;
begin
  inherited Create;
  Recent := TStringList.Create;
  OpenTabs := TStringList.Create;
  Defaults;
end;

destructor TSettings.Destroy;
begin
  Recent.Free;
  OpenTabs.Free;
  inherited Destroy;
end;

procedure TSettings.Defaults;
begin
  Skin := 'light';
  ConfirmExit := True;
  RestoreSessions := False;
  StartLocalTerminal := False;
  ShowToolbar := True;
  ShowMenubar := True;
  ShowSidebar := True;
  ShowStatusbar := True;
  SidebarWidth := 280;
  WindowWidth := 1280;
  WindowHeight := 800;
  Maximized := False;
  SidebarPage := 'sessions';
  DefaultShell := '';
  StartDir := '';
  FontName := 'Monospace 11';
  ColorScheme := 'MobaXterm';
  CursorShape := VTE_CURSOR_SHAPE_BLOCK;
  CursorBlink := True;
  Scrollback := 10000;
  CopyOnSelect := True;
  PasteRightClick := True;
  Bell := 'none';
  ScrollOnOutput := False;
  ScrollOnKeystroke := True;
  BackspaceSendsCtrlH := False;
  BoldIsBright := True;
  MobaPrompt := True;
  WordChars := '-,./?%&#:_=+@~';
  PasteWarnMultiline := True;
  SyntaxHighlight := True;
  Notifications := True;
  NotifyAfter := 10;
  TabActivity := True;
  LogTerminal := False;
  LogFolder := '';
  LogTimestamps := True;
  X11Default := True;
  KeepAlive := 60;
  CompressionDefault := False;
  HostKeyPolicy := 'ask';
  SftpBrowserAuto := True;
  FollowTerminalFolder := True;
  RemoteMonitoring := False;
  DownloadFolder := '';
  AutoReconnect := True;
  SavePasswords := 'ask';
  UseKeyring := True;
end;

procedure TSettings.Load;
var
  d: TJSONData;
  o: TJSONObject;
  a: TJSONArray;
  i: Integer;
begin
  Defaults;
  d := LoadJsonFile(ConfigDir + '/settings.json');
  if (d = nil) then Exit;
  try
    if d.JSONType <> jtObject then Exit;
    o := TJSONObject(d);
    Skin := JStr(o, 'skin', Skin);
    ConfirmExit := JBool(o, 'confirm_exit', ConfirmExit);
    RestoreSessions := JBool(o, 'restore_sessions', RestoreSessions);
    StartLocalTerminal := JBool(o, 'start_local_terminal', StartLocalTerminal);
    ShowToolbar := JBool(o, 'show_toolbar', ShowToolbar);
    ShowMenubar := JBool(o, 'show_menubar', ShowMenubar);
    ShowSidebar := JBool(o, 'show_sidebar', ShowSidebar);
    ShowStatusbar := JBool(o, 'show_statusbar', ShowStatusbar);
    SidebarWidth := JInt(o, 'sidebar_width', SidebarWidth);
    WindowWidth := JInt(o, 'window_width', WindowWidth);
    WindowHeight := JInt(o, 'window_height', WindowHeight);
    Maximized := JBool(o, 'maximized', Maximized);
    SidebarPage := JStr(o, 'sidebar_page', SidebarPage);
    DefaultShell := JStr(o, 'default_shell', DefaultShell);
    StartDir := JStr(o, 'start_dir', StartDir);
    FontName := JStr(o, 'font', FontName);
    ColorScheme := JStr(o, 'color_scheme', ColorScheme);
    CursorShape := JInt(o, 'cursor_shape', CursorShape);
    CursorBlink := JBool(o, 'cursor_blink', CursorBlink);
    Scrollback := JInt(o, 'scrollback', Scrollback);
    CopyOnSelect := JBool(o, 'copy_on_select', CopyOnSelect);
    PasteRightClick := JBool(o, 'paste_right_click', PasteRightClick);
    Bell := JStr(o, 'bell', Bell);
    ScrollOnOutput := JBool(o, 'scroll_on_output', ScrollOnOutput);
    ScrollOnKeystroke := JBool(o, 'scroll_on_keystroke', ScrollOnKeystroke);
    BackspaceSendsCtrlH := JBool(o, 'backspace_ctrl_h', BackspaceSendsCtrlH);
    BoldIsBright := JBool(o, 'bold_is_bright', BoldIsBright);
    MobaPrompt := JBool(o, 'mobaxterm_prompt', MobaPrompt);
    WordChars := JStr(o, 'word_chars', WordChars);
    PasteWarnMultiline := JBool(o, 'paste_warn_multiline', PasteWarnMultiline);
    SyntaxHighlight := JBool(o, 'syntax_highlight', SyntaxHighlight);
    Notifications := JBool(o, 'notifications', Notifications);
    NotifyAfter := JInt(o, 'notify_after', NotifyAfter);
    TabActivity := JBool(o, 'tab_activity', TabActivity);
    LogTerminal := JBool(o, 'log_terminal', LogTerminal);
    LogFolder := JStr(o, 'log_folder', LogFolder);
    LogTimestamps := JBool(o, 'log_timestamps', LogTimestamps);
    X11Default := JBool(o, 'x11_default', X11Default);
    KeepAlive := JInt(o, 'keepalive', KeepAlive);
    CompressionDefault := JBool(o, 'compression_default', CompressionDefault);
    HostKeyPolicy := JStr(o, 'host_key_policy', HostKeyPolicy);
    SftpBrowserAuto := JBool(o, 'sftp_browser_auto', SftpBrowserAuto);
    FollowTerminalFolder := JBool(o, 'follow_terminal_folder', FollowTerminalFolder);
    RemoteMonitoring := JBool(o, 'remote_monitoring', RemoteMonitoring);
    DownloadFolder := JStr(o, 'download_folder', DownloadFolder);
    AutoReconnect := JBool(o, 'auto_reconnect', AutoReconnect);
    SavePasswords := JStr(o, 'save_passwords', SavePasswords);
    UseKeyring := JBool(o, 'use_keyring', UseKeyring);
    Recent.Clear;
    a := o.Find('recent', jtArray) as TJSONArray;
    if a <> nil then
      for i := 0 to a.Count - 1 do
        Recent.Add(a[i].AsString);
    OpenTabs.Clear;
    a := o.Find('open_tabs', jtArray) as TJSONArray;
    if a <> nil then
      for i := 0 to a.Count - 1 do
        if a[i].JSONType = jtObject then
          OpenTabs.Add(a[i].AsJSON);
    if Scrollback < 100 then Scrollback := 100;
    if (CursorShape < 0) or (CursorShape > 2) then CursorShape := 0;
  finally
    d.Free;
  end;
end;

procedure TSettings.Save;
var
  o: TJSONObject;
  a: TJSONArray;
  i: Integer;
  d: TJSONData;
begin
  o := TJSONObject.Create;
  try
    o.Add('skin', Skin);
    o.Add('confirm_exit', ConfirmExit);
    o.Add('restore_sessions', RestoreSessions);
    o.Add('start_local_terminal', StartLocalTerminal);
    o.Add('show_toolbar', ShowToolbar);
    o.Add('show_menubar', ShowMenubar);
    o.Add('show_sidebar', ShowSidebar);
    o.Add('show_statusbar', ShowStatusbar);
    o.Add('sidebar_width', SidebarWidth);
    o.Add('window_width', WindowWidth);
    o.Add('window_height', WindowHeight);
    o.Add('maximized', Maximized);
    o.Add('sidebar_page', SidebarPage);
    o.Add('default_shell', DefaultShell);
    o.Add('start_dir', StartDir);
    o.Add('font', FontName);
    o.Add('color_scheme', ColorScheme);
    o.Add('cursor_shape', CursorShape);
    o.Add('cursor_blink', CursorBlink);
    o.Add('scrollback', Scrollback);
    o.Add('copy_on_select', CopyOnSelect);
    o.Add('paste_right_click', PasteRightClick);
    o.Add('bell', Bell);
    o.Add('scroll_on_output', ScrollOnOutput);
    o.Add('scroll_on_keystroke', ScrollOnKeystroke);
    o.Add('backspace_ctrl_h', BackspaceSendsCtrlH);
    o.Add('bold_is_bright', BoldIsBright);
    o.Add('mobaxterm_prompt', MobaPrompt);
    o.Add('word_chars', WordChars);
    o.Add('paste_warn_multiline', PasteWarnMultiline);
    o.Add('syntax_highlight', SyntaxHighlight);
    o.Add('notifications', Notifications);
    o.Add('notify_after', NotifyAfter);
    o.Add('tab_activity', TabActivity);
    o.Add('log_terminal', LogTerminal);
    o.Add('log_folder', LogFolder);
    o.Add('log_timestamps', LogTimestamps);
    o.Add('x11_default', X11Default);
    o.Add('keepalive', KeepAlive);
    o.Add('compression_default', CompressionDefault);
    o.Add('host_key_policy', HostKeyPolicy);
    o.Add('sftp_browser_auto', SftpBrowserAuto);
    o.Add('follow_terminal_folder', FollowTerminalFolder);
    o.Add('remote_monitoring', RemoteMonitoring);
    o.Add('download_folder', DownloadFolder);
    o.Add('auto_reconnect', AutoReconnect);
    o.Add('save_passwords', SavePasswords);
    o.Add('use_keyring', UseKeyring);
    a := TJSONArray.Create;
    for i := 0 to Recent.Count - 1 do
      a.Add(Recent[i]);
    o.Add('recent', a);
    a := TJSONArray.Create;
    for i := 0 to OpenTabs.Count - 1 do
    begin
      try
        d := GetJSON(OpenTabs[i]);
        a.Add(d);
      except
      end;
    end;
    o.Add('open_tabs', a);
    SaveJsonFile(ConfigDir + '/settings.json', o);
  finally
    o.Free;
  end;
end;

procedure TSettings.AddRecent(const Key: string);
var
  i: Integer;
begin
  i := Recent.IndexOf(Key);
  if i >= 0 then Recent.Delete(i);
  Recent.Insert(0, Key);
  while Recent.Count > 15 do
    Recent.Delete(Recent.Count - 1);
end;

function TSettings.LogDir: string;
var
  docs: string;
begin
  Result := LogFolder;
  if Result = '' then
  begin
    { G_USER_DIRECTORY_DOCUMENTS = 1 }
    docs := CStr(g_get_user_special_dir(1));
    if (docs = '') or not DirectoryExists(docs) then docs := HomeDir;
    Result := docs + '/LinXterm/logs';
  end;
end;

{ ---------------------------------------------------------------- passwords }

var
  Schema: TSecretSchema;
  SchemaInit: Boolean = False;

function GetSchema: PSecretSchema;
begin
  if not SchemaInit then
  begin
    FillChar(Schema, SizeOf(Schema), 0);
    Schema.name := 'dev.linxterm.Password';
    Schema.flags := 0;
    Schema.attributes[0].name := 'key';
    Schema.attributes[0].atype := 0; { SECRET_SCHEMA_ATTRIBUTE_STRING }
    SchemaInit := True;
  end;
  Result := @Schema;
end;

function FilePasswords: TJSONObject;
var
  d: TJSONData;
begin
  d := LoadJsonFile(ConfigDir + '/passwords.json');
  if (d <> nil) and (d.JSONType = jtObject) then
    Result := TJSONObject(d)
  else
  begin
    d.Free;
    Result := TJSONObject.Create;
  end;
end;

const
  ObfKey = 'LinXterm-local-obfuscation-key';

function Obfuscate(const S: string): string;
var
  i: Integer;
  t: string;
begin
  t := S;
  for i := 1 to Length(t) do
    t[i] := Chr(Ord(t[i]) xor Ord(ObfKey[((i - 1) mod Length(ObfKey)) + 1]));
  Result := EncodeStringBase64(t);
end;

function Deobfuscate(const S: string): string;
var
  i: Integer;
begin
  Result := DecodeStringBase64(S);
  for i := 1 to Length(Result) do
    Result[i] := Chr(Ord(Result[i]) xor Ord(ObfKey[((i - 1) mod Length(ObfKey)) + 1]));
end;

procedure IndexAdd(const Key: string; Add: Boolean);
var
  o: TJSONObject;
  a: TJSONArray;
  d: TJSONData;
  i: Integer;
begin
  d := LoadJsonFile(ConfigDir + '/password-index.json');
  if (d = nil) or (d.JSONType <> jtObject) then
  begin
    d.Free;
    o := TJSONObject.Create;
  end
  else
    o := TJSONObject(d);
  try
    a := o.Find('keys', jtArray) as TJSONArray;
    if a = nil then
    begin
      a := TJSONArray.Create;
      o.Add('keys', a);
    end;
    for i := a.Count - 1 downto 0 do
      if (a[i].JSONType <> jtString) or (a[i].AsString = Key) then a.Delete(i);
    if Add then a.Add(Key);
    SaveJsonFile(ConfigDir + '/password-index.json', o);
  finally
    o.Free;
  end;
end;

function KeyringUsable: Boolean;
begin
  Result := ((Settings = nil) or Settings.UseKeyring) and SecretAvailable;
end;

procedure StorePassword(const Key, Password: string);
var
  attrs: Pointer;
  err: PGError;
  ok: Boolean;
  o: TJSONObject;
  lbl: string;
begin
  ok := False;
  if KeyringUsable then
  begin
    attrs := g_hash_table_new(@g_str_hash, @g_str_equal);
    g_hash_table_insert(attrs, PChar('key'), PChar(Key));
    err := nil;
    lbl := 'LinXterm password (' + Key + ')';
    ok := secret_password_storev_sync(GetSchema, attrs, nil, PChar(lbl), PChar(Password), nil, @err);
    if err <> nil then
    begin
      ErrMsg(err);
      ok := False;
    end;
    g_hash_table_unref(attrs);
  end;
  o := FilePasswords;
  try
    if o.Find(Key) <> nil then o.Delete(Key);
    if not ok then
      o.Add(Key, Obfuscate(Password));
    SaveJsonFile(ConfigDir + '/passwords.json', o);
  finally
    o.Free;
  end;
  IndexAdd(Key, True);
end;

function LookupPassword(const Key: string; out Password: string): Boolean;
var
  attrs: Pointer;
  err: PGError;
  p: PChar;
  o: TJSONObject;
begin
  Password := '';
  Result := False;
  if KeyringUsable then
  begin
    attrs := g_hash_table_new(@g_str_hash, @g_str_equal);
    g_hash_table_insert(attrs, PChar('key'), PChar(Key));
    err := nil;
    p := secret_password_lookupv_sync(GetSchema, attrs, nil, @err);
    g_hash_table_unref(attrs);
    if err <> nil then ErrMsg(err);
    if p <> nil then
    begin
      Password := AnsiString(p);
      secret_password_free(p);
      Exit(True);
    end;
  end;
  o := FilePasswords;
  try
    if o.Find(Key) <> nil then
    begin
      Password := Deobfuscate(o.Strings[Key]);
      Result := True;
    end;
  finally
    o.Free;
  end;
end;

procedure ForgetPassword(const Key: string);
var
  attrs: Pointer;
  err: PGError;
  o: TJSONObject;
begin
  if SecretAvailable then
  begin
    attrs := g_hash_table_new(@g_str_hash, @g_str_equal);
    g_hash_table_insert(attrs, PChar('key'), PChar(Key));
    err := nil;
    secret_password_clearv_sync(GetSchema, attrs, nil, @err);
    if err <> nil then ErrMsg(err);
    g_hash_table_unref(attrs);
  end;
  o := FilePasswords;
  try
    if o.Find(Key) <> nil then
    begin
      o.Delete(Key);
      SaveJsonFile(ConfigDir + '/passwords.json', o);
    end;
  finally
    o.Free;
  end;
  IndexAdd(Key, False);
end;

function ListStoredPasswordKeys: TStringArray;
var
  d: TJSONData;
  a: TJSONArray;
  i: Integer;
begin
  Result := nil;
  d := LoadJsonFile(ConfigDir + '/password-index.json');
  if d = nil then Exit;
  try
    if d.JSONType <> jtObject then Exit;
    a := TJSONObject(d).Find('keys', jtArray) as TJSONArray;
    if a = nil then Exit;
    SetLength(Result, a.Count);
    for i := 0 to a.Count - 1 do
      Result[i] := a[i].AsString;
  finally
    d.Free;
  end;
end;

end.

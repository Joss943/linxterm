{ LinXterm - shared helpers: paths, icons, dialogs, async child processes,
  main-thread synchronisation for worker threads. }
unit lxutil;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, BaseUnix, Unix, lxgtk;

const
  APP_NAME = 'LinXterm';
  APP_ID = 'dev.linxterm.LinXterm';
  APP_VERSION = '1.2';

type
  TChildProcess = class;
  TChildLineEvent = procedure(Sender: TChildProcess; const Line: string; IsErr: Boolean) of object;
  TChildExitEvent = procedure(Sender: TChildProcess; Status: Integer) of object;

  PChildCtx = ^TChildCtx;
  TChildCtx = record
    Owner: TChildProcess;
    Pid: GPid;
  end;

  { Asynchronous child process driven by the GLib main loop. Output is
    delivered line by line through OnLine, OnExit fires once both pipes are
    drained and the process has been reaped. }
  TChildProcess = class
  private
    FCtx: PChildCtx;
    FRunning: Boolean;
    FExited: Boolean;
    FStatus: Integer;
    FOutCh, FErrCh: Pointer;
    FOutWatch, FErrWatch: guint;
    FOutBuf, FErrBuf: string;
    FStdin: gint;
    FOpen: Integer;
    FExitFired: Boolean;
    procedure StreamData(Ch: Pointer; IsErr: Boolean; Final: Boolean);
    procedure StreamClosed(IsErr: Boolean);
    procedure ChildExited(Status: Integer);
    procedure MaybeFireExit;
    procedure ReleaseIo;
  public
    OnLine: TChildLineEvent;
    OnExit: TChildExitEvent;
    Tag: PtrInt;
    Output: string;      { full stdout collected when CollectOutput }
    CollectOutput: Boolean;
    constructor Create;
    destructor Destroy; override;
    function Start(const Argv: array of string; const EnvAdd: array of string; const Cwd: string;
      WantStdin: Boolean; out Err: string): Boolean;
    procedure WriteStdin(const Data: string);
    procedure CloseStdin;
    procedure Signal(Sig: cint);
    function Pid: GPid;
    property Running: Boolean read FRunning;
    property ExitStatus: Integer read FStatus;
  end;

{ paths }
function AppDir: string;
function ConfigDir: string;
function RuntimeDir: string;
function HomeDir: string;
function HelperPath(const Name: string): string;
function DownloadDir: string;
function UserName: string;
function FindProgram(const Name: string): string;
function ShellQuote(const S: string): string;
function NewId: string;
function RandomToken(Len: Integer): string;
function WriteSecretFile(const Content: string): string;
procedure SecureDelete(const FileName: string);

{ text helpers }
function HumanSize(Size: Int64): string;
function FormatUnixTime(T: Int64): string;
function ModeString(Mode: LongWord; IsDir, IsLink: Boolean): string;
function SplitString(const S: string; Sep: Char): TStringArray;
function JoinPath(const A, B: string): string;
function RemoteJoin(const A, B: string): string;
function RemoteParent(const P: string): string;
function RemoteBaseName(const P: string): string;
function ExitStatusCode(Status: Integer): Integer;
function ReadFileText(const FileName: string; out Text: string): Boolean;
function WriteFileText(const FileName, Text: string; Private: Boolean = False): Boolean;
function RunCapture(const Argv: array of string; out Output: string): Integer;
function StrToIntSafe(const S: string; Def: Integer): Integer;

{ icons }
function IconPixbuf(const Name: string; Size: Integer): Pointer;
function NewIcon(const Name: string; Size: Integer): Pointer;

{ widgets }
var
  MainWindowWidget: Pointer = nil;

function NewLabel(const Text: string; XAlign: Single = 0): Pointer;
function NewMarkupLabel(const Markup: string; XAlign: Single = 0): Pointer;
function NewIconButton(const IconName, Text, Tooltip: string; IconSize: Integer = 16): Pointer;
function NewFlatIconButton(const IconName, Tooltip: string; IconSize: Integer = 16): Pointer;
function NewImageMenuItem(Menu: Pointer; const Text, IconName: string; Cb: Pointer; Data: Pointer): Pointer;
function NewMenuItem(Menu: Pointer; const Text: string; Cb: Pointer; Data: Pointer): Pointer;
function NewCheckMenuItem(Menu: Pointer; const Text: string; Active: Boolean; Cb: Pointer; Data: Pointer): Pointer;
procedure NewMenuSeparator(Menu: Pointer);
function NewSubMenu(Menu: Pointer; const Text, IconName: string): Pointer;
{ show a context menu built on the fly; it is destroyed once closed }
procedure PopupMenuAtPointer(Menu, AttachTo, Event: Pointer);
procedure PopupMenuBelow(Menu, Widget: Pointer);
procedure AddClass(W: Pointer; const Cls: string);
procedure RemoveClass(W: Pointer; const Cls: string);
function EntryText(E: Pointer): string;
procedure SetEntryText(E: Pointer; const T: string);
function ComboText(C: Pointer): string;
function NewScrolled(Child: Pointer; HPolicy: Integer = GTK_POLICY_AUTOMATIC; VPolicy: Integer = GTK_POLICY_AUTOMATIC): Pointer;
procedure SetMargins(W: Pointer; M: Integer);
function TextBufferText(Buf: Pointer): string;
procedure TextViewAppend(View: Pointer; const Text: string; const Tag: string = '');
procedure DestroyWidget(var W: Pointer);
procedure ProcessPendingEvents;
procedure FreeLater(Obj: TObject);

{ dialogs }
procedure MsgInfo(const Title, Text: string);
procedure MsgError(const Title, Text: string);
procedure MsgWarning(const Title, Text: string);
function AskYesNo(const Title, Text: string): Boolean;
function InputQuery(const Title, Prompt: string; var Value: string; Password: Boolean = False): Boolean;
function ChooseOpenFile(const Title, StartDir: string; out FileName: string): Boolean;
function ChooseOpenFiles(const Title, StartDir: string; out Files: TStringArray): Boolean;
function ChooseSaveFile(const Title, StartDir, DefaultName: string; out FileName: string): Boolean;
function ChooseFolder(const Title, StartDir: string; out Folder: string): Boolean;
procedure OpenUri(const Uri: string);
procedure OpenPath(const Path: string);

{ test / screenshot support }
function SaveWidgetPng(W: Pointer; const FileName: string): Boolean;

implementation

uses
  cairo, DateUtils;

var
  FAppDir: string = '';
  IconCache: TStringList = nil;
  PapirusTheme: Pointer = nil;
  IdCounter: Integer = 0;

type
  TSyncHelper = class
    procedure Wake(Sender: TObject);
  end;

var
  SyncHelper: TSyncHelper;

function IdleSync(data: gpointer): gboolean; cdecl;
begin
  CheckSynchronize(0);
  Result := False;
end;

procedure TSyncHelper.Wake(Sender: TObject);
begin
  g_idle_add(@IdleSync, nil);
end;

{ ---------------------------------------------------------------- paths }

function AppDir: string;
var
  exe: string;
begin
  if FAppDir = '' then
  begin
    exe := fpReadLink('/proc/self/exe');
    if exe = '' then exe := ParamStr(0);
    FAppDir := ExtractFileDir(ExpandFileName(exe));
    { binaries live in <app>/bin }
    if ExtractFileName(FAppDir) = 'bin' then
      FAppDir := ExtractFileDir(FAppDir);
  end;
  Result := FAppDir;
end;

function ConfigDir: string;
begin
  Result := IncludeTrailingPathDelimiter(CStr(g_get_user_config_dir)) + 'linxterm';
  if not DirectoryExists(Result) then
    ForceDirectories(Result);
end;

{ creates Dir if needed and checks that it is a real directory owned by the
  user and private: control sockets and password files are created there }
function PrivateDir(const Dir: string): Boolean;
var
  st: Stat;
begin
  Result := False;
  if fpLStat(Dir, st) <> 0 then
  begin
    if fpMkDir(Dir, &700) <> 0 then Exit;
    if fpLStat(Dir, st) <> 0 then Exit;
  end;
  if not fpS_ISDIR(st.st_mode) or (st.st_uid <> fpGetUid) then Exit;
  if (st.st_mode and &077) <> 0 then
    if fpChmod(Dir, &700) <> 0 then Exit;
  Result := True;
end;

function RuntimeDir: string;
var
  base: string;
begin
  base := CStr(g_get_user_runtime_dir);
  if (base = '') or not DirectoryExists(base) then
    base := CStr(g_get_tmp_dir);
  Result := IncludeTrailingPathDelimiter(base) + 'linxterm-' + IntToStr(fpGetUid);
  if PrivateDir(Result) then Exit;
  { the expected name is taken by somebody else (shared /tmp): fall back to
    a folder inside the home directory }
  Result := IncludeTrailingPathDelimiter(CStr(g_get_user_cache_dir)) + 'linxterm-run';
  ForceDirectories(ExtractFileDir(Result));
  PrivateDir(Result);
end;

function HomeDir: string;
begin
  Result := CStr(g_get_home_dir);
end;

function HelperPath(const Name: string): string;
begin
  Result := AppDir + '/bin/' + Name;
end;

function DownloadDir: string;
begin
  { G_USER_DIRECTORY_DOWNLOAD = 2 }
  Result := CStr(g_get_user_special_dir(2));
  if (Result = '') or not DirectoryExists(Result) then
    Result := HomeDir;
end;

function UserName: string;
begin
  Result := CStr(g_get_user_name);
end;

function FindProgram(const Name: string): string;
begin
  Result := TakeStr(g_find_program_in_path(PChar(Name)));
end;

function ShellQuote(const S: string): string;
begin
  Result := TakeStr(g_shell_quote(PChar(S)));
end;

function NewId: string;
begin
  Inc(IdCounter);
  Result := IntToHex(DateTimeToFileDate(Now), 8) + IntToHex(Random($7FFFFFFF), 8) + IntToHex(IdCounter, 4);
  Result := LowerCase(Result);
end;

function RandomToken(Len: Integer): string;
const
  Chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
var
  i: Integer;
begin
  SetLength(Result, Len);
  for i := 1 to Len do
    Result[i] := Chars[Random(Length(Chars)) + 1];
end;

function WriteAllFd(Fd: cint; const Data: string): Boolean;
var
  p, n: Int64;
begin
  p := 1;
  while p <= Length(Data) do
  begin
    n := fpWrite(Fd, Data[p], Length(Data) - p + 1);
    if n < 0 then
    begin
      if fpGetErrno = ESysEINTR then Continue;
      Exit(False);
    end;
    if n = 0 then Exit(False);
    Inc(p, n);
  end;
  Result := True;
end;

function WriteSecretFile(const Content: string): string;
var
  fd: cint;
  tries: Integer;
begin
  for tries := 1 to 5 do
  begin
    Result := RuntimeDir + '/p-' + RandomToken(16);
    { never reuse or follow an existing file }
    fd := fpOpen(Result, O_WRONLY or O_CREAT or O_EXCL or O_NOFOLLOW, &600);
    if fd < 0 then Continue;
    if WriteAllFd(fd, Content) then
    begin
      fpClose(fd);
      Exit;
    end;
    fpClose(fd);
    fpUnlink(Result);
  end;
  Result := '';
end;

procedure SecureDelete(const FileName: string);
begin
  if (FileName <> '') and FileExists(FileName) then
    DeleteFile(FileName);
end;

{ ---------------------------------------------------------------- text }

function HumanSize(Size: Int64): string;
const
  Units: array[0..4] of string = ('B', 'KB', 'MB', 'GB', 'TB');
var
  v: Double;
  i: Integer;
begin
  if Size < 1024 then Exit(IntToStr(Size) + ' B');
  v := Size;
  i := 0;
  while (v >= 1024) and (i < 4) do
  begin
    v := v / 1024;
    Inc(i);
  end;
  Result := FormatFloat('0.0', v) + ' ' + Units[i];
end;

function FormatUnixTime(T: Int64): string;
begin
  if T <= 0 then Exit('');
  Result := FormatDateTime('yyyy-mm-dd hh:nn', UnixToDateTime(T, False));
end;

function ModeString(Mode: LongWord; IsDir, IsLink: Boolean): string;
const
  RWX = 'rwxrwxrwx';
var
  i: Integer;
begin
  if IsLink then Result := 'l'
  else if IsDir then Result := 'd'
  else Result := '-';
  for i := 0 to 8 do
    if (Mode and (1 shl (8 - i))) <> 0 then
      Result := Result + RWX[i + 1]
    else
      Result := Result + '-';
end;

function SplitString(const S: string; Sep: Char): TStringArray;
var
  i, start, n: Integer;
begin
  Result := nil;
  n := 0;
  start := 1;
  for i := 1 to Length(S) + 1 do
    if (i > Length(S)) or (S[i] = Sep) then
    begin
      SetLength(Result, n + 1);
      Result[n] := Copy(S, start, i - start);
      Inc(n);
      start := i + 1;
    end;
end;

function JoinPath(const A, B: string): string;
begin
  if A = '' then Exit(B);
  if (A <> '') and (A[Length(A)] = '/') then Result := A + B
  else Result := A + '/' + B;
end;

function RemoteJoin(const A, B: string): string;
begin
  Result := JoinPath(A, B);
end;

function RemoteParent(const P: string): string;
var
  i: Integer;
  t: string;
begin
  t := P;
  while (Length(t) > 1) and (t[Length(t)] = '/') do
    Delete(t, Length(t), 1);
  i := Length(t);
  while (i > 0) and (t[i] <> '/') do Dec(i);
  if i <= 1 then
    Result := '/'
  else
    Result := Copy(t, 1, i - 1);
end;

function RemoteBaseName(const P: string): string;
var
  i: Integer;
  t: string;
begin
  t := P;
  while (Length(t) > 1) and (t[Length(t)] = '/') do
    Delete(t, Length(t), 1);
  i := Length(t);
  while (i > 0) and (t[i] <> '/') do Dec(i);
  Result := Copy(t, i + 1, MaxInt);
end;

function ExitStatusCode(Status: Integer): Integer;
begin
  if wifexited(Status) then
    Result := wexitstatus(Status)
  else if wifsignaled(Status) then
    Result := 128 + wtermsig(Status)
  else
    Result := Status;
end;

{ reads the whole file; works with pseudo files (/proc) that report a size of 0 }
function ReadFileText(const FileName: string; out Text: string): Boolean;
var
  fd: cint;
  st: Stat;
  total, n: Int64;
begin
  Text := '';
  Result := False;
  fd := fpOpen(FileName, O_RDONLY);
  if fd < 0 then Exit;
  try
    if (fpFStat(fd, st) = 0) and fpS_ISDIR(st.st_mode) then Exit;
    if st.st_size > 0 then SetLength(Text, st.st_size + 1) else SetLength(Text, 4096);
    total := 0;
    while True do
    begin
      if total = Length(Text) then SetLength(Text, Length(Text) * 2);
      n := fpRead(fd, Text[total + 1], Length(Text) - total);
      if n < 0 then
      begin
        if fpGetErrno = ESysEINTR then Continue;
        Text := '';
        Exit;
      end;
      if n = 0 then Break;
      Inc(total, n);
    end;
    SetLength(Text, total);
    Result := True;
  finally
    fpClose(fd);
  end;
end;

function fchmod(fd: cint; mode: TMode): cint; cdecl; external 'c';
function fchown(fd: cint; uid: TUid; gid: TGid): cint; cdecl; external 'c';

{ follows symbolic links so that saving a linked file keeps the link }
function ResolveLinks(const FileName: string): string;
var
  i: Integer;
  target: string;
  st: Stat;
begin
  Result := FileName;
  for i := 1 to 16 do
  begin
    if (fpLStat(Result, st) <> 0) or not fpS_ISLNK(st.st_mode) then Exit;
    target := fpReadLink(Result);
    if target = '' then Exit;
    if target[1] <> '/' then target := ExtractFilePath(Result) + target;
    Result := target;
  end;
end;

{ Writes a temporary file next to the target, then renames it over the
  target: a crash or a full disk never leaves a truncated file. Existing
  files keep their permissions; Private files are only readable by the user. }
function WriteFileText(const FileName, Text: string; Private: Boolean): Boolean;
var
  target, tmp: string;
  fd: cint;
  st: Stat;
  exists, ok: Boolean;
  err: cint;
begin
  Result := False;
  target := ResolveLinks(FileName);
  exists := fpStat(target, st) = 0;
  tmp := ExtractFilePath(target) + '.' + ExtractFileName(target) + '.lx' + RandomToken(6);
  if Private or exists then
    fd := fpOpen(tmp, O_WRONLY or O_CREAT or O_EXCL or O_NOFOLLOW, &600)
  else
    fd := fpOpen(tmp, O_WRONLY or O_CREAT or O_EXCL or O_NOFOLLOW, &666);
  if fd >= 0 then
  begin
    ok := WriteAllFd(fd, Text) and (fpFSync(fd) = 0);
    if ok and exists and not Private then
    begin
      fchmod(fd, st.st_mode and &7777);
      if (st.st_uid <> fpGetUid) or (st.st_gid <> fpGetGid) then
        fchown(fd, st.st_uid, st.st_gid);
    end;
    err := fpGetErrno;
    fpClose(fd);
    if ok and (fpRename(tmp, target) = 0) then Exit(True);
    fpUnlink(tmp);
    fpSetErrno(err);
    Exit;
  end;
  { the folder is not writable but the file may be: rewrite it in place }
  err := fpGetErrno;
  if not exists or ((err <> ESysEACCES) and (err <> ESysEPERM)) then Exit;
  fd := fpOpen(target, O_WRONLY or O_TRUNC);
  if fd < 0 then Exit;
  Result := WriteAllFd(fd, Text);
  fpClose(fd);
end;

{ runs a short command and returns its exit code with stdout + stderr
  (g_spawn: safe in a multi-threaded program, no file descriptor leaks) }
function RunCapture(const Argv: array of string; out Output: string): Integer;
var
  args: array of AnsiString;
  pargs: array of PChar;
  i: Integer;
  sout, serr: PChar;
  status: gint;
  gerr: PGError;
begin
  Output := '';
  Result := -1;
  if Length(Argv) = 0 then Exit;
  SetLength(args, Length(Argv));
  SetLength(pargs, Length(Argv) + 1);
  for i := 0 to High(Argv) do
  begin
    args[i] := Argv[i];
    pargs[i] := PChar(args[i]);
  end;
  pargs[Length(Argv)] := nil;
  sout := nil;
  serr := nil;
  status := 0;
  gerr := nil;
  if not g_spawn_sync(nil, @pargs[0], nil, G_SPAWN_SEARCH_PATH, nil, nil, @sout, @serr, @status, @gerr) then
  begin
    Output := ErrMsg(gerr);
    Exit;
  end;
  Output := TakeStr(sout) + TakeStr(serr);
  Result := ExitStatusCode(status);
end;

function StrToIntSafe(const S: string; Def: Integer): Integer;
begin
  Result := StrToIntDef(Trim(S), Def);
end;

{ ---------------------------------------------------------------- icons }

function LoadFromTheme(Theme: Pointer; const Name: string; Size: Integer): Pointer;
var
  err: PGError;
begin
  Result := nil;
  if (Theme = nil) or not gtk_icon_theme_has_icon(Theme, PChar(Name)) then Exit;
  err := nil;
  { GTK_ICON_LOOKUP_FORCE_SIZE = 16 }
  Result := gtk_icon_theme_load_icon(Theme, PChar(Name), Size, 16, @err);
  if err <> nil then
  begin
    ErrMsg(err);
    Result := nil;
  end;
end;

function IconPixbuf(const Name: string; Size: Integer): Pointer;
var
  key, fn: string;
  idx: Integer;
  err: PGError;
  pb: Pointer;
begin
  key := Name + '@' + IntToStr(Size);
  if IconCache = nil then
  begin
    IconCache := TStringList.Create;
    IconCache.Sorted := True;
  end;
  idx := IconCache.IndexOf(key);
  if idx >= 0 then Exit(Pointer(IconCache.Objects[idx]));
  Result := nil;
  { 1. bundled icons }
  fn := AppDir + '/icons/' + Name + '.svg';
  if not FileExists(fn) then fn := AppDir + '/icons/' + Name + '.png';
  if FileExists(fn) then
  begin
    err := nil;
    Result := gdk_pixbuf_new_from_file_at_size(PChar(fn), Size, Size, @err);
    if err <> nil then
    begin
      ErrMsg(err);
      Result := nil;
    end;
  end;
  { 2. Papirus (colourful, close to the MobaXterm look) }
  if Result = nil then
  begin
    if PapirusTheme = nil then
    begin
      PapirusTheme := gtk_icon_theme_new;
      gtk_icon_theme_set_custom_theme(PapirusTheme, 'Papirus');
    end;
    { Papirus icons below 22 px are monochrome: load the colourful 24 px
      version and scale it down }
    if Size < 22 then
    begin
      Result := LoadFromTheme(PapirusTheme, Name, 24);
      if Result <> nil then
      begin
        pb := gdk_pixbuf_scale_simple(Result, Size, Size, GDK_INTERP_BILINEAR);
        g_object_unref(Result);
        Result := pb;
      end;
    end;
    if Result = nil then
      Result := LoadFromTheme(PapirusTheme, Name, Size);
  end;
  { 3. current theme }
  if Result = nil then
    Result := LoadFromTheme(gtk_icon_theme_get_default, Name, Size);
  if Result = nil then
    Result := LoadFromTheme(gtk_icon_theme_get_default, 'image-missing', Size);
  IconCache.AddObject(key, TObject(Result));
end;

function NewIcon(const Name: string; Size: Integer): Pointer;
var
  pb: Pointer;
begin
  pb := IconPixbuf(Name, Size);
  if pb <> nil then
    Result := gtk_image_new_from_pixbuf(pb)
  else
    Result := gtk_image_new_from_icon_name(PChar(Name), GTK_ICON_SIZE_MENU);
end;

{ ---------------------------------------------------------------- widgets }

function NewLabel(const Text: string; XAlign: Single): Pointer;
begin
  Result := gtk_label_new(PChar(Text));
  gtk_label_set_xalign(Result, XAlign);
end;

function NewMarkupLabel(const Markup: string; XAlign: Single): Pointer;
begin
  Result := gtk_label_new(nil);
  gtk_label_set_markup(Result, PChar(Markup));
  gtk_label_set_xalign(Result, XAlign);
end;

function NewIconButton(const IconName, Text, Tooltip: string; IconSize: Integer): Pointer;
begin
  if Text <> '' then
    Result := gtk_button_new_with_mnemonic(PChar(Text))
  else
    Result := gtk_button_new;
  if IconName <> '' then
  begin
    gtk_button_set_image(Result, NewIcon(IconName, IconSize));
    gtk_button_set_always_show_image(Result, True);
  end;
  if Tooltip <> '' then
    gtk_widget_set_tooltip_text(Result, PChar(Tooltip));
end;

function NewFlatIconButton(const IconName, Tooltip: string; IconSize: Integer): Pointer;
begin
  Result := NewIconButton(IconName, '', Tooltip, IconSize);
  gtk_button_set_relief(Result, GTK_RELIEF_NONE);
  gtk_widget_set_can_focus(Result, False);
end;

function NewImageMenuItem(Menu: Pointer; const Text, IconName: string; Cb: Pointer; Data: Pointer): Pointer;
begin
  Result := gtk_image_menu_item_new_with_mnemonic(PChar(Text));
  if IconName <> '' then
  begin
    gtk_image_menu_item_set_image(Result, NewIcon(IconName, 16));
    gtk_image_menu_item_set_always_show_image(Result, True);
    { read back by the command palette }
    g_object_set_data_full(Result, 'lx-icon', g_strdup(PChar(IconName)), @g_free);
  end;
  if Cb <> nil then
    Connect(Result, 'activate', Cb, Data);
  if Menu <> nil then
    gtk_menu_shell_append(Menu, Result);
end;

function NewMenuItem(Menu: Pointer; const Text: string; Cb: Pointer; Data: Pointer): Pointer;
begin
  Result := gtk_menu_item_new_with_mnemonic(PChar(Text));
  if Cb <> nil then
    Connect(Result, 'activate', Cb, Data);
  if Menu <> nil then
    gtk_menu_shell_append(Menu, Result);
end;

function NewCheckMenuItem(Menu: Pointer; const Text: string; Active: Boolean; Cb: Pointer; Data: Pointer): Pointer;
begin
  Result := gtk_check_menu_item_new_with_mnemonic(PChar(Text));
  gtk_check_menu_item_set_active(Result, Active);
  if Cb <> nil then
    Connect(Result, 'toggled', Cb, Data);
  if Menu <> nil then
    gtk_menu_shell_append(Menu, Result);
end;

procedure NewMenuSeparator(Menu: Pointer);
begin
  gtk_menu_shell_append(Menu, gtk_separator_menu_item_new);
end;

function NewSubMenu(Menu: Pointer; const Text, IconName: string): Pointer;
var
  item: Pointer;
begin
  item := NewImageMenuItem(Menu, Text, IconName, nil, nil);
  Result := gtk_menu_new;
  gtk_menu_item_set_submenu(item, Result);
end;

function DestroyMenuIdle(data: gpointer): gboolean; cdecl;
begin
  gtk_widget_destroy(data);
  Result := False;
end;

procedure MenuSelectionDone(menu: Pointer; data: gpointer); cdecl;
begin
  { emitted once the activated item has run, or when the menu is cancelled }
  g_signal_handlers_disconnect_matched(menu, G_SIGNAL_MATCH_FUNC, 0, 0, nil, @MenuSelectionDone, nil);
  g_idle_add(@DestroyMenuIdle, menu);
end;

procedure PrepareMenu(Menu, AttachTo: Pointer);
begin
  gtk_widget_show_all(Menu);
  if AttachTo <> nil then gtk_menu_attach_to_widget(Menu, AttachTo, nil);
  Connect(Menu, 'selection-done', @MenuSelectionDone, nil);
end;

procedure PopupMenuAtPointer(Menu, AttachTo, Event: Pointer);
begin
  PrepareMenu(Menu, AttachTo);
  gtk_menu_popup_at_pointer(Menu, Event);
end;

procedure PopupMenuBelow(Menu, Widget: Pointer);
begin
  PrepareMenu(Menu, Widget);
  gtk_menu_popup_at_widget(Menu, Widget, GDK_GRAVITY_SOUTH_WEST, GDK_GRAVITY_NORTH_WEST, nil);
end;

procedure AddClass(W: Pointer; const Cls: string);
begin
  gtk_style_context_add_class(gtk_widget_get_style_context(W), PChar(Cls));
end;

procedure RemoveClass(W: Pointer; const Cls: string);
begin
  gtk_style_context_remove_class(gtk_widget_get_style_context(W), PChar(Cls));
end;

function EntryText(E: Pointer): string;
begin
  Result := CStr(gtk_entry_get_text(E));
end;

procedure SetEntryText(E: Pointer; const T: string);
begin
  gtk_entry_set_text(E, PChar(T));
end;

function ComboText(C: Pointer): string;
begin
  Result := TakeStr(gtk_combo_box_text_get_active_text(C));
end;

function NewScrolled(Child: Pointer; HPolicy: Integer; VPolicy: Integer): Pointer;
begin
  Result := gtk_scrolled_window_new(nil, nil);
  gtk_scrolled_window_set_policy(Result, HPolicy, VPolicy);
  gtk_scrolled_window_set_shadow_type(Result, GTK_SHADOW_IN);
  if Child <> nil then
    gtk_container_add(Result, Child);
end;

procedure SetMargins(W: Pointer; M: Integer);
begin
  gtk_widget_set_margin_start(W, M);
  gtk_widget_set_margin_end(W, M);
  gtk_widget_set_margin_top(W, M);
  gtk_widget_set_margin_bottom(W, M);
end;

function TextBufferText(Buf: Pointer): string;
var
  a, b: TGtkTextIter;
begin
  gtk_text_buffer_get_bounds(Buf, @a, @b);
  Result := TakeStr(gtk_text_buffer_get_text(Buf, @a, @b, True));
end;

procedure TextViewAppend(View: Pointer; const Text: string; const Tag: string);
var
  buf, mark: Pointer;
  it: TGtkTextIter;
begin
  buf := gtk_text_view_get_buffer(View);
  gtk_text_buffer_get_end_iter(buf, @it);
  if Tag <> '' then
    gtk_text_buffer_insert_with_tags_by_name(buf, @it, PChar(Text), -1, PChar(Tag), nil)
  else
    gtk_text_buffer_insert(buf, @it, PChar(Text), -1);
  gtk_text_buffer_get_end_iter(buf, @it);
  mark := gtk_text_buffer_get_insert(buf);
  gtk_text_buffer_place_cursor(buf, @it);
  gtk_text_view_scroll_to_mark(View, mark, 0, False, 0, 1);
end;

procedure DestroyWidget(var W: Pointer);
begin
  if W <> nil then
  begin
    gtk_widget_destroy(W);
    W := nil;
  end;
end;

function IdleFreeCb(data: gpointer): gboolean; cdecl;
begin
  TObject(data).Free;
  Result := False;
end;

procedure FreeLater(Obj: TObject);
begin
  if Obj <> nil then g_idle_add(@IdleFreeCb, Obj);
end;

procedure ProcessPendingEvents;
var
  n: Integer;
begin
  n := 0;
  while gtk_events_pending and (n < 200) do
  begin
    gtk_main_iteration;
    Inc(n);
  end;
end;

{ ---------------------------------------------------------------- dialogs }

procedure ShowMessage(MType: Integer; const Title, Text: string);
var
  d: Pointer;
begin
  d := gtk_message_dialog_new(MainWindowWidget, GTK_DIALOG_MODAL or GTK_DIALOG_DESTROY_WITH_PARENT,
    MType, GTK_BUTTONS_OK, '%s', PChar(Title));
  if Text <> '' then
    gtk_message_dialog_format_secondary_text(d, '%s', PChar(Text));
  gtk_window_set_title(d, PChar(APP_NAME));
  gtk_dialog_run(d);
  gtk_widget_destroy(d);
end;

procedure MsgInfo(const Title, Text: string);
begin
  ShowMessage(GTK_MESSAGE_INFO, Title, Text);
end;

procedure MsgError(const Title, Text: string);
begin
  ShowMessage(GTK_MESSAGE_ERROR, Title, Text);
end;

procedure MsgWarning(const Title, Text: string);
begin
  ShowMessage(GTK_MESSAGE_WARNING, Title, Text);
end;

function AskYesNo(const Title, Text: string): Boolean;
var
  d: Pointer;
begin
  d := gtk_message_dialog_new(MainWindowWidget, GTK_DIALOG_MODAL or GTK_DIALOG_DESTROY_WITH_PARENT,
    GTK_MESSAGE_QUESTION, GTK_BUTTONS_YES_NO, '%s', PChar(Title));
  if Text <> '' then
    gtk_message_dialog_format_secondary_text(d, '%s', PChar(Text));
  gtk_window_set_title(d, PChar(APP_NAME));
  Result := gtk_dialog_run(d) = GTK_RESPONSE_YES;
  gtk_widget_destroy(d);
end;

function InputQuery(const Title, Prompt: string; var Value: string; Password: Boolean): Boolean;
var
  d, area, box, entry: Pointer;
begin
  d := gtk_dialog_new_with_buttons(PChar(Title), MainWindowWidget, GTK_DIALOG_MODAL or GTK_DIALOG_DESTROY_WITH_PARENT,
    '_Cancel', GTK_RESPONSE_CANCEL, '_OK', GTK_RESPONSE_OK, nil);
  gtk_dialog_set_default_response(d, GTK_RESPONSE_OK);
  area := gtk_dialog_get_content_area(d);
  box := gtk_box_new(GTK_ORIENTATION_VERTICAL, 6);
  SetMargins(box, 12);
  gtk_box_pack_start(box, NewLabel(Prompt), False, False, 0);
  entry := gtk_entry_new;
  gtk_entry_set_text(entry, PChar(Value));
  gtk_entry_set_activates_default(entry, True);
  gtk_entry_set_width_chars(entry, 40);
  if Password then
  begin
    gtk_entry_set_visibility(entry, False);
    gtk_entry_set_input_purpose(entry, GTK_INPUT_PURPOSE_PASSWORD);
  end;
  gtk_box_pack_start(box, entry, False, False, 0);
  gtk_container_add(area, box);
  gtk_widget_show_all(d);
  Result := gtk_dialog_run(d) = GTK_RESPONSE_OK;
  if Result then
    Value := EntryText(entry);
  gtk_widget_destroy(d);
end;

function RunNativeChooser(const Title: string; Action: Integer; const StartDir, DefaultName: string;
  Multiple: Boolean; out Files: TStringArray): Boolean;
var
  d: Pointer;
  accept: string;
  list, it: PGSList;
  n: Integer;
begin
  Files := nil;
  case Action of
    GTK_FILE_CHOOSER_ACTION_SAVE: accept := '_Save';
    GTK_FILE_CHOOSER_ACTION_SELECT_FOLDER: accept := '_Select';
  else
    accept := '_Open';
  end;
  d := gtk_file_chooser_native_new(PChar(Title), MainWindowWidget, Action, PChar(accept), '_Cancel');
  gtk_native_dialog_set_modal(d, True);
  if StartDir <> '' then
    gtk_file_chooser_set_current_folder(d, PChar(StartDir));
  if (Action = GTK_FILE_CHOOSER_ACTION_SAVE) then
  begin
    gtk_file_chooser_set_do_overwrite_confirmation(d, True);
    if DefaultName <> '' then
      gtk_file_chooser_set_current_name(d, PChar(DefaultName));
  end;
  if Multiple then
    gtk_file_chooser_set_select_multiple(d, True);
  Result := gtk_native_dialog_run(d) = GTK_RESPONSE_ACCEPT;
  if Result then
  begin
    if Multiple then
    begin
      list := gtk_file_chooser_get_filenames(d);
      it := list;
      n := 0;
      while it <> nil do
      begin
        SetLength(Files, n + 1);
        Files[n] := CStr(PChar(it^.data));
        g_free(it^.data);
        Inc(n);
        it := it^.next;
      end;
      g_slist_free(list);
    end
    else
    begin
      SetLength(Files, 1);
      Files[0] := TakeStr(gtk_file_chooser_get_filename(d));
    end;
    Result := (Length(Files) > 0) and (Files[0] <> '');
  end;
  g_object_unref(d);
end;

function ChooseOpenFile(const Title, StartDir: string; out FileName: string): Boolean;
var
  f: TStringArray;
begin
  Result := RunNativeChooser(Title, GTK_FILE_CHOOSER_ACTION_OPEN, StartDir, '', False, f);
  if Result then FileName := f[0] else FileName := '';
end;

function ChooseOpenFiles(const Title, StartDir: string; out Files: TStringArray): Boolean;
begin
  Result := RunNativeChooser(Title, GTK_FILE_CHOOSER_ACTION_OPEN, StartDir, '', True, Files);
end;

function ChooseSaveFile(const Title, StartDir, DefaultName: string; out FileName: string): Boolean;
var
  f: TStringArray;
begin
  Result := RunNativeChooser(Title, GTK_FILE_CHOOSER_ACTION_SAVE, StartDir, DefaultName, False, f);
  if Result then FileName := f[0] else FileName := '';
end;

function ChooseFolder(const Title, StartDir: string; out Folder: string): Boolean;
var
  f: TStringArray;
begin
  Result := RunNativeChooser(Title, GTK_FILE_CHOOSER_ACTION_SELECT_FOLDER, StartDir, '', False, f);
  if Result then Folder := f[0] else Folder := '';
end;

procedure OpenUri(const Uri: string);
var
  err: PGError;
begin
  err := nil;
  if not gtk_show_uri_on_window(MainWindowWidget, PChar(Uri), gtk_get_current_event_time, @err) then
    MsgError('Unable to open "' + Uri + '"', ErrMsg(err));
end;

procedure OpenPath(const Path: string);
var
  uri: string;
  err: PGError;
begin
  err := nil;
  uri := TakeStr(g_filename_to_uri(PChar(Path), nil, @err));
  if uri = '' then
    MsgError('Unable to open "' + Path + '"', ErrMsg(err))
  else
    OpenUri(uri);
end;

{ ---------------------------------------------------------------- screenshot }

function SaveWidgetPng(W: Pointer; const FileName: string): Boolean;
var
  surf: Pcairo_surface_t;
  cr: Pcairo_t;
  wd, ht: Integer;
begin
  Result := False;
  if W = nil then Exit;
  wd := gtk_widget_get_allocated_width(W);
  ht := gtk_widget_get_allocated_height(W);
  if (wd <= 1) or (ht <= 1) then Exit;
  surf := cairo_image_surface_create(CAIRO_FORMAT_ARGB32, wd, ht);
  cr := cairo_create(surf);
  gtk_widget_draw(W, cr);
  cairo_destroy(cr);
  Result := cairo_surface_write_to_png(surf, PChar(FileName)) = CAIRO_STATUS_SUCCESS;
  cairo_surface_destroy(surf);
end;

{ ---------------------------------------------------------------- child process }

function ChildOutCb(source: Pointer; condition: guint; data: gpointer): gboolean; cdecl; forward;
function ChildErrCb(source: Pointer; condition: guint; data: gpointer): gboolean; cdecl; forward;

procedure ChildWatchCb(pid: GPid; status: gint; data: gpointer); cdecl;
var
  ctx: PChildCtx;
begin
  ctx := PChildCtx(data);
  g_spawn_close_pid(pid);
  if ctx^.Owner <> nil then
    ctx^.Owner.ChildExited(status);
  Dispose(ctx);
end;

function ChildOutCb(source: Pointer; condition: guint; data: gpointer): gboolean; cdecl;
var
  cp: TChildProcess;
begin
  cp := TChildProcess(data);
  Result := True;
  if (condition and (G_IO_IN or G_IO_PRI)) <> 0 then
    cp.StreamData(source, False, False);
  if (condition and (G_IO_HUP or G_IO_ERR or G_IO_NVAL)) <> 0 then
  begin
    cp.StreamData(source, False, True);
    cp.FOutWatch := 0;
    cp.StreamClosed(False);
    Result := False;
  end;
end;

function ChildErrCb(source: Pointer; condition: guint; data: gpointer): gboolean; cdecl;
var
  cp: TChildProcess;
begin
  cp := TChildProcess(data);
  Result := True;
  if (condition and (G_IO_IN or G_IO_PRI)) <> 0 then
    cp.StreamData(source, True, False);
  if (condition and (G_IO_HUP or G_IO_ERR or G_IO_NVAL)) <> 0 then
  begin
    cp.StreamData(source, True, True);
    cp.FErrWatch := 0;
    cp.StreamClosed(True);
    Result := False;
  end;
end;

constructor TChildProcess.Create;
begin
  inherited Create;
  FStdin := -1;
end;

{ closes the pipes of the previous run (each run opens new ones) }
procedure TChildProcess.ReleaseIo;
begin
  if FOutWatch <> 0 then g_source_remove(FOutWatch);
  if FErrWatch <> 0 then g_source_remove(FErrWatch);
  FOutWatch := 0;
  FErrWatch := 0;
  if FOutCh <> nil then g_io_channel_unref(FOutCh);
  if FErrCh <> nil then g_io_channel_unref(FErrCh);
  FOutCh := nil;
  FErrCh := nil;
  CloseStdin;
end;

destructor TChildProcess.Destroy;
begin
  OnLine := nil;
  OnExit := nil;
  ReleaseIo;
  if FCtx <> nil then
  begin
    { the child watch stays installed so the process gets reaped }
    if FRunning then
      fpKill(FCtx^.Pid, SIGTERM);
    FCtx^.Owner := nil;
    FCtx := nil;
  end;
  inherited Destroy;
end;

function TChildProcess.Start(const Argv: array of string; const EnvAdd: array of string; const Cwd: string;
  WantStdin: Boolean; out Err: string): Boolean;
var
  args: array of AnsiString;
  pargs: array of PChar;
  envp: PPChar;
  i, p: Integer;
  cpid: GPid;
  fin, fout, ferr: gint;
  gerr: PGError;
  wd: PChar;
  nm, vl: string;
begin
  Result := False;
  Err := '';
  if FRunning then
  begin
    Err := 'already running';
    Exit;
  end;
  ReleaseIo;
  SetLength(args, Length(Argv));
  SetLength(pargs, Length(Argv) + 1);
  for i := 0 to High(Argv) do
  begin
    args[i] := Argv[i];
    pargs[i] := PChar(args[i]);
  end;
  pargs[Length(Argv)] := nil;
  envp := g_get_environ;
  for i := 0 to High(EnvAdd) do
  begin
    p := Pos('=', EnvAdd[i]);
    if p > 0 then
    begin
      nm := Copy(EnvAdd[i], 1, p - 1);
      vl := Copy(EnvAdd[i], p + 1, MaxInt);
      if vl = #0 then
        envp := g_environ_unsetenv(envp, PChar(nm))
      else
        envp := g_environ_setenv(envp, PChar(nm), PChar(vl), True);
    end;
  end;
  if Cwd <> '' then wd := PChar(Cwd) else wd := nil;
  gerr := nil;
  fin := -1;
  fout := -1;
  ferr := -1;
  Output := '';
  FOutBuf := '';
  FErrBuf := '';
  FExited := False;
  FExitFired := False;
  if WantStdin then
    Result := g_spawn_async_with_pipes(wd, @pargs[0], envp, G_SPAWN_SEARCH_PATH or G_SPAWN_DO_NOT_REAP_CHILD or G_SPAWN_CLOEXEC_PIPES,
      nil, nil, @cpid, @fin, @fout, @ferr, @gerr)
  else
    Result := g_spawn_async_with_pipes(wd, @pargs[0], envp, G_SPAWN_SEARCH_PATH or G_SPAWN_DO_NOT_REAP_CHILD or G_SPAWN_CLOEXEC_PIPES,
      nil, nil, @cpid, nil, @fout, @ferr, @gerr);
  g_strfreev(envp);
  if not Result then
  begin
    Err := ErrMsg(gerr);
    Exit;
  end;
  FRunning := True;
  FStdin := fin;
  New(FCtx);
  FCtx^.Owner := Self;
  FCtx^.Pid := cpid;
  g_child_watch_add(cpid, @ChildWatchCb, FCtx);
  FOpen := 2;
  FOutCh := g_io_channel_unix_new(fout);
  g_io_channel_set_close_on_unref(FOutCh, True);
  g_io_channel_set_encoding(FOutCh, nil, nil);
  g_io_channel_set_flags(FOutCh, G_IO_FLAG_NONBLOCK, nil);
  FOutWatch := g_io_add_watch(FOutCh, G_IO_IN or G_IO_PRI or G_IO_HUP or G_IO_ERR or G_IO_NVAL, @ChildOutCb, Self);
  FErrCh := g_io_channel_unix_new(ferr);
  g_io_channel_set_close_on_unref(FErrCh, True);
  g_io_channel_set_encoding(FErrCh, nil, nil);
  g_io_channel_set_flags(FErrCh, G_IO_FLAG_NONBLOCK, nil);
  FErrWatch := g_io_add_watch(FErrCh, G_IO_IN or G_IO_PRI or G_IO_HUP or G_IO_ERR or G_IO_NVAL, @ChildErrCb, Self);
end;

procedure TChildProcess.StreamData(Ch: Pointer; IsErr: Boolean; Final: Boolean);
var
  buf: array[0..8191] of Char;
  n: PtrUInt;
  st, p: Integer;
  chunk, line: string;
begin
  repeat
    n := 0;
    st := g_io_channel_read_chars(Ch, @buf[0], SizeOf(buf), @n, nil);
    if n > 0 then
    begin
      SetString(chunk, PChar(@buf[0]), n);
      if (not IsErr) and CollectOutput then
        Output := Output + chunk;
      if IsErr then FErrBuf := FErrBuf + chunk else FOutBuf := FOutBuf + chunk;
    end;
  until (st <> G_IO_STATUS_NORMAL) or (n = 0);
  { dispatch complete lines }
  while True do
  begin
    if IsErr then p := Pos(#10, FErrBuf) else p := Pos(#10, FOutBuf);
    if p = 0 then Break;
    if IsErr then
    begin
      line := Copy(FErrBuf, 1, p - 1);
      Delete(FErrBuf, 1, p);
    end
    else
    begin
      line := Copy(FOutBuf, 1, p - 1);
      Delete(FOutBuf, 1, p);
    end;
    if (line <> '') and (line[Length(line)] = #13) then
      Delete(line, Length(line), 1);
    if Assigned(OnLine) then OnLine(Self, line, IsErr);
  end;
  if Final then
  begin
    if IsErr then line := FErrBuf else line := FOutBuf;
    if IsErr then FErrBuf := '' else FOutBuf := '';
    if (line <> '') and Assigned(OnLine) then OnLine(Self, line, IsErr);
  end;
end;

procedure TChildProcess.StreamClosed(IsErr: Boolean);
begin
  Dec(FOpen);
  MaybeFireExit;
end;

procedure TChildProcess.ChildExited(Status: Integer);
begin
  FStatus := ExitStatusCode(Status);
  FExited := True;
  FRunning := False;
  FCtx := nil;
  MaybeFireExit;
end;

procedure TChildProcess.MaybeFireExit;
begin
  if FExited and (FOpen <= 0) and not FExitFired then
  begin
    FExitFired := True;
    CloseStdin;
    if Assigned(OnExit) then OnExit(Self, FStatus);
  end;
end;

procedure TChildProcess.WriteStdin(const Data: string);
begin
  if (FStdin >= 0) and (Length(Data) > 0) then
    fpWrite(FStdin, Data[1], Length(Data));
end;

procedure TChildProcess.CloseStdin;
begin
  if FStdin >= 0 then
  begin
    fpClose(FStdin);
    FStdin := -1;
  end;
end;

procedure TChildProcess.Signal(Sig: cint);
begin
  if FRunning and (FCtx <> nil) then
    fpKill(FCtx^.Pid, Sig);
end;

function TChildProcess.Pid: GPid;
begin
  if FCtx <> nil then Result := FCtx^.Pid else Result := 0;
end;

initialization
  Randomize;
  SyncHelper := TSyncHelper.Create;
  WakeMainThread := @SyncHelper.Wake;
  { ignore SIGPIPE: writing to a closed ssh pipe must not kill the app }
  fpSignal(SIGPIPE, SignalHandler(SIG_IGN));

end.

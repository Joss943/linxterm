{ LinXterm - file system backends (local, SFTP, FTP) and the worker thread
  that runs file operations outside of the GTK main loop. }
unit lxfs;

{$mode objfpc}{$H+}
{$interfaces COM}

interface

uses
  Classes, SysUtils, SyncObjs, BaseUnix, Unix, lxsftp, lxftp;

type
  TFileEntry = record
    Name: string;
    IsDir, IsLink: Boolean;
    Size: Int64;
    MTime: Int64;
    Mode: LongWord;
    Owner, Group: string;
  end;
  TFileEntries = array of TFileEntry;

  TFsProgress = function(Done, Total: Int64): Boolean of object;

  TFsBackend = class
  public
    procedure Connect; virtual;
    procedure Disconnect; virtual;
    function IsConnected: Boolean; virtual;
    function IsLocal: Boolean; virtual;
    function HomeDir: string; virtual; abstract;
    function RealPath(const P: string): string; virtual; abstract;
    function List(const Dir: string): TFileEntries; virtual; abstract;
    function GetEntry(const P: string; out E: TFileEntry): Boolean; virtual; abstract;
    procedure MkDir(const P: string); virtual; abstract;
    procedure RemoveFile(const P: string); virtual; abstract;
    procedure RemoveDir(const P: string); virtual; abstract;
    procedure Rename(const A, B: string); virtual; abstract;
    procedure Chmod(const P: string; Mode: LongWord); virtual; abstract;
    procedure Download(const Remote, Local: string; Progress: TFsProgress); virtual; abstract;
    procedure Upload(const Local, Remote: string; Progress: TFsProgress); virtual; abstract;
    function Clone: TFsBackend; virtual; abstract;
    function Name: string; virtual; abstract;
  end;

  TLocalFs = class(TFsBackend)
  public
    function IsLocal: Boolean; override;
    function HomeDir: string; override;
    function RealPath(const P: string): string; override;
    function List(const Dir: string): TFileEntries; override;
    function GetEntry(const P: string; out E: TFileEntry): Boolean; override;
    procedure MkDir(const P: string); override;
    procedure RemoveFile(const P: string); override;
    procedure RemoveDir(const P: string); override;
    procedure Rename(const A, B: string); override;
    procedure Chmod(const P: string; Mode: LongWord); override;
    procedure Download(const Remote, Local: string; Progress: TFsProgress); override;
    procedure Upload(const Local, Remote: string; Progress: TFsProgress); override;
    function Clone: TFsBackend; override;
    function Name: string; override;
  end;

  TSftpFs = class(TFsBackend)
  private
    FClient: TSftpClient;
    FArgv: array of string;
    FDesc: string;
    FHome: string;
  public
    constructor Create(const Argv: array of string; const Desc: string);
    destructor Destroy; override;
    procedure Connect; override;
    procedure Disconnect; override;
    function IsConnected: Boolean; override;
    function HomeDir: string; override;
    function RealPath(const P: string): string; override;
    function List(const Dir: string): TFileEntries; override;
    function GetEntry(const P: string; out E: TFileEntry): Boolean; override;
    procedure MkDir(const P: string); override;
    procedure RemoveFile(const P: string); override;
    procedure RemoveDir(const P: string); override;
    procedure Rename(const A, B: string); override;
    procedure Chmod(const P: string; Mode: LongWord); override;
    procedure Download(const Remote, Local: string; Progress: TFsProgress); override;
    procedure Upload(const Local, Remote: string; Progress: TFsProgress); override;
    function Clone: TFsBackend; override;
    function Name: string; override;
  end;

  TFtpFs = class(TFsBackend)
  private
    FClient: TFtpClient;
    FHost, FUser, FPass: string;
    FPort: Integer;
    FPassive: Boolean;
    FHome: string;
  public
    constructor Create(const Host: string; Port: Integer; const User, Pass: string; Passive: Boolean);
    destructor Destroy; override;
    procedure Connect; override;
    procedure Disconnect; override;
    function IsConnected: Boolean; override;
    function HomeDir: string; override;
    function RealPath(const P: string): string; override;
    function List(const Dir: string): TFileEntries; override;
    function GetEntry(const P: string; out E: TFileEntry): Boolean; override;
    procedure MkDir(const P: string); override;
    procedure RemoveFile(const P: string); override;
    procedure RemoveDir(const P: string); override;
    procedure Rename(const A, B: string); override;
    procedure Chmod(const P: string; Mode: LongWord); override;
    procedure Download(const Remote, Local: string; Progress: TFsProgress); override;
    procedure Upload(const Local, Remote: string; Progress: TFsProgress); override;
    function Clone: TFsBackend; override;
    function Name: string; override;
  end;

  IFsToken = interface
    ['{6F2E4B6A-1C3D-4E5F-8A9B-0C1D2E3F4A5B}']
    function Alive: Boolean;
    procedure Kill;
  end;

  TFsToken = class(TInterfacedObject, IFsToken)
  private
    FAlive: Boolean;
  public
    constructor Create;
    function Alive: Boolean;
    procedure Kill;
  end;

  TFsWorker = class;

  TFsJob = class
  public
    Token: IFsToken;
    Err: string;
    Cancelled: Boolean;
    procedure Execute(B: TFsBackend); virtual; abstract;
    procedure Done; virtual; abstract;
    procedure Finish;
  end;

  TFsWorker = class(TThread)
  private
    FBackend: TFsBackend;
    FQueue: TThreadList;
    FEvent: TEvent;
    FIdleCloseMs: Integer;
    FCurrent: TFsJob;
    FLock: TCriticalSection;
  protected
    procedure Execute; override;
  public
    constructor Create(Backend: TFsBackend; IdleCloseMs: Integer);
    destructor Destroy; override;
    procedure Add(Job: TFsJob);
    procedure CancelAll;
    procedure Shutdown;
    function Pending: Integer;
  end;

function LocalJoin(const A, B: string): string;
function UidName(Uid: LongWord): string;
function GidName(Gid: LongWord): string;

implementation

var
  UserMap, GroupMap: TStringList;
  MapLock: TCriticalSection;

procedure LoadIdMap(const FileName: string; Map: TStringList);
var
  sl: TStringList;
  i, p1, p2, p3: Integer;
  line: string;
begin
  sl := TStringList.Create;
  try
    try
      sl.LoadFromFile(FileName);
    except
      Exit;
    end;
    for i := 0 to sl.Count - 1 do
    begin
      line := sl[i];
      p1 := Pos(':', line);
      if p1 = 0 then Continue;
      p2 := Pos(':', Copy(line, p1 + 1, MaxInt)) + p1;
      p3 := Pos(':', Copy(line, p2 + 1, MaxInt)) + p2;
      if (p2 > p1) and (p3 > p2) then
        Map.Values[Copy(line, p2 + 1, p3 - p2 - 1)] := Copy(line, 1, p1 - 1);
    end;
  finally
    sl.Free;
  end;
end;

function IdName(Map: TStringList; const FileName: string; Id: LongWord): string;
begin
  MapLock.Enter;
  try
    if Map.Count = 0 then LoadIdMap(FileName, Map);
    Result := Map.Values[IntToStr(Id)];
    if Result = '' then Result := IntToStr(Id);
  finally
    MapLock.Leave;
  end;
end;

function UidName(Uid: LongWord): string;
begin
  Result := IdName(UserMap, '/etc/passwd', Uid);
end;

function GidName(Gid: LongWord): string;
begin
  Result := IdName(GroupMap, '/etc/group', Gid);
end;

function LocalJoin(const A, B: string): string;
begin
  if (A <> '') and (A[Length(A)] = '/') then Result := A + B else Result := A + '/' + B;
end;

{ ---------------------------------------------------------------- TFsBackend }

procedure TFsBackend.Connect;
begin
end;

procedure TFsBackend.Disconnect;
begin
end;

function TFsBackend.IsConnected: Boolean;
begin
  Result := True;
end;

function TFsBackend.IsLocal: Boolean;
begin
  Result := False;
end;

{ ---------------------------------------------------------------- TLocalFs }

function TLocalFs.IsLocal: Boolean;
begin
  Result := True;
end;

function TLocalFs.HomeDir: string;
begin
  Result := GetEnvironmentVariable('HOME');
  if Result = '' then Result := '/';
end;

function TLocalFs.RealPath(const P: string): string;
begin
  Result := ExpandFileName(P);
  if (Length(Result) > 1) and (Result[Length(Result)] = '/') then
    Delete(Result, Length(Result), 1);
  if not DirectoryExists(Result) then
    raise Exception.Create('No such directory: ' + P);
end;

function StatToEntry(const Name: string; const st, lst: Stat; IsLink: Boolean): TFileEntry;
begin
  Result := Default(TFileEntry);
  Result.Name := Name;
  Result.IsLink := IsLink;
  Result.IsDir := fpS_ISDIR(st.st_mode);
  Result.Size := st.st_size;
  Result.MTime := st.st_mtime;
  Result.Mode := st.st_mode and &7777;
  Result.Owner := UidName(lst.st_uid);
  Result.Group := GidName(lst.st_gid);
end;

function TLocalFs.List(const Dir: string): TFileEntries;
var
  sr: TSearchRec;
  n: Integer;
  full: string;
  st, lst: Stat;
  islink: Boolean;
begin
  Result := nil;
  n := 0;
  if FindFirst(LocalJoin(Dir, '*'), faAnyFile or faHidden or faDirectory or faSymLink, sr) = 0 then
  begin
    try
      repeat
        if (sr.Name = '.') or (sr.Name = '..') then Continue;
        full := LocalJoin(Dir, sr.Name);
        if fpLStat(full, lst) <> 0 then Continue;
        islink := fpS_ISLNK(lst.st_mode);
        if islink then
        begin
          if fpStat(full, st) <> 0 then st := lst;
        end
        else
          st := lst;
        if n >= Length(Result) then SetLength(Result, n * 2 + 32);
        Result[n] := StatToEntry(sr.Name, st, lst, islink);
        Inc(n);
      until FindNext(sr) <> 0;
    finally
      FindClose(sr);
    end;
  end
  else if not DirectoryExists(Dir) then
    raise Exception.Create('No such directory: ' + Dir)
  else if fpAccess(Dir, R_OK or X_OK) <> 0 then
    raise Exception.Create('Permission denied: ' + Dir);
  SetLength(Result, n);
end;

function TLocalFs.GetEntry(const P: string; out E: TFileEntry): Boolean;
var
  st, lst: Stat;
begin
  Result := fpLStat(P, lst) = 0;
  if not Result then Exit;
  if fpS_ISLNK(lst.st_mode) then
  begin
    if fpStat(P, st) <> 0 then st := lst;
    E := StatToEntry(ExtractFileName(P), st, lst, True);
  end
  else
    E := StatToEntry(ExtractFileName(P), lst, lst, False);
end;

procedure RaiseErrno(const Prefix: string);
begin
  raise Exception.Create(Prefix + ': ' + SysErrorMessage(fpGetErrno));
end;

procedure TLocalFs.MkDir(const P: string);
begin
  if fpMkDir(P, &755) <> 0 then RaiseErrno('Cannot create ' + P);
end;

procedure TLocalFs.RemoveFile(const P: string);
begin
  if fpUnlink(P) <> 0 then RaiseErrno('Cannot delete ' + P);
end;

procedure TLocalFs.RemoveDir(const P: string);
begin
  if fpRmDir(P) <> 0 then RaiseErrno('Cannot delete ' + P);
end;

procedure TLocalFs.Rename(const A, B: string);
begin
  if fpRename(A, B) <> 0 then RaiseErrno('Cannot rename ' + A);
end;

procedure TLocalFs.Chmod(const P: string; Mode: LongWord);
begin
  if fpChmod(P, Mode and &7777) <> 0 then RaiseErrno('Cannot change permissions of ' + P);
end;

procedure CopyLocal(const Src, Dst: string; Progress: TFsProgress);
var
  fi, fo: cint;
  buf: array[0..131071] of Byte;
  n: TSsize;
  total, done: Int64;
  st, dst_st: Stat;
begin
  fi := fpOpen(Src, O_RDONLY);
  if fi < 0 then RaiseErrno('Cannot open ' + Src);
  try
    fpFStat(fi, st);
    total := st.st_size;
    { copying a file onto itself would truncate it }
    if (fpStat(Dst, dst_st) = 0) and (dst_st.st_dev = st.st_dev) and (dst_st.st_ino = st.st_ino) then
      raise Exception.Create('"' + Dst + '" is the source file itself');
    fo := fpOpen(Dst, O_WRONLY or O_CREAT or O_TRUNC, st.st_mode and &777);
    if fo < 0 then RaiseErrno('Cannot create ' + Dst);
    done := 0;
    try
      repeat
        n := fpRead(fi, buf[0], SizeOf(buf));
        if n < 0 then RaiseErrno('Read error on ' + Src);
        if n > 0 then
        begin
          if fpWrite(fo, buf[0], n) <> n then RaiseErrno('Write error on ' + Dst);
          Inc(done, n);
          if Assigned(Progress) and not Progress(done, total) then
          begin
            fpClose(fo);
            fo := -1;
            fpUnlink(Dst);
            raise Exception.Create('Transfer cancelled');
          end;
        end;
      until n <= 0;
    finally
      if fo >= 0 then fpClose(fo);
    end;
  finally
    fpClose(fi);
  end;
end;

procedure TLocalFs.Download(const Remote, Local: string; Progress: TFsProgress);
begin
  CopyLocal(Remote, Local, Progress);
end;

procedure TLocalFs.Upload(const Local, Remote: string; Progress: TFsProgress);
begin
  CopyLocal(Local, Remote, Progress);
end;

function TLocalFs.Clone: TFsBackend;
begin
  Result := TLocalFs.Create;
end;

function TLocalFs.Name: string;
begin
  Result := 'local';
end;

{ ---------------------------------------------------------------- TSftpFs }

constructor TSftpFs.Create(const Argv: array of string; const Desc: string);
var
  i: Integer;
begin
  inherited Create;
  SetLength(FArgv, Length(Argv));
  for i := 0 to High(Argv) do FArgv[i] := Argv[i];
  FDesc := Desc;
  FClient := TSftpClient.Create;
end;

destructor TSftpFs.Destroy;
begin
  FClient.Free;
  inherited Destroy;
end;

procedure TSftpFs.Connect;
begin
  if not FClient.Connected then
  begin
    FClient.Connect(FArgv);
    if FHome = '' then
      FHome := FClient.RealPath('.');
  end;
end;

procedure TSftpFs.Disconnect;
begin
  FClient.Disconnect;
end;

function TSftpFs.IsConnected: Boolean;
begin
  Result := FClient.Connected;
end;

function TSftpFs.HomeDir: string;
begin
  Connect;
  Result := FHome;
end;

function TSftpFs.RealPath(const P: string): string;
var
  a: TSftpAttrs;
begin
  Connect;
  Result := FClient.RealPath(P);
  if not FClient.Stat(Result, a) or ((a.Perms and S_IFMT_) <> S_IFDIR_) then
    raise ESftpError.Create('No such directory: ' + P);
end;

function AttrToEntry(const Name, LongName: string; const A: TSftpAttrs; IsLink: Boolean): TFileEntry;
var
  f: array of string;
  s: string;
  i, n, p: Integer;
begin
  Result := Default(TFileEntry);
  Result.Name := Name;
  Result.IsLink := IsLink;
  Result.IsDir := (A.Perms and S_IFMT_) = S_IFDIR_;
  Result.Size := A.Size;
  Result.MTime := A.MTime;
  Result.Mode := A.Perms and &7777;
  Result.Owner := '';
  Result.Group := '';
  { owner and group names come from the "ls -l" style long name }
  if LongName <> '' then
  begin
    s := LongName;
    SetLength(f, 4);
    n := 0;
    i := 1;
    while (n < 4) and (i <= Length(s)) do
    begin
      while (i <= Length(s)) and (s[i] = ' ') do Inc(i);
      p := i;
      while (i <= Length(s)) and (s[i] <> ' ') do Inc(i);
      f[n] := Copy(s, p, i - p);
      Inc(n);
    end;
    if n = 4 then
    begin
      Result.Owner := f[2];
      Result.Group := f[3];
    end;
  end;
  if Result.Owner = '' then Result.Owner := IntToStr(A.Uid);
  if Result.Group = '' then Result.Group := IntToStr(A.Gid);
end;

function TSftpFs.List(const Dir: string): TFileEntries;
var
  names: TSftpNames;
  i: Integer;
  a: TSftpAttrs;
  islink: Boolean;
begin
  Connect;
  names := FClient.ListDir(Dir);
  Result := nil;
  SetLength(Result, Length(names));
  for i := 0 to High(names) do
  begin
    islink := (names[i].Attrs.Perms and S_IFMT_) = S_IFLNK_;
    a := names[i].Attrs;
    if islink then
    begin
      { resolve the link target type (directory or file) }
      if not FClient.Stat(LocalJoin(Dir, names[i].Name), a) then
        a := names[i].Attrs;
    end;
    Result[i] := AttrToEntry(names[i].Name, names[i].LongName, a, islink);
  end;
end;

function TSftpFs.GetEntry(const P: string; out E: TFileEntry): Boolean;
var
  a, la: TSftpAttrs;
  islink: Boolean;
  base: string;
  i: Integer;
begin
  Connect;
  Result := FClient.LStat(P, la);
  if not Result then Exit;
  islink := (la.Perms and S_IFMT_) = S_IFLNK_;
  a := la;
  if islink then FClient.Stat(P, a);
  base := P;
  i := Length(base);
  while (i > 0) and (base[i] <> '/') do Dec(i);
  base := Copy(base, i + 1, MaxInt);
  E := AttrToEntry(base, '', a, islink);
end;

procedure TSftpFs.MkDir(const P: string);
begin
  Connect;
  FClient.MkDir(P);
end;

procedure TSftpFs.RemoveFile(const P: string);
begin
  Connect;
  FClient.Remove(P);
end;

procedure TSftpFs.RemoveDir(const P: string);
begin
  Connect;
  FClient.RmDir(P);
end;

procedure TSftpFs.Rename(const A, B: string);
begin
  Connect;
  FClient.Rename(A, B);
end;

procedure TSftpFs.Chmod(const P: string; Mode: LongWord);
begin
  Connect;
  FClient.Chmod(P, Mode);
end;

procedure TSftpFs.Download(const Remote, Local: string; Progress: TFsProgress);
begin
  Connect;
  FClient.Download(Remote, Local, TSftpProgress(Progress));
end;

procedure TSftpFs.Upload(const Local, Remote: string; Progress: TFsProgress);
begin
  Connect;
  FClient.Upload(Local, Remote, TSftpProgress(Progress));
end;

function TSftpFs.Clone: TFsBackend;
begin
  Result := TSftpFs.Create(FArgv, FDesc);
  TSftpFs(Result).FHome := FHome;
end;

function TSftpFs.Name: string;
begin
  Result := FDesc;
end;

{ ---------------------------------------------------------------- TFtpFs }

constructor TFtpFs.Create(const Host: string; Port: Integer; const User, Pass: string; Passive: Boolean);
begin
  inherited Create;
  FHost := Host;
  FPort := Port;
  FUser := User;
  FPass := Pass;
  FPassive := Passive;
  FClient := TFtpClient.Create;
end;

destructor TFtpFs.Destroy;
begin
  FClient.Free;
  inherited Destroy;
end;

procedure TFtpFs.Connect;
begin
  if not FClient.Connected then
  begin
    FClient.Connect(FHost, FPort, FUser, FPass, FPassive);
    if FHome = '' then FHome := FClient.Pwd;
  end;
end;

procedure TFtpFs.Disconnect;
begin
  FClient.Disconnect;
end;

function TFtpFs.IsConnected: Boolean;
begin
  Result := FClient.Connected;
end;

function TFtpFs.HomeDir: string;
begin
  Connect;
  Result := FHome;
end;

function TFtpFs.RealPath(const P: string): string;
begin
  Connect;
  FClient.Cwd(P);
  Result := FClient.Pwd;
end;

function TFtpFs.List(const Dir: string): TFileEntries;
var
  e: TFtpEntries;
  i: Integer;
begin
  Connect;
  e := FClient.List(Dir);
  Result := nil;
  SetLength(Result, Length(e));
  for i := 0 to High(e) do
  begin
    Result[i].Name := e[i].Name;
    Result[i].IsDir := e[i].IsDir;
    Result[i].IsLink := e[i].IsLink;
    Result[i].Size := e[i].Size;
    Result[i].MTime := e[i].MTime;
    Result[i].Mode := e[i].Mode;
    Result[i].Owner := e[i].Owner;
    Result[i].Group := e[i].Group;
  end;
end;

function TFtpFs.GetEntry(const P: string; out E: TFileEntry): Boolean;
var
  sz: Int64;
  i: Integer;
begin
  Connect;
  FillChar(E, SizeOf(E), 0);
  E.Name := P;
  i := Length(P);
  while (i > 0) and (P[i] <> '/') do Dec(i);
  E.Name := Copy(P, i + 1, MaxInt);
  sz := FClient.Size(P);
  Result := sz >= 0;
  E.Size := sz;
end;

procedure TFtpFs.MkDir(const P: string);
begin
  Connect;
  FClient.MkDir(P);
end;

procedure TFtpFs.RemoveFile(const P: string);
begin
  Connect;
  FClient.Delete(P);
end;

procedure TFtpFs.RemoveDir(const P: string);
begin
  Connect;
  FClient.RmDir(P);
end;

procedure TFtpFs.Rename(const A, B: string);
begin
  Connect;
  FClient.Rename(A, B);
end;

procedure TFtpFs.Chmod(const P: string; Mode: LongWord);
begin
  Connect;
  FClient.Chmod(P, Mode);
end;

procedure TFtpFs.Download(const Remote, Local: string; Progress: TFsProgress);
begin
  Connect;
  FClient.Retrieve(Remote, Local, TFtpProgress(Progress));
end;

procedure TFtpFs.Upload(const Local, Remote: string; Progress: TFsProgress);
begin
  Connect;
  FClient.Store(Local, Remote, TFtpProgress(Progress));
end;

function TFtpFs.Clone: TFsBackend;
begin
  Result := TFtpFs.Create(FHost, FPort, FUser, FPass, FPassive);
  TFtpFs(Result).FHome := FHome;
end;

function TFtpFs.Name: string;
begin
  if FUser <> '' then
    Result := 'ftp://' + FUser + '@' + FHost
  else
    Result := 'ftp://' + FHost;
end;

{ ---------------------------------------------------------------- token / jobs }

constructor TFsToken.Create;
begin
  inherited Create;
  FAlive := True;
end;

function TFsToken.Alive: Boolean;
begin
  Result := FAlive;
end;

procedure TFsToken.Kill;
begin
  FAlive := False;
end;

procedure TFsJob.Finish;
begin
  try
    if (Token <> nil) and Token.Alive then
      Done;
  finally
    Free;
  end;
end;

{ ---------------------------------------------------------------- TFsWorker }

constructor TFsWorker.Create(Backend: TFsBackend; IdleCloseMs: Integer);
begin
  FBackend := Backend;
  FQueue := TThreadList.Create;
  FEvent := TEvent.Create(nil, False, False, '');
  FLock := TCriticalSection.Create;
  FIdleCloseMs := IdleCloseMs;
  FreeOnTerminate := True;
  inherited Create(False);
end;

destructor TFsWorker.Destroy;
var
  l: TList;
  i: Integer;
begin
  try
    FBackend.Disconnect;
  except
  end;
  FBackend.Free;
  l := FQueue.LockList;
  try
    for i := 0 to l.Count - 1 do
      TFsJob(l[i]).Free;
    l.Clear;
  finally
    FQueue.UnlockList;
  end;
  FQueue.Free;
  FEvent.Free;
  FLock.Free;
  inherited Destroy;
end;

procedure TFsWorker.Add(Job: TFsJob);
begin
  FQueue.Add(Job);
  FEvent.SetEvent;
end;

procedure TFsWorker.CancelAll;
var
  l: TList;
  i: Integer;
begin
  l := FQueue.LockList;
  try
    for i := 0 to l.Count - 1 do
      TFsJob(l[i]).Cancelled := True;
  finally
    FQueue.UnlockList;
  end;
  FLock.Enter;
  try
    if FCurrent <> nil then FCurrent.Cancelled := True;
  finally
    FLock.Leave;
  end;
end;

function TFsWorker.Pending: Integer;
var
  l: TList;
begin
  l := FQueue.LockList;
  try
    Result := l.Count;
  finally
    FQueue.UnlockList;
  end;
  if FCurrent <> nil then Inc(Result);
end;

procedure TFsWorker.Shutdown;
begin
  CancelAll;
  Terminate;
  FEvent.SetEvent;
end;

procedure TFsWorker.Execute;
var
  l: TList;
  job: TFsJob;
  idle: Integer;
  wr: TWaitResult;
begin
  idle := 0;
  while not Terminated do
  begin
    job := nil;
    l := FQueue.LockList;
    try
      if l.Count > 0 then
      begin
        job := TFsJob(l[0]);
        l.Delete(0);
      end;
    finally
      FQueue.UnlockList;
    end;
    if job = nil then
    begin
      wr := FEvent.WaitFor(500);
      if wr = wrTimeout then
      begin
        Inc(idle, 500);
        if (FIdleCloseMs > 0) and (idle >= FIdleCloseMs) and FBackend.IsConnected then
          try
            FBackend.Disconnect;
          except
          end;
      end;
      Continue;
    end;
    idle := 0;
    FLock.Enter;
    FCurrent := job;
    FLock.Leave;
    try
      if not job.Cancelled and not Terminated then
        job.Execute(FBackend)
      else
        job.Err := 'Cancelled';
    except
      on E: Exception do
      begin
        job.Err := E.Message;
        { a failed remote operation may leave the protocol out of sync }
        if not FBackend.IsLocal then
          try
            FBackend.Disconnect;
          except
          end;
      end;
    end;
    FLock.Enter;
    FCurrent := nil;
    FLock.Leave;
    if Terminated then
      job.Free
    else
      TThread.Queue(nil, @job.Finish);
  end;
end;

initialization
  UserMap := TStringList.Create;
  GroupMap := TStringList.Create;
  MapLock := TCriticalSection.Create;

finalization
  UserMap.Free;
  GroupMap.Free;
  MapLock.Free;

end.

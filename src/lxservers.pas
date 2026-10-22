{ LinXterm - network servers: HTTP, FTP, TFTP (written in Pascal) and a
  user-mode SSH/SFTP server (OpenSSH sshd), plus iperf3 when available. }
unit lxservers;

{$mode objfpc}{$H+}
{$packrecords C}

interface

uses
  Classes, SysUtils, SyncObjs, BaseUnix, Unix, Sockets, fpjson, lxgtk, lxutil, lxconfig, lxtabs, lxnet;

procedure ShowServersWindow;

implementation

uses
  StrUtils, DateUtils, Math;

type
  TServerKind = (svTFTP, svFTP, svHTTP, svSSH, svIperf);

  TServerConfig = record
    Port: Integer;
    Root: string;
    Bind: string;
    User, Pass: string;
    Anonymous, ReadOnly: Boolean;
  end;

const
  ServerNames: array[TServerKind] of string = ('TFTP server', 'FTP server', 'HTTP server', 'SSH/SFTP server', 'Iperf server');
  ServerIds: array[TServerKind] of string = ('tftp', 'ftp', 'http', 'ssh', 'iperf');
  ServerIcons: array[TServerKind] of string = ('network-transmit-receive', 'filezilla', 'web-browser', 'putty', 'etherape');
  DefaultPorts: array[TServerKind] of Integer = (6969, 2121, 8080, 2222, 5201);

function realpath(path: PChar; resolved: PChar): PChar; cdecl; external 'c';

var
  LogLock: TCriticalSection;
  LogQueue: TStringList;

procedure ServerLog(const Msg: string);
begin
  LogLock.Enter;
  try
    LogQueue.Add(FormatDateTime('hh:nn:ss', Now) + '  ' + Msg);
  finally
    LogLock.Leave;
  end;
end;

function LocalJoinPath(const A, B: string): string;
begin
  if (A <> '') and (A[Length(A)] = '/') then Result := A + B else Result := A + '/' + B;
end;

function RealPathOf(const P: string): string;
var
  buf: array[0..4095] of Char;
begin
  if realpath(PChar(P), @buf[0]) <> nil then
    Result := AnsiString(PChar(@buf[0]))
  else
    Result := '';
end;

{ maps a virtual path ("/a/../b") inside Root; returns '' when it escapes Root }
function MapPath(const Root, Cwd, Arg: string; out Virt: string): string;
var
  parts: TStringArray;
  stack: TStringList;
  p, full, rp, parent: string;
  i: Integer;
begin
  Result := '';
  if (Arg <> '') and (Arg[1] = '/') then full := Arg else full := Cwd + '/' + Arg;
  parts := SplitString(full, '/');
  stack := TStringList.Create;
  try
    for p in parts do
    begin
      if (p = '') or (p = '.') then Continue;
      if p = '..' then
      begin
        if stack.Count > 0 then stack.Delete(stack.Count - 1);
      end
      else
        stack.Add(p);
    end;
    Virt := '/';
    for i := 0 to stack.Count - 1 do
    begin
      if Virt <> '/' then Virt := Virt + '/';
      Virt := Virt + stack[i];
    end;
  finally
    stack.Free;
  end;
  if Virt = '/' then full := Root else full := Root + Virt;
  { refuse symlinks pointing outside of the root }
  rp := RealPathOf(full);
  if rp = '' then
  begin
    parent := RealPathOf(ExtractFileDir(full));
    if (parent = '') or ((parent <> Root) and (Pos(Root + '/', parent) <> 1)) then Exit;
  end
  else if (rp <> Root) and (Pos(Root + '/', rp) <> 1) then
    Exit;
  Result := full;
end;

{ ---------------------------------------------------------------- base TCP server }

type
  TServer = class;

  TConnThread = class(TThread)
  public
    Server: TServer;
    Fd: cint;
    Peer: string;
    constructor Create(AServer: TServer; AFd: cint);
    procedure Execute; override;
    procedure Handle; virtual; abstract;
  end;
  TConnThreadClass = class of TConnThread;

  TServer = class(TThread)
  public
    Kind: TServerKind;
    Cfg: TServerConfig;
    ListenFd: cint;
    Lock: TCriticalSection;
    Clients: TList;   { client fds }
    ConnClass: TConnThreadClass;
    Active: Integer;
    constructor Create(AKind: TServerKind; const ACfg: TServerConfig; AListen: cint; AClass: TConnThreadClass);
    destructor Destroy; override;
    procedure Execute; override;
    procedure AddClient(Fd: cint);
    procedure RemoveClient(Fd: cint);
    procedure StopServer;
  end;

constructor TConnThread.Create(AServer: TServer; AFd: cint);
var
  port: Integer;
begin
  Server := AServer;
  Fd := AFd;
  Peer := PeerAddress(AFd, port);
  FreeOnTerminate := True;
  InterLockedIncrement(Server.Active);
  inherited Create(False);
end;

procedure TConnThread.Execute;
begin
  try
    try
      Handle;
    except
      on E: Exception do ServerLog(ServerNames[Server.Kind] + ': ' + Peer + ': ' + E.Message);
    end;
  finally
    Server.RemoveClient(Fd);
    fpShutdown(Fd, 2);
    fpClose(Fd);
    InterLockedDecrement(Server.Active);
  end;
end;

constructor TServer.Create(AKind: TServerKind; const ACfg: TServerConfig; AListen: cint; AClass: TConnThreadClass);
begin
  Kind := AKind;
  Cfg := ACfg;
  ListenFd := AListen;
  ConnClass := AClass;
  Lock := TCriticalSection.Create;
  Clients := TList.Create;
  FreeOnTerminate := False;
  inherited Create(False);
end;

destructor TServer.Destroy;
begin
  Clients.Free;
  Lock.Free;
  inherited Destroy;
end;

procedure TServer.AddClient(Fd: cint);
begin
  Lock.Enter;
  Clients.Add(Pointer(PtrInt(Fd)));
  Lock.Leave;
end;

procedure TServer.RemoveClient(Fd: cint);
begin
  Lock.Enter;
  Clients.Remove(Pointer(PtrInt(Fd)));
  Lock.Leave;
end;

procedure TServer.Execute;
var
  c: cint;
begin
  while not Terminated do
  begin
    if WaitFd(ListenFd, False, 300) <= 0 then Continue;
    c := fpAccept(ListenFd, nil, nil);
    if c < 0 then Continue;
    if Terminated then
    begin
      fpClose(c);
      Break;
    end;
    SetSocketTimeouts(c, 300);
    AddClient(c);
    ConnClass.Create(Self, c);
  end;
end;

procedure TServer.StopServer;
var
  i: Integer;
begin
  Terminate;
  WaitFor;
  fpClose(ListenFd);
  Lock.Enter;
  try
    for i := 0 to Clients.Count - 1 do
      fpShutdown(cint(PtrInt(Clients[i])), 2);
  finally
    Lock.Leave;
  end;
  { give the connection threads a moment to notice }
  for i := 1 to 50 do
  begin
    if Active <= 0 then Break;
    Sleep(20);
  end;
end;

function RecvLine(Fd: cint; var Buf: string; out Line: string; MaxLen: Integer): Boolean;
var
  p, n: Integer;
  tmp: array[0..4095] of Char;
begin
  Result := False;
  while True do
  begin
    p := Pos(#10, Buf);
    if p > 0 then
    begin
      Line := Copy(Buf, 1, p - 1);
      Delete(Buf, 1, p);
      if (Line <> '') and (Line[Length(Line)] = #13) then Delete(Line, Length(Line), 1);
      Exit(True);
    end;
    if Length(Buf) > MaxLen then Exit;
    n := fpRecv(Fd, @tmp[0], SizeOf(tmp), 0);
    if n <= 0 then
    begin
      if (n < 0) and (fpGetErrno = ESysEINTR) then Continue;
      Exit;
    end;
    Buf := Buf + BufToStr(tmp, n);
  end;
end;

function SendFileTo(Fd: cint; const FileName: string; Offset: Int64): Boolean;
var
  f: cint;
  buf: array[0..65535] of Char;
  n: Integer;
  s: string;
begin
  Result := False;
  f := fpOpen(FileName, O_RDONLY);
  if f < 0 then Exit;
  try
    if Offset > 0 then fpLSeek(f, Offset, SEEK_SET);
    repeat
      n := fpRead(f, buf[0], SizeOf(buf));
      if n > 0 then
      begin
        SetString(s, PChar(@buf[0]), n);
        if not SendAll(Fd, s) then Exit;
      end;
    until n <= 0;
    Result := n = 0;
  finally
    fpClose(f);
  end;
end;

function MimeType(const FileName: string): string;
begin
  case LowerCase(ExtractFileExt(FileName)) of
    '.html', '.htm': Result := 'text/html; charset=utf-8';
    '.txt', '.log', '.md', '.conf', '.cfg', '.ini', '.sh', '.py', '.c', '.h', '.pas': Result := 'text/plain; charset=utf-8';
    '.css': Result := 'text/css';
    '.js': Result := 'application/javascript';
    '.json': Result := 'application/json';
    '.xml': Result := 'application/xml';
    '.png': Result := 'image/png';
    '.jpg', '.jpeg': Result := 'image/jpeg';
    '.gif': Result := 'image/gif';
    '.svg': Result := 'image/svg+xml';
    '.ico': Result := 'image/x-icon';
    '.pdf': Result := 'application/pdf';
    '.zip': Result := 'application/zip';
    '.gz', '.tgz': Result := 'application/gzip';
    '.mp4': Result := 'video/mp4';
    '.mp3': Result := 'audio/mpeg';
    '.iso', '.img', '.bin': Result := 'application/octet-stream';
  else
    Result := 'application/octet-stream';
  end;
end;

function UrlDecode(const S: string): string;
var
  i: Integer;
begin
  Result := '';
  i := 1;
  while i <= Length(S) do
  begin
    if (S[i] = '%') and (i + 2 <= Length(S)) then
    begin
      Result := Result + Chr(StrToIntDef('$' + Copy(S, i + 1, 2), Ord('?')));
      Inc(i, 3);
    end
    else
    begin
      if S[i] = '+' then Result := Result + ' ' else Result := Result + S[i];
      Inc(i);
    end;
  end;
end;

function UrlEncode(const S: string): string;
var
  c: Char;
begin
  Result := '';
  for c in S do
    if c in ['A'..'Z', 'a'..'z', '0'..'9', '-', '_', '.', '~', '/'] then Result := Result + c
    else Result := Result + '%' + IntToHex(Ord(c), 2);
end;

function HtmlEscape(const S: string): string;
begin
  Result := StringReplace(StringReplace(StringReplace(S, '&', '&amp;', [rfReplaceAll]), '<', '&lt;', [rfReplaceAll]),
    '>', '&gt;', [rfReplaceAll]);
end;

{ ---------------------------------------------------------------- HTTP }

type
  THttpConn = class(TConnThread)
  public
    procedure Handle; override;
    procedure Reply(Code: Integer; const Status, CType, Body: string; HeadOnly: Boolean; const Extra: string = '');
  end;

procedure THttpConn.Reply(Code: Integer; const Status, CType, Body: string; HeadOnly: Boolean; const Extra: string);
var
  h: string;
begin
  h := 'HTTP/1.1 ' + IntToStr(Code) + ' ' + Status + #13#10 +
    'Server: LinXterm' + #13#10 +
    'Content-Type: ' + CType + #13#10 +
    'Content-Length: ' + IntToStr(Length(Body)) + #13#10 + Extra +
    'Connection: close' + #13#10#13#10;
  if HeadOnly then SendAll(Fd, h) else SendAll(Fd, h + Body);
end;

procedure THttpConn.Handle;
var
  buf, line, method, target, virt, real, html, name, q: string;
  parts: TStringArray;
  st: Stat;
  sr: TSearchRec;
  list: TStringList;
  i, p: Integer;
  head: Boolean;
begin
  buf := '';
  if not RecvLine(Fd, buf, line, 8192) then Exit;
  parts := SplitString(line, ' ');
  if Length(parts) < 2 then
  begin
    Reply(400, 'Bad Request', 'text/plain', 'Bad request', False);
    Exit;
  end;
  { skip the headers }
  repeat
    if not RecvLine(Fd, buf, q, 16384) then Break;
  until q = '';
  method := UpperCase(parts[0]);
  target := parts[1];
  p := Pos('?', target);
  if p > 0 then target := Copy(target, 1, p - 1);
  target := UrlDecode(target);
  head := method = 'HEAD';
  if (method <> 'GET') and not head then
  begin
    Reply(405, 'Method Not Allowed', 'text/plain', 'Method not allowed', False, 'Allow: GET, HEAD'#13#10);
    ServerLog('HTTP ' + Peer + ' ' + method + ' ' + target + ' -> 405');
    Exit;
  end;
  real := MapPath(Server.Cfg.Root, '/', target, virt);
  if (real = '') or (fpStat(real, st) <> 0) then
  begin
    Reply(404, 'Not Found', 'text/html', '<h1>404 Not Found</h1>', head);
    ServerLog('HTTP ' + Peer + ' ' + method + ' ' + target + ' -> 404');
    Exit;
  end;
  if fpS_ISDIR(st.st_mode) then
  begin
    if (target = '') or (target[Length(target)] <> '/') then
    begin
      Reply(301, 'Moved Permanently', 'text/html', '', head, 'Location: ' + UrlEncode(target + '/') + #13#10);
      Exit;
    end;
    if FileExists(real + '/index.html') then
    begin
      real := real + '/index.html';
      fpStat(real, st);
    end
    else
    begin
      list := TStringList.Create;
      try
        if FindFirst(real + '/*', faAnyFile or faDirectory, sr) = 0 then
        begin
          repeat
            if (sr.Name = '.') or (sr.Name = '..') then Continue;
            if (sr.Attr and faDirectory) <> 0 then list.Add('0' + sr.Name + '/') else list.Add('1' + sr.Name);
          until FindNext(sr) <> 0;
          FindClose(sr);
        end;
        list.Sort;
        html := '<!DOCTYPE html><html><head><meta charset="utf-8"><title>Index of ' + HtmlEscape(virt) +
          '</title><style>body{font-family:sans-serif;margin:2em}a{text-decoration:none}li{padding:2px}</style></head>' +
          '<body><h2>Index of ' + HtmlEscape(virt) + '</h2><ul>';
        if virt <> '/' then html := html + '<li><a href="../">../</a></li>';
        for i := 0 to list.Count - 1 do
        begin
          name := Copy(list[i], 2, MaxInt);
          html := html + '<li><a href="' + UrlEncode(name) + '">' + HtmlEscape(name) + '</a></li>';
        end;
        html := html + '</ul><hr><small>LinXterm HTTP server</small></body></html>';
      finally
        list.Free;
      end;
      Reply(200, 'OK', 'text/html; charset=utf-8', html, head);
      ServerLog('HTTP ' + Peer + ' ' + method + ' ' + target + ' -> 200 (listing)');
      Exit;
    end;
  end;
  if fpAccess(real, R_OK) <> 0 then
  begin
    Reply(403, 'Forbidden', 'text/html', '<h1>403 Forbidden</h1>', head);
    ServerLog('HTTP ' + Peer + ' ' + method + ' ' + target + ' -> 403');
    Exit;
  end;
  SendAll(Fd, 'HTTP/1.1 200 OK'#13#10'Server: LinXterm'#13#10'Content-Type: ' + MimeType(real) + #13#10 +
    'Content-Length: ' + IntToStr(st.st_size) + #13#10'Connection: close'#13#10#13#10);
  if not head then SendFileTo(Fd, real, 0);
  ServerLog('HTTP ' + Peer + ' ' + method + ' ' + target + ' -> 200 (' + HumanSize(st.st_size) + ')');
end;

{ ---------------------------------------------------------------- FTP }

type
  TFtpConn = class(TConnThread)
  private
    Cwd: string;
    User: string;
    Logged: Boolean;
    PasvFd: cint;
    ActiveAddr: string;
    ActivePort: Integer;
    RenameFrom: string;
    RestOffset: Int64;
    procedure Send(const S: string);
    function OpenData: cint;
    procedure CloseData;
    function ListLine(const Dir, Name: string; Mlsd: Boolean): string;
  public
    procedure Handle; override;
  end;

procedure TFtpConn.Send(const S: string);
begin
  SendAll(Fd, S + #13#10);
end;

procedure TFtpConn.CloseData;
begin
  if PasvFd >= 0 then fpClose(PasvFd);
  PasvFd := -1;
end;

function TFtpConn.OpenData: cint;
var
  err: string;
begin
  Result := -1;
  if PasvFd >= 0 then
  begin
    if WaitFd(PasvFd, False, 20000) > 0 then
      Result := fpAccept(PasvFd, nil, nil);
    CloseData;
  end
  else if ActiveAddr <> '' then
  begin
    Result := TcpConnect(ActiveAddr, ActivePort, 10000, err);
    ActiveAddr := '';
  end;
  if Result >= 0 then SetSocketTimeouts(Result, 120);
end;

function TFtpConn.ListLine(const Dir, Name: string; Mlsd: Boolean): string;
var
  st: Stat;
  dt: TDateTime;
  dstr: string;
begin
  Result := '';
  if fpLStat(LocalJoinPath(Dir, Name), st) <> 0 then Exit;
  dt := UnixToDateTime(st.st_mtime);
  if Mlsd then
  begin
    if fpS_ISDIR(st.st_mode) then Result := 'type=dir;' else Result := 'type=file;size=' + IntToStr(st.st_size) + ';';
    Result := Result + 'modify=' + FormatDateTime('yyyymmddhhnnss', dt) + ';UNIX.mode=0' +
      OctStr(st.st_mode and &777, 3) + '; ' + Name;
  end
  else
  begin
    if YearOf(dt) = YearOf(Now) then dstr := FormatDateTime('mmm dd hh:nn', dt, DefaultFormatSettings)
    else dstr := FormatDateTime('mmm dd  yyyy', dt, DefaultFormatSettings);
    Result := ModeString(st.st_mode and &777, fpS_ISDIR(st.st_mode), fpS_ISLNK(st.st_mode)) +
      Format(' 1 %-8s %-8s %12d ', ['ftp', 'ftp', st.st_size]) + dstr + ' ' + Name;
  end;
end;

procedure TFtpConn.Handle;
var
  buf, line, cmd, arg, virt, real, data, name, addr, err: string;
  sp, port, n, dfd: Integer;
  st: Stat;
  sr: TSearchRec;
  lfd, f: cint;
  parts: TStringArray;
  rbuf: array[0..65535] of Char;
  ok: Boolean;
  procedure Need(const Msg: string);
  begin
    Send('530 ' + Msg);
  end;
begin
  PasvFd := -1;
  Cwd := '/';
  buf := '';
  Send('220 LinXterm FTP server ready');
  ServerLog('FTP ' + Peer + ' connected');
  while not Server.Terminated do
  begin
    if not RecvLine(Fd, buf, line, 4096) then Break;
    sp := Pos(' ', line);
    if sp > 0 then
    begin
      cmd := UpperCase(Copy(line, 1, sp - 1));
      arg := Copy(line, sp + 1, MaxInt);
    end
    else
    begin
      cmd := UpperCase(line);
      arg := '';
    end;
    if cmd = 'QUIT' then
    begin
      Send('221 Goodbye');
      Break;
    end;
    if cmd = 'USER' then
    begin
      User := arg;
      Logged := False;
      Send('331 Password required for ' + arg);
      Continue;
    end;
    if cmd = 'PASS' then
    begin
      if Server.Cfg.Anonymous and ((LowerCase(User) = 'anonymous') or (LowerCase(User) = 'ftp')) then
        Logged := True
      else
        Logged := (Server.Cfg.User <> '') and (User = Server.Cfg.User) and (arg = Server.Cfg.Pass);
      if Logged then
      begin
        Send('230 Login successful');
        ServerLog('FTP ' + Peer + ' logged in as ' + User);
      end
      else
      begin
        Send('530 Login incorrect');
        ServerLog('FTP ' + Peer + ' login failed for ' + User);
        Sleep(1000);
      end;
      Continue;
    end;
    if cmd = 'SYST' then begin Send('215 UNIX Type: L8'); Continue; end;
    if cmd = 'FEAT' then
    begin
      Send('211-Features:');
      Send(' MLSD');
      Send(' SIZE');
      Send(' MDTM');
      Send(' UTF8');
      Send(' EPSV');
      Send(' PASV');
      Send(' REST STREAM');
      Send('211 End');
      Continue;
    end;
    if cmd = 'OPTS' then begin Send('200 OK'); Continue; end;
    if cmd = 'NOOP' then begin Send('200 OK'); Continue; end;
    if (cmd = 'AUTH') or (cmd = 'PBSZ') or (cmd = 'PROT') then begin Send('502 TLS is not supported'); Continue; end;
    if not Logged then
    begin
      Need('Please login with USER and PASS');
      Continue;
    end;
    if (cmd = 'PWD') or (cmd = 'XPWD') then
      Send('257 "' + StringReplace(Cwd, '"', '""', [rfReplaceAll]) + '" is the current directory')
    else if (cmd = 'CWD') or (cmd = 'XCWD') or (cmd = 'CDUP') then
    begin
      if cmd = 'CDUP' then arg := '..';
      real := MapPath(Server.Cfg.Root, Cwd, arg, virt);
      if (real <> '') and DirectoryExists(real) then
      begin
        Cwd := virt;
        Send('250 Directory changed to ' + Cwd);
      end
      else
        Send('550 No such directory');
    end
    else if cmd = 'TYPE' then Send('200 Type set to ' + UpperCase(Copy(arg, 1, 1)))
    else if (cmd = 'MODE') or (cmd = 'STRU') then Send('200 OK')
    else if cmd = 'REST' then
    begin
      RestOffset := StrToInt64Def(arg, 0);
      Send('350 Restarting at ' + IntToStr(RestOffset));
    end
    else if (cmd = 'PASV') or (cmd = 'EPSV') then
    begin
      CloseData;
      addr := LocalAddress(Fd, port);
      PasvFd := TcpListen(addr, 0, err);
      if PasvFd < 0 then
      begin
        Send('425 Cannot open a passive connection');
        Continue;
      end;
      LocalAddress(PasvFd, port);
      if cmd = 'EPSV' then
        Send('229 Entering Extended Passive Mode (|||' + IntToStr(port) + '|)')
      else if Pos(':', addr) > 0 then
        Send('425 Use EPSV with IPv6')
      else
        Send('227 Entering Passive Mode (' + StringReplace(addr, '.', ',', [rfReplaceAll]) + ',' +
          IntToStr(port div 256) + ',' + IntToStr(port mod 256) + ')');
    end
    else if cmd = 'PORT' then
    begin
      parts := SplitString(arg, ',');
      if Length(parts) = 6 then
      begin
        CloseData;
        addr := parts[0] + '.' + parts[1] + '.' + parts[2] + '.' + parts[3];
        port := StrToIntDef(parts[4], 0) * 256 + StrToIntDef(parts[5], 0);
        { the data connection may only go back to the client itself
          (no "FTP bounce" to another computer or to a privileged port) }
        if (addr <> Peer) or (port < 1024) or (port > 65535) then
          Send('500 Illegal PORT command')
        else
        begin
          ActiveAddr := addr;
          ActivePort := port;
          Send('200 PORT command successful');
        end;
      end
      else
        Send('501 Syntax error');
    end
    else if (cmd = 'LIST') or (cmd = 'NLST') or (cmd = 'MLSD') then
    begin
      if (arg <> '') and (arg[1] = '-') then
      begin
        { "LIST -a" style options }
        sp := Pos(' ', arg);
        if sp > 0 then arg := Copy(arg, sp + 1, MaxInt) else arg := '';
      end;
      real := MapPath(Server.Cfg.Root, Cwd, arg, virt);
      if (real = '') or not DirectoryExists(real) then
      begin
        Send('550 No such directory');
        Continue;
      end;
      Send('150 Opening data connection for directory listing');
      dfd := OpenData;
      if dfd < 0 then
      begin
        Send('425 Cannot open the data connection');
        Continue;
      end;
      data := '';
      if FindFirst(real + '/*', faAnyFile or faDirectory or faHidden, sr) = 0 then
      begin
        repeat
          if (sr.Name = '.') or (sr.Name = '..') then Continue;
          if cmd = 'NLST' then data := data + sr.Name + #13#10
          else data := data + ListLine(real, sr.Name, cmd = 'MLSD') + #13#10;
        until FindNext(sr) <> 0;
        FindClose(sr);
      end;
      SendAll(dfd, data);
      fpShutdown(dfd, 2);
      fpClose(dfd);
      Send('226 Transfer complete');
    end
    else if (cmd = 'RETR') or (cmd = 'SIZE') or (cmd = 'MDTM') then
    begin
      real := MapPath(Server.Cfg.Root, Cwd, arg, virt);
      if (real = '') or (fpStat(real, st) <> 0) or fpS_ISDIR(st.st_mode) then
      begin
        Send('550 No such file');
        Continue;
      end;
      if cmd = 'SIZE' then Send('213 ' + IntToStr(st.st_size))
      else if cmd = 'MDTM' then Send('213 ' + FormatDateTime('yyyymmddhhnnss', UnixToDateTime(st.st_mtime)))
      else
      begin
        Send('150 Opening BINARY data connection for ' + virt + ' (' + IntToStr(st.st_size) + ' bytes)');
        dfd := OpenData;
        if dfd < 0 then
        begin
          Send('425 Cannot open the data connection');
          Continue;
        end;
        ok := SendFileTo(dfd, real, RestOffset);
        RestOffset := 0;
        fpShutdown(dfd, 2);
        fpClose(dfd);
        if ok then
        begin
          Send('226 Transfer complete');
          ServerLog('FTP ' + Peer + ' downloaded ' + virt);
        end
        else
          Send('426 Transfer aborted');
      end;
    end
    else if (cmd = 'STOR') or (cmd = 'APPE') then
    begin
      if Server.Cfg.ReadOnly then
      begin
        Send('550 Read-only server');
        Continue;
      end;
      real := MapPath(Server.Cfg.Root, Cwd, arg, virt);
      if real = '' then
      begin
        Send('550 Permission denied');
        Continue;
      end;
      if cmd = 'APPE' then
        f := fpOpen(real, O_WRONLY or O_CREAT or O_APPEND, &644)
      else
        f := fpOpen(real, O_WRONLY or O_CREAT or O_TRUNC, &644);
      if f < 0 then
      begin
        Send('550 Cannot create the file');
        Continue;
      end;
      Send('150 Ok to send data');
      dfd := OpenData;
      if dfd < 0 then
      begin
        fpClose(f);
        Send('425 Cannot open the data connection');
        Continue;
      end;
      ok := True;
      repeat
        n := fpRecv(dfd, @rbuf[0], SizeOf(rbuf), 0);
        if n > 0 then
          if fpWrite(f, rbuf[0], n) <> n then ok := False;
      until n <= 0;
      fpClose(dfd);
      fpClose(f);
      if ok then
      begin
        Send('226 Transfer complete');
        ServerLog('FTP ' + Peer + ' uploaded ' + virt);
      end
      else
        Send('451 Write error');
    end
    else if (cmd = 'DELE') or (cmd = 'RMD') or (cmd = 'XRMD') or (cmd = 'MKD') or (cmd = 'XMKD') or (cmd = 'RNFR') or (cmd = 'RNTO') then
    begin
      if Server.Cfg.ReadOnly then
      begin
        Send('550 Read-only server');
        Continue;
      end;
      real := MapPath(Server.Cfg.Root, Cwd, arg, virt);
      if (real = '') or (virt = '/') then
      begin
        Send('550 Permission denied');
        Continue;
      end;
      if cmd = 'DELE' then
      begin
        if fpUnlink(real) = 0 then Send('250 File deleted') else Send('550 ' + SysErrorMessage(fpGetErrno));
      end
      else if (cmd = 'RMD') or (cmd = 'XRMD') then
      begin
        if fpRmDir(real) = 0 then Send('250 Directory removed') else Send('550 ' + SysErrorMessage(fpGetErrno));
      end
      else if (cmd = 'MKD') or (cmd = 'XMKD') then
      begin
        if fpMkDir(real, &755) = 0 then Send('257 "' + virt + '" created') else Send('550 ' + SysErrorMessage(fpGetErrno));
      end
      else if cmd = 'RNFR' then
      begin
        if fpAccess(real, F_OK) = 0 then
        begin
          RenameFrom := real;
          Send('350 Ready for RNTO');
        end
        else
          Send('550 No such file');
      end
      else
      begin
        if (RenameFrom <> '') and (fpRename(RenameFrom, real) = 0) then Send('250 Rename successful')
        else Send('550 Rename failed');
        RenameFrom := '';
      end;
    end
    else
      Send('502 Command not implemented');
  end;
  CloseData;
  ServerLog('FTP ' + Peer + ' disconnected');
end;

{ ---------------------------------------------------------------- TFTP }

type
  TTftpServer = class(TThread)
  public
    Fd: cint;
    Cfg: TServerConfig;
    constructor Create(AFd: cint; const ACfg: TServerConfig);
    procedure Execute; override;
  end;

  TTftpTransfer = class(TThread)
  public
    Cfg: TServerConfig;
    Client: array[0..127] of Byte;
    ClientLen: TSocklen;
    Packet: string;
    Owner: TTftpServer;
    constructor Create(AOwner: TTftpServer; const ACfg: TServerConfig; Sa: Pointer; SaLen: TSocklen; const Pkt: string);
    procedure Execute; override;
  end;

constructor TTftpServer.Create(AFd: cint; const ACfg: TServerConfig);
begin
  Fd := AFd;
  Cfg := ACfg;
  FreeOnTerminate := False;
  inherited Create(False);
end;

procedure TTftpServer.Execute;
var
  buf: array[0..1023] of Char;
  sa: array[0..127] of Byte;
  len: TSocklen;
  n: Integer;
  pkt: string;
begin
  while not Terminated do
  begin
    if WaitFd(Fd, False, 300) <= 0 then Continue;
    len := SizeOf(sa);
    n := fpRecvFrom(Fd, @buf[0], SizeOf(buf), 0, @sa[0], @len);
    if n < 4 then Continue;
    SetString(pkt, PChar(@buf[0]), n);
    if (Ord(pkt[1]) = 0) and (Ord(pkt[2]) in [1, 2]) then
      TTftpTransfer.Create(Self, Cfg, @sa[0], len, pkt);
  end;
end;

constructor TTftpTransfer.Create(AOwner: TTftpServer; const ACfg: TServerConfig; Sa: Pointer; SaLen: TSocklen; const Pkt: string);
begin
  Owner := AOwner;
  Cfg := ACfg;
  Move(Sa^, Client[0], SaLen);
  ClientLen := SaLen;
  Packet := Pkt;
  FreeOnTerminate := True;
  inherited Create(False);
end;

procedure TTftpTransfer.Execute;
var
  op: Integer;
  fname, virt, real, peer, data: string;
  p: Integer;
  fd, f: cint;
  block: Word;
  buf: array[0..1023] of Char;
  rbuf: array[0..1023] of Char;
  n, tries, port: Integer;
  done, acked: Boolean;
  family: Word;
  procedure SendPkt(const S: string);
  begin
    fpSendTo(fd, @S[1], Length(S), 0, @Client[0], ClientLen);
  end;
  procedure SendError(Code: Integer; const Msg: string);
  begin
    SendPkt(#0#5 + Chr(Code shr 8) + Chr(Code and 255) + Msg + #0);
  end;
  function WaitPacket(out Pkt: string): Boolean;
  var
    sa2: array[0..127] of Byte;
    l2: TSocklen;
  begin
    Result := False;
    if WaitFd(fd, False, 2000) <= 0 then Exit;
    l2 := SizeOf(sa2);
    n := fpRecvFrom(fd, @rbuf[0], SizeOf(rbuf), 0, @sa2[0], @l2);
    if n < 4 then Exit;
    SetString(Pkt, PChar(@rbuf[0]), n);
    Result := True;
  end;
var
  pkt: string;
begin
  op := Ord(Packet[2]);
  p := Pos(#0, Copy(Packet, 3, MaxInt));
  fname := Copy(Packet, 3, p - 1);
  peer := SockAddrToString(@Client[0], ClientLen, port);
  family := PWord(@Client[0])^;
  fd := fpSocket(family, SOCK_DGRAM, 0);
  if fd < 0 then Exit;
  try
    real := MapPath(Cfg.Root, '/', fname, virt);
    if op = 1 then
    begin
      { read request }
      if (real = '') or not FileExists(real) then
      begin
        SendError(1, 'File not found');
        ServerLog('TFTP ' + peer + ' RRQ ' + fname + ' -> not found');
        Exit;
      end;
      f := fpOpen(real, O_RDONLY);
      if f < 0 then
      begin
        SendError(2, 'Access violation');
        Exit;
      end;
      block := 1;
      done := False;
      try
        while not done do
        begin
          n := fpRead(f, buf[0], 512);
          if n < 0 then n := 0;
          SetString(data, PChar(@buf[0]), n);
          if n < 512 then done := True;
          tries := 0;
          acked := False;
          while (tries < 5) and not acked do
          begin
            SendPkt(#0#3 + Chr(block shr 8) + Chr(block and 255) + data);
            if WaitPacket(pkt) and (Ord(pkt[2]) = 4) and (((Ord(pkt[3]) shl 8) or Ord(pkt[4])) = block) then
              acked := True
            else
              Inc(tries);
          end;
          if not acked then
          begin
            ServerLog('TFTP ' + peer + ' RRQ ' + fname + ' -> timeout');
            Exit;
          end;
          Inc(block);
        end;
      finally
        fpClose(f);
      end;
      ServerLog('TFTP ' + peer + ' sent ' + virt);
    end
    else
    begin
      { write request }
      if Cfg.ReadOnly or (real = '') then
      begin
        SendError(2, 'Access violation');
        ServerLog('TFTP ' + peer + ' WRQ ' + fname + ' -> refused');
        Exit;
      end;
      f := fpOpen(real, O_WRONLY or O_CREAT or O_TRUNC, &644);
      if f < 0 then
      begin
        SendError(2, 'Cannot create file');
        Exit;
      end;
      try
        block := 0;
        SendPkt(#0#4#0#0);
        done := False;
        while not done do
        begin
          tries := 0;
          while True do
          begin
            if WaitPacket(pkt) then
            begin
              if (Ord(pkt[2]) = 3) and (((Ord(pkt[3]) shl 8) or Ord(pkt[4])) = Word(block + 1)) then Break;
            end
            else
            begin
              Inc(tries);
              if tries >= 5 then
              begin
                ServerLog('TFTP ' + peer + ' WRQ ' + fname + ' -> timeout');
                Exit;
              end;
              SendPkt(#0#4 + Chr(block shr 8) + Chr(block and 255));
            end;
          end;
          Inc(block);
          data := Copy(pkt, 5, MaxInt);
          if Length(data) > 0 then fpWrite(f, data[1], Length(data));
          SendPkt(#0#4 + Chr(block shr 8) + Chr(block and 255));
          if Length(data) < 512 then done := True;
        end;
      finally
        fpClose(f);
      end;
      ServerLog('TFTP ' + peer + ' received ' + virt);
    end;
  finally
    fpClose(fd);
  end;
end;

function UdpListen(const Bind: string; Port: Integer; out Err: string): cint;
var
  sa6: TInetSockAddr6;
  sa4: TInetSockAddr;
  one: cint;
begin
  Err := '';
  if (Bind = '') or (Bind = '0.0.0.0') or (Bind = '::') then
  begin
    Result := fpSocket(AF_INET6, SOCK_DGRAM, 0);
    if Result >= 0 then
    begin
      one := 0;
      fpSetSockOpt(Result, IPPROTO_IPV6, 26, @one, SizeOf(one));
      FillChar(sa6, SizeOf(sa6), 0);
      sa6.sin6_family := AF_INET6;
      sa6.sin6_port := htons(Port);
      if fpBind(Result, @sa6, SizeOf(sa6)) = 0 then Exit;
      Err := SysErrorMessage(fpGetErrno);
      fpClose(Result);
    end;
  end;
  Result := fpSocket(AF_INET, SOCK_DGRAM, 0);
  if Result < 0 then
  begin
    Err := SysErrorMessage(fpGetErrno);
    Exit;
  end;
  FillChar(sa4, SizeOf(sa4), 0);
  sa4.sin_family := AF_INET;
  sa4.sin_port := htons(Port);
  if (Bind = '') or (Bind = '0.0.0.0') then sa4.sin_addr.s_addr := 0 else sa4.sin_addr := StrToNetAddr(Bind);
  if fpBind(Result, @sa4, SizeOf(sa4)) <> 0 then
  begin
    Err := SysErrorMessage(fpGetErrno);
    fpClose(Result);
    Result := -1;
  end;
end;

{ ---------------------------------------------------------------- server manager / window }

type
  TServerSlot = record
    Cfg: TServerConfig;
    Tcp: TServer;
    Tftp: TTftpServer;
    TftpFd: cint;
    Proc: TChildProcess;
    Running: Boolean;
    StatusLbl, StartBtn, StopBtn, Dot: Pointer;
  end;

  TServersUi = class
  public
    Win, Log: Pointer;
    Timer: guint;
    procedure ProcLine(Sender: TChildProcess; const Line: string; IsErr: Boolean);
    procedure ProcExit(Sender: TChildProcess; Status: Integer);
  end;

var
  Slots: array[TServerKind] of TServerSlot;
  Ui: TServersUi = nil;
  Loaded: Boolean = False;

procedure LoadServerConfig;
var
  d: TJSONData;
  o: TJSONObject;
  k: TServerKind;
  pub: string;
begin
  if Loaded then Exit;
  Loaded := True;
  pub := HomeDir + '/Public';
  if not DirectoryExists(pub) then pub := HomeDir;
  for k := Low(TServerKind) to High(TServerKind) do
  begin
    Slots[k].Cfg.Port := DefaultPorts[k];
    Slots[k].Cfg.Root := pub;
    Slots[k].Cfg.Bind := '0.0.0.0';
    Slots[k].Cfg.User := UserName;
    Slots[k].Cfg.Pass := '';
    Slots[k].Cfg.Anonymous := False;
    Slots[k].Cfg.ReadOnly := k = svTFTP;
    Slots[k].TftpFd := -1;
  end;
  d := LoadJsonFile(ConfigDir + '/servers.json');
  if (d = nil) or (d.JSONType <> jtObject) then
  begin
    d.Free;
    Exit;
  end;
  try
    for k := Low(TServerKind) to High(TServerKind) do
    begin
      o := TJSONObject(d).Find(ServerIds[k], jtObject) as TJSONObject;
      if o = nil then Continue;
      Slots[k].Cfg.Port := JInt(o, 'port', Slots[k].Cfg.Port);
      Slots[k].Cfg.Root := JStr(o, 'root', Slots[k].Cfg.Root);
      Slots[k].Cfg.Bind := JStr(o, 'bind', Slots[k].Cfg.Bind);
      Slots[k].Cfg.User := JStr(o, 'user', Slots[k].Cfg.User);
      Slots[k].Cfg.Anonymous := JBool(o, 'anonymous', Slots[k].Cfg.Anonymous);
      Slots[k].Cfg.ReadOnly := JBool(o, 'readonly', Slots[k].Cfg.ReadOnly);
    end;
  finally
    d.Free;
  end;
  LookupPassword('server:ftp', Slots[svFTP].Cfg.Pass);
end;

procedure SaveServerConfig;
var
  o, s: TJSONObject;
  k: TServerKind;
begin
  o := TJSONObject.Create;
  try
    for k := Low(TServerKind) to High(TServerKind) do
    begin
      s := TJSONObject.Create;
      s.Add('port', Slots[k].Cfg.Port);
      s.Add('root', Slots[k].Cfg.Root);
      s.Add('bind', Slots[k].Cfg.Bind);
      s.Add('user', Slots[k].Cfg.User);
      s.Add('anonymous', Slots[k].Cfg.Anonymous);
      s.Add('readonly', Slots[k].Cfg.ReadOnly);
      o.Add(ServerIds[k], s);
    end;
    SaveJsonFile(ConfigDir + '/servers.json', o);
  finally
    o.Free;
  end;
  if Slots[svFTP].Cfg.Pass <> '' then StorePassword('server:ftp', Slots[svFTP].Cfg.Pass);
end;

function KindAvailable(K: TServerKind): Boolean;
begin
  case K of
    svSSH: Result := FileExists('/usr/sbin/sshd');
    svIperf: Result := FindProgram('iperf3') <> '';
  else
    Result := True;
  end;
end;

procedure UpdateRow(K: TServerKind);
var
  txt: string;
begin
  if Slots[K].StatusLbl = nil then Exit;
  if Slots[K].Running then
    txt := '<span foreground="#2e7d32"><b>running</b></span> on port ' + IntToStr(Slots[K].Cfg.Port)
  else if not KindAvailable(K) then
    txt := '<span foreground="#888888">not installed</span>'
  else
    txt := '<span foreground="#888888">stopped</span>';
  gtk_label_set_markup(Slots[K].StatusLbl, PChar(txt));
  gtk_widget_set_sensitive(Slots[K].StartBtn, (not Slots[K].Running) and KindAvailable(K));
  gtk_widget_set_sensitive(Slots[K].StopBtn, Slots[K].Running);
  if Slots[K].Running then
    gtk_image_set_from_pixbuf(Slots[K].Dot, IconPixbuf('lx-check', 16))
  else
    gtk_image_set_from_pixbuf(Slots[K].Dot, IconPixbuf('lx-cancel', 16));
end;

function SshdConfig(const Cfg: TServerConfig; out Err: string): string;
var
  dir, key, o, sftp, conf: string;
begin
  Err := '';
  dir := ConfigDir + '/sshd';
  ForceDirectories(dir);
  fpChmod(dir, &700);
  key := dir + '/ssh_host_ed25519_key';
  if not FileExists(key) then
    if RunCapture(['ssh-keygen', '-q', '-t', 'ed25519', '-N', '', '-f', key], o) <> 0 then
    begin
      Err := 'Unable to create the host key: ' + o;
      Exit('');
    end;
  sftp := '/usr/libexec/openssh/sftp-server';
  if not FileExists(sftp) then sftp := '/usr/lib/openssh/sftp-server';
  if not FileExists(sftp) then sftp := 'internal-sftp';
  conf := 'Port ' + IntToStr(Cfg.Port) + #10 +
    'ListenAddress ' + IfThen(Cfg.Bind = '', '0.0.0.0', Cfg.Bind) + #10 +
    'HostKey ' + key + #10 +
    'PidFile ' + dir + '/sshd.pid'#10 +
    'AuthorizedKeysFile .ssh/authorized_keys'#10 +
    'PubkeyAuthentication yes'#10 +
    'PasswordAuthentication no'#10 +
    'KbdInteractiveAuthentication no'#10 +
    'UsePAM no'#10 +
    'X11Forwarding yes'#10 +
    'PrintMotd no'#10 +
    'Subsystem sftp ' + sftp + #10;
  Result := dir + '/sshd_config';
  WriteFileText(Result, conf);
end;

procedure StartServer(K: TServerKind);
var
  err, root, conf: string;
  fd: cint;
  cfg: TServerConfig;
  p: TChildProcess;
begin
  if Slots[K].Running then Exit;
  cfg := Slots[K].Cfg;
  root := RealPathOf(cfg.Root);
  if (K in [svTFTP, svFTP, svHTTP]) and ((root = '') or not DirectoryExists(root)) then
  begin
    MsgError('Invalid root folder', cfg.Root);
    Exit;
  end;
  cfg.Root := root;
  case K of
    svHTTP, svFTP:
      begin
        if (K = svFTP) and not cfg.Anonymous and (cfg.Pass = '') then
        begin
          MsgWarning('FTP server', 'Set a password (or allow anonymous access) in the FTP server settings first.');
          Exit;
        end;
        fd := TcpListen(IfThen(cfg.Bind = '0.0.0.0', '', cfg.Bind), cfg.Port, err);
        if fd < 0 then
        begin
          MsgError('Unable to start the ' + ServerNames[K], 'Port ' + IntToStr(cfg.Port) + ': ' + err +
            IfThen(cfg.Port < 1024, #10'Ports below 1024 require administrator rights.', ''));
          Exit;
        end;
        if K = svHTTP then
          Slots[K].Tcp := TServer.Create(K, cfg, fd, THttpConn)
        else
          Slots[K].Tcp := TServer.Create(K, cfg, fd, TFtpConn);
      end;
    svTFTP:
      begin
        fd := UdpListen(cfg.Bind, cfg.Port, err);
        if fd < 0 then
        begin
          MsgError('Unable to start the TFTP server', 'Port ' + IntToStr(cfg.Port) + ': ' + err +
            IfThen(cfg.Port < 1024, #10'Ports below 1024 require administrator rights.', ''));
          Exit;
        end;
        Slots[K].TftpFd := fd;
        Slots[K].Tftp := TTftpServer.Create(fd, cfg);
      end;
    svSSH, svIperf:
      begin
        p := TChildProcess.Create;
        p.Tag := Ord(K);
        p.OnLine := @Ui.ProcLine;
        p.OnExit := @Ui.ProcExit;
        if K = svSSH then
        begin
          conf := SshdConfig(cfg, err);
          if conf = '' then
          begin
            p.Free;
            MsgError('SSH server', err);
            Exit;
          end;
          if not p.Start(['/usr/sbin/sshd', '-D', '-e', '-f', conf], [], HomeDir, False, err) then
          begin
            p.Free;
            MsgError('SSH server', err);
            Exit;
          end;
          ServerLog('SSH/SFTP server: key authentication only (' + HomeDir + '/.ssh/authorized_keys), user "' + UserName + '"');
        end
        else if not p.Start(['iperf3', '-s', '-p', IntToStr(cfg.Port)], [], HomeDir, False, err) then
        begin
          p.Free;
          MsgError('Iperf server', err);
          Exit;
        end;
        Slots[K].Proc := p;
      end;
  end;
  Slots[K].Running := True;
  ServerLog(ServerNames[K] + ' started on port ' + IntToStr(cfg.Port) + IfThen(K in [svTFTP, svFTP, svHTTP], ' (root: ' + root + ')', ''));
  UpdateRow(K);
end;

var
  StoppedServers: TList = nil;   { stopped servers whose connections are still closing }

function ReapServersCb(data: gpointer): gboolean; cdecl;
var
  i: Integer;
begin
  for i := StoppedServers.Count - 1 downto 0 do
    if TServer(StoppedServers[i]).Active <= 0 then
    begin
      TServer(StoppedServers[i]).Free;
      StoppedServers.Delete(i);
    end;
  Result := StoppedServers.Count > 0;
end;

procedure StopServer(K: TServerKind);
begin
  if not Slots[K].Running then Exit;
  if Slots[K].Tcp <> nil then
  begin
    Slots[K].Tcp.StopServer;
    { a connection thread still using the server object: free it later }
    if Slots[K].Tcp.Active > 0 then
    begin
      if StoppedServers = nil then StoppedServers := TList.Create;
      StoppedServers.Add(Slots[K].Tcp);
      if StoppedServers.Count = 1 then g_timeout_add(500, @ReapServersCb, nil);
      Slots[K].Tcp := nil;
    end
    else
      FreeAndNil(Slots[K].Tcp);
  end;
  if Slots[K].Tftp <> nil then
  begin
    Slots[K].Tftp.Terminate;
    Slots[K].Tftp.WaitFor;
    FreeAndNil(Slots[K].Tftp);
    fpClose(Slots[K].TftpFd);
    Slots[K].TftpFd := -1;
  end;
  if Slots[K].Proc <> nil then
  begin
    Slots[K].Proc.OnExit := nil;
    Slots[K].Proc.OnLine := nil;
    FreeAndNil(Slots[K].Proc);
  end;
  Slots[K].Running := False;
  ServerLog(ServerNames[K] + ' stopped');
  UpdateRow(K);
end;

procedure TServersUi.ProcLine(Sender: TChildProcess; const Line: string; IsErr: Boolean);
begin
  ServerLog(ServerNames[TServerKind(Sender.Tag)] + ': ' + Line);
end;

procedure TServersUi.ProcExit(Sender: TChildProcess; Status: Integer);
var
  k: TServerKind;
begin
  k := TServerKind(Sender.Tag);
  ServerLog(ServerNames[k] + ' exited (code ' + IntToStr(Status) + ')');
  Slots[k].Running := False;
  { the process object is released later, outside of its own callback }
  if Slots[k].Proc = Sender then
  begin
    Sender.OnLine := nil;
    Sender.OnExit := nil;
    FreeLater(Sender);
    Slots[k].Proc := nil;
  end;
  UpdateRow(k);
end;

function LogTimerCb(data: gpointer): gboolean; cdecl;
var
  lines: TStringList;
  i: Integer;
begin
  Result := True;
  if Ui = nil then Exit(False);
  lines := TStringList.Create;
  try
    LogLock.Enter;
    try
      lines.Assign(LogQueue);
      LogQueue.Clear;
    finally
      LogLock.Leave;
    end;
    if Ui.Log <> nil then
      for i := 0 to lines.Count - 1 do
        TextViewAppend(Ui.Log, lines[i] + #10);
  finally
    lines.Free;
  end;
end;

function SettingsDialog(K: TServerKind): Boolean;
var
  d, area, grid, port, root, bind, user, pass, anon, ro: Pointer;
  r: Integer;
  dir: string;
begin
  Result := False;
  d := gtk_dialog_new_with_buttons(PChar(ServerNames[K] + ' settings'), Ui.Win, GTK_DIALOG_MODAL or GTK_DIALOG_DESTROY_WITH_PARENT,
    '_Cancel', GTK_RESPONSE_CANCEL, '_OK', GTK_RESPONSE_OK, nil);
  area := gtk_dialog_get_content_area(d);
  grid := gtk_grid_new;
  gtk_grid_set_row_spacing(grid, 8);
  gtk_grid_set_column_spacing(grid, 8);
  SetMargins(grid, 12);
  r := 0;
  gtk_grid_attach(grid, NewLabel('Port', 1), 0, r, 1, 1);
  port := gtk_spin_button_new_with_range(1, 65535, 1);
  gtk_spin_button_set_value(port, Slots[K].Cfg.Port);
  gtk_grid_attach(grid, port, 1, r, 1, 1);
  Inc(r);
  gtk_grid_attach(grid, NewLabel('Listen on', 1), 0, r, 1, 1);
  bind := gtk_combo_box_text_new;
  gtk_combo_box_text_append(bind, '0.0.0.0', 'All network interfaces');
  gtk_combo_box_text_append(bind, '127.0.0.1', 'This computer only (127.0.0.1)');
  if not gtk_combo_box_set_active_id(bind, PChar(Slots[K].Cfg.Bind)) then gtk_combo_box_set_active(bind, 0);
  gtk_grid_attach(grid, bind, 1, r, 1, 1);
  Inc(r);
  root := nil;
  user := nil;
  pass := nil;
  anon := nil;
  ro := nil;
  if K in [svTFTP, svFTP, svHTTP] then
  begin
    gtk_grid_attach(grid, NewLabel('Root folder', 1), 0, r, 1, 1);
    root := gtk_entry_new;
    gtk_entry_set_width_chars(root, 34);
    SetEntryText(root, Slots[K].Cfg.Root);
    gtk_grid_attach(grid, root, 1, r, 1, 1);
    Inc(r);
  end;
  if K = svFTP then
  begin
    gtk_grid_attach(grid, NewLabel('User name', 1), 0, r, 1, 1);
    user := gtk_entry_new;
    SetEntryText(user, Slots[K].Cfg.User);
    gtk_grid_attach(grid, user, 1, r, 1, 1);
    Inc(r);
    gtk_grid_attach(grid, NewLabel('Password', 1), 0, r, 1, 1);
    pass := gtk_entry_new;
    gtk_entry_set_visibility(pass, False);
    SetEntryText(pass, Slots[K].Cfg.Pass);
    gtk_grid_attach(grid, pass, 1, r, 1, 1);
    Inc(r);
    anon := gtk_check_button_new_with_label('Allow anonymous access');
    gtk_toggle_button_set_active(anon, Slots[K].Cfg.Anonymous);
    gtk_grid_attach(grid, anon, 1, r, 1, 1);
    Inc(r);
  end;
  if K in [svTFTP, svFTP] then
  begin
    ro := gtk_check_button_new_with_label('Read-only (forbid uploads)');
    gtk_toggle_button_set_active(ro, Slots[K].Cfg.ReadOnly);
    gtk_grid_attach(grid, ro, 1, r, 1, 1);
    Inc(r);
  end;
  if K = svSSH then
  begin
    gtk_grid_attach(grid, NewMarkupLabel('<small>Users log in as <b>' + MarkupEscape(UserName) +
      '</b> with an SSH key listed in ~/.ssh/authorized_keys.</small>', 0), 0, r, 2, 1);
    Inc(r);
  end;
  gtk_container_add(area, grid);
  gtk_widget_show_all(d);
  if gtk_dialog_run(d) = GTK_RESPONSE_OK then
  begin
    gtk_spin_button_update(port);
    Slots[K].Cfg.Port := gtk_spin_button_get_value_as_int(port);
    Slots[K].Cfg.Bind := CStr(gtk_combo_box_get_active_id(bind));
    if root <> nil then
    begin
      dir := Trim(EntryText(root));
      if dir <> '' then Slots[K].Cfg.Root := dir;
    end;
    if user <> nil then Slots[K].Cfg.User := Trim(EntryText(user));
    if pass <> nil then Slots[K].Cfg.Pass := EntryText(pass);
    if anon <> nil then Slots[K].Cfg.Anonymous := gtk_toggle_button_get_active(anon);
    if ro <> nil then Slots[K].Cfg.ReadOnly := gtk_toggle_button_get_active(ro);
    SaveServerConfig;
    Result := True;
  end;
  gtk_widget_destroy(d);
end;

procedure BStart(b: Pointer; data: gpointer); cdecl;
begin
  StartServer(TServerKind(PtrInt(data)));
end;

procedure BStop(b: Pointer; data: gpointer); cdecl;
begin
  StopServer(TServerKind(PtrInt(data)));
end;

procedure BSettings(b: Pointer; data: gpointer); cdecl;
var
  k: TServerKind;
  wasRunning: Boolean;
begin
  k := TServerKind(PtrInt(data));
  wasRunning := Slots[k].Running;
  if SettingsDialog(k) and wasRunning then
  begin
    StopServer(k);
    StartServer(k);
  end;
  UpdateRow(k);
end;

function WinDelete(w: Pointer; ev: Pointer; data: gpointer): gboolean; cdecl;
begin
  { hide instead of destroying: the servers keep running }
  gtk_widget_hide(w);
  Result := True;
end;

procedure ShowServersWindow;
var
  vbox, grid, b, lbl, scroll, img: Pointer;
  k: TServerKind;
  r: Integer;
begin
  LoadServerConfig;
  if Ui = nil then
  begin
    Ui := TServersUi.Create;
    Ui.Win := gtk_window_new(GTK_WINDOW_TOPLEVEL);
    gtk_window_set_title(Ui.Win, 'LinXterm servers');
    gtk_window_set_default_size(Ui.Win, 640, 520);
    gtk_window_set_icon(Ui.Win, IconPixbuf('network-server', 64));
    gtk_window_set_transient_for(Ui.Win, MainWindowWidget);
    AddClass(Ui.Win, 'lx-main');
    vbox := gtk_box_new(GTK_ORIENTATION_VERTICAL, 8);
    SetMargins(vbox, 12);
    grid := gtk_grid_new;
    gtk_grid_set_row_spacing(grid, 6);
    gtk_grid_set_column_spacing(grid, 10);
    r := 0;
    for k := Low(TServerKind) to High(TServerKind) do
    begin
      gtk_grid_attach(grid, NewIcon(ServerIcons[k], 24), 0, r, 1, 1);
      lbl := NewMarkupLabel('<b>' + ServerNames[k] + '</b>', 0);
      gtk_widget_set_size_request(lbl, 150, -1);
      gtk_grid_attach(grid, lbl, 1, r, 1, 1);
      img := gtk_image_new_from_pixbuf(IconPixbuf('lx-cancel', 16));
      Slots[k].Dot := img;
      gtk_grid_attach(grid, img, 2, r, 1, 1);
      Slots[k].StatusLbl := NewLabel('', 0);
      gtk_widget_set_hexpand(Slots[k].StatusLbl, True);
      gtk_grid_attach(grid, Slots[k].StatusLbl, 3, r, 1, 1);
      b := NewIconButton('media-playback-start', '', 'Start', 16);
      Connect(b, 'clicked', @BStart, Pointer(PtrInt(Ord(k))));
      Slots[k].StartBtn := b;
      gtk_grid_attach(grid, b, 4, r, 1, 1);
      b := NewIconButton('media-playback-stop', '', 'Stop', 16);
      Connect(b, 'clicked', @BStop, Pointer(PtrInt(Ord(k))));
      Slots[k].StopBtn := b;
      gtk_grid_attach(grid, b, 5, r, 1, 1);
      b := NewIconButton('preferences-system', '', 'Settings', 16);
      Connect(b, 'clicked', @BSettings, Pointer(PtrInt(Ord(k))));
      gtk_grid_attach(grid, b, 6, r, 1, 1);
      Inc(r);
    end;
    gtk_box_pack_start(vbox, grid, False, False, 0);
    gtk_box_pack_start(vbox, NewMarkupLabel('<b>Activity log</b>', 0), False, False, 4);
    Ui.Log := gtk_text_view_new;
    gtk_text_view_set_editable(Ui.Log, False);
    gtk_text_view_set_monospace(Ui.Log, True);
    scroll := NewScrolled(Ui.Log);
    gtk_box_pack_start(vbox, scroll, True, True, 0);
    gtk_container_add(Ui.Win, vbox);
    Connect(Ui.Win, 'delete-event', @WinDelete, nil);
    Ui.Timer := g_timeout_add(300, @LogTimerCb, nil);
  end;
  for k := Low(TServerKind) to High(TServerKind) do UpdateRow(k);
  gtk_widget_show_all(Ui.Win);
  gtk_window_present(Ui.Win);
end;

function TestHook(const Cmd, Arg: string): Boolean;
var
  k: TServerKind;
begin
  Result := False;
  if (Cmd <> 'srvstart') and (Cmd <> 'srvstop') and (Cmd <> 'srvcfg') then Exit;
  Result := True;
  LoadServerConfig;
  for k := Low(TServerKind) to High(TServerKind) do
    if ServerIds[k] = Copy(Arg, 1, Pos(' ', Arg + ' ') - 1) then
    begin
      if Cmd = 'srvstart' then StartServer(k)
      else if Cmd = 'srvstop' then StopServer(k)
      else
      begin
        { srvcfg <id> <port> <root> <password> }
        Slots[k].Cfg.Port := StrToIntDef(ExtractWord(2, Arg, [' ']), Slots[k].Cfg.Port);
        if ExtractWord(3, Arg, [' ']) <> '' then Slots[k].Cfg.Root := ExtractWord(3, Arg, [' ']);
        Slots[k].Cfg.Pass := ExtractWord(4, Arg, [' ']);
        Slots[k].Cfg.ReadOnly := False;
      end;
    end;
end;

procedure StopAll;
var
  k: TServerKind;
begin
  for k := Low(TServerKind) to High(TServerKind) do
    if Slots[k].Running then StopServer(k);
end;

initialization
  LogLock := TCriticalSection.Create;
  LogQueue := TStringList.Create;
  ShowServersProc := @ShowServersWindow;
  SetLength(TestHooks, Length(TestHooks) + 1);
  TestHooks[High(TestHooks)] := @TestHook;
  RegisterShutdown(@StopAll);

end.

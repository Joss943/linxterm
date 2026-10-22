{ LinXterm - FTP client (RFC 959 / 2428 / 3659): passive (EPSV/PASV) and
  active (EPRT/PORT) data connections, MLSD or LIST directory listings.
  Blocking API used from a worker thread. }
unit lxftp;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, BaseUnix, Unix, Sockets, lxnet;

type
  EFtpError = class(Exception);

  TFtpEntry = record
    Name: string;
    IsDir, IsLink: Boolean;
    Size: Int64;
    MTime: Int64;
    Mode: LongWord;
    Owner, Group: string;
  end;
  TFtpEntries = array of TFtpEntry;

  TFtpProgress = function(Done, Total: Int64): Boolean of object;

  TFtpClient = class
  private
    FCtl: cint;
    FBuf: string;
    FHasMlsd, FHasUtf8, FHasSize: Boolean;
    FPassive: Boolean;
    FHost: string;
    FLastReply: string;
    function ReadLine: string;
    function ReadReply(out Text: string): Integer;
    function Cmd(const C: string; out Text: string): Integer;
    procedure CmdExpect(const C: string; Ok: Integer);
    function OpenData(const C: string; out Listener: cint): cint;
    function AcceptData(Listener: cint): cint;
    function ParseList(const Data: string; Mlsd: Boolean): TFtpEntries;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Connect(const Host: string; Port: Integer; const User, Pass: string; Passive: Boolean);
    procedure Disconnect;
    function Pwd: string;
    procedure Cwd(const Dir: string);
    function List(const Dir: string): TFtpEntries;
    procedure MkDir(const Dir: string);
    procedure RmDir(const Dir: string);
    procedure Delete(const F: string);
    procedure Rename(const A, B: string);
    procedure Chmod(const F: string; Mode: LongWord);
    function Size(const F: string): Int64;
    procedure Retrieve(const Remote, Local: string; Progress: TFtpProgress);
    procedure Store(const Local, Remote: string; Progress: TFtpProgress);
    function Connected: Boolean;
    property LastReply: string read FLastReply;
  end;

implementation

uses
  DateUtils, StrUtils;

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

constructor TFtpClient.Create;
begin
  inherited Create;
  FCtl := -1;
end;

destructor TFtpClient.Destroy;
begin
  Disconnect;
  inherited Destroy;
end;

function TFtpClient.Connected: Boolean;
begin
  Result := FCtl >= 0;
end;

function TFtpClient.ReadLine: string;
var
  p, n: Integer;
  buf: array[0..4095] of Char;
begin
  while True do
  begin
    p := Pos(#10, FBuf);
    if p > 0 then
    begin
      Result := Copy(FBuf, 1, p - 1);
      System.Delete(FBuf, 1, p);
      if (Result <> '') and (Result[Length(Result)] = #13) then
        System.Delete(Result, Length(Result), 1);
      Exit;
    end;
    n := fpRecv(FCtl, @buf[0], SizeOf(buf), 0);
    if n <= 0 then
    begin
      if (n < 0) and (fpGetErrno = ESysEINTR) then Continue;
      Disconnect;
      raise EFtpError.Create('Connection closed by the FTP server');
    end;
    FBuf := FBuf + BufToStr(buf, n);
  end;
end;

function TFtpClient.ReadReply(out Text: string): Integer;
var
  line, code: string;
begin
  line := ReadLine;
  Text := line;
  if (Length(line) < 3) then raise EFtpError.Create('Invalid FTP reply: ' + line);
  code := Copy(line, 1, 3);
  Result := StrToIntDef(code, 0);
  if (Length(line) > 3) and (line[4] = '-') then
    repeat
      line := ReadLine;
      Text := Text + #10 + line;
    until (Length(line) >= 4) and (Copy(line, 1, 3) = code) and (line[4] = ' ');
  FLastReply := Text;
end;

function TFtpClient.Cmd(const C: string; out Text: string): Integer;
begin
  if FCtl < 0 then raise EFtpError.Create('Not connected');
  { a line break inside a file name would inject another command }
  if (Pos(#10, C) > 0) or (Pos(#13, C) > 0) then
    raise EFtpError.Create('Invalid character in the file name');
  if not SendAll(FCtl, C + #13#10) then
  begin
    Disconnect;
    raise EFtpError.Create('Connection lost');
  end;
  Result := ReadReply(Text);
end;

procedure TFtpClient.CmdExpect(const C: string; Ok: Integer);
var
  t: string;
  r: Integer;
begin
  r := Cmd(C, t);
  if (r div 100) <> (Ok div 100) then
    raise EFtpError.Create(Trim(Copy(t, 5, MaxInt)) + ' (' + IntToStr(r) + ')');
end;

procedure TFtpClient.Connect(const Host: string; Port: Integer; const User, Pass: string; Passive: Boolean);
var
  err, t, u: string;
  r: Integer;
begin
  Disconnect;
  FHost := Host;
  FPassive := Passive;
  FCtl := TcpConnect(Host, Port, 15000, err);
  if FCtl < 0 then raise EFtpError.Create(err);
  SetSocketTimeouts(FCtl, 60);
  FBuf := '';
  r := ReadReply(t);
  if r <> 220 then
  begin
    Disconnect;
    raise EFtpError.Create('FTP server refused the connection: ' + t);
  end;
  u := User;
  if u = '' then u := 'anonymous';
  r := Cmd('USER ' + u, t);
  if r = 331 then
  begin
    if (Pass = '') and (u = 'anonymous') then
      r := Cmd('PASS anonymous@', t)
    else
      r := Cmd('PASS ' + Pass, t);
  end;
  if r <> 230 then
  begin
    Disconnect;
    raise EFtpError.Create('Login incorrect: ' + Trim(Copy(t, 5, MaxInt)));
  end;
  r := Cmd('FEAT', t);
  if r = 211 then
  begin
    FHasMlsd := Pos('MLST', UpperCase(t)) > 0;
    FHasUtf8 := Pos('UTF8', UpperCase(t)) > 0;
    FHasSize := Pos('SIZE', UpperCase(t)) > 0;
  end;
  if FHasUtf8 then Cmd('OPTS UTF8 ON', t);
  CmdExpect('TYPE I', 200);
end;

procedure TFtpClient.Disconnect;
begin
  if FCtl >= 0 then
  begin
    SendAll(FCtl, 'QUIT'#13#10);
    fpShutdown(FCtl, 2);
    fpClose(FCtl);
  end;
  FCtl := -1;
  FBuf := '';
end;

function TFtpClient.Pwd: string;
var
  t: string;
  a, b: Integer;
begin
  if Cmd('PWD', t) <> 257 then raise EFtpError.Create(t);
  a := Pos('"', t);
  b := PosEx('"', t, a + 1);
  { "" inside the path is an escaped quote }
  while (b > 0) and (b < Length(t)) and (t[b + 1] = '"') do
    b := PosEx('"', t, b + 2);
  if (a > 0) and (b > a) then
    Result := StringReplace(Copy(t, a + 1, b - a - 1), '""', '"', [rfReplaceAll])
  else
    Result := '/';
end;

procedure TFtpClient.Cwd(const Dir: string);
begin
  CmdExpect('CWD ' + Dir, 250);
end;

function TFtpClient.OpenData(const C: string; out Listener: cint): cint;
var
  t, peer, err, addr: string;
  r, a, b, port, lport: Integer;
  nums: array of Integer;
  parts: TStringArray;
  i: Integer;
begin
  Result := -1;
  Listener := -1;
  peer := PeerAddress(FCtl, port);
  if FPassive then
  begin
    r := Cmd('EPSV', t);
    if r = 229 then
    begin
      a := Pos('(', t);
      b := Pos(')', t);
      parts := SplitString(Copy(t, a + 1, b - a - 1), '|');
      port := 0;
      for i := 0 to High(parts) do
        if parts[i] <> '' then port := StrToIntDef(parts[i], 0);
    end
    else
    begin
      r := Cmd('PASV', t);
      if r <> 227 then raise EFtpError.Create('Passive mode refused: ' + t);
      a := Pos('(', t);
      b := Pos(')', t);
      if (a = 0) or (b = 0) then
      begin
        { some servers omit the parenthesis }
        a := Length(t);
        while (a > 0) and (t[a] in ['0'..'9', ',']) do Dec(a);
        b := Length(t) + 1;
      end;
      parts := SplitString(Copy(t, a + 1, b - a - 1), ',');
      SetLength(nums, Length(parts));
      for i := 0 to High(parts) do nums[i] := StrToIntDef(Trim(parts[i]), 0);
      if Length(nums) < 6 then raise EFtpError.Create('Invalid PASV answer: ' + t);
      port := nums[4] * 256 + nums[5];
    end;
    if port <= 0 then raise EFtpError.Create('Invalid passive port');
    { always connect to the control connection peer (NAT friendly) }
    Result := TcpConnect(peer, port, 15000, err);
    if Result < 0 then raise EFtpError.Create('Data connection failed: ' + err);
    SetSocketTimeouts(Result, 60);
    r := Cmd(C, t);
    if (r <> 125) and (r <> 150) then
    begin
      fpClose(Result);
      Result := -1;
      raise EFtpError.Create(Trim(Copy(t, 5, MaxInt)) + ' (' + IntToStr(r) + ')');
    end;
  end
  else
  begin
    addr := LocalAddress(FCtl, port);
    Listener := TcpListen(addr, 0, err);
    if Listener < 0 then raise EFtpError.Create('Cannot open a local data port: ' + err);
    LocalAddress(Listener, lport);
    if Pos(':', addr) > 0 then
      r := Cmd('EPRT |2|' + addr + '|' + IntToStr(lport) + '|', t)
    else
      r := Cmd('PORT ' + StringReplace(addr, '.', ',', [rfReplaceAll]) + ',' + IntToStr(lport div 256) + ',' +
        IntToStr(lport mod 256), t);
    if r <> 200 then
    begin
      fpClose(Listener);
      Listener := -1;
      raise EFtpError.Create('Active mode refused: ' + t);
    end;
    r := Cmd(C, t);
    if (r <> 125) and (r <> 150) then
    begin
      fpClose(Listener);
      Listener := -1;
      raise EFtpError.Create(Trim(Copy(t, 5, MaxInt)) + ' (' + IntToStr(r) + ')');
    end;
    Result := AcceptData(Listener);
  end;
end;

function TFtpClient.AcceptData(Listener: cint): cint;
begin
  if WaitFd(Listener, False, 20000) <= 0 then
  begin
    fpClose(Listener);
    raise EFtpError.Create('The server did not open the data connection (active mode)');
  end;
  Result := fpAccept(Listener, nil, nil);
  fpClose(Listener);
  if Result < 0 then raise EFtpError.Create('Data connection failed');
  SetSocketTimeouts(Result, 60);
end;

function MonthNum(const M: string): Integer;
const
  Months = 'janfebmaraprmayjunjulaugsepoctnovdec';
begin
  Result := (Pos(LowerCase(Copy(M, 1, 3)), Months) + 2) div 3;
end;

function ParseUnixMode(const S: string): LongWord;
var
  i: Integer;
begin
  Result := 0;
  for i := 2 to 10 do
    if (i <= Length(S)) and (S[i] <> '-') then
      Result := Result or (1 shl (10 - i));
end;

function TFtpClient.ParseList(const Data: string; Mlsd: Boolean): TFtpEntries;
var
  lines, fields, facts: TStringArray;
  line, l, nm, typ, key, val, rest: string;
  n, i, j, p, y, mo, d, hh, mi: Integer;
  e: TFtpEntry;
  now_: TDateTime;
begin
  Result := nil;
  n := 0;
  lines := SplitString(StringReplace(Data, #13, '', [rfReplaceAll]), #10);
  now_ := Now;
  for line in lines do
  begin
    if Trim(line) = '' then Continue;
    FillChar(e, SizeOf(e), 0);
    e.Name := '';
    e.Owner := '';
    e.Group := '';
    if Mlsd then
    begin
      p := Pos(' ', line);
      if p = 0 then Continue;
      nm := Copy(line, p + 1, MaxInt);
      facts := SplitString(Copy(line, 1, p - 1), ';');
      typ := '';
      for j := 0 to High(facts) do
      begin
        i := Pos('=', facts[j]);
        if i = 0 then Continue;
        key := LowerCase(Copy(facts[j], 1, i - 1));
        val := Copy(facts[j], i + 1, MaxInt);
        if key = 'type' then typ := LowerCase(val)
        else if key = 'size' then e.Size := StrToInt64Def(val, 0)
        else if key = 'modify' then
        begin
          if Length(val) >= 14 then
            try
              e.MTime := DateTimeToUnix(EncodeDateTime(StrToInt(Copy(val, 1, 4)), StrToInt(Copy(val, 5, 2)),
                StrToInt(Copy(val, 7, 2)), StrToInt(Copy(val, 9, 2)), StrToInt(Copy(val, 11, 2)),
                StrToInt(Copy(val, 13, 2)), 0));
            except
              e.MTime := 0;
            end;
        end
        else if key = 'unix.mode' then e.Mode := StrToIntDef('&' + val, 0)
        else if (key = 'unix.owner') or (key = 'unix.ownername') then e.Owner := val
        else if (key = 'unix.group') or (key = 'unix.groupname') then e.Group := val;
      end;
      if (typ = 'cdir') or (typ = 'pdir') then Continue;
      e.IsDir := (typ = 'dir') or (Pos('os.unix=slink', typ) = 1);
      e.IsLink := Pos('slink', typ) > 0;
      e.Name := nm;
    end
    else
    begin
      l := line;
      if (Length(l) > 10) and (l[1] in ['d', '-', 'l', 'c', 'b', 'p', 's']) and (l[2] in ['r', '-']) then
      begin
        { unix style: perms links owner group size month day time/year name }
        fields := SplitString(DelSpace1(l), ' ');
        if Length(fields) < 9 then Continue;
        e.IsDir := l[1] = 'd';
        e.IsLink := l[1] = 'l';
        e.Mode := ParseUnixMode(fields[0]);
        e.Owner := fields[2];
        e.Group := fields[3];
        e.Size := StrToInt64Def(fields[4], 0);
        mo := MonthNum(fields[5]);
        d := StrToIntDef(fields[6], 1);
        if Pos(':', fields[7]) > 0 then
        begin
          y := YearOf(now_);
          hh := StrToIntDef(Copy(fields[7], 1, Pos(':', fields[7]) - 1), 0);
          mi := StrToIntDef(Copy(fields[7], Pos(':', fields[7]) + 1, 2), 0);
          if (mo > MonthOf(now_)) then Dec(y);
        end
        else
        begin
          y := StrToIntDef(fields[7], 1970);
          hh := 0;
          mi := 0;
        end;
        if (mo >= 1) and (mo <= 12) and (d >= 1) and (d <= 31) then
          try
            e.MTime := DateTimeToUnix(EncodeDateTime(y, mo, d, hh, mi, 0, 0)) - Round(GetLocalTimeOffset * 60);
          except
            e.MTime := 0;
          end;
        { the name is everything after the 8th field (it may contain spaces) }
        rest := l;
        for j := 1 to 8 do
        begin
          rest := TrimLeft(rest);
          p := Pos(' ', rest);
          if p = 0 then
          begin
            rest := '';
            Break;
          end;
          rest := Copy(rest, p + 1, MaxInt);
        end;
        nm := TrimLeft(rest);
        if e.IsLink and (Pos(' -> ', nm) > 0) then
          nm := Copy(nm, 1, Pos(' -> ', nm) - 1);
        e.Name := nm;
      end
      else if (Length(l) > 17) and (l[3] = '-') and (l[6] = '-') then
      begin
        { DOS / IIS style: 01-15-23  10:30AM <DIR> name }
        fields := SplitString(DelSpace1(l), ' ');
        if Length(fields) < 4 then Continue;
        e.IsDir := UpperCase(fields[2]) = '<DIR>';
        if not e.IsDir then e.Size := StrToInt64Def(fields[2], 0);
        rest := l;
        for j := 1 to 3 do
        begin
          rest := TrimLeft(rest);
          p := Pos(' ', rest);
          if p = 0 then Break;
          rest := Copy(rest, p + 1, MaxInt);
        end;
        e.Name := TrimLeft(rest);
        e.Mode := 0;
      end
      else
        Continue;
    end;
    if (e.Name = '') or (e.Name = '.') or (e.Name = '..') then Continue;
    if n >= Length(Result) then SetLength(Result, n * 2 + 16);
    Result[n] := e;
    Inc(n);
  end;
  SetLength(Result, n);
end;

function ReadAllFrom(Fd: cint): string;
var
  buf: array[0..65535] of Char;
  n: Integer;
begin
  Result := '';
  repeat
    n := fpRecv(Fd, @buf[0], SizeOf(buf), 0);
    if (n < 0) and (fpGetErrno = ESysEINTR) then Continue;
    if n > 0 then Result := Result + BufToStr(buf, n);
  until n <= 0;
end;

function TFtpClient.List(const Dir: string): TFtpEntries;
var
  data, t: string;
  fd, lst: cint;
  r: Integer;
  mlsd: Boolean;
begin
  mlsd := FHasMlsd;
  if mlsd then
    fd := OpenData('MLSD ' + Dir, lst)
  else
  begin
    { LIST does not accept paths with spaces everywhere: change directory first }
    Cwd(Dir);
    fd := OpenData('LIST -a', lst);
  end;
  try
    data := ReadAllFrom(fd);
  finally
    fpClose(fd);
  end;
  r := ReadReply(t);
  if (r div 100) <> 2 then
    raise EFtpError.Create(Trim(Copy(t, 5, MaxInt)));
  Result := ParseList(data, mlsd);
end;

procedure TFtpClient.MkDir(const Dir: string);
begin
  CmdExpect('MKD ' + Dir, 257);
end;

procedure TFtpClient.RmDir(const Dir: string);
begin
  CmdExpect('RMD ' + Dir, 250);
end;

procedure TFtpClient.Delete(const F: string);
begin
  CmdExpect('DELE ' + F, 250);
end;

procedure TFtpClient.Rename(const A, B: string);
begin
  CmdExpect('RNFR ' + A, 350);
  CmdExpect('RNTO ' + B, 250);
end;

procedure TFtpClient.Chmod(const F: string; Mode: LongWord);
begin
  CmdExpect('SITE CHMOD ' + OctStr(Mode and &7777, 3) + ' ' + F, 200);
end;

function TFtpClient.Size(const F: string): Int64;
var
  t: string;
begin
  Result := -1;
  if Cmd('SIZE ' + F, t) = 213 then
    Result := StrToInt64Def(Trim(Copy(t, 5, MaxInt)), -1);
end;

procedure TFtpClient.Retrieve(const Remote, Local: string; Progress: TFtpProgress);
var
  fd, lfd, lst: cint;
  total, done: Int64;
  buf: array[0..65535] of Char;
  n, r: Integer;
  t: string;
  cancelled: Boolean;
begin
  total := Size(Remote);
  lfd := fpOpen(Local, O_WRONLY or O_CREAT or O_TRUNC, &644);
  if lfd < 0 then raise EFtpError.Create('Cannot create ' + Local + ': ' + SysErrorMessage(fpGetErrno));
  cancelled := False;
  done := 0;
  try
    fd := OpenData('RETR ' + Remote, lst);
    try
      repeat
        n := fpRecv(fd, @buf[0], SizeOf(buf), 0);
        if (n < 0) and (fpGetErrno = ESysEINTR) then Continue;
        if n > 0 then
        begin
          if fpWrite(lfd, buf[0], n) <> n then raise EFtpError.Create('Write error on ' + Local);
          Inc(done, n);
          if Assigned(Progress) and not Progress(done, total) then
          begin
            cancelled := True;
            Break;
          end;
        end;
      until n <= 0;
    finally
      fpClose(fd);
    end;
    if cancelled then
    begin
      Cmd('ABOR', t);
      { drain the transfer status replies }
      Disconnect;
    end
    else
    begin
      r := ReadReply(t);
      if (r div 100) <> 2 then raise EFtpError.Create(Trim(Copy(t, 5, MaxInt)));
    end;
  finally
    fpClose(lfd);
  end;
  if cancelled then
  begin
    DeleteFile(Local);
    raise EFtpError.Create('Transfer cancelled');
  end;
end;

procedure TFtpClient.Store(const Local, Remote: string; Progress: TFtpProgress);
var
  fd, lfd, lst: cint;
  st: Stat;
  total, done: Int64;
  buf: array[0..65535] of Char;
  n, r: Integer;
  t, chunk: string;
  cancelled: Boolean;
begin
  lfd := fpOpen(Local, O_RDONLY);
  if lfd < 0 then raise EFtpError.Create('Cannot open ' + Local + ': ' + SysErrorMessage(fpGetErrno));
  fpFStat(lfd, st);
  total := st.st_size;
  done := 0;
  cancelled := False;
  try
    fd := OpenData('STOR ' + Remote, lst);
    try
      repeat
        n := fpRead(lfd, buf[0], SizeOf(buf));
        if n > 0 then
        begin
          SetString(chunk, PChar(@buf[0]), n);
          if not SendAll(fd, chunk) then raise EFtpError.Create('Data connection lost');
          Inc(done, n);
          if Assigned(Progress) and not Progress(done, total) then
          begin
            cancelled := True;
            Break;
          end;
        end;
      until n <= 0;
    finally
      fpClose(fd);
    end;
    r := ReadReply(t);
    if not cancelled and ((r div 100) <> 2) then raise EFtpError.Create(Trim(Copy(t, 5, MaxInt)));
  finally
    fpClose(lfd);
  end;
  if cancelled then
  begin
    try
      Delete(Remote);
    except
    end;
    raise EFtpError.Create('Transfer cancelled');
  end;
end;

end.

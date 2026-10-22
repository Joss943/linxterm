{ LinXterm - Telnet client (RFC 854 / 855 / 857 / 858 / 1073 / 1091).
  Runs inside a LinXterm terminal tab.
  usage: lxtelnet <host> [port] [user]
  LINXTERM_PASSFILE: optional file holding the password used for auto-login. }
program lxtelnet;

{$mode objfpc}{$H+}
{$packrecords C}

uses
  cthreads, SysUtils, BaseUnix, Unix, Sockets, termio;

const
  IAC = 255; DONT = 254; DO_ = 253; WONT = 252; WILL = 251; SB = 250; SE = 240;
  OPT_BINARY = 0; OPT_ECHO = 1; OPT_SGA = 3; OPT_TTYPE = 24; OPT_NAWS = 31;
  TTYPE_IS = 0; TTYPE_SEND = 1;

type
  PAddrInfo = ^TAddrInfo;
  TAddrInfo = record
    ai_flags: cint;
    ai_family: cint;
    ai_socktype: cint;
    ai_protocol: cint;
    ai_addrlen: TSocklen;
    ai_addr: PSockAddr;
    ai_canonname: PChar;
    ai_next: PAddrInfo;
  end;

function getaddrinfo(node, service: PChar; hints: PAddrInfo; res: Pointer): cint; cdecl; external 'c';
procedure freeaddrinfo(res: PAddrInfo); cdecl; external 'c';
function gai_strerror(code: cint): PChar; cdecl; external 'c';

var
  Sock: cint = -1;
  SavedTios: Termios;
  RawSet: Boolean = False;
  WinchFlag: Boolean = False;
  RemoteEcho: Boolean = False;
  LocalBinary: Boolean = False;
  NawsEnabled: Boolean = False;
  HisOpts, MyOpts: array[0..255] of Boolean;
  AutoUser, AutoPass: string;
  UserSent, PassSent: Boolean;
  Recent: string;

procedure Out(const S: string);
var
  t: string;
begin
  t := S;
  { outside raw mode the tty already turns LF into CR LF }
  if not RawSet then t := StringReplace(t, #13#10, #10, [rfReplaceAll]);
  if t <> '' then fpWrite(1, t[1], Length(t));
end;

procedure RestoreTty;
begin
  if RawSet then
  begin
    TCSetAttr(0, TCSANOW, SavedTios);
    RawSet := False;
  end;
end;

procedure SetRaw;
var
  t: Termios;
begin
  if TCGetAttr(0, SavedTios) = 0 then
  begin
    t := SavedTios;
    CFMakeRaw(t);
    TCSetAttr(0, TCSANOW, t);
    RawSet := True;
  end;
end;

procedure SendRaw(const Data: string);
var
  p, n: Integer;
begin
  p := 1;
  while p <= Length(Data) do
  begin
    n := fpSend(Sock, @Data[p], Length(Data) - p + 1, 0);
    if n <= 0 then
    begin
      if fpGetErrno = ESysEINTR then Continue;
      Exit;
    end;
    Inc(p, n);
  end;
end;

procedure SendCmd(Cmd, Opt: Byte);
begin
  SendRaw(Chr(IAC) + Chr(Cmd) + Chr(Opt));
end;

procedure SendNaws;
var
  ws: TWinSize;
  s: string;
  procedure AddByte(B: Byte);
  begin
    s := s + Chr(B);
    if B = IAC then s := s + Chr(IAC);
  end;
begin
  if not NawsEnabled then Exit;
  FillChar(ws, SizeOf(ws), 0);
  if fpIOCtl(0, TIOCGWINSZ, @ws) <> 0 then Exit;
  s := Chr(IAC) + Chr(SB) + Chr(OPT_NAWS);
  AddByte(ws.ws_col shr 8);
  AddByte(ws.ws_col and $FF);
  AddByte(ws.ws_row shr 8);
  AddByte(ws.ws_row and $FF);
  s := s + Chr(IAC) + Chr(SE);
  SendRaw(s);
end;

procedure HandleOption(Cmd, Opt: Byte);
begin
  case Cmd of
    WILL:
      begin
        if Opt in [OPT_ECHO, OPT_SGA, OPT_BINARY] then
        begin
          if not HisOpts[Opt] then
          begin
            HisOpts[Opt] := True;
            SendCmd(DO_, Opt);
          end;
          if Opt = OPT_ECHO then RemoteEcho := True;
        end
        else
          SendCmd(DONT, Opt);
      end;
    WONT:
      begin
        if HisOpts[Opt] then
        begin
          HisOpts[Opt] := False;
          SendCmd(DONT, Opt);
        end;
        if Opt = OPT_ECHO then RemoteEcho := False;
      end;
    DO_:
      begin
        if Opt in [OPT_TTYPE, OPT_NAWS, OPT_SGA, OPT_BINARY] then
        begin
          if not MyOpts[Opt] then
          begin
            MyOpts[Opt] := True;
            SendCmd(WILL, Opt);
          end;
          if Opt = OPT_NAWS then
          begin
            NawsEnabled := True;
            SendNaws;
          end;
          if Opt = OPT_BINARY then LocalBinary := True;
        end
        else
          SendCmd(WONT, Opt);
      end;
    DONT:
      begin
        if MyOpts[Opt] then
        begin
          MyOpts[Opt] := False;
          SendCmd(WONT, Opt);
        end;
        if Opt = OPT_NAWS then NawsEnabled := False;
        if Opt = OPT_BINARY then LocalBinary := False;
      end;
  end;
end;

procedure HandleSub(const Data: string);
begin
  if Length(Data) < 1 then Exit;
  if (Ord(Data[1]) = OPT_TTYPE) and (Length(Data) >= 2) and (Ord(Data[2]) = TTYPE_SEND) then
    SendRaw(Chr(IAC) + Chr(SB) + Chr(OPT_TTYPE) + Chr(TTYPE_IS) + 'XTERM-256COLOR' + Chr(IAC) + Chr(SE));
end;

function StripAnsi(const S: string): string;
var
  i: Integer;
  esc: Boolean;
begin
  Result := '';
  esc := False;
  for i := 1 to Length(S) do
  begin
    if esc then
    begin
      if S[i] in ['A'..'Z', 'a'..'z'] then esc := False;
      Continue;
    end;
    if S[i] = #27 then esc := True
    else if S[i] >= ' ' then Result := Result + S[i];
  end;
end;

procedure AutoLogin(const Text: string);
var
  t: string;
  function EndsWith(const Suffix: string): Boolean;
  begin
    Result := (Length(t) >= Length(Suffix)) and (Copy(t, Length(t) - Length(Suffix) + 1, MaxInt) = Suffix);
  end;
begin
  if ((AutoUser = '') or UserSent) and ((AutoPass = '') or PassSent) then Exit;
  Recent := Recent + StripAnsi(Text);
  if Length(Recent) > 300 then
    Delete(Recent, 1, Length(Recent) - 300);
  t := LowerCase(TrimRight(Recent));
  if (AutoUser <> '') and not UserSent and (EndsWith('login:') or EndsWith('username:') or
    EndsWith('user name:') or EndsWith('user:')) then
  begin
    UserSent := True;
    Recent := '';
    SendRaw(AutoUser + #13#10);
  end
  else if (AutoPass <> '') and not PassSent and EndsWith('password:') then
  begin
    PassSent := True;
    Recent := '';
    SendRaw(AutoPass + #13#10);
  end;
end;

var
  State: Integer = 0;   { 0 data, 1 IAC, 2 option cmd, 3 SB, 4 SB+IAC, 5 after CR }
  PendingCmd: Byte;
  SubBuf: string;

procedure ProcessIncoming(const Buf: string);
var
  i: Integer;
  b: Byte;
  outp: string;
begin
  outp := '';
  for i := 1 to Length(Buf) do
  begin
    b := Ord(Buf[i]);
    case State of
      0, 5:
        begin
          if b = IAC then
            State := 1
          else
          begin
            if (State = 5) and (b = 0) then
            begin
              State := 0;
              Continue;    { CR NUL -> CR }
            end;
            State := 0;
            outp := outp + Chr(b);
            if b = 13 then State := 5;
          end;
        end;
      1:
        case b of
          IAC:
            begin
              outp := outp + Chr(IAC);
              State := 0;
            end;
          WILL, WONT, DO_, DONT:
            begin
              PendingCmd := b;
              State := 2;
            end;
          SB:
            begin
              SubBuf := '';
              State := 3;
            end;
        else
          State := 0;
        end;
      2:
        begin
          HandleOption(PendingCmd, b);
          State := 0;
        end;
      3:
        if b = IAC then State := 4 else SubBuf := SubBuf + Chr(b);
      4:
        if b = SE then
        begin
          HandleSub(SubBuf);
          State := 0;
        end
        else
        begin
          if b = IAC then SubBuf := SubBuf + Chr(IAC);
          State := 3;
        end;
    end;
  end;
  if outp <> '' then
  begin
    Out(outp);
    AutoLogin(outp);
  end;
end;

procedure ProcessKeys(const Buf: string);
var
  i: Integer;
  c: Char;
  s, echo: string;
begin
  s := '';
  echo := '';
  for i := 1 to Length(Buf) do
  begin
    c := Buf[i];
    if c = #13 then
    begin
      if LocalBinary then s := s + #13 else s := s + #13#10;
      echo := echo + #13#10;
    end
    else if Ord(c) = IAC then
      s := s + Chr(IAC) + Chr(IAC)
    else
    begin
      s := s + c;
      if (c = #127) or (c = #8) then echo := echo + #8' '#8
      else if c >= ' ' then echo := echo + c;
    end;
  end;
  SendRaw(s);
  if not RemoteEcho then Out(echo);
end;

procedure WinchHandler(sig: cint); cdecl;
begin
  WinchFlag := True;
end;

function ConnectTo(const Host, Port: string; out Err: string): cint;
var
  hints: TAddrInfo;
  res, ai: PAddrInfo;
  rc, fd, so: cint;
  flags: cint;
  wfds: TFDSet;
  tv: TTimeVal;
  len: TSocklen;
begin
  Result := -1;
  Err := '';
  FillChar(hints, SizeOf(hints), 0);
  hints.ai_family := AF_UNSPEC;
  hints.ai_socktype := SOCK_STREAM;
  res := nil;
  rc := getaddrinfo(PChar(Host), PChar(Port), @hints, @res);
  if rc <> 0 then
  begin
    Err := 'Unable to resolve "' + Host + '": ' + AnsiString(gai_strerror(rc));
    Exit;
  end;
  ai := res;
  while ai <> nil do
  begin
    fd := fpSocket(ai^.ai_family, ai^.ai_socktype, ai^.ai_protocol);
    if fd >= 0 then
    begin
      flags := fpFcntl(fd, F_GETFL);
      fpFcntl(fd, F_SETFL, flags or O_NONBLOCK);
      rc := fpConnect(fd, ai^.ai_addr, ai^.ai_addrlen);
      if (rc < 0) and (fpGetErrno = ESysEINPROGRESS) then
      begin
        fpFD_ZERO(wfds);
        fpFD_SET(fd, wfds);
        tv.tv_sec := 15;
        tv.tv_usec := 0;
        rc := fpSelect(fd + 1, nil, @wfds, nil, @tv);
        if rc > 0 then
        begin
          so := 0;
          len := SizeOf(so);
          fpGetSockOpt(fd, SOL_SOCKET, SO_ERROR, @so, @len);
          if so = 0 then rc := 0 else
          begin
            Err := SysErrorMessage(so);
            rc := -1;
          end;
        end
        else
        begin
          Err := 'Connection timed out';
          rc := -1;
        end;
      end
      else if rc < 0 then
        Err := SysErrorMessage(fpGetErrno);
      if rc = 0 then
      begin
        fpFcntl(fd, F_SETFL, flags);
        Result := fd;
        Break;
      end;
      fpClose(fd);
    end;
    ai := ai^.ai_next;
  end;
  freeaddrinfo(res);
end;

var
  host, port, err, pf, buf: string;
  rfds: TFDSet;
  n, maxfd: cint;
  rbuf: array[0..16383] of Char;
  f: TextFile;
  sa: SigActionRec;
begin
  if ParamCount < 1 then
  begin
    WriteLn('usage: lxtelnet <host> [port] [user]');
    Halt(2);
  end;
  host := ParamStr(1);
  port := '23';
  if (ParamCount >= 2) and (ParamStr(2) <> '') and (ParamStr(2) <> '0') then port := ParamStr(2);
  if ParamCount >= 3 then AutoUser := ParamStr(3);
  pf := GetEnvironmentVariable('LINXTERM_PASSFILE');
  if (pf <> '') and FileExists(pf) then
  begin
    AssignFile(f, pf);
    Reset(f);
    if not Eof(f) then ReadLn(f, AutoPass);
    CloseFile(f);
    DeleteFile(pf);
  end;
  FillChar(HisOpts, SizeOf(HisOpts), 0);
  FillChar(MyOpts, SizeOf(MyOpts), 0);
  Out('Trying ' + host + ' port ' + port + '...'#13#10);
  Sock := ConnectTo(host, port, err);
  if Sock < 0 then
  begin
    Out(#27'[1;31mUnable to connect to ' + host + ':' + port + ': ' + err + #27'[0m'#13#10);
    Halt(1);
  end;
  Out('Connected to ' + host + '.'#13#10);
  FillChar(sa, SizeOf(sa), 0);
  sa.sa_handler := SigActionHandler(@WinchHandler);
  fpSigAction(SIGWINCH, @sa, nil);
  fpSignal(SIGPIPE, SignalHandler(SIG_IGN));
  SetRaw;
  try
    while True do
    begin
      if WinchFlag then
      begin
        WinchFlag := False;
        SendNaws;
      end;
      fpFD_ZERO(rfds);
      fpFD_SET(0, rfds);
      fpFD_SET(Sock, rfds);
      if Sock > 0 then maxfd := Sock + 1 else maxfd := 1;
      n := fpSelect(maxfd, @rfds, nil, nil, nil);
      if n < 0 then
      begin
        if fpGetErrno = ESysEINTR then Continue;
        Break;
      end;
      if fpFD_ISSET(Sock, rfds) = 1 then
      begin
        n := fpRecv(Sock, @rbuf[0], SizeOf(rbuf), 0);
        if n <= 0 then
        begin
          if (n < 0) and (fpGetErrno = ESysEINTR) then Continue;
          Break;
        end;
        SetString(buf, PChar(@rbuf[0]), n);
        ProcessIncoming(buf);
      end;
      if fpFD_ISSET(0, rfds) = 1 then
      begin
        n := fpRead(0, rbuf[0], SizeOf(rbuf));
        if n <= 0 then Break;
        SetString(buf, PChar(@rbuf[0]), n);
        ProcessKeys(buf);
      end;
    end;
  finally
    RestoreTty;
    fpClose(Sock);
  end;
  Out(#13#10'Connection closed by foreign host.'#13#10);
end.

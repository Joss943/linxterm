{ LinXterm - small BSD socket helpers (IPv4 / IPv6). }
unit lxnet;

{$mode objfpc}{$H+}
{$packrecords C}

interface

uses
  SysUtils, BaseUnix, Unix, Sockets;

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

const
  AI_PASSIVE = 1;
  NI_NUMERICHOST = 1;
  NI_NAMEREQD = 8;

function getaddrinfo(node, service: PChar; hints: PAddrInfo; res: Pointer): cint; cdecl; external 'c';
procedure freeaddrinfo(res: PAddrInfo); cdecl; external 'c';
function gai_strerror(code: cint): PChar; cdecl; external 'c';
function getnameinfo(sa: PSockAddr; salen: TSocklen; host: PChar; hostlen: TSocklen; serv: PChar;
  servlen: TSocklen; flags: cint): cint; cdecl; external 'c';

function TcpConnect(const Host: string; Port: Integer; TimeoutMs: Integer; out Err: string): cint;
{ waits until Fd is readable (or writable); 1 = ready, 0 = timeout, -1 = error.
  poll() works with any descriptor number, unlike select() }
function WaitFd(Fd: cint; ForWrite: Boolean; TimeoutMs: Integer): Integer;
{ binary safe conversion of a received buffer }
function BufToStr(const Buf; N: Integer): string;
function TcpListen(const BindAddr: string; Port: Integer; out Err: string): cint;
procedure SetSocketTimeouts(Fd: cint; Seconds: Integer);
function SendAll(Fd: cint; const Data: string): Boolean;
function SockAddrToString(Sa: PSockAddr; Len: TSocklen; out Port: Integer): string;
function LocalAddress(Fd: cint; out Port: Integer): string;
function PeerAddress(Fd: cint; out Port: Integer): string;
function ReverseLookup(const Ip: string): string;
function ResolveHost(const Host: string; out Ip: string): Boolean;

implementation

function WaitFd(Fd: cint; ForWrite: Boolean; TimeoutMs: Integer): Integer;
var
  p: pollfd;
  rc: cint;
begin
  p.fd := Fd;
  if ForWrite then p.events := POLLOUT else p.events := POLLIN;
  repeat
    p.revents := 0;
    rc := fpPoll(@p, 1, TimeoutMs);
  until (rc >= 0) or (fpGetErrno <> ESysEINTR);
  if rc < 0 then Exit(-1);
  if rc = 0 then Exit(0);
  Result := 1;
end;

function BufToStr(const Buf; N: Integer): string;
begin
  if N <= 0 then Exit('');
  SetString(Result, PChar(@Buf), N);
end;

function TcpConnect(const Host: string; Port: Integer; TimeoutMs: Integer; out Err: string): cint;
var
  hints: TAddrInfo;
  res, ai: PAddrInfo;
  rc, fd, so: cint;
  flags: cint;
  len: TSocklen;
begin
  Result := -1;
  Err := '';
  FillChar(hints, SizeOf(hints), 0);
  hints.ai_family := AF_UNSPEC;
  hints.ai_socktype := SOCK_STREAM;
  res := nil;
  rc := getaddrinfo(PChar(Host), PChar(IntToStr(Port)), @hints, @res);
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
        rc := WaitFd(fd, True, TimeoutMs);
        if rc > 0 then
        begin
          so := 0;
          len := SizeOf(so);
          fpGetSockOpt(fd, SOL_SOCKET, SO_ERROR, @so, @len);
          if so = 0 then rc := 0
          else
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
  if (Result < 0) and (Err = '') then Err := 'Connection failed';
end;

function TcpListen(const BindAddr: string; Port: Integer; out Err: string): cint;
var
  hints: TAddrInfo;
  res, ai: PAddrInfo;
  rc, fd, one: cint;
  node: PChar;
  pass: Integer;
begin
  Result := -1;
  Err := '';
  FillChar(hints, SizeOf(hints), 0);
  hints.ai_family := AF_UNSPEC;
  hints.ai_socktype := SOCK_STREAM;
  hints.ai_flags := AI_PASSIVE;
  if BindAddr = '' then node := nil else node := PChar(BindAddr);
  res := nil;
  rc := getaddrinfo(node, PChar(IntToStr(Port)), @hints, @res);
  if rc <> 0 then
  begin
    Err := AnsiString(gai_strerror(rc));
    Exit;
  end;
  { prefer an IPv6 dual-stack socket when binding to every address,
    then fall back to any other address family }
  for pass := 0 to 1 do
  begin
    if Result >= 0 then Break;
    ai := res;
    while ai <> nil do
    begin
      if (pass = 0) and ((node <> nil) or (ai^.ai_family <> AF_INET6)) then
      begin
        ai := ai^.ai_next;
        Continue;
      end;
      fd := fpSocket(ai^.ai_family, ai^.ai_socktype, ai^.ai_protocol);
      if fd >= 0 then
      begin
        one := 1;
        fpSetSockOpt(fd, SOL_SOCKET, SO_REUSEADDR, @one, SizeOf(one));
        if ai^.ai_family = AF_INET6 then
        begin
          one := 0;
          fpSetSockOpt(fd, IPPROTO_IPV6, 26 { IPV6_V6ONLY }, @one, SizeOf(one));
        end;
        if (fpBind(fd, ai^.ai_addr, ai^.ai_addrlen) = 0) and (fpListen(fd, 32) = 0) then
        begin
          Result := fd;
          Err := '';
          Break;
        end;
        Err := SysErrorMessage(fpGetErrno);
        fpClose(fd);
      end;
      ai := ai^.ai_next;
    end;
  end;
  freeaddrinfo(res);
end;

procedure SetSocketTimeouts(Fd: cint; Seconds: Integer);
var
  tv: TTimeVal;
begin
  tv.tv_sec := Seconds;
  tv.tv_usec := 0;
  fpSetSockOpt(Fd, SOL_SOCKET, SO_RCVTIMEO, @tv, SizeOf(tv));
  fpSetSockOpt(Fd, SOL_SOCKET, SO_SNDTIMEO, @tv, SizeOf(tv));
end;

function SendAll(Fd: cint; const Data: string): Boolean;
var
  p, n: Integer;
begin
  p := 1;
  while p <= Length(Data) do
  begin
    n := fpSend(Fd, @Data[p], Length(Data) - p + 1, MSG_NOSIGNAL);
    if n <= 0 then
    begin
      if (n < 0) and (fpGetErrno = ESysEINTR) then Continue;
      Exit(False);
    end;
    Inc(p, n);
  end;
  Result := True;
end;

function SockAddrToString(Sa: PSockAddr; Len: TSocklen; out Port: Integer): string;
var
  host: array[0..63] of Char;
  serv: array[0..15] of Char;
begin
  Result := '';
  Port := 0;
  if getnameinfo(Sa, Len, @host[0], SizeOf(host), @serv[0], SizeOf(serv), NI_NUMERICHOST or 2 { NI_NUMERICSERV }) = 0 then
  begin
    Result := AnsiString(PChar(@host[0]));
    Port := StrToIntDef(AnsiString(PChar(@serv[0])), 0);
    if Copy(Result, 1, 7) = '::ffff:' then
      Result := Copy(Result, 8, MaxInt);
  end;
end;

function LocalAddress(Fd: cint; out Port: Integer): string;
var
  ss: array[0..127] of Byte;
  len: TSocklen;
begin
  len := SizeOf(ss);
  if fpGetSockName(Fd, @ss[0], @len) = 0 then
    Result := SockAddrToString(@ss[0], len, Port)
  else
  begin
    Result := '';
    Port := 0;
  end;
end;

function PeerAddress(Fd: cint; out Port: Integer): string;
var
  ss: array[0..127] of Byte;
  len: TSocklen;
begin
  len := SizeOf(ss);
  if fpGetPeerName(Fd, @ss[0], @len) = 0 then
    Result := SockAddrToString(@ss[0], len, Port)
  else
  begin
    Result := '';
    Port := 0;
  end;
end;

function ReverseLookup(const Ip: string): string;
var
  hints: TAddrInfo;
  res: PAddrInfo;
  host: array[0..255] of Char;
begin
  Result := '';
  FillChar(hints, SizeOf(hints), 0);
  hints.ai_flags := 4; { AI_NUMERICHOST }
  res := nil;
  if getaddrinfo(PChar(Ip), nil, @hints, @res) <> 0 then Exit;
  if getnameinfo(res^.ai_addr, res^.ai_addrlen, @host[0], SizeOf(host), nil, 0, NI_NAMEREQD) = 0 then
    Result := AnsiString(PChar(@host[0]));
  freeaddrinfo(res);
end;

function ResolveHost(const Host: string; out Ip: string): Boolean;
var
  hints: TAddrInfo;
  res: PAddrInfo;
  port: Integer;
begin
  Result := False;
  Ip := '';
  FillChar(hints, SizeOf(hints), 0);
  hints.ai_family := AF_UNSPEC;
  hints.ai_socktype := SOCK_STREAM;
  res := nil;
  if getaddrinfo(PChar(Host), nil, @hints, @res) <> 0 then Exit;
  Ip := SockAddrToString(res^.ai_addr, res^.ai_addrlen, port);
  freeaddrinfo(res);
  Result := Ip <> '';
end;

end.

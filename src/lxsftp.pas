{ LinXterm - SFTP version 3 client (draft-ietf-secsh-filexfer-02) running
  over an "ssh -s ... sftp" subprocess. All calls are blocking and must be
  used from a single worker thread. }
unit lxsftp;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, BaseUnix, lxgtk;

const
  SSH_FXP_INIT = 1;
  SSH_FXP_VERSION = 2;
  SSH_FXP_OPEN = 3;
  SSH_FXP_CLOSE = 4;
  SSH_FXP_READ = 5;
  SSH_FXP_WRITE = 6;
  SSH_FXP_LSTAT = 7;
  SSH_FXP_FSTAT = 8;
  SSH_FXP_SETSTAT = 9;
  SSH_FXP_OPENDIR = 11;
  SSH_FXP_READDIR = 12;
  SSH_FXP_REMOVE = 13;
  SSH_FXP_MKDIR = 14;
  SSH_FXP_RMDIR = 15;
  SSH_FXP_REALPATH = 16;
  SSH_FXP_STAT = 17;
  SSH_FXP_RENAME = 18;
  SSH_FXP_READLINK = 19;
  SSH_FXP_STATUS = 101;
  SSH_FXP_HANDLE = 102;
  SSH_FXP_DATA = 103;
  SSH_FXP_NAME = 104;
  SSH_FXP_ATTRS = 105;

  SSH_FX_OK = 0;
  SSH_FX_EOF = 1;
  SSH_FX_NO_SUCH_FILE = 2;
  SSH_FX_PERMISSION_DENIED = 3;
  SSH_FX_FAILURE = 4;

  SSH_FILEXFER_ATTR_SIZE = $1;
  SSH_FILEXFER_ATTR_UIDGID = $2;
  SSH_FILEXFER_ATTR_PERMISSIONS = $4;
  SSH_FILEXFER_ATTR_ACMODTIME = $8;
  SSH_FILEXFER_ATTR_EXTENDED = $80000000;

  SSH_FXF_READ = $1;
  SSH_FXF_WRITE = $2;
  SSH_FXF_APPEND = $4;
  SSH_FXF_CREAT = $8;
  SSH_FXF_TRUNC = $10;

  S_IFMT_ = $F000;
  S_IFDIR_ = $4000;
  S_IFLNK_ = $A000;
  S_IFREG_ = $8000;

type
  ESftpError = class(Exception)
  public
    Code: LongWord;
  end;

  TSftpAttrs = record
    Flags: LongWord;
    Size: Int64;
    Uid, Gid: LongWord;
    Perms: LongWord;
    ATime, MTime: LongWord;
  end;

  TSftpName = record
    Name: string;
    LongName: string;
    Attrs: TSftpAttrs;
  end;
  TSftpNames = array of TSftpName;

  TSftpProgress = function(Done, Total: Int64): Boolean of object;

  TSftpClient = class
  private
    FPid: GPid;
    FIn, FOut, FErr: cint;
    FNextId: LongWord;
    FConnected: Boolean;
    FStderr: string;
    procedure WriteAll(const Data: string);
    procedure ReadExact(var Buf; Count: Integer);
    procedure SendPacket(PType: Byte; const Payload: string);
    function ReadPacket(out PType: Byte): string;
    function NewId: LongWord;
    function Request(PType: Byte; const Payload: string; out RType: Byte): string;
    procedure CheckStatus(const Resp: string; RType: Byte; AllowEof: Boolean = False);
    function GetHandle(const Resp: string; RType: Byte): string;
    procedure ReadStderr;
  public
    constructor Create;
    destructor Destroy; override;
    { Argv: full ssh command line ending with "-s host sftp" (or a direct sftp-server) }
    procedure Connect(const Argv: array of string);
    procedure Disconnect;
    function RealPath(const P: string): string;
    function Stat(const P: string; out A: TSftpAttrs): Boolean;
    function LStat(const P: string; out A: TSftpAttrs): Boolean;
    function ListDir(const P: string): TSftpNames;
    procedure MkDir(const P: string);
    procedure RmDir(const P: string);
    procedure Remove(const P: string);
    procedure Rename(const OldPath, NewPath: string);
    procedure Chmod(const P: string; Mode: LongWord);
    function ReadLink(const P: string): string;
    procedure Download(const Remote, Local: string; Progress: TSftpProgress);
    procedure Upload(const Local, Remote: string; Progress: TSftpProgress);
    property Connected: Boolean read FConnected;
    property StderrText: string read FStderr;
  end;

function StatusText(Code: LongWord): string;

implementation

{ ---------------------------------------------------------------- encoding }

function U32(V: LongWord): string;
begin
  SetLength(Result, 4);
  Result[1] := Chr((V shr 24) and $FF);
  Result[2] := Chr((V shr 16) and $FF);
  Result[3] := Chr((V shr 8) and $FF);
  Result[4] := Chr(V and $FF);
end;

function U64(V: Int64): string;
begin
  Result := U32(LongWord(QWord(V) shr 32)) + U32(LongWord(QWord(V) and $FFFFFFFF));
end;

function Str(const S: string): string;
begin
  Result := U32(Length(S)) + S;
end;

type
  TReader = record
    Data: string;
    Pos: Integer;
  end;

procedure RInit(var R: TReader; const D: string; Start: Integer = 1);
begin
  R.Data := D;
  R.Pos := Start;
end;

function RByte(var R: TReader): Byte;
begin
  if R.Pos > Length(R.Data) then raise ESftpError.Create('Malformed SFTP packet');
  Result := Ord(R.Data[R.Pos]);
  Inc(R.Pos);
end;

function RU32(var R: TReader): LongWord;
begin
  if R.Pos + 3 > Length(R.Data) then raise ESftpError.Create('Malformed SFTP packet');
  Result := (LongWord(Ord(R.Data[R.Pos])) shl 24) or (LongWord(Ord(R.Data[R.Pos + 1])) shl 16) or
    (LongWord(Ord(R.Data[R.Pos + 2])) shl 8) or LongWord(Ord(R.Data[R.Pos + 3]));
  Inc(R.Pos, 4);
end;

function RU64(var R: TReader): Int64;
var
  hi, lo: LongWord;
begin
  hi := RU32(R);
  lo := RU32(R);
  Result := Int64((QWord(hi) shl 32) or lo);
end;

function RStr(var R: TReader): string;
var
  n: LongWord;
begin
  n := RU32(R);
  if R.Pos + Int64(n) - 1 > Length(R.Data) then raise ESftpError.Create('Malformed SFTP packet');
  Result := Copy(R.Data, R.Pos, n);
  Inc(R.Pos, n);
end;

function RAttrs(var R: TReader): TSftpAttrs;
var
  n, i: LongWord;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.Flags := RU32(R);
  if (Result.Flags and SSH_FILEXFER_ATTR_SIZE) <> 0 then Result.Size := RU64(R);
  if (Result.Flags and SSH_FILEXFER_ATTR_UIDGID) <> 0 then
  begin
    Result.Uid := RU32(R);
    Result.Gid := RU32(R);
  end;
  if (Result.Flags and SSH_FILEXFER_ATTR_PERMISSIONS) <> 0 then Result.Perms := RU32(R);
  if (Result.Flags and SSH_FILEXFER_ATTR_ACMODTIME) <> 0 then
  begin
    Result.ATime := RU32(R);
    Result.MTime := RU32(R);
  end;
  if (Result.Flags and SSH_FILEXFER_ATTR_EXTENDED) <> 0 then
  begin
    n := RU32(R);
    for i := 1 to n do
    begin
      RStr(R);
      RStr(R);
    end;
  end;
end;

function StatusText(Code: LongWord): string;
begin
  case Code of
    SSH_FX_OK: Result := 'Success';
    SSH_FX_EOF: Result := 'End of file';
    SSH_FX_NO_SUCH_FILE: Result := 'No such file or directory';
    SSH_FX_PERMISSION_DENIED: Result := 'Permission denied';
    SSH_FX_FAILURE: Result := 'Failure';
    5: Result := 'Bad message';
    6: Result := 'No connection';
    7: Result := 'Connection lost';
    8: Result := 'Operation unsupported';
  else
    Result := 'Error ' + IntToStr(Code);
  end;
end;

procedure RaiseSftp(Code: LongWord; const Msg: string);
var
  e: ESftpError;
begin
  if Msg <> '' then
    e := ESftpError.Create(Msg)
  else
    e := ESftpError.Create(StatusText(Code));
  e.Code := Code;
  raise e;
end;

{ ---------------------------------------------------------------- TSftpClient }

constructor TSftpClient.Create;
begin
  inherited Create;
  FIn := -1;
  FOut := -1;
  FErr := -1;
end;

destructor TSftpClient.Destroy;
begin
  Disconnect;
  inherited Destroy;
end;

procedure TSftpClient.ReadStderr;
var
  buf: array[0..4095] of Char;
  n: Integer;
  fl: cint;
  chunk: string;
begin
  if FErr < 0 then Exit;
  fl := fpFcntl(FErr, F_GETFL);
  fpFcntl(FErr, F_SETFL, fl or O_NONBLOCK);
  repeat
    n := fpRead(FErr, buf[0], SizeOf(buf));
    if n > 0 then
    begin
      SetString(chunk, PChar(@buf[0]), n);
      FStderr := FStderr + chunk;
    end;
  until n <= 0;
  fpFcntl(FErr, F_SETFL, fl);
  FStderr := Trim(FStderr);
end;

procedure TSftpClient.Connect(const Argv: array of string);
var
  args: array of AnsiString;
  pargs: array of PChar;
  i: Integer;
  gerr: PGError;
  t: Byte;
  r: TReader;
  resp: string;
  ver: LongWord;
begin
  Disconnect;
  FStderr := '';
  SetLength(args, Length(Argv));
  SetLength(pargs, Length(Argv) + 1);
  for i := 0 to High(Argv) do
  begin
    args[i] := Argv[i];
    pargs[i] := PChar(args[i]);
  end;
  pargs[Length(Argv)] := nil;
  gerr := nil;
  if not g_spawn_async_with_pipes(nil, @pargs[0], nil, G_SPAWN_SEARCH_PATH or G_SPAWN_DO_NOT_REAP_CHILD or G_SPAWN_CLOEXEC_PIPES,
    nil, nil, @FPid, @FIn, @FOut, @FErr, @gerr) then
    raise ESftpError.Create('Unable to start ssh: ' + ErrMsg(gerr));
  FConnected := True;
  try
    SendPacket(SSH_FXP_INIT, U32(3));
    resp := ReadPacket(t);
    if t <> SSH_FXP_VERSION then
      raise ESftpError.Create('Unexpected answer from the SFTP server');
    RInit(r, resp);
    ver := RU32(r);
    if ver < 3 then
      raise ESftpError.Create('Unsupported SFTP protocol version ' + IntToStr(ver));
  except
    on E: Exception do
    begin
      ReadStderr;
      Disconnect;
      if FStderr <> '' then
        raise ESftpError.Create(FStderr)
      else
        raise;
    end;
  end;
end;

procedure TSftpClient.Disconnect;
var
  st: cint;
  i: Integer;
begin
  if FIn >= 0 then fpClose(FIn);
  FIn := -1;
  if FOut >= 0 then fpClose(FOut);
  FOut := -1;
  if FPid > 0 then
  begin
    { give ssh a moment to exit after stdin is closed, then make sure }
    for i := 1 to 20 do
    begin
      if fpWaitPid(FPid, st, WNOHANG) <> 0 then
      begin
        FPid := 0;
        Break;
      end;
      Sleep(10);
    end;
    if FPid > 0 then
    begin
      fpKill(FPid, SIGTERM);
      fpWaitPid(FPid, st, 0);
      FPid := 0;
    end;
  end;
  if FErr >= 0 then fpClose(FErr);
  FErr := -1;
  FConnected := False;
end;

procedure TSftpClient.WriteAll(const Data: string);
var
  p, n: Integer;
begin
  p := 1;
  while p <= Length(Data) do
  begin
    n := fpWrite(FIn, Data[p], Length(Data) - p + 1);
    if n <= 0 then
    begin
      if (n < 0) and (fpGetErrno = ESysEINTR) then Continue;
      FConnected := False;
      ReadStderr;
      if FStderr <> '' then raise ESftpError.Create(FStderr);
      raise ESftpError.Create('Connection lost');
    end;
    Inc(p, n);
  end;
end;

procedure TSftpClient.ReadExact(var Buf; Count: Integer);
var
  p: PByte;
  n: Integer;
begin
  p := @Buf;
  while Count > 0 do
  begin
    n := fpRead(FOut, p^, Count);
    if n <= 0 then
    begin
      if (n < 0) and (fpGetErrno = ESysEINTR) then Continue;
      FConnected := False;
      ReadStderr;
      if FStderr <> '' then raise ESftpError.Create(FStderr);
      raise ESftpError.Create('Connection lost');
    end;
    Inc(p, n);
    Dec(Count, n);
  end;
end;

procedure TSftpClient.SendPacket(PType: Byte; const Payload: string);
begin
  if not FConnected then raise ESftpError.Create('Not connected');
  WriteAll(U32(Length(Payload) + 1) + Chr(PType) + Payload);
end;

function TSftpClient.ReadPacket(out PType: Byte): string;
var
  hdr: array[0..3] of Byte;
  len: LongWord;
begin
  ReadExact(hdr, 4);
  len := (LongWord(hdr[0]) shl 24) or (LongWord(hdr[1]) shl 16) or (LongWord(hdr[2]) shl 8) or hdr[3];
  if (len < 1) or (len > 4 * 1024 * 1024) then
    raise ESftpError.Create('Invalid SFTP packet length');
  ReadExact(PType, 1);
  SetLength(Result, len - 1);
  if len > 1 then ReadExact(Result[1], len - 1);
end;

function TSftpClient.NewId: LongWord;
begin
  Inc(FNextId);
  Result := FNextId;
end;

function TSftpClient.Request(PType: Byte; const Payload: string; out RType: Byte): string;
var
  id, rid: LongWord;
  r: TReader;
begin
  id := NewId;
  SendPacket(PType, U32(id) + Payload);
  repeat
    Result := ReadPacket(RType);
    RInit(r, Result);
    rid := RU32(r);
  until rid = id;
  Result := Copy(Result, 5, MaxInt);
end;

procedure TSftpClient.CheckStatus(const Resp: string; RType: Byte; AllowEof: Boolean);
var
  r: TReader;
  code: LongWord;
  msg: string;
begin
  if RType <> SSH_FXP_STATUS then
    raise ESftpError.Create('Unexpected SFTP answer');
  RInit(r, Resp);
  code := RU32(r);
  msg := '';
  if r.Pos <= Length(Resp) then
    try
      msg := RStr(r);
    except
      msg := '';
    end;
  if (code = SSH_FX_OK) or (AllowEof and (code = SSH_FX_EOF)) then Exit;
  RaiseSftp(code, msg);
end;

function TSftpClient.GetHandle(const Resp: string; RType: Byte): string;
var
  r: TReader;
begin
  if RType = SSH_FXP_STATUS then CheckStatus(Resp, RType);
  if RType <> SSH_FXP_HANDLE then raise ESftpError.Create('Unexpected SFTP answer');
  RInit(r, Resp);
  Result := RStr(r);
end;

function TSftpClient.RealPath(const P: string): string;
var
  t: Byte;
  resp: string;
  r: TReader;
begin
  resp := Request(SSH_FXP_REALPATH, Str(P), t);
  if t = SSH_FXP_STATUS then CheckStatus(resp, t);
  if t <> SSH_FXP_NAME then raise ESftpError.Create('Unexpected SFTP answer');
  RInit(r, resp);
  if RU32(r) < 1 then raise ESftpError.Create('Empty path');
  Result := RStr(r);
end;

function TSftpClient.Stat(const P: string; out A: TSftpAttrs): Boolean;
var
  t: Byte;
  resp: string;
  r: TReader;
begin
  FillChar(A, SizeOf(A), 0);
  resp := Request(SSH_FXP_STAT, Str(P), t);
  Result := t = SSH_FXP_ATTRS;
  if Result then
  begin
    RInit(r, resp);
    A := RAttrs(r);
  end;
end;

function TSftpClient.LStat(const P: string; out A: TSftpAttrs): Boolean;
var
  t: Byte;
  resp: string;
  r: TReader;
begin
  FillChar(A, SizeOf(A), 0);
  resp := Request(SSH_FXP_LSTAT, Str(P), t);
  Result := t = SSH_FXP_ATTRS;
  if Result then
  begin
    RInit(r, resp);
    A := RAttrs(r);
  end;
end;

function TSftpClient.ListDir(const P: string): TSftpNames;
var
  t: Byte;
  resp, h: string;
  r: TReader;
  n, i: LongWord;
  cnt: Integer;
  e: TSftpName;
begin
  Result := nil;
  cnt := 0;
  h := GetHandle(Request(SSH_FXP_OPENDIR, Str(P), t), t);
  try
    while True do
    begin
      resp := Request(SSH_FXP_READDIR, Str(h), t);
      if t = SSH_FXP_STATUS then
      begin
        CheckStatus(resp, t, True);
        Break;
      end;
      if t <> SSH_FXP_NAME then raise ESftpError.Create('Unexpected SFTP answer');
      RInit(r, resp);
      n := RU32(r);
      for i := 1 to n do
      begin
        e.Name := RStr(r);
        e.LongName := RStr(r);
        e.Attrs := RAttrs(r);
        if (e.Name = '.') or (e.Name = '..') then Continue;
        if cnt >= Length(Result) then SetLength(Result, cnt * 2 + 16);
        Result[cnt] := e;
        Inc(cnt);
      end;
    end;
  finally
    try
      Request(SSH_FXP_CLOSE, Str(h), t);
    except
    end;
  end;
  SetLength(Result, cnt);
end;

procedure TSftpClient.MkDir(const P: string);
var
  t: Byte;
  resp: string;
begin
  resp := Request(SSH_FXP_MKDIR, Str(P) + U32(0), t);
  CheckStatus(resp, t);
end;

procedure TSftpClient.RmDir(const P: string);
var
  t: Byte;
  resp: string;
begin
  resp := Request(SSH_FXP_RMDIR, Str(P), t);
  CheckStatus(resp, t);
end;

procedure TSftpClient.Remove(const P: string);
var
  t: Byte;
  resp: string;
begin
  resp := Request(SSH_FXP_REMOVE, Str(P), t);
  CheckStatus(resp, t);
end;

procedure TSftpClient.Rename(const OldPath, NewPath: string);
var
  t: Byte;
  resp: string;
begin
  resp := Request(SSH_FXP_RENAME, Str(OldPath) + Str(NewPath), t);
  CheckStatus(resp, t);
end;

procedure TSftpClient.Chmod(const P: string; Mode: LongWord);
var
  t: Byte;
  resp: string;
begin
  resp := Request(SSH_FXP_SETSTAT, Str(P) + U32(SSH_FILEXFER_ATTR_PERMISSIONS) + U32(Mode and &7777), t);
  CheckStatus(resp, t);
end;

function TSftpClient.ReadLink(const P: string): string;
var
  t: Byte;
  resp: string;
  r: TReader;
begin
  resp := Request(SSH_FXP_READLINK, Str(P), t);
  if t = SSH_FXP_STATUS then CheckStatus(resp, t);
  RInit(r, resp);
  if RU32(r) < 1 then Exit('');
  Result := RStr(r);
end;

const
  CHUNK = 32768;
  MAXREQ = 32;

type
  TPending = record
    Id: LongWord;
    Offset: Int64;
    Len: LongWord;
  end;

procedure TSftpClient.Download(const Remote, Local: string; Progress: TSftpProgress);
var
  t: Byte;
  h, resp, data: string;
  a: TSftpAttrs;
  total, nextOff, done: Int64;
  pend: array of TPending;
  npend, i, idx: Integer;
  r: TReader;
  rid, code: LongWord;
  fd: cint;
  eof, cancelled: Boolean;
  roff: Int64;
  rlen: LongWord;
  procedure Issue(Off: Int64; Len: LongWord);
  var
    id: LongWord;
  begin
    id := NewId;
    SendPacket(SSH_FXP_READ, U32(id) + Str(h) + U64(Off) + U32(Len));
    pend[npend].Id := id;
    pend[npend].Offset := Off;
    pend[npend].Len := Len;
    Inc(npend);
  end;
begin
  if not Stat(Remote, a) then a.Size := 0;
  total := a.Size;
  h := GetHandle(Request(SSH_FXP_OPEN, Str(Remote) + U32(SSH_FXF_READ) + U32(0), t), t);
  fd := fpOpen(Local, O_WRONLY or O_CREAT or O_TRUNC, &644);
  if fd < 0 then
  begin
    try
      Request(SSH_FXP_CLOSE, Str(h), t);
    except
    end;
    raise ESftpError.Create('Cannot create ' + Local + ': ' + SysErrorMessage(fpGetErrno));
  end;
  SetLength(pend, MAXREQ * 2);
  npend := 0;
  nextOff := 0;
  done := 0;
  eof := False;
  cancelled := False;
  try
    while (npend < MAXREQ) do
    begin
      Issue(nextOff, CHUNK);
      Inc(nextOff, CHUNK);
    end;
    while npend > 0 do
    begin
      resp := ReadPacket(t);
      RInit(r, resp);
      rid := RU32(r);
      idx := -1;
      for i := 0 to npend - 1 do
        if pend[i].Id = rid then idx := i;
      if idx < 0 then Continue;
      if t = SSH_FXP_STATUS then
      begin
        code := RU32(r);
        if code <> SSH_FX_EOF then
          RaiseSftp(code, '');
        eof := True;
      end
      else if t = SSH_FXP_DATA then
      begin
        data := RStr(r);
        if Length(data) > 0 then
        begin
          if fpLSeek(fd, pend[idx].Offset, SEEK_SET) < 0 then
            raise ESftpError.Create('Local seek error');
          if fpWrite(fd, data[1], Length(data)) <> Length(data) then
            raise ESftpError.Create('Cannot write ' + Local + ': ' + SysErrorMessage(fpGetErrno));
          Inc(done, Length(data));
          if Length(data) < Integer(pend[idx].Len) then
          begin
            { short read: ask again for the remainder of this block }
            roff := pend[idx].Offset + Length(data);
            rlen := pend[idx].Len - LongWord(Length(data));
            pend[idx] := pend[npend - 1];
            Dec(npend);
            Issue(roff, rlen);
            if Assigned(Progress) and not cancelled then
              if not Progress(done, total) then cancelled := True;
            Continue;
          end;
        end
        else
          eof := True;
      end
      else
        raise ESftpError.Create('Unexpected SFTP answer');
      { remove the completed request }
      pend[idx] := pend[npend - 1];
      Dec(npend);
      if Assigned(Progress) and not cancelled then
        if not Progress(done, total) then cancelled := True;
      if not eof and not cancelled then
      begin
        Issue(nextOff, CHUNK);
        Inc(nextOff, CHUNK);
      end;
    end;
  finally
    fpClose(fd);
    try
      Request(SSH_FXP_CLOSE, Str(h), t);
    except
    end;
  end;
  if cancelled then
  begin
    DeleteFile(Local);
    raise ESftpError.Create('Transfer cancelled');
  end;
end;

procedure TSftpClient.Upload(const Local, Remote: string; Progress: TSftpProgress);
var
  t: Byte;
  h, resp, data: string;
  fd: cint;
  st: Stat;
  total, off: Int64;
  npend: Integer;
  n: Integer;
  r: TReader;
  code: LongWord;
  buf: array[0..CHUNK - 1] of Char;
  cancelled, eof: Boolean;
  mode: LongWord;
begin
  fd := fpOpen(Local, O_RDONLY);
  if fd < 0 then
    raise ESftpError.Create('Cannot open ' + Local + ': ' + SysErrorMessage(fpGetErrno));
  try
    fpFStat(fd, st);
    total := st.st_size;
    mode := st.st_mode and &777;
    h := GetHandle(Request(SSH_FXP_OPEN, Str(Remote) + U32(SSH_FXF_WRITE or SSH_FXF_CREAT or SSH_FXF_TRUNC) +
      U32(SSH_FILEXFER_ATTR_PERMISSIONS) + U32(mode), t), t);
    off := 0;
    npend := 0;
    cancelled := False;
    eof := False;
    try
      while True do
      begin
        while (npend < MAXREQ) and not eof and not cancelled do
        begin
          n := fpRead(fd, buf[0], CHUNK);
          if n < 0 then raise ESftpError.Create('Cannot read ' + Local);
          if n = 0 then
          begin
            eof := True;
            Break;
          end;
          SetString(data, PChar(@buf[0]), n);
          SendPacket(SSH_FXP_WRITE, U32(NewId) + Str(h) + U64(off) + Str(data));
          Inc(off, n);
          Inc(npend);
        end;
        if npend = 0 then Break;
        resp := ReadPacket(t);
        Dec(npend);
        if t <> SSH_FXP_STATUS then raise ESftpError.Create('Unexpected SFTP answer');
        RInit(r, resp);
        RU32(r);
        code := RU32(r);
        if code <> SSH_FX_OK then RaiseSftp(code, '');
        if Assigned(Progress) and not cancelled then
          if not Progress(off - Int64(npend) * CHUNK, total) then cancelled := True;
      end;
    finally
      try
        Request(SSH_FXP_CLOSE, Str(h), t);
      except
      end;
    end;
  finally
    fpClose(fd);
  end;
  if cancelled then
  begin
    try
      Remove(Remote);
    except
    end;
    raise ESftpError.Create('Transfer cancelled');
  end;
end;

end.

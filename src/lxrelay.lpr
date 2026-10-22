{ LinXterm - terminal relay. Runs a command in its own pseudo-terminal and
  relays everything between the LinXterm terminal and the command. On the way
  it can
  - colour keywords of the output like the "Syntax highlighting" of MobaXterm
    (errors in red, warnings in orange, success in green); SIGUSR1 / SIGUSR2
    switch the colouring on / off while the session runs;
  - write what the command prints to a plain-text log file (escape sequences
    removed, line editing applied, full-screen applications skipped), like
    the "Log terminal output" option of MobaXterm.
  usage: lxrelay <logfile|-> <timestamps: 0|1> <highlight: 0|1> <command> [args...] }
program lxrelay;

{$mode objfpc}{$H+}
{$linklib c}

uses
  cthreads, Classes, SysUtils, Math, BaseUnix, Unix, termio;

type
  TWinSize = record
    ws_row, ws_col, ws_xpixel, ws_ypixel: Word;
  end;

const
  TIOCGWINSZ = $5413;
  TIOCSWINSZ = $5414;
  TIOCSCTTY = $540E;

function posix_openpt(flags: cint): cint; cdecl; external 'c';
function grantpt(fd: cint): cint; cdecl; external 'c';
function unlockpt(fd: cint): cint; cdecl; external 'c';
function ptsname(fd: cint): PChar; cdecl; external 'c';

type
  TParseState = (psText, psEsc, psEscArg, psCsi, psString, psStringEsc);

var
  LogFd: cint = -1;
  Stamps: Boolean;
  { line being built: one UTF-8 character (up to 4 bytes packed) per cell }
  Cells: array of LongWord;
  CellCount: Integer;
  Col: Integer;
  LineTime: TDateTime;
  LineStarted: Boolean;
  AltScreen: Boolean;
  State: TParseState = psText;
  CsiBuf: string;
  Pending: string;          { log text not yet written }
  StampSec: Int64 = -1;
  StampText: string;
  GotWinch: Boolean = False;
  GotHup: Boolean = False;
  Highlight: Boolean = False;
  Child: TPid = 0;
  SavedTios: Termios;
  RawSet: Boolean = False;

procedure WriteAll(Fd: cint; const S: string);
var
  p, n: Integer;
begin
  p := 1;
  while p <= Length(S) do
  begin
    n := fpWrite(Fd, S[p], Length(S) - p + 1);
    if n < 0 then
    begin
      if fpGetErrno = ESysEINTR then Continue;
      Exit;
    end;
    Inc(p, n);
  end;
end;

procedure FlushLog;
begin
  if (LogFd >= 0) and (Pending <> '') then WriteAll(LogFd, Pending);
  Pending := '';
end;

procedure SetCellCount(N: Integer);
var
  i: Integer;
begin
  if N > Length(Cells) then SetLength(Cells, N * 2 + 64);
  for i := CellCount to N - 1 do Cells[i] := Ord(' ');
  CellCount := N;
end;

procedure EmitLine;
var
  s: string;
  i, k: Integer;
  c: LongWord;
  sec: Int64;
begin
  SetLength(s, CellCount * 4);
  k := 0;
  for i := 0 to CellCount - 1 do
  begin
    c := Cells[i];
    repeat
      Inc(k);
      s[k] := Chr(c and $FF);
      c := c shr 8;
    until c = 0;
  end;
  SetLength(s, k);
  s := TrimRight(s);
  CellCount := 0;
  Col := 0;
  { the command LinXterm types to follow the remote folder erases itself
    from the screen: keep it out of the log too }
  if Pos('_lxosc7()', s) > 0 then
  begin
    LineStarted := False;
    Exit;
  end;
  if Stamps then
  begin
    if not LineStarted then LineTime := Now;
    sec := Trunc(LineTime * SecsPerDay);
    if sec <> StampSec then
    begin
      StampSec := sec;
      StampText := FormatDateTime('[yyyy-mm-dd hh:nn:ss] ', LineTime);
    end;
    s := StampText + s;
  end;
  Pending := Pending + s + #10;
  LineStarted := False;
end;

procedure PutCell(C: LongWord);
begin
  if AltScreen then Exit;
  if not LineStarted then
  begin
    LineStarted := True;
    if Stamps then LineTime := Now;
  end;
  if Col >= CellCount then SetCellCount(Col + 1);
  Cells[Col] := C;
  Inc(Col);
end;

{ UTF-8 continuation byte: belongs to the character before the cursor }
procedure AddToCell(B: Char);
var
  c: LongWord;
  sh: Integer;
begin
  if AltScreen or (Col <= 0) or (Col > CellCount) then Exit;
  c := Cells[Col - 1];
  sh := 8;
  while (sh < 32) and ((c shr sh) <> 0) do Inc(sh, 8);
  if sh < 32 then Cells[Col - 1] := c or (LongWord(Ord(B)) shl sh);
end;

function CsiParam(const Args: string; Def: Integer): Integer;
var
  a: string;
  p: Integer;
begin
  a := Args;
  p := Pos(';', a);
  if p > 0 then a := Copy(a, 1, p - 1);
  Result := StrToIntDef(a, Def);
  if Result <= 0 then Result := Def;
end;

{ applies the CSI sequences that matter for a text log: alternate screen
  switches (full-screen programs are not logged) and line editing }
procedure DoCsi(const Seq: string);
var
  fin: Char;
  args: string;
  n, i: Integer;
begin
  if Seq = '' then Exit;
  fin := Seq[Length(Seq)];
  args := Copy(Seq, 1, Length(Seq) - 1);
  if (args <> '') and (args[1] = '?') then
  begin
    if (fin in ['h', 'l']) and ((args = '?1049') or (args = '?1047') or (args = '?47')) then
    begin
      if fin = 'h' then
      begin
        if LineStarted and (CellCount > 0) then EmitLine;
        AltScreen := True;
      end
      else
      begin
        AltScreen := False;
        CellCount := 0;
        Col := 0;
        LineStarted := False;
      end;
    end;
    Exit;
  end;
  if AltScreen then Exit;
  case fin of
    'K':  { erase in line }
      begin
        n := StrToIntDef(args, 0);
        if n = 0 then
        begin
          if Col < CellCount then CellCount := Col;
        end
        else if n = 2 then
          CellCount := 0;
      end;
    'P':  { delete characters }
      begin
        n := Min(CsiParam(args, 1), CellCount - Col);
        if n > 0 then
        begin
          for i := Col to CellCount - n - 1 do
            Cells[i] := Cells[i + n];
          Dec(CellCount, n);
        end;
      end;
    '@':  { insert blanks }
      begin
        n := CsiParam(args, 1);
        if (Col <= CellCount) and (n < 1000) then
        begin
          SetCellCount(CellCount + n);
          for i := CellCount - 1 downto Col + n do
            Cells[i] := Cells[i - n];
          for i := Col to Col + n - 1 do
            Cells[i] := Ord(' ');
        end;
      end;
    'C': Inc(Col, CsiParam(args, 1));
    'D':
      begin
        Dec(Col, CsiParam(args, 1));
        if Col < 0 then Col := 0;
      end;
    'G':
      begin
        Col := CsiParam(args, 1) - 1;
        if Col < 0 then Col := 0;
      end;
  end;
end;

procedure Feed(const Buf: string);
var
  i: Integer;
  b: Char;
begin
  for i := 1 to Length(Buf) do
  begin
    b := Buf[i];
    case State of
      psText:
        case b of
          #27: State := psEsc;
          #10: if not AltScreen then EmitLine;
          #13: Col := 0;
          #8: if Col > 0 then Dec(Col);
          #9: if not AltScreen then repeat PutCell(Ord(' ')) until Col mod 8 = 0;
          #0..#7, #11, #12, #14..#26, #28..#31, #127: ;
          #$80..#$BF: AddToCell(b);
        else
          PutCell(Ord(b));
        end;
      psEsc:
        case b of
          '[':
            begin
              CsiBuf := '';
              State := psCsi;
            end;
          ']', 'P', 'X', '^', '_': State := psString;
          '(', ')', '*', '+', '-', '.', '/', '#', '%', ' ': State := psEscArg;
        else
          State := psText;
        end;
      psEscArg: State := psText;
      psCsi:
        begin
          CsiBuf := CsiBuf + b;
          if b in [#$40..#$7E] then
          begin
            DoCsi(CsiBuf);
            State := psText;
          end
          else if Length(CsiBuf) > 64 then
            State := psText;
        end;
      psString:
        if b = #7 then State := psText
        else if b = #27 then State := psStringEsc;
      psStringEsc:
        if b = '\' then State := psText
        else State := psString;
    end;
  end;
end;

{ ---------------------------------------------------------------- keyword highlighting }

type
  THlState = (hsText, hsEsc, hsEscArg, hsCsi, hsString, hsStringEsc);

const
  KW_ERROR = 1;
  KW_WARN = 2;
  KW_OK = 3;
  KwColors: array[KW_ERROR..KW_OK] of string = (#27'[1;31m', #27'[1;38;5;208m', #27'[1;32m');
  ErrorWords: array[0..36] of string = (
    'error', 'errors', 'failed', 'failure', 'failures', 'fail', 'fails', 'fatal', 'critical', 'crit',
    'denied', 'refused', 'panic', 'exception', 'aborted', 'abort', 'killed', 'unreachable', 'invalid',
    'segfault', 'emerg', 'emergency', 'corrupt', 'corrupted', 'unsuccessful', 'erreur', 'erreurs',
    'échec', 'échecs', 'Échec', 'échoué', 'échouée', 'échoués', 'refusé', 'refusée', 'interdit', 'impossible');
  WarnWords: array[0..13] of string = (
    'warning', 'warnings', 'warn', 'deprecated', 'caution', 'timeout', 'retrying', 'degraded', 'notice',
    'inactive', 'stopped', 'avertissement', 'attention', 'stoppé');
  OkWords: array[0..18] of string = (
    'ok', 'success', 'successful', 'successfully', 'succeeded', 'passed', 'done', 'completed', 'active',
    'running', 'enabled', 'online', 'connected', 'réussi', 'réussie', 'succès', 'terminé', 'terminée', 'complété');

type
  TKeyword = record
    Word: string;      { ASCII letters in lower case }
    Cls: Integer;
  end;

var
  { keywords indexed by length and first byte: most words of the output are
    rejected without any allocation }
  KwIndex: array[2..16, Char] of array of TKeyword;
  HlState: THlState = hsText;
  HlAlt: Boolean = False;
  HlCsi: string;
  SgrParams: string;   { attributes set since the last reset: restored after a keyword }
  FgSet: Boolean;      { the program chose a text colour itself: leave its text alone }
  HlOut: string;
  HlLen: Integer;

procedure AddKeyword(const W: string; Cls: Integer);
var
  lw: string;
  n: Integer;
begin
  lw := LowerCase(W);
  if (Length(lw) < 2) or (Length(lw) > 16) then Exit;
  n := Length(KwIndex[Length(lw), lw[1]]);
  SetLength(KwIndex[Length(lw), lw[1]], n + 1);
  KwIndex[Length(lw), lw[1]][n].Word := lw;
  KwIndex[Length(lw), lw[1]][n].Cls := Cls;
end;

procedure InitKeywords;
var
  w: string;
begin
  for w in ErrorWords do AddKeyword(w, KW_ERROR);
  for w in WarnWords do AddKeyword(w, KW_WARN);
  for w in OkWords do AddKeyword(w, KW_OK);
end;

function LowerAscii(C: Char): Char; inline;
begin
  if C in ['A'..'Z'] then Result := Chr(Ord(C) + 32) else Result := C;
end;

{ case-insensitive for ASCII letters; accented capitals are listed as written }
function KeywordClass(P: PChar; N: Integer): Integer;
var
  i, j: Integer;
  ok: Boolean;
begin
  Result := 0;
  if (N < 2) or (N > 16) then Exit;
  for i := 0 to High(KwIndex[N, LowerAscii(P[0])]) do
    with KwIndex[N, LowerAscii(P[0])][i] do
    begin
      ok := True;
      for j := 1 to N - 1 do
        if LowerAscii(P[j]) <> Word[j + 1] then
        begin
          ok := False;
          Break;
        end;
      if ok then Exit(Cls);
    end;
end;

procedure SgrAdd(const P: string);
begin
  if SgrParams <> '' then SgrParams := SgrParams + ';';
  SgrParams := SgrParams + P;
end;

procedure ApplySgr(const Params: string);
var
  parts: TStringArray;
  i, j, v, skip: Integer;
  p: string;
begin
  if Params = '' then
  begin
    SgrParams := '';
    FgSet := False;
    Exit;
  end;
  parts := Params.Split([';']);
  i := 0;
  while i <= High(parts) do
  begin
    v := StrToIntDef(parts[i], -1);
    if (parts[i] = '') or (v = 0) then
    begin
      SgrParams := '';
      FgSet := False;
    end
    else if (v = 38) or (v = 48) then
    begin
      { extended colours: 38;5;n or 38;2;r;g;b }
      if v = 38 then FgSet := True;
      skip := 0;
      if (i < High(parts)) and (parts[i + 1] = '5') then skip := 2
      else if (i < High(parts)) and (parts[i + 1] = '2') then skip := 4;
      p := parts[i];
      for j := i + 1 to Min(i + skip, High(parts)) do
        p := p + ';' + parts[j];
      SgrAdd(p);
      Inc(i, skip);
    end
    else
    begin
      if ((v >= 30) and (v <= 37)) or ((v >= 90) and (v <= 97)) then FgSet := True
      else if v = 39 then FgSet := False;
      SgrAdd(parts[i]);
    end;
    Inc(i);
  end;
end;

procedure HlPutP(P: PChar; N: Integer);
begin
  if N <= 0 then Exit;
  if HlLen + N > Length(HlOut) then
    SetLength(HlOut, (HlLen + N) * 2);
  Move(P^, HlOut[HlLen + 1], N);
  Inc(HlLen, N);
end;

procedure HlPut(const T: string);
begin
  if T <> '' then HlPutP(PChar(T), Length(T));
end;

procedure HlToken(P: PChar; N: Integer);
var
  core, cls: Integer;
begin
  cls := 0;
  core := N;
  if Highlight and not HlAlt and not FgSet then
  begin
    { "failed." -> "failed" + "." }
    while (core > 0) and (P[core - 1] in ['.', '-', '/']) do Dec(core);
    cls := KeywordClass(P, core);
  end;
  if cls = 0 then
  begin
    HlPutP(P, N);
    Exit;
  end;
  HlPut(KwColors[cls]);
  HlPutP(P, core);
  HlPut(#27'[0m');
  if SgrParams <> '' then HlPut(#27'[' + SgrParams + 'm');
  HlPutP(@P[core], N - core);
end;

{ returns S with the keywords of the plain text wrapped in colours; escape
  sequences are copied untouched and followed to know the current state }
function HighlightChunk(const S: string): string;
var
  i, n, tokStart, runStart: Integer;
  b: Char;
  p: PChar;
begin
  HlLen := 0;
  n := Length(S);
  if n = 0 then Exit('');
  if Length(HlOut) < n * 2 + 64 then SetLength(HlOut, n * 2 + 64);
  p := PChar(S);
  tokStart := -1;
  runStart := 0;
  for i := 0 to n - 1 do
  begin
    b := p[i];
    if HlState = hsText then
    begin
      if b in ['A'..'Z', 'a'..'z', '0'..'9', '_', '.', '-', '/', #$80..#$FF] then
      begin
        if tokStart < 0 then
        begin
          HlPutP(@p[runStart], i - runStart);
          tokStart := i;
        end;
        Continue;
      end;
      if tokStart >= 0 then
      begin
        HlToken(@p[tokStart], i - tokStart);
        tokStart := -1;
        runStart := i;
      end;
      if b = #27 then HlState := hsEsc;
      Continue;
    end;
    case HlState of
      hsEsc:
        case b of
          '[':
            begin
              HlCsi := '';
              HlState := hsCsi;
            end;
          ']', 'P', 'X', '^', '_': HlState := hsString;
          '(', ')', '*', '+', '-', '.', '/', '#', '%', ' ': HlState := hsEscArg;
          'c':
            begin
              { full reset }
              SgrParams := '';
              FgSet := False;
              HlAlt := False;
              HlState := hsText;
            end;
        else
          HlState := hsText;
        end;
      hsEscArg: HlState := hsText;
      hsCsi:
        if b in [#$40..#$7E] then
        begin
          if b = 'm' then
          begin
            if (HlCsi = '') or (HlCsi[1] in ['0'..'9', ';']) then ApplySgr(HlCsi);
          end
          else if (b in ['h', 'l']) and ((HlCsi = '?1049') or (HlCsi = '?1047') or (HlCsi = '?47')) then
            HlAlt := b = 'h';
          HlState := hsText;
        end
        else if Length(HlCsi) < 64 then
          HlCsi := HlCsi + b
        else
          HlState := hsText;
      hsString:
        if b = #7 then HlState := hsText
        else if b = #27 then HlState := hsStringEsc;
      hsStringEsc:
        if b = '\' then HlState := hsText
        else HlState := hsString;
    end;
  end;
  { a word cut by the end of the read is copied as it is }
  if tokStart >= 0 then
    HlPutP(@p[tokStart], n - tokStart)
  else
    HlPutP(@p[runStart], n - runStart);
  SetString(Result, PChar(@HlOut[1]), HlLen);
end;

procedure OnWinch(sig: cint); cdecl;
begin
  GotWinch := True;
end;

procedure OnHup(sig: cint); cdecl;
begin
  GotHup := True;
end;

procedure OnUsr(sig: cint); cdecl;
begin
  { LinXterm switches the keyword colouring of a running session }
  Highlight := sig = SIGUSR1;
end;

procedure CopyWinSize(Master: cint);
var
  ws: TWinSize;
begin
  FillChar(ws, SizeOf(ws), 0);
  if fpIoctl(0, TIOCGWINSZ, @ws) = 0 then
    fpIoctl(Master, TIOCSWINSZ, @ws);
end;

procedure RestoreTty;
begin
  if RawSet then
  begin
    TCSetAttr(0, TCSANOW, SavedTios);
    RawSet := False;
  end;
end;

var
  master, slave, n, status, i, code: cint;
  sname: string;
  tios: Termios;
  args: array of PChar;
  fds: array[0..1] of pollfd;
  buf: array[0..16383] of Char;
  chunk: string;
  childDone, haveTios: Boolean;
  w: TPid;
begin
  if ParamCount < 4 then
  begin
    WriteLn(StdErr, 'usage: lxrelay <logfile|-> <timestamps 0|1> <highlight 0|1> <command> [args...]');
    Halt(2);
  end;
  Stamps := ParamStr(2) = '1';
  Highlight := ParamStr(3) = '1';
  InitKeywords;
  if ParamStr(1) <> '-' then
  begin
    LogFd := fpOpen(ParamStr(1), O_WRONLY or O_CREAT or O_APPEND, &600);
    if LogFd < 0 then
      WriteLn(StdErr, 'lxrelay: unable to open ', ParamStr(1), ': ', SysErrorMessage(fpGetErrno));
  end;

  master := posix_openpt(O_RDWR or O_NOCTTY);
  if (master < 0) or (grantpt(master) <> 0) or (unlockpt(master) <> 0) then
  begin
    WriteLn(StdErr, 'lxrelay: no pseudo-terminal available');
    Halt(1);
  end;
  sname := StrPas(ptsname(master));
  CopyWinSize(master);
  { read the terminal settings before the parent switches to raw mode }
  haveTios := TCGetAttr(0, SavedTios) = 0;

  Child := fpFork;
  if Child < 0 then
  begin
    WriteLn(StdErr, 'lxrelay: fork failed');
    Halt(1);
  end;
  if Child = 0 then
  begin
    fpSetsid;
    slave := fpOpen(sname, O_RDWR);
    if slave < 0 then fpExit(127);
    fpIoctl(slave, TIOCSCTTY, nil);
    { the new terminal behaves like the one LinXterm gave us }
    if haveTios then TCSetAttr(slave, TCSANOW, SavedTios);
    fpDup2(slave, 0);
    fpDup2(slave, 1);
    fpDup2(slave, 2);
    if slave > 2 then fpClose(slave);
    fpClose(master);
    if LogFd >= 0 then fpClose(LogFd);
    SetLength(args, ParamCount - 2);
    for i := 4 to ParamCount do
      args[i - 4] := StrNew(PChar(ParamStr(i)));
    args[ParamCount - 3] := nil;
    fpExecvp(args[0], @args[0]);
    WriteLn(StdErr, 'lxrelay: unable to run ', ParamStr(4), ': ', SysErrorMessage(fpGetErrno));
    fpExit(127);
  end;

  fpSignal(SIGWINCH, @OnWinch);
  fpSignal(SIGHUP, @OnHup);
  fpSignal(SIGTERM, @OnHup);
  fpSignal(SIGUSR1, @OnUsr);
  fpSignal(SIGUSR2, @OnUsr);
  fpSignal(SIGINT, SignalHandler(SIG_IGN));
  fpSignal(SIGQUIT, SignalHandler(SIG_IGN));
  fpSignal(SIGPIPE, SignalHandler(SIG_IGN));
  if haveTios then
  begin
    tios := SavedTios;
    CFMakeRaw(tios);
    TCSetAttr(0, TCSANOW, tios);
    RawSet := True;
  end;

  status := 0;
  childDone := False;
  while True do
  begin
    if GotWinch then
    begin
      GotWinch := False;
      CopyWinSize(master);
    end;
    if GotHup then
    begin
      { LinXterm closes or restarts the tab: hang up the command too }
      fpKill(-Child, SIGHUP);
      fpKill(Child, SIGHUP);
      Break;
    end;
    if not childDone then
    begin
      w := fpWaitPid(Child, status, WNOHANG);
      if w = Child then childDone := True;
    end;
    fds[0].fd := 0;
    fds[0].events := POLLIN;
    fds[0].revents := 0;
    fds[1].fd := master;
    fds[1].events := POLLIN;
    fds[1].revents := 0;
    if childDone then
      n := fpPoll(@fds[1], 1, 0)
    else
      n := fpPoll(@fds[0], 2, 250);
    if n < 0 then
    begin
      if fpGetErrno = ESysEINTR then Continue;
      Break;
    end;
    if n = 0 then
    begin
      { command gone and everything it printed has been relayed }
      if childDone then Break;
      Continue;
    end;
    if (not childDone) and ((fds[0].revents and POLLIN) <> 0) then
    begin
      n := fpRead(0, buf, SizeOf(buf));
      if n > 0 then
      begin
        SetString(chunk, PChar(@buf[0]), n);
        WriteAll(master, chunk);
      end
      else if (n = 0) or (fpGetErrno <> ESysEINTR) then
      begin
        { LinXterm closed the terminal }
        fpKill(-Child, SIGHUP);
        fpKill(Child, SIGHUP);
        Break;
      end;
    end
    else if (not childDone) and ((fds[0].revents and (POLLHUP or POLLERR)) <> 0) then
    begin
      fpKill(-Child, SIGHUP);
      fpKill(Child, SIGHUP);
      Break;
    end;
    if (fds[1].revents and (POLLIN or POLLHUP or POLLERR)) <> 0 then
    begin
      n := fpRead(master, buf, SizeOf(buf));
      if n > 0 then
      begin
        SetString(chunk, PChar(@buf[0]), n);
        WriteAll(1, HighlightChunk(chunk));
        if LogFd >= 0 then Feed(chunk);
        FlushLog;
      end
      else if (n < 0) and (fpGetErrno = ESysEINTR) then
        Continue
      else
      begin
        { EIO: every process using the terminal is gone }
        if not childDone then
        begin
          fpWaitPid(Child, status, 0);
          childDone := True;
        end;
        Break;
      end;
    end;
  end;

  if LineStarted or (CellCount > 0) then EmitLine;
  FlushLog;
  if LogFd >= 0 then fpClose(LogFd);
  RestoreTty;
  if not childDone then
  begin
    { give the command a moment to exit after the hang-up }
    for i := 1 to 20 do
    begin
      if fpWaitPid(Child, status, WNOHANG) = Child then
      begin
        childDone := True;
        Break;
      end;
      Sleep(50);
    end;
  end;
  if childDone then
  begin
    if WIFEXITED(status) then code := WEXITSTATUS(status)
    else if WIFSIGNALED(status) then code := 128 + WTERMSIG(status)
    else code := 1;
  end
  else
    code := 129;
  Halt(code);
end.

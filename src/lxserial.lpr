{ LinXterm - serial port terminal.
  usage: lxserial <device> <baud> <databits> <parity: none|odd|even> <stopbits> <flow: none|rtscts|xonxoff> }
program lxserial;

{$mode objfpc}{$H+}

uses
  cthreads, SysUtils, BaseUnix, Unix, termio;

var
  SavedTios: Termios;
  RawSet: Boolean = False;

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

function BaudConst(B: Integer; out C: cardinal): Boolean;
begin
  Result := True;
  case B of
    50: C := B50;
    75: C := B75;
    110: C := B110;
    134: C := B134;
    150: C := B150;
    200: C := B200;
    300: C := B300;
    600: C := B600;
    1200: C := B1200;
    1800: C := B1800;
    2400: C := B2400;
    4800: C := B4800;
    9600: C := B9600;
    19200: C := B19200;
    38400: C := B38400;
    57600: C := B57600;
    115200: C := B115200;
    230400: C := B230400;
    460800: C := B460800;
    500000: C := B500000;
    576000: C := B576000;
    921600: C := B921600;
    1000000: C := B1000000;
    1152000: C := B1152000;
    1500000: C := B1500000;
    2000000: C := B2000000;
    2500000: C := B2500000;
    3000000: C := B3000000;
    3500000: C := B3500000;
    4000000: C := B4000000;
  else
    Result := False;
  end;
end;

var
  dev, parity, flow, err, buf: string;
  baud, bits, stop: Integer;
  fd, n, maxfd: cint;
  tio, t: Termios;
  sp: cardinal;
  rfds: TFDSet;
  rbuf: array[0..8191] of Char;
  e: cint;
begin
  if ParamCount < 1 then
  begin
    WriteLn('usage: lxserial <device> [baud] [databits] [parity] [stopbits] [flow]');
    Halt(2);
  end;
  dev := ParamStr(1);
  baud := StrToIntDef(ParamStr(2), 115200);
  bits := StrToIntDef(ParamStr(3), 8);
  parity := LowerCase(ParamStr(4));
  if parity = '' then parity := 'none';
  stop := StrToIntDef(ParamStr(5), 1);
  flow := LowerCase(ParamStr(6));
  if flow = '' then flow := 'none';
  if not BaudConst(baud, sp) then
  begin
    Out(#27'[1;31mUnsupported speed: ' + IntToStr(baud) + ' bps'#27'[0m'#13#10);
    Halt(1);
  end;
  fd := fpOpen(dev, O_RDWR or O_NOCTTY or O_NONBLOCK);
  if fd < 0 then
  begin
    e := fpGetErrno;
    err := SysErrorMessage(e);
    Out(#27'[1;31mUnable to open ' + dev + ': ' + err + #27'[0m'#13#10);
    if (e = ESysEACCES) or (e = ESysEPERM) then
      Out(#13#10'Your user is not allowed to use serial ports. Add it to the "dialout" group:'#13#10 +
        '    sudo usermod -aG dialout $USER'#13#10'then log out and log in again.'#13#10);
    Halt(1);
  end;
  { back to blocking I/O }
  fpFcntl(fd, F_SETFL, fpFcntl(fd, F_GETFL) and not O_NONBLOCK);
  if TCGetAttr(fd, tio) <> 0 then
  begin
    Out(#27'[1;31m' + dev + ' is not a serial port (' + SysErrorMessage(fpGetErrno) + ')'#27'[0m'#13#10);
    Halt(1);
  end;
  CFMakeRaw(tio);
  CFSetISpeed(tio, sp);
  CFSetOSpeed(tio, sp);
  tio.c_cflag := tio.c_cflag and not CSIZE;
  case bits of
    5: tio.c_cflag := tio.c_cflag or CS5;
    6: tio.c_cflag := tio.c_cflag or CS6;
    7: tio.c_cflag := tio.c_cflag or CS7;
  else
    tio.c_cflag := tio.c_cflag or CS8;
  end;
  tio.c_cflag := tio.c_cflag and not (PARENB or PARODD);
  if parity = 'odd' then tio.c_cflag := tio.c_cflag or PARENB or PARODD
  else if parity = 'even' then tio.c_cflag := tio.c_cflag or PARENB;
  if stop = 2 then tio.c_cflag := tio.c_cflag or CSTOPB else tio.c_cflag := tio.c_cflag and not CSTOPB;
  tio.c_cflag := tio.c_cflag and not CRTSCTS;
  tio.c_iflag := tio.c_iflag and not (IXON or IXOFF or IXANY);
  if flow = 'rtscts' then tio.c_cflag := tio.c_cflag or CRTSCTS
  else if flow = 'xonxoff' then tio.c_iflag := tio.c_iflag or IXON or IXOFF;
  tio.c_cflag := tio.c_cflag or CLOCAL or CREAD;
  tio.c_cc[VMIN] := 1;
  tio.c_cc[VTIME] := 0;
  if TCSetAttr(fd, TCSANOW, tio) <> 0 then
  begin
    Out(#27'[1;31mUnable to configure ' + dev + ': ' + SysErrorMessage(fpGetErrno) + #27'[0m'#13#10);
    Halt(1);
  end;
  TCFlush(fd, TCIOFLUSH);
  Out(#27'[1;32mConnected to ' + dev + ' at ' + IntToStr(baud) + ' bps, ' + IntToStr(bits) +
    UpperCase(Copy(parity, 1, 1)) + IntToStr(stop) + ', flow control: ' + flow + #27'[0m'#13#10);
  if TCGetAttr(0, SavedTios) = 0 then
  begin
    t := SavedTios;
    CFMakeRaw(t);
    TCSetAttr(0, TCSANOW, t);
    RawSet := True;
  end;
  fpSignal(SIGPIPE, SignalHandler(SIG_IGN));
  try
    while True do
    begin
      fpFD_ZERO(rfds);
      fpFD_SET(0, rfds);
      fpFD_SET(fd, rfds);
      maxfd := fd + 1;
      n := fpSelect(maxfd, @rfds, nil, nil, nil);
      if n < 0 then
      begin
        if fpGetErrno = ESysEINTR then Continue;
        Break;
      end;
      if fpFD_ISSET(fd, rfds) = 1 then
      begin
        n := fpRead(fd, rbuf[0], SizeOf(rbuf));
        if n <= 0 then
        begin
          if (n < 0) and (fpGetErrno = ESysEINTR) then Continue;
          RestoreTty;
          Out(#13#10#27'[1;31mSerial port ' + dev + ' disconnected.'#27'[0m'#13#10);
          Break;
        end;
        SetString(buf, PChar(@rbuf[0]), n);
        Out(buf);
      end;
      if fpFD_ISSET(0, rfds) = 1 then
      begin
        n := fpRead(0, rbuf[0], SizeOf(rbuf));
        if n <= 0 then Break;
        if fpWrite(fd, rbuf[0], n) < 0 then
        begin
          RestoreTty;
          Out(#13#10#27'[1;31mWrite error on ' + dev + '.'#27'[0m'#13#10);
          Break;
        end;
      end;
    end;
  finally
    RestoreTty;
    fpClose(fd);
  end;
end.

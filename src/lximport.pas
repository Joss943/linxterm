{ LinXterm - import of sessions created by other programs: MobaXterm
  (.mxtsessions export or MobaXterm.ini), OpenSSH (~/.ssh/config), PuTTY
  (~/.putty/sessions) and Remmina (~/.local/share/remmina). Passwords are
  never imported. }
unit lximport;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, lxgtk, lxutil, lxconfig;

type
  TImportResult = record
    Added: Integer;
    Skipped: Integer;      { unsupported session types }
    Existing: Integer;     { already in the session list }
    Stripped: Integer;     { local commands / expert options removed for safety }
    Folder: string;        { top folder of the imported sessions }
  end;

{ detects the format of FileName (LinXterm JSON, MobaXterm, OpenSSH config,
  PuTTY session file, Remmina file) and imports it }
function ImportSessionsFile(const FileName: string; out R: TImportResult; out Err: string): Boolean;
function ImportMobaXterm(const FileName: string; out R: TImportResult): Boolean;
function ImportSshConfig(const FileName: string; out R: TImportResult): Boolean;
function ImportPutty(const Dir: string; out R: TImportResult): Boolean;
function ImportRemmina(const Dir: string; out R: TImportResult): Boolean;
function DefaultSshConfig: string;
function DefaultKnownHosts: string;
{ for the quick connect completion: "alias=description" / "host[:port]" }
function ListSshConfigHosts(const FileName: string): TStringList;
function ListKnownHosts(const FileName: string): TStringList;
function DefaultPuttyDir: string;
function DefaultRemminaDir: string;
function DescribeImport(const R: TImportResult): string;

implementation

uses
  StrUtils;

function DefaultSshConfig: string;
begin
  Result := HomeDir + '/.ssh/config';
end;

function DefaultKnownHosts: string;
begin
  Result := HomeDir + '/.ssh/known_hosts';
end;

function DefaultPuttyDir: string;
begin
  Result := HomeDir + '/.putty/sessions';
end;

function DefaultRemminaDir: string;
begin
  Result := CStr(g_get_user_data_dir) + '/remmina';
  if not DirectoryExists(Result) then
    Result := HomeDir + '/.local/share/remmina';
end;

function DescribeImport(const R: TImportResult): string;
begin
  Result := IntToStr(R.Added) + ' session(s) imported';
  if R.Folder <> '' then Result := Result + ' into the "' + R.Folder + '" folder';
  Result := Result + '.';
  if R.Existing > 0 then
    Result := Result + #10 + IntToStr(R.Existing) + ' session(s) were already in your list.';
  if R.Skipped > 0 then
    Result := Result + #10 + IntToStr(R.Skipped) + ' session(s) of a type that does not exist on Linux were skipped.';
  if R.Stripped > 0 then
    Result := Result + #10 + IntToStr(R.Stripped) + ' session(s) contained a local command or expert options ' +
      '(ssh / FreeRDP): they were removed for safety, check these sessions before using them.';
  Result := Result + #10#10'Passwords are never imported: they are asked at the first connection.';
end;

{ Windows exports are often encoded in Windows-1252 }
function ToUtf8(const S: string): string;
var
  p: PChar;
begin
  if (S = '') or g_utf8_validate(PChar(S), Length(S), nil) then Exit(S);
  p := g_convert_with_fallback(PChar(S), Length(S), 'UTF-8', 'WINDOWS-1252', '?', nil, nil, nil);
  if p <> nil then Result := TakeStr(p) else Result := S;
end;

procedure ResetResult(out R: TImportResult; const Folder: string);
begin
  R.Added := 0;
  R.Skipped := 0;
  R.Existing := 0;
  R.Stripped := 0;
  R.Folder := Folder;
end;

{ adds S to the store unless the same session already exists there }
procedure AddImported(S: TSession; var R: TImportResult);
var
  i: Integer;
  o: TSession;
begin
  for i := 0 to Store.Sessions.Count - 1 do
  begin
    o := Store.Sessions[i];
    if (o.Kind = S.Kind) and (o.Name = S.Name) and (o.Folder = S.Folder) and
      SameText(o.Host, S.Host) and (o.Url = S.Url) then
    begin
      Inc(R.Existing);
      S.Free;
      Exit;
    end;
  end;
  if S.Folder <> '' then Store.AddFolder(S.Folder);
  Store.Add(S);
  Inc(R.Added);
end;

function CleanFolder(const F: string): string;
var
  parts: TStringArray;
  p: string;
begin
  Result := '';
  parts := SplitString(StringReplace(F, '\', '/', [rfReplaceAll]), '/');
  for p in parts do
    if Trim(p) <> '' then
    begin
      if Result <> '' then Result := Result + '/';
      Result := Result + Trim(p);
    end;
end;

function JoinFolder(const A, B: string): string;
begin
  if B = '' then Result := A
  else if A = '' then Result := B
  else Result := A + '/' + B;
end;

{ ---------------------------------------------------------------- MobaXterm }

{ MobaXterm paths use variables for the profile folder: map them to $HOME }
function MobaPath(const P: string): string;
var
  s: string;
begin
  s := P;
  s := StringReplace(s, '_ProfileDir_', HomeDir, [rfIgnoreCase]);
  s := StringReplace(s, '_MyDocuments_', HomeDir + '/Documents', [rfIgnoreCase]);
  s := StringReplace(s, '_CurrentDrive_:', '', [rfIgnoreCase]);
  s := StringReplace(s, '\', '/', [rfReplaceAll]);
  Result := s;
end;

function Field(const F: TStringArray; I: Integer): string;
begin
  if (I >= 0) and (I <= High(F)) then Result := F[I] else Result := '';
end;

{ one bookmark: name=#icon#type%field1%field2...#terminal settings#...#comment }
function ParseMobaBookmark(const Name, Value, Folder: string; var R: TImportResult): Boolean;
var
  parts, f: TStringArray;
  typ, i: Integer;
  s: TSession;
  key, gw: string;
begin
  Result := False;
  parts := SplitString(Value, '#');
  if Length(parts) < 3 then Exit;
  f := SplitString(parts[2], '%');
  if Length(f) = 0 then Exit;
  typ := StrToIntDef(f[0], -1);
  s := nil;
  case typ of
    0: s := TSession.Create(skSSH);
    1: s := TSession.Create(skTelnet);
    4: s := TSession.Create(skRDP);
    5: s := TSession.Create(skVNC);
    6: s := TSession.Create(skFTP);
    7: s := TSession.Create(skSFTP);
    8: s := TSession.Create(skSerial);
    10: s := TSession.Create(skShell);
    11: s := TSession.Create(skBrowser);
    12: s := TSession.Create(skMosh);
  end;
  if s = nil then
  begin
    { Rsh, XDMCP, AWS S3, WSL, Windows folders... }
    Inc(R.Skipped);
    Exit(True);
  end;
  s.Name := ToUtf8(Trim(Name));
  s.Folder := Folder;
  case s.Kind of
    skSSH, skTelnet, skRDP, skVNC, skFTP, skSFTP, skMosh:
      begin
        s.Host := Trim(Field(f, 1));
        s.Port := StrToIntDef(Field(f, 2), SessionKindDefaultPorts[s.Kind]);
        s.User := Trim(Field(f, 3));
      end;
    skSerial:
      begin
        s.Baud := StrToIntDef(Field(f, 2), 115200);
        if s.Baud <= 0 then s.Baud := 115200;
        { the Windows COM port does not exist here: the user picks the device }
        s.Device := '/dev/ttyUSB0';
        s.Comment := 'Imported from MobaXterm: check the serial port.';
      end;
    skBrowser:
      for i := 1 to High(f) do
        if Pos('://', f[i]) > 0 then
        begin
          s.Url := f[i];
          Break;
        end;
  end;
  if s.Kind = skSSH then
  begin
    s.X11 := Field(f, 5) <> '0';
    s.Compression := Field(f, 6) = '-1';
    s.RemoteCommand := Trim(Field(f, 7));
    gw := Trim(Field(f, 8));
    if gw <> '' then
    begin
      if Trim(Field(f, 10)) <> '' then gw := Trim(Field(f, 10)) + '@' + gw;
      if (StrToIntDef(Field(f, 9), 22) <> 22) and (StrToIntDef(Field(f, 9), 0) > 0) then
        gw := gw + ':' + Field(f, 9);
      s.JumpHost := gw;
    end;
    key := Trim(Field(f, 14));
    if (key <> '') and ((Pos('\', key) > 0) or (Pos('/', key) > 0)) then
    begin
      key := MobaPath(key);
      if FileExists(key) then
        s.KeyFile := key
      else if FileExists(HomeDir + '/.ssh/' + ExtractFileName(key)) then
        s.KeyFile := HomeDir + '/.ssh/' + ExtractFileName(key)
      else
        s.Comment := 'Private key used on Windows: ' + Trim(Field(f, 14));
    end;
  end;
  if (Length(parts) > 5) and (Trim(parts[5]) <> '') and (s.Comment = '') then
    s.Comment := ToUtf8(Trim(parts[5]));
  if (s.Kind in [skSSH, skTelnet, skRDP, skVNC, skFTP, skSFTP, skMosh]) and (s.Host = '') then
  begin
    s.Free;
    Inc(R.Skipped);
    Exit(True);
  end;
  AddImported(s, R);
  Result := True;
end;

function ImportMobaXterm(const FileName: string; out R: TImportResult): Boolean;
var
  lines: TStringList;
  i, eq: Integer;
  line, section, folder, name, value: string;
  inBookmarks, found: Boolean;
begin
  ResetResult(R, 'MobaXterm');
  Result := False;
  found := False;
  lines := TStringList.Create;
  try
    try
      lines.LoadFromFile(FileName);
    except
      Exit;
    end;
    inBookmarks := False;
    folder := R.Folder;
    for i := 0 to lines.Count - 1 do
    begin
      line := TrimRight(lines[i]);
      if line = '' then Continue;
      if line[1] = '[' then
      begin
        section := Copy(line, 2, Pos(']', line) - 2);
        inBookmarks := (section = 'Bookmarks') or AnsiStartsText('Bookmarks_', section);
        folder := R.Folder;
        if inBookmarks then found := True;
        Continue;
      end;
      if not inBookmarks then Continue;
      eq := Pos('=', line);
      if eq <= 1 then Continue;
      name := Copy(line, 1, eq - 1);
      value := Copy(line, eq + 1, MaxInt);
      if SameText(name, 'SubRep') then
        folder := JoinFolder(R.Folder, ToUtf8(CleanFolder(value)))
      else if SameText(name, 'ImgNum') then
        Continue
      else if (value <> '') and (value[1] = '#') then
        ParseMobaBookmark(name, value, folder, R);
    end;
    Result := found;
  finally
    lines.Free;
  end;
end;

{ ---------------------------------------------------------------- OpenSSH }

type
  TSshHost = class
    HostName, User, Port, Jump, X11, Comp, Agent: string;
  end;

{ "Host" entries of an OpenSSH client configuration (wildcards, negations and
  "Match" blocks left out); each string owns a TSshHost }
procedure ParseSshConfig(const FileName: string; Hosts: TStringList);
var
  lines: TStringList;
  names: TStringArray;
  cur: array of TSshHost;
  i, j, sp: Integer;
  line, key, value, h: string;
  inMatch: Boolean;
  sh: TSshHost;
begin
  if not FileExists(FileName) then Exit;
  lines := TStringList.Create;
  try
    try
      lines.LoadFromFile(FileName);
    except
      Exit;
    end;
    cur := nil;
    inMatch := False;
    for i := 0 to lines.Count - 1 do
    begin
      line := Trim(lines[i]);
      if (line = '') or (line[1] = '#') then Continue;
      sp := 1;
      while (sp <= Length(line)) and not (line[sp] in [' ', #9, '=']) do Inc(sp);
      key := LowerCase(Copy(line, 1, sp - 1));
      value := Trim(Copy(line, sp, MaxInt));
      if (value <> '') and (value[1] = '=') then value := Trim(Copy(value, 2, MaxInt));
      if (Length(value) >= 2) and (value[1] = '"') and (value[Length(value)] = '"') then
        value := Copy(value, 2, Length(value) - 2);
      if (key = 'host') or (key = 'match') then
      begin
        cur := nil;
        inMatch := key = 'match';
        if not inMatch then
        begin
          names := SplitString(DelSpace1(StringReplace(value, #9, ' ', [rfReplaceAll])), ' ');
          for j := 0 to High(names) do
          begin
            h := Trim(names[j]);
            if (h = '') or (h[1] = '!') or (Pos('*', h) > 0) or (Pos('?', h) > 0) then Continue;
            if Hosts.IndexOf(h) >= 0 then Continue;
            sh := TSshHost.Create;
            Hosts.AddObject(h, sh);
            SetLength(cur, Length(cur) + 1);
            cur[High(cur)] := sh;
          end;
        end;
        Continue;
      end;
      if inMatch then Continue;
      for sh in cur do
      begin
        { the first value of an option wins, like ssh does }
        if (key = 'hostname') and (sh.HostName = '') then sh.HostName := value
        else if (key = 'user') and (sh.User = '') then sh.User := value
        else if (key = 'port') and (sh.Port = '') then sh.Port := value
        else if (key = 'proxyjump') and (sh.Jump = '') then sh.Jump := value
        else if (key = 'forwardx11') and (sh.X11 = '') then sh.X11 := value
        else if (key = 'compression') and (sh.Comp = '') then sh.Comp := value
        else if (key = 'forwardagent') and (sh.Agent = '') then sh.Agent := value;
      end;
    end;
  finally
    lines.Free;
  end;
end;

procedure FreeHosts(Hosts: TStringList);
var
  i: Integer;
begin
  for i := 0 to Hosts.Count - 1 do
    Hosts.Objects[i].Free;
  Hosts.Free;
end;

function DescribeSshHost(H: TSshHost): string;
begin
  Result := '';
  if H.HostName <> '' then Result := H.HostName;
  if H.User <> '' then Result := Result + IfThen(Result <> '', ', ', '') + 'user ' + H.User;
  if H.Port <> '' then Result := Result + IfThen(Result <> '', ', ', '') + 'port ' + H.Port;
  if H.Jump <> '' then Result := Result + IfThen(Result <> '', ', ', '') + 'via ' + H.Jump;
end;

function ListSshConfigHosts(const FileName: string): TStringList;
var
  hosts: TStringList;
  i: Integer;
begin
  Result := TStringList.Create;
  hosts := TStringList.Create;
  try
    ParseSshConfig(FileName, hosts);
    for i := 0 to hosts.Count - 1 do
      Result.Add(hosts[i] + '=' + DescribeSshHost(TSshHost(hosts.Objects[i])));
  finally
    FreeHosts(hosts);
  end;
end;

function ListKnownHosts(const FileName: string): TStringList;
var
  lines: TStringList;
  names: TStringArray;
  i, p: Integer;
  line, h: string;
begin
  Result := TStringList.Create;
  Result.Sorted := True;
  Result.Duplicates := dupIgnore;
  if not FileExists(FileName) then Exit;
  lines := TStringList.Create;
  try
    try
      lines.LoadFromFile(FileName);
    except
      Exit;
    end;
    for i := 0 to lines.Count - 1 do
    begin
      line := Trim(lines[i]);
      { hashed names (HashKnownHosts) cannot be read back; markers are skipped }
      if (line = '') or (line[1] in ['#', '|', '@']) then Continue;
      p := Pos(' ', line);
      if p = 0 then Continue;
      names := SplitString(Copy(line, 1, p - 1), ',');
      for h in names do
      begin
        if (h = '') or (Pos('*', h) > 0) or (Pos('?', h) > 0) or (h[1] = '!') then Continue;
        if h[1] = '[' then
        begin
          { [host]:port }
          p := Pos(']:', h);
          if p = 0 then Continue;
          if Copy(h, p + 2, 10) = '22' then Result.Add(Copy(h, 2, p - 2))
          else Result.Add(Copy(h, 2, p - 2) + ':' + Copy(h, p + 2, 10));
        end
        else
          Result.Add(h);
      end;
    end;
  finally
    lines.Free;
  end;
end;

function ImportSshConfig(const FileName: string; out R: TImportResult): Boolean;
var
  hosts: TStringList;
  i: Integer;
  h: TSshHost;
  s: TSession;
  desc: string;
begin
  ResetResult(R, 'OpenSSH');
  Result := FileExists(FileName);
  if not Result then Exit;
  hosts := TStringList.Create;
  try
    ParseSshConfig(FileName, hosts);
    for i := 0 to hosts.Count - 1 do
    begin
      h := TSshHost(hosts.Objects[i]);
      s := TSession.Create(skSSH);
      s.Name := hosts[i];
      s.Folder := R.Folder;
      { connect through the alias: ssh applies every option of the config file }
      s.Host := hosts[i];
      s.Port := 22;
      if h.X11 <> '' then s.X11 := SameText(h.X11, 'yes');
      if h.Comp <> '' then s.Compression := SameText(h.Comp, 'yes');
      if h.Agent <> '' then s.AgentForward := SameText(h.Agent, 'yes');
      desc := DescribeSshHost(h);
      s.Comment := 'From ~/.ssh/config' + IfThen(desc <> '', ' - ' + desc, '');
      AddImported(s, R);
    end;
  finally
    FreeHosts(hosts);
  end;
end;

{ ---------------------------------------------------------------- PuTTY }

function UrlDecode(const S: string): string;
var
  i: Integer;
begin
  Result := '';
  i := 1;
  while i <= Length(S) do
  begin
    if (S[i] = '%') and (i + 2 <= Length(S)) and (StrToIntDef('$' + Copy(S, i + 1, 2), -1) >= 0) then
    begin
      Result := Result + Chr(StrToInt('$' + Copy(S, i + 1, 2)));
      Inc(i, 3);
    end
    else
    begin
      Result := Result + S[i];
      Inc(i);
    end;
  end;
end;

function ImportPuttyFile(const FileName: string; var R: TImportResult): Boolean;
var
  kv: TStringList;
  proto, name: string;
  s: TSession;
begin
  Result := False;
  name := UrlDecode(ExtractFileName(FileName));
  if SameText(name, 'Default Settings') then Exit(True);
  kv := TStringList.Create;
  try
    try
      kv.LoadFromFile(FileName);
    except
      Exit;
    end;
    kv.NameValueSeparator := '=';
    proto := LowerCase(kv.Values['Protocol']);
    if proto = '' then proto := 'ssh';
    if proto = 'ssh' then s := TSession.Create(skSSH)
    else if proto = 'telnet' then s := TSession.Create(skTelnet)
    else if proto = 'serial' then s := TSession.Create(skSerial)
    else
    begin
      Inc(R.Skipped);
      Exit(True);
    end;
    s.Name := ToUtf8(name);
    s.Folder := R.Folder;
    s.Host := kv.Values['HostName'];
    if (Pos('@', s.Host) > 0) then
    begin
      s.User := Copy(s.Host, 1, Pos('@', s.Host) - 1);
      s.Host := Copy(s.Host, Pos('@', s.Host) + 1, MaxInt);
    end;
    if kv.Values['UserName'] <> '' then s.User := kv.Values['UserName'];
    s.Port := StrToIntDef(kv.Values['PortNumber'], SessionKindDefaultPorts[s.Kind]);
    if s.Kind = skSSH then
    begin
      if kv.Values['X11Forward'] <> '' then s.X11 := kv.Values['X11Forward'] = '1';
      s.Compression := kv.Values['Compression'] = '1';
      s.AgentForward := kv.Values['AgentFwd'] = '1';
      s.RemoteCommand := kv.Values['RemoteCommand'];
      if (kv.Values['PublicKeyFile'] <> '') then
        s.Comment := 'PuTTY key (.ppk) to convert with "puttygen key.ppk -O private-openssh": ' + kv.Values['PublicKeyFile'];
    end
    else if s.Kind = skSerial then
    begin
      s.Device := kv.Values['SerialLine'];
      s.Baud := StrToIntDef(kv.Values['SerialSpeed'], 115200);
      s.DataBits := StrToIntDef(kv.Values['SerialDataBits'], 8);
      s.StopBits := StrToIntDef(kv.Values['SerialStopHalfbits'], 2) div 2;
      if s.StopBits < 1 then s.StopBits := 1;
    end;
    if (s.Kind <> skSerial) and (s.Host = '') then
    begin
      s.Free;
      Inc(R.Skipped);
      Exit(True);
    end;
    AddImported(s, R);
    Result := True;
  finally
    kv.Free;
  end;
end;

function ImportPutty(const Dir: string; out R: TImportResult): Boolean;
var
  sr: TSearchRec;
begin
  ResetResult(R, 'PuTTY');
  Result := DirectoryExists(Dir);
  if not Result then Exit;
  if FindFirst(IncludeTrailingPathDelimiter(Dir) + '*', faAnyFile, sr) = 0 then
  begin
    repeat
      if (sr.Attr and faDirectory) = 0 then
        ImportPuttyFile(IncludeTrailingPathDelimiter(Dir) + sr.Name, R);
    until FindNext(sr) <> 0;
    FindClose(sr);
  end;
end;

{ ---------------------------------------------------------------- Remmina }

function ImportRemminaFile(const FileName: string; var R: TImportResult): Boolean;
var
  kv: TStringList;
  i, p: Integer;
  proto, server, line: string;
  s: TSession;
begin
  Result := False;
  kv := TStringList.Create;
  try
    try
      kv.LoadFromFile(FileName);
    except
      Exit;
    end;
    { keep the [remmina] section only }
    for i := kv.Count - 1 downto 0 do
    begin
      line := Trim(kv[i]);
      if (line = '') or (line[1] in ['[', '#', ';']) then kv.Delete(i);
    end;
    kv.NameValueSeparator := '=';
    proto := UpperCase(kv.Values['protocol']);
    if proto = 'RDP' then s := TSession.Create(skRDP)
    else if (proto = 'VNC') or (proto = 'VNCI') then s := TSession.Create(skVNC)
    else if proto = 'SSH' then s := TSession.Create(skSSH)
    else if proto = 'SFTP' then s := TSession.Create(skSFTP)
    else
    begin
      Inc(R.Skipped);
      Exit(True);
    end;
    s.Name := kv.Values['name'];
    if s.Name = '' then s.Name := ChangeFileExt(ExtractFileName(FileName), '');
    s.Folder := JoinFolder(R.Folder, CleanFolder(kv.Values['group']));
    server := kv.Values['server'];
    if server = '' then server := kv.Values['ssh_server'];
    p := LastDelimiter(':', server);
    if (p > 0) and (Pos(']', server) < p) and (StrToIntDef(Copy(server, p + 1, 6), -1) > 0) then
    begin
      s.Port := StrToInt(Copy(server, p + 1, 6));
      server := Copy(server, 1, p - 1);
    end;
    if (s.Kind = skVNC) and (s.Port > 0) and (s.Port < 100) then
      s.Port := 5900 + s.Port;
    s.Host := server;
    s.User := kv.Values['username'];
    if s.User = '' then s.User := kv.Values['ssh_username'];
    if s.Kind = skRDP then
      s.Domain := kv.Values['domain'];
    if s.Host = '' then
    begin
      s.Free;
      Inc(R.Skipped);
      Exit(True);
    end;
    AddImported(s, R);
    Result := True;
  finally
    kv.Free;
  end;
end;

function ImportRemmina(const Dir: string; out R: TImportResult): Boolean;
var
  sr: TSearchRec;
begin
  ResetResult(R, 'Remmina');
  Result := DirectoryExists(Dir);
  if not Result then Exit;
  if FindFirst(IncludeTrailingPathDelimiter(Dir) + '*.remmina', faAnyFile, sr) = 0 then
  begin
    repeat
      ImportRemminaFile(IncludeTrailingPathDelimiter(Dir) + sr.Name, R);
    until FindNext(sr) <> 0;
    FindClose(sr);
  end;
end;

{ ---------------------------------------------------------------- detection }

function ImportSessionsFile(const FileName: string; out R: TImportResult; out Err: string): Boolean;
var
  txt, low: string;
  n: Integer;
begin
  Result := False;
  Err := '';
  ResetResult(R, '');
  if not ReadFileText(FileName, txt) then
  begin
    Err := 'Unable to read ' + FileName;
    Exit;
  end;
  low := LowerCase(txt);
  if (Trim(txt) <> '') and (Trim(txt)[1] = '{') then
  begin
    Result := Store.ImportFrom(FileName, n, R.Stripped);
    R.Added := n;
    if not Result then Err := 'The file is not a valid ' + APP_NAME + ' sessions file.';
  end
  else if Pos('[bookmarks', low) > 0 then
  begin
    Result := ImportMobaXterm(FileName, R);
    if not Result then Err := 'No MobaXterm session found in this file.';
  end
  else if Pos('[remmina]', low) > 0 then
  begin
    ResetResult(R, 'Remmina');
    Result := ImportRemminaFile(FileName, R);
    if not Result then Err := 'Unable to read this Remmina file.';
  end
  else if (Pos('hostname=', low) > 0) and (Pos('protocol=', low) > 0) then
  begin
    ResetResult(R, 'PuTTY');
    Result := ImportPuttyFile(FileName, R);
    if not Result then Err := 'Unable to read this PuTTY session.';
  end
  else if (Pos('host ', low) > 0) or (Pos('host'#9, low) > 0) then
  begin
    Result := ImportSshConfig(FileName, R);
    if not Result then Err := 'Unable to read this OpenSSH configuration file.';
  end
  else
    Err := 'Unknown file format. Supported: ' + APP_NAME + ' (.json), MobaXterm (.mxtsessions, MobaXterm.ini), ' +
      'OpenSSH (ssh_config), PuTTY and Remmina session files.';
end;

end.

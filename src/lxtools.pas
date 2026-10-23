{ LinXterm - network and system tools (Tools menu / Tools side panel). }
unit lxtools;

{$mode objfpc}{$H+}
{$packrecords C}

interface

uses
  Classes, SysUtils, SyncObjs, BaseUnix, Unix, Sockets, cairo, lxgtk, lxutil, lxconfig, lxtabs, lxnet;

procedure OpenTool(const Id: string);

implementation

uses
  StrUtils, Math, DateUtils, lxfs;

type
  TToolDef = record
    Id, Caption, Icon, Group: string;
  end;

const
  ToolDefs: array[0..17] of TToolDef = (
    (Id: 'editor'; Caption: 'Text editor'; Icon: 'accessories-text-editor'; Group: 'Applications'),
    (Id: 'keygen'; Caption: 'SSH key generator'; Icon: 'seahorse'; Group: 'Applications'),
    (Id: 'diff'; Caption: 'Compare files (diff)'; Icon: 'meld'; Group: 'Applications'),
    (Id: 'folderdiff'; Caption: 'Compare folders'; Icon: 'kdiff3'; Group: 'Applications'),
    (Id: 'passwords'; Caption: 'Passwords management'; Icon: 'dialog-password'; Group: 'Applications'),
    (Id: 'packages'; Caption: 'Packages manager'; Icon: 'system-software-install'; Group: 'System'),
    (Id: 'processes'; Caption: 'List running processes'; Icon: 'utilities-system-monitor'; Group: 'System'),
    (Id: 'sysmon'; Caption: 'System monitor (top)'; Icon: 'htop'; Group: 'System'),
    (Id: 'hardware'; Caption: 'List hardware devices'; Icon: 'computer'; Group: 'System'),
    (Id: 'tunnels'; Caption: 'SSH tunnels (port forwarding)'; Icon: 'network-vpn'; Group: 'Network'),
    (Id: 'openports'; Caption: 'List open network ports'; Icon: 'gnome-nettool'; Group: 'Network'),
    (Id: 'netscan'; Caption: 'Network scanner'; Icon: 'ipscan'; Group: 'Network'),
    (Id: 'portscan'; Caption: 'Ports scanner'; Icon: 'zenmap'; Group: 'Network'),
    (Id: 'ping'; Caption: 'Ping (graphical)'; Icon: 'etherape'; Group: 'Network'),
    (Id: 'traceroute'; Caption: 'Traceroute'; Icon: 'knetattach'; Group: 'Network'),
    (Id: 'interfaces'; Caption: 'Network interfaces'; Icon: 'network-wired'; Group: 'Network'),
    (Id: 'wol'; Caption: 'Wake on LAN'; Icon: 'system-shutdown'; Group: 'Network'),
    (Id: 'ipcalc'; Caption: 'IP subnet calculator'; Icon: 'gnome-calculator'; Group: 'Network'));

{ ---------------------------------------------------------------- base window }

type
  TToolWindow = class
  public
    Win: Pointer;
    Alive: Boolean;
    constructor Create(const Title, Icon: string; W, H: Integer);
    destructor Destroy; override;
    procedure Closed; virtual;
  end;

procedure ToolDestroyed(w: Pointer; data: gpointer); cdecl;
begin
  TToolWindow(data).Win := nil;
  TToolWindow(data).Closed;
end;

constructor TToolWindow.Create(const Title, Icon: string; W, H: Integer);
begin
  inherited Create;
  Alive := True;
  Win := gtk_window_new(GTK_WINDOW_TOPLEVEL);
  gtk_window_set_title(Win, PChar(Title));
  gtk_window_set_default_size(Win, W, H);
  gtk_window_set_icon(Win, IconPixbuf(Icon, 64));
  gtk_window_set_transient_for(Win, MainWindowWidget);
  gtk_window_set_destroy_with_parent(Win, True);
  gtk_window_set_position(Win, GTK_WIN_POS_CENTER_ON_PARENT);
  AddClass(Win, 'lx-main');
  Connect(Win, 'destroy', @ToolDestroyed, Self);
end;

destructor TToolWindow.Destroy;
begin
  inherited Destroy;
end;

procedure TToolWindow.Closed;
begin
  Alive := False;
  Free;
end;

function NewListView(const Titles: array of string; out Store: Pointer): Pointer;
var
  types: array of GType;
  i: Integer;
  col, cell: Pointer;
begin
  SetLength(types, Length(Titles));
  for i := 0 to High(Titles) do types[i] := G_TYPE_STRING;
  Store := gtk_list_store_newv(Length(Titles), @types[0]);
  Result := gtk_tree_view_new_with_model(Store);
  g_object_unref(Store);
  for i := 0 to High(Titles) do
  begin
    col := gtk_tree_view_column_new;
    gtk_tree_view_column_set_title(col, PChar(Titles[i]));
    cell := gtk_cell_renderer_text_new;
    gtk_tree_view_column_pack_start(col, cell, True);
    gtk_tree_view_column_add_attribute(col, cell, 'text', i);
    gtk_tree_view_column_set_resizable(col, True);
    gtk_tree_view_column_set_sort_column_id(col, i);
    gtk_tree_view_append_column(Result, col);
  end;
end;

procedure ListAdd(Store: Pointer; const Values: array of string);
var
  it: TGtkTreeIter;
  i: Integer;
begin
  gtk_list_store_append(Store, @it);
  for i := 0 to High(Values) do
    gtk_list_store_set(Store, @it, i, PChar(Values[i]), -1);
end;

function ListSelectedText(View: Pointer; Col: Integer): string;
var
  it: TGtkTreeIter;
  model: Pointer;
  p: PChar;
begin
  Result := '';
  if gtk_tree_selection_get_selected(gtk_tree_view_get_selection(View), @model, @it) then
  begin
    p := nil;
    gtk_tree_model_get(model, @it, Col, @p, -1);
    Result := TakeStr(p);
  end;
end;

{ ---------------------------------------------------------------- network helpers }

function ProbePort(const Ip: string; Port: Integer; TimeoutMs: Integer): Integer;
{ 1 = open, 0 = closed (host up), -1 = no answer }
var
  sa: TInetSockAddr;
  fd, rc, so, flags: cint;
  len: TSocklen;
begin
  Result := -1;
  fd := fpSocket(AF_INET, SOCK_STREAM, 0);
  if fd < 0 then Exit;
  try
    FillChar(sa, SizeOf(sa), 0);
    sa.sin_family := AF_INET;
    sa.sin_port := htons(Port);
    sa.sin_addr := StrToNetAddr(Ip);
    flags := fpFcntl(fd, F_GETFL);
    fpFcntl(fd, F_SETFL, flags or O_NONBLOCK);
    rc := fpConnect(fd, @sa, SizeOf(sa));
    if rc = 0 then Exit(1);
    if fpGetErrno = ESysECONNREFUSED then Exit(0);
    if fpGetErrno <> ESysEINPROGRESS then Exit(-1);
    if WaitFd(fd, True, TimeoutMs) <= 0 then Exit(-1);
    so := 0;
    len := SizeOf(so);
    fpGetSockOpt(fd, SOL_SOCKET, SO_ERROR, @so, @len);
    if so = 0 then Result := 1
    else if so = ESysECONNREFUSED then Result := 0
    else Result := -1;
  finally
    fpClose(fd);
  end;
end;

function Checksum(const Buf; Len: Integer): Word;
var
  p: PByte;
  sum: LongWord;
  i: Integer;
begin
  p := @Buf;
  sum := 0;
  i := 0;
  while i < Len - 1 do
  begin
    sum := sum + (LongWord(p[i]) shl 8) + p[i + 1];
    Inc(i, 2);
  end;
  if Odd(Len) then sum := sum + (LongWord(p[Len - 1]) shl 8);
  while (sum shr 16) <> 0 do sum := (sum and $FFFF) + (sum shr 16);
  Result := Word(not sum);
end;

{ unprivileged ICMP echo (Linux "ping sockets"); Rtt in ms, -1 if no answer, -2 if not allowed }
function IcmpPing(const Ip: string; TimeoutMs: Integer): Double;
var
  fd: cint;
  pkt: array[0..15] of Byte;
  sa: TInetSockAddr;
  t0: Int64;
  buf: array[0..1499] of Byte;
  n, remain: Integer;
  cs: Word;
begin
  Result := -2;
  fd := fpSocket(AF_INET, SOCK_DGRAM, 1 { IPPROTO_ICMP });
  if fd < 0 then Exit;
  Result := -1;
  try
    FillChar(pkt, SizeOf(pkt), 0);
    pkt[0] := 8;
    pkt[6] := 0;
    pkt[7] := 1;
    Move(PChar('linxterm')^, pkt[8], 8);
    cs := Checksum(pkt, SizeOf(pkt));
    pkt[2] := cs shr 8;
    pkt[3] := cs and $FF;
    FillChar(sa, SizeOf(sa), 0);
    sa.sin_family := AF_INET;
    sa.sin_addr := StrToNetAddr(Ip);
    t0 := g_get_monotonic_time;
    if fpSendTo(fd, @pkt, SizeOf(pkt), 0, @sa, SizeOf(sa)) < 0 then Exit;
    remain := TimeoutMs;
    while remain > 0 do
    begin
      if WaitFd(fd, False, remain) <= 0 then Exit;
      n := fpRecv(fd, @buf, SizeOf(buf), 0);
      if (n >= 8) and (buf[0] = 0) then
      begin
        Result := (g_get_monotonic_time - t0) / 1000;
        Exit;
      end;
      remain := TimeoutMs - Integer((g_get_monotonic_time - t0) div 1000);
    end;
  finally
    fpClose(fd);
  end;
end;

function IpToNum(const Ip: string; out N: LongWord): Boolean;
var
  parts: TStringArray;
  i, v: Integer;
begin
  Result := False;
  parts := SplitString(Trim(Ip), '.');
  if Length(parts) <> 4 then Exit;
  N := 0;
  for i := 0 to 3 do
  begin
    v := StrToIntDef(parts[i], -1);
    if (v < 0) or (v > 255) then Exit;
    N := (N shl 8) or LongWord(v);
  end;
  Result := True;
end;

function NumToIp(N: LongWord): string;
begin
  Result := Format('%d.%d.%d.%d', [(N shr 24) and 255, (N shr 16) and 255, (N shr 8) and 255, N and 255]);
end;

function LocalIPv4Cidr: string;
var
  o, line: string;
  lines, f: TStringArray;
  i: Integer;
begin
  Result := '192.168.1.0/24';
  if RunCapture(['ip', '-4', '-o', 'addr', 'show', 'scope', 'global'], o) <> 0 then Exit;
  lines := SplitString(o, #10);
  for line in lines do
  begin
    f := SplitString(DelSpace1(Trim(line)), ' ');
    for i := 0 to High(f) - 1 do
      if f[i] = 'inet' then
      begin
        Result := f[i + 1];
        Exit;
      end;
  end;
end;

function ParseRange(const S: string; out First, Last: LongWord): Boolean;
var
  p, bits: Integer;
  a, b, mask: LongWord;
  t: string;
begin
  Result := False;
  t := Trim(S);
  p := Pos('/', t);
  if p > 0 then
  begin
    if not IpToNum(Copy(t, 1, p - 1), a) then Exit;
    bits := StrToIntDef(Copy(t, p + 1, 3), -1);
    if (bits < 16) or (bits > 32) then Exit;
    if bits = 32 then mask := $FFFFFFFF else mask := not ((LongWord(1) shl (32 - bits)) - 1);
    First := a and mask;
    Last := First or not mask;
    if bits < 31 then
    begin
      Inc(First);
      Dec(Last);
    end;
    Exit(True);
  end;
  p := Pos('-', t);
  if p > 0 then
  begin
    if not IpToNum(Copy(t, 1, p - 1), a) then Exit;
    if Pos('.', Copy(t, p + 1, MaxInt)) > 0 then
    begin
      if not IpToNum(Copy(t, p + 1, MaxInt), b) then Exit;
    end
    else
      b := (a and $FFFFFF00) or LongWord(StrToIntDef(Copy(t, p + 1, 3), 0) and 255);
    if b < a then Exit;
    First := a;
    Last := b;
    Exit((Last - First) < 65536);
  end;
  if IpToNum(t, a) then
  begin
    First := a;
    Last := a;
    Exit(True);
  end;
end;

function ServiceName(Port: Integer): string;
const
  Known: array[0..41] of Integer = (20, 21, 22, 23, 25, 53, 67, 69, 80, 88, 110, 111, 123, 135, 139, 143, 161, 389,
    443, 445, 465, 514, 587, 631, 636, 873, 993, 995, 1194, 1433, 1521, 1883, 2049, 2222, 3306, 3389, 5432, 5900,
    6379, 8080, 8443, 9090);
  Names: array[0..41] of string = ('ftp-data', 'ftp', 'ssh', 'telnet', 'smtp', 'dns', 'dhcp', 'tftp', 'http',
    'kerberos', 'pop3', 'rpcbind', 'ntp', 'msrpc', 'netbios', 'imap', 'snmp', 'ldap', 'https', 'smb', 'smtps',
    'syslog', 'submission', 'ipp (printing)', 'ldaps', 'rsync', 'imaps', 'pop3s', 'openvpn', 'mssql', 'oracle',
    'mqtt', 'nfs', 'ssh-alt', 'mysql', 'rdp', 'postgres', 'vnc', 'redis', 'http-alt', 'https-alt', 'cockpit');
var
  i: Integer;
begin
  for i := 0 to High(Known) do
    if Known[i] = Port then Exit(Names[i]);
  Result := '';
end;

{ ---------------------------------------------------------------- scanner job (shared by both scanners) }

type
  TScanResult = record
    Ip, Name, Info: string;
    Ports: string;
    Ping: string;
    Port: Integer;
  end;

  TScanJob = class
  public
    Lock: TCriticalSection;
    Targets: array of LongWord;   { IPs (network scan) }
    Ports: array of Integer;
    PortMode: Boolean;            { port scan of a single host }
    HostIp: string;
    NextIndex: Integer;
    Total: Integer;
    DoneCount: Integer;
    Results: array of TScanResult;
    ResultCount: Integer;
    Cancelled: Boolean;
    Threads: Integer;
    WindowAlive: Boolean;
    constructor Create;
    destructor Destroy; override;
    function Take(out Index: Integer): Boolean;
    procedure AddResult(const R: TScanResult);
    procedure ThreadDone;
  end;

  TScanThread = class(TThread)
  public
    Job: TScanJob;
    constructor Create(AJob: TScanJob);
    procedure Execute; override;
  end;

constructor TScanJob.Create;
begin
  inherited Create;
  Lock := TCriticalSection.Create;
  WindowAlive := True;
end;

destructor TScanJob.Destroy;
begin
  Lock.Free;
  inherited Destroy;
end;

function TScanJob.Take(out Index: Integer): Boolean;
begin
  Lock.Enter;
  try
    Result := (not Cancelled) and (NextIndex < Total);
    if Result then
    begin
      Index := NextIndex;
      Inc(NextIndex);
    end;
  finally
    Lock.Leave;
  end;
end;

procedure TScanJob.AddResult(const R: TScanResult);
begin
  Lock.Enter;
  try
    if ResultCount >= Length(Results) then SetLength(Results, ResultCount * 2 + 16);
    Results[ResultCount] := R;
    Inc(ResultCount);
  finally
    Lock.Leave;
  end;
end;

procedure TScanJob.ThreadDone;
var
  freeIt: Boolean;
begin
  Lock.Enter;
  Dec(Threads);
  freeIt := (Threads = 0) and not WindowAlive;
  Lock.Leave;
  if freeIt then Free;
end;

constructor TScanThread.Create(AJob: TScanJob);
begin
  Job := AJob;
  FreeOnTerminate := True;
  inherited Create(False);
end;

procedure TScanThread.Execute;
var
  idx, i, st: Integer;
  ip, open: string;
  r: TScanResult;
  alive: Boolean;
  rtt: Double;
begin
  try
    while Job.Take(idx) do
    begin
      if Job.PortMode then
      begin
        st := ProbePort(Job.HostIp, Job.Ports[idx], 800);
        if st = 1 then
        begin
          r := Default(TScanResult);
          r.Ip := Job.HostIp;
          r.Port := Job.Ports[idx];
          r.Name := ServiceName(Job.Ports[idx]);
          Job.AddResult(r);
        end;
      end
      else
      begin
        ip := NumToIp(Job.Targets[idx]);
        alive := False;
        rtt := IcmpPing(ip, 700);
        if rtt >= 0 then alive := True;
        open := '';
        for i := 0 to High(Job.Ports) do
        begin
          if Job.Cancelled then Break;
          st := ProbePort(ip, Job.Ports[i], 500);
          if st >= 0 then alive := True;
          if st = 1 then open := open + IntToStr(Job.Ports[i]) + ' ';
        end;
        if alive then
        begin
          r := Default(TScanResult);
          r.Ip := ip;
          r.Ports := Trim(open);
          if rtt >= 0 then r.Ping := FormatFloat('0.0', rtt) + ' ms' else r.Ping := '-';
          r.Name := ReverseLookup(ip);
          Job.AddResult(r);
        end;
      end;
      Job.Lock.Enter;
      Inc(Job.DoneCount);
      Job.Lock.Leave;
    end;
  finally
    Job.ThreadDone;
  end;
end;

{ ---------------------------------------------------------------- network scanner window }

type
  TNetScanWindow = class(TToolWindow)
  public
    Range, PortsE, Store, View, Progress, StartBtn, Status: Pointer;
    Job: TScanJob;
    Shown: Integer;
    Timer: guint;
    PortMode: Boolean;
    constructor Create(APortMode: Boolean);
    procedure Start;
    procedure Stop;
    procedure Poll;
    procedure Closed; override;
  end;

function ScanPollCb(data: gpointer): gboolean; cdecl;
begin
  TNetScanWindow(data).Poll;
  Result := TNetScanWindow(data).Timer <> 0;
end;

procedure ScanStartCb(b: Pointer; data: gpointer); cdecl;
var
  w: TNetScanWindow;
begin
  w := TNetScanWindow(data);
  if w.Job <> nil then w.Stop else w.Start;
end;

procedure ScanRowActivated(view: Pointer; path: Pointer; col: Pointer; data: gpointer); cdecl;
var
  w: TNetScanWindow;
  ip: string;
  s: TSession;
begin
  w := TNetScanWindow(data);
  ip := ListSelectedText(w.View, 0);
  if ip = '' then Exit;
  s := TSession.Create(skSSH);
  try
    s.Host := ip;
    if w.PortMode then
    begin
      ip := ListSelectedText(w.View, 1);
      case StrToIntDef(ip, 22) of
        23: begin s.Kind := skTelnet; s.Port := 23; end;
        3389: begin s.Kind := skRDP; s.Port := 3389; end;
        5900..5910: begin s.Kind := skVNC; s.Port := StrToIntDef(ip, 5900); end;
        21: begin s.Kind := skFTP; s.Port := 21; end;
        80, 443, 8080: begin s.Kind := skBrowser; s.Url := IfThen(ip = '443', 'https://', 'http://') + s.Host + ':' + ip; end;
      else
        s.Port := StrToIntDef(ip, 22);
      end;
    end;
    App.OpenSession(s);
  finally
    s.Free;
  end;
end;

constructor TNetScanWindow.Create(APortMode: Boolean);
var
  vbox, grid, scroll: Pointer;
begin
  PortMode := APortMode;
  if PortMode then
    inherited Create('Ports scanner', 'zenmap', 620, 520)
  else
    inherited Create('Network scanner', 'ipscan', 820, 560);
  vbox := gtk_box_new(GTK_ORIENTATION_VERTICAL, 6);
  SetMargins(vbox, 10);
  grid := gtk_grid_new;
  gtk_grid_set_row_spacing(grid, 6);
  gtk_grid_set_column_spacing(grid, 8);
  Range := gtk_entry_new;
  PortsE := gtk_entry_new;
  if PortMode then
  begin
    gtk_grid_attach(grid, NewLabel('Host', 1), 0, 0, 1, 1);
    SetEntryText(Range, '127.0.0.1');
    gtk_grid_attach(grid, NewLabel('Ports', 1), 0, 1, 1, 1);
    SetEntryText(PortsE, '1-1024');
  end
  else
  begin
    gtk_grid_attach(grid, NewLabel('IP range', 1), 0, 0, 1, 1);
    SetEntryText(Range, LocalIPv4Cidr);
    gtk_grid_attach(grid, NewLabel('Ports to test', 1), 0, 1, 1, 1);
    SetEntryText(PortsE, '22,23,80,443,445,3389,5900');
  end;
  gtk_widget_set_hexpand(Range, True);
  gtk_grid_attach(grid, Range, 1, 0, 1, 1);
  gtk_grid_attach(grid, PortsE, 1, 1, 1, 1);
  StartBtn := NewIconButton('media-playback-start', '_Start scan', '', 16);
  Connect(StartBtn, 'clicked', @ScanStartCb, Self);
  gtk_grid_attach(grid, StartBtn, 2, 0, 1, 2);
  gtk_box_pack_start(vbox, grid, False, False, 0);
  if PortMode then
    View := NewListView(['Host', 'Port', 'Service'], Store)
  else
    View := NewListView(['IP address', 'Host name', 'Ping', 'Open ports'], Store);
  Connect(View, 'row-activated', @ScanRowActivated, Self);
  scroll := NewScrolled(View);
  gtk_box_pack_start(vbox, scroll, True, True, 0);
  Progress := gtk_progress_bar_new;
  gtk_progress_bar_set_show_text(Progress, True);
  gtk_box_pack_start(vbox, Progress, False, False, 0);
  Status := NewMarkupLabel('<small>Double-click a result to open a session.</small>', 0);
  gtk_box_pack_start(vbox, Status, False, False, 0);
  gtk_container_add(Win, vbox);
  gtk_widget_show_all(Win);
end;

function ParsePorts(const S: string; out Ports: TStringList): Boolean;
var
  parts: TStringArray;
  p: string;
  a, b, i, d: Integer;
begin
  Ports := TStringList.Create;
  Result := False;
  parts := SplitString(StringReplace(S, ' ', '', [rfReplaceAll]), ',');
  for p in parts do
  begin
    if p = '' then Continue;
    d := Pos('-', p);
    if d > 0 then
    begin
      a := StrToIntDef(Copy(p, 1, d - 1), -1);
      b := StrToIntDef(Copy(p, d + 1, 6), -1);
    end
    else
    begin
      a := StrToIntDef(p, -1);
      b := a;
    end;
    if (a < 1) or (b > 65535) or (b < a) then Exit;
    for i := a to b do Ports.Add(IntToStr(i));
  end;
  Result := Ports.Count > 0;
end;

procedure TNetScanWindow.Start;
var
  first, last, n: LongWord;
  ports: TStringList;
  i, nthreads: Integer;
  ip: string;
begin
  if not ParsePorts(EntryText(PortsE), ports) then
  begin
    ports.Free;
    MsgWarning('Invalid ports', 'Use a list like "22,80,443" or a range like "1-1024".');
    Exit;
  end;
  Job := TScanJob.Create;
  SetLength(Job.Ports, ports.Count);
  for i := 0 to ports.Count - 1 do Job.Ports[i] := StrToInt(ports[i]);
  ports.Free;
  if PortMode then
  begin
    if not ResolveHost(Trim(EntryText(Range)), ip) then
    begin
      MsgWarning('Unknown host', EntryText(Range));
      FreeAndNil(Job);
      Exit;
    end;
    Job.PortMode := True;
    Job.HostIp := ip;
    Job.Total := Length(Job.Ports);
    nthreads := Min(64, Job.Total);
  end
  else
  begin
    if not ParseRange(EntryText(Range), first, last) then
    begin
      MsgWarning('Invalid IP range', 'Examples: 192.168.1.0/24, 10.0.0.1-50, 192.168.1.10-192.168.1.40');
      FreeAndNil(Job);
      Exit;
    end;
    SetLength(Job.Targets, last - first + 1);
    n := 0;
    while first + n <= last do
    begin
      Job.Targets[n] := first + n;
      Inc(n);
      if n >= LongWord(Length(Job.Targets)) then Break;
    end;
    Job.Total := Length(Job.Targets);
    nthreads := Min(48, Job.Total);
  end;
  gtk_list_store_clear(Store);
  Shown := 0;
  Job.Threads := nthreads;
  for i := 1 to nthreads do TScanThread.Create(Job);
  gtk_button_set_label(StartBtn, '_Stop');
  Timer := g_timeout_add(250, @ScanPollCb, Self);
end;

procedure TNetScanWindow.Stop;
begin
  if Job <> nil then Job.Cancelled := True;
end;

procedure TNetScanWindow.Poll;
var
  i, done, total, cnt: Integer;
  r: TScanResult;
  finished: Boolean;
begin
  if Job = nil then Exit;
  Job.Lock.Enter;
  try
    cnt := Job.ResultCount;
    done := Job.DoneCount;
    total := Job.Total;
    finished := Job.Threads = 0;
    for i := Shown to cnt - 1 do
    begin
      r := Job.Results[i];
      if PortMode then
        ListAdd(Store, [r.Ip, IntToStr(r.Port), r.Name])
      else
        ListAdd(Store, [r.Ip, r.Name, r.Ping, r.Ports]);
    end;
    Shown := cnt;
  finally
    Job.Lock.Leave;
  end;
  if total > 0 then gtk_progress_bar_set_fraction(Progress, done / total);
  gtk_progress_bar_set_text(Progress, PChar(Format('%d / %d scanned  -  %d found', [done, total, cnt])));
  if finished then
  begin
    g_source_remove(Timer);
    Timer := 0;
    FreeAndNil(Job);
    gtk_button_set_label(StartBtn, '_Start scan');
  end;
end;

procedure TNetScanWindow.Closed;
var
  freeJob: Boolean;
begin
  if Timer <> 0 then g_source_remove(Timer);
  Timer := 0;
  if Job <> nil then
  begin
    Job.Lock.Enter;
    Job.Cancelled := True;
    Job.WindowAlive := False;
    freeJob := Job.Threads = 0;
    Job.Lock.Leave;
    if freeJob then Job.Free;
    Job := nil;
  end;
  inherited Closed;
end;

{ ---------------------------------------------------------------- ping graph }

type
  TPingWindow = class(TToolWindow)
  public
    HostE, Area, Stats, StartBtn: Pointer;
    Proc: TChildProcess;
    Samples: array of Double;   { -1 = lost }
    Sent, Received: Integer;
    MinT, MaxT, SumT: Double;
    constructor Create;
    procedure Start;
    procedure Stop;
    procedure Line(Sender: TChildProcess; const L: string; IsErr: Boolean);
    procedure Exited(Sender: TChildProcess; Status: Integer);
    procedure Draw(cr: Pcairo_t);
    procedure Closed; override;
  end;

procedure PingStartCb(b: Pointer; data: gpointer); cdecl;
begin
  if (TPingWindow(data).Proc <> nil) and TPingWindow(data).Proc.Running then
    TPingWindow(data).Stop
  else
    TPingWindow(data).Start;
end;

function PingDrawCb(w: Pointer; cr: Pointer; data: gpointer): gboolean; cdecl;
begin
  TPingWindow(data).Draw(cr);
  Result := False;
end;

constructor TPingWindow.Create;
var
  vbox, hb: Pointer;
begin
  inherited Create('Graphical ping', 'etherape', 760, 420);
  vbox := gtk_box_new(GTK_ORIENTATION_VERTICAL, 6);
  SetMargins(vbox, 10);
  hb := gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 6);
  gtk_box_pack_start(hb, NewLabel('Host'), False, False, 0);
  HostE := gtk_entry_new;
  SetEntryText(HostE, '8.8.8.8');
  gtk_box_pack_start(hb, HostE, True, True, 0);
  StartBtn := NewIconButton('media-playback-start', '_Start', '', 16);
  Connect(StartBtn, 'clicked', @PingStartCb, Self);
  gtk_box_pack_start(hb, StartBtn, False, False, 0);
  gtk_box_pack_start(vbox, hb, False, False, 0);
  Area := gtk_drawing_area_new;
  gtk_widget_set_size_request(Area, 600, 250);
  Connect(Area, 'draw', @PingDrawCb, Self);
  gtk_box_pack_start(vbox, Area, True, True, 0);
  Stats := NewLabel('', 0);
  gtk_box_pack_start(vbox, Stats, False, False, 0);
  gtk_container_add(Win, vbox);
  gtk_widget_show_all(Win);
end;

procedure TPingWindow.Start;
var
  err, h: string;
begin
  h := Trim(EntryText(HostE));
  if h = '' then Exit;
  SetLength(Samples, 0);
  Sent := 0;
  Received := 0;
  MinT := MaxDouble;
  MaxT := 0;
  SumT := 0;
  if Proc <> nil then FreeAndNil(Proc);
  Proc := TChildProcess.Create;
  Proc.OnLine := @Line;
  Proc.OnExit := @Exited;
  if not Proc.Start(['ping', '-n', '-O', '-i', '1', h], ['LC_ALL=C'], HomeDir, False, err) then
  begin
    MsgError('Unable to start ping', err);
    Exit;
  end;
  gtk_button_set_label(StartBtn, '_Stop');
  gtk_label_set_text(Stats, PChar('Pinging ' + h + '...'));
end;

procedure TPingWindow.Stop;
begin
  if (Proc <> nil) and Proc.Running then Proc.Signal(SIGINT);
end;

procedure TPingWindow.Line(Sender: TChildProcess; const L: string; IsErr: Boolean);
var
  p, q: Integer;
  t: Double;
  txt: string;
begin
  if IsErr then
  begin
    gtk_label_set_text(Stats, PChar(L));
    Exit;
  end;
  p := Pos('time=', L);
  if p > 0 then
  begin
    q := PosEx(' ', L, p);
    txt := Copy(L, p + 5, q - p - 5);
    t := StrToFloatDef(StringReplace(txt, '.', DefaultFormatSettings.DecimalSeparator, []), -1);
    Inc(Sent);
    if t >= 0 then
    begin
      Inc(Received);
      MinT := Min(MinT, t);
      MaxT := Max(MaxT, t);
      SumT := SumT + t;
    end;
    SetLength(Samples, Length(Samples) + 1);
    Samples[High(Samples)] := t;
  end
  else if Pos('no answer yet', L) > 0 then
  begin
    Inc(Sent);
    SetLength(Samples, Length(Samples) + 1);
    Samples[High(Samples)] := -1;
  end
  else
    Exit;
  if Length(Samples) > 300 then Samples := Copy(Samples, Length(Samples) - 300, 300);
  if Received > 0 then
    gtk_label_set_text(Stats, PChar(Format('Sent %d   Received %d   Lost %.0f%%   Min %.1f ms   Avg %.1f ms   Max %.1f ms',
      [Sent, Received, 100.0 * (Sent - Received) / Max(1, Sent), MinT, SumT / Received, MaxT])))
  else
    gtk_label_set_text(Stats, PChar(Format('Sent %d   Received 0   Lost 100%%', [Sent])));
  gtk_widget_queue_draw(Area);
end;

procedure TPingWindow.Exited(Sender: TChildProcess; Status: Integer);
begin
  gtk_button_set_label(StartBtn, '_Start');
  if (Status <> 0) and (Sent = 0) then
    gtk_label_set_text(Stats, PChar('ping failed (code ' + IntToStr(Status) + '): unknown host or network unreachable'));
end;

procedure TPingWindow.Draw(cr: Pcairo_t);
var
  w, h, i, n: Integer;
  maxv, x, y, step: Double;
  lbl: string;
begin
  w := gtk_widget_get_allocated_width(Area);
  h := gtk_widget_get_allocated_height(Area);
  cairo_set_source_rgb(cr, 0.08, 0.09, 0.11);
  cairo_rectangle(cr, 0, 0, w, h);
  cairo_fill(cr);
  maxv := 10;
  for i := 0 to High(Samples) do
    if Samples[i] > maxv then maxv := Samples[i];
  maxv := maxv * 1.2;
  cairo_set_line_width(cr, 1);
  cairo_set_source_rgba(cr, 1, 1, 1, 0.12);
  for i := 1 to 4 do
  begin
    y := h - (h - 20) * i / 4;
    cairo_move_to(cr, 40, y);
    cairo_line_to(cr, w, y);
    cairo_stroke(cr);
  end;
  cairo_set_source_rgb(cr, 0.75, 0.75, 0.75);
  cairo_select_font_face(cr, 'Sans', CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL);
  cairo_set_font_size(cr, 10);
  for i := 1 to 4 do
  begin
    y := h - (h - 20) * i / 4;
    lbl := FormatFloat('0', maxv * i / 4) + ' ms';
    cairo_move_to(cr, 2, y + 4);
    cairo_show_text(cr, PChar(lbl));
  end;
  n := Length(Samples);
  if n = 0 then Exit;
  step := (w - 45) / 120;
  cairo_set_line_width(cr, 2);
  for i := Max(0, n - 120) to n - 1 do
  begin
    x := 42 + (i - Max(0, n - 120)) * step;
    if Samples[i] < 0 then
    begin
      cairo_set_source_rgb(cr, 0.9, 0.2, 0.2);
      cairo_rectangle(cr, x, 0, Max(2, step - 1), h);
      cairo_fill(cr);
      Continue;
    end;
    y := h - (h - 20) * Samples[i] / maxv;
    cairo_set_source_rgb(cr, 0.25, 0.85, 0.4);
    cairo_rectangle(cr, x, y, Max(2, step - 1), h - y);
    cairo_fill(cr);
  end;
end;

procedure TPingWindow.Closed;
begin
  if Proc <> nil then
  begin
    Proc.OnLine := nil;
    Proc.OnExit := nil;
    FreeAndNil(Proc);
  end;
  inherited Closed;
end;

{ ---------------------------------------------------------------- open ports }

type
  TPortsWindow = class(TToolWindow)
  public
    Store, View, Filter: Pointer;
    constructor Create;
    procedure Refresh;
  end;

procedure PortsRefreshCb(b: Pointer; data: gpointer); cdecl;
begin
  TPortsWindow(data).Refresh;
end;

constructor TPortsWindow.Create;
var
  vbox, hb, b: Pointer;
begin
  inherited Create('Open network ports', 'gnome-nettool', 860, 520);
  vbox := gtk_box_new(GTK_ORIENTATION_VERTICAL, 6);
  SetMargins(vbox, 10);
  hb := gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 6);
  Filter := gtk_search_entry_new;
  gtk_entry_set_placeholder_text(Filter, 'Filter...');
  Connect(Filter, 'search-changed', @PortsRefreshCb, Self);
  gtk_box_pack_start(hb, Filter, True, True, 0);
  b := NewIconButton('lx-refresh', '_Refresh', '', 16);
  Connect(b, 'clicked', @PortsRefreshCb, Self);
  gtk_box_pack_start(hb, b, False, False, 0);
  gtk_box_pack_start(vbox, hb, False, False, 0);
  View := NewListView(['Protocol', 'State', 'Local address', 'Port', 'Remote address', 'Process'], Store);
  gtk_box_pack_start(vbox, NewScrolled(View), True, True, 0);
  gtk_box_pack_start(vbox, NewMarkupLabel('<small>Process names of other users are only visible to root.</small>', 0), False, False, 0);
  gtk_container_add(Win, vbox);
  gtk_widget_show_all(Win);
  Refresh;
end;

procedure TPortsWindow.Refresh;
var
  o, line, local, port, proc, flt: string;
  lines, f: TStringArray;
  p, a, b: Integer;
begin
  gtk_list_store_clear(Store);
  if RunCapture(['ss', '-tulnpH'], o) <> 0 then
  begin
    ListAdd(Store, ['error', '', Trim(o), '', '', '']);
    Exit;
  end;
  flt := LowerCase(Trim(EntryText(Filter)));
  lines := SplitString(o, #10);
  for line in lines do
  begin
    if Trim(line) = '' then Continue;
    if (flt <> '') and (Pos(flt, LowerCase(line)) = 0) then Continue;
    f := SplitString(DelSpace1(Trim(line)), ' ');
    if Length(f) < 6 then Continue;
    local := f[4];
    p := LastDelimiter(':', local);
    port := Copy(local, p + 1, MaxInt);
    local := Copy(local, 1, p - 1);
    proc := '';
    if Length(f) >= 7 then
    begin
      proc := f[6];
      a := Pos('(("', proc);
      if a > 0 then
      begin
        b := PosEx('"', proc, a + 3);
        if b > 0 then proc := Copy(proc, a + 3, b - a - 3) + ' ' + Copy(proc, PosEx('pid=', proc) , 12);
      end;
    end;
    ListAdd(Store, [f[0], f[1], local, port, f[5], Trim(StringReplace(proc, ',', '', [rfReplaceAll]))]);
  end;
end;

{ ---------------------------------------------------------------- process explorer }

type
  TProcWindow = class(TToolWindow)
  public
    Store, View, Filter: Pointer;
    Timer: guint;
    Prev: TStringList;   { pid=ticks }
    PrevTime: Int64;
    constructor Create;
    procedure Refresh;
    procedure KillSelected(Sig: cint);
    procedure Closed; override;
  end;

{ numeric value of a cell: "  1234", " 12.5", "  21.5 MB" }
function CellNumber(const S: string): Double;
var
  t, num, unit_: string;
  p: Integer;
begin
  t := Trim(S);
  p := Pos(' ', t);
  if p > 0 then
  begin
    num := Copy(t, 1, p - 1);
    unit_ := UpperCase(Trim(Copy(t, p + 1, MaxInt)));
  end
  else
  begin
    num := t;
    unit_ := '';
  end;
  Result := StrToFloatDef(num, 0);
  if unit_ = 'KB' then Result := Result * 1024
  else if unit_ = 'MB' then Result := Result * 1048576
  else if unit_ = 'GB' then Result := Result * 1073741824.0
  else if unit_ = 'TB' then Result := Result * 1099511627776.0;
end;

function ProcSortFunc(model: Pointer; a, b: PGtkTreeIter; data: gpointer): gint; cdecl;
var
  pa, pb: PChar;
  col: PtrInt;
begin
  col := PtrInt(data);
  pa := nil;
  pb := nil;
  gtk_tree_model_get(model, a, col, @pa, -1);
  gtk_tree_model_get(model, b, col, @pb, -1);
  Result := CompareValue(CellNumber(TakeStr(pa)), CellNumber(TakeStr(pb)));
end;

function ProcTimerCb(data: gpointer): gboolean; cdecl;
begin
  TProcWindow(data).Refresh;
  Result := True;
end;

procedure ProcRefreshCb(b: Pointer; data: gpointer); cdecl;
begin
  TProcWindow(data).Refresh;
end;

procedure ProcTermCb(b: Pointer; data: gpointer); cdecl;
begin
  TProcWindow(data).KillSelected(SIGTERM);
end;

procedure ProcKillCb(b: Pointer; data: gpointer); cdecl;
begin
  TProcWindow(data).KillSelected(SIGKILL);
end;

constructor TProcWindow.Create;
var
  vbox, hb, b: Pointer;
begin
  inherited Create('Running processes', 'utilities-system-monitor', 900, 600);
  Prev := TStringList.Create;
  Prev.Sorted := True;
  vbox := gtk_box_new(GTK_ORIENTATION_VERTICAL, 6);
  SetMargins(vbox, 10);
  hb := gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 6);
  Filter := gtk_search_entry_new;
  gtk_entry_set_placeholder_text(Filter, 'Filter by name, user or command...');
  Connect(Filter, 'search-changed', @ProcRefreshCb, Self);
  gtk_box_pack_start(hb, Filter, True, True, 0);
  b := NewIconButton('process-stop', '_End process', 'Send SIGTERM', 16);
  Connect(b, 'clicked', @ProcTermCb, Self);
  gtk_box_pack_start(hb, b, False, False, 0);
  b := NewIconButton('lx-cancel', '_Kill', 'Send SIGKILL', 16);
  Connect(b, 'clicked', @ProcKillCb, Self);
  gtk_box_pack_start(hb, b, False, False, 0);
  gtk_box_pack_start(vbox, hb, False, False, 0);
  View := NewListView(['PID', 'Name', 'User', 'CPU %', 'Memory', 'State', 'Command'], Store);
  { numbers are sorted as numbers, not as text }
  gtk_tree_sortable_set_sort_func(Store, 0, @ProcSortFunc, Pointer(PtrInt(0)), nil);
  gtk_tree_sortable_set_sort_func(Store, 3, @ProcSortFunc, Pointer(PtrInt(3)), nil);
  gtk_tree_sortable_set_sort_func(Store, 4, @ProcSortFunc, Pointer(PtrInt(4)), nil);
  gtk_tree_sortable_set_sort_column_id(Store, 0, GTK_SORT_ASCENDING);
  gtk_box_pack_start(vbox, NewScrolled(View), True, True, 0);
  gtk_container_add(Win, vbox);
  gtk_widget_show_all(Win);
  Refresh;
  Timer := g_timeout_add(2500, @ProcTimerCb, Self);
end;

type
  TProcInfo = class
    Pid, Name, User, Cpu, Mem, State, Cmd: string;
    Seen: Boolean;
  end;

procedure TProcWindow.Refresh;
var
  sr: TSearchRec;
  pid, stat, status, cmd, name, user, flt, state, line: string;
  rss, ticks: Int64;
  uid, p, q, i, idx, n: Integer;
  f, lines: TStringArray;
  cur, procs: TStringList;
  now_: Int64;
  dt, cpu: Double;
  info: TProcInfo;
  iters: array of TGtkTreeIter;
  it: TGtkTreeIter;
  ps: PChar;
begin
  flt := LowerCase(Trim(EntryText(Filter)));
  now_ := g_get_monotonic_time;
  dt := (now_ - PrevTime) / 1000000;
  cur := TStringList.Create;      { pid -> cpu ticks, for the next refresh }
  cur.Sorted := True;
  procs := TStringList.Create;    { pid -> row }
  procs.Sorted := True;
  procs.OwnsObjects := True;
  try
    if FindFirst('/proc/*', faDirectory, sr) = 0 then
    begin
      repeat
        pid := sr.Name;
        if StrToIntDef(pid, -1) < 0 then Continue;
        if not ReadFileText('/proc/' + pid + '/stat', stat) then Continue;
        p := Pos('(', stat);
        q := LastDelimiter(')', stat);
        if (p = 0) or (q = 0) then Continue;
        name := Copy(stat, p + 1, q - p - 1);
        f := SplitString(Trim(Copy(stat, q + 2, MaxInt)), ' ');
        if Length(f) < 22 then Continue;
        state := f[0];
        ticks := StrToInt64Def(f[11], 0) + StrToInt64Def(f[12], 0);
        rss := StrToInt64Def(f[21], 0) * 4096;
        cur.AddObject(pid, TObject(PtrInt(ticks)));
        cpu := 0;
        idx := Prev.IndexOf(pid);
        if (idx >= 0) and (dt > 0) then
          cpu := (ticks - PtrInt(Prev.Objects[idx])) / 100 / dt * 100;
        if cpu < 0 then cpu := 0;
        uid := -1;
        if ReadFileText('/proc/' + pid + '/status', status) then
        begin
          lines := SplitString(status, #10);
          for line in lines do
            if Copy(line, 1, 4) = 'Uid:' then
            begin
              { "Uid:<tab>1000<tab>1000<tab>..." }
              uid := StrToIntDef(SplitString(DelSpace1(Trim(StringReplace(Copy(line, 5, MaxInt), #9, ' ',
                [rfReplaceAll]))), ' ')[0], -1);
              Break;
            end;
        end;
        user := '';
        if uid >= 0 then user := UidName(uid);
        cmd := '';
        if ReadFileText('/proc/' + pid + '/cmdline', cmd) then
          cmd := Trim(StringReplace(cmd, #0, ' ', [rfReplaceAll]));
        if (flt <> '') and (Pos(flt, LowerCase(name + ' ' + user + ' ' + cmd + ' ' + pid)) = 0) then Continue;
        info := TProcInfo.Create;
        info.Pid := Format('%7s', [pid]);
        info.Name := name;
        info.User := user;
        info.Cpu := Format('%5.1f', [cpu]);
        info.Mem := Format('%10s', [HumanSize(rss)]);
        info.State := state;
        info.Cmd := cmd;
        procs.AddObject(pid, info);
      until FindNext(sr) <> 0;
      FindClose(sr);
    end;
    { update the rows in place, so that the selection and the scroll
      position survive the periodic refresh (list store iters persist) }
    n := 0;
    iters := nil;
    if gtk_tree_model_get_iter_first(Store, @it) then
      repeat
        SetLength(iters, n + 1);
        iters[n] := it;
        Inc(n);
      until not gtk_tree_model_iter_next(Store, @it);
    for i := 0 to n - 1 do
    begin
      ps := nil;
      gtk_tree_model_get(Store, @iters[i], 0, @ps, -1);
      idx := procs.IndexOf(Trim(TakeStr(ps)));
      if idx < 0 then
        gtk_list_store_remove(Store, @iters[i])
      else
      begin
        info := TProcInfo(procs.Objects[idx]);
        info.Seen := True;
        gtk_list_store_set(Store, @iters[i], 1, PChar(info.Name), 2, PChar(info.User), 3, PChar(info.Cpu),
          4, PChar(info.Mem), 5, PChar(info.State), 6, PChar(info.Cmd), -1);
      end;
    end;
    for i := 0 to procs.Count - 1 do
    begin
      info := TProcInfo(procs.Objects[i]);
      if not info.Seen then
        ListAdd(Store, [info.Pid, info.Name, info.User, info.Cpu, info.Mem, info.State, info.Cmd]);
    end;
  finally
    procs.Free;
    Prev.Free;
    Prev := cur;
  end;
  PrevTime := now_;
end;

procedure TProcWindow.KillSelected(Sig: cint);
var
  pid: Integer;
  name: string;
begin
  pid := StrToIntDef(Trim(ListSelectedText(View, 0)), 0);
  name := ListSelectedText(View, 1);
  if pid <= 0 then Exit;
  if not AskYesNo(IfThen(Sig = SIGKILL, 'Kill', 'End') + ' process ' + IntToStr(pid) + ' (' + name + ')?', '') then Exit;
  if fpKill(pid, Sig) <> 0 then
    MsgError('Unable to signal the process', SysErrorMessage(fpGetErrno))
  else
    Refresh;
end;

procedure TProcWindow.Closed;
begin
  if Timer <> 0 then g_source_remove(Timer);
  Timer := 0;
  Prev.Free;
  inherited Closed;
end;

{ ---------------------------------------------------------------- SSH key generator }

type
  TKeygenWindow = class(TToolWindow)
  public
    TypeC, Comment, Pass1, Pass2, FileE, PubView: Pointer;
    constructor Create;
    procedure Generate;
    procedure CopyPub;
    procedure CopyToServer;
  end;

procedure KgGenCb(b: Pointer; data: gpointer); cdecl; begin TKeygenWindow(data).Generate; end;
procedure KgCopyCb(b: Pointer; data: gpointer); cdecl; begin TKeygenWindow(data).CopyPub; end;
procedure KgServerCb(b: Pointer; data: gpointer); cdecl; begin TKeygenWindow(data).CopyToServer; end;
procedure KgTypeCb(c: Pointer; data: gpointer); cdecl;
var
  w: TKeygenWindow;
  t: string;
begin
  w := TKeygenWindow(data);
  t := CStr(gtk_combo_box_get_active_id(c));
  if Pos('rsa', t) = 1 then t := 'rsa' else if Pos('ecdsa', t) = 1 then t := 'ecdsa';
  SetEntryText(w.FileE, HomeDir + '/.ssh/id_' + t);
end;

constructor TKeygenWindow.Create;
var
  grid, b, hb: Pointer;
begin
  inherited Create('SSH key generator', 'seahorse', 640, 520);
  grid := gtk_grid_new;
  gtk_grid_set_row_spacing(grid, 8);
  gtk_grid_set_column_spacing(grid, 10);
  SetMargins(grid, 14);
  gtk_grid_attach(grid, NewLabel('Key type', 1), 0, 0, 1, 1);
  TypeC := gtk_combo_box_text_new;
  gtk_combo_box_text_append(TypeC, 'ed25519', 'Ed25519 (recommended)');
  gtk_combo_box_text_append(TypeC, 'rsa4096', 'RSA 4096 bits');
  gtk_combo_box_text_append(TypeC, 'rsa2048', 'RSA 2048 bits');
  gtk_combo_box_text_append(TypeC, 'ecdsa521', 'ECDSA 521 bits');
  gtk_combo_box_set_active(TypeC, 0);
  Connect(TypeC, 'changed', @KgTypeCb, Self);
  gtk_grid_attach(grid, TypeC, 1, 0, 2, 1);
  gtk_grid_attach(grid, NewLabel('Comment', 1), 0, 1, 1, 1);
  Comment := gtk_entry_new;
  SetEntryText(Comment, UserName + '@' + CStr(g_get_host_name));
  gtk_grid_attach(grid, Comment, 1, 1, 2, 1);
  gtk_grid_attach(grid, NewLabel('Passphrase', 1), 0, 2, 1, 1);
  Pass1 := gtk_entry_new;
  gtk_entry_set_visibility(Pass1, False);
  gtk_entry_set_placeholder_text(Pass1, 'empty = no passphrase');
  gtk_grid_attach(grid, Pass1, 1, 2, 2, 1);
  gtk_grid_attach(grid, NewLabel('Confirm', 1), 0, 3, 1, 1);
  Pass2 := gtk_entry_new;
  gtk_entry_set_visibility(Pass2, False);
  gtk_grid_attach(grid, Pass2, 1, 3, 2, 1);
  gtk_grid_attach(grid, NewLabel('Save as', 1), 0, 4, 1, 1);
  FileE := gtk_entry_new;
  SetEntryText(FileE, HomeDir + '/.ssh/id_ed25519');
  gtk_widget_set_hexpand(FileE, True);
  gtk_grid_attach(grid, FileE, 1, 4, 2, 1);
  b := NewIconButton('lx-check', '_Generate', '', 16);
  Connect(b, 'clicked', @KgGenCb, Self);
  gtk_grid_attach(grid, b, 1, 5, 1, 1);
  gtk_grid_attach(grid, NewLabel('Public key', 0), 0, 6, 3, 1);
  PubView := gtk_text_view_new;
  gtk_text_view_set_editable(PubView, False);
  gtk_text_view_set_monospace(PubView, True);
  gtk_text_view_set_wrap_mode(PubView, GTK_WRAP_CHAR);
  b := NewScrolled(PubView);
  gtk_widget_set_vexpand(b, True);
  gtk_grid_attach(grid, b, 0, 7, 3, 1);
  hb := gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 6);
  b := NewIconButton('edit-copy', '_Copy public key', '', 16);
  Connect(b, 'clicked', @KgCopyCb, Self);
  gtk_box_pack_start(hb, b, False, False, 0);
  b := NewIconButton('network-server', 'Install it on a _server (ssh-copy-id)...', '', 16);
  Connect(b, 'clicked', @KgServerCb, Self);
  gtk_box_pack_start(hb, b, False, False, 0);
  gtk_grid_attach(grid, hb, 0, 8, 3, 1);
  gtk_container_add(Win, grid);
  gtk_widget_show_all(Win);
end;

procedure TKeygenWindow.Generate;
var
  id, typ, bits, fn, o, pub: string;
begin
  if EntryText(Pass1) <> EntryText(Pass2) then
  begin
    MsgWarning('The passphrases do not match', '');
    Exit;
  end;
  fn := Trim(EntryText(FileE));
  if fn = '' then Exit;
  if FileExists(fn) then
  begin
    if not AskYesNo('The key "' + fn + '" already exists', 'Overwrite it? The old key will be lost.') then Exit;
    DeleteFile(fn);
    DeleteFile(fn + '.pub');
  end;
  ForceDirectories(ExtractFileDir(fn));
  fpChmod(ExtractFileDir(fn), &700);
  id := CStr(gtk_combo_box_get_active_id(TypeC));
  bits := '';
  if id = 'ed25519' then typ := 'ed25519'
  else if id = 'rsa4096' then begin typ := 'rsa'; bits := '4096'; end
  else if id = 'rsa2048' then begin typ := 'rsa'; bits := '2048'; end
  else begin typ := 'ecdsa'; bits := '521'; end;
  if bits <> '' then
    RunCapture(['ssh-keygen', '-q', '-t', typ, '-b', bits, '-C', EntryText(Comment), '-N', EntryText(Pass1), '-f', fn], o)
  else
    RunCapture(['ssh-keygen', '-q', '-t', typ, '-C', EntryText(Comment), '-N', EntryText(Pass1), '-f', fn], o);
  if ReadFileText(fn + '.pub', pub) then
  begin
    pub := Trim(pub);
    gtk_text_buffer_set_text(gtk_text_view_get_buffer(PubView), PChar(pub), Length(pub));
    App.SetStatus('SSH key pair created: ' + fn);
  end
  else
    MsgError('ssh-keygen failed', Trim(o));
end;

procedure TKeygenWindow.CopyPub;
var
  t: string;
begin
  t := TextBufferText(gtk_text_view_get_buffer(PubView));
  if t <> '' then
    gtk_clipboard_set_text(gtk_clipboard_get(GDK_SELECTION_CLIPBOARD), PChar(t), -1);
end;

procedure TKeygenWindow.CopyToServer;
var
  target, fn: string;
begin
  fn := Trim(EntryText(FileE)) + '.pub';
  if not FileExists(fn) then
  begin
    MsgWarning('Generate the key first', fn + ' does not exist.');
    Exit;
  end;
  target := UserName + '@';
  if not InputQuery('Install the public key', 'Server (user@host or user@host:port):', target) then Exit;
  target := Trim(target);
  if (target = '') or (target[Length(target)] = '@') then Exit;
  if (Pos(':', target) > 0) then
    App.RunCommandTab('ssh-copy-id ' + target, 'seahorse', ['ssh-copy-id', '-i', fn, '-p',
      Copy(target, Pos(':', target) + 1, 6), Copy(target, 1, Pos(':', target) - 1)])
  else
    App.RunCommandTab('ssh-copy-id ' + target, 'seahorse', ['ssh-copy-id', '-i', fn, target]);
end;

{ ---------------------------------------------------------------- diff }

type
  TDiffWindow = class(TToolWindow)
  public
    A, B, View, Store, Folder: Pointer;
    Folders: Boolean;
    constructor Create(AFolders: Boolean);
    procedure Compare;
  end;

procedure DiffCompareCb(btn: Pointer; data: gpointer); cdecl; begin TDiffWindow(data).Compare; end;
procedure DiffBrowseCb(btn: Pointer; data: gpointer); cdecl;
var
  w: TDiffWindow;
  e: Pointer;
  fn: string;
begin
  w := TDiffWindow(g_object_get_data(btn, 'win'));
  e := data;
  if w.Folders then
  begin
    if ChooseFolder('Choose a folder', HomeDir, fn) then SetEntryText(e, fn);
  end
  else if ChooseOpenFile('Choose a file', HomeDir, fn) then
    SetEntryText(e, fn);
end;

constructor TDiffWindow.Create(AFolders: Boolean);
var
  vbox, grid, btn, buf: Pointer;
  i: Integer;
  e: Pointer;
begin
  Folders := AFolders;
  if Folders then
    inherited Create('Compare folders', 'kdiff3', 860, 600)
  else
    inherited Create('Compare files', 'meld', 980, 680);
  vbox := gtk_box_new(GTK_ORIENTATION_VERTICAL, 6);
  SetMargins(vbox, 10);
  grid := gtk_grid_new;
  gtk_grid_set_row_spacing(grid, 6);
  gtk_grid_set_column_spacing(grid, 6);
  A := gtk_entry_new;
  B := gtk_entry_new;
  for i := 0 to 1 do
  begin
    if i = 0 then e := A else e := B;
    gtk_widget_set_hexpand(e, True);
    gtk_grid_attach(grid, NewLabel(IfThen(i = 0, 'First', 'Second') + IfThen(Folders, ' folder', ' file'), 1), 0, i, 1, 1);
    gtk_grid_attach(grid, e, 1, i, 1, 1);
    btn := NewFlatIconButton('document-open', 'Browse...', 16);
    g_object_set_data(btn, 'win', Self);
    Connect(btn, 'clicked', @DiffBrowseCb, e);
    gtk_grid_attach(grid, btn, 2, i, 1, 1);
  end;
  btn := NewIconButton('kdiff3', '_Compare', '', 16);
  Connect(btn, 'clicked', @DiffCompareCb, Self);
  gtk_grid_attach(grid, btn, 3, 0, 1, 2);
  gtk_box_pack_start(vbox, grid, False, False, 0);
  if Folders then
    View := NewListView(['Difference', 'Path'], Store)
  else
  begin
    View := gtk_text_view_new;
    gtk_text_view_set_editable(View, False);
    gtk_text_view_set_monospace(View, True);
    buf := gtk_text_view_get_buffer(View);
    gtk_text_buffer_create_tag(buf, 'add', 'background', '#d7f5dd', 'foreground', '#0b5d1e', nil);
    gtk_text_buffer_create_tag(buf, 'del', 'background', '#fbdcdc', 'foreground', '#8e1010', nil);
    gtk_text_buffer_create_tag(buf, 'hunk', 'foreground', '#1d5fbf', 'weight', PANGO_WEIGHT_BOLD, nil);
    gtk_text_buffer_create_tag(buf, 'head', 'foreground', '#666666', nil);
  end;
  gtk_box_pack_start(vbox, NewScrolled(View), True, True, 0);
  gtk_container_add(Win, vbox);
  gtk_widget_show_all(Win);
end;

procedure TDiffWindow.Compare;
var
  fa, fb, o, line, tag, kind: string;
  rc: Integer;
  lines: TStringArray;
  buf: Pointer;
  it: TGtkTextIter;
begin
  fa := Trim(EntryText(A));
  fb := Trim(EntryText(B));
  if (fa = '') or (fb = '') then Exit;
  if Folders then
  begin
    gtk_list_store_clear(Store);
    rc := RunCapture(['diff', '-rq', '--no-dereference', fa, fb], o);
    if rc = 0 then
    begin
      ListAdd(Store, ['identical', 'The two folders have the same content']);
      Exit;
    end;
    lines := SplitString(o, #10);
    for line in lines do
    begin
      if Trim(line) = '' then Continue;
      if Copy(line, 1, 8) = 'Only in ' then
      begin
        if Pos(fa, line) = 9 then kind := 'only in first' else kind := 'only in second';
        ListAdd(Store, [kind, StringReplace(Copy(line, 9, MaxInt), ': ', '/', [])]);
      end
      else if Copy(line, 1, 6) = 'Files ' then
        ListAdd(Store, ['different', Copy(line, 7, Pos(' and ', line) - 7)])
      else
        ListAdd(Store, ['note', line]);
    end;
    Exit;
  end;
  rc := RunCapture(['diff', '-u', fa, fb], o);
  buf := gtk_text_view_get_buffer(View);
  gtk_text_buffer_set_text(buf, '', 0);
  if rc = 0 then
  begin
    TextViewAppend(View, 'The two files are identical.'#10, 'head');
    Exit;
  end;
  lines := SplitString(o, #10);
  { insert everything first and scroll once (fast with big diffs) }
  for line in lines do
  begin
    tag := '';
    if (Copy(line, 1, 3) = '+++') or (Copy(line, 1, 3) = '---') then tag := 'head'
    else if Copy(line, 1, 2) = '@@' then tag := 'hunk'
    else if Copy(line, 1, 1) = '+' then tag := 'add'
    else if Copy(line, 1, 1) = '-' then tag := 'del';
    gtk_text_buffer_get_end_iter(buf, @it);
    if tag <> '' then
      gtk_text_buffer_insert_with_tags_by_name(buf, @it, PChar(line + #10), -1, PChar(tag), nil)
    else
      gtk_text_buffer_insert(buf, @it, PChar(line + #10), -1);
  end;
  gtk_text_buffer_get_start_iter(buf, @it);
  gtk_text_buffer_place_cursor(buf, @it);
  gtk_text_view_scroll_to_iter(View, @it, 0, False, 0, 0);
end;

{ ---------------------------------------------------------------- Wake on LAN }

procedure WakeOnLan;
var
  mac, bcast: string;
  hex: string;
  bytes: array[0..5] of Byte;
  pkt: array[0..101] of Byte;
  i, j: Integer;
  fd: cint;
  one: cint;
  sa: TInetSockAddr;
  ok: Boolean;
  n: LongWord;
begin
  mac := '';
  if not InputQuery('Wake on LAN', 'MAC address of the computer to wake up (e.g. 00:11:22:33:44:55):', mac) then Exit;
  hex := UpperCase(StringReplace(StringReplace(StringReplace(Trim(mac), ':', '', [rfReplaceAll]), '-', '', [rfReplaceAll]), '.', '', [rfReplaceAll]));
  ok := Length(hex) = 12;
  for i := 1 to Length(hex) do
    if not (hex[i] in ['0'..'9', 'A'..'F']) then ok := False;
  if not ok then
  begin
    MsgWarning('Invalid MAC address', mac);
    Exit;
  end;
  for i := 0 to 5 do
    bytes[i] := StrToInt('$' + Copy(hex, i * 2 + 1, 2));
  bcast := '255.255.255.255';
  if not InputQuery('Wake on LAN', 'Broadcast address:', bcast) then Exit;
  if not IpToNum(bcast, n) then
  begin
    MsgWarning('Invalid broadcast address', bcast);
    Exit;
  end;
  for i := 0 to 5 do pkt[i] := $FF;
  for j := 0 to 15 do
    for i := 0 to 5 do pkt[6 + j * 6 + i] := bytes[i];
  fd := fpSocket(AF_INET, SOCK_DGRAM, 0);
  if fd < 0 then
  begin
    MsgError('Unable to send the packet', SysErrorMessage(fpGetErrno));
    Exit;
  end;
  one := 1;
  fpSetSockOpt(fd, SOL_SOCKET, SO_BROADCAST, @one, SizeOf(one));
  FillChar(sa, SizeOf(sa), 0);
  sa.sin_family := AF_INET;
  sa.sin_port := htons(9);
  sa.sin_addr := StrToNetAddr(Trim(bcast));
  if fpSendTo(fd, @pkt, SizeOf(pkt), 0, @sa, SizeOf(sa)) = SizeOf(pkt) then
    MsgInfo('Magic packet sent', 'Wake-on-LAN packet sent to ' + mac + ' (' + bcast + ':9).')
  else
    MsgError('Unable to send the packet', SysErrorMessage(fpGetErrno));
  fpClose(fd);
end;

{ ---------------------------------------------------------------- IP calculator }

type
  TIpCalcWindow = class(TToolWindow)
  public
    Input, Output: Pointer;
    constructor Create;
    procedure Calc;
  end;

procedure IpCalcCb(e: Pointer; data: gpointer); cdecl; begin TIpCalcWindow(data).Calc; end;

constructor TIpCalcWindow.Create;
var
  vbox: Pointer;
begin
  inherited Create('IP subnet calculator', 'gnome-calculator', 480, 420);
  vbox := gtk_box_new(GTK_ORIENTATION_VERTICAL, 8);
  SetMargins(vbox, 12);
  gtk_box_pack_start(vbox, NewLabel('Address with prefix or mask (192.168.1.10/24 or 10.0.0.5 255.255.0.0):', 0), False, False, 0);
  Input := gtk_entry_new;
  SetEntryText(Input, LocalIPv4Cidr);
  Connect(Input, 'changed', @IpCalcCb, Self);
  gtk_box_pack_start(vbox, Input, False, False, 0);
  Output := NewLabel('', 0);
  gtk_label_set_selectable(Output, True);
  gtk_widget_set_valign(Output, GTK_ALIGN_START);
  gtk_box_pack_start(vbox, Output, True, True, 0);
  gtk_container_add(Win, vbox);
  gtk_widget_show_all(Win);
  Calc;
end;

procedure TIpCalcWindow.Calc;
var
  t, ipS, maskS: string;
  ip, mask, net, bc: LongWord;
  bits, p, i: Integer;
  cls, kind, txt: string;
  hosts: Int64;
begin
  t := Trim(EntryText(Input));
  p := Pos('/', t);
  bits := -1;
  if p > 0 then
  begin
    ipS := Copy(t, 1, p - 1);
    bits := StrToIntDef(Copy(t, p + 1, 3), -1);
  end
  else
  begin
    p := Pos(' ', t);
    if p > 0 then
    begin
      ipS := Copy(t, 1, p - 1);
      maskS := Trim(Copy(t, p + 1, MaxInt));
      if IpToNum(maskS, mask) then
      begin
        bits := 0;
        for i := 31 downto 0 do
          if (mask and (LongWord(1) shl i)) <> 0 then Inc(bits) else Break;
      end;
    end
    else
    begin
      ipS := t;
      bits := 24;
    end;
  end;
  if not IpToNum(ipS, ip) or (bits < 0) or (bits > 32) then
  begin
    gtk_label_set_markup(Output, '<span foreground="#c62828">Invalid address</span>');
    Exit;
  end;
  if bits = 0 then mask := 0 else mask := not ((LongWord(1) shl (32 - bits)) - 1);
  if bits = 32 then mask := $FFFFFFFF;
  net := ip and mask;
  bc := net or not mask;
  if bits >= 31 then hosts := Int64(1) shl (32 - bits) else hosts := (Int64(1) shl (32 - bits)) - 2;
  case ip shr 24 of
    0..127: cls := 'A';
    128..191: cls := 'B';
    192..223: cls := 'C';
    224..239: cls := 'D (multicast)';
  else
    cls := 'E (reserved)';
  end;
  if ((ip shr 24) = 10) or ((ip shr 20) = $AC1) or ((ip shr 16) = $C0A8) then kind := 'private (RFC 1918)'
  else if (ip shr 24) = 127 then kind := 'loopback'
  else if (ip shr 16) = $A9FE then kind := 'link-local'
  else if (ip shr 22) = $191 then kind := 'carrier-grade NAT'
  else kind := 'public';
  txt := Format('<tt>Address     : <b>%s</b>'#10'Netmask     : %s = %d'#10'Wildcard    : %s'#10 +
    'Network     : <b>%s/%d</b>'#10'Broadcast   : %s'#10, [NumToIp(ip), NumToIp(mask), bits, NumToIp(not mask),
    NumToIp(net), bits, NumToIp(bc)]);
  if bits < 31 then
    txt := txt + Format('First host  : %s'#10'Last host   : %s'#10, [NumToIp(net + 1), NumToIp(bc - 1)]);
  txt := txt + Format('Hosts       : %d'#10'Class       : %s'#10'Type        : %s</tt>', [hosts, cls, kind]);
  gtk_label_set_markup(Output, PChar(txt));
end;

{ ---------------------------------------------------------------- menu / panel }

procedure AskAndRun(const Title, Prompt, Def, Icon: string; const Cmd: array of string);
var
  h: string;
  args: array of string;
  i: Integer;
begin
  h := Def;
  if not InputQuery(Title, Prompt, h) then Exit;
  h := Trim(h);
  if h = '' then Exit;
  SetLength(args, Length(Cmd) + 1);
  for i := 0 to High(Cmd) do args[i] := Cmd[i];
  args[High(args)] := h;
  App.RunCommandTab(Title + ' ' + h, Icon, args);
end;

procedure OpenTool(const Id: string);
var
  top: string;
begin
  if Id = 'editor' then
  begin
    if Assigned(OpenEditorProc) then OpenEditorProc('');
  end
  else if Id = 'keygen' then TKeygenWindow.Create
  else if Id = 'diff' then TDiffWindow.Create(False)
  else if Id = 'folderdiff' then TDiffWindow.Create(True)
  else if Id = 'passwords' then
  begin
    if Assigned(ShowPasswordsProc) then ShowPasswordsProc;
  end
  else if Id = 'packages' then
  begin
    if Assigned(ShowPackagesProc) then ShowPackagesProc;
  end
  else if Id = 'processes' then TProcWindow.Create
  else if Id = 'sysmon' then
  begin
    top := FindProgram('htop');
    if top = '' then top := 'top';
    App.RunCommandTab('System monitor', 'htop', [top]);
  end
  else if Id = 'hardware' then
    App.RunCommandTab('Hardware devices', 'computer', ['/bin/sh', '-c',
      'for c in lspci lsusb lsblk; do if command -v $c >/dev/null; then printf "\033[1;36m== %s ==\033[0m\n" $c; $c; echo; fi; done'])
  else if Id = 'tunnels' then
  begin
    if Assigned(ShowTunnelsProc) then ShowTunnelsProc;
  end
  else if Id = 'openports' then TPortsWindow.Create
  else if Id = 'netscan' then TNetScanWindow.Create(False)
  else if Id = 'portscan' then TNetScanWindow.Create(True)
  else if Id = 'ping' then TPingWindow.Create
  else if Id = 'traceroute' then
  begin
    if FindProgram('traceroute') <> '' then
      AskAndRun('Traceroute', 'Host to trace:', '8.8.8.8', 'knetattach', ['traceroute'])
    else
      AskAndRun('Traceroute', 'Host to trace:', '8.8.8.8', 'knetattach', ['tracepath']);
  end
  else if Id = 'interfaces' then
    App.RunCommandTab('Network interfaces', 'network-wired', ['/bin/sh', '-c', 'ip -c addr; echo; ip -c route'])
  else if Id = 'wol' then WakeOnLan
  else if Id = 'ipcalc' then TIpCalcWindow.Create;
end;

procedure ToolItemCb(item: Pointer; data: gpointer); cdecl;
begin
  OpenTool(CStr(PChar(data)));
end;

procedure BuildToolsMenu(Menu: Pointer);
var
  i: Integer;
  group: string;
  item, lbl: Pointer;
begin
  group := '';
  for i := 0 to High(ToolDefs) do
  begin
    if ToolDefs[i].Group <> group then
    begin
      if group <> '' then NewMenuSeparator(Menu);
      group := ToolDefs[i].Group;
      item := gtk_menu_item_new;
      lbl := NewMarkupLabel('<b>' + group + '</b>', 0);
      gtk_container_add(item, lbl);
      gtk_widget_set_sensitive(item, False);
      gtk_menu_shell_append(Menu, item);
    end;
    NewImageMenuItem(Menu, ToolDefs[i].Caption, ToolDefs[i].Icon, @ToolItemCb, PChar(ToolDefs[i].Id));
  end;
end;

procedure PanelRowActivated(view: Pointer; path: Pointer; col: Pointer; data: gpointer); cdecl;
var
  it: TGtkTreeIter;
  model: Pointer;
  id: PChar;
begin
  model := gtk_tree_view_get_model(view);
  if gtk_tree_model_get_iter(model, @it, path) then
  begin
    id := nil;
    gtk_tree_model_get(model, @it, 2, @id, -1);
    if id <> nil then OpenTool(TakeStr(id));
  end;
end;

function BuildToolsPanel: Pointer;
var
  types: array[0..2] of GType;
  store, view, col, cell, scroll: Pointer;
  i: Integer;
  group: string;
  it, parent: TGtkTreeIter;
begin
  types[0] := gdk_pixbuf_get_type;
  types[1] := G_TYPE_STRING;
  types[2] := G_TYPE_STRING;
  store := gtk_tree_store_newv(3, @types[0]);
  view := gtk_tree_view_new_with_model(store);
  g_object_unref(store);
  gtk_tree_view_set_headers_visible(view, False);
  gtk_tree_view_set_activate_on_single_click(view, True);
  col := gtk_tree_view_column_new;
  cell := gtk_cell_renderer_pixbuf_new;
  gtk_tree_view_column_pack_start(col, cell, False);
  gtk_tree_view_column_add_attribute(col, cell, 'pixbuf', 0);
  cell := gtk_cell_renderer_text_new;
  gtk_cell_renderer_set_padding(cell, 4, 2);
  gtk_tree_view_column_pack_start(col, cell, True);
  gtk_tree_view_column_add_attribute(col, cell, 'markup', 1);
  gtk_tree_view_append_column(view, col);
  group := '';
  for i := 0 to High(ToolDefs) do
  begin
    if ToolDefs[i].Group <> group then
    begin
      group := ToolDefs[i].Group;
      gtk_tree_store_append(store, @parent, nil);
      gtk_tree_store_set(store, @parent, 0, IconPixbuf('lx-tools', 16), 1, PChar('<b>' + group + '</b>'), 2, nil, -1);
    end;
    gtk_tree_store_append(store, @it, @parent);
    gtk_tree_store_set(store, @it, 0, IconPixbuf(ToolDefs[i].Icon, 16), 1, PChar(MarkupEscape(ToolDefs[i].Caption)),
      2, PChar(ToolDefs[i].Id), -1);
  end;
  gtk_tree_view_expand_all(view);
  Connect(view, 'row-activated', @PanelRowActivated, nil);
  scroll := gtk_scrolled_window_new(nil, nil);
  gtk_scrolled_window_set_policy(scroll, GTK_POLICY_AUTOMATIC, GTK_POLICY_AUTOMATIC);
  gtk_container_add(scroll, view);
  gtk_widget_show_all(scroll);
  Result := scroll;
end;

initialization
  BuildToolsMenuProc := @BuildToolsMenu;
  BuildToolsPanelProc := @BuildToolsPanel;
  OpenToolProc := @OpenTool;

end.

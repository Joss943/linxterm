{ LinXterm - games (Games menu): Mines, 2048 and Flood. }
unit lxgames;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, cairo, lxgtk, lxutil, lxtabs;

procedure OpenGame(const Id: string);

implementation

uses
  StrUtils, Math, DateUtils;

{ ---------------------------------------------------------------- common }

procedure SetRGB(cr: Pcairo_t; Hex: LongWord);
begin
  cairo_set_source_rgb(cr, ((Hex shr 16) and 255) / 255, ((Hex shr 8) and 255) / 255, (Hex and 255) / 255);
end;

procedure RoundRect(cr: Pcairo_t; X, Y, W, H, R: Double);
begin
  cairo_new_sub_path(cr);
  cairo_arc(cr, X + W - R, Y + R, R, -Pi / 2, 0);
  cairo_arc(cr, X + W - R, Y + H - R, R, 0, Pi / 2);
  cairo_arc(cr, X + R, Y + H - R, R, Pi / 2, Pi);
  cairo_arc(cr, X + R, Y + R, R, Pi, 3 * Pi / 2);
  cairo_close_path(cr);
end;

procedure CenterText(cr: Pcairo_t; const S: string; CX, CY, Size: Double; Bold: Boolean);
var
  ext: cairo_text_extents_t;
begin
  if Bold then
    cairo_select_font_face(cr, 'Sans', CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_BOLD)
  else
    cairo_select_font_face(cr, 'Sans', CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL);
  cairo_set_font_size(cr, Size);
  cairo_text_extents(cr, PChar(S), @ext);
  cairo_move_to(cr, CX - ext.width / 2 - ext.x_bearing, CY - ext.height / 2 - ext.y_bearing);
  cairo_show_text(cr, PChar(S));
end;

type
  TGameWindow = class
  public
    Win, Area, Status: Pointer;
    constructor Create(const Title, Icon: string);
    procedure Draw(cr: Pcairo_t); virtual; abstract;
    procedure Click(X, Y: Double; Button: Integer; Double_: Boolean); virtual;
    procedure Key(KeyVal: guint); virtual;
    procedure NewGame; virtual; abstract;
  end;

function GDraw(w: Pointer; cr: Pointer; data: gpointer): gboolean; cdecl;
begin
  TGameWindow(data).Draw(cr);
  Result := True;
end;

function GButton(w: Pointer; ev: Pointer; data: gpointer): gboolean; cdecl;
var
  x, y: gdouble;
  t: gint;
begin
  gdk_event_get_coords(ev, @x, @y);
  t := gdk_event_get_event_type(ev);
  if (t = GDK_BUTTON_PRESS) or (t = GDK_2BUTTON_PRESS) then
    TGameWindow(data).Click(x, y, EventButton(ev), t = GDK_2BUTTON_PRESS);
  Result := True;
end;

function GKey(w: Pointer; ev: Pointer; data: gpointer): gboolean; cdecl;
begin
  TGameWindow(data).Key(EventKeyval(ev));
  Result := False;
end;

procedure GDestroy(w: Pointer; data: gpointer); cdecl;
begin
  TGameWindow(data).Free;
end;

procedure GNew(b: Pointer; data: gpointer); cdecl;
begin
  TGameWindow(data).NewGame;
end;

constructor TGameWindow.Create(const Title, Icon: string);
var
  vbox, hb, b: Pointer;
begin
  inherited Create;
  Win := gtk_window_new(GTK_WINDOW_TOPLEVEL);
  gtk_window_set_title(Win, PChar(Title));
  gtk_window_set_icon(Win, IconPixbuf(Icon, 64));
  gtk_window_set_resizable(Win, False);
  vbox := gtk_box_new(GTK_ORIENTATION_VERTICAL, 6);
  SetMargins(vbox, 10);
  hb := gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 6);
  b := NewIconButton('lx-refresh', '_New game', '', 16);
  Connect(b, 'clicked', @GNew, Self);
  gtk_widget_set_can_focus(b, False);
  gtk_box_pack_start(hb, b, False, False, 0);
  Status := NewLabel('', 1);
  gtk_box_pack_end(hb, Status, True, True, 0);
  gtk_box_pack_start(vbox, hb, False, False, 0);
  Area := gtk_drawing_area_new;
  gtk_widget_add_events(Area, GDK_BUTTON_PRESS_MASK);
  Connect(Area, 'draw', @GDraw, Self);
  Connect(Area, 'button-press-event', @GButton, Self);
  gtk_box_pack_start(vbox, Area, True, True, 0);
  gtk_container_add(Win, vbox);
  Connect(Win, 'key-press-event', @GKey, Self);
  Connect(Win, 'destroy', @GDestroy, Self);
end;

procedure TGameWindow.Click(X, Y: Double; Button: Integer; Double_: Boolean);
begin
end;

procedure TGameWindow.Key(KeyVal: guint);
begin
end;

{ ---------------------------------------------------------------- Mines }

const
  CELL = 26;

type
  TMinesWindow = class(TGameWindow)
  public
    W, H, Count: Integer;
    Mine, Open, Flag: array of Boolean;
    Started, Over, Won: Boolean;
    StartTime: TDateTime;
    Timer: guint;
    Level: Pointer;
    constructor Create;
    destructor Destroy; override;
    procedure NewGame; override;
    function Idx(X, Y: Integer): Integer;
    function Around(X, Y: Integer): Integer;
    procedure Reveal(X, Y: Integer);
    procedure Place(SafeX, SafeY: Integer);
    procedure Draw(cr: Pcairo_t); override;
    procedure Click(X, Y: Double; Button: Integer; Double_: Boolean); override;
    procedure UpdateStatus;
  end;

function MinesTick(data: gpointer): gboolean; cdecl;
begin
  TMinesWindow(data).UpdateStatus;
  Result := True;
end;

procedure LevelChanged(c: Pointer; data: gpointer); cdecl;
begin
  TMinesWindow(data).NewGame;
end;

constructor TMinesWindow.Create;
var
  hb: Pointer;
begin
  inherited Create('Mines', 'gnome-mines');
  Level := gtk_combo_box_text_new;
  gtk_combo_box_text_append_text(Level, 'Beginner (9 x 9, 10 mines)');
  gtk_combo_box_text_append_text(Level, 'Intermediate (16 x 16, 40 mines)');
  gtk_combo_box_text_append_text(Level, 'Expert (30 x 16, 99 mines)');
  gtk_combo_box_set_active(Level, 0);
  gtk_widget_set_can_focus(Level, False);
  hb := gtk_widget_get_parent(Status);
  gtk_box_pack_start(hb, Level, False, False, 0);
  Connect(Level, 'changed', @LevelChanged, Self);
  NewGame;
  Timer := g_timeout_add(1000, @MinesTick, Self);
  gtk_widget_show_all(Win);
end;

destructor TMinesWindow.Destroy;
begin
  if Timer <> 0 then g_source_remove(Timer);
  inherited Destroy;
end;

procedure TMinesWindow.NewGame;
begin
  case gtk_combo_box_get_active(Level) of
    1: begin W := 16; H := 16; Count := 40; end;
    2: begin W := 30; H := 16; Count := 99; end;
  else
    begin W := 9; H := 9; Count := 10; end;
  end;
  SetLength(Mine, W * H);
  SetLength(Open, W * H);
  SetLength(Flag, W * H);
  FillChar(Mine[0], W * H, 0);
  FillChar(Open[0], W * H, 0);
  FillChar(Flag[0], W * H, 0);
  Started := False;
  Over := False;
  Won := False;
  gtk_widget_set_size_request(Area, W * CELL + 1, H * CELL + 1);
  UpdateStatus;
  gtk_widget_queue_draw(Area);
end;

function TMinesWindow.Idx(X, Y: Integer): Integer;
begin
  Result := Y * W + X;
end;

function TMinesWindow.Around(X, Y: Integer): Integer;
var
  dx, dy: Integer;
begin
  Result := 0;
  for dy := -1 to 1 do
    for dx := -1 to 1 do
      if ((dx <> 0) or (dy <> 0)) and (X + dx >= 0) and (X + dx < W) and (Y + dy >= 0) and (Y + dy < H) then
        if Mine[Idx(X + dx, Y + dy)] then Inc(Result);
end;

procedure TMinesWindow.Place(SafeX, SafeY: Integer);
var
  n, x, y: Integer;
begin
  n := 0;
  while n < Count do
  begin
    x := Random(W);
    y := Random(H);
    if Mine[Idx(x, y)] or ((Abs(x - SafeX) <= 1) and (Abs(y - SafeY) <= 1)) then Continue;
    Mine[Idx(x, y)] := True;
    Inc(n);
  end;
end;

procedure TMinesWindow.Reveal(X, Y: Integer);
var
  dx, dy: Integer;
begin
  if (X < 0) or (X >= W) or (Y < 0) or (Y >= H) then Exit;
  if Open[Idx(X, Y)] or Flag[Idx(X, Y)] then Exit;
  Open[Idx(X, Y)] := True;
  if Mine[Idx(X, Y)] then
  begin
    Over := True;
    Exit;
  end;
  if Around(X, Y) = 0 then
    for dy := -1 to 1 do
      for dx := -1 to 1 do
        if (dx <> 0) or (dy <> 0) then Reveal(X + dx, Y + dy);
end;

procedure TMinesWindow.Click(X, Y: Double; Button: Integer; Double_: Boolean);
var
  cx, cy, i, dx, dy, flags: Integer;
  closed: Integer;
begin
  if Over or Won then Exit;
  cx := Trunc(X) div CELL;
  cy := Trunc(Y) div CELL;
  if (cx < 0) or (cx >= W) or (cy < 0) or (cy >= H) then Exit;
  if Button = 3 then
  begin
    if not Open[Idx(cx, cy)] then Flag[Idx(cx, cy)] := not Flag[Idx(cx, cy)];
  end
  else if (Button = 2) or Double_ or Open[Idx(cx, cy)] then
  begin
    { chord: open the neighbours when the flags match the number }
    if Open[Idx(cx, cy)] then
    begin
      flags := 0;
      for dy := -1 to 1 do
        for dx := -1 to 1 do
          if (cx + dx >= 0) and (cx + dx < W) and (cy + dy >= 0) and (cy + dy < H) and Flag[Idx(cx + dx, cy + dy)] then
            Inc(flags);
      if flags = Around(cx, cy) then
        for dy := -1 to 1 do
          for dx := -1 to 1 do Reveal(cx + dx, cy + dy);
    end;
  end
  else if Button = 1 then
  begin
    if not Started then
    begin
      Place(cx, cy);
      Started := True;
      StartTime := Now;
    end;
    Reveal(cx, cy);
  end;
  closed := 0;
  for i := 0 to W * H - 1 do
    if not Open[i] then Inc(closed);
  if (not Over) and (closed = Count) then Won := True;
  UpdateStatus;
  gtk_widget_queue_draw(Area);
end;

procedure TMinesWindow.UpdateStatus;
var
  flags, i, secs: Integer;
begin
  flags := 0;
  for i := 0 to High(Flag) do
    if Flag[i] then Inc(flags);
  if Started then secs := SecondsBetween(Now, StartTime) else secs := 0;
  if Over then
    gtk_label_set_markup(Status, '<b><span foreground="#c62828">Boom! You lost.</span></b>')
  else if Won then
    gtk_label_set_markup(Status, PChar('<b><span foreground="#2e7d32">You won in ' + IntToStr(secs) + ' s!</span></b>'))
  else
    gtk_label_set_text(Status, PChar(Format('Mines left: %d    Time: %d s', [Count - flags, secs])));
end;

procedure TMinesWindow.Draw(cr: Pcairo_t);
const
  NumColors: array[1..8] of LongWord = ($1976D2, $388E3C, $D32F2F, $303F9F, $8D2C1F, $00838F, $212121, $757575);
var
  x, y, n: Integer;
  px, py: Double;
begin
  for y := 0 to H - 1 do
    for x := 0 to W - 1 do
    begin
      px := x * CELL;
      py := y * CELL;
      if Open[Idx(x, y)] then
      begin
        if Mine[Idx(x, y)] then SetRGB(cr, $E53935) else SetRGB(cr, $E8E8E8);
        cairo_rectangle(cr, px, py, CELL, CELL);
        cairo_fill(cr);
        SetRGB(cr, $C4C4C4);
        cairo_rectangle(cr, px + 0.5, py + 0.5, CELL - 1, CELL - 1);
        cairo_set_line_width(cr, 1);
        cairo_stroke(cr);
        if Mine[Idx(x, y)] then
        begin
          SetRGB(cr, $111111);
          cairo_arc(cr, px + CELL / 2, py + CELL / 2, CELL / 4, 0, 2 * Pi);
          cairo_fill(cr);
        end
        else
        begin
          n := Around(x, y);
          if n > 0 then
          begin
            SetRGB(cr, NumColors[n]);
            CenterText(cr, IntToStr(n), px + CELL / 2, py + CELL / 2, 15, True);
          end;
        end;
      end
      else
      begin
        SetRGB(cr, $9EB6D4);
        cairo_rectangle(cr, px, py, CELL, CELL);
        cairo_fill(cr);
        SetRGB(cr, $C8D8EC);
        cairo_rectangle(cr, px + 1, py + 1, CELL - 3, CELL - 3);
        cairo_fill(cr);
        SetRGB(cr, $B0C4DE);
        cairo_rectangle(cr, px + 3, py + 3, CELL - 6, CELL - 6);
        cairo_fill(cr);
        if Over and Mine[Idx(x, y)] and not Flag[Idx(x, y)] then
        begin
          SetRGB(cr, $222222);
          cairo_arc(cr, px + CELL / 2, py + CELL / 2, CELL / 5, 0, 2 * Pi);
          cairo_fill(cr);
        end;
        if Flag[Idx(x, y)] then
        begin
          SetRGB(cr, $D32F2F);
          cairo_move_to(cr, px + 9, py + 5);
          cairo_line_to(cr, px + 19, py + 9);
          cairo_line_to(cr, px + 9, py + 13);
          cairo_close_path(cr);
          cairo_fill(cr);
          SetRGB(cr, $333333);
          cairo_rectangle(cr, px + 8, py + 5, 2, 15);
          cairo_fill(cr);
        end;
      end;
    end;
end;

{ ---------------------------------------------------------------- 2048 }

type
  T2048Window = class(TGameWindow)
  public
    Grid: array[0..3, 0..3] of Integer;
    Score: Integer;
    Lost: Boolean;
    constructor Create;
    procedure NewGame; override;
    procedure AddTile;
    function Move(DX, DY: Integer): Boolean;
    function CanMove: Boolean;
    procedure Draw(cr: Pcairo_t); override;
    procedure Key(KeyVal: guint); override;
  end;

constructor T2048Window.Create;
begin
  inherited Create('2048', 'gnome-2048');
  gtk_widget_set_size_request(Area, 4 * 100 + 10, 4 * 100 + 10);
  NewGame;
  gtk_widget_show_all(Win);
end;

procedure T2048Window.NewGame;
begin
  FillChar(Grid, SizeOf(Grid), 0);
  Score := 0;
  Lost := False;
  AddTile;
  AddTile;
  gtk_label_set_text(Status, 'Use the arrow keys - Score: 0');
  gtk_widget_queue_draw(Area);
end;

procedure T2048Window.AddTile;
var
  free_: array[0..15] of Integer;
  n, i, k: Integer;
begin
  n := 0;
  for i := 0 to 15 do
    if Grid[i div 4, i mod 4] = 0 then
    begin
      free_[n] := i;
      Inc(n);
    end;
  if n = 0 then Exit;
  k := free_[Random(n)];
  if Random(10) = 0 then Grid[k div 4, k mod 4] := 4 else Grid[k div 4, k mod 4] := 2;
end;

function T2048Window.Move(DX, DY: Integer): Boolean;
var
  line: array[0..3] of Integer;
  merged: array[0..3] of Integer;
  i, j, k, n, r, c: Integer;
begin
  Result := False;
  for i := 0 to 3 do
  begin
    { read the line in the direction of the move }
    for j := 0 to 3 do
    begin
      if DX <> 0 then
      begin
        r := i;
        if DX > 0 then c := 3 - j else c := j;
      end
      else
      begin
        c := i;
        if DY > 0 then r := 3 - j else r := j;
      end;
      line[j] := Grid[r, c];
    end;
    FillChar(merged, SizeOf(merged), 0);
    n := 0;
    k := 0;
    while k < 4 do
    begin
      if line[k] <> 0 then
      begin
        if (n > 0) and (merged[n - 1] = line[k]) and (merged[n - 1] > 0) then
        begin
          merged[n - 1] := -merged[n - 1] * 2;
          Inc(Score, -merged[n - 1]);
        end
        else
        begin
          merged[n] := line[k];
          Inc(n);
        end;
      end;
      Inc(k);
    end;
    for j := 0 to 3 do
    begin
      merged[j] := Abs(merged[j]);
      if DX <> 0 then
      begin
        r := i;
        if DX > 0 then c := 3 - j else c := j;
      end
      else
      begin
        c := i;
        if DY > 0 then r := 3 - j else r := j;
      end;
      if Grid[r, c] <> merged[j] then Result := True;
      Grid[r, c] := merged[j];
    end;
  end;
end;

function T2048Window.CanMove: Boolean;
var
  r, c: Integer;
begin
  Result := True;
  for r := 0 to 3 do
    for c := 0 to 3 do
    begin
      if Grid[r, c] = 0 then Exit;
      if (c < 3) and (Grid[r, c] = Grid[r, c + 1]) then Exit;
      if (r < 3) and (Grid[r, c] = Grid[r + 1, c]) then Exit;
    end;
  Result := False;
end;

procedure T2048Window.Key(KeyVal: guint);
var
  moved: Boolean;
begin
  if Lost then Exit;
  case KeyVal of
    GDK_KEY_Left, Ord('a'), Ord('q'): moved := Move(-1, 0);
    GDK_KEY_Right, Ord('d'): moved := Move(1, 0);
    GDK_KEY_Up, Ord('w'), Ord('z'): moved := Move(0, -1);
    GDK_KEY_Down, Ord('s'): moved := Move(0, 1);
  else
    Exit;
  end;
  if moved then AddTile;
  if not CanMove then
  begin
    Lost := True;
    gtk_label_set_markup(Status, PChar('<b>Game over - Score: ' + IntToStr(Score) + '</b>'));
  end
  else
    gtk_label_set_text(Status, PChar('Use the arrow keys - Score: ' + IntToStr(Score)));
  gtk_widget_queue_draw(Area);
end;

procedure T2048Window.Draw(cr: Pcairo_t);
var
  r, c, v: Integer;
  x, y: Double;
  col: LongWord;
begin
  SetRGB(cr, $BBADA0);
  RoundRect(cr, 0, 0, 410, 410, 8);
  cairo_fill(cr);
  for r := 0 to 3 do
    for c := 0 to 3 do
    begin
      v := Grid[r, c];
      x := 10 + c * 100;
      y := 10 + r * 100;
      case v of
        0: col := $CDC1B4;
        2: col := $EEE4DA;
        4: col := $EDE0C8;
        8: col := $F2B179;
        16: col := $F59563;
        32: col := $F67C5F;
        64: col := $F65E3B;
        128: col := $EDCF72;
        256: col := $EDCC61;
        512: col := $EDC850;
        1024: col := $EDC53F;
      else
        col := $EDC22E;
      end;
      SetRGB(cr, col);
      RoundRect(cr, x, y, 90, 90, 6);
      cairo_fill(cr);
      if v > 0 then
      begin
        if v <= 4 then SetRGB(cr, $776E65) else SetRGB(cr, $F9F6F2);
        CenterText(cr, IntToStr(v), x + 45, y + 45, IfThen(v < 100, 36, IfThen(v < 1000, 30, 24)), True);
      end;
    end;
end;

{ ---------------------------------------------------------------- Flood }

const
  FSIZE = 14;
  FCELL = 28;
  FColors: array[0..5] of LongWord = ($E53935, $1E88E5, $43A047, $FDD835, $8E24AA, $FB8C00);

type
  TFloodWindow = class(TGameWindow)
  public
    Cells: array[0..FSIZE - 1, 0..FSIZE - 1] of Integer;
    Moves: Integer;
    Done: Boolean;
    constructor Create;
    procedure NewGame; override;
    procedure Play(Color: Integer);
    procedure Draw(cr: Pcairo_t); override;
    procedure Click(X, Y: Double; Button: Integer; Double_: Boolean); override;
  end;

const
  MAXMOVES = 25;

constructor TFloodWindow.Create;
begin
  inherited Create('Flood', 'kblocks');
  gtk_widget_set_size_request(Area, FSIZE * FCELL, FSIZE * FCELL + 50);
  NewGame;
  gtk_widget_show_all(Win);
end;

procedure TFloodWindow.NewGame;
var
  r, c: Integer;
begin
  for r := 0 to FSIZE - 1 do
    for c := 0 to FSIZE - 1 do
      Cells[r, c] := Random(6);
  Moves := 0;
  Done := False;
  gtk_label_set_text(Status, PChar('Fill the board with one color in ' + IntToStr(MAXMOVES) + ' moves'));
  gtk_widget_queue_draw(Area);
end;

procedure TFloodWindow.Play(Color: Integer);
var
  old, r, c: Integer;
  stack: array of Integer;
  n, k: Integer;
  seen: array[0..FSIZE - 1, 0..FSIZE - 1] of Boolean;
  all: Boolean;
begin
  if Done then Exit;
  old := Cells[0, 0];
  if old = Color then Exit;
  FillChar(seen, SizeOf(seen), 0);
  SetLength(stack, FSIZE * FSIZE);
  n := 1;
  stack[0] := 0;
  seen[0, 0] := True;
  while n > 0 do
  begin
    Dec(n);
    k := stack[n];
    r := k div FSIZE;
    c := k mod FSIZE;
    Cells[r, c] := Color;
    if (r > 0) and not seen[r - 1, c] and (Cells[r - 1, c] = old) then begin seen[r - 1, c] := True; stack[n] := (r - 1) * FSIZE + c; Inc(n); end;
    if (r < FSIZE - 1) and not seen[r + 1, c] and (Cells[r + 1, c] = old) then begin seen[r + 1, c] := True; stack[n] := (r + 1) * FSIZE + c; Inc(n); end;
    if (c > 0) and not seen[r, c - 1] and (Cells[r, c - 1] = old) then begin seen[r, c - 1] := True; stack[n] := r * FSIZE + c - 1; Inc(n); end;
    if (c < FSIZE - 1) and not seen[r, c + 1] and (Cells[r, c + 1] = old) then begin seen[r, c + 1] := True; stack[n] := r * FSIZE + c + 1; Inc(n); end;
  end;
  Inc(Moves);
  all := True;
  for r := 0 to FSIZE - 1 do
    for c := 0 to FSIZE - 1 do
      if Cells[r, c] <> Color then all := False;
  if all then
  begin
    Done := True;
    gtk_label_set_markup(Status, PChar('<b><span foreground="#2e7d32">Well done! ' + IntToStr(Moves) + ' moves.</span></b>'));
  end
  else if Moves >= MAXMOVES then
  begin
    Done := True;
    gtk_label_set_markup(Status, '<b><span foreground="#c62828">No moves left!</span></b>');
  end
  else
    gtk_label_set_text(Status, PChar(Format('Moves: %d / %d', [Moves, MAXMOVES])));
  gtk_widget_queue_draw(Area);
end;

procedure TFloodWindow.Click(X, Y: Double; Button: Integer; Double_: Boolean);
var
  r, c, i: Integer;
begin
  if Y > FSIZE * FCELL then
  begin
    i := Trunc(X) div (FSIZE * FCELL div 6);
    if (i >= 0) and (i < 6) then Play(i);
    Exit;
  end;
  r := Trunc(Y) div FCELL;
  c := Trunc(X) div FCELL;
  if (r >= 0) and (r < FSIZE) and (c >= 0) and (c < FSIZE) then Play(Cells[r, c]);
end;

procedure TFloodWindow.Draw(cr: Pcairo_t);
var
  r, c, i, bw: Integer;
begin
  for r := 0 to FSIZE - 1 do
    for c := 0 to FSIZE - 1 do
    begin
      SetRGB(cr, FColors[Cells[r, c]]);
      cairo_rectangle(cr, c * FCELL, r * FCELL, FCELL, FCELL);
      cairo_fill(cr);
    end;
  bw := FSIZE * FCELL div 6;
  for i := 0 to 5 do
  begin
    SetRGB(cr, FColors[i]);
    RoundRect(cr, i * bw + 4, FSIZE * FCELL + 8, bw - 8, 36, 6);
    cairo_fill(cr);
  end;
end;

{ ---------------------------------------------------------------- menu }

procedure OpenGame(const Id: string);
begin
  if Id = 'mines' then TMinesWindow.Create
  else if Id = '2048' then T2048Window.Create
  else if Id = 'flood' then TFloodWindow.Create;
end;

procedure GameItem(i: Pointer; data: gpointer); cdecl;
begin
  OpenGame(CStr(PChar(data)));
end;

procedure BuildGamesMenu(Menu: Pointer);
begin
  NewImageMenuItem(Menu, '_Mines', 'gnome-mines', @GameItem, PChar('mines'));
  NewImageMenuItem(Menu, '_2048', 'gnome-2048', @GameItem, PChar('2048'));
  NewImageMenuItem(Menu, '_Flood', 'kblocks', @GameItem, PChar('flood'));
end;

initialization
  BuildGamesMenuProc := @BuildGamesMenu;
  OpenGameProc := @OpenGame;

end.

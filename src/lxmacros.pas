{ LinXterm - macros: record keystrokes typed in a terminal, replay them in
  the current terminal (or in every terminal in MultiExec mode), hotkeys. }
unit lxmacros;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpjson, lxgtk, lxutil, lxconfig, lxtabs, lxterminal;

function MacroText(const Name: string): string;
function MacroNames: TStringArray;

implementation

uses
  StrUtils, lxsessiondlg;

type
  TMacro = class
    Name, Text, Hotkey: string;
  end;

  TMacroPanel = class
  public
    Widget, Store, View, Status, RecBtn, StopBtn: Pointer;
    constructor Create;
    procedure Rebuild;
    function Selected: TMacro;
    procedure UpdateStatus;
  end;

var
  Macros: TList;
  Panel: TMacroPanel = nil;
  Recording: Boolean = False;
  RecTab: TTabPage = nil;
  RecBuf: string = '';
  HotkeysHooked: Boolean = False;

const
  { Ctrl+Alt+F1..F12 switch the Linux virtual consoles and never reach the
    application: the hotkeys use Ctrl+Shift and Alt+Shift instead }
  HotkeyChoices: array[0..24] of string = ('',
    'Ctrl+Shift+F1', 'Ctrl+Shift+F2', 'Ctrl+Shift+F3', 'Ctrl+Shift+F4', 'Ctrl+Shift+F5', 'Ctrl+Shift+F6',
    'Ctrl+Shift+F7', 'Ctrl+Shift+F8', 'Ctrl+Shift+F9', 'Ctrl+Shift+F10', 'Ctrl+Shift+F11', 'Ctrl+Shift+F12',
    'Alt+Shift+F1', 'Alt+Shift+F2', 'Alt+Shift+F3', 'Alt+Shift+F4', 'Alt+Shift+F5', 'Alt+Shift+F6',
    'Alt+Shift+F7', 'Alt+Shift+F8', 'Alt+Shift+F9', 'Alt+Shift+F10', 'Alt+Shift+F11', 'Alt+Shift+F12');

{ ---------------------------------------------------------------- storage }

procedure LoadMacros;
var
  d: TJSONData;
  a: TJSONArray;
  i: Integer;
  m: TMacro;
begin
  Macros := TList.Create;
  d := LoadJsonFile(ConfigDir + '/macros.json');
  if d = nil then Exit;
  try
    if d.JSONType <> jtArray then Exit;
    a := TJSONArray(d);
    for i := 0 to a.Count - 1 do
      if a[i].JSONType = jtObject then
      begin
        m := TMacro.Create;
        m.Name := JStr(TJSONObject(a[i]), 'name', 'macro');
        m.Text := JStr(TJSONObject(a[i]), 'text', '');
        m.Hotkey := JStr(TJSONObject(a[i]), 'hotkey', '');
        { old Ctrl+Alt hotkeys cannot work on Linux }
        if Pos('Ctrl+Alt+', m.Hotkey) = 1 then
          m.Hotkey := 'Ctrl+Shift+' + Copy(m.Hotkey, 10, MaxInt);
        Macros.Add(m);
      end;
  finally
    d.Free;
  end;
end;

procedure SaveMacros;
var
  a: TJSONArray;
  o: TJSONObject;
  i: Integer;
begin
  a := TJSONArray.Create;
  try
    for i := 0 to Macros.Count - 1 do
    begin
      o := TJSONObject.Create;
      o.Add('name', TMacro(Macros[i]).Name);
      o.Add('text', TMacro(Macros[i]).Text);
      o.Add('hotkey', TMacro(Macros[i]).Hotkey);
      a.Add(o);
    end;
    SaveJsonFile(ConfigDir + '/macros.json', a);
  finally
    a.Free;
  end;
end;

function FindMacro(const Name: string): TMacro;
var
  i: Integer;
begin
  for i := 0 to Macros.Count - 1 do
    if SameText(TMacro(Macros[i]).Name, Name) then Exit(TMacro(Macros[i]));
  Result := nil;
end;

function MacroText(const Name: string): string;
var
  m: TMacro;
begin
  m := FindMacro(Name);
  if m <> nil then Result := m.Text else Result := '';
end;

function MacroNames: TStringArray;
var
  i: Integer;
begin
  Result := nil;
  SetLength(Result, Macros.Count);
  for i := 0 to Macros.Count - 1 do Result[i] := TMacro(Macros[i]).Name;
end;

{ ---------------------------------------------------------------- encoding }

{ Enter is shown as a line break; other control characters are escaped }
function EncodeMacro(const S: string): string;
var
  i: Integer;
  c: Char;
begin
  Result := '';
  for i := 1 to Length(S) do
  begin
    c := S[i];
    case c of
      #13: Result := Result + #10;
      #10: Result := Result + '\n';
      #9: Result := Result + '\t';
      #27: Result := Result + '\e';
      '\': Result := Result + '\\';
    else
      if (Ord(c) < 32) or (Ord(c) = 127) then
        Result := Result + '\x' + LowerCase(IntToHex(Ord(c), 2))
      else
        Result := Result + c;
    end;
  end;
end;

function DecodeMacro(const S: string): string;
var
  i: Integer;
begin
  Result := '';
  i := 1;
  while i <= Length(S) do
  begin
    if S[i] = #10 then
      Result := Result + #13
    else if (S[i] = '\') and (i < Length(S)) then
    begin
      Inc(i);
      case S[i] of
        'n': Result := Result + #10;
        'r': Result := Result + #13;
        't': Result := Result + #9;
        'e': Result := Result + #27;
        '\': Result := Result + '\';
        'x':
          if i + 2 <= Length(S) then
          begin
            Result := Result + Chr(StrToIntDef('$' + Copy(S, i + 1, 2), 0));
            Inc(i, 2);
          end;
      else
        Result := Result + '\' + S[i];
      end;
    end
    else
      Result := Result + S[i];
    Inc(i);
  end;
end;

{ ---------------------------------------------------------------- actions }

procedure PlayMacro(M: TMacro);
var
  t: TTabPage;
begin
  if M = nil then Exit;
  t := App.CurrentTab;
  if not (t is TTerminalTab) then
  begin
    MsgInfo('No terminal', 'Select a terminal tab before playing a macro.');
    Exit;
  end;
  TTerminalTab(t).SendInput(M.Text);
  if App.MultiExecActive then App.TerminalInput(t, M.Text);
  t.FocusContent;
end;

function EditMacroDialog(M: TMacro; IsNew: Boolean): Boolean;
var
  d, area, grid, name, view, scroll, hot: Pointer;
  i: Integer;
  nm, txt: string;
  other: TMacro;
begin
  Result := False;
  d := gtk_dialog_new_with_buttons(PChar(IfThen(IsNew, 'New macro', 'Macro edition')), MainWindowWidget,
    GTK_DIALOG_MODAL or GTK_DIALOG_DESTROY_WITH_PARENT, '_Cancel', GTK_RESPONSE_CANCEL, '_OK', GTK_RESPONSE_OK, nil);
  gtk_window_set_default_size(d, 460, 420);
  area := gtk_dialog_get_content_area(d);
  grid := gtk_grid_new;
  gtk_grid_set_row_spacing(grid, 8);
  gtk_grid_set_column_spacing(grid, 8);
  SetMargins(grid, 12);
  gtk_grid_attach(grid, NewLabel('Name', 1), 0, 0, 1, 1);
  name := gtk_entry_new;
  SetEntryText(name, M.Name);
  gtk_widget_set_hexpand(name, True);
  gtk_grid_attach(grid, name, 1, 0, 1, 1);
  gtk_grid_attach(grid, NewMarkupLabel('<small>One line per Enter key. Escapes: \t Tab, \e Escape, ' +
    '\n line feed, \x03 Ctrl+C, \\ backslash.</small>', 0), 0, 1, 2, 1);
  view := gtk_text_view_new;
  gtk_text_view_set_monospace(view, True);
  txt := EncodeMacro(M.Text);
  gtk_text_buffer_set_text(gtk_text_view_get_buffer(view), PChar(txt), Length(txt));
  scroll := NewScrolled(view);
  gtk_widget_set_vexpand(scroll, True);
  gtk_grid_attach(grid, scroll, 0, 2, 2, 1);
  gtk_grid_attach(grid, NewLabel('Hotkey', 1), 0, 3, 1, 1);
  hot := gtk_combo_box_text_new;
  for i := 0 to High(HotkeyChoices) do
    if HotkeyChoices[i] = '' then
      gtk_combo_box_text_append(hot, '', '<none>')
    else
      gtk_combo_box_text_append(hot, PChar(HotkeyChoices[i]), PChar(HotkeyChoices[i]));
  if not gtk_combo_box_set_active_id(hot, PChar(M.Hotkey)) then gtk_combo_box_set_active(hot, 0);
  gtk_grid_attach(grid, hot, 1, 3, 1, 1);
  gtk_container_add(area, grid);
  gtk_widget_show_all(d);
  while gtk_dialog_run(d) = GTK_RESPONSE_OK do
  begin
    nm := Trim(EntryText(name));
    other := FindMacro(nm);
    if nm = '' then
      MsgWarning('The macro name is missing', '')
    else if (other <> nil) and (other <> M) then
      MsgWarning('A macro with this name already exists', nm)
    else
    begin
      M.Name := nm;
      M.Text := DecodeMacro(TextBufferText(gtk_text_view_get_buffer(view)));
      M.Hotkey := CStr(gtk_combo_box_get_active_id(hot));
      { a hotkey belongs to one macro only }
      if M.Hotkey <> '' then
        for i := 0 to Macros.Count - 1 do
          if (TMacro(Macros[i]) <> M) and (TMacro(Macros[i]).Hotkey = M.Hotkey) then
            TMacro(Macros[i]).Hotkey := '';
      Result := True;
      Break;
    end;
  end;
  gtk_widget_destroy(d);
end;

procedure StartRecording;
var
  t: TTabPage;
begin
  t := App.CurrentTab;
  if not (t is TTerminalTab) then
  begin
    MsgInfo('No terminal', 'Select the terminal tab in which the keystrokes will be recorded.');
    Exit;
  end;
  Recording := True;
  RecTab := t;
  RecBuf := '';
  if Panel <> nil then Panel.UpdateStatus;
  App.SetStatus('Recording a macro: type your commands in "' + t.FullTitle + '", then click Stop');
  t.FocusContent;
end;

procedure StopRecording;
var
  m: TMacro;
begin
  if not Recording then Exit;
  Recording := False;
  RecTab := nil;
  if Panel <> nil then Panel.UpdateStatus;
  if RecBuf = '' then
  begin
    App.SetStatus('Macro recording cancelled: nothing was typed');
    Exit;
  end;
  m := TMacro.Create;
  m.Name := 'Macro ' + IntToStr(Macros.Count + 1);
  while FindMacro(m.Name) <> nil do m.Name := m.Name + '+';
  m.Text := RecBuf;
  if EditMacroDialog(m, True) then
  begin
    Macros.Add(m);
    SaveMacros;
    if Panel <> nil then Panel.Rebuild;
    App.SetStatus('Macro "' + m.Name + '" saved');
  end
  else
    m.Free;
  RecBuf := '';
end;

procedure MacroInput(Tab: TTabPage; const Data: string);
begin
  if Recording and (Tab = RecTab) then
  begin
    RecBuf := RecBuf + Data;
    if Panel <> nil then Panel.UpdateStatus;
  end;
end;

function ParseHotkey(const H: string; out Key: guint; out Mods: guint): Boolean;
var
  f: Integer;
begin
  Result := False;
  Mods := 0;
  if Pos('Ctrl+', H) > 0 then Mods := Mods or GDK_CONTROL_MASK;
  if Pos('Alt+', H) > 0 then Mods := Mods or GDK_MOD1_MASK;
  if Pos('Shift+', H) > 0 then Mods := Mods or GDK_SHIFT_MASK;
  f := StrToIntDef(Copy(H, LastDelimiter('F', H) + 1, 3), 0);
  if (f < 1) or (f > 12) then Exit;
  Key := GDK_KEY_F1 + guint(f - 1);
  Result := True;
end;

function WindowKey(w: Pointer; ev: Pointer; data: gpointer): gboolean; cdecl;
var
  kv, st, k, m: guint;
  i: Integer;
begin
  Result := False;
  kv := EventKeyval(ev);
  if (kv < GDK_KEY_F1) or (kv > GDK_KEY_F1 + 11) then Exit;
  st := EventState(ev) and (GDK_CONTROL_MASK or GDK_MOD1_MASK or GDK_SHIFT_MASK);
  for i := 0 to Macros.Count - 1 do
    if (TMacro(Macros[i]).Hotkey <> '') and ParseHotkey(TMacro(Macros[i]).Hotkey, k, m) and (k = kv) and (m = st) then
    begin
      PlayMacro(TMacro(Macros[i]));
      Exit(True);
    end;
end;

procedure HookHotkeys;
begin
  if HotkeysHooked or (MainWindowWidget = nil) then Exit;
  Connect(MainWindowWidget, 'key-press-event', @WindowKey, nil);
  HotkeysHooked := True;
end;

{ ---------------------------------------------------------------- panel }

procedure BRecord(b: Pointer; data: gpointer); cdecl; begin StartRecording; end;
procedure BStop(b: Pointer; data: gpointer); cdecl; begin StopRecording; end;
procedure BPlay(b: Pointer; data: gpointer); cdecl; begin PlayMacro(Panel.Selected); end;
procedure BNew(b: Pointer; data: gpointer); cdecl;
var
  m: TMacro;
begin
  m := TMacro.Create;
  m.Name := 'Macro ' + IntToStr(Macros.Count + 1);
  while FindMacro(m.Name) <> nil do m.Name := m.Name + '+';
  if EditMacroDialog(m, True) then
  begin
    Macros.Add(m);
    SaveMacros;
    Panel.Rebuild;
  end
  else
    m.Free;
end;
procedure BEdit(b: Pointer; data: gpointer); cdecl;
var
  m: TMacro;
begin
  m := Panel.Selected;
  if (m <> nil) and EditMacroDialog(m, False) then
  begin
    SaveMacros;
    Panel.Rebuild;
  end;
end;
procedure BDelete(b: Pointer; data: gpointer); cdecl;
var
  m: TMacro;
begin
  m := Panel.Selected;
  if (m <> nil) and AskYesNo('Delete the macro "' + m.Name + '"?', '') then
  begin
    Macros.Remove(m);
    m.Free;
    SaveMacros;
    Panel.Rebuild;
  end;
end;
procedure RowActivated(view: Pointer; path: Pointer; col: Pointer; data: gpointer); cdecl;
begin
  PlayMacro(Panel.Selected);
end;

constructor TMacroPanel.Create;
var
  tb, col, cell, scroll: Pointer;
  types: array[0..2] of GType;
  procedure Tool(const Icon, Tip: string; Cb: Pointer; out W: Pointer);
  begin
    W := NewFlatIconButton(Icon, Tip, 16);
    Connect(W, 'clicked', Cb, nil);
    gtk_box_pack_start(tb, W, False, False, 0);
  end;
var
  dummy: Pointer;
begin
  inherited Create;
  Widget := gtk_box_new(GTK_ORIENTATION_VERTICAL, 2);
  tb := gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0);
  AddClass(tb, 'lx-browser-toolbar');
  Tool('lx-record', 'Record a new macro in the current terminal', @BRecord, RecBtn);
  Tool('lx-stop', 'Stop recording', @BStop, StopBtn);
  Tool('lx-play', 'Play the selected macro in the current terminal', @BPlay, dummy);
  Tool('lx-add', 'New macro', @BNew, dummy);
  Tool('lx-edit', 'Edit the selected macro', @BEdit, dummy);
  Tool('lx-cancel', 'Delete the selected macro', @BDelete, dummy);
  gtk_box_pack_start(Widget, tb, False, False, 0);
  types[0] := gdk_pixbuf_get_type;
  types[1] := G_TYPE_STRING;
  types[2] := G_TYPE_STRING;
  Store := gtk_list_store_newv(3, @types[0]);
  View := gtk_tree_view_new_with_model(Store);
  g_object_unref(Store);
  gtk_tree_view_set_headers_visible(View, False);
  col := gtk_tree_view_column_new;
  cell := gtk_cell_renderer_pixbuf_new;
  gtk_tree_view_column_pack_start(col, cell, False);
  gtk_tree_view_column_add_attribute(col, cell, 'pixbuf', 0);
  cell := gtk_cell_renderer_text_new;
  gtk_cell_renderer_set_padding(cell, 4, 2);
  gtk_tree_view_column_pack_start(col, cell, True);
  gtk_tree_view_column_add_attribute(col, cell, 'markup', 1);
  gtk_tree_view_append_column(View, col);
  Connect(View, 'row-activated', @RowActivated, nil);
  scroll := gtk_scrolled_window_new(nil, nil);
  gtk_scrolled_window_set_policy(scroll, GTK_POLICY_AUTOMATIC, GTK_POLICY_AUTOMATIC);
  gtk_container_add(scroll, View);
  gtk_box_pack_start(Widget, scroll, True, True, 0);
  Status := NewLabel('', 0);
  gtk_label_set_line_wrap(Status, True);
  SetMargins(Status, 4);
  gtk_box_pack_start(Widget, Status, False, False, 0);
  Rebuild;
  UpdateStatus;
  gtk_widget_show_all(Widget);
end;

procedure TMacroPanel.Rebuild;
var
  i: Integer;
  it: TGtkTreeIter;
  m: TMacro;
  txt: string;
begin
  gtk_list_store_clear(Store);
  for i := 0 to Macros.Count - 1 do
  begin
    m := TMacro(Macros[i]);
    txt := '<b>' + MarkupEscape(m.Name) + '</b>';
    if m.Hotkey <> '' then txt := txt + '  <span foreground="#888888">' + MarkupEscape(m.Hotkey) + '</span>';
    gtk_list_store_append(Store, @it);
    gtk_list_store_set(Store, @it, 0, IconPixbuf('lx-macro', 16), 1, PChar(txt), 2, PChar(m.Name), -1);
  end;
end;

function TMacroPanel.Selected: TMacro;
var
  it: TGtkTreeIter;
  model: Pointer;
  p: PChar;
begin
  Result := nil;
  if not gtk_tree_selection_get_selected(gtk_tree_view_get_selection(View), @model, @it) then
  begin
    if Macros.Count = 1 then Result := TMacro(Macros[0]);
    Exit;
  end;
  p := nil;
  gtk_tree_model_get(model, @it, 2, @p, -1);
  Result := FindMacro(TakeStr(p));
end;

procedure TMacroPanel.UpdateStatus;
begin
  gtk_widget_set_sensitive(RecBtn, not Recording);
  gtk_widget_set_sensitive(StopBtn, Recording);
  if Recording then
    gtk_label_set_markup(Status, PChar('<span foreground="#c62828"><b>● Recording</b></span> ' +
      IntToStr(Length(RecBuf)) + ' keystroke(s)'))
  else if Macros.Count = 0 then
    gtk_label_set_markup(Status, '<span foreground="#888888">Click the red button to record the commands ' +
      'you type in a terminal.</span>')
  else
    gtk_label_set_markup(Status, '<span foreground="#888888">Double-click a macro to play it.</span>');
end;

function BuildPanel: Pointer;
begin
  if Panel = nil then Panel := TMacroPanel.Create;
  Result := Panel.Widget;
  HookHotkeys;
end;

{ ---------------------------------------------------------------- menu }

procedure MRecord(i: Pointer; d: gpointer); cdecl; begin StartRecording; end;
procedure MStop(i: Pointer; d: gpointer); cdecl; begin StopRecording; end;
procedure MPlay(i: Pointer; d: gpointer); cdecl;
begin
  PlayMacro(FindMacro(CStr(PChar(g_object_get_data(i, 'macro')))));
end;
procedure MNew(i: Pointer; d: gpointer); cdecl; begin BNew(nil, nil); end;

procedure FreeNotify(data: gpointer); cdecl;
begin
  g_free(data);
end;

procedure BuildMenu(Menu: Pointer);
var
  i: Integer;
  item: Pointer;
begin
  NewImageMenuItem(Menu, '_Record a new macro', 'media-record', @MRecord, nil);
  NewImageMenuItem(Menu, '_Stop recording', 'media-playback-stop', @MStop, nil);
  NewImageMenuItem(Menu, '_New macro...', 'list-add', @MNew, nil);
  NewMenuSeparator(Menu);
  for i := 0 to Macros.Count - 1 do
  begin
    item := NewImageMenuItem(Menu, 'Play "' + TMacro(Macros[i]).Name + '"' +
      IfThen(TMacro(Macros[i]).Hotkey <> '', '   (' + TMacro(Macros[i]).Hotkey + ')', ''), 'lx-macro', nil, nil);
    g_object_set_data_full(item, 'macro', g_strdup(PChar(TMacro(Macros[i]).Name)), @FreeNotify);
    Connect(item, 'activate', @MPlay, nil);
  end;
  if Macros.Count = 0 then
    gtk_widget_set_sensitive(NewMenuItem(Menu, '(no macro)', nil, nil), False);
end;

function TestHook(const Cmd, Arg: string): Boolean;
begin
  Result := True;
  if Cmd = 'macrorec' then StartRecording
  else if Cmd = 'macrostop' then StopRecording
  else if Cmd = 'macroplay' then PlayMacro(FindMacro(Arg))
  else Result := False;
end;

procedure HookStartup;
begin
  HookHotkeys;
end;

initialization
  LoadMacros;
  BuildMacrosPanelProc := @BuildPanel;
  BuildMacrosMenuProc := @BuildMenu;
  MacroInputProc := @MacroInput;
  MacroTextByName := @MacroText;
  MacroNamesProvider := @MacroNames;
  RegisterStartup(@HookStartup);
  SetLength(TestHooks, Length(TestHooks) + 1);
  TestHooks[High(TestHooks)] := @TestHook;

end.

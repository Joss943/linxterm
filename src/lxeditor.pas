{ LinXterm - text editor (MobaTextEditor equivalent): tabs, syntax
  highlighting with GtkSourceView 4, find / replace, line numbers. }
unit lxeditor;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, StrUtils, BaseUnix, lxgtk, lxutil, lxconfig, lxtabs, lxdyn;

procedure OpenTextEditor(const FileName: string);

implementation

type
  TEditorWindow = class;

  TEditorDoc = class
  public
    Owner: TEditorWindow;
    FileName: string;
    Buffer, View, Scroll, LabelW, Page: Pointer;
    IsSource: Boolean;
    procedure UpdateLabel;
    function Modified: Boolean;
    function Title: string;
  end;

  TEditorWindow = class
  public
    Window, Notebook, FindEntry, ReplaceEntry, CaseCheck, StatusPos, StatusLang, LangCombo, WrapCheck: Pointer;
    Docs: TList;
    constructor Create;
    destructor Destroy; override;
    function Current: TEditorDoc;
    function NewDoc(const FileName: string): TEditorDoc;
    function OpenFile(const FileName: string): Boolean;
    function SaveDoc(D: TEditorDoc; SaveAs: Boolean): Boolean;
    function CloseDoc(D: TEditorDoc): Boolean;
    function CloseAll: Boolean;
    procedure Find(Backward: Boolean);
    procedure Replace(All: Boolean);
    procedure UpdateStatus;
    procedure SetLanguage(D: TEditorDoc; const Id: string);
    procedure ApplyWrap;
  end;

var
  Editor: TEditorWindow = nil;

const
  Languages: array[0..19] of string = ('', 'sh', 'python3', 'c', 'cpp', 'pascal', 'java', 'js', 'json', 'xml',
    'html', 'css', 'yaml', 'ini', 'markdown', 'sql', 'php', 'perl', 'ruby', 'diff');

{ ---------------------------------------------------------------- doc }

function TEditorDoc.Modified: Boolean;
begin
  Result := gtk_text_buffer_get_modified(Buffer);
end;

function TEditorDoc.Title: string;
begin
  if FileName = '' then Result := 'Untitled' else Result := ExtractFileName(FileName);
end;

procedure TEditorDoc.UpdateLabel;
var
  t: string;
begin
  t := Title;
  if Modified then t := '*' + t;
  gtk_label_set_text(LabelW, PChar(t));
  if FileName <> '' then gtk_widget_set_tooltip_text(LabelW, PChar(FileName));
end;

{ ---------------------------------------------------------------- callbacks }

procedure ModifiedChanged(buf: Pointer; data: gpointer); cdecl;
begin
  TEditorDoc(data).UpdateLabel;
end;

procedure CursorMoved(buf: Pointer; spec: Pointer; data: gpointer); cdecl;
begin
  if Editor <> nil then Editor.UpdateStatus;
end;

function SwitchIdle(data: gpointer): gboolean; cdecl;
begin
  if Editor <> nil then Editor.UpdateStatus;
  Result := False;
end;

procedure SwitchPage(nb: Pointer; page: Pointer; num: guint; data: gpointer); cdecl;
begin
  if Editor <> nil then g_idle_add(@SwitchIdle, nil);
end;

procedure CloseTabClicked(b: Pointer; data: gpointer); cdecl;
begin
  TEditorDoc(data).Owner.CloseDoc(TEditorDoc(data));
end;

procedure TbNew(b: Pointer; data: gpointer); cdecl; begin Editor.NewDoc(''); end;
procedure TbOpen(b: Pointer; data: gpointer); cdecl;
var
  files: TStringArray;
  i: Integer;
  dir: string;
begin
  dir := HomeDir;
  if (Editor.Current <> nil) and (Editor.Current.FileName <> '') then dir := ExtractFileDir(Editor.Current.FileName);
  if ChooseOpenFiles('Open files', dir, files) then
    for i := 0 to High(files) do Editor.OpenFile(files[i]);
end;
procedure TbSave(b: Pointer; data: gpointer); cdecl;
begin
  if Editor.Current <> nil then Editor.SaveDoc(Editor.Current, False);
end;
procedure TbSaveAs(b: Pointer; data: gpointer); cdecl;
begin
  if Editor.Current <> nil then Editor.SaveDoc(Editor.Current, True);
end;
procedure TbUndo(b: Pointer; data: gpointer); cdecl;
var
  d: TEditorDoc;
begin
  d := Editor.Current;
  if (d <> nil) and d.IsSource and gtk_source_buffer_can_undo(d.Buffer) then gtk_source_buffer_undo(d.Buffer);
end;
procedure TbRedo(b: Pointer; data: gpointer); cdecl;
var
  d: TEditorDoc;
begin
  d := Editor.Current;
  if (d <> nil) and d.IsSource and gtk_source_buffer_can_redo(d.Buffer) then gtk_source_buffer_redo(d.Buffer);
end;
procedure TbFindNext(b: Pointer; data: gpointer); cdecl; begin Editor.Find(False); end;
procedure TbFindPrev(b: Pointer; data: gpointer); cdecl; begin Editor.Find(True); end;
procedure TbReplace(b: Pointer; data: gpointer); cdecl; begin Editor.Replace(False); end;
procedure TbReplaceAll(b: Pointer; data: gpointer); cdecl; begin Editor.Replace(True); end;
procedure TbWrap(b: Pointer; data: gpointer); cdecl; begin Editor.ApplyWrap; end;
procedure LangChanged(c: Pointer; data: gpointer); cdecl;
begin
  if Editor.Current <> nil then
    Editor.SetLanguage(Editor.Current, CStr(gtk_combo_box_get_active_id(c)));
end;

function WinDelete(w: Pointer; ev: Pointer; data: gpointer): gboolean; cdecl;
begin
  Result := not Editor.CloseAll;
  if not Result then
  begin
    gtk_widget_destroy(Editor.Window);
    FreeAndNil(Editor);
    Result := True;
  end;
end;

function WinKey(w: Pointer; ev: Pointer; data: gpointer): gboolean; cdecl;
var
  kv, st: guint;
begin
  Result := False;
  kv := gdk_keyval_to_lower(EventKeyval(ev));
  st := EventState(ev) and (GDK_CONTROL_MASK or GDK_SHIFT_MASK or GDK_MOD1_MASK);
  if st = GDK_CONTROL_MASK then
  begin
    Result := True;
    case kv of
      Ord('s'): TbSave(nil, nil);
      Ord('o'): TbOpen(nil, nil);
      Ord('n'): TbNew(nil, nil);
      Ord('f'): gtk_widget_grab_focus(Editor.FindEntry);
      Ord('h'): gtk_widget_grab_focus(Editor.ReplaceEntry);
      Ord('w'): if Editor.Current <> nil then Editor.CloseDoc(Editor.Current);
    else
      Result := False;
    end;
  end
  else if st = (GDK_CONTROL_MASK or GDK_SHIFT_MASK) then
  begin
    if kv = Ord('s') then
    begin
      TbSaveAs(nil, nil);
      Result := True;
    end;
  end
  else if kv = GDK_KEY_F3 then
  begin
    Editor.Find((st and GDK_SHIFT_MASK) <> 0);
    Result := True;
  end;
end;

procedure FindActivate(e: Pointer; data: gpointer); cdecl;
begin
  Editor.Find(False);
end;

procedure DropReceived(widget: Pointer; ctx: Pointer; x, y: gint; seldata: Pointer; info: guint; time: guint32; data: gpointer); cdecl;
var
  uris, p: PPChar;
  fn: string;
begin
  uris := gtk_selection_data_get_uris(seldata);
  if uris = nil then Exit;
  p := uris;
  while p^ <> nil do
  begin
    fn := TakeStr(g_filename_from_uri(p^, nil, nil));
    if fn <> '' then Editor.OpenFile(fn);
    Inc(p);
  end;
  g_strfreev(uris);
  gtk_drag_finish(ctx, True, False, time);
end;

{ ---------------------------------------------------------------- window }

var
  UriTarget: array[0..0] of TGtkTargetEntry = ((target: 'text/uri-list'; flags: 0; info: 1));

constructor TEditorWindow.Create;
var
  vbox, tb, b, status, sep: Pointer;
  i: Integer;
  procedure Tool(const Icon, Tip: string; Cb: Pointer);
  var
    btn: Pointer;
  begin
    btn := NewFlatIconButton(Icon, Tip, 16);
    Connect(btn, 'clicked', Cb, nil);
    gtk_box_pack_start(tb, btn, False, False, 0);
  end;
begin
  inherited Create;
  Docs := TList.Create;
  Window := gtk_window_new(GTK_WINDOW_TOPLEVEL);
  gtk_window_set_title(Window, 'LinXterm text editor');
  gtk_window_set_default_size(Window, 980, 700);
  gtk_window_set_icon(Window, IconPixbuf('accessories-text-editor', 64));
  AddClass(Window, 'lx-main');
  vbox := gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
  gtk_container_add(Window, vbox);
  tb := gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 2);
  AddClass(tb, 'lx-toolbar');
  Tool('lx-file-new', 'New (Ctrl+N)', @TbNew);
  Tool('lx-open', 'Open (Ctrl+O)', @TbOpen);
  Tool('lx-save', 'Save (Ctrl+S)', @TbSave);
  Tool('document-save-as', 'Save as (Ctrl+Shift+S)', @TbSaveAs);
  sep := gtk_separator_new(GTK_ORIENTATION_VERTICAL);
  gtk_box_pack_start(tb, sep, False, False, 4);
  Tool('edit-undo', 'Undo (Ctrl+Z)', @TbUndo);
  Tool('edit-redo', 'Redo (Ctrl+Shift+Z)', @TbRedo);
  sep := gtk_separator_new(GTK_ORIENTATION_VERTICAL);
  gtk_box_pack_start(tb, sep, False, False, 4);
  FindEntry := gtk_search_entry_new;
  gtk_entry_set_placeholder_text(FindEntry, 'Find (Ctrl+F)');
  gtk_entry_set_width_chars(FindEntry, 18);
  Connect(FindEntry, 'activate', @FindActivate, nil);
  gtk_box_pack_start(tb, FindEntry, False, False, 0);
  Tool('go-up', 'Previous match (Shift+F3)', @TbFindPrev);
  Tool('go-down', 'Next match (F3)', @TbFindNext);
  CaseCheck := gtk_check_button_new_with_label('Aa');
  gtk_widget_set_tooltip_text(CaseCheck, 'Match case');
  gtk_box_pack_start(tb, CaseCheck, False, False, 2);
  ReplaceEntry := gtk_entry_new;
  gtk_entry_set_placeholder_text(ReplaceEntry, 'Replace with (Ctrl+H)');
  gtk_entry_set_width_chars(ReplaceEntry, 16);
  gtk_box_pack_start(tb, ReplaceEntry, False, False, 4);
  b := gtk_button_new_with_label('Replace');
  Connect(b, 'clicked', @TbReplace, nil);
  gtk_box_pack_start(tb, b, False, False, 0);
  b := gtk_button_new_with_label('All');
  Connect(b, 'clicked', @TbReplaceAll, nil);
  gtk_box_pack_start(tb, b, False, False, 0);
  WrapCheck := gtk_check_button_new_with_label('Word wrap');
  Connect(WrapCheck, 'toggled', @TbWrap, nil);
  gtk_box_pack_end(tb, WrapCheck, False, False, 4);
  LangCombo := gtk_combo_box_text_new;
  gtk_combo_box_text_append(LangCombo, '', 'Plain text');
  for i := 1 to High(Languages) do
    gtk_combo_box_text_append(LangCombo, PChar(Languages[i]), PChar(Languages[i]));
  gtk_combo_box_set_active(LangCombo, 0);
  Connect(LangCombo, 'changed', @LangChanged, nil);
  gtk_widget_set_sensitive(LangCombo, SourceViewAvailable);
  gtk_box_pack_end(tb, LangCombo, False, False, 0);
  gtk_box_pack_start(vbox, tb, False, False, 0);
  Notebook := gtk_notebook_new;
  gtk_notebook_set_scrollable(Notebook, True);
  Connect(Notebook, 'switch-page', @SwitchPage, nil);
  gtk_box_pack_start(vbox, Notebook, True, True, 0);
  status := gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 12);
  AddClass(status, 'lx-status');
  StatusPos := NewLabel('', 0);
  gtk_box_pack_start(status, StatusPos, False, False, 0);
  StatusLang := NewLabel('', 1);
  gtk_box_pack_end(status, StatusLang, False, False, 0);
  gtk_box_pack_end(status, NewLabel('UTF-8', 1), False, False, 0);
  gtk_box_pack_start(vbox, status, False, False, 0);
  gtk_drag_dest_set(Window, GTK_DEST_DEFAULT_ALL, @UriTarget[0], 1, GDK_ACTION_COPY);
  Connect(Window, 'drag-data-received', @DropReceived, nil);
  Connect(Window, 'delete-event', @WinDelete, nil);
  Connect(Window, 'key-press-event', @WinKey, nil);
  gtk_widget_show_all(Window);
end;

destructor TEditorWindow.Destroy;
var
  i: Integer;
begin
  for i := 0 to Docs.Count - 1 do TEditorDoc(Docs[i]).Free;
  Docs.Free;
  inherited Destroy;
end;

function TEditorWindow.Current: TEditorDoc;
var
  n: Integer;
  page: Pointer;
  i: Integer;
begin
  Result := nil;
  n := gtk_notebook_get_current_page(Notebook);
  if n < 0 then Exit;
  page := gtk_notebook_get_nth_page(Notebook, n);
  for i := 0 to Docs.Count - 1 do
    if TEditorDoc(Docs[i]).Page = page then Exit(TEditorDoc(Docs[i]));
end;

function TEditorWindow.NewDoc(const FileName: string): TEditorDoc;
var
  d: TEditorDoc;
  hb, b: Pointer;
  scheme: Pointer;
  n: Integer;
begin
  d := TEditorDoc.Create;
  d.Owner := Self;
  d.FileName := FileName;
  d.IsSource := SourceViewAvailable;
  if d.IsSource then
  begin
    d.Buffer := gtk_source_buffer_new(nil);
    d.View := gtk_source_view_new_with_buffer(d.Buffer);
    g_object_unref(d.Buffer);
    gtk_source_view_set_show_line_numbers(d.View, True);
    gtk_source_view_set_highlight_current_line(d.View, True);
    gtk_source_view_set_auto_indent(d.View, True);
    gtk_source_view_set_tab_width(d.View, 4);
    scheme := gtk_source_style_scheme_manager_get_scheme(gtk_source_style_scheme_manager_get_default(),
      PChar(IfThen(Settings.Skin = 'dark', 'oblivion', 'classic')));
    if scheme <> nil then gtk_source_buffer_set_style_scheme(d.Buffer, scheme);
  end
  else
  begin
    d.Buffer := gtk_text_buffer_new(nil);
    d.View := gtk_text_view_new_with_buffer(d.Buffer);
    g_object_unref(d.Buffer);
  end;
  gtk_text_view_set_monospace(d.View, True);
  gtk_text_view_set_left_margin(d.View, 4);
  if gtk_toggle_button_get_active(WrapCheck) then
    gtk_text_view_set_wrap_mode(d.View, GTK_WRAP_WORD_CHAR);
  d.Scroll := NewScrolled(d.View);
  d.Page := d.Scroll;
  hb := gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 4);
  d.LabelW := gtk_label_new('');
  gtk_box_pack_start(hb, d.LabelW, True, True, 0);
  b := NewFlatIconButton('window-close-symbolic', 'Close (Ctrl+W)', 12);
  gtk_button_set_image(b, gtk_image_new_from_icon_name('window-close-symbolic', GTK_ICON_SIZE_MENU));
  Connect(b, 'clicked', @CloseTabClicked, d);
  gtk_box_pack_start(hb, b, False, False, 0);
  gtk_widget_show_all(hb);
  Docs.Add(d);
  n := gtk_notebook_append_page(Notebook, d.Scroll, hb);
  gtk_notebook_set_tab_reorderable(Notebook, d.Scroll, True);
  Connect(d.Buffer, 'modified-changed', @ModifiedChanged, d);
  Connect(d.Buffer, 'notify::cursor-position', @CursorMoved, d);
  d.UpdateLabel;
  gtk_widget_show_all(d.Scroll);
  gtk_notebook_set_current_page(Notebook, n);
  gtk_widget_grab_focus(d.View);
  Result := d;
end;

function TEditorWindow.OpenFile(const FileName: string): Boolean;
var
  i: Integer;
  txt, conv: string;
  d: TEditorDoc;
  it: TGtkTextIter;
  lang: Pointer;
begin
  Result := False;
  for i := 0 to Docs.Count - 1 do
    if TEditorDoc(Docs[i]).FileName = FileName then
    begin
      gtk_notebook_set_current_page(Notebook, gtk_notebook_page_num(Notebook, TEditorDoc(Docs[i]).Page));
      Exit(True);
    end;
  if not FileExists(FileName) then
    txt := ''
  else if not ReadFileText(FileName, txt) then
  begin
    MsgError('Unable to open the file', FileName);
    Exit;
  end;
  if (Length(txt) > 0) and (Pos(#0, Copy(txt, 1, 8000)) > 0) then
  begin
    if not AskYesNo('This looks like a binary file', 'Open "' + FileName + '" anyway?') then Exit;
    txt := StringReplace(txt, #0, '?', [rfReplaceAll]);
  end;
  if not g_utf8_validate(PChar(txt), Length(txt), nil) then
  begin
    conv := TakeStr(g_convert_with_fallback(PChar(txt), Length(txt), 'UTF-8', 'ISO-8859-15', '?', nil, nil, nil));
    if conv <> '' then txt := conv;
  end;
  { reuse an empty untitled document }
  d := Current;
  if (d = nil) or (d.FileName <> '') or d.Modified or (gtk_text_buffer_get_char_count(d.Buffer) > 0) then
    d := NewDoc(FileName)
  else
    d.FileName := FileName;
  if d.IsSource then gtk_source_buffer_begin_not_undoable_action(d.Buffer);
  gtk_text_buffer_set_text(d.Buffer, PChar(txt), Length(txt));
  if d.IsSource then gtk_source_buffer_end_not_undoable_action(d.Buffer);
  gtk_text_buffer_get_start_iter(d.Buffer, @it);
  gtk_text_buffer_place_cursor(d.Buffer, @it);
  gtk_text_buffer_set_modified(d.Buffer, False);
  if d.IsSource then
  begin
    lang := gtk_source_language_manager_guess_language(gtk_source_language_manager_get_default(), PChar(FileName), nil);
    if lang <> nil then gtk_source_buffer_set_language(d.Buffer, lang);
  end;
  d.UpdateLabel;
  UpdateStatus;
  Result := True;
end;

function TEditorWindow.SaveDoc(D: TEditorDoc; SaveAs: Boolean): Boolean;
var
  fn, txt: string;
  lang: Pointer;
begin
  Result := False;
  fn := D.FileName;
  if SaveAs or (fn = '') then
  begin
    if fn <> '' then
    begin
      if not ChooseSaveFile('Save as', ExtractFileDir(fn), ExtractFileName(fn), fn) then Exit;
    end
    else if not ChooseSaveFile('Save as', HomeDir, 'untitled.txt', fn) then Exit;
  end;
  txt := TextBufferText(D.Buffer);
  if not WriteFileText(fn, txt) then
  begin
    MsgError('Unable to save the file', fn + #10 + SysErrorMessage(fpGetErrno));
    Exit;
  end;
  if D.FileName <> fn then
  begin
    D.FileName := fn;
    if D.IsSource then
    begin
      lang := gtk_source_language_manager_guess_language(gtk_source_language_manager_get_default(), PChar(fn), nil);
      if lang <> nil then gtk_source_buffer_set_language(D.Buffer, lang);
    end;
  end;
  gtk_text_buffer_set_modified(D.Buffer, False);
  D.UpdateLabel;
  UpdateStatus;
  Result := True;
end;

function TEditorWindow.CloseDoc(D: TEditorDoc): Boolean;
var
  dlg: Pointer;
  r: Integer;
begin
  Result := True;
  if D.Modified then
  begin
    dlg := gtk_message_dialog_new(Window, GTK_DIALOG_MODAL, GTK_MESSAGE_QUESTION, GTK_BUTTONS_NONE, '%s',
      PChar('Save the changes to "' + D.Title + '"?'));
    gtk_dialog_add_button(dlg, 'Close _without saving', GTK_RESPONSE_NO);
    gtk_dialog_add_button(dlg, '_Cancel', GTK_RESPONSE_CANCEL);
    gtk_dialog_add_button(dlg, '_Save', GTK_RESPONSE_YES);
    gtk_dialog_set_default_response(dlg, GTK_RESPONSE_YES);
    r := gtk_dialog_run(dlg);
    gtk_widget_destroy(dlg);
    if r = GTK_RESPONSE_YES then
    begin
      if not SaveDoc(D, False) then Exit(False);
    end
    else if r <> GTK_RESPONSE_NO then
      Exit(False);
  end;
  Docs.Remove(D);
  gtk_notebook_remove_page(Notebook, gtk_notebook_page_num(Notebook, D.Page));
  D.Free;
  if Docs.Count = 0 then NewDoc('');
end;

function TEditorWindow.CloseAll: Boolean;
var
  i: Integer;
  d: TEditorDoc;
begin
  Result := True;
  for i := Docs.Count - 1 downto 0 do
  begin
    d := TEditorDoc(Docs[i]);
    if d.Modified then
    begin
      gtk_notebook_set_current_page(Notebook, gtk_notebook_page_num(Notebook, d.Page));
      if not CloseDoc(d) then Exit(False);
    end;
  end;
end;

procedure TEditorWindow.UpdateStatus;
var
  d: TEditorDoc;
  it: TGtkTextIter;
  lang: string;
  l: Pointer;
begin
  l := nil;
  d := Current;
  if d = nil then Exit;
  gtk_text_buffer_get_iter_at_mark(d.Buffer, @it, gtk_text_buffer_get_insert(d.Buffer));
  gtk_label_set_text(StatusPos, PChar(Format('Line %d, Column %d   |   %d lines', [gtk_text_iter_get_line(@it) + 1,
    gtk_text_iter_get_line_offset(@it) + 1, gtk_text_buffer_get_line_count(d.Buffer)])));
  lang := 'Plain text';
  if d.IsSource then
  begin
    l := gtk_source_buffer_get_language(d.Buffer);
    if l <> nil then lang := CStr(gtk_source_language_get_name(l));
  end;
  if d.FileName <> '' then
    gtk_window_set_title(Window, PChar(d.FileName + ' - LinXterm text editor'))
  else
    gtk_window_set_title(Window, 'Untitled - LinXterm text editor');
  gtk_label_set_text(StatusLang, PChar(lang));
  { keep the language selector in sync without re-applying it }
  g_signal_handlers_block_by_func(LangCombo, @LangChanged, nil);
  if (l = nil) or not gtk_combo_box_set_active_id(LangCombo, gtk_source_language_get_id(l)) then
    gtk_combo_box_set_active(LangCombo, 0);
  g_signal_handlers_unblock_by_func(LangCombo, @LangChanged, nil);
end;

procedure TEditorWindow.SetLanguage(D: TEditorDoc; const Id: string);
var
  lang: Pointer;
begin
  if not D.IsSource then Exit;
  if Id = '' then
    gtk_source_buffer_set_language(D.Buffer, nil)
  else
  begin
    lang := gtk_source_language_manager_get_language(gtk_source_language_manager_get_default(), PChar(Id));
    if lang <> nil then gtk_source_buffer_set_language(D.Buffer, lang);
  end;
end;

procedure TEditorWindow.ApplyWrap;
var
  i: Integer;
  mode: Integer;
begin
  if gtk_toggle_button_get_active(WrapCheck) then mode := GTK_WRAP_WORD_CHAR else mode := GTK_WRAP_NONE;
  for i := 0 to Docs.Count - 1 do
    gtk_text_view_set_wrap_mode(TEditorDoc(Docs[i]).View, mode);
end;

procedure TEditorWindow.Find(Backward: Boolean);
var
  d: TEditorDoc;
  txt: string;
  it, ms, me, a, b: TGtkTextIter;
  flags: gint;
  found: Boolean;
begin
  d := Current;
  if d = nil then Exit;
  txt := EntryText(FindEntry);
  if txt = '' then Exit;
  { GTK_TEXT_SEARCH_CASE_INSENSITIVE = 4 }
  if gtk_toggle_button_get_active(CaseCheck) then flags := 0 else flags := 4;
  if gtk_text_buffer_get_selection_bounds(d.Buffer, @a, @b) then
  begin
    if Backward then it := a else it := b;
  end
  else
    gtk_text_buffer_get_iter_at_mark(d.Buffer, @it, gtk_text_buffer_get_insert(d.Buffer));
  if Backward then
    found := gtk_text_iter_backward_search(@it, PChar(txt), flags, @ms, @me, nil)
  else
    found := gtk_text_iter_forward_search(@it, PChar(txt), flags, @ms, @me, nil);
  if not found then
  begin
    { wrap around }
    if Backward then gtk_text_buffer_get_end_iter(d.Buffer, @it) else gtk_text_buffer_get_start_iter(d.Buffer, @it);
    if Backward then
      found := gtk_text_iter_backward_search(@it, PChar(txt), flags, @ms, @me, nil)
    else
      found := gtk_text_iter_forward_search(@it, PChar(txt), flags, @ms, @me, nil);
  end;
  if found then
  begin
    gtk_text_buffer_select_range(d.Buffer, @ms, @me);
    gtk_text_view_scroll_to_iter(d.View, @ms, 0.1, False, 0, 0);
  end
  else
    gdk_display_beep(gdk_display_get_default);
end;

procedure TEditorWindow.Replace(All: Boolean);
var
  d: TEditorDoc;
  txt, rep, sel: string;
  a, b, it, ms, me: TGtkTextIter;
  flags: gint;
  n: Integer;
begin
  d := Current;
  if d = nil then Exit;
  txt := EntryText(FindEntry);
  rep := EntryText(ReplaceEntry);
  if txt = '' then Exit;
  if gtk_toggle_button_get_active(CaseCheck) then flags := 0 else flags := 4;
  if All then
  begin
    n := 0;
    gtk_text_buffer_begin_user_action(d.Buffer);
    gtk_text_buffer_get_start_iter(d.Buffer, @it);
    while gtk_text_iter_forward_search(@it, PChar(txt), flags, @ms, @me, nil) do
    begin
      gtk_text_buffer_delete(d.Buffer, @ms, @me);
      gtk_text_buffer_insert(d.Buffer, @ms, PChar(rep), Length(rep));
      it := ms;
      Inc(n);
      if n > 1000000 then Break;
    end;
    gtk_text_buffer_end_user_action(d.Buffer);
    gtk_label_set_text(StatusPos, PChar(IntToStr(n) + ' replacement(s)'));
    Exit;
  end;
  if gtk_text_buffer_get_selection_bounds(d.Buffer, @a, @b) then
  begin
    sel := TakeStr(gtk_text_buffer_get_text(d.Buffer, @a, @b, True));
    if (sel = txt) or ((flags = 4) and SameText(sel, txt)) then
    begin
      gtk_text_buffer_begin_user_action(d.Buffer);
      gtk_text_buffer_delete(d.Buffer, @a, @b);
      gtk_text_buffer_insert(d.Buffer, @a, PChar(rep), Length(rep));
      gtk_text_buffer_end_user_action(d.Buffer);
    end;
  end;
  Find(False);
end;

procedure OpenTextEditor(const FileName: string);
begin
  if Editor = nil then
  begin
    Editor := TEditorWindow.Create;
    if FileName = '' then Editor.NewDoc('');
  end;
  if FileName <> '' then Editor.OpenFile(FileName);
  gtk_window_present(Editor.Window);
end;

initialization
  OpenEditorProc := @OpenTextEditor;

end.

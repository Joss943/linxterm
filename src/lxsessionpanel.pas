{ LinXterm - "Sessions" side panel: the "User sessions" tree with folders. }
unit lxsessionpanel;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, lxgtk, lxutil, lxconfig, lxtabs;

type
  TSessionsPanel = class
  private
    FStore: Pointer;
    FView: Pointer;
    FFilter: string;
    FExpanded: TStringList;
    FMatches: TList;
    procedure AddFolderNode(const Path: string; Parent: PGtkTreeIter; out Iter: TGtkTreeIter);
    function FindFolderIter(const Path: string; out Iter: TGtkTreeIter): Boolean;
    procedure SaveExpanded;
  public
    Widget: Pointer;
    constructor Create;
    destructor Destroy; override;
    procedure Rebuild;
    procedure ExpandAll;
    procedure SetFilter(const F: string);
    function SingleMatch: TSession;
    function SelectedKind(out Key: string): Integer;
    function SelectedSession: TSession;
    procedure PopupMenu(Event: Pointer);
    procedure RowActivated;
    procedure NewSessionIn(const Folder: string);
    procedure NewFolderIn(const Parent: string);
    procedure DeleteSelected;
    procedure RenameSelected;
    procedure DuplicateSelected;
    procedure MoveSessionTo(S: TSession; const Folder: string);
    procedure DragGet(SelData: Pointer);
    procedure DragReceived(X, Y: Integer; SelData: Pointer; Ctx: Pointer; Time: guint32);
  end;

implementation

uses
  StrUtils, lxsessiondlg;

const
  COL_ICON = 0;
  COL_TEXT = 1;
  COL_KIND = 2;
  COL_KEY = 3;
  COL_TIP = 4;

  KIND_ROOT = 0;
  KIND_FOLDER = 1;
  KIND_SESSION = 2;

var
  DndTargets: array[0..0] of TGtkTargetEntry = ((target: 'LINXTERM_SESSION'; flags: GTK_TARGET_SAME_APP; info: 1));

{ ---------------------------------------------------------------- callbacks }

procedure RowActivatedCb(view: Pointer; path: Pointer; col: Pointer; data: gpointer); cdecl;
begin
  TSessionsPanel(data).RowActivated;
end;

function ButtonPressCb(widget: Pointer; event: Pointer; data: gpointer): gboolean; cdecl;
var
  path: Pointer;
  x, y: gdouble;
begin
  Result := False;
  if (gdk_event_get_event_type(event) = GDK_BUTTON_PRESS) and (EventButton(event) = 3) then
  begin
    gdk_event_get_coords(event, @x, @y);
    path := nil;
    gtk_tree_selection_unselect_all(gtk_tree_view_get_selection(widget));
    { a click on an empty area shows the "User sessions" menu }
    if gtk_tree_view_get_path_at_pos(widget, Trunc(x), Trunc(y), @path, nil, nil, nil) then
    begin
      gtk_tree_selection_select_path(gtk_tree_view_get_selection(widget), path);
      gtk_tree_path_free(path);
    end;
    TSessionsPanel(data).PopupMenu(event);
    Result := True;
  end;
end;

function KeyPressCb(widget: Pointer; event: Pointer; data: gpointer): gboolean; cdecl;
var
  kv: guint;
begin
  Result := False;
  kv := EventKeyval(event);
  if kv = GDK_KEY_Delete then
  begin
    TSessionsPanel(data).DeleteSelected;
    Result := True;
  end
  else if kv = GDK_KEY_F2 then
  begin
    TSessionsPanel(data).RenameSelected;
    Result := True;
  end;
end;

procedure RowExpandedCb(view: Pointer; iter: PGtkTreeIter; path: Pointer; data: gpointer); cdecl;
begin
  TSessionsPanel(data).SaveExpanded;
end;

procedure DragGetCb(widget: Pointer; ctx: Pointer; seldata: Pointer; info: guint; time: guint32; data: gpointer); cdecl;
begin
  TSessionsPanel(data).DragGet(seldata);
end;

procedure DragReceivedCb(widget: Pointer; ctx: Pointer; x, y: gint; seldata: Pointer; info: guint; time: guint32; data: gpointer); cdecl;
begin
  g_signal_stop_emission_by_name(widget, 'drag-data-received');
  TSessionsPanel(data).DragReceived(x, y, seldata, ctx, time);
end;

{ menu actions }
procedure MConnect(item: Pointer; data: gpointer); cdecl;
begin
  TSessionsPanel(data).RowActivated;
end;

procedure MEdit(item: Pointer; data: gpointer); cdecl;
var
  s: TSession;
begin
  s := TSessionsPanel(data).SelectedSession;
  if s <> nil then App.EditSession(s);
end;

procedure MRename(item: Pointer; data: gpointer); cdecl;
begin
  TSessionsPanel(data).RenameSelected;
end;

procedure MDuplicate(item: Pointer; data: gpointer); cdecl;
begin
  TSessionsPanel(data).DuplicateSelected;
end;

procedure MDelete(item: Pointer; data: gpointer); cdecl;
begin
  TSessionsPanel(data).DeleteSelected;
end;

procedure MShortcut(item: Pointer; data: gpointer); cdecl;
var
  s: TSession;
begin
  s := TSessionsPanel(data).SelectedSession;
  if s <> nil then CreateDesktopShortcut(s);
end;

procedure MNewSession(item: Pointer; data: gpointer); cdecl;
var
  key: string;
  k: Integer;
begin
  k := TSessionsPanel(data).SelectedKind(key);
  if k = KIND_FOLDER then
    TSessionsPanel(data).NewSessionIn(key)
  else
    TSessionsPanel(data).NewSessionIn('');
end;

procedure MNewFolder(item: Pointer; data: gpointer); cdecl;
var
  key: string;
  k: Integer;
begin
  k := TSessionsPanel(data).SelectedKind(key);
  if k = KIND_FOLDER then
    TSessionsPanel(data).NewFolderIn(key)
  else
    TSessionsPanel(data).NewFolderIn('');
end;

procedure MOpenFolder(item: Pointer; data: gpointer); cdecl;
var
  key: string;
begin
  if TSessionsPanel(data).SelectedKind(key) = KIND_FOLDER then
    App.OpenFolder(key, PtrInt(g_object_get_data(item, 'layout')));
end;

procedure MExpandAll(item: Pointer; data: gpointer); cdecl;
begin
  TSessionsPanel(data).ExpandAll;
end;

procedure MCollapseAll(item: Pointer; data: gpointer); cdecl;
var
  p: TSessionsPanel;
  path: Pointer;
  it: TGtkTreeIter;
  child: TGtkTreeIter;
begin
  p := TSessionsPanel(data);
  if gtk_tree_model_get_iter_first(p.FStore, @it) then
    if gtk_tree_model_iter_children(p.FStore, @child, @it) then
      repeat
        path := gtk_tree_model_get_path(p.FStore, @child);
        gtk_tree_view_collapse_row(p.FView, path);
        gtk_tree_path_free(path);
      until not gtk_tree_model_iter_next(p.FStore, @child);
end;

procedure MMoveTo(item: Pointer; data: gpointer); cdecl;
var
  p: TSessionsPanel;
  s: TSession;
begin
  p := TSessionsPanel(data);
  s := p.SelectedSession;
  if s <> nil then
    p.MoveSessionTo(s, CStr(PChar(g_object_get_data(item, 'folder'))));
end;

procedure FreeStr(data: gpointer); cdecl;
begin
  g_free(data);
end;

{ ---------------------------------------------------------------- TSessionsPanel }

constructor TSessionsPanel.Create;
var
  types: array[0..4] of GType;
  col, cell: Pointer;
  scroll: Pointer;
begin
  inherited Create;
  FExpanded := TStringList.Create;
  FExpanded.Sorted := True;
  FExpanded.Duplicates := dupIgnore;
  FMatches := TList.Create;
  types[0] := gdk_pixbuf_get_type;
  types[1] := G_TYPE_STRING;
  types[2] := G_TYPE_INT;
  types[3] := G_TYPE_STRING;
  types[4] := G_TYPE_STRING;
  FStore := gtk_tree_store_newv(5, @types[0]);
  FView := gtk_tree_view_new_with_model(FStore);
  g_object_unref(FStore);
  gtk_tree_view_set_headers_visible(FView, False);
  gtk_tree_view_set_enable_search(FView, True);
  gtk_tree_view_set_search_column(FView, COL_TEXT);
  gtk_tree_view_set_tooltip_column(FView, COL_TIP);
  gtk_tree_view_set_level_indentation(FView, 4);
  col := gtk_tree_view_column_new;
  cell := gtk_cell_renderer_pixbuf_new;
  gtk_tree_view_column_pack_start(col, cell, False);
  gtk_tree_view_column_add_attribute(col, cell, 'pixbuf', COL_ICON);
  cell := gtk_cell_renderer_text_new;
  gtk_cell_renderer_set_padding(cell, 4, 1);
  gtk_tree_view_column_pack_start(col, cell, True);
  gtk_tree_view_column_add_attribute(col, cell, 'markup', COL_TEXT);
  gtk_tree_view_append_column(FView, col);
  Connect(FView, 'row-activated', @RowActivatedCb, Self);
  Connect(FView, 'button-press-event', @ButtonPressCb, Self);
  Connect(FView, 'key-press-event', @KeyPressCb, Self);
  Connect(FView, 'row-expanded', @RowExpandedCb, Self);
  Connect(FView, 'row-collapsed', @RowExpandedCb, Self);
  gtk_tree_view_enable_model_drag_source(FView, GDK_BUTTON1_MASK, @DndTargets[0], 1, GDK_ACTION_MOVE);
  gtk_tree_view_enable_model_drag_dest(FView, @DndTargets[0], 1, GDK_ACTION_MOVE);
  Connect(FView, 'drag-data-get', @DragGetCb, Self);
  Connect(FView, 'drag-data-received', @DragReceivedCb, Self);
  scroll := gtk_scrolled_window_new(nil, nil);
  gtk_scrolled_window_set_policy(scroll, GTK_POLICY_AUTOMATIC, GTK_POLICY_AUTOMATIC);
  gtk_container_add(scroll, FView);
  Widget := scroll;
  Rebuild;
end;

destructor TSessionsPanel.Destroy;
begin
  FExpanded.Free;
  FMatches.Free;
  inherited Destroy;
end;

function TSessionsPanel.FindFolderIter(const Path: string; out Iter: TGtkTreeIter): Boolean;
  function Search(Parent: PGtkTreeIter; out Found: TGtkTreeIter): Boolean;
  var
    it: TGtkTreeIter;
    kind: gint;
    key: PChar;
  begin
    Result := False;
    if not gtk_tree_model_iter_children(FStore, @it, Parent) then Exit;
    repeat
      key := nil;
      gtk_tree_model_get(FStore, @it, COL_KIND, @kind, COL_KEY, @key, -1);
      if (kind = KIND_FOLDER) and (TakeStr(key) = Path) then
      begin
        Found := it;
        Exit(True);
      end
      else if kind <> KIND_SESSION then
      begin
        if Search(@it, Found) then Exit(True);
      end;
    until not gtk_tree_model_iter_next(FStore, @it);
  end;
begin
  Result := Search(nil, Iter);
end;

procedure TSessionsPanel.AddFolderNode(const Path: string; Parent: PGtkTreeIter; out Iter: TGtkTreeIter);
var
  name: string;
begin
  name := RemoteBaseName(Path);
  gtk_tree_store_append(FStore, @Iter, Parent);
  gtk_tree_store_set(FStore, @Iter, COL_ICON, IconPixbuf('folder', 16), COL_TEXT, PChar(MarkupEscape(name)),
    COL_KIND, KIND_FOLDER, COL_KEY, PChar(Path), COL_TIP, PChar(Path), -1);
end;

procedure TSessionsPanel.SaveExpanded;
var
  i: Integer;
  it: TGtkTreeIter;
  path: Pointer;
begin
  if FFilter <> '' then Exit;
  FExpanded.Clear;
  for i := 0 to Store.Folders.Count - 1 do
    if FindFolderIter(Store.Folders[i], it) then
    begin
      path := gtk_tree_model_get_path(FStore, @it);
      if gtk_tree_view_row_expanded(FView, path) then
        FExpanded.Add(Store.Folders[i]);
      gtk_tree_path_free(path);
    end;
end;

procedure TSessionsPanel.Rebuild;
var
  root, parent, it: TGtkTreeIter;
  i: Integer;
  f, txt, tip, lf: string;
  s: TSession;
  path: Pointer;
  folders: TStringList;
  sorted: TStringList;
  pparent: PGtkTreeIter;
begin
  g_signal_handlers_block_by_func(FView, @RowExpandedCb, Self);
  gtk_tree_store_clear(FStore);
  FMatches.Clear;
  lf := LowerCase(Trim(FFilter));
  gtk_tree_store_append(FStore, @root, nil);
  gtk_tree_store_set(FStore, @root, COL_ICON, IconPixbuf('lx-user', 16), COL_TEXT, PChar('<b>User sessions</b>'),
    COL_KIND, KIND_ROOT, COL_KEY, PChar(''), COL_TIP, PChar('Right-click to create sessions and folders'), -1);
  folders := TStringList.Create;
  sorted := TStringList.Create;
  try
    folders.Sorted := True;
    folders.Duplicates := dupIgnore;
    { which folders are needed }
    if lf = '' then
      folders.Assign(Store.Folders)
    else
      for i := 0 to Store.Sessions.Count - 1 do
      begin
        s := Store.Sessions[i];
        if (Pos(lf, LowerCase(s.DisplayName)) > 0) or (Pos(lf, LowerCase(s.Host)) > 0) or
          (Pos(lf, LowerCase(s.User)) > 0) or (Pos(lf, LowerCase(s.Folder)) > 0) then
        begin
          f := s.Folder;
          while f <> '' do
          begin
            folders.Add(f);
            if Pos('/', f) > 0 then f := Copy(f, 1, LastDelimiter('/', f) - 1) else f := '';
          end;
        end;
      end;
    { folder nodes (sorted list guarantees parents come first) }
    for i := 0 to folders.Count - 1 do
    begin
      f := folders[i];
      pparent := @root;
      if Pos('/', f) > 0 then
        if FindFolderIter(Copy(f, 1, LastDelimiter('/', f) - 1), parent) then
          pparent := @parent;
      AddFolderNode(f, pparent, it);
    end;
    { sessions sorted by name }
    sorted.Sorted := True;
    sorted.Duplicates := dupAccept;
    for i := 0 to Store.Sessions.Count - 1 do
      sorted.AddObject(LowerCase(Store.Sessions[i].DisplayName), Store.Sessions[i]);
    for i := 0 to sorted.Count - 1 do
    begin
      s := TSession(sorted.Objects[i]);
      if (lf <> '') and not ((Pos(lf, LowerCase(s.DisplayName)) > 0) or (Pos(lf, LowerCase(s.Host)) > 0) or
        (Pos(lf, LowerCase(s.User)) > 0) or (Pos(lf, LowerCase(s.Folder)) > 0)) then
        Continue;
      FMatches.Add(s);
      pparent := @root;
      if (s.Folder <> '') and FindFolderIter(s.Folder, parent) then
        pparent := @parent;
      txt := MarkupEscape(s.DisplayName);
      tip := SessionKindNames[s.Kind] + ': ' + s.Target;
      if s.Comment <> '' then tip := tip + #10 + s.Comment;
      gtk_tree_store_append(FStore, @it, pparent);
      gtk_tree_store_set(FStore, @it, COL_ICON, IconPixbuf(s.IconName, 16), COL_TEXT, PChar(txt),
        COL_KIND, KIND_SESSION, COL_KEY, PChar(s.Id), COL_TIP, PChar(tip), -1);
    end;
  finally
    folders.Free;
    sorted.Free;
  end;
  { expansion }
  path := gtk_tree_model_get_path(FStore, @root);
  gtk_tree_view_expand_row(FView, path, False);
  gtk_tree_path_free(path);
  if lf <> '' then
    gtk_tree_view_expand_all(FView)
  else
    for i := 0 to FExpanded.Count - 1 do
      if FindFolderIter(FExpanded[i], it) then
      begin
        path := gtk_tree_model_get_path(FStore, @it);
        gtk_tree_view_expand_to_path(FView, path);
        gtk_tree_path_free(path);
      end;
  g_signal_handlers_unblock_by_func(FView, @RowExpandedCb, Self);
end;

procedure TSessionsPanel.ExpandAll;
begin
  gtk_tree_view_expand_all(FView);
end;

procedure TSessionsPanel.SetFilter(const F: string);
begin
  if F = FFilter then Exit;
  if FFilter = '' then SaveExpanded;
  FFilter := F;
  Rebuild;
end;

function TSessionsPanel.SingleMatch: TSession;
var
  i: Integer;
  lf: string;
begin
  Result := nil;
  if FFilter = '' then Exit;
  lf := LowerCase(Trim(FFilter));
  { an exact name match wins }
  for i := 0 to FMatches.Count - 1 do
    if LowerCase(TSession(FMatches[i]).DisplayName) = lf then
      Exit(TSession(FMatches[i]));
  if FMatches.Count = 1 then
    Result := TSession(FMatches[0]);
end;

function TSessionsPanel.SelectedKind(out Key: string): Integer;
var
  it: TGtkTreeIter;
  model: Pointer;
  kind: gint;
  k: PChar;
begin
  Result := -1;
  Key := '';
  if not gtk_tree_selection_get_selected(gtk_tree_view_get_selection(FView), @model, @it) then Exit;
  k := nil;
  gtk_tree_model_get(model, @it, COL_KIND, @kind, COL_KEY, @k, -1);
  Key := TakeStr(k);
  Result := kind;
end;

function TSessionsPanel.SelectedSession: TSession;
var
  key: string;
begin
  Result := nil;
  if SelectedKind(key) = KIND_SESSION then
    Result := Store.FindById(key);
end;

procedure TSessionsPanel.RowActivated;
var
  key: string;
  kind: Integer;
  it: TGtkTreeIter;
  path: Pointer;
  s: TSession;
begin
  kind := SelectedKind(key);
  if kind = KIND_SESSION then
  begin
    s := Store.FindById(key);
    if s <> nil then App.OpenSession(s);
  end
  else if kind = KIND_FOLDER then
  begin
    if FindFolderIter(key, it) then
    begin
      path := gtk_tree_model_get_path(FStore, @it);
      if gtk_tree_view_row_expanded(FView, path) then
        gtk_tree_view_collapse_row(FView, path)
      else
        gtk_tree_view_expand_row(FView, path, False);
      gtk_tree_path_free(path);
    end;
  end;
end;

procedure TSessionsPanel.PopupMenu(Event: Pointer);
var
  menu, sub, item: Pointer;
  key: string;
  kind, i: Integer;
  s: TSession;
begin
  kind := SelectedKind(key);
  menu := gtk_menu_new;
  case kind of
    KIND_SESSION:
      begin
        NewImageMenuItem(menu, '_Execute', 'media-playback-start', @MConnect, Self);
        NewImageMenuItem(menu, 'E_dit session', 'document-properties', @MEdit, Self);
        NewImageMenuItem(menu, '_Rename session', 'document-edit', @MRename, Self);
        NewImageMenuItem(menu, 'D_uplicate session', 'edit-copy', @MDuplicate, Self);
        NewImageMenuItem(menu, '_Delete session', 'edit-delete', @MDelete, Self);
        NewMenuSeparator(menu);
        s := SelectedSession;
        sub := NewSubMenu(menu, '_Move to folder', 'folder');
        if (s = nil) or (s.Folder <> '') then
        begin
          item := NewImageMenuItem(sub, '<User sessions>', 'lx-user', nil, nil);
          g_object_set_data_full(item, 'folder', g_strdup(''), @FreeStr);
          Connect(item, 'activate', @MMoveTo, Self);
        end;
        for i := 0 to Store.Folders.Count - 1 do
          if (s = nil) or (Store.Folders[i] <> s.Folder) then
          begin
            item := NewImageMenuItem(sub, Store.Folders[i], 'folder', nil, nil);
            g_object_set_data_full(item, 'folder', g_strdup(PChar(Store.Folders[i])), @FreeStr);
            Connect(item, 'activate', @MMoveTo, Self);
          end;
        NewImageMenuItem(menu, 'Create a desktop _shortcut', 'user-desktop', @MShortcut, Self);
      end;
    KIND_FOLDER:
      begin
        item := NewImageMenuItem(menu, '_Open all sessions', 'media-playback-start', @MOpenFolder, Self);
        g_object_set_data(item, 'layout', Pointer(0));
        item := NewImageMenuItem(menu, 'Open all in _split view', 'preferences-desktop-virtual', @MOpenFolder, Self);
        g_object_set_data(item, 'layout', Pointer(1));
        item := NewImageMenuItem(menu, 'Open all in _MultiExec (type in all at once)', 'terminator', @MOpenFolder, Self);
        g_object_set_data(item, 'layout', Pointer(2));
        NewMenuSeparator(menu);
        NewImageMenuItem(menu, '_New session', 'list-add', @MNewSession, Self);
        NewImageMenuItem(menu, 'New _folder', 'folder-new', @MNewFolder, Self);
        NewImageMenuItem(menu, '_Rename folder', 'document-edit', @MRename, Self);
        NewImageMenuItem(menu, '_Delete folder', 'edit-delete', @MDelete, Self);
        NewMenuSeparator(menu);
        NewImageMenuItem(menu, '_Expand all', 'list-add', @MExpandAll, Self);
        NewImageMenuItem(menu, '_Collapse all', 'list-remove', @MCollapseAll, Self);
      end;
  else
    begin
      NewImageMenuItem(menu, '_New session', 'list-add', @MNewSession, Self);
      NewImageMenuItem(menu, 'New _folder', 'folder-new', @MNewFolder, Self);
      NewMenuSeparator(menu);
      NewImageMenuItem(menu, '_Expand all', 'list-add', @MExpandAll, Self);
      NewImageMenuItem(menu, '_Collapse all', 'list-remove', @MCollapseAll, Self);
    end;
  end;
  PopupMenuAtPointer(menu, FView, Event);
end;

procedure TSessionsPanel.NewSessionIn(const Folder: string);
var
  s: TSession;
begin
  s := TSession.Create(skSSH);
  s.Folder := Folder;
  if EditSessionDialog(s, True) then
  begin
    if (s.Folder = '') and (Folder <> '') then ;
    if s.Name = '' then s.Name := Store.UniqueName(s.DisplayName);
    Store.Add(s);
    Store.Save;
    Rebuild;
  end
  else
    s.Free;
end;

procedure TSessionsPanel.NewFolderIn(const Parent: string);
var
  name, full: string;
begin
  name := '';
  if not InputQuery('New folder', 'Folder name:', name) then Exit;
  name := Trim(StringReplace(name, '/', '-', [rfReplaceAll]));
  if name = '' then Exit;
  if Parent <> '' then full := Parent + '/' + name else full := name;
  Store.AddFolder(full);
  Store.Save;
  if Parent <> '' then FExpanded.Add(Parent);
  Rebuild;
end;

procedure TSessionsPanel.DeleteSelected;
var
  key: string;
  kind, n, i: Integer;
  s: TSession;
begin
  kind := SelectedKind(key);
  if kind = KIND_SESSION then
  begin
    s := Store.FindById(key);
    if s = nil then Exit;
    if not AskYesNo('Delete session "' + s.DisplayName + '"?', 'This cannot be undone.') then Exit;
    Store.Remove(s);
    Store.Save;
    Rebuild;
  end
  else if kind = KIND_FOLDER then
  begin
    n := 0;
    for i := 0 to Store.Sessions.Count - 1 do
      if (Store.Sessions[i].Folder = key) or (Pos(key + '/', Store.Sessions[i].Folder) = 1) then Inc(n);
    if not AskYesNo('Delete folder "' + key + '"?',
      IfThen(n > 0, 'The ' + IntToStr(n) + ' session(s) it contains will be deleted too.', 'The folder is empty.')) then Exit;
    Store.RemoveFolder(key);
    Store.Save;
    Rebuild;
  end;
end;

procedure TSessionsPanel.RenameSelected;
var
  key, name, newpath: string;
  kind: Integer;
  s: TSession;
begin
  kind := SelectedKind(key);
  if kind = KIND_SESSION then
  begin
    s := Store.FindById(key);
    if s = nil then Exit;
    name := s.DisplayName;
    if InputQuery('Rename session', 'New session name:', name) and (Trim(name) <> '') then
    begin
      s.Name := Trim(name);
      Store.Save;
      Rebuild;
    end;
  end
  else if kind = KIND_FOLDER then
  begin
    name := RemoteBaseName(key);
    if InputQuery('Rename folder', 'New folder name:', name) and (Trim(name) <> '') then
    begin
      name := Trim(StringReplace(name, '/', '-', [rfReplaceAll]));
      if Pos('/', key) > 0 then
        newpath := Copy(key, 1, LastDelimiter('/', key)) + name
      else
        newpath := name;
      Store.RenameFolder(key, newpath);
      Store.Save;
      Rebuild;
    end;
  end;
end;

procedure TSessionsPanel.DuplicateSelected;
var
  s, c: TSession;
  pw: string;
begin
  s := SelectedSession;
  if s = nil then Exit;
  c := s.Clone;
  c.Id := NewId;
  c.Name := Store.UniqueName(s.DisplayName + ' - copy');
  c.HasPassword := False;
  if s.HasPassword and LookupPassword(s.PasswordKey, pw) then
  begin
    StorePassword(c.PasswordKey, pw);
    c.HasPassword := True;
  end;
  Store.Add(c);
  Store.Save;
  Rebuild;
end;

procedure TSessionsPanel.MoveSessionTo(S: TSession; const Folder: string);
begin
  S.Folder := Folder;
  if Folder <> '' then
  begin
    Store.AddFolder(Folder);
    FExpanded.Add(Folder);
  end;
  Store.Save;
  Rebuild;
end;

procedure TSessionsPanel.DragGet(SelData: Pointer);
var
  key: string;
begin
  if SelectedKind(key) = KIND_SESSION then
    gtk_selection_data_set(SelData, gtk_selection_data_get_target(SelData), 8, PChar(key), Length(key));
end;

procedure TSessionsPanel.DragReceived(X, Y: Integer; SelData: Pointer; Ctx: Pointer; Time: guint32);
var
  path: Pointer;
  pos: gint;
  it: TGtkTreeIter;
  kind: gint;
  k: PChar;
  key, id: string;
  s: TSession;
  len: Integer;
  ok: Boolean;
begin
  ok := False;
  len := gtk_selection_data_get_length(SelData);
  if len > 0 then
  begin
    SetString(id, gtk_selection_data_get_data(SelData), len);
    s := Store.FindById(id);
    path := nil;
    if (s <> nil) and gtk_tree_view_get_dest_row_at_pos(FView, X, Y, @path, @pos) then
    begin
      if gtk_tree_model_get_iter(FStore, @it, path) then
      begin
        k := nil;
        gtk_tree_model_get(FStore, @it, COL_KIND, @kind, COL_KEY, @k, -1);
        key := TakeStr(k);
        if kind = KIND_SESSION then
        begin
          { dropped on a session: use the folder of that session }
          if Store.FindById(key) <> nil then
            key := Store.FindById(key).Folder;
          kind := KIND_FOLDER;
        end;
        if kind = KIND_ROOT then key := '';
        if key <> s.Folder then
        begin
          MoveSessionTo(s, key);
          ok := True;
        end;
      end;
      gtk_tree_path_free(path);
    end;
  end;
  gtk_drag_finish(Ctx, ok, False, Time);
end;

end.

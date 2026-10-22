{ LinXterm - file browser widget used by the SFTP side panel and by the
  SFTP / FTP / File session tabs. }
unit lxbrowser;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, BaseUnix, lxgtk, lxutil, lxfs;

type
  TFileBrowser = class;

  TBrowserJob = class(TFsJob)
  public
    Owner: TFileBrowser;
  end;

  TListJob = class(TBrowserJob)
  public
    Path: string;
    Resolved: string;
    Entries: TFileEntries;
    Silent: Boolean;
    procedure Execute(B: TFsBackend); override;
    procedure Done; override;
  end;

  TOpKind = (opMkDir, opDelete, opRename, opChmod, opNewFile);

  TOpJob = class(TBrowserJob)
  public
    Kind: TOpKind;
    Paths: TStringList;
    Arg: string;
    Mode: LongWord;
    constructor Create;
    destructor Destroy; override;
    procedure DeleteTree(B: TFsBackend; const P: string);
    procedure Execute(B: TFsBackend); override;
    procedure Done; override;
  end;

  TXferItem = record
    Src, Dst: string;
    IsDir: Boolean;
  end;
  PXferItem = ^TXferItem;

  TTransferJob = class(TBrowserJob)
  public
    Upload: Boolean;            { local -> backend }
    Items: array of TXferItem;
    CurrentName: string;
    FileIndex, FileCount: Integer;
    Done_, Total_: Int64;
    OpenAfter: Boolean;         { open the downloaded file afterwards }
    WatchRemote: string;
    Quiet: Boolean;
    RefreshTarget: TFileBrowser;
    function Progress(D, T: Int64): Boolean;
    procedure Expand(B: TFsBackend; const Src, Dst: string; IsDir: Boolean; var List: TList);
    procedure DownloadFile(B: TFsBackend; const Src, Dst: string);
    procedure Execute(B: TFsBackend); override;
    procedure Done; override;
  end;

  TWatchedFile = class
    Local, Remote: string;
    MTime, MNsec, Size: Int64;   { change detection: two saves may happen within one second }
  end;

  TFileBrowser = class
  private
    FWorker: TFsWorker;
    FXfer: TFsWorker;
    FToken: IFsToken;
    FLocal: Boolean;
    FConnected: Boolean;
    FPath: string;
    FEntries: TFileEntries;
    FStore, FView, FPathEntry, FStatus, FXferBox, FProgress, FCancelBtn: Pointer;
    FToolbar, FHiddenBtn: Pointer;
    FShowHidden: Boolean;
    FXferTimer: guint;
    FXferJobs: TList;           { queued transfers, the first one is running }
    FWatches: TList;
    FWatchTimer: guint;
    FDesc: string;
    FPlaceholder: Pointer;
    FStack: Pointer;
    procedure BuildUi(Sidebar: Boolean);
    procedure FillList;
    function SelectedNames: TStringList;
    function SelectedEntries(out Count: Integer): TFileEntries;
    procedure StartTransfer(Job: TTransferJob);
    procedure XferFinished(Job: TTransferJob);
    procedure UpdateXferUi;
  public
    Widget: Pointer;
    FollowCheck, MonitorCheck: Pointer;
    Peer: TFileBrowser;
    Tag: Pointer;
    constructor Create(Sidebar: Boolean);
    destructor Destroy; override;
    procedure SetBackend(B: TFsBackend; const StartPath: string; IdleCloseMs: Integer);
    procedure ShowMessage(const Msg: string);
    procedure Navigate(const Path: string; Silent: Boolean = False);
    procedure Refresh;
    procedure GoUp;
    procedure GoHome;
    procedure ListDone(Job: TListJob);
    procedure OpDone(Job: TOpJob);
    procedure Activate(const Name: string; IsDir: Boolean);
    procedure DownloadSelected(const TargetDir: string);
    procedure DownloadSelectedAsk;
    procedure UploadFiles(const Files: TStringArray; const TargetDir: string);
    procedure UploadAsk;
    procedure DeleteSelected;
    procedure RenameSelected;
    procedure NewFolder;
    procedure NewFile;
    procedure ChmodSelected;
    procedure OpenSelected(Edit: Boolean);
    procedure CopyPath;
    procedure ToggleHidden;
    procedure PopupMenu(Event: Pointer);
    procedure CheckWatches;
    procedure DragGet(SelData: Pointer; Info: guint);
    procedure DragReceived(X, Y: Integer; SelData: Pointer; Info: guint; Ctx: Pointer; Time: guint32);
    function FullPath(const Name: string): string;
    procedure TestOp(const Op, A, B: string);
    property Path: string read FPath;
    property IsLocal: Boolean read FLocal;
    property Connected: Boolean read FConnected;
    property Description: string read FDesc;
  end;

function FileIconName(const Name: string; IsDir, IsLink: Boolean): string;

implementation

uses
  StrUtils, Math, lxtabs, lxconfig;

const
  COL_ICON = 0;
  COL_NAME = 1;
  COL_SIZE = 2;
  COL_DATE = 3;
  COL_OWNER = 4;
  COL_GROUP = 5;
  COL_ACCESS = 6;
  COL_ISDIR = 7;
  COL_SIZEN = 8;
  COL_MTIME = 9;

  TARGET_INTERNAL = 1;
  TARGET_URIS = 2;

var
  DndTargets: array[0..1] of TGtkTargetEntry = (
    (target: 'LINXTERM_FILES'; flags: GTK_TARGET_SAME_APP; info: TARGET_INTERNAL),
    (target: 'text/uri-list'; flags: 0; info: TARGET_URIS));
  LiveBrowsers: TList = nil;

function FileIconName(const Name: string; IsDir, IsLink: Boolean): string;
var
  ext: string;
begin
  if IsDir then
  begin
    if IsLink then Exit('folder-remote');
    Exit('folder');
  end;
  ext := LowerCase(ExtractFileExt(Name));
  case ext of
    '.png', '.jpg', '.jpeg', '.gif', '.bmp', '.svg', '.webp', '.ico', '.tif', '.tiff': Result := 'image-x-generic';
    '.mp3', '.wav', '.flac', '.ogg', '.m4a', '.aac': Result := 'audio-x-generic';
    '.mp4', '.mkv', '.avi', '.mov', '.webm', '.wmv': Result := 'video-x-generic';
    '.zip', '.tar', '.gz', '.tgz', '.bz2', '.xz', '.7z', '.rar', '.zst', '.rpm', '.deb': Result := 'package-x-generic';
    '.pdf': Result := 'application-pdf';
    '.sh', '.bash', '.zsh', '.py', '.pl', '.rb', '.php', '.js', '.ts', '.lua': Result := 'text-x-script';
    '.c', '.h', '.cpp', '.hpp', '.pas', '.pp', '.lpr', '.java', '.go', '.rs', '.cs': Result := 'text-x-csrc';
    '.html', '.htm', '.xml', '.css', '.json', '.yml', '.yaml', '.toml', '.ini', '.conf', '.cfg': Result := 'text-html';
    '.txt', '.log', '.md', '.csv', '.rst': Result := 'text-x-generic';
    '.exe', '.bin', '.run', '.appimage', '.so': Result := 'application-x-executable';
  else
    Result := 'text-x-generic';
  end;
  if IsLink then Result := 'emblem-symbolic-link';
end;

function EntryIsHidden(const Name: string): Boolean;
begin
  Result := (Name <> '') and (Name[1] = '.');
end;

{ ---------------------------------------------------------------- jobs }

procedure TListJob.Execute(B: TFsBackend);
begin
  if Path = '' then
    Resolved := B.HomeDir
  else
    Resolved := B.RealPath(Path);
  Entries := B.List(Resolved);
end;

procedure TListJob.Done;
begin
  Owner.ListDone(Self);
end;

constructor TOpJob.Create;
begin
  inherited Create;
  Paths := TStringList.Create;
end;

destructor TOpJob.Destroy;
begin
  Paths.Free;
  inherited Destroy;
end;

procedure TOpJob.DeleteTree(B: TFsBackend; const P: string);
var
  e: TFileEntries;
  i: Integer;
begin
  e := B.List(P);
  for i := 0 to High(e) do
  begin
    if Cancelled then raise Exception.Create('Cancelled');
    if e[i].IsDir and not e[i].IsLink then
      DeleteTree(B, LocalJoin(P, e[i].Name))
    else
      B.RemoveFile(LocalJoin(P, e[i].Name));
  end;
  B.RemoveDir(P);
end;

procedure TOpJob.Execute(B: TFsBackend);
var
  i: Integer;
  e: TFileEntry;
  tmp: string;
begin
  case Kind of
    opMkDir: B.MkDir(Paths[0]);
    opRename: B.Rename(Paths[0], Arg);
    opChmod:
      for i := 0 to Paths.Count - 1 do B.Chmod(Paths[i], Mode);
    opDelete:
      for i := 0 to Paths.Count - 1 do
      begin
        if B.GetEntry(Paths[i], e) and e.IsDir and not e.IsLink then
          DeleteTree(B, Paths[i])
        else
          B.RemoveFile(Paths[i]);
      end;
    opNewFile:
      begin
        { private folder and exclusive creation: no symlink race in /tmp }
        tmp := WriteSecretFile('');
        if tmp = '' then raise Exception.Create('Unable to create a temporary file');
        try
          B.Upload(tmp, Paths[0], nil);
        finally
          DeleteFile(tmp);
        end;
      end;
  end;
end;

procedure TOpJob.Done;
begin
  Owner.OpDone(Self);
end;

function TTransferJob.Progress(D, T: Int64): Boolean;
begin
  Done_ := D;
  Total_ := T;
  Result := not Cancelled;
end;

procedure TTransferJob.Expand(B: TFsBackend; const Src, Dst: string; IsDir: Boolean; var List: TList);
var
  sr: TSearchRec;
  e: TFileEntries;
  i: Integer;
  p: PXferItem;
begin
  New(p);
  p^.Src := Src;
  p^.Dst := Dst;
  p^.IsDir := IsDir;
  List.Add(p);
  if not IsDir then Exit;
  if Upload then
  begin
    if FindFirst(LocalJoin(Src, '*'), faAnyFile or faHidden or faDirectory, sr) = 0 then
    begin
      try
        repeat
          if (sr.Name = '.') or (sr.Name = '..') then Continue;
          Expand(B, LocalJoin(Src, sr.Name), LocalJoin(Dst, sr.Name),
            ((sr.Attr and faDirectory) <> 0) and ((sr.Attr and faSymLink) = 0), List);
        until FindNext(sr) <> 0;
      finally
        FindClose(sr);
      end;
    end;
  end
  else
  begin
    e := B.List(Src);
    for i := 0 to High(e) do
      Expand(B, LocalJoin(Src, e[i].Name), LocalJoin(Dst, e[i].Name), e[i].IsDir and not e[i].IsLink, List);
  end;
end;

{ downloads to a temporary name first: an interrupted transfer never leaves
  a truncated file in place of a good one }
procedure TTransferJob.DownloadFile(B: TFsBackend; const Src, Dst: string);
var
  tmp: string;
  st: Stat;
begin
  tmp := ExtractFilePath(Dst) + '.' + ExtractFileName(Dst) + '.part';
  try
    B.Download(Src, tmp, @Progress);
  except
    DeleteFile(tmp);
    raise;
  end;
  { keep the permissions of the file being replaced }
  if fpStat(Dst, st) = 0 then fpChmod(tmp, st.st_mode and &7777);
  if fpRename(tmp, Dst) <> 0 then
  begin
    DeleteFile(tmp);
    raise Exception.Create('Cannot write ' + Dst + ': ' + SysErrorMessage(fpGetErrno));
  end;
end;

procedure TTransferJob.Execute(B: TFsBackend);
var
  lst: TList;
  i: Integer;
  p: PXferItem;
begin
  lst := TList.Create;
  try
    for i := 0 to High(Items) do
      Expand(B, Items[i].Src, Items[i].Dst, Items[i].IsDir, lst);
    FileCount := 0;
    for i := 0 to lst.Count - 1 do
      if not PXferItem(lst[i])^.IsDir then Inc(FileCount);
    FileIndex := 0;
    for i := 0 to lst.Count - 1 do
    begin
      if Cancelled then raise Exception.Create('Transfer cancelled');
      p := lst[i];
      if p^.IsDir then
      begin
        if Upload then
        begin
          try
            B.MkDir(p^.Dst);
          except
            { the folder may already exist }
          end;
        end
        else if not DirectoryExists(p^.Dst) then
          if fpMkDir(p^.Dst, &755) <> 0 then
            raise Exception.Create('Cannot create ' + p^.Dst);
      end
      else
      begin
        Inc(FileIndex);
        CurrentName := ExtractFileName(p^.Src);
        Done_ := 0;
        Total_ := 0;
        if Upload then
          B.Upload(p^.Src, p^.Dst, @Progress)
        else
          DownloadFile(B, p^.Src, p^.Dst);
      end;
    end;
  finally
    for i := 0 to lst.Count - 1 do
      Dispose(PXferItem(lst[i]));
    lst.Free;
  end;
end;

procedure TTransferJob.Done;
begin
  Owner.XferFinished(Self);
end;

{ ---------------------------------------------------------------- callbacks }

procedure BtnUp(b: Pointer; data: gpointer); cdecl; begin TFileBrowser(data).GoUp; end;
procedure BtnRefresh(b: Pointer; data: gpointer); cdecl; begin TFileBrowser(data).Refresh; end;
procedure BtnHome(b: Pointer; data: gpointer); cdecl; begin TFileBrowser(data).GoHome; end;
procedure BtnDownload(b: Pointer; data: gpointer); cdecl; begin TFileBrowser(data).DownloadSelectedAsk; end;
procedure BtnUpload(b: Pointer; data: gpointer); cdecl; begin TFileBrowser(data).UploadAsk; end;
procedure BtnNewFolder(b: Pointer; data: gpointer); cdecl; begin TFileBrowser(data).NewFolder; end;
procedure BtnNewFile(b: Pointer; data: gpointer); cdecl; begin TFileBrowser(data).NewFile; end;
procedure BtnDelete(b: Pointer; data: gpointer); cdecl; begin TFileBrowser(data).DeleteSelected; end;
procedure BtnHidden(b: Pointer; data: gpointer); cdecl; begin TFileBrowser(data).ToggleHidden; end;
procedure BtnCancel(b: Pointer; data: gpointer); cdecl;
var
  fb: TFileBrowser;
begin
  fb := TFileBrowser(data);
  if fb.FXfer <> nil then fb.FXfer.CancelAll;
end;

procedure PathActivate(entry: Pointer; data: gpointer); cdecl;
begin
  TFileBrowser(data).Navigate(Trim(EntryText(entry)));
end;

procedure PathGo(b: Pointer; data: gpointer); cdecl;
begin
  TFileBrowser(data).Navigate(Trim(EntryText(TFileBrowser(data).FPathEntry)));
end;

procedure RowActivated(view: Pointer; path: Pointer; col: Pointer; data: gpointer); cdecl;
var
  fb: TFileBrowser;
  it: TGtkTreeIter;
  name: PChar;
  isdir: gboolean;
begin
  fb := TFileBrowser(data);
  if not gtk_tree_model_get_iter(fb.FStore, @it, path) then Exit;
  name := nil;
  gtk_tree_model_get(fb.FStore, @it, COL_NAME, @name, COL_ISDIR, @isdir, -1);
  fb.Activate(TakeStr(name), isdir);
end;

function ViewButton(widget: Pointer; event: Pointer; data: gpointer): gboolean; cdecl;
var
  path: Pointer;
  x, y: gdouble;
  sel: Pointer;
begin
  Result := False;
  if (gdk_event_get_event_type(event) = GDK_BUTTON_PRESS) and (EventButton(event) = 3) then
  begin
    gdk_event_get_coords(event, @x, @y);
    path := nil;
    sel := gtk_tree_view_get_selection(widget);
    if gtk_tree_view_get_path_at_pos(widget, Trunc(x), Trunc(y), @path, nil, nil, nil) then
    begin
      if not gtk_tree_selection_path_is_selected(sel, path) then
      begin
        gtk_tree_selection_unselect_all(sel);
        gtk_tree_selection_select_path(sel, path);
      end;
      gtk_tree_path_free(path);
    end
    else
      gtk_tree_selection_unselect_all(sel);
    TFileBrowser(data).PopupMenu(event);
    Result := True;
  end;
end;

function ViewKey(widget: Pointer; event: Pointer; data: gpointer): gboolean; cdecl;
var
  kv, st: guint;
begin
  Result := True;
  kv := EventKeyval(event);
  st := EventState(event) and (GDK_CONTROL_MASK or GDK_SHIFT_MASK or GDK_MOD1_MASK);
  if kv = GDK_KEY_Delete then TFileBrowser(data).DeleteSelected
  else if kv = GDK_KEY_F2 then TFileBrowser(data).RenameSelected
  else if kv = GDK_KEY_F5 then TFileBrowser(data).Refresh
  else if kv = GDK_KEY_BackSpace then TFileBrowser(data).GoUp
  else if (st = GDK_MOD1_MASK) and (kv = GDK_KEY_Up) then TFileBrowser(data).GoUp
  else if (st = GDK_CONTROL_MASK) and (kv = Ord('h')) then TFileBrowser(data).ToggleHidden
  else Result := False;
end;

procedure DragGetCb(widget: Pointer; ctx: Pointer; seldata: Pointer; info: guint; time: guint32; data: gpointer); cdecl;
begin
  TFileBrowser(data).DragGet(seldata, info);
end;

procedure DragReceivedCb(widget: Pointer; ctx: Pointer; x, y: gint; seldata: Pointer; info: guint; time: guint32; data: gpointer); cdecl;
begin
  g_signal_stop_emission_by_name(widget, 'drag-data-received');
  TFileBrowser(data).DragReceived(x, y, seldata, info, ctx, time);
end;

function XferTimerCb(data: gpointer): gboolean; cdecl;
begin
  TFileBrowser(data).UpdateXferUi;
  Result := True;
end;

function WatchTimerCb(data: gpointer): gboolean; cdecl;
begin
  TFileBrowser(data).CheckWatches;
  Result := True;
end;

{ sort: folders first, then the column value }
function SortFunc(model: Pointer; a, b: PGtkTreeIter; data: gpointer): gint; cdecl;
var
  da, db: gboolean;
  na, nb: PChar;
  sa, sb: Int64;
  col: PtrInt;
  sn1, sn2: string;
begin
  col := PtrInt(data);
  na := nil;
  nb := nil;
  gtk_tree_model_get(model, a, COL_ISDIR, @da, COL_NAME, @na, -1);
  gtk_tree_model_get(model, b, COL_ISDIR, @db, COL_NAME, @nb, -1);
  sn1 := TakeStr(na);
  sn2 := TakeStr(nb);
  if sn1 = '..' then Exit(-1);
  if sn2 = '..' then Exit(1);
  if da <> db then
  begin
    if da then Exit(-1) else Exit(1);
  end;
  case col of
    COL_SIZE:
      begin
        gtk_tree_model_get(model, a, COL_SIZEN, @sa, -1);
        gtk_tree_model_get(model, b, COL_SIZEN, @sb, -1);
        Result := CompareValue(sa, sb);
      end;
    COL_DATE:
      begin
        gtk_tree_model_get(model, a, COL_MTIME, @sa, -1);
        gtk_tree_model_get(model, b, COL_MTIME, @sb, -1);
        Result := CompareValue(sa, sb);
      end;
  else
    Result := 0;
  end;
  if Result = 0 then
    Result := CompareText(sn1, sn2);
end;

{ context menu }
procedure MOpen(i: Pointer; data: gpointer); cdecl; begin TFileBrowser(data).OpenSelected(False); end;
procedure MEdit(i: Pointer; data: gpointer); cdecl; begin TFileBrowser(data).OpenSelected(True); end;
procedure MDownload(i: Pointer; data: gpointer); cdecl; begin TFileBrowser(data).DownloadSelectedAsk; end;
procedure MUpload(i: Pointer; data: gpointer); cdecl; begin TFileBrowser(data).UploadAsk; end;
procedure MRename(i: Pointer; data: gpointer); cdecl; begin TFileBrowser(data).RenameSelected; end;
procedure MDelete(i: Pointer; data: gpointer); cdecl; begin TFileBrowser(data).DeleteSelected; end;
procedure MNewFolder(i: Pointer; data: gpointer); cdecl; begin TFileBrowser(data).NewFolder; end;
procedure MNewFile(i: Pointer; data: gpointer); cdecl; begin TFileBrowser(data).NewFile; end;
procedure MChmod(i: Pointer; data: gpointer); cdecl; begin TFileBrowser(data).ChmodSelected; end;
procedure MCopyPath(i: Pointer; data: gpointer); cdecl; begin TFileBrowser(data).CopyPath; end;
procedure MRefresh(i: Pointer; data: gpointer); cdecl; begin TFileBrowser(data).Refresh; end;
procedure MHidden(i: Pointer; data: gpointer); cdecl; begin TFileBrowser(data).ToggleHidden; end;
procedure MOpenTerminal(i: Pointer; data: gpointer); cdecl;
var
  fb: TFileBrowser;
begin
  fb := TFileBrowser(data);
  if App <> nil then
    App.RunCommandTab(fb.FPath, 'utilities-terminal', ['/bin/sh', '-c', 'cd ' + ShellQuote(fb.FPath) + ' && exec "${SHELL:-/bin/bash}"']);
end;
procedure MFileManager(i: Pointer; data: gpointer); cdecl;
begin
  OpenPath(TFileBrowser(data).FPath);
end;

{ ---------------------------------------------------------------- TFileBrowser }

constructor TFileBrowser.Create(Sidebar: Boolean);
begin
  inherited Create;
  FWatches := TList.Create;
  FXferJobs := TList.Create;
  if LiveBrowsers = nil then LiveBrowsers := TList.Create;
  LiveBrowsers.Add(Self);
  BuildUi(Sidebar);
end;

destructor TFileBrowser.Destroy;
var
  i: Integer;
begin
  LiveBrowsers.Remove(Self);
  if FToken <> nil then FToken.Kill;
  FToken := nil;
  if FWorker <> nil then FWorker.Shutdown;
  if FXfer <> nil then FXfer.Shutdown;
  FWorker := nil;
  FXfer := nil;
  if FXferTimer <> 0 then g_source_remove(FXferTimer);
  if FWatchTimer <> 0 then g_source_remove(FWatchTimer);
  for i := 0 to FWatches.Count - 1 do
    TWatchedFile(FWatches[i]).Free;
  FWatches.Free;
  FXferJobs.Free;
  if Widget <> nil then
  begin
    gtk_widget_destroy(Widget);
    g_object_unref(Widget);
  end;
  inherited Destroy;
end;

procedure TFileBrowser.BuildUi(Sidebar: Boolean);
var
  vbox, tb, hb, b, col, cell, scroll, sel: Pointer;
  types: array[0..9] of GType;
  procedure Tool(const Icon, Tip: string; Cb: Pointer);
  var
    btn: Pointer;
  begin
    btn := NewFlatIconButton(Icon, Tip, 16);
    Connect(btn, 'clicked', Cb, Self);
    gtk_box_pack_start(tb, btn, False, False, 0);
  end;
  procedure AddCol(const Title: string; ColId: Integer; Expand: Boolean; Width: Integer);
  begin
    col := gtk_tree_view_column_new;
    gtk_tree_view_column_set_title(col, PChar(Title));
    cell := gtk_cell_renderer_text_new;
    gtk_tree_view_column_pack_start(col, cell, True);
    gtk_tree_view_column_add_attribute(col, cell, 'text', ColId);
    gtk_tree_view_column_set_resizable(col, True);
    gtk_tree_view_column_set_sort_column_id(col, ColId);
    if Width > 0 then
    begin
      gtk_tree_view_column_set_sizing(col, GTK_TREE_VIEW_COLUMN_FIXED);
      gtk_tree_view_column_set_fixed_width(col, Width);
    end;
    gtk_tree_view_column_set_expand(col, Expand);
    gtk_tree_view_append_column(FView, col);
  end;
begin
  vbox := gtk_box_new(GTK_ORIENTATION_VERTICAL, 2);
  Widget := vbox;
  g_object_ref_sink(Widget);

  tb := gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0);
  FToolbar := tb;
  AddClass(tb, 'lx-browser-toolbar');
  Tool('lx-folder-up', 'Parent directory (Backspace)', @BtnUp);
  Tool('lx-download', 'Download selected files', @BtnDownload);
  Tool('lx-upload', 'Upload files to the current folder', @BtnUpload);
  Tool('lx-refresh', 'Refresh (F5)', @BtnRefresh);
  Tool('lx-folder-new', 'Create a new folder', @BtnNewFolder);
  Tool('lx-file-new', 'Create a new empty file', @BtnNewFile);
  Tool('lx-cancel', 'Delete selected files (Del)', @BtnDelete);
  Tool('lx-home', 'Home directory', @BtnHome);
  FHiddenBtn := gtk_toggle_button_new;
  gtk_button_set_image(FHiddenBtn, NewIcon('lx-eye', 16));
  gtk_button_set_relief(FHiddenBtn, GTK_RELIEF_NONE);
  gtk_widget_set_tooltip_text(FHiddenBtn, 'Show hidden files (Ctrl+H)');
  gtk_widget_set_can_focus(FHiddenBtn, False);
  Connect(FHiddenBtn, 'toggled', @BtnHidden, Self);
  gtk_box_pack_end(tb, FHiddenBtn, False, False, 0);
  gtk_box_pack_start(vbox, tb, False, False, 0);

  hb := gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 2);
  FPathEntry := gtk_entry_new;
  AddClass(FPathEntry, 'lx-browser-path');
  Connect(FPathEntry, 'activate', @PathActivate, Self);
  gtk_box_pack_start(hb, FPathEntry, True, True, 0);
  b := NewFlatIconButton('lx-check', 'Go to this folder', 16);
  Connect(b, 'clicked', @PathGo, Self);
  gtk_box_pack_start(hb, b, False, False, 0);
  gtk_box_pack_start(vbox, hb, False, False, 0);

  types[0] := gdk_pixbuf_get_type;
  types[1] := G_TYPE_STRING;
  types[2] := G_TYPE_STRING;
  types[3] := G_TYPE_STRING;
  types[4] := G_TYPE_STRING;
  types[5] := G_TYPE_STRING;
  types[6] := G_TYPE_STRING;
  types[7] := G_TYPE_BOOLEAN;
  types[8] := G_TYPE_INT64;
  types[9] := G_TYPE_INT64;
  FStore := gtk_list_store_newv(10, @types[0]);
  gtk_tree_sortable_set_sort_func(FStore, COL_NAME, @SortFunc, Pointer(PtrInt(COL_NAME)), nil);
  gtk_tree_sortable_set_sort_func(FStore, COL_SIZE, @SortFunc, Pointer(PtrInt(COL_SIZE)), nil);
  gtk_tree_sortable_set_sort_func(FStore, COL_DATE, @SortFunc, Pointer(PtrInt(COL_DATE)), nil);
  gtk_tree_sortable_set_sort_func(FStore, COL_OWNER, @SortFunc, Pointer(PtrInt(COL_OWNER)), nil);
  gtk_tree_sortable_set_sort_func(FStore, COL_GROUP, @SortFunc, Pointer(PtrInt(COL_GROUP)), nil);
  gtk_tree_sortable_set_sort_func(FStore, COL_ACCESS, @SortFunc, Pointer(PtrInt(COL_ACCESS)), nil);
  gtk_tree_sortable_set_sort_column_id(FStore, COL_NAME, GTK_SORT_ASCENDING);
  FView := gtk_tree_view_new_with_model(FStore);
  g_object_unref(FStore);
  sel := gtk_tree_view_get_selection(FView);
  gtk_tree_selection_set_mode(sel, GTK_SELECTION_MULTIPLE);
  gtk_tree_view_set_rubber_banding(FView, True);
  gtk_tree_view_set_enable_search(FView, True);
  gtk_tree_view_set_search_column(FView, COL_NAME);

  col := gtk_tree_view_column_new;
  gtk_tree_view_column_set_title(col, 'Name');
  cell := gtk_cell_renderer_pixbuf_new;
  gtk_tree_view_column_pack_start(col, cell, False);
  gtk_tree_view_column_add_attribute(col, cell, 'pixbuf', COL_ICON);
  cell := gtk_cell_renderer_text_new;
  gtk_tree_view_column_pack_start(col, cell, True);
  gtk_tree_view_column_add_attribute(col, cell, 'text', COL_NAME);
  gtk_tree_view_column_set_resizable(col, True);
  gtk_tree_view_column_set_sort_column_id(col, COL_NAME);
  gtk_tree_view_column_set_expand(col, True);
  if Sidebar then
  begin
    gtk_tree_view_column_set_sizing(col, GTK_TREE_VIEW_COLUMN_FIXED);
    gtk_tree_view_column_set_fixed_width(col, 190);
  end
  else
    gtk_tree_view_column_set_min_width(col, 220);
  gtk_tree_view_append_column(FView, col);
  AddCol('Size', COL_SIZE, False, 0);
  AddCol('Last modified', COL_DATE, False, 0);
  AddCol('Owner', COL_OWNER, False, 0);
  AddCol('Group', COL_GROUP, False, 0);
  AddCol('Access', COL_ACCESS, False, 0);

  Connect(FView, 'row-activated', @RowActivated, Self);
  Connect(FView, 'button-press-event', @ViewButton, Self);
  Connect(FView, 'key-press-event', @ViewKey, Self);
  gtk_tree_view_enable_model_drag_source(FView, GDK_BUTTON1_MASK, @DndTargets[0], 2, GDK_ACTION_COPY);
  gtk_tree_view_enable_model_drag_dest(FView, @DndTargets[0], 2, GDK_ACTION_COPY);
  Connect(FView, 'drag-data-get', @DragGetCb, Self);
  Connect(FView, 'drag-data-received', @DragReceivedCb, Self);

  scroll := gtk_scrolled_window_new(nil, nil);
  gtk_scrolled_window_set_policy(scroll, GTK_POLICY_AUTOMATIC, GTK_POLICY_AUTOMATIC);
  gtk_scrolled_window_set_shadow_type(scroll, GTK_SHADOW_IN);
  gtk_container_add(scroll, FView);

  FStack := gtk_stack_new;
  gtk_stack_add_named(FStack, scroll, 'list');
  FPlaceholder := NewMarkupLabel('', 0.5);
  gtk_label_set_line_wrap(FPlaceholder, True);
  gtk_label_set_justify(FPlaceholder, GTK_JUSTIFY_CENTER);
  SetMargins(FPlaceholder, 12);
  gtk_stack_add_named(FStack, FPlaceholder, 'message');
  gtk_box_pack_start(vbox, FStack, True, True, 0);

  { transfer progress }
  FXferBox := gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 4);
  FProgress := gtk_progress_bar_new;
  gtk_progress_bar_set_show_text(FProgress, True);
  gtk_box_pack_start(FXferBox, FProgress, True, True, 0);
  FCancelBtn := NewFlatIconButton('process-stop', 'Cancel the transfers', 16);
  Connect(FCancelBtn, 'clicked', @BtnCancel, Self);
  gtk_box_pack_start(FXferBox, FCancelBtn, False, False, 0);
  gtk_widget_set_no_show_all(FXferBox, True);
  gtk_box_pack_start(vbox, FXferBox, False, False, 0);

  FStatus := NewLabel('', 0);
  gtk_label_set_ellipsize(FStatus, PANGO_ELLIPSIZE_END);
  AddClass(FStatus, 'dim-label');
  gtk_widget_set_margin_start(FStatus, 4);
  gtk_box_pack_start(vbox, FStatus, False, False, 0);

  if Sidebar then
  begin
    FollowCheck := gtk_check_button_new_with_label('Follow terminal folder');
    gtk_box_pack_start(vbox, FollowCheck, False, False, 0);
    MonitorCheck := gtk_check_button_new_with_label('Remote monitoring');
    gtk_box_pack_start(vbox, MonitorCheck, False, False, 0);
  end;
  gtk_widget_show_all(vbox);
  gtk_widget_set_sensitive(FToolbar, False);
end;

procedure TFileBrowser.ShowMessage(const Msg: string);
begin
  gtk_label_set_markup(FPlaceholder, PChar(Msg));
  gtk_stack_set_visible_child_name(FStack, 'message');
end;

procedure TFileBrowser.SetBackend(B: TFsBackend; const StartPath: string; IdleCloseMs: Integer);
begin
  if FToken <> nil then FToken.Kill;
  if FWorker <> nil then FWorker.Shutdown;
  if FXfer <> nil then FXfer.Shutdown;
  FToken := TFsToken.Create;
  FLocal := B.IsLocal;
  FDesc := B.Name;
  FXfer := TFsWorker.Create(B.Clone, IdleCloseMs);
  FWorker := TFsWorker.Create(B, IdleCloseMs);
  FConnected := False;
  gtk_widget_set_sensitive(FToolbar, True);
  if not FLocal then
  begin
    gtk_list_store_clear(FStore);
    ShowMessage('<span foreground="#888888">Connecting...</span>');
  end;
  Navigate(StartPath);
end;

function TFileBrowser.FullPath(const Name: string): string;
begin
  Result := LocalJoin(FPath, Name);
end;

procedure TFileBrowser.Navigate(const Path: string; Silent: Boolean);
var
  j: TListJob;
begin
  if FWorker = nil then Exit;
  j := TListJob.Create;
  j.Owner := Self;
  j.Token := FToken;
  j.Silent := Silent;
  if (Path <> '') and (Path[1] = '~') then
    j.Path := ''
  else
    j.Path := Path;
  if not Silent then
    gtk_label_set_text(FStatus, 'Loading...');
  FWorker.Add(j);
end;

procedure TFileBrowser.Refresh;
begin
  Navigate(FPath, True);
end;

procedure TFileBrowser.GoUp;
begin
  if FPath = '' then Exit;
  Navigate(RemoteParent(FPath));
end;

procedure TFileBrowser.GoHome;
begin
  Navigate('');
end;

procedure TFileBrowser.ListDone(Job: TListJob);
begin
  if Job.Err <> '' then
  begin
    gtk_label_set_text(FStatus, PChar(Job.Err));
    if not FConnected then
      ShowMessage('<span foreground="#c62828"><b>Unable to browse ' + MarkupEscape(FDesc) + '</b></span>'#10 +
        MarkupEscape(Job.Err))
    else if not Job.Silent then
      MsgError('Unable to open the folder', Job.Err);
    Exit;
  end;
  FConnected := True;
  FPath := Job.Resolved;
  FEntries := Job.Entries;
  SetEntryText(FPathEntry, FPath);
  FillList;
  gtk_stack_set_visible_child_name(FStack, 'list');
end;

procedure TFileBrowser.FillList;
var
  i, n: Integer;
  it: TGtkTreeIter;
  e: TFileEntry;
  sz: string;
  sel: TStringList;
  selection: Pointer;
  vadj: Pointer;
  scroll: gdouble;
begin
  sel := SelectedNames;
  vadj := gtk_scrollable_get_vadjustment(FView);
  scroll := 0;
  if vadj <> nil then scroll := gtk_adjustment_get_upper(vadj);
  gtk_list_store_clear(FStore);
  if FPath <> '/' then
  begin
    gtk_list_store_append(FStore, @it);
    gtk_list_store_set(FStore, @it, COL_ICON, IconPixbuf('lx-folder-up', 16), COL_NAME, PChar('..'),
      COL_SIZE, PChar(''), COL_DATE, PChar(''), COL_OWNER, PChar(''), COL_GROUP, PChar(''),
      COL_ACCESS, PChar(''), COL_ISDIR, GBool(True), COL_SIZEN, Int64(-1), COL_MTIME, Int64(0), -1);
  end;
  n := 0;
  selection := gtk_tree_view_get_selection(FView);
  for i := 0 to High(FEntries) do
  begin
    e := FEntries[i];
    if not FShowHidden and EntryIsHidden(e.Name) then Continue;
    if e.IsDir then sz := '' else sz := HumanSize(e.Size);
    gtk_list_store_append(FStore, @it);
    gtk_list_store_set(FStore, @it, COL_ICON, IconPixbuf(FileIconName(e.Name, e.IsDir, e.IsLink), 16),
      COL_NAME, PChar(e.Name), COL_SIZE, PChar(sz), COL_DATE, PChar(FormatUnixTime(e.MTime)),
      COL_OWNER, PChar(e.Owner), COL_GROUP, PChar(e.Group),
      COL_ACCESS, PChar(ModeString(e.Mode, e.IsDir, e.IsLink)), COL_ISDIR, GBool(e.IsDir),
      COL_SIZEN, e.Size, COL_MTIME, e.MTime, -1);
    if sel.IndexOf(e.Name) >= 0 then
      gtk_tree_selection_select_iter(selection, @it);
    Inc(n);
  end;
  sel.Free;
  if scroll = 0 then ;
  gtk_label_set_text(FStatus, PChar(IntToStr(n) + ' item(s)' + IfThen(FLocal, '', '  -  ' + FDesc)));
end;

function TFileBrowser.SelectedNames: TStringList;
var
  rows, it: PGList;
  iter: TGtkTreeIter;
  model: Pointer;
  name: PChar;
  s: string;
begin
  Result := TStringList.Create;
  model := nil;
  rows := gtk_tree_selection_get_selected_rows(gtk_tree_view_get_selection(FView), @model);
  it := rows;
  while it <> nil do
  begin
    if gtk_tree_model_get_iter(model, @iter, it^.data) then
    begin
      name := nil;
      gtk_tree_model_get(model, @iter, COL_NAME, @name, -1);
      s := TakeStr(name);
      if (s <> '') and (s <> '..') then Result.Add(s);
    end;
    gtk_tree_path_free(it^.data);
    it := it^.next;
  end;
  g_list_free(rows);
end;

function TFileBrowser.SelectedEntries(out Count: Integer): TFileEntries;
var
  names: TStringList;
  i, j: Integer;
begin
  names := SelectedNames;
  try
    Result := nil;
    SetLength(Result, names.Count);
    Count := 0;
    for i := 0 to names.Count - 1 do
      for j := 0 to High(FEntries) do
        if FEntries[j].Name = names[i] then
        begin
          Result[Count] := FEntries[j];
          Inc(Count);
          Break;
        end;
    SetLength(Result, Count);
  finally
    names.Free;
  end;
end;

procedure TFileBrowser.Activate(const Name: string; IsDir: Boolean);
begin
  if Name = '..' then
    GoUp
  else if IsDir then
    Navigate(FullPath(Name))
  else
    OpenSelected(False);
end;

procedure TFileBrowser.OpDone(Job: TOpJob);
begin
  if Job.Err <> '' then
    MsgError('Operation failed', Job.Err);
  Refresh;
end;

{ ---------------------------------------------------------------- transfers }

procedure TFileBrowser.StartTransfer(Job: TTransferJob);
begin
  Job.Owner := Self;
  Job.Token := FToken;
  FXferJobs.Add(Job);
  FXfer.Add(Job);
  gtk_widget_set_no_show_all(FXferBox, False);
  gtk_widget_show_all(FXferBox);
  if FXferTimer = 0 then
    FXferTimer := g_timeout_add(200, @XferTimerCb, Self);
  UpdateXferUi;
end;

procedure TFileBrowser.UpdateXferUi;
var
  j: TTransferJob;
  frac: Double;
  txt: string;
begin
  { the worker runs the transfers in order: the first one is the active one }
  if FXferJobs.Count = 0 then Exit;
  j := TTransferJob(FXferJobs[0]);
  if j.Total_ > 0 then frac := j.Done_ / j.Total_ else frac := 0;
  if frac > 1 then frac := 1;
  gtk_progress_bar_set_fraction(FProgress, frac);
  if j.CurrentName = '' then
    txt := 'Preparing transfer...'
  else
    txt := IfThen(j.Upload, 'Uploading ', 'Downloading ') + j.CurrentName +
      Format(' (%d/%d)  %s / %s', [j.FileIndex, Max(1, j.FileCount), HumanSize(j.Done_), HumanSize(j.Total_)]);
  if FXferJobs.Count > 1 then txt := txt + '  [+' + IntToStr(FXferJobs.Count - 1) + ' queued]';
  gtk_progress_bar_set_text(FProgress, PChar(txt));
end;

procedure TFileBrowser.XferFinished(Job: TTransferJob);
var
  w: TWatchedFile;
  st: Stat;
begin
  FXferJobs.Remove(Job);
  if FXferJobs.Count = 0 then
  begin
    gtk_widget_hide(FXferBox);
    if FXferTimer <> 0 then g_source_remove(FXferTimer);
    FXferTimer := 0;
  end;
  if Job.Err <> '' then
  begin
    if (Job.Err <> 'Transfer cancelled') and (Job.Err <> 'Cancelled') then
      MsgError(IfThen(Job.Upload, 'Upload failed', 'Download failed'), Job.Err)
    else
      gtk_label_set_text(FStatus, 'Transfer cancelled');
    if Job.Upload then Refresh;
    Exit;
  end;
  if Job.Upload then
  begin
    Refresh;
    if not Job.Quiet and (App <> nil) then
      App.SetStatus('Upload complete: ' + IntToStr(Job.FileCount) + ' file(s)');
    if Job.Quiet and (App <> nil) then
      App.SetStatus('Modified file uploaded: ' + Job.WatchRemote);
  end
  else
  begin
    if Peer <> nil then Peer.Refresh;
    if (Job.RefreshTarget <> nil) and (LiveBrowsers.IndexOf(Job.RefreshTarget) >= 0) then
      Job.RefreshTarget.Refresh;
    if (App <> nil) and not Job.OpenAfter then
      App.SetStatus('Download complete: ' + IntToStr(Job.FileCount) + ' file(s) to ' + ExtractFileDir(Job.Items[0].Dst));
    if Job.OpenAfter and (Length(Job.Items) > 0) then
    begin
      w := TWatchedFile.Create;
      w.Local := Job.Items[0].Dst;
      w.Remote := Job.Items[0].Src;
      if fpStat(w.Local, st) = 0 then
      begin
        w.MTime := st.st_mtime;
        w.MNsec := st.st_mtime_nsec;
        w.Size := st.st_size;
      end;
      FWatches.Add(w);
      if FWatchTimer = 0 then
        FWatchTimer := g_timeout_add(1500, @WatchTimerCb, Self);
      if Job.WatchRemote = 'edit' then
      begin
        if App <> nil then App.OpenEditor(w.Local);
      end
      else
        OpenPath(w.Local);
      if App <> nil then
        App.SetStatus('Editing ' + w.Remote + ': saved changes are uploaded automatically');
    end;
  end;
end;

procedure TFileBrowser.CheckWatches;
var
  i: Integer;
  w: TWatchedFile;
  st: Stat;
  j: TTransferJob;
begin
  if FXfer = nil then Exit;
  for i := 0 to FWatches.Count - 1 do
  begin
    w := TWatchedFile(FWatches[i]);
    if (fpStat(w.Local, st) = 0) and ((st.st_mtime <> w.MTime) or (Int64(st.st_mtime_nsec) <> w.MNsec) or
      (st.st_size <> w.Size)) then
    begin
      w.MTime := st.st_mtime;
      w.MNsec := st.st_mtime_nsec;
      w.Size := st.st_size;
      j := TTransferJob.Create;
      j.Upload := True;
      SetLength(j.Items, 1);
      j.Items[0].Src := w.Local;
      j.Items[0].Dst := w.Remote;
      j.Items[0].IsDir := False;
      j.Quiet := True;
      j.WatchRemote := w.Remote;
      StartTransfer(j);
    end;
  end;
end;

procedure TFileBrowser.DownloadSelected(const TargetDir: string);
var
  e: TFileEntries;
  n, i, exist: Integer;
  j: TTransferJob;
begin
  e := SelectedEntries(n);
  if n = 0 then
  begin
    MsgInfo('Nothing to download', 'Select one or more files or folders first.');
    Exit;
  end;
  exist := 0;
  for i := 0 to n - 1 do
    if FileExists(LocalJoin(TargetDir, e[i].Name)) or DirectoryExists(LocalJoin(TargetDir, e[i].Name)) then Inc(exist);
  if (exist > 0) and not AskYesNo(IntToStr(exist) + ' item(s) already exist in ' + TargetDir, 'Overwrite them?') then Exit;
  j := TTransferJob.Create;
  j.Upload := False;
  SetLength(j.Items, n);
  for i := 0 to n - 1 do
  begin
    j.Items[i].Src := FullPath(e[i].Name);
    j.Items[i].Dst := LocalJoin(TargetDir, e[i].Name);
    j.Items[i].IsDir := e[i].IsDir and not e[i].IsLink;
  end;
  StartTransfer(j);
end;

procedure TFileBrowser.DownloadSelectedAsk;
var
  dir: string;
begin
  if FLocal then
  begin
    if (Peer <> nil) and not Peer.IsLocal and Peer.Connected then
      Peer.UploadFiles(nil, '')
    else
      MsgInfo('Local folder', 'These files are already on this computer.');
    Exit;
  end;
  if (Peer <> nil) and Peer.IsLocal and (Peer.Path <> '') then
    dir := Peer.Path
  else
  begin
    dir := Settings.DownloadFolder;
    if (dir = '') or not DirectoryExists(dir) then dir := DownloadDir;
    if not ChooseFolder('Download to...', dir, dir) then Exit;
  end;
  DownloadSelected(dir);
end;

procedure TFileBrowser.UploadFiles(const Files: TStringArray; const TargetDir: string);
var
  j: TTransferJob;
  i, n, exist, k: Integer;
  target: string;
  srcs: TStringArray;
  e: TFileEntries;
begin
  if FLocal then Exit;
  target := TargetDir;
  if target = '' then target := FPath;
  srcs := Files;
  if (Length(srcs) = 0) and (Peer <> nil) and Peer.IsLocal then
  begin
    { upload what is selected in the local pane }
    e := Peer.SelectedEntries(n);
    SetLength(srcs, n);
    for i := 0 to n - 1 do srcs[i] := Peer.FullPath(e[i].Name);
  end;
  if Length(srcs) = 0 then
  begin
    MsgInfo('Nothing to upload', 'Select the local files to upload first.');
    Exit;
  end;
  exist := 0;
  if target = FPath then
    for i := 0 to High(srcs) do
      for k := 0 to High(FEntries) do
        if FEntries[k].Name = ExtractFileName(srcs[i]) then Inc(exist);
  if (exist > 0) and not AskYesNo(IntToStr(exist) + ' item(s) already exist on the server', 'Overwrite them?') then Exit;
  j := TTransferJob.Create;
  j.Upload := True;
  SetLength(j.Items, Length(srcs));
  for i := 0 to High(srcs) do
  begin
    j.Items[i].Src := srcs[i];
    j.Items[i].Dst := LocalJoin(target, ExtractFileName(ExcludeTrailingPathDelimiter(srcs[i])));
    j.Items[i].IsDir := DirectoryExists(srcs[i]);
  end;
  StartTransfer(j);
end;

procedure TFileBrowser.UploadAsk;
var
  files: TStringArray;
  sel: TStringList;
  n: Integer;
begin
  if FLocal then
  begin
    if Peer <> nil then Peer.UploadFiles(nil, '');
    Exit;
  end;
  if (Peer <> nil) and Peer.IsLocal then
  begin
    sel := Peer.SelectedNames;
    n := sel.Count;
    sel.Free;
    if n > 0 then
    begin
      UploadFiles(nil, '');
      Exit;
    end;
  end;
  if ChooseOpenFiles('Upload files to ' + FPath, HomeDir, files) then
    UploadFiles(files, '');
end;

{ ---------------------------------------------------------------- file operations }

procedure TFileBrowser.DeleteSelected;
var
  names: TStringList;
  j: TOpJob;
  i: Integer;
  msg: string;
begin
  names := SelectedNames;
  try
    if names.Count = 0 then Exit;
    if names.Count = 1 then msg := '"' + names[0] + '"' else msg := IntToStr(names.Count) + ' items';
    if not AskYesNo('Delete ' + msg + '?', 'Folders are deleted with all their content. This cannot be undone.') then Exit;
    j := TOpJob.Create;
    j.Owner := Self;
    j.Token := FToken;
    j.Kind := opDelete;
    for i := 0 to names.Count - 1 do
      j.Paths.Add(FullPath(names[i]));
    FWorker.Add(j);
  finally
    names.Free;
  end;
end;

procedure TFileBrowser.RenameSelected;
var
  names: TStringList;
  nm: string;
  j: TOpJob;
begin
  names := SelectedNames;
  try
    if names.Count <> 1 then Exit;
    nm := names[0];
    if not InputQuery('Rename', 'New name:', nm) then Exit;
    nm := Trim(nm);
    if (nm = '') or (nm = names[0]) or (Pos('/', nm) > 0) then Exit;
    j := TOpJob.Create;
    j.Owner := Self;
    j.Token := FToken;
    j.Kind := opRename;
    j.Paths.Add(FullPath(names[0]));
    j.Arg := FullPath(nm);
    FWorker.Add(j);
  finally
    names.Free;
  end;
end;

procedure TFileBrowser.NewFolder;
var
  nm: string;
  j: TOpJob;
begin
  if not FConnected then Exit;
  nm := 'New folder';
  if not InputQuery('New folder', 'Folder name:', nm) then Exit;
  nm := Trim(nm);
  if (nm = '') or (Pos('/', nm) > 0) then Exit;
  j := TOpJob.Create;
  j.Owner := Self;
  j.Token := FToken;
  j.Kind := opMkDir;
  j.Paths.Add(FullPath(nm));
  FWorker.Add(j);
end;

procedure TFileBrowser.NewFile;
var
  nm: string;
  j: TOpJob;
begin
  if not FConnected then Exit;
  nm := 'new_file.txt';
  if not InputQuery('New file', 'File name:', nm) then Exit;
  nm := Trim(nm);
  if (nm = '') or (Pos('/', nm) > 0) then Exit;
  j := TOpJob.Create;
  j.Owner := Self;
  j.Token := FToken;
  j.Kind := opNewFile;
  j.Paths.Add(FullPath(nm));
  FWorker.Add(j);
end;

procedure TFileBrowser.ChmodSelected;
var
  e: TFileEntries;
  n, i, r, c: Integer;
  d, area, grid, checks: Pointer;
  boxes: array[0..8] of Pointer;
  octal: Pointer;
  mode: LongWord;
  who: array[0..2] of string = ('Owner', 'Group', 'Others');
  what: array[0..2] of string = ('Read', 'Write', 'Execute');
  j: TOpJob;
begin
  e := SelectedEntries(n);
  if n = 0 then Exit;
  mode := e[0].Mode;
  d := gtk_dialog_new_with_buttons('Permissions', MainWindowWidget, GTK_DIALOG_MODAL or GTK_DIALOG_DESTROY_WITH_PARENT,
    '_Cancel', GTK_RESPONSE_CANCEL, '_OK', GTK_RESPONSE_OK, nil);
  area := gtk_dialog_get_content_area(d);
  grid := gtk_grid_new;
  gtk_grid_set_row_spacing(grid, 6);
  gtk_grid_set_column_spacing(grid, 14);
  SetMargins(grid, 14);
  if n = 1 then
    gtk_grid_attach(grid, NewMarkupLabel('<b>' + MarkupEscape(e[0].Name) + '</b>'), 0, 0, 4, 1)
  else
    gtk_grid_attach(grid, NewMarkupLabel('<b>' + IntToStr(n) + ' items</b>'), 0, 0, 4, 1);
  for c := 0 to 2 do
    gtk_grid_attach(grid, NewMarkupLabel('<b>' + what[c] + '</b>', 0.5), c + 1, 1, 1, 1);
  for r := 0 to 2 do
  begin
    gtk_grid_attach(grid, NewLabel(who[r], 0), 0, r + 2, 1, 1);
    for c := 0 to 2 do
    begin
      checks := gtk_check_button_new;
      gtk_widget_set_halign(checks, GTK_ALIGN_CENTER);
      gtk_toggle_button_set_active(checks, (mode and (1 shl (8 - (r * 3 + c)))) <> 0);
      boxes[r * 3 + c] := checks;
      gtk_grid_attach(grid, checks, c + 1, r + 2, 1, 1);
    end;
  end;
  gtk_grid_attach(grid, NewLabel('Octal (overrides when changed)', 0), 0, 5, 2, 1);
  octal := gtk_entry_new;
  gtk_entry_set_width_chars(octal, 6);
  SetEntryText(octal, OctStr(mode and &777, 3));
  gtk_grid_attach(grid, octal, 2, 5, 2, 1);
  gtk_container_add(area, grid);
  gtk_widget_show_all(d);
  if gtk_dialog_run(d) = GTK_RESPONSE_OK then
  begin
    if Trim(EntryText(octal)) <> OctStr(mode and &777, 3) then
      mode := StrToIntDef('&' + Trim(EntryText(octal)), mode) and &7777
    else
    begin
      mode := mode and not LongWord(&777);
      for i := 0 to 8 do
        if gtk_toggle_button_get_active(boxes[i]) then
          mode := mode or (1 shl (8 - i));
    end;
    j := TOpJob.Create;
    j.Owner := Self;
    j.Token := FToken;
    j.Kind := opChmod;
    j.Mode := mode;
    for i := 0 to n - 1 do j.Paths.Add(FullPath(e[i].Name));
    FWorker.Add(j);
  end;
  gtk_widget_destroy(d);
end;

procedure TFileBrowser.OpenSelected(Edit: Boolean);
var
  e: TFileEntries;
  n: Integer;
  j: TTransferJob;
  dir: string;
begin
  e := SelectedEntries(n);
  if n <> 1 then Exit;
  if e[0].IsDir then
  begin
    Navigate(FullPath(e[0].Name));
    Exit;
  end;
  if FLocal then
  begin
    if Edit then
    begin
      if App <> nil then App.OpenEditor(FullPath(e[0].Name));
    end
    else
      OpenPath(FullPath(e[0].Name));
    Exit;
  end;
  { remote: download to a private temporary folder, open, and watch for changes }
  dir := RuntimeDir + '/edit-' + RandomToken(8);
  fpMkDir(dir, &700);
  j := TTransferJob.Create;
  j.Upload := False;
  SetLength(j.Items, 1);
  j.Items[0].Src := FullPath(e[0].Name);
  j.Items[0].Dst := LocalJoin(dir, e[0].Name);
  j.Items[0].IsDir := False;
  j.OpenAfter := True;
  if Edit then j.WatchRemote := 'edit';
  StartTransfer(j);
end;

procedure TFileBrowser.CopyPath;
var
  names: TStringList;
  p: string;
begin
  names := SelectedNames;
  try
    if names.Count > 0 then p := FullPath(names[0]) else p := FPath;
  finally
    names.Free;
  end;
  gtk_clipboard_set_text(gtk_clipboard_get(GDK_SELECTION_CLIPBOARD), PChar(p), -1);
  if App <> nil then App.SetStatus('Copied: ' + p);
end;

procedure TFileBrowser.ToggleHidden;
begin
  FShowHidden := not FShowHidden;
  g_signal_handlers_block_by_func(FHiddenBtn, @BtnHidden, Self);
  gtk_toggle_button_set_active(FHiddenBtn, FShowHidden);
  g_signal_handlers_unblock_by_func(FHiddenBtn, @BtnHidden, Self);
  FillList;
end;

procedure TFileBrowser.PopupMenu(Event: Pointer);
var
  menu: Pointer;
  e: TFileEntries;
  n: Integer;
begin
  if not FConnected then Exit;
  e := SelectedEntries(n);
  menu := gtk_menu_new;
  if n = 1 then
  begin
    if e[0].IsDir then
      NewImageMenuItem(menu, '_Open folder', 'folder-open', @MOpen, Self)
    else
    begin
      NewImageMenuItem(menu, '_Open with default application', 'document-open', @MOpen, Self);
      NewImageMenuItem(menu, '_Edit with LinXterm text editor', 'accessories-text-editor', @MEdit, Self);
    end;
  end;
  if not FLocal then
  begin
    if n > 0 then NewImageMenuItem(menu, '_Download', 'go-down', @MDownload, Self);
    NewImageMenuItem(menu, '_Upload to current folder...', 'go-up', @MUpload, Self);
  end;
  NewMenuSeparator(menu);
  if n = 1 then NewImageMenuItem(menu, '_Rename', 'document-edit', @MRename, Self);
  if n > 0 then
  begin
    NewImageMenuItem(menu, '_Delete', 'edit-delete', @MDelete, Self);
    NewImageMenuItem(menu, '_Permissions...', 'document-properties', @MChmod, Self);
  end;
  NewImageMenuItem(menu, 'New _folder', 'folder-new', @MNewFolder, Self);
  NewImageMenuItem(menu, 'New empty _file', 'document-new', @MNewFile, Self);
  NewMenuSeparator(menu);
  NewImageMenuItem(menu, '_Copy path to clipboard', 'edit-copy', @MCopyPath, Self);
  NewCheckMenuItem(menu, 'Show _hidden files', FShowHidden, @MHidden, Self);
  if FLocal then
  begin
    NewImageMenuItem(menu, 'Open _terminal here', 'utilities-terminal', @MOpenTerminal, Self);
    NewImageMenuItem(menu, 'Open in file _manager', 'system-file-manager', @MFileManager, Self);
  end;
  NewImageMenuItem(menu, 'Re_fresh', 'view-refresh', @MRefresh, Self);
  PopupMenuAtPointer(menu, FView, Event);
end;

{ non interactive operations used by the automated tests }
procedure TFileBrowser.TestOp(const Op, A, B: string);
var
  j: TOpJob;
  t: TTransferJob;
  i: Integer;
  files: TStringArray;
begin
  if Op = 'cd' then
  begin
    Navigate(A);
    Exit;
  end;
  if (Op = 'upload') then
  begin
    SetLength(files, 1);
    files[0] := A;
    UploadFiles(files, '');
    Exit;
  end;
  if Op = 'download' then
  begin
    t := TTransferJob.Create;
    t.Upload := False;
    SetLength(t.Items, 1);
    t.Items[0].Src := FullPath(A);
    t.Items[0].Dst := LocalJoin(B, A);
    t.Items[0].IsDir := False;
    for i := 0 to High(FEntries) do
      if FEntries[i].Name = A then t.Items[0].IsDir := FEntries[i].IsDir and not FEntries[i].IsLink;
    StartTransfer(t);
    Exit;
  end;
  j := TOpJob.Create;
  j.Owner := Self;
  j.Token := FToken;
  j.Paths.Add(FullPath(A));
  if Op = 'mkdir' then j.Kind := opMkDir
  else if Op = 'newfile' then j.Kind := opNewFile
  else if Op = 'delete' then j.Kind := opDelete
  else if Op = 'rename' then
  begin
    j.Kind := opRename;
    j.Arg := FullPath(B);
  end
  else if Op = 'chmod' then
  begin
    j.Kind := opChmod;
    j.Mode := StrToIntDef('&' + B, &644);
  end
  else
  begin
    j.Free;
    Exit;
  end;
  FWorker.Add(j);
end;

{ ---------------------------------------------------------------- drag and drop }

procedure TFileBrowser.DragGet(SelData: Pointer; Info: guint);
var
  names: TStringList;
  i: Integer;
  s: string;
  uris: array of PChar;
  us: array of string;
begin
  names := SelectedNames;
  try
    if names.Count = 0 then Exit;
    if Info = TARGET_INTERNAL then
    begin
      s := IntToHex(PtrUInt(Self), 16);
      for i := 0 to names.Count - 1 do
        s := s + #10 + FullPath(names[i]);
      gtk_selection_data_set(SelData, gtk_selection_data_get_target(SelData), 8, PChar(s), Length(s));
    end
    else if FLocal then
    begin
      SetLength(us, names.Count);
      SetLength(uris, names.Count + 1);
      for i := 0 to names.Count - 1 do
      begin
        us[i] := TakeStr(g_filename_to_uri(PChar(FullPath(names[i])), nil, nil));
        uris[i] := PChar(us[i]);
      end;
      uris[names.Count] := nil;
      gtk_selection_data_set_uris(SelData, @uris[0]);
    end;
  finally
    names.Free;
  end;
end;

procedure TFileBrowser.DragReceived(X, Y: Integer; SelData: Pointer; Info: guint; Ctx: Pointer; Time: guint32);
var
  len, i: Integer;
  raw, target: string;
  lines: TStringArray;
  src: TFileBrowser;
  files: TStringArray;
  uris: PPChar;
  p: PPChar;
  tpath: Pointer;
  pos: gint;
  it: TGtkTreeIter;
  name: PChar;
  isdir: gboolean;
  ok: Boolean;
  nm: string;
  j: TTransferJob;
begin
  ok := False;
  target := FPath;
  tpath := nil;
  { dropped on a folder row: use that folder }
  if gtk_tree_view_get_dest_row_at_pos(FView, X, Y, @tpath, @pos) then
  begin
    if gtk_tree_model_get_iter(FStore, @it, tpath) then
    begin
      name := nil;
      gtk_tree_model_get(FStore, @it, COL_NAME, @name, COL_ISDIR, @isdir, -1);
      nm := TakeStr(name);
      if isdir and (nm <> '..') and (pos in [2, 3]) then target := FullPath(nm);
    end;
    gtk_tree_path_free(tpath);
  end;
  files := nil;
  src := nil;
  if Info = TARGET_INTERNAL then
  begin
    len := gtk_selection_data_get_length(SelData);
    if len > 0 then
    begin
      SetString(raw, gtk_selection_data_get_data(SelData), len);
      lines := SplitString(raw, #10);
      if Length(lines) > 1 then
      begin
        src := TFileBrowser(PtrUInt(StrToQWordDef('$' + lines[0], 0)));
        if LiveBrowsers.IndexOf(src) < 0 then src := nil;
        SetLength(files, Length(lines) - 1);
        for i := 1 to High(lines) do files[i - 1] := lines[i];
      end;
    end;
  end
  else
  begin
    uris := gtk_selection_data_get_uris(SelData);
    if uris <> nil then
    begin
      p := uris;
      while p^ <> nil do
      begin
        nm := TakeStr(g_filename_from_uri(p^, nil, nil));
        if nm <> '' then
        begin
          SetLength(files, Length(files) + 1);
          files[High(files)] := nm;
        end;
        Inc(p);
      end;
      g_strfreev(uris);
    end;
  end;
  gtk_drag_finish(Ctx, Length(files) > 0, False, Time);
  if (Length(files) = 0) or (src = Self) or not FConnected then Exit;
  if (src = nil) or src.IsLocal then
  begin
    { local files dropped here }
    if FLocal then
    begin
      j := TTransferJob.Create;
      j.Upload := True;
      SetLength(j.Items, Length(files));
      for i := 0 to High(files) do
      begin
        j.Items[i].Src := files[i];
        j.Items[i].Dst := LocalJoin(target, ExtractFileName(files[i]));
        j.Items[i].IsDir := DirectoryExists(files[i]);
      end;
      StartTransfer(j);
    end
    else
      UploadFiles(files, target);
    ok := True;
  end
  else if FLocal and not src.IsLocal then
  begin
    { remote files dropped on a local browser: let the remote side download }
    j := TTransferJob.Create;
    j.Upload := False;
    SetLength(j.Items, Length(files));
    for i := 0 to High(files) do
    begin
      j.Items[i].Src := files[i];
      j.Items[i].Dst := LocalJoin(target, RemoteBaseName(files[i]));
      j.Items[i].IsDir := False;
      for len := 0 to High(src.FEntries) do
        if LocalJoin(src.FPath, src.FEntries[len].Name) = files[i] then
          j.Items[i].IsDir := src.FEntries[len].IsDir and not src.FEntries[len].IsLink;
    end;
    j.RefreshTarget := Self;
    src.StartTransfer(j);
    ok := True;
  end
  else
    MsgInfo('Not supported', 'Transfers between two remote servers are not supported. ' +
      'Download the files first, then upload them.');
  if ok then ;
end;

end.

{ LinXterm - main window: menu bar, big toolbar, quick connect, vertical
  side panel tabs (Sessions / Tools / Macros / Sftp), home tab, session
  tabs, split view, MultiExec mode, detached windows and test scripting. }
unit lxmainwin;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, BaseUnix, fpjson, jsonparser, lxgtk, lxutil, lxconfig, lxtabs, lxterminal,
  lxsessiondlg, lxsessionpanel;

type
  TMainWindow = class;

  THomeTab = class(TTabPage)
  public
    Owner: TMainWindow;
    RecentList: Pointer;
    RestoreBtn: Pointer;
    SearchEntry: Pointer;
    constructor Create(AOwner: TMainWindow);
    procedure RefreshRecent;
    procedure FocusContent; override;
  end;

  TSplitTile = record
    Frame: Pointer;
    Header: Pointer;
    Combo: Pointer;
    Check: Pointer;    { MultiExec: "Receive input" }
    Slot: Pointer;
    Tab: TTerminalTab;
  end;

  TDetachedWindow = class
  public
    Window: Pointer;
    Notebook: Pointer;
    Owner: TMainWindow;
    constructor Create(AOwner: TMainWindow);
  end;

  TMainWindow = class(TAppIntf)
  private
    FApp: Pointer;
    FAccel: Pointer;
    FMenuBar, FToolbar, FStatusBar, FStatusLabel, FStatusRight: Pointer;
    FPaned, FLeftBox, FQuickEntry, FSideStack, FStrip, FCollapseBtn: Pointer;
    FSideButtons: array[0..3] of Pointer;
    FSidePages: array[0..3] of string;
    FSideGuard: Boolean;
    FSideCollapsed: Boolean;
    FSavedPanedPos: Integer;
    FMainStack: Pointer;
    FNotebook: Pointer;
    FSplitBox, FSplitGrid, FMultiBar, FMultiLabel: Pointer;
    FSplitOnly: TList;        { terminals shown by the split view ('' = all) }
    FQuickStore: Pointer;     { completion of the quick connect / home search entries }
    FKeepFilter: Boolean;
    FTiles: array of TSplitTile;
    FSplitMode: Integer;
    FMultiExec: Boolean;
    FMultiExecBtn: Pointer;
    FMultiExecGuard: Boolean;
    FTabs: TList;
    FDetached: TList;
    FTabCounter: Integer;
    FPendingTile: Integer;    { split tile that receives the next terminal tab }
    FHome: THomeTab;
    FSessions: TSessionsPanel;
    FFocusedTab: TTabPage;
    FCss: Pointer;
    FFullscreen: Boolean;
    FQuitting: Boolean;
    FMenuSidebar, FMenuToolbar, FMenuMenubar, FMenuStatusbar: Pointer;
    FMenuSkinLight, FMenuSkinDark: Pointer;
    FTestCmds: TStringList;
    FTestIndex: Integer;
    FTestShotCount: Integer;
    procedure BuildMenuBar(VBox: Pointer);
    procedure BuildToolbar(VBox: Pointer);
    procedure BuildBody(VBox: Pointer);
    procedure BuildStatusBar(VBox: Pointer);
    function ToolbarButton(const Icon, Text, Tip: string; Cb: Pointer): Pointer;
    procedure AddAccel(Item: Pointer; Key: guint; Mods: guint);
    procedure UpdateStatusRight;
    function NotebookOf(Tab: TTabPage): Pointer;
    procedure SetupNotebook(NB: Pointer);
    procedure AttachSplitTiles(Prefer: TList = nil);
    procedure DetachSplitTiles;
    function TileTabs: TList;
    function SplitCandidates: TList;
    function EmptyTile(Index: Integer): Pointer;
    procedure SyncTileChecks;
    procedure UpdateMultiLabel;
    procedure AddQuickCompletion(Entry: Pointer);
    procedure RebuildSplit;
    function TerminalTabs: TList;
    function TerminalCount: Integer;
    procedure SaveOpenTabs;
  public
    Window: Pointer;
    constructor Create(AApp: Pointer);
    destructor Destroy; override;
    procedure ApplySkin;
    procedure ApplyVisibility;
    procedure ApplyTerminalSettings;
    { TAppIntf }
    procedure AddTab(Tab: TTabPage; Activate: Boolean); override;
    procedure CloseTab(Tab: TTabPage); override;
    procedure CloseTabLater(Tab: TTabPage); override;
    procedure ActivateTab(Tab: TTabPage); override;
    function CurrentTab: TTabPage; override;
    procedure OpenSession(S: TSession); override;
    procedure NewLocalTerminal; override;
    procedure RunCommandTab(const ATitle, AIcon: string; const Argv: array of string); override;
    procedure SetStatus(const Msg: string); override;
    procedure TabChanged(Tab: TTabPage); override;
    procedure TabFocused(Tab: TTabPage); override;
    procedure ShowTabMenu(Tab: TTabPage; Event: Pointer); override;
    procedure DuplicateTab(Tab: TTabPage); override;
    procedure RenameTab(Tab: TTabPage); override;
    procedure DetachTab(Tab: TTabPage); override;
    procedure RefreshSessionTree; override;
    procedure EditSession(S: TSession); override;
    function MultiExecActive: Boolean; override;
    procedure TerminalInput(Sender: TTabPage; const Data: string); override;
    procedure OpenEditor(const FileName: string); override;
    procedure SettingsChanged; override;
    function TabVisible(Tab: TTabPage): Boolean; override;
    procedure OpenFolder(const Folder: string; Layout: Integer); override;
    procedure NotifyTab(Tab: TTabPage; const Title, Body: string); override;
    procedure ShowTabNumber(N: Integer);
    procedure TileCheckToggled(Index: Integer);
    procedure FillQuickCompletion;
    { actions }
    procedure RemoveTab(Tab: TTabPage);
    function HasTab(Tab: TTabPage): Boolean;
    procedure NewSessionDialog;
    procedure QuickConnect(const Text: string);
    procedure RecoverSessions;
    procedure OpenRecent(const Key: string);
    procedure SetSplitMode(Mode: Integer);
    procedure SetMultiExec(V: Boolean);
    procedure ShowSidePage(Index: Integer);
    procedure SetSidebarCollapsed(V: Boolean);
    procedure ToggleFullscreen;
    procedure ShowXServerInfo;
    procedure ShowAbout;
    procedure ShowShortcuts;
    procedure ShowCommandPalette;
    procedure ImportSessions;
    procedure ImportFrom(const Source: string);
    procedure BuildImportMenu(Menu: Pointer);
    procedure ExportSessions;
    procedure Quit;
    procedure PopupToolbarMenu(Button: Pointer; Kind: Integer);
    procedure SwitchedPage(Page: Pointer);
    procedure TileComboChanged(Index: Integer);
    procedure NewTerminalInTile(Index: Integer);
    procedure OpenSessionInTile(Index: Integer; Button: Pointer);
    procedure ProcessCommandLine(const Args: TStringArray);
    procedure StartTestScript(const Script: string);
    function TestStep: Boolean;
  end;

var
  MainWin: TMainWindow = nil;

procedure RunApplication;

implementation

uses
  StrUtils, Math, lximport;

const
  SIDE_SESSIONS = 0;
  SIDE_TOOLS = 1;
  SIDE_MACROS = 2;
  SIDE_SFTP = 3;

  MENU_SERVERS = 1;
  MENU_TOOLS = 2;
  MENU_GAMES = 3;
  MENU_SESSIONS = 4;
  MENU_VIEW = 5;
  MENU_SPLIT = 6;
  MENU_HELP = 7;
  MENU_XSERVER = 8;

  LightCss =
    '.lx-main { font-size: 10pt; }'#10 +
    '.lx-menubar { background-color: #ffffff; border-bottom: 1px solid #e3e3e3; padding: 0; }'#10 +
    '.lx-menubar > menuitem { padding: 3px 8px; }'#10 +
    '.lx-toolbar { background-color: #ffffff; border-bottom: 1px solid #d6d6d6; padding: 2px 4px 3px 4px; }'#10 +
    '.lx-toolbar button { padding: 3px 5px 1px 5px; margin: 0; border-radius: 0; border: 1px solid transparent; background: none; box-shadow: none; min-width: 46px; }'#10 +
    '.lx-toolbar button:hover { background-color: #e5f3ff; border-color: #cce8ff; }'#10 +
    '.lx-toolbar button:checked, .lx-toolbar button:active { background-color: #cce8ff; border-color: #99d1ff; }'#10 +
    '.lx-toolbar label { font-size: 9pt; color: #1e1e1e; }'#10 +
    '.lx-body { background-color: #f0f0f0; }'#10 +
    '.lx-quick { margin: 3px 2px 2px 3px; font-size: 11pt; min-height: 24px; }'#10 +
    '.lx-strip { background-color: #f0f0f0; padding: 0 0 0 2px; }'#10 +
    '.lx-strip button { border-radius: 0; padding: 8px 1px; margin: 0 0 2px 0; background: #dbe5f1; border: 1px solid #b4c4d9; border-right-width: 0; box-shadow: none; }'#10 +
    '.lx-strip button:hover { background: #e8f0fa; }'#10 +
    '.lx-strip button:checked { background: #ffffff; border-color: #b4c4d9; }'#10 +
    '.lx-strip button label { font-size: 9pt; font-weight: bold; color: #303030; }'#10 +
    '.lx-collapse { padding: 2px; margin-bottom: 6px; border: none; background: none; box-shadow: none; color: #1a73e8; font-weight: bold; font-size: 14pt; }'#10 +
    '.lx-sidepanel { background-color: #ffffff; border: 1px solid #b4c4d9; }'#10 +
    '.lx-sidepanel treeview { background-color: #ffffff; }'#10 +
    'notebook.lx-tabs > header { background-color: #f0f0f0; border-bottom: 1px solid #b9b9b9; padding: 2px 0 0 0; }'#10 +
    'notebook.lx-tabs > header > tabs > tab { padding: 2px 6px; min-height: 22px; margin: 0 1px; background: #e6e6e6; border: 1px solid #c8c8c8; border-bottom: none; border-radius: 3px 3px 0 0; }'#10 +
    'notebook.lx-tabs > header > tabs > tab:checked { background: #2b2b2b; border-color: #2b2b2b; }'#10 +
    'notebook.lx-tabs > header > tabs > tab:checked label { color: #ffffff; }'#10 +
    'notebook.lx-tabs > header > tabs > tab:checked .lx-tab-close image { color: #ffffff; }'#10 +
    '.lx-tab-close { padding: 0; min-height: 14px; min-width: 14px; margin-left: 4px; }'#10 +
    '.lx-tabmark { min-width: 4px; min-height: 16px; border-radius: 2px; margin-right: 1px; }'#10 +
    '.lx-tabmark.red { background-color: #e53935; }'#10 +
    '.lx-tabmark.orange { background-color: #fb8c00; }'#10 +
    '.lx-tabmark.yellow { background-color: #fdd835; }'#10 +
    '.lx-tabmark.green { background-color: #43a047; }'#10 +
    '.lx-tabmark.blue { background-color: #1e88e5; }'#10 +
    '.lx-tabmark.purple { background-color: #8e24aa; }'#10 +
    '.lx-tabmark.gray { background-color: #78909c; }'#10 +
    '.lx-newtab { padding: 0 6px; margin: 2px 4px; min-height: 18px; border-radius: 3px; }'#10 +
    '.lx-status { background-color: #f0f0f0; border-top: 1px solid #d6d6d6; padding: 1px 6px; font-size: 9pt; color: #404040; }'#10 +
    '.lx-multibar { background-color: #fffbd0; border-bottom: 1px solid #e1d68a; padding: 6px 10px; }'#10 +
    '.lx-multibar label { font-weight: bold; }'#10 +
    '.lx-tile-header { background-color: #3c3c3c; padding: 1px 4px; }'#10 +
    '.lx-tile-header label { color: #f0f0f0; font-size: 9pt; }'#10 +
    '.lx-tile-active .lx-tile-header { background-color: #1a73e8; }'#10 +
    '.lx-tile-off .lx-tile-header { background-color: #8a8a8a; }'#10 +
    '.lx-monitor { background-color: #e9e9e9; border-top: 1px solid #c0c0c0; }'#10 +
    '.lx-monitor label { font-size: 9pt; color: #202020; }'#10 +
    '.lx-monitor levelbar trough { min-height: 8px; min-width: 50px; padding: 1px; border-radius: 2px; }'#10 +
    '.lx-monitor levelbar block { min-height: 6px; border-radius: 1px; }'#10 +
    '.lx-monitor levelbar block.lx-ok { background-color: #43a047; border-color: #2e7d32; }'#10 +
    '.lx-monitor levelbar block.lx-warn { background-color: #fb8c00; border-color: #ef6c00; }'#10 +
    '.lx-monitor levelbar block.lx-crit { background-color: #e53935; border-color: #c62828; }'#10 +
    '.lx-searchbar { background-color: #f3f3f3; }'#10 +
    '.lx-home { background-color: #ffffff; }'#10 +
    '.lx-home-title { font-size: 26pt; font-weight: bold; color: #1b2a40; }'#10 +
    '.lx-home-sub { color: #6b6b6b; }'#10 +
    '.lx-home-big { padding: 10px 20px; font-size: 11pt; }'#10 +
    '.lx-home list { background-color: #ffffff; border: 1px solid #e2e2e2; }'#10 +
    '.lx-home list row { padding: 4px 8px; }'#10 +
    '.lx-home-caption { font-weight: bold; color: #1b2a40; }'#10 +
    '.lx-kind-row button { padding: 4px 6px; min-width: 58px; border-radius: 0; border: 1px solid transparent; }'#10 +
    '.lx-kind-row button:checked { background: #cce8ff; border-color: #99d1ff; }'#10 +
    '.lx-kind-row button label { font-size: 9pt; }'#10 +
    '.lx-group > label { color: #1b4f8a; }'#10 +
    '.lx-browser-path { font-size: 9pt; }'#10 +
    '.lx-browser-toolbar button { padding: 2px; min-height: 20px; min-width: 20px; }'#10 +
    '.lx-panel-title { font-weight: bold; padding: 4px; color: #1b2a40; }'#10 +
    '.lx-palette { background-color: #ffffff; border: 1px solid #9fb4cc; border-radius: 6px; }'#10 +
    '.lx-palette list { background-color: #ffffff; }'#10 +
    '.lx-palette list row:selected { background-color: #cce8ff; color: #1e1e1e; }'#10;

  DarkCss =
    '.lx-main { font-size: 10pt; }'#10 +
    '.lx-menubar { background-color: #2b2b2b; border-bottom: 1px solid #1f1f1f; }'#10 +
    '.lx-toolbar { background-color: #2b2b2b; border-bottom: 1px solid #1f1f1f; padding: 2px 4px 3px 4px; }'#10 +
    '.lx-toolbar button { padding: 3px 5px 1px 5px; margin: 0; border-radius: 0; border: 1px solid transparent; background: none; box-shadow: none; min-width: 46px; }'#10 +
    '.lx-toolbar button:hover { background-color: #3d4a5a; border-color: #4f6177; }'#10 +
    '.lx-toolbar button:checked { background-color: #2f5f8f; border-color: #4f86bd; }'#10 +
    '.lx-toolbar label { font-size: 9pt; color: #e8e8e8; }'#10 +
    '.lx-body { background-color: #232323; }'#10 +
    '.lx-quick { margin: 3px 2px 2px 3px; font-size: 11pt; min-height: 24px; }'#10 +
    '.lx-strip { background-color: #232323; padding: 0 0 0 2px; }'#10 +
    '.lx-strip button { border-radius: 0; padding: 8px 1px; margin: 0 0 2px 0; background: #34404e; border: 1px solid #46566a; border-right-width: 0; box-shadow: none; }'#10 +
    '.lx-strip button:checked { background: #1e1e1e; }'#10 +
    '.lx-strip button label { font-size: 9pt; font-weight: bold; color: #e0e0e0; }'#10 +
    '.lx-collapse { padding: 2px; margin-bottom: 6px; border: none; background: none; box-shadow: none; color: #6aa9ff; font-weight: bold; font-size: 14pt; }'#10 +
    '.lx-sidepanel { background-color: #1e1e1e; border: 1px solid #46566a; }'#10 +
    'notebook.lx-tabs > header { background-color: #232323; border-bottom: 1px solid #111; padding: 2px 0 0 0; }'#10 +
    'notebook.lx-tabs > header > tabs > tab { padding: 2px 6px; min-height: 22px; margin: 0 1px; background: #333; border: 1px solid #444; border-bottom: none; border-radius: 3px 3px 0 0; }'#10 +
    'notebook.lx-tabs > header > tabs > tab:checked { background: #000000; border-color: #555; }'#10 +
    '.lx-tab-close { padding: 0; min-height: 14px; min-width: 14px; margin-left: 4px; }'#10 +
    '.lx-tabmark { min-width: 4px; min-height: 16px; border-radius: 2px; margin-right: 1px; }'#10 +
    '.lx-tabmark.red { background-color: #e53935; }'#10 +
    '.lx-tabmark.orange { background-color: #fb8c00; }'#10 +
    '.lx-tabmark.yellow { background-color: #fdd835; }'#10 +
    '.lx-tabmark.green { background-color: #43a047; }'#10 +
    '.lx-tabmark.blue { background-color: #1e88e5; }'#10 +
    '.lx-tabmark.purple { background-color: #8e24aa; }'#10 +
    '.lx-tabmark.gray { background-color: #78909c; }'#10 +
    '.lx-newtab { padding: 0 6px; margin: 2px 4px; min-height: 18px; border-radius: 3px; }'#10 +
    '.lx-status { background-color: #232323; border-top: 1px solid #111; padding: 1px 6px; font-size: 9pt; color: #c0c0c0; }'#10 +
    '.lx-multibar { background-color: #5a5220; border-bottom: 1px solid #7a6f2a; padding: 6px 10px; }'#10 +
    '.lx-multibar label { font-weight: bold; color: #fff6c0; }'#10 +
    '.lx-tile-header { background-color: #3c3c3c; padding: 1px 4px; }'#10 +
    '.lx-tile-header label { color: #f0f0f0; font-size: 9pt; }'#10 +
    '.lx-tile-active .lx-tile-header { background-color: #1a73e8; }'#10 +
    '.lx-tile-off .lx-tile-header { background-color: #8a8a8a; }'#10 +
    '.lx-monitor { background-color: #2d2d2d; border-top: 1px solid #111; }'#10 +
    '.lx-monitor label { font-size: 9pt; color: #e0e0e0; }'#10 +
    '.lx-monitor levelbar trough { min-height: 8px; min-width: 50px; padding: 1px; border-radius: 2px; }'#10 +
    '.lx-monitor levelbar block { min-height: 6px; border-radius: 1px; }'#10 +
    '.lx-monitor levelbar block.lx-ok { background-color: #43a047; border-color: #2e7d32; }'#10 +
    '.lx-monitor levelbar block.lx-warn { background-color: #fb8c00; border-color: #ef6c00; }'#10 +
    '.lx-monitor levelbar block.lx-crit { background-color: #e53935; border-color: #c62828; }'#10 +
    '.lx-home { background-color: #1e1e1e; }'#10 +
    '.lx-home-title { font-size: 26pt; font-weight: bold; color: #e8eef7; }'#10 +
    '.lx-home-sub { color: #a0a0a0; }'#10 +
    '.lx-home-big { padding: 10px 20px; font-size: 11pt; }'#10 +
    '.lx-home list { border: 1px solid #3a3a3a; }'#10 +
    '.lx-home list row { padding: 4px 8px; }'#10 +
    '.lx-home-caption { font-weight: bold; color: #e8eef7; }'#10 +
    '.lx-kind-row button { padding: 4px 6px; min-width: 58px; border-radius: 0; border: 1px solid transparent; }'#10 +
    '.lx-kind-row button:checked { background: #2f5f8f; border-color: #4f86bd; }'#10 +
    '.lx-kind-row button label { font-size: 9pt; }'#10 +
    '.lx-group > label { color: #8cbcf2; }'#10 +
    '.lx-browser-path { font-size: 9pt; }'#10 +
    '.lx-browser-toolbar button { padding: 2px; min-height: 20px; min-width: 20px; }'#10 +
    '.lx-panel-title { font-weight: bold; padding: 4px; }'#10 +
    '.lx-palette { background-color: #252526; border: 1px solid #46566a; border-radius: 6px; }'#10 +
    '.lx-palette list { background-color: #252526; }'#10 +
    '.lx-palette list row:selected { background-color: #2f5f8f; }'#10;

{ ---------------------------------------------------------------- small callbacks }

type
  TIdleClose = class
    Win: TMainWindow;
    Tab: TTabPage;
  end;

function IdleCloseCb(data: gpointer): gboolean; cdecl;
var
  ic: TIdleClose;
begin
  ic := TIdleClose(data);
  if ic.Win.HasTab(ic.Tab) then
    ic.Win.CloseTab(ic.Tab);
  ic.Free;
  Result := False;
end;

function IdleFocusCb(data: gpointer): gboolean; cdecl;
var
  t: TTabPage;
begin
  t := TTabPage(data);
  if (MainWin <> nil) and MainWin.HasTab(t) then
    t.FocusContent;
  Result := False;
end;

function WindowDeleteCb(widget: Pointer; event: Pointer; data: gpointer): gboolean; cdecl;
begin
  TMainWindow(data).Quit;
  Result := True;
end;

procedure SwitchPageCb(notebook: Pointer; page: Pointer; num: guint; data: gpointer); cdecl;
begin
  TMainWindow(data).SwitchedPage(page);
end;

function CreateWindowCb(notebook: Pointer; page: Pointer; x, y: gint; data: gpointer): Pointer; cdecl;
var
  dw: TDetachedWindow;
begin
  dw := TDetachedWindow.Create(TMainWindow(data));
  Result := dw.Notebook;
end;

function DetachedEmptyCheck(data: gpointer): gboolean; cdecl;
var
  dw: TDetachedWindow;
begin
  Result := False;
  { several checks may be queued for the same window: it may be gone }
  if (MainWin = nil) or (MainWin.FDetached.IndexOf(data) < 0) then Exit;
  dw := TDetachedWindow(data);
  if gtk_notebook_get_n_pages(dw.Notebook) = 0 then
  begin
    MainWin.FDetached.Remove(dw);
    gtk_widget_destroy(dw.Window);
    dw.Free;
  end;
end;

procedure DetachedPageRemovedCb(notebook: Pointer; child: Pointer; num: guint; data: gpointer); cdecl;
begin
  g_idle_add(@DetachedEmptyCheck, data);
end;

function DetachedDeleteCb(widget: Pointer; event: Pointer; data: gpointer): gboolean; cdecl;
var
  dw: TDetachedWindow;
  i: Integer;
  page: Pointer;
  tab: TTabPage;
  lst: TList;
begin
  dw := TDetachedWindow(data);
  lst := TList.Create;
  try
    for i := 0 to gtk_notebook_get_n_pages(dw.Notebook) - 1 do
    begin
      page := gtk_notebook_get_nth_page(dw.Notebook, i);
      tab := TTabPage(g_object_get_data(page, 'lxtab'));
      if tab <> nil then lst.Add(tab);
    end;
    for i := 0 to lst.Count - 1 do
      dw.Owner.RemoveTab(TTabPage(lst[i]));
  finally
    lst.Free;
  end;
  Result := True;
  g_idle_add(@DetachedEmptyCheck, dw);
end;

{ menu callbacks }
procedure CbNewLocal(item: Pointer; data: gpointer); cdecl; begin MainWin.NewLocalTerminal; end;
procedure CbNewSession(item: Pointer; data: gpointer); cdecl; begin MainWin.NewSessionDialog; end;
procedure CbCloseTab(item: Pointer; data: gpointer); cdecl;
begin
  if (MainWin.CurrentTab <> nil) and MainWin.CurrentTab.Closable then
    MainWin.CloseTabLater(MainWin.CurrentTab);
end;
procedure CbDuplicate(item: Pointer; data: gpointer); cdecl;
begin
  if MainWin.CurrentTab <> nil then MainWin.DuplicateTab(MainWin.CurrentTab);
end;
procedure CbRename(item: Pointer; data: gpointer); cdecl;
begin
  if MainWin.CurrentTab <> nil then MainWin.RenameTab(MainWin.CurrentTab);
end;
procedure CbDetach(item: Pointer; data: gpointer); cdecl;
begin
  if MainWin.CurrentTab <> nil then MainWin.DetachTab(MainWin.CurrentTab);
end;
procedure CbFind(item: Pointer; data: gpointer); cdecl;
begin
  if MainWin.CurrentTab is TTerminalTab then TTerminalTab(MainWin.CurrentTab).ShowSearch;
end;
procedure CbClear(item: Pointer; data: gpointer); cdecl;
begin
  if MainWin.CurrentTab is TTerminalTab then TTerminalTab(MainWin.CurrentTab).ClearScrollback;
end;
procedure CbReset(item: Pointer; data: gpointer); cdecl;
begin
  if MainWin.CurrentTab is TTerminalTab then TTerminalTab(MainWin.CurrentTab).ResetTerminal;
end;
procedure CbSaveOutput(item: Pointer; data: gpointer); cdecl;
begin
  if MainWin.CurrentTab is TTerminalTab then TTerminalTab(MainWin.CurrentTab).SaveOutput;
end;
procedure CbLogFolder(item: Pointer; data: gpointer); cdecl;
begin
  ForceDirectories(Settings.LogDir);
  OpenPath(Settings.LogDir);
end;
procedure CbCopy(item: Pointer; data: gpointer); cdecl;
begin
  if MainWin.CurrentTab is TTerminalTab then TTerminalTab(MainWin.CurrentTab).CopySelection;
end;
procedure CbPaste(item: Pointer; data: gpointer); cdecl;
begin
  if MainWin.CurrentTab is TTerminalTab then TTerminalTab(MainWin.CurrentTab).Paste;
end;
procedure CbZoomIn(item: Pointer; data: gpointer); cdecl;
begin
  if MainWin.CurrentTab is TTerminalTab then TTerminalTab(MainWin.CurrentTab).ZoomIn;
end;
procedure CbZoomOut(item: Pointer; data: gpointer); cdecl;
begin
  if MainWin.CurrentTab is TTerminalTab then TTerminalTab(MainWin.CurrentTab).ZoomOut;
end;
procedure CbZoomReset(item: Pointer; data: gpointer); cdecl;
begin
  if MainWin.CurrentTab is TTerminalTab then TTerminalTab(MainWin.CurrentTab).ZoomReset;
end;
procedure CbNextTab(item: Pointer; data: gpointer); cdecl;
begin
  gtk_notebook_next_page(MainWin.FNotebook);
end;
procedure CbPrevTab(item: Pointer; data: gpointer); cdecl;
begin
  gtk_notebook_prev_page(MainWin.FNotebook);
end;
procedure CbQuit(item: Pointer; data: gpointer); cdecl; begin MainWin.Quit; end;
procedure CbRecover(item: Pointer; data: gpointer); cdecl; begin MainWin.RecoverSessions; end;
procedure CbImport(item: Pointer; data: gpointer); cdecl; begin MainWin.ImportSessions; end;
procedure CbImportSource(item: Pointer; data: gpointer); cdecl;
begin
  MainWin.ImportFrom(CStr(PChar(g_object_get_data(item, 'source'))));
end;
procedure CbExport(item: Pointer; data: gpointer); cdecl; begin MainWin.ExportSessions; end;
procedure CbShowSessions(item: Pointer; data: gpointer); cdecl;
begin
  MainWin.SetSidebarCollapsed(False);
  MainWin.ShowSidePage(SIDE_SESSIONS);
end;
procedure CbOpenFolder(item: Pointer; data: gpointer); cdecl;
begin
  MainWin.OpenFolder(CStr(PChar(g_object_get_data(item, 'folder'))), PtrInt(g_object_get_data(item, 'layout')));
end;

procedure CbOpenSavedSession(item: Pointer; data: gpointer); cdecl;
var
  s: TSession;
begin
  s := Store.FindById(CStr(PChar(g_object_get_data(item, 'sid'))));
  if s <> nil then MainWin.OpenSession(s);
end;

procedure CbToggleSidebar(item: Pointer; data: gpointer); cdecl;
begin
  Settings.ShowSidebar := gtk_check_menu_item_get_active(item);
  Settings.Save;
  MainWin.ApplyVisibility;
end;
procedure CbToggleToolbar(item: Pointer; data: gpointer); cdecl;
begin
  Settings.ShowToolbar := gtk_check_menu_item_get_active(item);
  Settings.Save;
  MainWin.ApplyVisibility;
end;
procedure CbToggleMenubar(item: Pointer; data: gpointer); cdecl;
begin
  Settings.ShowMenubar := gtk_check_menu_item_get_active(item);
  Settings.Save;
  MainWin.ApplyVisibility;
end;
procedure CbToggleStatusbar(item: Pointer; data: gpointer); cdecl;
begin
  Settings.ShowStatusbar := gtk_check_menu_item_get_active(item);
  Settings.Save;
  MainWin.ApplyVisibility;
end;
procedure CbFullscreen(item: Pointer; data: gpointer); cdecl; begin MainWin.ToggleFullscreen; end;
procedure CbSkinLight(item: Pointer; data: gpointer); cdecl;
begin
  if gtk_check_menu_item_get_active(item) then
  begin
    Settings.Skin := 'light';
    Settings.Save;
    MainWin.ApplySkin;
  end;
end;
procedure CbSkinDark(item: Pointer; data: gpointer); cdecl;
begin
  if gtk_check_menu_item_get_active(item) then
  begin
    Settings.Skin := 'dark';
    Settings.Save;
    MainWin.ApplySkin;
  end;
end;
procedure CbToggleSidebarKey(item: Pointer; data: gpointer); cdecl;
begin
  Settings.ShowSidebar := not Settings.ShowSidebar;
  MainWin.ApplyVisibility;
end;

procedure CbSplit(item: Pointer; data: gpointer); cdecl;
var
  mode: Integer;
begin
  if not gtk_check_menu_item_get_active(item) then Exit;
  mode := PtrInt(g_object_get_data(item, 'mode'));
  { a split layout replaces the MultiExec mosaic }
  if MainWin.MultiExecActive then MainWin.SetMultiExec(False);
  MainWin.SetSplitMode(mode);
end;
procedure CbMultiExecMenu(item: Pointer; data: gpointer); cdecl;
begin
  MainWin.SetMultiExec(not MainWin.MultiExecActive);
end;

procedure CbSettings(item: Pointer; data: gpointer); cdecl;
begin
  if Assigned(ShowSettingsProc) then ShowSettingsProc;
end;
procedure CbPasswords(item: Pointer; data: gpointer); cdecl;
begin
  if Assigned(ShowPasswordsProc) then ShowPasswordsProc;
end;
procedure CbServers(item: Pointer; data: gpointer); cdecl;
begin
  if Assigned(ShowServersProc) then ShowServersProc;
end;
procedure CbTunnels(item: Pointer; data: gpointer); cdecl;
begin
  if Assigned(ShowTunnelsProc) then ShowTunnelsProc;
end;
procedure CbPackages(item: Pointer; data: gpointer); cdecl;
begin
  if Assigned(ShowPackagesProc) then ShowPackagesProc;
end;
procedure CbXInfo(item: Pointer; data: gpointer); cdecl; begin MainWin.ShowXServerInfo; end;
procedure CbX11Default(item: Pointer; data: gpointer); cdecl;
begin
  Settings.X11Default := gtk_check_menu_item_get_active(item);
  Settings.Save;
end;
type
  TX11Reaper = class
    procedure Exited(Sender: TChildProcess; Status: Integer);
  end;

procedure TX11Reaper.Exited(Sender: TChildProcess; Status: Integer);
begin
  { the X11 application has quit: release its process object }
  FreeLater(Sender);
end;

var
  X11Reaper: TX11Reaper = nil;

procedure CbRunX11(item: Pointer; data: gpointer); cdecl;
var
  cmd, err: string;
  argc: gint;
  argv: PPChar;
  gerr: PGError;
  args: TStringArray;
  i: Integer;
  cp: TChildProcess;
begin
  cmd := 'xeyes';
  if not InputQuery('Run X11 application', 'Command line of the X11 / graphical application to start:', cmd) then Exit;
  if Trim(cmd) = '' then Exit;
  gerr := nil;
  argv := nil;
  if not g_shell_parse_argv(PChar(cmd), @argc, @argv, @gerr) then
  begin
    MsgError('Invalid command line', ErrMsg(gerr));
    Exit;
  end;
  SetLength(args, argc);
  for i := 0 to argc - 1 do
    args[i] := AnsiString(argv[i]);
  g_strfreev(argv);
  cp := TChildProcess.Create;
  cp.OnExit := @X11Reaper.Exited;
  if not cp.Start(args, [], HomeDir, False, err) then
  begin
    cp.Free;
    MsgError('Unable to start "' + cmd + '"', err);
  end;
end;
procedure CbAbout(item: Pointer; data: gpointer); cdecl; begin MainWin.ShowAbout; end;
procedure CbMacrosMenu(item: Pointer; data: gpointer); cdecl;
begin
  DestroyChildren(data);
  if Assigned(BuildMacrosMenuProc) then BuildMacrosMenuProc(data);
  gtk_widget_show_all(data);
end;
procedure CbShortcuts(item: Pointer; data: gpointer); cdecl; begin MainWin.ShowShortcuts; end;
procedure CbWebsite(item: Pointer; data: gpointer); cdecl;
begin
  OpenPath(AppDir + '/README.md');
end;

{ toolbar callbacks }
procedure TbSession(b: Pointer; data: gpointer); cdecl; begin MainWin.NewSessionDialog; end;
procedure TbMenu(b: Pointer; data: gpointer); cdecl;
begin
  MainWin.PopupToolbarMenu(b, PtrInt(data));
end;
procedure TbMultiExec(b: Pointer; data: gpointer); cdecl;
begin
  if MainWin.FMultiExecGuard then Exit;
  MainWin.SetMultiExec(gtk_toggle_button_get_active(b));
end;
procedure TbTunnels(b: Pointer; data: gpointer); cdecl;
begin
  if Assigned(ShowTunnelsProc) then ShowTunnelsProc;
end;
procedure TbServers(b: Pointer; data: gpointer); cdecl;
begin
  if Assigned(ShowServersProc) then ShowServersProc;
end;
procedure TbPackages(b: Pointer; data: gpointer); cdecl;
begin
  if Assigned(ShowPackagesProc) then ShowPackagesProc;
end;
procedure TbSettings(b: Pointer; data: gpointer); cdecl;
begin
  if Assigned(ShowSettingsProc) then ShowSettingsProc;
end;
procedure TbExit(b: Pointer; data: gpointer); cdecl; begin MainWin.Quit; end;
procedure TbNewTab(b: Pointer; data: gpointer); cdecl; begin MainWin.NewLocalTerminal; end;

{ side strip }
procedure SideButtonClicked(b: Pointer; data: gpointer); cdecl;
var
  idx: Integer;
begin
  if MainWin.FSideGuard then Exit;
  idx := PtrInt(data);
  if MainWin.FSideCollapsed then
  begin
    MainWin.SetSidebarCollapsed(False);
    MainWin.ShowSidePage(idx);
  end
  else if CStr(gtk_stack_get_visible_child_name(MainWin.FSideStack)) = MainWin.FSidePages[idx] then
    MainWin.SetSidebarCollapsed(True)
  else
    MainWin.ShowSidePage(idx);
end;

procedure CollapseClicked(b: Pointer; data: gpointer); cdecl;
begin
  MainWin.SetSidebarCollapsed(not MainWin.FSideCollapsed);
end;

{ quick connect completion: saved sessions, recent connections,
  ~/.ssh/config hosts and ~/.ssh/known_hosts }
const
  QC_TEXT = 0;
  QC_DESC = 1;
  QC_SEARCH = 2;
  QC_KEY = 3;

function QuickMatch(completion: Pointer; key: PChar; iter: PGtkTreeIter; data: gpointer): gboolean; cdecl;
var
  p: PChar;
  hay, w: string;
begin
  p := nil;
  gtk_tree_model_get(data, iter, QC_SEARCH, @p, -1);
  hay := TakeStr(p);
  Result := Trim(CStr(key)) <> '';
  { every word typed must appear somewhere (name, address, folder...) }
  for w in SplitString(DelSpace1(LowerCase(Trim(CStr(key)))), ' ') do
    if (w <> '') and (Pos(w, hay) = 0) then Exit(False);
end;

function QuickMatchSelected(completion: Pointer; model: Pointer; iter: PGtkTreeIter; data: gpointer): gboolean; cdecl;
var
  p: PChar;
  key: string;
  s: TSession;
begin
  p := nil;
  gtk_tree_model_get(model, iter, QC_KEY, @p, -1);
  key := TakeStr(p);
  SetEntryText(gtk_entry_completion_get_entry(completion), '');
  if Copy(key, 1, 3) = 'id:' then
  begin
    s := Store.FindById(Copy(key, 4, MaxInt));
    if s <> nil then MainWin.OpenSession(s);
  end
  else if Copy(key, 1, 3) = 'qc:' then
    MainWin.QuickConnect(Copy(key, 4, MaxInt));
  Result := True;
end;

function QuickFocusIn(widget: Pointer; event: Pointer; data: gpointer): gboolean; cdecl;
begin
  MainWin.FillQuickCompletion;
  Result := False;
end;

{ quick connect }
procedure QuickChanged(entry: Pointer; data: gpointer); cdecl;
begin
  MainWin.FSessions.SetFilter(EntryText(entry));
end;

procedure QuickActivate(entry: Pointer; data: gpointer); cdecl;
var
  txt: string;
  s: TSession;
begin
  txt := Trim(EntryText(entry));
  if txt = '' then Exit;
  s := MainWin.FSessions.SingleMatch;
  if s <> nil then
    MainWin.OpenSession(s)
  else
    MainWin.QuickConnect(txt);
  SetEntryText(entry, '');
end;

function QuickKey(widget: Pointer; event: Pointer; data: gpointer): gboolean; cdecl;
begin
  Result := False;
  if EventKeyval(event) = GDK_KEY_Escape then
  begin
    SetEntryText(widget, '');
    Result := True;
  end;
end;

{ tab menu }
procedure TabMenuClose(item: Pointer; data: gpointer); cdecl;
begin
  MainWin.CloseTabLater(TTabPage(data));
end;
procedure TabMenuCloseOthers(item: Pointer; data: gpointer); cdecl;
var
  i: Integer;
  keep: TTabPage;
  lst: TList;
begin
  keep := TTabPage(data);
  lst := TList.Create;
  try
    for i := 0 to MainWin.FTabs.Count - 1 do
      if (TTabPage(MainWin.FTabs[i]) <> keep) and TTabPage(MainWin.FTabs[i]).Closable then
        lst.Add(MainWin.FTabs[i]);
    for i := 0 to lst.Count - 1 do
      if MainWin.HasTab(TTabPage(lst[i])) then
        MainWin.CloseTab(TTabPage(lst[i]));
  finally
    lst.Free;
  end;
end;
procedure TabMenuCloseRight(item: Pointer; data: gpointer); cdecl;
var
  i, me: Integer;
  nb: Pointer;
  lst: TList;
  t: TTabPage;
begin
  nb := MainWin.NotebookOf(TTabPage(data));
  if nb = nil then Exit;
  me := gtk_notebook_page_num(nb, TTabPage(data).Page);
  lst := TList.Create;
  try
    for i := me + 1 to gtk_notebook_get_n_pages(nb) - 1 do
    begin
      t := TTabPage(g_object_get_data(gtk_notebook_get_nth_page(nb, i), 'lxtab'));
      if (t <> nil) and t.Closable then lst.Add(t);
    end;
    for i := 0 to lst.Count - 1 do
      if MainWin.HasTab(TTabPage(lst[i])) then
        MainWin.CloseTab(TTabPage(lst[i]));
  finally
    lst.Free;
  end;
end;
procedure TabMenuDuplicate(item: Pointer; data: gpointer); cdecl;
begin MainWin.DuplicateTab(TTabPage(data)); end;
procedure TabMenuRename(item: Pointer; data: gpointer); cdecl;
begin MainWin.RenameTab(TTabPage(data)); end;
procedure TabMenuDetach(item: Pointer; data: gpointer); cdecl;
begin MainWin.DetachTab(TTabPage(data)); end;
procedure TabMenuRestart(item: Pointer; data: gpointer); cdecl;
begin TTabPage(data).Restart; end;
procedure TabMenuSave(item: Pointer; data: gpointer); cdecl;
var
  t: TTabPage;
  s: TSession;
begin
  t := TTabPage(data);
  if t.Session = nil then Exit;
  s := t.Session.Clone;
  s.Id := NewId;
  s.HasPassword := False;
  if s.Name = '' then s.Name := Store.UniqueName(t.Session.DisplayName);
  if EditSessionDialog(s, False) then
  begin
    Store.Add(s);
    Store.Save;
    MainWin.RefreshSessionTree;
  end
  else
    s.Free;
end;
procedure TabMenuEditSession(item: Pointer; data: gpointer); cdecl;
var
  t: TTabPage;
  s: TSession;
begin
  t := TTabPage(data);
  if t.Session = nil then Exit;
  s := Store.FindById(t.Session.Id);
  if s <> nil then MainWin.EditSession(s);
end;

{ split tiles }
procedure TileComboCb(combo: Pointer; data: gpointer); cdecl;
begin
  MainWin.TileComboChanged(PtrInt(data));
end;

{ "app.show-tab" action: a click on a desktop notification }
procedure ShowTabActionCb(action: Pointer; param: Pointer; data: gpointer); cdecl;
begin
  if (MainWin <> nil) and (param <> nil) then
    MainWin.ShowTabNumber(g_variant_get_int32(param));
end;

procedure TileCheckCb(b: Pointer; data: gpointer); cdecl;
begin
  MainWin.TileCheckToggled(PtrInt(data));
end;

procedure TileNewLocalCb(b: Pointer; data: gpointer); cdecl;
begin
  MainWin.NewTerminalInTile(PtrInt(data));
end;

procedure TileOpenSessionCb(b: Pointer; data: gpointer); cdecl;
begin
  MainWin.OpenSessionInTile(PtrInt(data), b);
end;

function ClearPendingTileCb(data: gpointer): gboolean; cdecl;
begin
  if MainWin <> nil then MainWin.FPendingTile := -1;
  Result := False;
end;

procedure TileMenuDone(menu: Pointer; data: gpointer); cdecl;
begin
  { the chosen session (if any) has been opened by now }
  g_idle_add(@ClearPendingTileCb, nil);
end;

procedure MultiExitClicked(b: Pointer; data: gpointer); cdecl;
begin
  MainWin.SetMultiExec(False);
end;

{ home }
procedure HomeStartLocal(b: Pointer; data: gpointer); cdecl; begin MainWin.NewLocalTerminal; end;
procedure HomeRecover(b: Pointer; data: gpointer); cdecl; begin MainWin.RecoverSessions; end;
procedure HomeImport(b: Pointer; data: gpointer); cdecl;
var
  menu: Pointer;
begin
  menu := gtk_menu_new;
  MainWin.BuildImportMenu(menu);
  PopupMenuBelow(menu, b);
end;
procedure HomePalette(b: Pointer; data: gpointer); cdecl; begin MainWin.ShowCommandPalette; end;
procedure HomeRecentActivated(list: Pointer; row: Pointer; data: gpointer); cdecl;
var
  key: string;
begin
  key := CStr(PChar(g_object_get_data(row, 'key')));
  if key <> '' then MainWin.OpenRecent(key);
end;
procedure HomeSearchActivate(entry: Pointer; data: gpointer); cdecl;
var
  txt: string;
  s: TSession;
begin
  txt := Trim(EntryText(entry));
  if txt = '' then Exit;
  MainWin.FSessions.SetFilter(txt);
  s := MainWin.FSessions.SingleMatch;
  if s <> nil then
    MainWin.OpenSession(s)
  else
    MainWin.QuickConnect(txt);
  MainWin.FSessions.SetFilter('');
  SetEntryText(entry, '');
end;

{ automated tests: text shown by a widget (labels inside boxes included) }
function WidgetText(W: Pointer): string;
var
  lst, it: PGList;
begin
  Result := '';
  if W = nil then Exit;
  if g_type_check_instance_is_a(W, gtk_label_get_type) then
    Exit(CStr(gtk_label_get_text(W)));
  if not g_type_check_instance_is_a(W, gtk_container_get_type) then Exit;
  lst := gtk_container_get_children(W);
  it := lst;
  while it <> nil do
  begin
    Result := Result + WidgetText(it^.data);
    it := it^.next;
  end;
  g_list_free(lst);
end;

{ automated tests: finds a visible button showing Text (mnemonic underscores ignored) }
function FindButton(W: Pointer; const Text: string): Pointer;
var
  lst, it: PGList;
begin
  Result := nil;
  if (W = nil) or not g_type_check_instance_is_a(W, gtk_container_get_type) then Exit;
  if g_type_check_instance_is_a(W, gtk_button_get_type) and gtk_widget_get_visible(W) and
    (StringReplace(WidgetText(W), '_', '', [rfReplaceAll]) = Text) then
    Exit(W);
  lst := gtk_container_get_children(W);
  it := lst;
  while (it <> nil) and (Result = nil) do
  begin
    Result := FindButton(it^.data, Text);
    it := it^.next;
  end;
  g_list_free(lst);
end;

{ automated tests: notebooks inside W (deepest last) }
procedure FindNotebooks(W: Pointer; List: TList);
var
  lst, it: PGList;
begin
  if (W = nil) or not g_type_check_instance_is_a(W, gtk_container_get_type) then Exit;
  if g_type_check_instance_is_a(W, gtk_notebook_get_type) then List.Add(W);
  lst := gtk_container_get_children(W);
  it := lst;
  while it <> nil do
  begin
    FindNotebooks(it^.data, List);
    it := it^.next;
  end;
  g_list_free(lst);
end;

function TestTimerCb(data: gpointer): gboolean; cdecl;
begin
  Result := TMainWindow(data).TestStep;
end;

function FreeStringData(data: gpointer): gboolean; cdecl;
begin
  Result := False;
end;

procedure FreePCharNotify(data: gpointer); cdecl;
begin
  g_free(data);
end;

{ ---------------------------------------------------------------- command palette }

const
  PK_CONNECT = 0;
  PK_TAB = 1;
  PK_SESSION = 2;
  PK_MENU = 3;
  PK_ACTION = 4;
  PaletteRows = 14;

type
  TPaletteItem = class
    Kind: Integer;
    Title, Sub, Icon, Hay: string;
    Tab: TTabPage;
    SessId: string;
    MenuItem: Pointer;
    Action: string;
    Order: Integer;
    Score: Integer;
  end;

  { Ctrl+Shift+P: search box over the open tabs, the saved sessions and every
    command of the menus, run with the keyboard }
  TCommandPalette = class
  public
    Win, Entry, List, More: Pointer;
    Items: TList;
    Shown: TList;
    TempMenus: TList;
    Opened: Int64;
    Closing: Boolean;
    constructor Create;
    destructor Destroy; override;
    procedure AddItem(AKind: Integer; const ATitle, ASub, AIcon: string; AOrder: Integer; out It: TPaletteItem);
    procedure Collect;
    procedure Harvest(Menu: Pointer; const Path: string);
    procedure Refilter;
    procedure Move(Delta: Integer);
    procedure ActivateRow(Index: Integer);
    procedure CloseLater;
  end;

var
  Palette: TCommandPalette = nil;

function PaletteDestroyCb(data: gpointer): gboolean; cdecl;
begin
  if Palette <> nil then FreeAndNil(Palette);
  Result := False;
end;

procedure PaletteChanged(entry: Pointer; data: gpointer); cdecl;
begin
  if Palette <> nil then Palette.Refilter;
end;

function PaletteKey(widget: Pointer; event: Pointer; data: gpointer): gboolean; cdecl;
var
  kv: guint;
  row: Pointer;
begin
  Result := False;
  if Palette = nil then Exit;
  kv := EventKeyval(event);
  case kv of
    GDK_KEY_Escape:
      begin
        Palette.CloseLater;
        Result := True;
      end;
    GDK_KEY_Down:
      begin
        Palette.Move(1);
        Result := True;
      end;
    GDK_KEY_Up:
      begin
        Palette.Move(-1);
        Result := True;
      end;
    GDK_KEY_Return, GDK_KEY_KP_Enter:
      begin
        row := gtk_list_box_get_selected_row(Palette.List);
        if row <> nil then Palette.ActivateRow(gtk_list_box_row_get_index(row))
        else Palette.ActivateRow(0);
        Result := True;
      end;
  end;
end;

procedure PaletteRowActivated(list: Pointer; row: Pointer; data: gpointer); cdecl;
begin
  if Palette <> nil then Palette.ActivateRow(gtk_list_box_row_get_index(row));
end;

function PaletteFocusOut(widget: Pointer; event: Pointer; data: gpointer): gboolean; cdecl;
begin
  { a click outside closes the palette (not the focus changes of its opening) }
  if (Palette <> nil) and (g_get_monotonic_time - Palette.Opened > 400000) then
    Palette.CloseLater;
  Result := False;
end;

constructor TCommandPalette.Create;
var
  box, frame: Pointer;
begin
  inherited Create;
  Items := TList.Create;
  Shown := TList.Create;
  TempMenus := TList.Create;
  Win := gtk_window_new(GTK_WINDOW_TOPLEVEL);
  gtk_window_set_title(Win, 'Command palette');
  gtk_window_set_transient_for(Win, MainWin.Window);
  gtk_window_set_modal(Win, True);
  gtk_window_set_decorated(Win, False);
  gtk_window_set_position(Win, GTK_WIN_POS_CENTER_ON_PARENT);
  gtk_window_set_default_size(Win, 660, -1);
  AddClass(Win, 'lx-main');
  frame := gtk_event_box_new;
  AddClass(frame, 'lx-palette');
  box := gtk_box_new(GTK_ORIENTATION_VERTICAL, 6);
  SetMargins(box, 8);
  Entry := gtk_search_entry_new;
  gtk_entry_set_placeholder_text(Entry, 'Type a session, a tab, a command, or user@host to connect...');
  Connect(Entry, 'search-changed', @PaletteChanged, nil);
  Connect(Entry, 'key-press-event', @PaletteKey, nil);
  gtk_box_pack_start(box, Entry, False, False, 0);
  List := gtk_list_box_new;
  gtk_list_box_set_selection_mode(List, GTK_SELECTION_BROWSE);
  gtk_list_box_set_activate_on_single_click(List, True);
  Connect(List, 'row-activated', @PaletteRowActivated, nil);
  gtk_box_pack_start(box, List, False, False, 0);
  More := NewMarkupLabel('', 0);
  gtk_box_pack_start(box, More, False, False, 0);
  gtk_container_add(frame, box);
  gtk_container_add(Win, frame);
  Connect(Win, 'focus-out-event', @PaletteFocusOut, nil);
  Collect;
  Refilter;
  gtk_widget_show_all(Win);
  Opened := g_get_monotonic_time;
  gtk_widget_grab_focus(Entry);
end;

destructor TCommandPalette.Destroy;
var
  i: Integer;
begin
  if Win <> nil then gtk_widget_destroy(Win);
  for i := 0 to TempMenus.Count - 1 do
    gtk_widget_destroy(TempMenus[i]);
  for i := 0 to Items.Count - 1 do
    TObject(Items[i]).Free;
  Items.Free;
  Shown.Free;
  TempMenus.Free;
  inherited Destroy;
end;

procedure TCommandPalette.AddItem(AKind: Integer; const ATitle, ASub, AIcon: string; AOrder: Integer; out It: TPaletteItem);
begin
  It := TPaletteItem.Create;
  It.Kind := AKind;
  It.Title := ATitle;
  It.Sub := ASub;
  It.Icon := AIcon;
  It.Order := AOrder;
  It.Hay := LowerCase(ATitle + '  ' + ASub);
  Items.Add(It);
end;

procedure TCommandPalette.Harvest(Menu: Pointer; const Path: string);
var
  lst, it: PGList;
  w, sub: Pointer;
  txt: string;
  item: TPaletteItem;
begin
  if Menu = nil then Exit;
  lst := gtk_container_get_children(Menu);
  it := lst;
  while it <> nil do
  begin
    w := it^.data;
    it := it^.next;
    txt := Trim(WidgetText(w));
    if (txt = '') or not gtk_widget_get_sensitive(w) then Continue;
    if Pos('Command palette', txt) > 0 then Continue;
    sub := gtk_menu_item_get_submenu(w);
    if sub <> nil then
      Harvest(sub, IfThen(Path = '', txt, Path + ' › ' + txt))
    else
    begin
      AddItem(PK_MENU, txt, Path, CStr(PChar(g_object_get_data(w, 'lx-icon'))), 300 + Items.Count, item);
      item.MenuItem := w;
    end;
  end;
  g_list_free(lst);
end;

procedure TCommandPalette.Collect;
var
  i, j: Integer;
  t: TTabPage;
  s: TSession;
  item: TPaletteItem;
  lst, it: PGList;
  top, m: Pointer;
  txt, key: string;
  modes: array[0..4] of string = ('Single tab mode', '2 terminals: vertical split', '2 terminals: horizontal split',
    '4 terminals (2 x 2)', 'Mosaic: all terminals');
begin
  { open tabs }
  for i := 0 to MainWin.FTabs.Count - 1 do
  begin
    t := TTabPage(MainWin.FTabs[i]);
    if not t.Closable then Continue;
    AddItem(PK_TAB, t.FullTitle, 'Tab · ' + t.KindLabel, t.IconName, i, item);
    item.Tab := t;
  end;
  { saved sessions, the recent ones first }
  for i := 0 to Store.Sessions.Count - 1 do
  begin
    s := Store.Sessions[i];
    j := Settings.Recent.IndexOf('id:' + s.Id);
    if j < 0 then j := 100 + i;
    key := 'Session · ' + SessionKindNames[s.Kind] + '  ' + s.Target;
    if s.Folder <> '' then key := key + '  (' + s.Folder + ')';
    AddItem(PK_SESSION, s.DisplayName, key, s.IconName, j, item);
    item.SessId := s.Id;
  end;
  { commands of the toolbar that are not in the menus }
  for i := 0 to 4 do
  begin
    AddItem(PK_ACTION, modes[i], 'Split', 'preferences-desktop-virtual', 200 + i, item);
    item.Action := 'split' + IntToStr(i);
  end;
  AddItem(PK_ACTION, 'MultiExec mode (type in all terminals)', 'Toolbar', 'terminator', 210, item);
  item.Action := 'multiexec';
  AddItem(PK_ACTION, 'Servers (HTTP, FTP, TFTP, SSH...)', 'Toolbar', 'network-server', 211, item);
  item.Action := 'servers';
  AddItem(PK_ACTION, 'Tunneling (SSH port forwarding)', 'Toolbar', 'network-vpn', 212, item);
  item.Action := 'tunnels';
  AddItem(PK_ACTION, 'Packages (install additional tools)', 'Toolbar', 'system-software-install', 213, item);
  item.Action := 'packages';
  { every command of the menu bar }
  lst := gtk_container_get_children(MainWin.FMenuBar);
  it := lst;
  while it <> nil do
  begin
    top := it^.data;
    it := it^.next;
    txt := Trim(WidgetText(top));
    if txt = 'Macros' then
    begin
      { this menu is filled when it opens: use a private copy }
      if Assigned(BuildMacrosMenuProc) then
      begin
        m := gtk_menu_new;
        g_object_ref_sink(m);
        BuildMacrosMenuProc(m);
        TempMenus.Add(m);
        Harvest(m, 'Macros');
      end;
    end
    else
      Harvest(gtk_menu_item_get_submenu(top), txt);
  end;
  g_list_free(lst);
end;

function LooksLikeHost(const S: string): Boolean;
var
  w: string;
begin
  w := LowerCase(Trim(S));
  Result := False;
  if w = '' then Exit;
  if AnsiStartsStr('ssh ', w) or AnsiStartsStr('telnet ', w) or AnsiStartsStr('rdp ', w) or
    AnsiStartsStr('vnc ', w) or AnsiStartsStr('ftp ', w) or AnsiStartsStr('sftp ', w) or AnsiStartsStr('mosh ', w) then
    Exit(True);
  if Pos(' ', w) > 0 then Exit;
  Result := (Pos('@', w) > 0) or (Pos('.', w) > 0) or (Pos(':', w) > 0);
end;

function ComparePalette(A, B: Pointer): Integer;
begin
  Result := TPaletteItem(A).Score - TPaletteItem(B).Score;
  if Result = 0 then
    Result := CompareText(TPaletteItem(A).Title, TPaletteItem(B).Title);
end;

procedure TCommandPalette.Refilter;
var
  q: string;
  words: TStringArray;
  i, n, p, best: Integer;
  item: TPaletteItem;
  ok: Boolean;
  w: string;
  cands: TList;
  row, box, lbl: Pointer;
  conn: TPaletteItem;
  title: string;
begin
  DestroyChildren(List);
  Shown.Clear;
  q := Trim(EntryText(Entry));
  words := SplitString(DelSpace1(LowerCase(q)), ' ');
  cands := TList.Create;
  try
    for i := 0 to Items.Count - 1 do
    begin
      item := TPaletteItem(Items[i]);
      if item.Kind = PK_CONNECT then Continue;
      ok := True;
      best := 0;
      for w in words do
      begin
        if w = '' then Continue;
        p := Pos(w, item.Hay);
        if p = 0 then
        begin
          ok := False;
          Break;
        end;
        { matches at the start of the title come first }
        if p = 1 then Inc(best, 0)
        else if p <= Length(item.Title) then Inc(best, 20 + p)
        else Inc(best, 200 + p);
      end;
      if not ok then Continue;
      if q = '' then
        item.Score := item.Kind * 1000 + item.Order
      else
        item.Score := best * 10 + item.Kind * 15 + Min(item.Order, 400) div 40;
      cands.Add(item);
    end;
    cands.Sort(@ComparePalette);
    if LooksLikeHost(q) then
    begin
      AddItem(PK_CONNECT, 'Connect to ' + q, 'Quick connect (ssh, telnet, rdp, vnc, ftp, sftp, mosh)', 'network-connect', 0, conn);
      conn.Action := q;
      cands.Insert(0, conn);
    end;
    n := Min(cands.Count, PaletteRows);
    for i := 0 to n - 1 do
    begin
      item := TPaletteItem(cands[i]);
      Shown.Add(item);
      box := gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
      SetMargins(box, 3);
      if item.Icon <> '' then
        gtk_box_pack_start(box, NewIcon(item.Icon, 16), False, False, 0)
      else
        gtk_box_pack_start(box, NewIcon('system-run', 16), False, False, 0);
      title := MarkupEscape(item.Title);
      lbl := NewMarkupLabel('<b>' + title + '</b>', 0);
      gtk_label_set_ellipsize(lbl, PANGO_ELLIPSIZE_END);
      gtk_box_pack_start(box, lbl, True, True, 0);
      lbl := NewMarkupLabel('<span foreground="#888888" size="small">' + MarkupEscape(item.Sub) + '</span>', 1);
      gtk_label_set_ellipsize(lbl, PANGO_ELLIPSIZE_START);
      gtk_label_set_max_width_chars(lbl, 42);
      gtk_box_pack_end(box, lbl, False, False, 0);
      row := gtk_list_box_row_new;
      gtk_container_add(row, box);
      gtk_list_box_insert(List, row, -1);
    end;
    gtk_widget_show_all(List);
    if n > 0 then
      gtk_list_box_select_row(List, gtk_list_box_get_row_at_index(List, 0));
    if cands.Count > n then
      gtk_label_set_markup(More, PChar('<span foreground="#888888" size="small">' + IntToStr(cands.Count - n) +
        ' more results: type to narrow down.   ↑↓ select   Enter run   Esc close</span>'))
    else if n = 0 then
      gtk_label_set_markup(More, '<span foreground="#888888" size="small">No match.   Esc close</span>')
    else
      gtk_label_set_markup(More, '<span foreground="#888888" size="small">↑↓ select   Enter run   Esc close</span>');
    { shrink to the new list }
    gtk_window_resize(Win, 660, 1);
  finally
    cands.Free;
  end;
end;

procedure TCommandPalette.Move(Delta: Integer);
var
  row: Pointer;
  i: Integer;
begin
  if Shown.Count = 0 then Exit;
  row := gtk_list_box_get_selected_row(List);
  if row = nil then i := 0 else i := gtk_list_box_row_get_index(row) + Delta;
  if i < 0 then i := Shown.Count - 1;
  if i >= Shown.Count then i := 0;
  gtk_list_box_select_row(List, gtk_list_box_get_row_at_index(List, i));
end;

procedure TCommandPalette.CloseLater;
begin
  if Closing then Exit;
  Closing := True;
  gtk_widget_hide(Win);
  g_idle_add(@PaletteDestroyCb, nil);
end;

procedure TCommandPalette.ActivateRow(Index: Integer);
var
  item: TPaletteItem;
  s: TSession;
begin
  if Closing or (Index < 0) or (Index >= Shown.Count) then Exit;
  item := TPaletteItem(Shown[Index]);
  { the palette disappears first: the command may open a dialog }
  Closing := True;
  gtk_widget_hide(Win);
  case item.Kind of
    PK_CONNECT: MainWin.QuickConnect(item.Action);
    PK_TAB:
      if MainWin.HasTab(item.Tab) then MainWin.ActivateTab(item.Tab);
    PK_SESSION:
      begin
        s := Store.FindById(item.SessId);
        if s <> nil then MainWin.OpenSession(s);
      end;
    PK_MENU:
      gtk_menu_item_activate(item.MenuItem);
    PK_ACTION:
      if AnsiStartsStr('split', item.Action) then
      begin
        if MainWin.MultiExecActive then MainWin.SetMultiExec(False);
        MainWin.SetSplitMode(StrToIntDef(Copy(item.Action, 6, 2), 0));
      end
      else if item.Action = 'multiexec' then MainWin.SetMultiExec(not MainWin.MultiExecActive)
      else if item.Action = 'servers' then CbServers(nil, nil)
      else if item.Action = 'tunnels' then CbTunnels(nil, nil)
      else if item.Action = 'packages' then CbPackages(nil, nil);
  end;
  g_idle_add(@PaletteDestroyCb, nil);
end;

procedure CbPalette(item: Pointer; data: gpointer); cdecl;
begin
  MainWin.ShowCommandPalette;
end;

{ ---------------------------------------------------------------- THomeTab }

constructor THomeTab.Create(AOwner: TMainWindow);
var
  scroll, col, hb, tbox, logo, sub, b, cap, ph: Pointer;
begin
  inherited Create(nil);
  Owner := AOwner;
  Closable := False;
  IconName := 'lx-home';
  SetTitle('');
  Page := gtk_event_box_new;
  AddClass(Page, 'lx-home');
  col := gtk_box_new(GTK_ORIENTATION_VERTICAL, 12);
  gtk_widget_set_halign(col, GTK_ALIGN_CENTER);
  gtk_widget_set_margin_top(col, 30);
  gtk_widget_set_margin_bottom(col, 30);
  gtk_widget_set_size_request(col, 560, -1);

  hb := gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 16);
  gtk_widget_set_halign(hb, GTK_ALIGN_CENTER);
  logo := NewIcon('linxterm', 96);
  gtk_box_pack_start(hb, logo, False, False, 0);
  tbox := gtk_box_new(GTK_ORIENTATION_VERTICAL, 2);
  gtk_widget_set_valign(tbox, GTK_ALIGN_CENTER);
  cap := NewLabel(APP_NAME, 0);
  AddClass(cap, 'lx-home-title');
  gtk_box_pack_start(tbox, cap, False, False, 0);
  sub := NewLabel('Enhanced terminal for Linux with X11 forwarding, tabbed SSH client'#10 +
    'and network tools  -  version ' + APP_VERSION, 0);
  AddClass(sub, 'lx-home-sub');
  gtk_box_pack_start(tbox, sub, False, False, 0);
  gtk_box_pack_start(hb, tbox, False, False, 0);
  gtk_box_pack_start(col, hb, False, False, 10);

  hb := gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 20);
  gtk_widget_set_halign(hb, GTK_ALIGN_CENTER);
  b := NewIconButton('utilities-terminal', 'Start local terminal', 'Open a new tab with a local shell', 32);
  AddClass(b, 'lx-home-big');
  Connect(b, 'clicked', @HomeStartLocal, nil);
  gtk_box_pack_start(hb, b, False, False, 0);
  RestoreBtn := NewIconButton('document-revert', 'Recover previous sessions', 'Re-open the sessions of the last run', 32);
  AddClass(RestoreBtn, 'lx-home-big');
  Connect(RestoreBtn, 'clicked', @HomeRecover, nil);
  gtk_box_pack_start(hb, RestoreBtn, False, False, 0);
  gtk_box_pack_start(col, hb, False, False, 6);

  SearchEntry := gtk_search_entry_new;
  gtk_entry_set_placeholder_text(SearchEntry, 'Find existing session or server name...');
  gtk_widget_set_size_request(SearchEntry, 420, -1);
  gtk_widget_set_halign(SearchEntry, GTK_ALIGN_CENTER);
  Connect(SearchEntry, 'activate', @HomeSearchActivate, nil);
  gtk_box_pack_start(col, SearchEntry, False, False, 6);

  cap := NewLabel('Recent sessions', 0);
  AddClass(cap, 'lx-home-caption');
  gtk_box_pack_start(col, cap, False, False, 4);
  RecentList := gtk_list_box_new;
  gtk_list_box_set_selection_mode(RecentList, GTK_SELECTION_NONE);
  gtk_list_box_set_activate_on_single_click(RecentList, True);
  Connect(RecentList, 'row-activated', @HomeRecentActivated, nil);
  ph := NewMarkupLabel('<span foreground="#888888"><i>No recent session</i></span>', 0.5);
  SetMargins(ph, 8);
  gtk_widget_show(ph);
  gtk_list_box_set_placeholder(RecentList, ph);
  gtk_box_pack_start(col, RecentList, False, False, 0);

  hb := gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 12);
  gtk_widget_set_halign(hb, GTK_ALIGN_CENTER);
  b := NewIconButton('document-import', 'Import sessions...', 'Import your sessions from MobaXterm (.mxtsessions / MobaXterm.ini), ' +
    '~/.ssh/config, PuTTY or Remmina', 16);
  gtk_button_set_relief(b, GTK_RELIEF_NONE);
  Connect(b, 'clicked', @HomeImport, nil);
  gtk_box_pack_start(hb, b, False, False, 0);
  b := NewIconButton('system-search', 'Command palette (Ctrl+Shift+P)', 'Find a session, a tab or a command', 16);
  gtk_button_set_relief(b, GTK_RELIEF_NONE);
  Connect(b, 'clicked', @HomePalette, nil);
  gtk_box_pack_start(hb, b, False, False, 0);
  gtk_box_pack_start(col, hb, False, False, 8);

  scroll := gtk_scrolled_window_new(nil, nil);
  gtk_scrolled_window_set_policy(scroll, GTK_POLICY_NEVER, GTK_POLICY_AUTOMATIC);
  gtk_container_add(scroll, col);
  gtk_container_add(Page, scroll);
  RefreshRecent;
  gtk_widget_show_all(Page);
end;

procedure THomeTab.RefreshRecent;
var
  children, it: PGList;
  i, n: Integer;
  key, name, icon, target: string;
  s: TSession;
  row, box: Pointer;
  d: TJSONData;
  tmp: TSession;
begin
  children := gtk_container_get_children(RecentList);
  it := children;
  while it <> nil do
  begin
    gtk_widget_destroy(it^.data);
    it := it^.next;
  end;
  g_list_free(children);
  n := 0;
  for i := 0 to Settings.Recent.Count - 1 do
  begin
    key := Settings.Recent[i];
    name := '';
    icon := 'utilities-terminal';
    target := '';
    if Copy(key, 1, 3) = 'id:' then
    begin
      s := Store.FindById(Copy(key, 4, MaxInt));
      if s = nil then Continue;
      name := s.DisplayName;
      icon := s.IconName;
      target := SessionKindNames[s.Kind] + '  ' + s.Target;
    end
    else if Copy(key, 1, 5) = 'json:' then
    begin
      try
        d := GetJSON(Copy(key, 6, MaxInt));
      except
        d := nil;
      end;
      if (d = nil) or (d.JSONType <> jtObject) then
      begin
        d.Free;
        Continue;
      end;
      tmp := TSession.Create;
      tmp.FromJSON(TJSONObject(d));
      d.Free;
      name := tmp.DisplayName;
      icon := tmp.IconName;
      target := SessionKindNames[tmp.Kind] + '  ' + tmp.Target;
      tmp.Free;
    end
    else
      Continue;
    box := gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
    gtk_box_pack_start(box, NewIcon(icon, 20), False, False, 0);
    gtk_box_pack_start(box, NewMarkupLabel('<b>' + MarkupEscape(name) + '</b>   <span foreground="#888888">' +
      MarkupEscape(target) + '</span>', 0), True, True, 0);
    row := gtk_list_box_row_new;
    gtk_container_add(row, box);
    g_object_set_data_full(row, 'key', g_strdup(PChar(key)), @FreePCharNotify);
    gtk_list_box_insert(RecentList, row, -1);
    Inc(n);
    if n >= 10 then Break;
  end;
  gtk_widget_show_all(RecentList);
  gtk_widget_set_sensitive(RestoreBtn, Settings.OpenTabs.Count > 0);
end;

procedure THomeTab.FocusContent;
begin
  gtk_widget_grab_focus(SearchEntry);
end;

{ ---------------------------------------------------------------- TDetachedWindow }

constructor TDetachedWindow.Create(AOwner: TMainWindow);
begin
  inherited Create;
  Owner := AOwner;
  Window := gtk_window_new(GTK_WINDOW_TOPLEVEL);
  gtk_window_set_title(Window, PChar(APP_NAME));
  gtk_window_set_default_size(Window, 900, 600);
  gtk_window_set_icon(Window, IconPixbuf('linxterm', 64));
  AddClass(Window, 'lx-main');
  Notebook := gtk_notebook_new;
  Owner.SetupNotebook(Notebook);
  Connect(Notebook, 'page-removed', @DetachedPageRemovedCb, Self);
  Connect(Window, 'delete-event', @DetachedDeleteCb, Self);
  gtk_container_add(Window, Notebook);
  gtk_widget_show_all(Window);
  Owner.FDetached.Add(Self);
end;

{ ---------------------------------------------------------------- TMainWindow }

constructor TMainWindow.Create(AApp: Pointer);
var
  vbox, act, vt: Pointer;
begin
  inherited Create;
  MainWin := Self;
  App := Self;
  FApp := AApp;
  FTabs := TList.Create;
  FDetached := TList.Create;
  FSplitOnly := TList.Create;
  FPendingTile := -1;
  FSidePages[0] := 'sessions';
  FSidePages[1] := 'tools';
  FSidePages[2] := 'macros';
  FSidePages[3] := 'sftp';
  InstallTermprops;
  Window := gtk_application_window_new(FApp);
  MainWindowWidget := Window;
  vt := g_variant_type_new('i');
  act := g_simple_action_new('show-tab', vt);
  g_variant_type_free(vt);
  Connect(act, 'activate', @ShowTabActionCb, nil);
  g_action_map_add_action(FApp, act);
  g_object_unref(act);
  gtk_window_set_title(Window, PChar(APP_NAME));
  gtk_window_set_default_size(Window, Settings.WindowWidth, Settings.WindowHeight);
  gtk_window_set_icon(Window, IconPixbuf('linxterm', 128));
  gtk_window_set_default_icon(IconPixbuf('linxterm', 128));
  AddClass(Window, 'lx-main');
  FAccel := gtk_accel_group_new;
  gtk_window_add_accel_group(Window, FAccel);
  ApplySkin;

  vbox := gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
  gtk_container_add(Window, vbox);
  BuildMenuBar(vbox);
  BuildToolbar(vbox);
  BuildBody(vbox);
  BuildStatusBar(vbox);
  Connect(Window, 'delete-event', @WindowDeleteCb, Self);

  gtk_widget_show_all(Window);
  if Settings.Maximized then gtk_window_maximize(Window);
  ApplyVisibility;
  if Settings.SidebarPage = 'tools' then ShowSidePage(SIDE_TOOLS)
  else if Settings.SidebarPage = 'macros' then ShowSidePage(SIDE_MACROS)
  else ShowSidePage(SIDE_SESSIONS);
  UpdateStatusRight;
  SetStatus('Welcome to ' + APP_NAME + ' ' + APP_VERSION);
end;

destructor TMainWindow.Destroy;
begin
  FTabs.Free;
  FDetached.Free;
  FSplitOnly.Free;
  FTestCmds.Free;
  inherited Destroy;
end;

procedure TMainWindow.ApplySkin;
var
  dark: Boolean;
  err: PGError;
  css: string;
begin
  dark := Settings.Skin = 'dark';
  g_object_set(gtk_settings_get_default, 'gtk-theme-name', PChar('Adwaita'),
    'gtk-application-prefer-dark-theme', GBool(dark), nil);
  if FCss <> nil then
  begin
    gtk_style_context_remove_provider_for_screen(gdk_screen_get_default, FCss);
    g_object_unref(FCss);
  end;
  FCss := gtk_css_provider_new;
  if dark then css := DarkCss else css := LightCss;
  err := nil;
  gtk_css_provider_load_from_data(FCss, PChar(css), -1, @err);
  if err <> nil then
    WriteLn(StdErr, 'CSS error: ', ErrMsg(err));
  gtk_style_context_add_provider_for_screen(gdk_screen_get_default, FCss, GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
  { keep the two "Skin" radio items of the View menu consistent }
  if FMenuSkinLight <> nil then
  begin
    g_signal_handlers_block_by_func(FMenuSkinLight, @CbSkinLight, nil);
    g_signal_handlers_block_by_func(FMenuSkinDark, @CbSkinDark, nil);
    gtk_check_menu_item_set_active(FMenuSkinLight, not dark);
    gtk_check_menu_item_set_active(FMenuSkinDark, dark);
    g_signal_handlers_unblock_by_func(FMenuSkinLight, @CbSkinLight, nil);
    g_signal_handlers_unblock_by_func(FMenuSkinDark, @CbSkinDark, nil);
  end;
end;

procedure TMainWindow.AddAccel(Item: Pointer; Key: guint; Mods: guint);
begin
  gtk_widget_add_accelerator(Item, 'activate', FAccel, Key, Mods, GTK_ACCEL_VISIBLE);
end;

procedure TMainWindow.BuildMenuBar(VBox: Pointer);
var
  m, item, sub: Pointer;
  procedure TopMenu(const Caption: string);
  begin
    item := gtk_menu_item_new_with_mnemonic(PChar(Caption));
    m := gtk_menu_new;
    gtk_menu_set_accel_group(m, FAccel);
    gtk_menu_item_set_submenu(item, m);
    gtk_menu_shell_append(FMenuBar, item);
  end;
var
  ctrlshift: guint;
  light, dark: Pointer;
begin
  ctrlshift := GDK_CONTROL_MASK or GDK_SHIFT_MASK;
  FMenuBar := gtk_menu_bar_new;
  AddClass(FMenuBar, 'lx-menubar');

  TopMenu('_Terminal');
  AddAccel(NewImageMenuItem(m, 'Open new _tab', 'utilities-terminal', @CbNewLocal, nil), Ord('T'), ctrlshift);
  AddAccel(NewImageMenuItem(m, '_New session...', 'preferences-desktop-remote-desktop', @CbNewSession, nil), Ord('N'), ctrlshift);
  NewMenuSeparator(m);
  AddAccel(NewImageMenuItem(m, '_Copy', 'edit-copy', @CbCopy, nil), Ord('C'), ctrlshift);
  AddAccel(NewImageMenuItem(m, '_Paste', 'edit-paste', @CbPaste, nil), Ord('V'), ctrlshift);
  AddAccel(NewImageMenuItem(m, '_Find in terminal...', 'edit-find', @CbFind, nil), Ord('F'), ctrlshift);
  NewImageMenuItem(m, 'C_lear scrollback', 'edit-clear', @CbClear, nil);
  NewImageMenuItem(m, '_Reset terminal', 'view-refresh', @CbReset, nil);
  NewImageMenuItem(m, '_Save terminal text...', 'document-save', @CbSaveOutput, nil);
  NewImageMenuItem(m, 'Open the session _logs folder', 'folder', @CbLogFolder, nil);
  NewMenuSeparator(m);
  AddAccel(NewImageMenuItem(m, '_Duplicate tab', 'tab-new', @CbDuplicate, nil), Ord('D'), ctrlshift);
  NewImageMenuItem(m, 'Rena_me tab', 'document-edit', @CbRename, nil);
  NewImageMenuItem(m, 'Detac_h tab', 'window-new', @CbDetach, nil);
  AddAccel(NewImageMenuItem(m, 'Next tab', 'go-next', @CbNextTab, nil), GDK_KEY_Page_Down, GDK_CONTROL_MASK);
  AddAccel(NewImageMenuItem(m, 'Previous tab', 'go-previous', @CbPrevTab, nil), GDK_KEY_Page_Up, GDK_CONTROL_MASK);
  AddAccel(NewImageMenuItem(m, 'Clos_e tab', 'window-close', @CbCloseTab, nil), Ord('W'), ctrlshift);
  NewMenuSeparator(m);
  AddAccel(NewImageMenuItem(m, 'E_xit', 'system-shutdown', @CbQuit, nil), Ord('Q'), ctrlshift);

  TopMenu('_Sessions');
  NewImageMenuItem(m, '_New session', 'preferences-desktop-remote-desktop', @CbNewSession, nil);
  NewImageMenuItem(m, 'User _sessions', 'starred', @CbShowSessions, nil);
  NewImageMenuItem(m, '_Recover previous sessions', 'document-revert', @CbRecover, nil);
  NewMenuSeparator(m);
  sub := NewSubMenu(m, '_Import sessions', 'document-import');
  BuildImportMenu(sub);
  NewImageMenuItem(m, '_Export sessions to file...', 'document-export', @CbExport, nil);

  TopMenu('_View');
  FMenuMenubar := NewCheckMenuItem(m, 'Show _menu bar', Settings.ShowMenubar, @CbToggleMenubar, nil);
  FMenuToolbar := NewCheckMenuItem(m, 'Show _toolbar', Settings.ShowToolbar, @CbToggleToolbar, nil);
  FMenuSidebar := NewCheckMenuItem(m, 'Show _side panel', Settings.ShowSidebar, @CbToggleSidebar, nil);
  FMenuStatusbar := NewCheckMenuItem(m, 'Show status _bar', Settings.ShowStatusbar, @CbToggleStatusbar, nil);
  AddAccel(FMenuSidebar, Ord('B'), ctrlshift);
  NewMenuSeparator(m);
  AddAccel(NewImageMenuItem(m, '_Fullscreen', 'view-fullscreen', @CbFullscreen, nil), GDK_KEY_F11, 0);
  AddAccel(NewImageMenuItem(m, 'Command palette...', 'system-search', @CbPalette, nil), Ord('P'), ctrlshift);
  NewMenuSeparator(m);
  AddAccel(NewImageMenuItem(m, 'Increase font size', 'zoom-in', @CbZoomIn, nil), GDK_KEY_plus, GDK_CONTROL_MASK);
  AddAccel(NewImageMenuItem(m, 'Decrease font size', 'zoom-out', @CbZoomOut, nil), GDK_KEY_minus, GDK_CONTROL_MASK);
  NewImageMenuItem(m, 'Reset font size', 'zoom-original', @CbZoomReset, nil);
  NewMenuSeparator(m);
  sub := NewSubMenu(m, '_Skin', 'preferences-desktop-theme');
  light := gtk_check_menu_item_new_with_label('Light (MobaXterm classic)');
  gtk_check_menu_item_set_draw_as_radio(light, True);
  gtk_check_menu_item_set_active(light, Settings.Skin <> 'dark');
  Connect(light, 'toggled', @CbSkinLight, nil);
  gtk_menu_shell_append(sub, light);
  dark := gtk_check_menu_item_new_with_label('Dark');
  gtk_check_menu_item_set_draw_as_radio(dark, True);
  gtk_check_menu_item_set_active(dark, Settings.Skin = 'dark');
  Connect(dark, 'toggled', @CbSkinDark, nil);
  gtk_menu_shell_append(sub, dark);
  FMenuSkinLight := light;
  FMenuSkinDark := dark;

  TopMenu('_X server');
  NewImageMenuItem(m, 'X server _information', 'xorg', @CbXInfo, nil);
  NewImageMenuItem(m, '_Run X11 application...', 'system-run', @CbRunX11, nil);
  NewCheckMenuItem(m, 'Enable X11-forwarding for new SSH sessions', Settings.X11Default, @CbX11Default, nil);

  TopMenu('T_ools');
  if Assigned(BuildToolsMenuProc) then BuildToolsMenuProc(m);

  TopMenu('_Games');
  if Assigned(BuildGamesMenuProc) then BuildGamesMenuProc(m);

  TopMenu('S_ettings');
  NewImageMenuItem(m, '_Configuration', 'preferences-system', @CbSettings, nil);
  NewImageMenuItem(m, '_Passwords management', 'dialog-password', @CbPasswords, nil);
  NewImageMenuItem(m, '_Keyboard shortcuts', 'preferences-desktop-keyboard-shortcuts', @CbShortcuts, nil);

  TopMenu('_Macros');
  { rebuilt every time it opens so that new macros appear }
  Connect(item, 'activate', @CbMacrosMenu, m);

  TopMenu('_Help');
  NewImageMenuItem(m, '_Keyboard shortcuts', 'preferences-desktop-keyboard-shortcuts', @CbShortcuts, nil);
  NewImageMenuItem(m, '_Documentation (README)', 'help-browser', @CbWebsite, nil);
  NewMenuSeparator(m);
  NewImageMenuItem(m, '_About ' + APP_NAME, 'help-about', @CbAbout, nil);

  gtk_box_pack_start(VBox, FMenuBar, False, False, 0);
end;

function TMainWindow.ToolbarButton(const Icon, Text, Tip: string; Cb: Pointer): Pointer;
var
  box, lbl: Pointer;
begin
  Result := gtk_button_new;
  gtk_button_set_relief(Result, GTK_RELIEF_NONE);
  gtk_widget_set_can_focus(Result, False);
  box := gtk_box_new(GTK_ORIENTATION_VERTICAL, 1);
  gtk_box_pack_start(box, NewIcon(Icon, 32), False, False, 0);
  lbl := gtk_label_new(PChar(Text));
  gtk_box_pack_start(box, lbl, False, False, 0);
  gtk_container_add(Result, box);
  gtk_widget_set_tooltip_text(Result, PChar(Tip));
  if Cb <> nil then
    Connect(Result, 'clicked', Cb, nil);
end;

procedure TMainWindow.BuildToolbar(VBox: Pointer);
var
  b, box, lbl: Pointer;
  procedure Add(W: Pointer);
  begin
    gtk_box_pack_start(FToolbar, W, False, False, 0);
  end;
begin
  FToolbar := gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0);
  AddClass(FToolbar, 'lx-toolbar');
  Add(ToolbarButton('preferences-desktop-remote-desktop', 'Session', 'Create a new session (SSH, telnet, RDP, VNC, ...)', @TbSession));
  Add(ToolbarButton('network-server', 'Servers', 'Start / stop network servers (HTTP, FTP, TFTP, SSH, ...)', @TbServers));
  b := ToolbarButton('applications-utilities', 'Tools', 'Network and system tools', nil);
  Connect(b, 'clicked', @TbMenu, Pointer(PtrInt(MENU_TOOLS)));
  Add(b);
  b := ToolbarButton('applications-games', 'Games', 'Have a break...', nil);
  Connect(b, 'clicked', @TbMenu, Pointer(PtrInt(MENU_GAMES)));
  Add(b);
  b := ToolbarButton('starred', 'Sessions', 'Saved sessions', nil);
  Connect(b, 'clicked', @TbMenu, Pointer(PtrInt(MENU_SESSIONS)));
  Add(b);
  b := ToolbarButton('preferences-desktop-display', 'View', 'Display options', nil);
  Connect(b, 'clicked', @TbMenu, Pointer(PtrInt(MENU_VIEW)));
  Add(b);
  b := ToolbarButton('preferences-desktop-virtual', 'Split', 'Display several terminals at once', nil);
  Connect(b, 'clicked', @TbMenu, Pointer(PtrInt(MENU_SPLIT)));
  Add(b);
  { MultiExec is a toggle }
  FMultiExecBtn := gtk_toggle_button_new;
  gtk_button_set_relief(FMultiExecBtn, GTK_RELIEF_NONE);
  gtk_widget_set_can_focus(FMultiExecBtn, False);
  box := gtk_box_new(GTK_ORIENTATION_VERTICAL, 1);
  gtk_box_pack_start(box, NewIcon('terminator', 32), False, False, 0);
  lbl := gtk_label_new('MultiExec');
  gtk_box_pack_start(box, lbl, False, False, 0);
  gtk_container_add(FMultiExecBtn, box);
  gtk_widget_set_tooltip_text(FMultiExecBtn, 'Multi-execution mode: type commands in all terminals at once');
  Connect(FMultiExecBtn, 'toggled', @TbMultiExec, nil);
  Add(FMultiExecBtn);
  Add(ToolbarButton('network-vpn', 'Tunneling', 'Graphical SSH tunnels (port forwarding) manager', @TbTunnels));
  Add(ToolbarButton('system-software-install', 'Packages', 'Install additional tools', @TbPackages));
  Add(ToolbarButton('preferences-system', 'Settings', 'Configuration', @TbSettings));
  b := ToolbarButton('help-browser', 'Help', 'Help', nil);
  Connect(b, 'clicked', @TbMenu, Pointer(PtrInt(MENU_HELP)));
  Add(b);
  b := ToolbarButton('system-shutdown', 'Exit', 'Exit ' + APP_NAME, @TbExit);
  gtk_box_pack_end(FToolbar, b, False, False, 0);
  b := ToolbarButton('xorg', 'X server', 'X server', nil);
  Connect(b, 'clicked', @TbMenu, Pointer(PtrInt(MENU_XSERVER)));
  gtk_box_pack_end(FToolbar, b, False, False, 8);
  gtk_box_pack_start(VBox, FToolbar, False, False, 0);
end;

procedure TMainWindow.SetupNotebook(NB: Pointer);
begin
  AddClass(NB, 'lx-tabs');
  gtk_notebook_set_scrollable(NB, True);
  gtk_notebook_set_show_border(NB, False);
  gtk_notebook_set_group_name(NB, 'linxterm-tabs');
  gtk_notebook_popup_enable(NB);
  Connect(NB, 'switch-page', @SwitchPageCb, Self);
  Connect(NB, 'create-window', @CreateWindowCb, Self);
end;

procedure TMainWindow.BuildBody(VBox: Pointer);
var
  body, strip, panel, lbl, inner, b, mbar, mlabel, w: Pointer;
  i: Integer;
  names: array[0..3] of string = ('Sessions', 'Tools', 'Macros', 'Sftp');
  icons: array[0..3] of string = ('lx-star', 'lx-tools', 'lx-macro', 'lx-sftp');
  bx: Pointer;
begin
  body := gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
  AddClass(body, 'lx-body');
  FPaned := gtk_paned_new(GTK_ORIENTATION_HORIZONTAL);
  gtk_box_pack_start(body, FPaned, True, True, 0);

  { ---- left column ---- }
  FLeftBox := gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
  FQuickEntry := gtk_search_entry_new;
  gtk_entry_set_placeholder_text(FQuickEntry, 'Quick connect...');
  AddClass(FQuickEntry, 'lx-quick');
  gtk_widget_set_tooltip_text(FQuickEntry, 'Type a session name to filter, or user@host[:port] / "telnet host" / "rdp host" and press Enter');
  Connect(FQuickEntry, 'search-changed', @QuickChanged, nil);
  Connect(FQuickEntry, 'activate', @QuickActivate, nil);
  Connect(FQuickEntry, 'key-press-event', @QuickKey, nil);
  gtk_box_pack_start(FLeftBox, FQuickEntry, False, False, 0);
  AddQuickCompletion(FQuickEntry);

  inner := gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0);
  strip := gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
  AddClass(strip, 'lx-strip');
  FStrip := strip;
  FCollapseBtn := gtk_button_new_with_label('«');
  AddClass(FCollapseBtn, 'lx-collapse');
  gtk_widget_set_can_focus(FCollapseBtn, False);
  gtk_widget_set_tooltip_text(FCollapseBtn, 'Hide / show the side panel');
  Connect(FCollapseBtn, 'clicked', @CollapseClicked, nil);
  gtk_box_pack_start(strip, FCollapseBtn, False, False, 0);
  for i := 0 to 3 do
  begin
    b := gtk_toggle_button_new;
    gtk_widget_set_can_focus(b, False);
    bx := gtk_box_new(GTK_ORIENTATION_VERTICAL, 4);
    lbl := gtk_label_new(PChar(names[i]));
    gtk_label_set_angle(lbl, 90);
    gtk_box_pack_start(bx, lbl, False, False, 0);
    gtk_box_pack_start(bx, NewIcon(icons[i], 16), False, False, 0);
    gtk_container_add(b, bx);
    Connect(b, 'clicked', @SideButtonClicked, Pointer(PtrInt(i)));
    gtk_box_pack_start(strip, b, False, False, 0);
    FSideButtons[i] := b;
  end;
  gtk_box_pack_start(inner, strip, False, False, 0);

  FSideStack := gtk_stack_new;
  gtk_stack_set_transition_type(FSideStack, GTK_STACK_TRANSITION_TYPE_NONE);
  panel := gtk_event_box_new;
  AddClass(panel, 'lx-sidepanel');
  gtk_container_add(panel, FSideStack);
  FSessions := TSessionsPanel.Create;
  gtk_stack_add_named(FSideStack, FSessions.Widget, 'sessions');
  if Assigned(BuildToolsPanelProc) then w := BuildToolsPanelProc() else w := NewLabel('No tools', 0.5);
  gtk_stack_add_named(FSideStack, w, 'tools');
  if Assigned(BuildMacrosPanelProc) then w := BuildMacrosPanelProc() else w := NewLabel('No macros', 0.5);
  gtk_stack_add_named(FSideStack, w, 'macros');
  if Assigned(BuildSftpPanelProc) then w := BuildSftpPanelProc() else w := NewLabel('No SFTP', 0.5);
  gtk_stack_add_named(FSideStack, w, 'sftp');
  gtk_box_pack_start(inner, panel, True, True, 0);
  gtk_box_pack_start(FLeftBox, inner, True, True, 0);
  gtk_paned_pack1(FPaned, FLeftBox, False, False);

  { ---- right: notebook / split view ---- }
  FMainStack := gtk_stack_new;
  FNotebook := gtk_notebook_new;
  SetupNotebook(FNotebook);
  b := NewFlatIconButton('list-add', 'Open a new tab (local terminal)', 16);
  AddClass(b, 'lx-newtab');
  Connect(b, 'clicked', @TbNewTab, nil);
  gtk_widget_show_all(b);
  gtk_notebook_set_action_widget(FNotebook, b, GTK_PACK_END);
  gtk_stack_add_named(FMainStack, FNotebook, 'tabs');

  FSplitBox := gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
  FMultiBar := gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 10);
  mbar := FMultiBar;
  AddClass(mbar, 'lx-multibar');
  gtk_box_pack_start(mbar, NewIcon('terminator', 24), False, False, 0);
  mlabel := NewLabel('Multi-execution mode: commands are typed to all terminals (use Ctrl+Shift+Insert to paste)', 0);
  gtk_label_set_ellipsize(mlabel, PANGO_ELLIPSIZE_END);
  FMultiLabel := mlabel;
  gtk_box_pack_start(mbar, mlabel, True, True, 0);
  b := NewIconButton('dialog-cancel', 'Exit multi-execution mode', '', 16);
  Connect(b, 'clicked', @MultiExitClicked, nil);
  gtk_box_pack_end(mbar, b, False, False, 0);
  gtk_widget_set_no_show_all(FMultiBar, True);
  gtk_box_pack_start(FSplitBox, FMultiBar, False, False, 0);
  FSplitGrid := gtk_grid_new;
  gtk_grid_set_row_homogeneous(FSplitGrid, True);
  gtk_grid_set_column_homogeneous(FSplitGrid, True);
  gtk_grid_set_row_spacing(FSplitGrid, 3);
  gtk_grid_set_column_spacing(FSplitGrid, 3);
  gtk_box_pack_start(FSplitBox, FSplitGrid, True, True, 0);
  gtk_stack_add_named(FMainStack, FSplitBox, 'split');
  gtk_paned_pack2(FPaned, FMainStack, True, False);
  gtk_paned_set_position(FPaned, Settings.SidebarWidth);
  gtk_box_pack_start(VBox, body, True, True, 0);

  { home tab }
  FHome := THomeTab.Create(Self);
  AddTab(FHome, True);
  AddQuickCompletion(FHome.SearchEntry);
end;

procedure TMainWindow.BuildStatusBar(VBox: Pointer);
begin
  FStatusBar := gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
  AddClass(FStatusBar, 'lx-status');
  FStatusLabel := NewLabel('', 0);
  gtk_label_set_ellipsize(FStatusLabel, PANGO_ELLIPSIZE_END);
  gtk_box_pack_start(FStatusBar, FStatusLabel, True, True, 0);
  FStatusRight := NewLabel('', 1);
  gtk_box_pack_end(FStatusBar, FStatusRight, False, False, 0);
  gtk_box_pack_start(VBox, FStatusBar, False, False, 0);
end;

procedure TMainWindow.UpdateStatusRight;
var
  n, i: Integer;
  disp, txt: string;
begin
  if FStatusRight = nil then Exit;
  n := 0;
  for i := 0 to FTabs.Count - 1 do
    if TTabPage(FTabs[i]).Closable then Inc(n);
  disp := GetEnvironmentVariable('DISPLAY');
  txt := IntToStr(n) + ' session' + IfThen(n <> 1, 's', '');
  if FMultiExec then txt := 'MultiExec ON  |  ' + txt;
  if disp <> '' then
    txt := txt + '  |  X server: ' + disp
  else
    txt := txt + '  |  X server: not available';
  gtk_label_set_text(FStatusRight, PChar(txt));
end;

procedure TMainWindow.SetStatus(const Msg: string);
begin
  if FStatusLabel = nil then Exit;
  gtk_label_set_text(FStatusLabel, PChar(Msg));
end;

procedure TMainWindow.ApplyVisibility;
  procedure Sync(Item: Pointer; Cb: Pointer; V: Boolean);
  begin
    if Item = nil then Exit;
    g_signal_handlers_block_by_func(Item, Cb, nil);
    gtk_check_menu_item_set_active(Item, V);
    g_signal_handlers_unblock_by_func(Item, Cb, nil);
  end;
begin
  gtk_widget_set_visible(FMenuBar, Settings.ShowMenubar);
  gtk_widget_set_visible(FToolbar, Settings.ShowToolbar);
  gtk_widget_set_visible(FLeftBox, Settings.ShowSidebar);
  gtk_widget_set_visible(FStatusBar, Settings.ShowStatusbar);
  { the toolbar "View" menu and the keyboard shortcuts change the same settings }
  Sync(FMenuSidebar, @CbToggleSidebar, Settings.ShowSidebar);
  Sync(FMenuToolbar, @CbToggleToolbar, Settings.ShowToolbar);
  Sync(FMenuMenubar, @CbToggleMenubar, Settings.ShowMenubar);
  Sync(FMenuStatusbar, @CbToggleStatusbar, Settings.ShowStatusbar);
  if not Settings.ShowMenubar and not Settings.ShowToolbar then
    SetStatus('Menu bar and toolbar hidden: right-click a tab or use Ctrl+Shift+B / F11');
end;

procedure TMainWindow.ApplyTerminalSettings;
var
  i: Integer;
begin
  for i := 0 to FTabs.Count - 1 do
    if TTabPage(FTabs[i]) is TTerminalTab then
      TTerminalTab(FTabs[i]).ApplySettings;
end;

procedure TMainWindow.ShowSidePage(Index: Integer);
var
  i: Integer;
begin
  FSideGuard := True;
  for i := 0 to 3 do
    gtk_toggle_button_set_active(FSideButtons[i], i = Index);
  FSideGuard := False;
  gtk_stack_set_visible_child_name(FSideStack, PChar(FSidePages[Index]));
  if Index <> SIDE_SFTP then
    Settings.SidebarPage := FSidePages[Index];
  if (Index = SIDE_SFTP) and Assigned(SftpShowTabProc) then
    SftpShowTabProc(CurrentTab);
end;

procedure TMainWindow.SetSidebarCollapsed(V: Boolean);
var
  w: gint;
begin
  if V = FSideCollapsed then Exit;
  FSideCollapsed := V;
  if V then
  begin
    FSavedPanedPos := gtk_paned_get_position(FPaned);
    gtk_widget_hide(gtk_widget_get_parent(FSideStack));
    gtk_widget_hide(FQuickEntry);
    gtk_button_set_label(FCollapseBtn, '»');
    FSideGuard := True;
    gtk_toggle_button_set_active(FSideButtons[0], False);
    gtk_toggle_button_set_active(FSideButtons[1], False);
    gtk_toggle_button_set_active(FSideButtons[2], False);
    gtk_toggle_button_set_active(FSideButtons[3], False);
    FSideGuard := False;
    gtk_widget_get_preferred_width(FStrip, nil, @w);
    gtk_paned_set_position(FPaned, w);
  end
  else
  begin
    gtk_widget_show(gtk_widget_get_parent(FSideStack));
    gtk_widget_show(FQuickEntry);
    gtk_button_set_label(FCollapseBtn, '«');
    if FSavedPanedPos < 120 then FSavedPanedPos := Settings.SidebarWidth;
    gtk_paned_set_position(FPaned, FSavedPanedPos);
    ShowSidePage(Max(0, IndexStr(CStr(gtk_stack_get_visible_child_name(FSideStack)), FSidePages)));
  end;
end;

{ ---------------------------------------------------------------- tabs }

function TMainWindow.HasTab(Tab: TTabPage): Boolean;
begin
  Result := (Tab <> nil) and (FTabs.IndexOf(Tab) >= 0);
end;

function TMainWindow.NotebookOf(Tab: TTabPage): Pointer;
begin
  Result := nil;
  if (Tab = nil) or (Tab.Page = nil) then Exit;
  Result := gtk_widget_get_parent(Tab.Page);
end;

procedure TMainWindow.AddTab(Tab: TTabPage; Activate: Boolean);
var
  n, tile: Integer;
  prefer: TList;
begin
  if Tab.Closable then
  begin
    Inc(FTabCounter);
    Tab.Number := FTabCounter;
  end;
  Tab.BuildLabel;
  if (Tab.LabelText <> nil) and (Tab.Title = '') then
    gtk_widget_hide(Tab.LabelText);
  g_object_set_data(Tab.Page, 'lxtab', Tab);
  FTabs.Add(Tab);
  tile := -1;
  if (FSplitMode <> 0) and not FMultiExec then
  begin
    if (FPendingTile >= 0) and (FPendingTile <= High(FTiles)) and (Tab is TTerminalTab) then
      tile := FPendingTile
    else
      SetSplitMode(0);
  end;
  FPendingTile := -1;
  if (FSplitOnly.Count > 0) and (Tab is TTerminalTab) and (FMultiExec or (tile >= 0)) then
    FSplitOnly.Add(Tab);
  n := gtk_notebook_append_page(FNotebook, Tab.Page, Tab.LabelBox);
  gtk_notebook_set_tab_reorderable(FNotebook, Tab.Page, Tab.Closable);
  gtk_notebook_set_tab_detachable(FNotebook, Tab.Page, Tab.Closable);
  gtk_widget_show(Tab.Page);
  if Activate then
  begin
    gtk_notebook_set_current_page(FNotebook, n);
    g_idle_add(@IdleFocusCb, Tab);
  end;
  if tile >= 0 then
  begin
    prefer := TileTabs;
    try
      prefer[tile] := Tab;
      DetachSplitTiles;
      AttachSplitTiles(prefer);
    finally
      prefer.Free;
    end;
  end
  else if FMultiExec then RebuildSplit;
  UpdateStatusRight;
end;

procedure TMainWindow.CloseTabLater(Tab: TTabPage);
var
  ic: TIdleClose;
begin
  ic := TIdleClose.Create;
  ic.Win := Self;
  ic.Tab := Tab;
  g_idle_add(@IdleCloseCb, ic);
end;

procedure TMainWindow.CloseTab(Tab: TTabPage);
begin
  if not HasTab(Tab) or not Tab.Closable then Exit;
  if not Tab.ConfirmClose then Exit;
  RemoveTab(Tab);
end;

procedure TMainWindow.RemoveTab(Tab: TTabPage);
var
  nb: Pointer;
  idx: Integer;
  wasSplit, filterGone: Boolean;
  prefer: TList;
begin
  if not HasTab(Tab) then Exit;
  wasSplit := FSplitMode <> 0;
  filterGone := (FSplitOnly.Count > 0) and (FSplitOnly.IndexOf(Tab) >= 0) and (FSplitOnly.Count = 1);
  FSplitOnly.Remove(Tab);
  prefer := nil;
  if wasSplit then
  begin
    { the other terminals stay in their tiles }
    prefer := TileTabs;
    idx := prefer.IndexOf(Tab);
    if idx >= 0 then prefer[idx] := nil;
    DetachSplitTiles;
  end;
  Tab.Shutdown;
  if Assigned(SftpTabClosedProc) then SftpTabClosedProc(Tab);
  if FFocusedTab = Tab then FFocusedTab := nil;
  FTabs.Remove(Tab);
  nb := NotebookOf(Tab);
  if nb <> nil then
  begin
    idx := gtk_notebook_page_num(nb, Tab.Page);
    if idx >= 0 then gtk_notebook_remove_page(nb, idx);
  end;
  Tab.Free;
  if wasSplit then
  begin
    if (TerminalCount = 0) or filterGone then
    begin
      FMultiExec := False;
      SetSplitMode(0);
      SetMultiExec(False);
    end
    else
      AttachSplitTiles(prefer);
    prefer.Free;
  end;
  UpdateStatusRight;
  if CurrentTab <> nil then
  begin
    if Assigned(SftpShowTabProc) then SftpShowTabProc(CurrentTab);
    g_idle_add(@IdleFocusCb, CurrentTab);
  end;
end;

procedure TMainWindow.ActivateTab(Tab: TTabPage);
var
  nb: Pointer;
begin
  if not HasTab(Tab) then Exit;
  if FSplitMode <> 0 then
  begin
    Tab.FocusContent;
    Exit;
  end;
  nb := NotebookOf(Tab);
  if nb = nil then Exit;
  gtk_notebook_set_current_page(nb, gtk_notebook_page_num(nb, Tab.Page));
  gtk_window_present(gtk_widget_get_toplevel(nb));
  g_idle_add(@IdleFocusCb, Tab);
end;

function TMainWindow.CurrentTab: TTabPage;
var
  n: Integer;
begin
  if (FSplitMode <> 0) and (FFocusedTab <> nil) and HasTab(FFocusedTab) then
    Exit(FFocusedTab);
  Result := nil;
  if FNotebook = nil then Exit;
  n := gtk_notebook_get_current_page(FNotebook);
  if n < 0 then Exit;
  Result := TTabPage(g_object_get_data(gtk_notebook_get_nth_page(FNotebook, n), 'lxtab'));
end;

procedure TMainWindow.SwitchedPage(Page: Pointer);
var
  tab: TTabPage;
begin
  tab := TTabPage(g_object_get_data(Page, 'lxtab'));
  if tab = nil then Exit;
  FFocusedTab := tab;
  tab.SetActivity(False);
  tab.Activated;
  if Assigned(SftpShowTabProc) then SftpShowTabProc(tab);
  if tab is THomeTab then
    THomeTab(tab).RefreshRecent;
  if tab.Closable then
    gtk_window_set_title(Window, PChar(tab.FullTitle + ' - ' + APP_NAME))
  else
    gtk_window_set_title(Window, PChar(APP_NAME));
  g_idle_add(@IdleFocusCb, tab);
end;

procedure TMainWindow.TabChanged(Tab: TTabPage);
begin
  if not HasTab(Tab) then Exit;
  if (Tab = CurrentTab) and Assigned(SftpShowTabProc) then
    SftpShowTabProc(Tab);
  if (Tab is TTerminalTab) and TTerminalTab(Tab).MasterReady and Settings.SftpBrowserAuto
    and (Tab = CurrentTab) and (Tab.Session <> nil) and Tab.Session.SftpBrowser
    and not FSideCollapsed and Settings.ShowSidebar then
  begin
    if CStr(gtk_stack_get_visible_child_name(FSideStack)) <> 'sftp' then
      if not Boolean(PtrInt(g_object_get_data(Tab.Page, 'sftp-shown'))) then
      begin
        g_object_set_data(Tab.Page, 'sftp-shown', Pointer(1));
        ShowSidePage(SIDE_SFTP);
      end;
  end;
  UpdateStatusRight;
end;

procedure TMainWindow.TabFocused(Tab: TTabPage);
var
  i: Integer;
begin
  if not HasTab(Tab) then Exit;
  Tab.SetActivity(False);
  gtk_window_set_urgency_hint(gtk_widget_get_toplevel(Tab.Page), False);
  if FFocusedTab <> Tab then
  begin
    FFocusedTab := Tab;
    if Assigned(SftpShowTabProc) then SftpShowTabProc(Tab);
  end;
  for i := 0 to High(FTiles) do
    if FTiles[i].Frame <> nil then
    begin
      if FTiles[i].Tab = Tab then AddClass(FTiles[i].Frame, 'lx-tile-active')
      else RemoveClass(FTiles[i].Frame, 'lx-tile-active');
    end;
end;

procedure TMainWindow.ShowTabMenu(Tab: TTabPage; Event: Pointer);
var
  menu: Pointer;
begin
  menu := gtk_menu_new;
  if Tab.Closable then
  begin
    if Tab.CanDuplicate then
      NewImageMenuItem(menu, '_Duplicate tab', 'tab-new', @TabMenuDuplicate, Tab);
    NewImageMenuItem(menu, '_Rename tab', 'document-edit', @TabMenuRename, Tab);
    if Tab.CanRestart then
      NewImageMenuItem(menu, 'Re_start session', 'view-refresh', @TabMenuRestart, Tab);
    NewImageMenuItem(menu, 'De_tach tab', 'window-new', @TabMenuDetach, Tab);
    if Tab.Session <> nil then
    begin
      if Store.FindById(Tab.Session.Id) <> nil then
        NewImageMenuItem(menu, '_Edit session', 'document-properties', @TabMenuEditSession, Tab)
      else if Tab.Session.Kind <> skShell then
        NewImageMenuItem(menu, 'Save as _bookmarked session...', 'starred', @TabMenuSave, Tab);
    end;
    NewMenuSeparator(menu);
    NewImageMenuItem(menu, '_Close tab', 'window-close', @TabMenuClose, Tab);
  end;
  NewImageMenuItem(menu, 'Close _other tabs', 'edit-clear-all', @TabMenuCloseOthers, Tab);
  NewImageMenuItem(menu, 'Close tabs to the righ_t', 'go-last', @TabMenuCloseRight, Tab);
  PopupMenuAtPointer(menu, Tab.LabelBox, Event);
end;

procedure TMainWindow.DuplicateTab(Tab: TTabPage);
begin
  if (Tab = nil) or (Tab.Session = nil) or not Tab.CanDuplicate then Exit;
  OpenSession(Tab.Session);
end;

procedure TMainWindow.RenameTab(Tab: TTabPage);
var
  t: string;
begin
  if (Tab = nil) or not Tab.Closable then Exit;
  t := Tab.Title;
  if InputQuery('Rename tab', 'New name for this tab:', t) and (Trim(t) <> '') then
  begin
    Tab.UserTitle := True;
    Tab.SetTitle(Trim(t));
    if Tab = CurrentTab then
      gtk_window_set_title(Window, PChar(Tab.FullTitle + ' - ' + APP_NAME));
  end;
end;

procedure TMainWindow.DetachTab(Tab: TTabPage);
var
  dw: TDetachedWindow;
  nb: Pointer;
begin
  if (Tab = nil) or not Tab.Closable then Exit;
  if FSplitMode <> 0 then
  begin
    FMultiExec := False;
    SetMultiExec(False);
    SetSplitMode(0);
  end;
  nb := NotebookOf(Tab);
  if nb = nil then Exit;
  { the notebook owns the page and its label: keep both alive while moving }
  g_object_ref(Tab.Page);
  g_object_ref(Tab.LabelBox);
  gtk_notebook_remove_page(nb, gtk_notebook_page_num(nb, Tab.Page));
  dw := TDetachedWindow.Create(Self);
  gtk_notebook_append_page(dw.Notebook, Tab.Page, Tab.LabelBox);
  g_object_unref(Tab.LabelBox);
  g_object_unref(Tab.Page);
  gtk_notebook_set_tab_reorderable(dw.Notebook, Tab.Page, True);
  gtk_notebook_set_tab_detachable(dw.Notebook, Tab.Page, True);
  gtk_widget_show_all(dw.Window);
  g_idle_add(@IdleFocusCb, Tab);
end;

procedure TMainWindow.RefreshSessionTree;
begin
  FSessions.Rebuild;
  if FHome <> nil then FHome.RefreshRecent;
end;

procedure TMainWindow.EditSession(S: TSession);
var
  i: Integer;
  t: TTabPage;
begin
  if EditSessionDialog(S, False) then
  begin
    Store.Save;
    RefreshSessionTree;
    { the open tabs of this session show the new colour mark }
    for i := 0 to FTabs.Count - 1 do
    begin
      t := TTabPage(FTabs[i]);
      if (t.Session <> nil) and (t.Session.Id = S.Id) then
      begin
        t.Session.TabColor := S.TabColor;
        t.ApplyTabColor;
      end;
    end;
  end;
end;

{ ---------------------------------------------------------------- sessions }

procedure TMainWindow.OpenSession(S: TSession);
var
  tab: TTabPage;
  c: TSession;
  o: TJSONObject;
begin
  if S = nil then Exit;
  c := S.Clone;
  tab := nil;
  case c.Kind of
    skSSH, skTelnet, skSerial, skShell, skMosh:
      begin
        tab := TTerminalTab.Create(c);
        AddTab(tab, True);
        TTerminalTab(tab).Start;
      end;
    skRDP:
      if Assigned(CreateRdpTabProc) then tab := CreateRdpTabProc(c);
    skVNC:
      if Assigned(CreateVncTabProc) then tab := CreateVncTabProc(c);
    skFTP, skSFTP, skFile:
      if Assigned(CreateFileTabProc) then tab := CreateFileTabProc(c);
    skBrowser:
      if Assigned(CreateWebTabProc) then tab := CreateWebTabProc(c);
  end;
  if tab = nil then
  begin
    MsgError('This session type is not available', SessionKindNames[c.Kind]);
    c.Free;
    Exit;
  end;
  if not HasTab(tab) then
    AddTab(tab, True);
  { remember it in the recent list }
  if Store.FindById(S.Id) <> nil then
    Settings.AddRecent('id:' + S.Id)
  else if S.Kind <> skShell then
  begin
    o := S.ToJSON;
    try
      o.Delete('id');
      Settings.AddRecent('json:' + o.AsJSON);
    finally
      o.Free;
    end;
  end;
  Settings.Save;
  SetStatus(SessionKindNames[c.Kind] + ' session: ' + c.DisplayName);
end;

procedure TMainWindow.NewLocalTerminal;
var
  s: TSession;
begin
  s := TSession.Create(skShell);
  try
    OpenSession(s);
  finally
    s.Free;
  end;
end;

procedure TMainWindow.RunCommandTab(const ATitle, AIcon: string; const Argv: array of string);
var
  tab: TTerminalTab;
begin
  tab := TTerminalTab.CreateCommand(ATitle, AIcon, Argv);
  AddTab(tab, True);
  tab.Start;
end;

procedure TMainWindow.NewSessionDialog;
var
  s: TSession;
begin
  s := TSession.Create(skSSH);
  if EditSessionDialog(s, True) then
  begin
    if (s.Kind = skShell) and (s.Name = '') and (s.Command = '') and (s.StartDir = '') and (s.ShellPath = '') then
    begin
      { a plain local shell does not need to be bookmarked }
      OpenSession(s);
      s.Free;
      Exit;
    end;
    if s.Name = '' then
      s.Name := Store.UniqueName(s.DisplayName);
    Store.Add(s);
    Store.Save;
    RefreshSessionTree;
    OpenSession(s);
  end
  else
    s.Free;
end;

procedure TMainWindow.QuickConnect(const Text: string);
var
  parts: TStringArray;
  t, target, user, host: string;
  kind: TSessionKind;
  port, p, i: Integer;
  s: TSession;
begin
  t := Trim(Text);
  if t = '' then Exit;
  kind := skSSH;
  parts := SplitString(DelSpace1(t), ' ');
  i := 0;
  if (Length(parts) > 1) then
  begin
    if SameText(parts[0], 'ssh') then kind := skSSH
    else if SameText(parts[0], 'telnet') then kind := skTelnet
    else if SameText(parts[0], 'rdp') then kind := skRDP
    else if SameText(parts[0], 'vnc') then kind := skVNC
    else if SameText(parts[0], 'ftp') then kind := skFTP
    else if SameText(parts[0], 'sftp') then kind := skSFTP
    else if SameText(parts[0], 'mosh') then kind := skMosh
    else
    begin
      MsgWarning('Unknown quick connect command', 'Use: [ssh|telnet|rdp|vnc|ftp|sftp|mosh] [user@]host[:port]');
      Exit;
    end;
    i := 1;
  end;
  target := parts[i];
  port := SessionKindDefaultPorts[kind];
  if (i + 1 <= High(parts)) and (StrToIntDef(parts[i + 1], -1) > 0) then
    port := StrToInt(parts[i + 1]);
  user := '';
  p := Pos('@', target);
  if p > 0 then
  begin
    user := Copy(target, 1, p - 1);
    target := Copy(target, p + 1, MaxInt);
  end;
  host := target;
  p := LastDelimiter(':', target);
  if (p > 0) and (Pos(':', target) = p) and (StrToIntDef(Copy(target, p + 1, 10), -1) > 0) then
  begin
    host := Copy(target, 1, p - 1);
    port := StrToInt(Copy(target, p + 1, 10));
  end;
  if host = '' then Exit;
  s := TSession.Create(kind);
  try
    s.Host := host;
    s.User := user;
    s.Port := port;
    OpenSession(s);
  finally
    s.Free;
  end;
end;

procedure TMainWindow.OpenRecent(const Key: string);
var
  s: TSession;
  d: TJSONData;
begin
  if Copy(Key, 1, 3) = 'id:' then
  begin
    s := Store.FindById(Copy(Key, 4, MaxInt));
    if s <> nil then OpenSession(s);
  end
  else if Copy(Key, 1, 5) = 'json:' then
  begin
    try
      d := GetJSON(Copy(Key, 6, MaxInt));
    except
      d := nil;
    end;
    if (d <> nil) and (d.JSONType = jtObject) then
    begin
      s := TSession.Create;
      try
        s.FromJSON(TJSONObject(d));
        OpenSession(s);
      finally
        s.Free;
      end;
    end;
    d.Free;
  end;
end;

procedure TMainWindow.RecoverSessions;
var
  i: Integer;
  d: TJSONData;
  s, saved: TSession;
  lst: TStringList;
begin
  if Settings.OpenTabs.Count = 0 then
  begin
    MsgInfo('No previous session to recover', 'Sessions that are open when you exit are remembered here.');
    Exit;
  end;
  lst := TStringList.Create;
  try
    lst.Assign(Settings.OpenTabs);
    for i := 0 to lst.Count - 1 do
    begin
      try
        d := GetJSON(lst[i]);
      except
        d := nil;
      end;
      if (d <> nil) and (d.JSONType = jtObject) then
      begin
        s := TSession.Create;
        s.FromJSON(TJSONObject(d));
        saved := Store.FindById(s.Id);
        if saved <> nil then
          OpenSession(saved)
        else
          OpenSession(s);
        s.Free;
      end;
      d.Free;
    end;
  finally
    lst.Free;
  end;
end;

procedure TMainWindow.ImportSessions;
var
  fn, err: string;
  r: TImportResult;
begin
  if not ChooseOpenFile('Import sessions (MobaXterm .mxtsessions / MobaXterm.ini, ' + APP_NAME +
    ' .json, ssh_config, PuTTY, Remmina)', HomeDir, fn) then Exit;
  if ImportSessionsFile(fn, r, err) then
  begin
    Store.Save;
    RefreshSessionTree;
    MsgInfo('Sessions imported', DescribeImport(r));
  end
  else
    MsgError('Import failed', err);
end;

procedure TMainWindow.ImportFrom(const Source: string);
var
  r: TImportResult;
  ok: Boolean;
  what: string;
begin
  if Source = 'file' then
  begin
    ImportSessions;
    Exit;
  end;
  if Source = 'ssh' then
  begin
    what := DefaultSshConfig;
    ok := ImportSshConfig(what, r);
  end
  else if Source = 'putty' then
  begin
    what := DefaultPuttyDir;
    ok := ImportPutty(what, r);
  end
  else if Source = 'remmina' then
  begin
    what := DefaultRemminaDir;
    ok := ImportRemmina(what, r);
  end
  else
    Exit;
  if not ok then
  begin
    MsgError('Import failed', 'Nothing to import: ' + what + ' was not found.');
    Exit;
  end;
  Store.Save;
  RefreshSessionTree;
  MsgInfo('Sessions imported', DescribeImport(r));
end;

procedure TMainWindow.BuildImportMenu(Menu: Pointer);
  procedure Add(const Caption, Icon, Source: string; Available: Boolean);
  var
    item: Pointer;
  begin
    item := NewImageMenuItem(Menu, Caption, Icon, @CbImportSource, nil);
    g_object_set_data_full(item, 'source', g_strdup(PChar(Source)), @FreePCharNotify);
    gtk_widget_set_sensitive(item, Available);
  end;
begin
  Add('From a file (MobaXterm .mxtsessions / MobaXterm.ini, ' + APP_NAME + ' .json...)...', 'document-open', 'file', True);
  NewMenuSeparator(Menu);
  Add('From OpenSSH (~/.ssh/config)', 'utilities-terminal', 'ssh', FileExists(DefaultSshConfig));
  Add('From PuTTY (~/.putty/sessions)', 'putty', 'putty', DirectoryExists(DefaultPuttyDir));
  Add('From Remmina', 'org.remmina.Remmina', 'remmina', DirectoryExists(DefaultRemminaDir));
end;

procedure TMainWindow.ExportSessions;
var
  fn: string;
begin
  if not ChooseSaveFile('Export sessions', HomeDir, 'linxterm-sessions.json', fn) then Exit;
  if Store.ExportTo(fn) then
    MsgInfo('Sessions exported', IntToStr(Store.Sessions.Count) + ' session(s) exported to ' + fn +
      #10'Passwords are never exported.')
  else
    MsgError('Export failed', fn);
end;

{ ---------------------------------------------------------------- split / multiexec }

function TMainWindow.TerminalTabs: TList;
var
  i, n: Integer;
  t: TTabPage;
begin
  Result := TList.Create;
  { notebook order of the main window }
  for i := 0 to gtk_notebook_get_n_pages(FNotebook) - 1 do
  begin
    t := TTabPage(g_object_get_data(gtk_notebook_get_nth_page(FNotebook, i), 'lxtab'));
    if (t <> nil) and (t is TTerminalTab) then
      Result.Add(t);
  end;
  { put the current terminal first }
  t := CurrentTab;
  n := Result.IndexOf(t);
  if n > 0 then Result.Move(n, 0);
end;

function TMainWindow.TerminalCount: Integer;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to FTabs.Count - 1 do
    if TTabPage(FTabs[i]) is TTerminalTab then Inc(Result);
end;

procedure TMainWindow.DetachSplitTiles;
var
  i: Integer;
  t: TTerminalTab;
begin
  for i := 0 to High(FTiles) do
  begin
    t := FTiles[i].Tab;
    if (t <> nil) and HasTab(t) then
    begin
      gtk_container_remove(FTiles[i].Slot, t.Container);
      gtk_box_pack_start(t.Holder, t.Container, True, True, 0);
      gtk_widget_set_opacity(t.Container, 1.0);
      gtk_widget_show(t.Container);
    end;
    if FTiles[i].Frame <> nil then
      gtk_widget_destroy(FTiles[i].Frame);
  end;
  SetLength(FTiles, 0);
end;

procedure TMainWindow.AttachSplitTiles(Prefer: TList);
var
  terms: TList;
  n, cols, rows, i, j, k: Integer;
  frame, hdr, combo, slot: Pointer;
  t: TTerminalTab;
  assign: array of TTerminalTab;
  taken: Boolean;
  focus: TTabPage;
  chk: Pointer;
begin
  terms := SplitCandidates;
  try
    case FSplitMode of
      1, 2: n := 2;
      3: n := 4;
    else
      n := Max(1, terms.Count);
    end;
    if FMultiExec then n := Max(1, terms.Count);
    case FSplitMode of
      1: begin cols := 2; rows := 1; end;
      2: begin cols := 1; rows := 2; end;
      3: begin cols := 2; rows := 2; end;
    else
      begin
        cols := Ceil(Sqrt(n));
        rows := Ceil(n / cols);
      end;
    end;
    if FMultiExec then
    begin
      cols := Ceil(Sqrt(n));
      rows := Ceil(n / cols);
    end;
    { terminals keep their tile; the others fill the free tiles in tab order }
    SetLength(assign, n);
    for i := 0 to n - 1 do
    begin
      assign[i] := nil;
      if (Prefer <> nil) and (i < Prefer.Count) and (Prefer[i] <> nil) and (terms.IndexOf(Prefer[i]) >= 0) then
        assign[i] := TTerminalTab(Prefer[i]);
    end;
    j := 0;
    for i := 0 to n - 1 do
      if assign[i] = nil then
        while j < terms.Count do
        begin
          taken := False;
          for k := 0 to n - 1 do
            if assign[k] = TTerminalTab(terms[j]) then taken := True;
          Inc(j);
          if not taken then
          begin
            assign[i] := TTerminalTab(terms[j - 1]);
            Break;
          end;
        end;
    SetLength(FTiles, n);
    for i := 0 to n - 1 do
    begin
      frame := gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
      hdr := gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 4);
      AddClass(hdr, 'lx-tile-header');
      combo := gtk_combo_box_text_new;
      for j := 0 to terms.Count - 1 do
        gtk_combo_box_text_append_text(combo, PChar(TTabPage(terms[j]).FullTitle));
      gtk_box_pack_start(hdr, combo, False, False, 0);
      gtk_box_pack_start(frame, hdr, False, False, 0);
      slot := gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
      gtk_box_pack_start(frame, slot, True, True, 0);
      FTiles[i].Frame := frame;
      FTiles[i].Header := hdr;
      FTiles[i].Combo := combo;
      FTiles[i].Slot := slot;
      FTiles[i].Tab := nil;
      FTiles[i].Check := nil;
      if FMultiExec then
      begin
        chk := gtk_check_button_new_with_label('Receive input');
        gtk_widget_set_can_focus(chk, False);
        gtk_widget_set_tooltip_text(chk, 'MultiExec: this terminal receives (and sends) the keystrokes typed in the other terminals. ' +
          'Untick it to keep this terminal out.');
        gtk_box_pack_end(hdr, chk, False, False, 4);
        FTiles[i].Check := chk;
      end;
      t := assign[i];
      if t <> nil then
      begin
        t.SetActivity(False);
        FTiles[i].Tab := t;
        gtk_container_remove(t.Holder, t.Container);
        gtk_box_pack_start(slot, t.Container, True, True, 0);
        gtk_combo_box_set_active(combo, terms.IndexOf(t));
      end
      else
        gtk_box_pack_start(slot, EmptyTile(i), True, True, 0);
      Connect(combo, 'changed', @TileComboCb, Pointer(PtrInt(i)));
      if FTiles[i].Check <> nil then
        Connect(FTiles[i].Check, 'toggled', @TileCheckCb, Pointer(PtrInt(i)));
      { the last tile of an incomplete row takes the rest of the row }
      if i = n - 1 then
        gtk_grid_attach(FSplitGrid, frame, i mod cols, i div cols, cols - i mod cols, 1)
      else
        gtk_grid_attach(FSplitGrid, frame, i mod cols, i div cols, 1, 1);
    end;
    if rows = 0 then ;
    gtk_widget_show_all(FSplitGrid);
    SyncTileChecks;
    if FMultiExec then
    begin
      gtk_widget_set_no_show_all(FMultiBar, False);
      gtk_widget_show_all(FMultiBar);
    end
    else
      gtk_widget_hide(FMultiBar);
    gtk_stack_set_visible_child_name(FMainStack, 'split');
    { keep the focus on the terminal that had it }
    focus := nil;
    for i := 0 to High(FTiles) do
      if (FTiles[i].Tab <> nil) and (FTiles[i].Tab = FFocusedTab) then focus := FFocusedTab;
    for i := 0 to High(FTiles) do
      if (focus = nil) and (FTiles[i].Tab <> nil) then focus := FTiles[i].Tab;
    if focus <> nil then
    begin
      FFocusedTab := focus;
      g_idle_add(@IdleFocusCb, focus);
      TabFocused(focus);
    end;
  finally
    terms.Free;
  end;
end;

procedure TMainWindow.RebuildSplit;
var
  prefer: TList;
begin
  if FSplitMode = 0 then Exit;
  prefer := TileTabs;
  try
    DetachSplitTiles;
    AttachSplitTiles(prefer);
  finally
    prefer.Free;
  end;
end;

{ terminal shown by each tile (nil for an empty tile) }
function TMainWindow.TileTabs: TList;
var
  i: Integer;
begin
  Result := TList.Create;
  for i := 0 to High(FTiles) do
    Result.Add(FTiles[i].Tab);
end;

function TMainWindow.EmptyTile(Index: Integer): Pointer;
var
  box, hb, b: Pointer;
begin
  box := gtk_box_new(GTK_ORIENTATION_VERTICAL, 10);
  gtk_widget_set_valign(box, GTK_ALIGN_CENTER);
  gtk_widget_set_halign(box, GTK_ALIGN_CENTER);
  gtk_box_pack_start(box, NewIcon('utilities-terminal', 48), False, False, 0);
  gtk_box_pack_start(box, NewMarkupLabel('<span foreground="#888888">Empty tile</span>', 0.5), False, False, 0);
  hb := gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
  b := NewIconButton('utilities-terminal', 'Start local terminal', 'Open a local terminal in this tile', 16);
  Connect(b, 'clicked', @TileNewLocalCb, Pointer(PtrInt(Index)));
  gtk_box_pack_start(hb, b, False, False, 0);
  b := NewIconButton('starred', 'Open a session...', 'Open a saved session in this tile', 16);
  Connect(b, 'clicked', @TileOpenSessionCb, Pointer(PtrInt(Index)));
  gtk_box_pack_start(hb, b, False, False, 0);
  gtk_box_pack_start(box, hb, False, False, 0);
  Result := box;
end;

procedure TMainWindow.NewTerminalInTile(Index: Integer);
begin
  if (FSplitMode = 0) or (Index > High(FTiles)) then Exit;
  FPendingTile := Index;
  NewLocalTerminal;
  FPendingTile := -1;
end;

procedure TMainWindow.OpenSessionInTile(Index: Integer; Button: Pointer);
var
  menu, item: Pointer;
  i: Integer;
  s: TSession;
  n: Integer;
begin
  if (FSplitMode = 0) or (Index > High(FTiles)) then Exit;
  menu := gtk_menu_new;
  n := 0;
  for i := 0 to Store.Sessions.Count - 1 do
  begin
    s := Store.Sessions[i];
    if not (s.Kind in [skSSH, skTelnet, skSerial, skShell, skMosh]) then Continue;
    item := NewImageMenuItem(menu, IfThen(s.Folder <> '', s.Folder + ' / ', '') + s.DisplayName, s.IconName, nil, nil);
    g_object_set_data_full(item, 'sid', g_strdup(PChar(s.Id)), @FreePCharNotify);
    Connect(item, 'activate', @CbOpenSavedSession, nil);
    Inc(n);
  end;
  if n = 0 then
    gtk_widget_set_sensitive(NewMenuItem(menu, '(no saved terminal session)', nil, nil), False);
  FPendingTile := Index;
  Connect(menu, 'deactivate', @TileMenuDone, nil);
  PopupMenuBelow(menu, Button);
end;

procedure TMainWindow.TileComboChanged(Index: Integer);
var
  terms: TList;
  sel, other: Integer;
  wanted, cur: TTerminalTab;
  i: Integer;
begin
  if (Index < 0) or (Index > High(FTiles)) then Exit;
  sel := gtk_combo_box_get_active(FTiles[Index].Combo);
  terms := SplitCandidates;
  try
    if (sel < 0) or (sel >= terms.Count) then Exit;
    wanted := TTerminalTab(terms[sel]);
  finally
    terms.Free;
  end;
  cur := FTiles[Index].Tab;
  if wanted = cur then Exit;
  other := -1;
  for i := 0 to High(FTiles) do
    if FTiles[i].Tab = wanted then other := i;
  { remove what is currently shown in this tile }
  if cur <> nil then
    gtk_container_remove(FTiles[Index].Slot, cur.Container)
  else
    DestroyChildren(FTiles[Index].Slot);
  if other >= 0 then
  begin
    gtk_container_remove(FTiles[other].Slot, wanted.Container);
    FTiles[other].Tab := cur;
    if cur <> nil then
      gtk_box_pack_start(FTiles[other].Slot, cur.Container, True, True, 0)
    else
      gtk_box_pack_start(FTiles[other].Slot, EmptyTile(other), True, True, 0);
    gtk_widget_show_all(FTiles[other].Slot);
  end
  else if cur <> nil then
    gtk_box_pack_start(cur.Holder, cur.Container, True, True, 0);
  FTiles[Index].Tab := wanted;
  wanted.SetActivity(False);
  gtk_box_pack_start(FTiles[Index].Slot, wanted.Container, True, True, 0);
  gtk_widget_show_all(FTiles[Index].Slot);
  { refresh the combos without recursion }
  for i := 0 to High(FTiles) do
  begin
    g_signal_handlers_block_matched(FTiles[i].Combo, G_SIGNAL_MATCH_FUNC, 0, 0, nil, @TileComboCb, nil);
    terms := SplitCandidates;
    try
      gtk_combo_box_set_active(FTiles[i].Combo, terms.IndexOf(FTiles[i].Tab));
    finally
      terms.Free;
    end;
    g_signal_handlers_unblock_matched(FTiles[i].Combo, G_SIGNAL_MATCH_FUNC, 0, 0, nil, @TileComboCb, nil);
  end;
  if cur <> nil then gtk_widget_set_opacity(cur.Container, 1.0);
  SyncTileChecks;
  if HasTab(wanted) then
  begin
    FFocusedTab := wanted;
    g_idle_add(@IdleFocusCb, wanted);
  end;
end;

{ a terminal shown by a split tile: candidates of the split view }
function TMainWindow.SplitCandidates: TList;
var
  i: Integer;
begin
  Result := TerminalTabs;
  if FSplitOnly.Count = 0 then Exit;
  for i := Result.Count - 1 downto 0 do
    if FSplitOnly.IndexOf(Result[i]) < 0 then Result.Delete(i);
end;

{ "Receive input" boxes, dimmed terminals and header colour of the tiles }
procedure TMainWindow.SyncTileChecks;
var
  i: Integer;
  t: TTerminalTab;
begin
  for i := 0 to High(FTiles) do
  begin
    t := FTiles[i].Tab;
    if FTiles[i].Check <> nil then
    begin
      g_signal_handlers_block_matched(FTiles[i].Check, G_SIGNAL_MATCH_FUNC, 0, 0, nil, @TileCheckCb, nil);
      gtk_toggle_button_set_active(FTiles[i].Check, (t <> nil) and not t.MultiExecOff);
      g_signal_handlers_unblock_matched(FTiles[i].Check, G_SIGNAL_MATCH_FUNC, 0, 0, nil, @TileCheckCb, nil);
      gtk_widget_set_visible(FTiles[i].Check, t <> nil);
    end;
    if (t <> nil) and FMultiExec and t.MultiExecOff then
    begin
      AddClass(FTiles[i].Frame, 'lx-tile-off');
      gtk_widget_set_opacity(t.Container, 0.55);
    end
    else
    begin
      RemoveClass(FTiles[i].Frame, 'lx-tile-off');
      if t <> nil then gtk_widget_set_opacity(t.Container, 1.0);
    end;
  end;
  UpdateMultiLabel;
end;

procedure TMainWindow.NotifyTab(Tab: TTabPage; const Title, Body: string);
var
  n: Pointer;
begin
  if not Settings.Notifications or not HasTab(Tab) then Exit;
  n := g_notification_new(PChar(Title));
  g_notification_set_body(n, PChar(Body));
  g_notification_set_default_action_and_target_value(n, 'app.show-tab', g_variant_new_int32(Tab.Number));
  { one notification per tab: a new one replaces the previous one }
  g_application_send_notification(FApp, PChar('tab-' + IntToStr(Tab.Number)), n);
  g_object_unref(n);
end;

procedure TMainWindow.ShowTabNumber(N: Integer);
var
  i: Integer;
  t: TTabPage;
begin
  for i := 0 to FTabs.Count - 1 do
  begin
    t := TTabPage(FTabs[i]);
    if t.Number = N then
    begin
      ActivateTab(t);
      gtk_window_present(gtk_widget_get_toplevel(t.Page));
      Exit;
    end;
  end;
  gtk_window_present(Window);
end;

procedure TMainWindow.TileCheckToggled(Index: Integer);
var
  t: TTerminalTab;
begin
  if (Index < 0) or (Index > High(FTiles)) then Exit;
  t := FTiles[Index].Tab;
  if t = nil then Exit;
  t.MultiExecOff := not gtk_toggle_button_get_active(FTiles[Index].Check);
  SyncTileChecks;
  if HasTab(t) then g_idle_add(@IdleFocusCb, t);
end;

procedure TMainWindow.UpdateMultiLabel;
var
  i, n, on: Integer;
begin
  if (FMultiLabel = nil) or not FMultiExec then Exit;
  n := 0;
  on := 0;
  for i := 0 to High(FTiles) do
    if FTiles[i].Tab <> nil then
    begin
      Inc(n);
      if not FTiles[i].Tab.MultiExecOff then Inc(on);
    end;
  gtk_label_set_text(FMultiLabel, PChar('Multi-execution mode: what you type goes to ' + IntToStr(on) + ' of ' +
    IntToStr(n) + ' terminals (untick "Receive input" to leave one out, Ctrl+Shift+Insert pastes)'));
end;

procedure TMainWindow.AddQuickCompletion(Entry: Pointer);
var
  c, r: Pointer;
  types: array[0..3] of GType;
  i: Integer;
begin
  if FQuickStore = nil then
  begin
    for i := 0 to 3 do types[i] := G_TYPE_STRING;
    FQuickStore := gtk_list_store_newv(4, @types[0]);
  end;
  c := gtk_entry_completion_new;
  gtk_entry_completion_set_model(c, FQuickStore);
  gtk_entry_completion_set_text_column(c, QC_TEXT);
  r := gtk_cell_renderer_text_new;
  gtk_cell_layout_pack_start(c, r, False);
  gtk_cell_layout_add_attribute(c, r, 'markup', QC_DESC);
  gtk_entry_completion_set_minimum_key_length(c, 1);
  gtk_entry_completion_set_popup_set_width(c, False);
  gtk_entry_completion_set_match_func(c, @QuickMatch, FQuickStore, nil);
  Connect(c, 'match-selected', @QuickMatchSelected, nil);
  gtk_entry_set_completion(Entry, c);
  g_object_unref(c);
  Connect(Entry, 'focus-in-event', @QuickFocusIn, nil);
end;

procedure TMainWindow.FillQuickCompletion;
var
  it: TGtkTreeIter;
  seen, lst: TStringList;
  i: Integer;
  s, tmp: TSession;
  d: TJSONData;
  txt, name, desc: string;

  procedure Add(const AText, ADesc, ASearch, AKey: string);
  var
    markup: string;
  begin
    if (AText = '') or (seen.IndexOf(AText) >= 0) then Exit;
    seen.Add(AText);
    markup := '<span foreground="#888888" size="small">' + MarkupEscape(ADesc) + '</span>';
    gtk_list_store_append(FQuickStore, @it);
    gtk_list_store_set(FQuickStore, @it, QC_TEXT, PChar(AText), QC_DESC, PChar(markup),
      QC_SEARCH, PChar(LowerCase(AText + ' ' + ASearch)), QC_KEY, PChar(AKey), -1);
  end;

begin
  if FQuickStore = nil then Exit;
  gtk_list_store_clear(FQuickStore);
  seen := TStringList.Create;
  try
    seen.Sorted := True;
    { saved sessions }
    for i := 0 to Store.Sessions.Count - 1 do
    begin
      s := Store.Sessions[i];
      desc := SessionKindNames[s.Kind] + ' session   ' + s.Target;
      if s.Folder <> '' then desc := desc + '   (' + s.Folder + ')';
      Add(s.DisplayName, desc, s.Target + ' ' + s.Folder + ' ' + s.Comment, 'id:' + s.Id);
    end;
    { recent connections that are not saved sessions }
    for i := 0 to Settings.Recent.Count - 1 do
      if Copy(Settings.Recent[i], 1, 5) = 'json:' then
      begin
        try
          d := GetJSON(Copy(Settings.Recent[i], 6, MaxInt));
        except
          d := nil;
        end;
        if (d <> nil) and (d.JSONType = jtObject) then
        begin
          tmp := TSession.Create;
          tmp.FromJSON(TJSONObject(d));
          if tmp.Kind in [skSSH, skTelnet, skRDP, skVNC, skFTP, skSFTP, skMosh] then
          begin
            txt := tmp.Target;
            if tmp.Kind <> skSSH then txt := SessionKindIds[tmp.Kind] + ' ' + txt;
            Add(txt, 'Recent ' + SessionKindNames[tmp.Kind] + ' connection', '', 'qc:' + txt);
          end;
          tmp.Free;
        end;
        d.Free;
      end;
    { OpenSSH aliases }
    lst := ListSshConfigHosts(DefaultSshConfig);
    try
      for i := 0 to lst.Count - 1 do
      begin
        name := lst.Names[i];
        desc := lst.ValueFromIndex[i];
        Add(name, '~/.ssh/config' + IfThen(desc <> '', '   ' + desc, ''), desc, 'qc:ssh ' + name);
      end;
    finally
      lst.Free;
    end;
    { hosts already connected to }
    lst := ListKnownHosts(DefaultKnownHosts);
    try
      for i := 0 to lst.Count - 1 do
        Add(lst[i], 'Known host (~/.ssh/known_hosts)', '', 'qc:ssh ' + lst[i]);
    finally
      lst.Free;
    end;
  finally
    seen.Free;
  end;
end;

procedure TMainWindow.OpenFolder(const Folder: string; Layout: Integer);
var
  i: Integer;
  s: TSession;
  lst, before: TList;
  t: TTabPage;
begin
  lst := TList.Create;
  before := TList.Create;
  try
    for i := 0 to Store.Sessions.Count - 1 do
    begin
      s := Store.Sessions[i];
      if (s.Folder = Folder) or (Pos(Folder + '/', s.Folder) = 1) then
        if (Layout = 0) or (s.Kind in [skSSH, skTelnet, skSerial, skShell, skMosh]) then
          lst.Add(s);
    end;
    if lst.Count = 0 then
    begin
      if Layout = 0 then
        MsgInfo('Empty folder', 'There is no session in "' + Folder + '".')
      else
        MsgInfo('No terminal session', 'There is no terminal session (SSH, Telnet, Serial, Shell, Mosh) in "' + Folder + '".');
      Exit;
    end;
    if (lst.Count > 12) and not AskYesNo('Open ' + IntToStr(lst.Count) + ' sessions?',
      'Every session of "' + Folder + '" will be opened.') then Exit;
    if FMultiExec then SetMultiExec(False);
    if FSplitMode <> 0 then SetSplitMode(0);
    before.Assign(FTabs);
    for i := 0 to lst.Count - 1 do
      OpenSession(TSession(lst[i]));
    if Layout = 0 then Exit;
    FSplitOnly.Clear;
    for i := 0 to FTabs.Count - 1 do
    begin
      t := TTabPage(FTabs[i]);
      if (before.IndexOf(t) < 0) and (t is TTerminalTab) then FSplitOnly.Add(t);
    end;
    if FSplitOnly.Count = 0 then Exit;
    { only the terminals of the folder are tiled }
    FKeepFilter := True;
    try
      if Layout = 2 then SetMultiExec(True)
      else if FSplitOnly.Count = 2 then SetSplitMode(1)
      else if FSplitOnly.Count = 4 then SetSplitMode(3)
      else if FSplitOnly.Count > 1 then SetSplitMode(4);
    finally
      FKeepFilter := False;
    end;
    if FSplitMode = 0 then FSplitOnly.Clear;
    SetStatus(IntToStr(lst.Count) + ' session(s) of "' + Folder + '" opened');
  finally
    before.Free;
    lst.Free;
  end;
end;

procedure TMainWindow.SetSplitMode(Mode: Integer);
begin
  if not FKeepFilter then FSplitOnly.Clear;
  if (Mode = FSplitMode) and (Mode <> 0) then
  begin
    RebuildSplit;
    Exit;
  end;
  if FSplitMode <> 0 then DetachSplitTiles;
  FSplitMode := Mode;
  if Mode = 0 then
  begin
    gtk_widget_hide(FMultiBar);
    gtk_stack_set_visible_child_name(FMainStack, 'tabs');
    if CurrentTab <> nil then g_idle_add(@IdleFocusCb, CurrentTab);
  end
  else
  begin
    if TerminalCount = 0 then
    begin
      FSplitMode := 0;
      MsgInfo('No terminal to display', 'Open at least one terminal session first.');
      Exit;
    end;
    AttachSplitTiles;
  end;
end;

procedure TMainWindow.SetMultiExec(V: Boolean);
var
  i: Integer;
begin
  if not FKeepFilter then FSplitOnly.Clear;
  if V and (TerminalCount = 0) then
  begin
    MsgInfo('MultiExec', 'Open at least one terminal session first.');
    V := False;
  end;
  FMultiExecGuard := True;
  gtk_toggle_button_set_active(FMultiExecBtn, V);
  FMultiExecGuard := False;
  if V = FMultiExec then Exit;
  FMultiExec := V;
  if V then
  begin
    if FSplitMode <> 0 then DetachSplitTiles;
    FSplitMode := 4;
    AttachSplitTiles;
    SetStatus('MultiExec mode: keystrokes are sent to every terminal');
  end
  else
  begin
    SetSplitMode(0);
    { the next MultiExec starts with every terminal again }
    for i := 0 to FTabs.Count - 1 do
      if TTabPage(FTabs[i]) is TTerminalTab then TTerminalTab(FTabs[i]).MultiExecOff := False;
    SetStatus('MultiExec mode disabled');
  end;
  UpdateStatusRight;
end;

function TMainWindow.MultiExecActive: Boolean;
begin
  Result := FMultiExec;
end;

function TMainWindow.TabVisible(Tab: TTabPage): Boolean;
var
  i: Integer;
  nb: Pointer;
begin
  Result := False;
  if not HasTab(Tab) then Exit;
  for i := 0 to High(FTiles) do
    if FTiles[i].Tab = Tab then Exit(True);
  nb := NotebookOf(Tab);
  if nb = nil then Exit;
  { the main notebook is hidden behind the split tiles }
  if (nb = FNotebook) and (FSplitMode <> 0) then Exit;
  Result := gtk_notebook_get_current_page(nb) = gtk_notebook_page_num(nb, Tab.Page);
end;

procedure TMainWindow.TerminalInput(Sender: TTabPage; const Data: string);
var
  i: Integer;
  t: TTabPage;
begin
  if Assigned(MacroInputProc) then MacroInputProc(Sender, Data);
  if not FMultiExec then Exit;
  { what is typed in a terminal left out stays there }
  if (Sender is TTerminalTab) and TTerminalTab(Sender).MultiExecOff then Exit;
  for i := 0 to High(FTiles) do
  begin
    t := FTiles[i].Tab;
    if (t <> nil) and (t <> Sender) and not TTerminalTab(t).MultiExecOff then
      TTerminalTab(t).SendInput(Data);
  end;
end;

procedure TMainWindow.OpenEditor(const FileName: string);
begin
  if Assigned(OpenEditorProc) then OpenEditorProc(FileName);
end;

procedure TMainWindow.SettingsChanged;
  procedure SetCheck(Item: Pointer; Cb: Pointer; V: Boolean);
  begin
    if Item = nil then Exit;
    g_signal_handlers_block_by_func(Item, Cb, nil);
    gtk_check_menu_item_set_active(Item, V);
    g_signal_handlers_unblock_by_func(Item, Cb, nil);
  end;
var
  i: Integer;
begin
  ApplySkin;
  ApplyVisibility;
  ApplyTerminalSettings;
  SetCheck(FMenuMenubar, @CbToggleMenubar, Settings.ShowMenubar);
  SetCheck(FMenuToolbar, @CbToggleToolbar, Settings.ShowToolbar);
  SetCheck(FMenuStatusbar, @CbToggleStatusbar, Settings.ShowStatusbar);
  for i := 0 to FTabs.Count - 1 do
    if TTabPage(FTabs[i]) is TTerminalTab then
    begin
      TTerminalTab(FTabs[i]).SetMonitoring(Settings.RemoteMonitoring);
      { sessions without a choice of their own follow the configuration }
      if (TTabPage(FTabs[i]).Session <> nil) and (TTabPage(FTabs[i]).Session.Highlight = '') then
        TTerminalTab(FTabs[i]).SetHighlight(Settings.SyntaxHighlight, False);
    end;
  SetStatus('Configuration saved');
end;

{ ---------------------------------------------------------------- toolbar menus }

procedure TMainWindow.PopupToolbarMenu(Button: Pointer; Kind: Integer);
var
  menu, item, sub, light, dark: Pointer;
  i, j: Integer;
  s: TSession;
  folders: TStringList;
  modes: array[0..4] of string = ('Single tab mode', '2 terminals: vertical split', '2 terminals: horizontal split',
    '4 terminals (2 x 2)', 'Mosaic: all terminals');
  disp: string;
begin
  menu := gtk_menu_new;
  case Kind of
    MENU_TOOLS:
      if Assigned(BuildToolsMenuProc) then BuildToolsMenuProc(menu);
    MENU_GAMES:
      if Assigned(BuildGamesMenuProc) then BuildGamesMenuProc(menu);
    MENU_SESSIONS:
      begin
        NewImageMenuItem(menu, 'New session...', 'preferences-desktop-remote-desktop', @CbNewSession, nil);
        NewImageMenuItem(menu, 'Recover previous sessions', 'document-revert', @CbRecover, nil);
        sub := NewSubMenu(menu, 'Import sessions', 'document-import');
        BuildImportMenu(sub);
        NewMenuSeparator(menu);
        folders := TStringList.Create;
        try
          folders.Sorted := True;
          folders.Duplicates := dupIgnore;
          for i := 0 to Store.Sessions.Count - 1 do
            if Store.Sessions[i].Folder = '' then
            begin
              s := Store.Sessions[i];
              item := NewImageMenuItem(menu, s.DisplayName, s.IconName, nil, nil);
              g_object_set_data_full(item, 'sid', g_strdup(PChar(s.Id)), @FreePCharNotify);
              Connect(item, 'activate', @CbOpenSavedSession, nil);
            end
            else
              folders.Add(Store.Sessions[i].Folder);
          for j := 0 to folders.Count - 1 do
          begin
            sub := NewSubMenu(menu, folders[j], 'folder');
            item := NewImageMenuItem(sub, 'Open all', 'media-playback-start', @CbOpenFolder, nil);
            g_object_set_data_full(item, 'folder', g_strdup(PChar(folders[j])), @FreePCharNotify);
            item := NewImageMenuItem(sub, 'Open all in split view', 'preferences-desktop-virtual', @CbOpenFolder, nil);
            g_object_set_data_full(item, 'folder', g_strdup(PChar(folders[j])), @FreePCharNotify);
            g_object_set_data(item, 'layout', Pointer(1));
            item := NewImageMenuItem(sub, 'Open all in MultiExec', 'terminator', @CbOpenFolder, nil);
            g_object_set_data_full(item, 'folder', g_strdup(PChar(folders[j])), @FreePCharNotify);
            g_object_set_data(item, 'layout', Pointer(2));
            NewMenuSeparator(sub);
            for i := 0 to Store.Sessions.Count - 1 do
              if Store.Sessions[i].Folder = folders[j] then
              begin
                s := Store.Sessions[i];
                item := NewImageMenuItem(sub, s.DisplayName, s.IconName, nil, nil);
                g_object_set_data_full(item, 'sid', g_strdup(PChar(s.Id)), @FreePCharNotify);
                Connect(item, 'activate', @CbOpenSavedSession, nil);
              end;
          end;
        finally
          folders.Free;
        end;
        if Store.Sessions.Count = 0 then
          gtk_widget_set_sensitive(NewMenuItem(menu, '(no saved session)', nil, nil), False);
      end;
    MENU_VIEW:
      begin
        NewCheckMenuItem(menu, 'Show menu bar', Settings.ShowMenubar, @CbToggleMenubar, nil);
        NewCheckMenuItem(menu, 'Show toolbar', Settings.ShowToolbar, @CbToggleToolbar, nil);
        NewCheckMenuItem(menu, 'Show side panel', Settings.ShowSidebar, @CbToggleSidebar, nil);
        NewCheckMenuItem(menu, 'Show status bar', Settings.ShowStatusbar, @CbToggleStatusbar, nil);
        NewMenuSeparator(menu);
        NewImageMenuItem(menu, 'Fullscreen (F11)', 'view-fullscreen', @CbFullscreen, nil);
        NewMenuSeparator(menu);
        light := gtk_check_menu_item_new_with_label('Light skin');
        gtk_check_menu_item_set_draw_as_radio(light, True);
        gtk_check_menu_item_set_active(light, Settings.Skin <> 'dark');
        Connect(light, 'toggled', @CbSkinLight, nil);
        gtk_menu_shell_append(menu, light);
        dark := gtk_check_menu_item_new_with_label('Dark skin');
        gtk_check_menu_item_set_draw_as_radio(dark, True);
        gtk_check_menu_item_set_active(dark, Settings.Skin = 'dark');
        Connect(dark, 'toggled', @CbSkinDark, nil);
        gtk_menu_shell_append(menu, dark);
      end;
    MENU_SPLIT:
      begin
        for i := 0 to 4 do
        begin
          item := gtk_check_menu_item_new_with_label(PChar(modes[i]));
          gtk_check_menu_item_set_draw_as_radio(item, True);
          gtk_check_menu_item_set_active(item, (FSplitMode = i) and not FMultiExec);
          g_object_set_data(item, 'mode', Pointer(PtrInt(i)));
          Connect(item, 'toggled', @CbSplit, nil);
          gtk_menu_shell_append(menu, item);
        end;
        NewMenuSeparator(menu);
        NewImageMenuItem(menu, 'MultiExec mode', 'terminator', @CbMultiExecMenu, nil);
      end;
    MENU_HELP:
      begin
        NewImageMenuItem(menu, 'Keyboard shortcuts', 'preferences-desktop-keyboard-shortcuts', @CbShortcuts, nil);
        NewImageMenuItem(menu, 'Documentation (README)', 'help-browser', @CbWebsite, nil);
        NewMenuSeparator(menu);
        NewImageMenuItem(menu, 'About ' + APP_NAME, 'help-about', @CbAbout, nil);
      end;
    MENU_XSERVER:
      begin
        disp := GetEnvironmentVariable('DISPLAY');
        if disp <> '' then
          item := NewImageMenuItem(menu, 'X server is running (DISPLAY=' + disp + ')', 'emblem-ok', nil, nil)
        else
          item := NewImageMenuItem(menu, 'No X server available', 'dialog-error', nil, nil);
        gtk_widget_set_sensitive(item, False);
        NewMenuSeparator(menu);
        NewImageMenuItem(menu, 'X server information', 'xorg', @CbXInfo, nil);
        NewImageMenuItem(menu, 'Run X11 application...', 'system-run', @CbRunX11, nil);
        NewCheckMenuItem(menu, 'Enable X11-forwarding for new SSH sessions', Settings.X11Default, @CbX11Default, nil);
      end;
  end;
  PopupMenuBelow(menu, Button);
end;

procedure TMainWindow.ToggleFullscreen;
begin
  FFullscreen := not FFullscreen;
  if FFullscreen then gtk_window_fullscreen(Window) else gtk_window_unfullscreen(Window);
end;

procedure TMainWindow.ShowXServerInfo;
var
  disp, wl, typ, xhost, txt: string;
begin
  disp := GetEnvironmentVariable('DISPLAY');
  wl := GetEnvironmentVariable('WAYLAND_DISPLAY');
  typ := GetEnvironmentVariable('XDG_SESSION_TYPE');
  RunCapture(['xhost'], xhost);
  txt := 'Session type: ' + IfThen(typ = '', 'unknown', typ) + #10 +
    'DISPLAY: ' + IfThen(disp = '', '(not set)', disp) + #10 +
    'WAYLAND_DISPLAY: ' + IfThen(wl = '', '(not set)', wl) + #10#10;
  if (wl <> '') and (disp <> '') then
    txt := txt + 'Your desktop runs Wayland with the Xwayland X server: X11 applications ' +
      'and SSH X11-forwarding work out of the box.'#10#10
  else if disp <> '' then
    txt := txt + 'Your desktop runs a native X11 server.'#10#10;
  txt := txt + 'Remote X11 applications started from SSH sessions with "X11-Forwarding" enabled are ' +
    'displayed on this X server automatically.'#10#10'xhost:'#10 + Trim(xhost);
  MsgInfo('X server', txt);
end;

procedure TMainWindow.ShowAbout;
var
  d: Pointer;
begin
  d := gtk_about_dialog_new;
  gtk_window_set_transient_for(d, Window);
  gtk_window_set_modal(d, True);
  gtk_about_dialog_set_program_name(d, PChar(APP_NAME));
  gtk_about_dialog_set_version(d, PChar(APP_VERSION));
  gtk_about_dialog_set_logo(d, IconPixbuf('linxterm', 128));
  gtk_about_dialog_set_comments(d, PChar('Enhanced terminal for Linux: tabbed SSH client, X11 forwarding, ' +
    'RDP, VNC, SFTP / FTP browser, network tools and servers.'#10'Written in Object Pascal (Free Pascal) with GTK 3 and VTE.'#10 +
    'Interface inspired by MobaXterm.'));
  gtk_about_dialog_set_license_type(d, 3 { GTK_LICENSE_GPL_3_0 });
  gtk_dialog_run(d);
  gtk_widget_destroy(d);
end;

procedure TMainWindow.ShowCommandPalette;
begin
  if Palette <> nil then
  begin
    gtk_window_present(Palette.Win);
    Exit;
  end;
  Palette := TCommandPalette.Create;
end;

procedure TMainWindow.ShowShortcuts;
begin
  MsgInfo('Keyboard shortcuts',
    'Ctrl+Shift+T          Open a new tab (local terminal)'#10 +
    'Ctrl+Shift+N          New session'#10 +
    'Ctrl+Shift+W          Close tab'#10 +
    'Ctrl+Shift+D          Duplicate tab'#10 +
    'Ctrl+PageUp/Down      Previous / next tab'#10 +
    'Ctrl+Shift+C / V      Copy / paste'#10 +
    'Shift+Insert          Paste'#10 +
    'Ctrl+Shift+F          Find in terminal'#10 +
    'Ctrl + / - / 0        Font size'#10 +
    'Ctrl+Shift+B          Show / hide the side panel'#10 +
    'Ctrl+Shift+P          Command palette (sessions, tabs, commands)'#10 +
    'Ctrl + mouse wheel    Font size'#10 +
    'F11                   Fullscreen'#10 +
    'Ctrl+click            Open a link'#10 +
    'Right-click           Paste (Ctrl+right-click: context menu)'#10 +
    'Middle-click on tab   Close tab');
end;

procedure TMainWindow.SaveOpenTabs;
var
  i: Integer;
begin
  Settings.OpenTabs.Clear;
  for i := 0 to FTabs.Count - 1 do
    if TTabPage(FTabs[i]).Closable then
      TTabPage(FTabs[i]).SaveState(Settings.OpenTabs);
end;

procedure TMainWindow.Quit;
var
  n, i: Integer;
  w, h: gint;
  lst: TList;
begin
  if FQuitting then Exit;
  n := 0;
  for i := 0 to FTabs.Count - 1 do
    if TTabPage(FTabs[i]).Closable then Inc(n);
  if Settings.ConfirmExit and (n > 0) and (FTestCmds = nil) then
    if not AskYesNo('Do you want to quit ' + APP_NAME + '?',
      IntToStr(n) + ' session(s) still open. They can be recovered at next start with "Recover previous sessions".') then
      Exit;
  FQuitting := True;
  SaveOpenTabs;
  Settings.Maximized := gtk_window_is_maximized(Window);
  if not Settings.Maximized and not FFullscreen then
  begin
    gtk_window_get_size(Window, @w, @h);
    Settings.WindowWidth := w;
    Settings.WindowHeight := h;
  end;
  if not FSideCollapsed and Settings.ShowSidebar then
    Settings.SidebarWidth := gtk_paned_get_position(FPaned);
  Settings.Save;
  if FSplitMode <> 0 then DetachSplitTiles;
  lst := TList.Create;
  try
    lst.Assign(FTabs);
    for i := 0 to lst.Count - 1 do
      TTabPage(lst[i]).Shutdown;
  finally
    lst.Free;
  end;
  for i := 0 to High(ShutdownProcs) do
    ShutdownProcs[i]();
  gtk_widget_destroy(Window);
  g_application_quit(FApp);
end;

{ ---------------------------------------------------------------- command line / tests }

procedure TMainWindow.ProcessCommandLine(const Args: TStringArray);
var
  i: Integer;
  s: TSession;
begin
  i := 1;
  while i <= High(Args) do
  begin
    if (Args[i] = '--session') and (i < High(Args)) then
    begin
      s := Store.FindById(Args[i + 1]);
      if s = nil then s := Store.FindByName(Args[i + 1]);
      if s <> nil then OpenSession(s)
      else MsgError('Unknown session', Args[i + 1]);
      Inc(i);
    end
    else if (Args[i] = '--ssh') and (i < High(Args)) then
    begin
      QuickConnect('ssh ' + Args[i + 1]);
      Inc(i);
    end
    else if Args[i] = '--local' then
      NewLocalTerminal
    else if (Args[i] = '--edit') and (i < High(Args)) then
    begin
      OpenEditor(Args[i + 1]);
      Inc(i);
    end;
    Inc(i);
  end;
end;

procedure TMainWindow.StartTestScript(const Script: string);
var
  parts: TStringArray;
  p: string;
begin
  FTestCmds := TStringList.Create;
  parts := SplitString(Script, ';');
  for p in parts do
    if Trim(p) <> '' then FTestCmds.Add(Trim(p));
  FTestIndex := 0;
  g_timeout_add(300, @TestTimerCb, Self);
end;

function TMainWindow.TestStep: Boolean;
var
  cmd, arg: string;
  sp, i, n: Integer;
  lst, it: PGList;
  w: Pointer;
  s: TSession;
  t: TTabPage;
  handled: Boolean;
  sr: TSearchRec;
  ir: TImportResult;
  ierr: string;
  nbs: TList;
  qit: TGtkTreeIter;
  qp: PChar;
begin
  Result := False;
  if (FTestCmds = nil) or (FTestIndex >= FTestCmds.Count) then Exit;
  cmd := FTestCmds[FTestIndex];
  Inc(FTestIndex);
  sp := Pos(' ', cmd);
  if sp > 0 then
  begin
    arg := Trim(Copy(cmd, sp + 1, MaxInt));
    cmd := Copy(cmd, 1, sp - 1);
  end
  else
    arg := '';
  WriteLn('[test] ', cmd, ' ', arg);
  if cmd = 'wait' then
  begin
    g_timeout_add(StrToIntDef(arg, 500), @TestTimerCb, Self);
    Exit(False);
  end;
  { schedule the next step first: the command may run a modal dialog }
  if (FTestIndex < FTestCmds.Count) and (cmd <> 'quit') then
    g_timeout_add(250, @TestTimerCb, Self);
  if cmd = 'shot' then
  begin
    SaveWidgetPng(Window, arg);
    { also capture the other visible top-level windows (dialogs, tools) }
    lst := gtk_window_list_toplevels;
    it := lst;
    n := 0;
    while it <> nil do
    begin
      w := it^.data;
      if (w <> Window) and gtk_widget_get_visible(w) and gtk_widget_get_mapped(w) and
        (gtk_widget_get_allocated_width(w) > 50) then
      begin
        Inc(n);
        SaveWidgetPng(w, ChangeFileExt(arg, '') + '-w' + IntToStr(n) + '.png');
      end;
      it := it^.next;
    end;
    g_list_free(lst);
  end
  else if cmd = 'local' then NewLocalTerminal
  else if cmd = 'newsession' then NewSessionDialog
  else if cmd = 'quick' then QuickConnect(arg)
  else if cmd = 'open' then
  begin
    s := Store.FindByName(arg);
    if s <> nil then OpenSession(s) else WriteLn('[test] no session ', arg);
  end
  else if cmd = 'feed' then
  begin
    t := CurrentTab;
    if t is TTerminalTab then
      TTerminalTab(t).SendInput(StringReplace(StringReplace(arg, '\n', #13, [rfReplaceAll]), '\t', #9, [rfReplaceAll]));
  end
  else if cmd = 'type' then
  begin
    t := CurrentTab;
    { \n = Return, \xNN = any byte (e.g. \x03 = Ctrl+C) }
    w := nil;
    ierr := StringReplace(arg, '\n', #13, [rfReplaceAll]);
    i := Pos('\x', ierr);
    while (i > 0) and (i + 3 <= Length(ierr) + 0) do
    begin
      ierr := Copy(ierr, 1, i - 1) + Chr(StrToIntDef('$' + Copy(ierr, i + 2, 2), 0)) + Copy(ierr, i + 4, MaxInt);
      i := Pos('\x', ierr);
    end;
    if t is TTerminalTab then
      TTerminalTab(t).TypeInput(ierr);
  end
  else if cmd = 'respond' then
  begin
    lst := gtk_window_list_toplevels;
    it := lst;
    while it <> nil do
    begin
      w := it^.data;
      if (w <> Window) and gtk_widget_get_visible(w) and g_type_check_instance_is_a(w, gtk_dialog_get_type) then
        gtk_dialog_response(w, StrToIntDef(arg, GTK_RESPONSE_CANCEL));
      it := it^.next;
    end;
    g_list_free(lst);
  end
  else if cmd = 'closewin' then
  begin
    lst := gtk_window_list_toplevels;
    it := lst;
    while it <> nil do
    begin
      w := it^.data;
      if (w <> Window) and gtk_widget_get_visible(w) and (gtk_widget_get_allocated_width(w) > 50) then
        gtk_window_close(w);
      it := it^.next;
    end;
    g_list_free(lst);
  end
  else if cmd = 'side' then
  begin
    SetSidebarCollapsed(False);
    ShowSidePage(Max(0, IndexStr(arg, FSidePages)));
  end
  else if cmd = 'collapse' then SetSidebarCollapsed(True)
  else if cmd = 'split' then SetSplitMode(StrToIntDef(arg, 0))
  else if cmd = 'multiexec' then SetMultiExec(arg <> '0')
  else if cmd = 'menu' then PopupToolbarMenu(FToolbar, StrToIntDef(arg, MENU_TOOLS))
  else if cmd = 'settings' then CbSettings(nil, nil)
  else if cmd = 'servers' then CbServers(nil, nil)
  else if cmd = 'tunnels' then CbTunnels(nil, nil)
  else if cmd = 'packages' then CbPackages(nil, nil)
  else if cmd = 'tab' then
  begin
    i := StrToIntDef(arg, 0);
    if i < gtk_notebook_get_n_pages(FNotebook) then gtk_notebook_set_current_page(FNotebook, i);
  end
  else if cmd = 'closetab' then
  begin
    if (CurrentTab <> nil) and CurrentTab.Closable then RemoveTab(CurrentTab);
  end
  else if cmd = 'skin' then
  begin
    Settings.Skin := arg;
    ApplySkin;
  end
  else if cmd = 'quit' then
  begin
    FQuitting := False;
    Settings.ConfirmExit := False;
    Quit;
    Exit(False);
  end
  else if cmd = 'tool' then
  begin
    if Assigned(OpenToolProc) then OpenToolProc(arg);
  end
  else if cmd = 'game' then
  begin
    if Assigned(OpenGameProc) then OpenGameProc(arg);
  end
  else if cmd = 'edit' then OpenEditor(arg)
  else if cmd = 'detach' then
  begin
    if (CurrentTab <> nil) and CurrentTab.Closable then DetachTab(CurrentTab);
  end
  else if cmd = 'closeall' then
  begin
    while FTabs.Count > 1 do
      for i := FTabs.Count - 1 downto 0 do
        if TTabPage(FTabs[i]).Closable then
        begin
          RemoveTab(TTabPage(FTabs[i]));
          Break;
        end;
  end
  else if cmd = 'import' then
  begin
    { import <file> | import ssh|putty|remmina:<path> }
    if Pos(':', arg) > 0 then
    begin
      if Copy(arg, 1, 4) = 'ssh:' then ImportSshConfig(Copy(arg, 5, MaxInt), ir)
      else if Copy(arg, 1, 6) = 'putty:' then ImportPutty(Copy(arg, 7, MaxInt), ir)
      else if Copy(arg, 1, 8) = 'remmina:' then ImportRemmina(Copy(arg, 9, MaxInt), ir);
      Store.Save;
      RefreshSessionTree;
      WriteLn('[test] ', StringReplace(DescribeImport(ir), #10, ' | ', [rfReplaceAll]));
    end
    else if ImportSessionsFile(arg, ir, ierr) then
    begin
      Store.Save;
      RefreshSessionTree;
      WriteLn('[test] ', StringReplace(DescribeImport(ir), #10, ' | ', [rfReplaceAll]));
    end
    else
      WriteLn('[test] import failed: ', ierr);
  end
  else if cmd = 'expand' then FSessions.ExpandAll
  else if cmd = 'tilelocal' then NewTerminalInTile(StrToIntDef(arg, 0))
  else if cmd = 'qc' then
  begin
    { qc <text>: types in the quick connect entry and lists the completions }
    gtk_widget_grab_focus(FQuickEntry);
    FillQuickCompletion;
    SetEntryText(FQuickEntry, arg);
    if gtk_tree_model_get_iter_first(FQuickStore, @qit) then
      repeat
        if QuickMatch(nil, PChar(arg), @qit, FQuickStore) then
        begin
          qp := nil;
          gtk_tree_model_get(FQuickStore, @qit, QC_TEXT, @qp, -1);
          ierr := TakeStr(qp);
          qp := nil;
          gtk_tree_model_get(FQuickStore, @qit, QC_KEY, @qp, -1);
          WriteLn('[test] completion "', ierr, '" -> ', TakeStr(qp));
        end;
      until not gtk_tree_model_iter_next(FQuickStore, @qit);
  end
  else if cmd = 'openfolder' then
    { openfolder <layout> <folder> }
    OpenFolder(Copy(arg, Pos(' ', arg) + 1, MaxInt), StrToIntDef(Copy(arg, 1, Pos(' ', arg) - 1), 0))
  else if cmd = 'tilecheck' then
  begin
    { tilecheck <tile> <0|1> }
    i := StrToIntDef(ExtractWord(1, arg, [' ']), 0);
    if (i <= High(FTiles)) and (FTiles[i].Check <> nil) then
      gtk_toggle_button_set_active(FTiles[i].Check, ExtractWord(2, arg, [' ']) <> '0');
  end
  else if cmd = 'tiletype' then
  begin
    { tiletype <tile> <text>: types in the terminal of a tile }
    i := StrToIntDef(ExtractWord(1, arg, [' ']), 0);
    if (i <= High(FTiles)) and (FTiles[i].Tab <> nil) then
      FTiles[i].Tab.TypeInput(StringReplace(Copy(arg, Pos(' ', arg) + 1, MaxInt), '\n', #13, [rfReplaceAll]));
  end
  else if cmd = 'vtesize' then
  begin
    t := CurrentTab;
    if t is TTerminalTab then
      WriteLn('[test] vte cols=', vte_terminal_get_column_count(TTerminalTab(t).Term),
        ' rows=', vte_terminal_get_row_count(TTerminalTab(t).Term), ' relay=', TTerminalTab(t).Relayed,
        ' highlight=', TTerminalTab(t).Highlighting);
  end
  else if cmd = 'hl' then
  begin
    t := CurrentTab;
    if t is TTerminalTab then TTerminalTab(t).SetHighlight(arg <> '0');
  end
  else if cmd = 'dlgpage' then
  begin
    { dlgpage <notebook index> <page>: switches a notebook of the open dialog }
    lst := gtk_window_list_toplevels;
    it := lst;
    while it <> nil do
    begin
      w := it^.data;
      if (w <> Window) and gtk_widget_get_visible(w) and g_type_check_instance_is_a(w, gtk_dialog_get_type) then
      begin
        nbs := TList.Create;
        FindNotebooks(w, nbs);
        i := StrToIntDef(ExtractWord(1, arg, [' ']), 0);
        if i < nbs.Count then
          gtk_notebook_set_current_page(nbs[i], StrToIntDef(ExtractWord(2, arg, [' ']), 0));
        nbs.Free;
      end;
      it := it^.next;
    end;
    g_list_free(lst);
  end
  else if cmd = 'palette' then
  begin
    ShowCommandPalette;
    if (Palette <> nil) and (arg <> '') then SetEntryText(Palette.Entry, arg);
  end
  else if cmd = 'paletterun' then
  begin
    if Palette <> nil then Palette.ActivateRow(StrToIntDef(arg, 0));
  end
  else if cmd = 'clip' then
    gtk_clipboard_set_text(gtk_clipboard_get(GDK_SELECTION_CLIPBOARD),
      PChar(StringReplace(arg, '\n', #10, [rfReplaceAll])), -1)
  else if cmd = 'paste' then
  begin
    t := CurrentTab;
    if t is TTerminalTab then TTerminalTab(t).Paste;
  end
  else if cmd = 'recover' then RecoverSessions
  else if cmd = 'editsession' then
  begin
    s := Store.FindByName(arg);
    if s <> nil then EditSession(s);
  end
  else if cmd = 'restart' then
  begin
    if CurrentTab <> nil then CurrentTab.Restart;
  end
  else if cmd = 'click' then
  begin
    { click the button labelled <arg> in the most recent window showing one }
    w := nil;
    lst := gtk_window_list_toplevels;
    it := lst;
    while it <> nil do
    begin
      if gtk_widget_get_visible(it^.data) and (FindButton(it^.data, arg) <> nil) then
        w := FindButton(it^.data, arg);
      it := it^.next;
    end;
    g_list_free(lst);
    if w <> nil then gtk_button_clicked(w) else WriteLn('[test] no button ', arg);
  end
  else if cmd = 'state' then
  begin
    t := CurrentTab;
    if t is TTerminalTab then
      WriteLn('[test] state=', Ord(TTerminalTab(t).State), ' alive=', TTerminalTab(t).Alive,
        ' master=', TTerminalTab(t).MasterReady);
  end
  else if cmd = 'fds' then
  begin
    { number of open file descriptors (leak checks) }
    n := 0;
    if FindFirst('/proc/self/fd/*', faAnyFile, sr) = 0 then
    begin
      repeat
        Inc(n);
      until FindNext(sr) <> 0;
      FindClose(sr);
    end;
    WriteLn('[test] fds=', n);
  end
  else
  begin
    handled := False;
    for i := 0 to High(TestHooks) do
      if TestHooks[i](cmd, arg) then
      begin
        handled := True;
        Break;
      end;
    if not handled then
      WriteLn('[test] unknown command ', cmd);
  end;
  Result := False;
end;

{ ---------------------------------------------------------------- application }

procedure AppActivate(app: Pointer; data: gpointer); cdecl;
var
  script: string;
  i: Integer;
begin
  if MainWin <> nil then
  begin
    gtk_window_present(MainWin.Window);
    Exit;
  end;
  TMainWindow.Create(app);
  for i := 0 to High(StartupProcs) do
    StartupProcs[i]();
  if Settings.RestoreSessions and (Settings.OpenTabs.Count > 0) then
    MainWin.RecoverSessions
  else if Settings.StartLocalTerminal then
    MainWin.NewLocalTerminal;
  script := GetEnvironmentVariable('LINXTERM_TEST');
  if script <> '' then
    MainWin.StartTestScript(script);
end;

function AppCommandLine(app: Pointer; cmdline: Pointer; data: gpointer): gint; cdecl;
var
  argc: gint;
  argv: PPChar;
  args: TStringArray;
  i: Integer;
begin
  argv := g_application_command_line_get_arguments(cmdline, @argc);
  SetLength(args, argc);
  for i := 0 to argc - 1 do
    args[i] := AnsiString(argv[i]);
  g_strfreev(argv);
  AppActivate(app, nil);
  if MainWin <> nil then
    MainWin.ProcessCommandLine(args);
  Result := 0;
end;

procedure RunApplication;
var
  app: Pointer;
  flags: gint;
  argv: array of PChar;
  args: array of AnsiString;
  i: Integer;
begin
  { the Wayland app_id / X11 WM_CLASS must match the .desktop file name }
  g_set_prgname(APP_ID);
  g_set_application_name(PChar(APP_NAME));
  flags := G_APPLICATION_HANDLES_COMMAND_LINE;
  if GetEnvironmentVariable('LINXTERM_TEST') <> '' then
    flags := flags or G_APPLICATION_NON_UNIQUE;
  app := gtk_application_new(APP_ID, flags);
  Connect(app, 'activate', @AppActivate, nil);
  Connect(app, 'command-line', @AppCommandLine, nil);
  SetLength(args, ParamCount + 1);
  SetLength(argv, ParamCount + 2);
  for i := 0 to ParamCount do
  begin
    args[i] := ParamStr(i);
    argv[i] := PChar(args[i]);
  end;
  argv[ParamCount + 1] := nil;
  g_application_run(app, ParamCount + 1, @argv[0]);
  g_object_unref(app);
end;

end.

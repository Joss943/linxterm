{ LinXterm - base class for every tab of the main notebook and the
  application interface the tabs use to talk to the main window. }
unit lxtabs;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, lxgtk, lxutil, lxconfig;

type
  TTabPage = class
  private
    FTitle: string;
    FDisconnected: Boolean;
    FActivity: Boolean;
    procedure UpdateLabel;
  public
    Page: Pointer;          { root widget placed in the notebook }
    LabelBox: Pointer;      { event box used as tab label }
    LabelIcon: Pointer;
    LabelText: Pointer;
    LabelMark: Pointer;     { colour mark of the session (Bookmark settings) }
    CloseBtn: Pointer;
    Number: Integer;
    IconName: string;
    Closable: Boolean;
    Session: TSession;      { owned copy, may be nil }
    UserTitle: Boolean;     { title set by "Rename tab" }
    constructor Create(ASession: TSession);
    destructor Destroy; override;
    procedure BuildLabel;
    procedure SetTitle(const T: string);
    function Title: string;
    function FullTitle: string;
    procedure SetIcon(const Name: string);
    procedure SetDisconnected(V: Boolean);
    { new output in a tab that is not displayed }
    procedure SetActivity(V: Boolean);
    property HasActivity: Boolean read FActivity;
    procedure ApplyTabColor;
    function KindLabel: string; virtual;
    function ConfirmClose: Boolean; virtual;
    procedure Shutdown; virtual;
    procedure FocusContent; virtual;
    procedure Activated; virtual;
    function CanRestart: Boolean; virtual;
    procedure Restart; virtual;
    function CanDuplicate: Boolean; virtual;
    function IsTerminal: Boolean; virtual;
    procedure SaveState(List: TStrings); virtual;
  end;

  TAppIntf = class
  public
    procedure AddTab(Tab: TTabPage; Activate: Boolean); virtual; abstract;
    procedure CloseTab(Tab: TTabPage); virtual; abstract;
    procedure CloseTabLater(Tab: TTabPage); virtual; abstract;
    procedure ActivateTab(Tab: TTabPage); virtual; abstract;
    function CurrentTab: TTabPage; virtual; abstract;
    procedure OpenSession(S: TSession); virtual; abstract;
    procedure NewLocalTerminal; virtual; abstract;
    procedure RunCommandTab(const ATitle, AIcon: string; const Argv: array of string); virtual; abstract;
    procedure SetStatus(const Msg: string); virtual; abstract;
    procedure TabChanged(Tab: TTabPage); virtual; abstract;
    procedure TabFocused(Tab: TTabPage); virtual; abstract;
    procedure ShowTabMenu(Tab: TTabPage; Event: Pointer); virtual; abstract;
    procedure DuplicateTab(Tab: TTabPage); virtual; abstract;
    procedure RenameTab(Tab: TTabPage); virtual; abstract;
    procedure DetachTab(Tab: TTabPage); virtual; abstract;
    procedure RefreshSessionTree; virtual; abstract;
    procedure EditSession(S: TSession); virtual; abstract;
    function MultiExecActive: Boolean; virtual; abstract;
    procedure TerminalInput(Sender: TTabPage; const Data: string); virtual; abstract;
    procedure OpenEditor(const FileName: string); virtual; abstract;
    procedure SettingsChanged; virtual; abstract;
    { the tab is displayed (current tab of its window, or a split tile) }
    function TabVisible(Tab: TTabPage): Boolean; virtual; abstract;
    { opens every session of Folder (and its subfolders):
      Layout 0 = tabs, 1 = split view, 2 = MultiExec }
    procedure OpenFolder(const Folder: string; Layout: Integer); virtual; abstract;
    { desktop notification; clicking it shows Tab }
    procedure NotifyTab(Tab: TTabPage; const Title, Body: string); virtual; abstract;
  end;

  TTabFactory = function(S: TSession): TTabPage;

const
  TabColorCount = 8;
  TabColorIds: array[0..TabColorCount - 1] of string =
    ('', 'red', 'orange', 'yellow', 'green', 'blue', 'purple', 'gray');
  TabColorNames: array[0..TabColorCount - 1] of string =
    ('None', 'Red', 'Orange', 'Yellow', 'Green', 'Blue', 'Purple', 'Gray');
  TabColorValues: array[0..TabColorCount - 1] of string =
    ('', '#e53935', '#fb8c00', '#fdd835', '#43a047', '#1e88e5', '#8e24aa', '#78909c');

type
  TMenuBuilder = procedure(Menu: Pointer);
  TWidgetBuilder = function: Pointer;
  TTabNotify = procedure(Tab: TTabPage);
  TInputNotify = procedure(Tab: TTabPage; const Data: string);
  TSimpleProc = procedure;

var
  App: TAppIntf = nil;

  { feature registry: units register their entry points at initialization
    so that the main window does not depend on every feature unit }
  CreateFileTabProc: TTabFactory = nil;
  CreateVncTabProc: TTabFactory = nil;
  CreateRdpTabProc: TTabFactory = nil;
  CreateWebTabProc: TTabFactory = nil;
  BuildToolsMenuProc: TMenuBuilder = nil;
  BuildToolsPanelProc: TWidgetBuilder = nil;
  BuildGamesMenuProc: TMenuBuilder = nil;
  BuildMacrosMenuProc: TMenuBuilder = nil;
  BuildMacrosPanelProc: TWidgetBuilder = nil;
  MacroInputProc: TInputNotify = nil;
  BuildSftpPanelProc: TWidgetBuilder = nil;
  SftpShowTabProc: TTabNotify = nil;
  SftpTabClosedProc: TTabNotify = nil;
  ShowServersProc: TSimpleProc = nil;
  ShowTunnelsProc: TSimpleProc = nil;
  ShowPackagesProc: TSimpleProc = nil;
  ShowSettingsProc: TSimpleProc = nil;
  ShowPasswordsProc: TSimpleProc = nil;
  OpenEditorProc: procedure(const FileName: string) = nil;
  OpenToolProc: procedure(const Id: string) = nil;
  OpenGameProc: procedure(const Id: string) = nil;
  StartupProcs: array of TSimpleProc;
  { automated test commands handled by feature units }
  TestHooks: array of function(const Cmd, Arg: string): Boolean;
  ShutdownProcs: array of TSimpleProc;

procedure RegisterStartup(P: TSimpleProc);
procedure RegisterShutdown(P: TSimpleProc);

implementation

uses
  fpjson;

procedure RegisterStartup(P: TSimpleProc);
begin
  SetLength(StartupProcs, Length(StartupProcs) + 1);
  StartupProcs[High(StartupProcs)] := P;
end;

procedure RegisterShutdown(P: TSimpleProc);
begin
  SetLength(ShutdownProcs, Length(ShutdownProcs) + 1);
  ShutdownProcs[High(ShutdownProcs)] := P;
end;

function TabLabelPress(widget: Pointer; event: Pointer; data: gpointer): gboolean; cdecl;
var
  tab: TTabPage;
  btn: guint;
begin
  tab := TTabPage(data);
  Result := False;
  if gdk_event_get_event_type(event) <> GDK_BUTTON_PRESS then Exit;
  btn := EventButton(event);
  if (btn = 2) and tab.Closable then
  begin
    App.CloseTabLater(tab);
    Result := True;
  end
  else if btn = 3 then
  begin
    App.ShowTabMenu(tab, event);
    Result := True;
  end;
end;

procedure TabCloseClicked(button: Pointer; data: gpointer); cdecl;
begin
  App.CloseTabLater(TTabPage(data));
end;

constructor TTabPage.Create(ASession: TSession);
begin
  inherited Create;
  Session := ASession;
  Closable := True;
  if Session <> nil then
  begin
    IconName := Session.IconName;
    FTitle := Session.TabTitle;
  end;
end;

destructor TTabPage.Destroy;
begin
  Session.Free;
  inherited Destroy;
end;

procedure TTabPage.BuildLabel;
var
  hbox: Pointer;
begin
  LabelBox := gtk_event_box_new;
  gtk_event_box_set_visible_window(LabelBox, False);
  hbox := gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 4);
  LabelMark := gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
  AddClass(LabelMark, 'lx-tabmark');
  gtk_widget_set_valign(LabelMark, GTK_ALIGN_CENTER);
  gtk_widget_set_no_show_all(LabelMark, True);
  gtk_box_pack_start(hbox, LabelMark, False, False, 0);
  LabelIcon := NewIcon(IconName, 16);
  gtk_box_pack_start(hbox, LabelIcon, False, False, 0);
  LabelText := gtk_label_new(nil);
  gtk_label_set_ellipsize(LabelText, PANGO_ELLIPSIZE_END);
  gtk_label_set_max_width_chars(LabelText, 32);
  gtk_box_pack_start(hbox, LabelText, True, True, 0);
  if Closable then
  begin
    CloseBtn := NewFlatIconButton('window-close-symbolic', 'Close tab', 12);
    gtk_button_set_image(CloseBtn, gtk_image_new_from_icon_name('window-close-symbolic', GTK_ICON_SIZE_MENU));
    AddClass(CloseBtn, 'lx-tab-close');
    Connect(CloseBtn, 'clicked', @TabCloseClicked, Self);
    gtk_box_pack_start(hbox, CloseBtn, False, False, 0);
  end;
  gtk_container_add(LabelBox, hbox);
  Connect(LabelBox, 'button-press-event', @TabLabelPress, Self);
  gtk_widget_show_all(LabelBox);
  ApplyTabColor;
  UpdateLabel;
end;

procedure TTabPage.ApplyTabColor;
var
  i: Integer;
  c: string;
begin
  if LabelMark = nil then Exit;
  c := '';
  if Session <> nil then c := Session.TabColor;
  for i := 1 to TabColorCount - 1 do
    if TabColorIds[i] = c then AddClass(LabelMark, TabColorIds[i])
    else RemoveClass(LabelMark, TabColorIds[i]);
  gtk_widget_set_visible(LabelMark, c <> '');
end;

function Utf8Chars(const S: string): Integer;
var
  i: Integer;
begin
  Result := 0;
  for i := 1 to Length(S) do
    if (Ord(S[i]) and $C0) <> $80 then Inc(Result);
end;

procedure TTabPage.UpdateLabel;
var
  t: string;
  n: Integer;
begin
  if LabelText = nil then Exit;
  t := FullTitle;
  if FDisconnected then
    gtk_label_set_markup(LabelText, PChar('<span foreground="#a0a0a0">' + MarkupEscape(t) + '</span>'))
  else if FActivity then
    gtk_label_set_markup(LabelText, PChar('<span foreground="#2a7de1"><b>' + MarkupEscape(t) + '</b></span>'))
  else
    gtk_label_set_text(LabelText, PChar(t));
  { ellipsized labels only get their minimum width inside notebook tabs }
  n := Utf8Chars(t);
  if n > 32 then n := 32;
  gtk_label_set_width_chars(LabelText, n);
  gtk_widget_set_tooltip_text(LabelBox, PChar(t));
end;

procedure TTabPage.SetTitle(const T: string);
begin
  FTitle := T;
  UpdateLabel;
end;

function TTabPage.Title: string;
begin
  Result := FTitle;
end;

function TTabPage.FullTitle: string;
begin
  if Number > 0 then
    Result := IntToStr(Number) + '. ' + FTitle
  else
    Result := FTitle;
end;

procedure TTabPage.SetIcon(const Name: string);
var
  pb: Pointer;
begin
  IconName := Name;
  if LabelIcon <> nil then
  begin
    pb := IconPixbuf(Name, 16);
    if pb <> nil then gtk_image_set_from_pixbuf(LabelIcon, pb);
  end;
end;

procedure TTabPage.SetDisconnected(V: Boolean);
begin
  if FDisconnected = V then Exit;
  FDisconnected := V;
  UpdateLabel;
end;

procedure TTabPage.SetActivity(V: Boolean);
begin
  if FActivity = V then Exit;
  FActivity := V;
  UpdateLabel;
end;

function TTabPage.KindLabel: string;
begin
  if Session <> nil then
    Result := SessionKindNames[Session.Kind]
  else
    Result := '';
end;

function TTabPage.ConfirmClose: Boolean;
begin
  Result := True;
end;

procedure TTabPage.Shutdown;
begin
end;

procedure TTabPage.FocusContent;
begin
end;

procedure TTabPage.Activated;
begin
end;

function TTabPage.CanRestart: Boolean;
begin
  Result := False;
end;

procedure TTabPage.Restart;
begin
end;

function TTabPage.CanDuplicate: Boolean;
begin
  Result := Session <> nil;
end;

function TTabPage.IsTerminal: Boolean;
begin
  Result := False;
end;

procedure TTabPage.SaveState(List: TStrings);
var
  o: TJSONObject;
begin
  if Session = nil then Exit;
  o := Session.ToJSON;
  try
    List.Add(o.AsJSON);
  finally
    o.Free;
  end;
end;

end.

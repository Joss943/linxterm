{ LinXterm - optional libraries loaded at runtime:
  GtkSourceView 4 (text editor), GTK-VNC 2.0 (embedded VNC viewer),
  WebKit2GTK 4.1 (browser sessions) and libsecret (password storage). }
unit lxdyn;

{$mode objfpc}{$H+}
{$packrecords C}

interface

uses
  dynlibs, lxgtk;

type
  TSecretSchemaAttribute = record
    name: PChar;
    atype: gint;
  end;

  PSecretSchema = ^TSecretSchema;
  TSecretSchema = record
    name: PChar;
    flags: gint;
    attributes: array[0..31] of TSecretSchemaAttribute;
    reserved: gint;
    reserved1, reserved2, reserved3, reserved4, reserved5, reserved6, reserved7: gpointer;
  end;

var
  { GtkSourceView 4 }
  gtk_source_buffer_new: function(table: Pointer): Pointer; cdecl;
  gtk_source_view_new_with_buffer: function(buf: Pointer): Pointer; cdecl;
  gtk_source_view_set_show_line_numbers: procedure(v: Pointer; s: gboolean); cdecl;
  gtk_source_view_set_highlight_current_line: procedure(v: Pointer; s: gboolean); cdecl;
  gtk_source_view_set_auto_indent: procedure(v: Pointer; s: gboolean); cdecl;
  gtk_source_view_set_tab_width: procedure(v: Pointer; w: guint); cdecl;
  gtk_source_view_set_show_right_margin: procedure(v: Pointer; s: gboolean); cdecl;
  gtk_source_language_manager_get_default: function: Pointer; cdecl;
  gtk_source_language_manager_guess_language: function(lm: Pointer; filename, ctype: PChar): Pointer; cdecl;
  gtk_source_language_manager_get_language: function(lm: Pointer; id: PChar): Pointer; cdecl;
  gtk_source_language_get_name: function(l: Pointer): PChar; cdecl;
  gtk_source_language_get_id: function(l: Pointer): PChar; cdecl;
  gtk_source_buffer_set_language: procedure(b, lang: Pointer); cdecl;
  gtk_source_buffer_get_language: function(b: Pointer): Pointer; cdecl;
  gtk_source_buffer_set_highlight_syntax: procedure(b: Pointer; v: gboolean); cdecl;
  gtk_source_style_scheme_manager_get_default: function: Pointer; cdecl;
  gtk_source_style_scheme_manager_get_scheme: function(m: Pointer; id: PChar): Pointer; cdecl;
  gtk_source_buffer_set_style_scheme: procedure(b, scheme: Pointer); cdecl;
  gtk_source_buffer_can_undo: function(b: Pointer): gboolean; cdecl;
  gtk_source_buffer_can_redo: function(b: Pointer): gboolean; cdecl;
  gtk_source_buffer_undo: procedure(b: Pointer); cdecl;
  gtk_source_buffer_redo: procedure(b: Pointer); cdecl;
  gtk_source_buffer_begin_not_undoable_action: procedure(b: Pointer); cdecl;
  gtk_source_buffer_end_not_undoable_action: procedure(b: Pointer); cdecl;

  { GTK-VNC }
  vnc_display_new: function: Pointer; cdecl;
  vnc_display_open_host: function(d: Pointer; host, port: PChar): gboolean; cdecl;
  vnc_display_close: procedure(d: Pointer); cdecl;
  vnc_display_is_open: function(d: Pointer): gboolean; cdecl;
  vnc_display_set_credential: function(d: Pointer; typ: gint; data: PChar): gboolean; cdecl;
  vnc_display_set_scaling: function(d: Pointer; v: gboolean): gboolean; cdecl;
  vnc_display_set_read_only: procedure(d: Pointer; v: gboolean); cdecl;
  vnc_display_set_keyboard_grab: procedure(d: Pointer; v: gboolean); cdecl;
  vnc_display_set_pointer_grab: procedure(d: Pointer; v: gboolean); cdecl;
  vnc_display_set_shared_flag: procedure(d: Pointer; v: gboolean); cdecl;
  vnc_display_set_lossy_encoding: procedure(d: Pointer; v: gboolean); cdecl;
  vnc_display_send_keys: procedure(d: Pointer; keys: Pguint; n: gint); cdecl;
  vnc_display_get_pixbuf: function(d: Pointer): Pointer; cdecl;
  vnc_display_get_width: function(d: Pointer): gint; cdecl;
  vnc_display_get_height: function(d: Pointer): gint; cdecl;
  vnc_display_get_name: function(d: Pointer): PChar; cdecl;

  { WebKit2GTK 4.1 }
  webkit_web_view_new: function: Pointer; cdecl;
  webkit_web_view_load_uri: procedure(v: Pointer; uri: PChar); cdecl;
  webkit_web_view_go_back: procedure(v: Pointer); cdecl;
  webkit_web_view_go_forward: procedure(v: Pointer); cdecl;
  webkit_web_view_reload: procedure(v: Pointer); cdecl;
  webkit_web_view_stop_loading: procedure(v: Pointer); cdecl;
  webkit_web_view_get_uri: function(v: Pointer): PChar; cdecl;
  webkit_web_view_get_title: function(v: Pointer): PChar; cdecl;
  webkit_web_view_can_go_back: function(v: Pointer): gboolean; cdecl;
  webkit_web_view_can_go_forward: function(v: Pointer): gboolean; cdecl;

  { VTE >= 0.78: shell integration properties (termprops) }
  vte_terminal_get_termprop_uint: function(t: Pointer; name: PChar; value: PQWord): gboolean; cdecl;
  vte_install_termprop: function(name: PChar; ptype, flags: gint): gint; cdecl;

  { libsecret }
  secret_password_storev_sync: function(schema: PSecretSchema; attrs: Pointer; collection, lbl, password: PChar;
    cancellable: Pointer; error: PPGError): gboolean; cdecl;
  secret_password_lookupv_sync: function(schema: PSecretSchema; attrs: Pointer; cancellable: Pointer; error: PPGError): PChar; cdecl;
  secret_password_clearv_sync: function(schema: PSecretSchema; attrs: Pointer; cancellable: Pointer; error: PPGError): gboolean; cdecl;
  secret_password_free: procedure(p: PChar); cdecl;

function SourceViewAvailable: Boolean;
function VncAvailable: Boolean;
function WebKitAvailable: Boolean;
function SecretAvailable: Boolean;
function TermpropsAvailable: Boolean;

const
  VNC_DISPLAY_CREDENTIAL_PASSWORD = 0;
  VNC_DISPLAY_CREDENTIAL_USERNAME = 1;
  VNC_DISPLAY_CREDENTIAL_CLIENTNAME = 2;

implementation

type
  TLoadState = (lsUnknown, lsOk, lsFailed);

var
  SrcState, VncState, WebState, SecState, PropState: TLoadState;

function Bind(h: TLibHandle; const name: string; var p: Pointer): Boolean;
begin
  p := GetProcedureAddress(h, name);
  Result := p <> nil;
end;

function SourceViewAvailable: Boolean;
var
  h: TLibHandle;
  ok: Boolean;
begin
  if SrcState = lsUnknown then
  begin
    SrcState := lsFailed;
    h := LoadLibrary('libgtksourceview-4.so.0');
    if h <> NilHandle then
    begin
      ok := Bind(h, 'gtk_source_buffer_new', Pointer(gtk_source_buffer_new))
        and Bind(h, 'gtk_source_view_new_with_buffer', Pointer(gtk_source_view_new_with_buffer))
        and Bind(h, 'gtk_source_view_set_show_line_numbers', Pointer(gtk_source_view_set_show_line_numbers))
        and Bind(h, 'gtk_source_view_set_highlight_current_line', Pointer(gtk_source_view_set_highlight_current_line))
        and Bind(h, 'gtk_source_view_set_auto_indent', Pointer(gtk_source_view_set_auto_indent))
        and Bind(h, 'gtk_source_view_set_tab_width', Pointer(gtk_source_view_set_tab_width))
        and Bind(h, 'gtk_source_view_set_show_right_margin', Pointer(gtk_source_view_set_show_right_margin))
        and Bind(h, 'gtk_source_language_manager_get_default', Pointer(gtk_source_language_manager_get_default))
        and Bind(h, 'gtk_source_language_manager_guess_language', Pointer(gtk_source_language_manager_guess_language))
        and Bind(h, 'gtk_source_language_manager_get_language', Pointer(gtk_source_language_manager_get_language))
        and Bind(h, 'gtk_source_language_get_name', Pointer(gtk_source_language_get_name))
        and Bind(h, 'gtk_source_language_get_id', Pointer(gtk_source_language_get_id))
        and Bind(h, 'gtk_source_buffer_set_language', Pointer(gtk_source_buffer_set_language))
        and Bind(h, 'gtk_source_buffer_get_language', Pointer(gtk_source_buffer_get_language))
        and Bind(h, 'gtk_source_buffer_set_highlight_syntax', Pointer(gtk_source_buffer_set_highlight_syntax))
        and Bind(h, 'gtk_source_style_scheme_manager_get_default', Pointer(gtk_source_style_scheme_manager_get_default))
        and Bind(h, 'gtk_source_style_scheme_manager_get_scheme', Pointer(gtk_source_style_scheme_manager_get_scheme))
        and Bind(h, 'gtk_source_buffer_set_style_scheme', Pointer(gtk_source_buffer_set_style_scheme))
        and Bind(h, 'gtk_source_buffer_can_undo', Pointer(gtk_source_buffer_can_undo))
        and Bind(h, 'gtk_source_buffer_can_redo', Pointer(gtk_source_buffer_can_redo))
        and Bind(h, 'gtk_source_buffer_undo', Pointer(gtk_source_buffer_undo))
        and Bind(h, 'gtk_source_buffer_redo', Pointer(gtk_source_buffer_redo))
        and Bind(h, 'gtk_source_buffer_begin_not_undoable_action', Pointer(gtk_source_buffer_begin_not_undoable_action))
        and Bind(h, 'gtk_source_buffer_end_not_undoable_action', Pointer(gtk_source_buffer_end_not_undoable_action));
      if ok then SrcState := lsOk;
    end;
  end;
  Result := SrcState = lsOk;
end;

function VncAvailable: Boolean;
var
  h: TLibHandle;
  ok: Boolean;
begin
  if VncState = lsUnknown then
  begin
    VncState := lsFailed;
    h := LoadLibrary('libgtk-vnc-2.0.so.0');
    if h <> NilHandle then
    begin
      ok := Bind(h, 'vnc_display_new', Pointer(vnc_display_new))
        and Bind(h, 'vnc_display_open_host', Pointer(vnc_display_open_host))
        and Bind(h, 'vnc_display_close', Pointer(vnc_display_close))
        and Bind(h, 'vnc_display_is_open', Pointer(vnc_display_is_open))
        and Bind(h, 'vnc_display_set_credential', Pointer(vnc_display_set_credential))
        and Bind(h, 'vnc_display_set_scaling', Pointer(vnc_display_set_scaling))
        and Bind(h, 'vnc_display_set_read_only', Pointer(vnc_display_set_read_only))
        and Bind(h, 'vnc_display_set_keyboard_grab', Pointer(vnc_display_set_keyboard_grab))
        and Bind(h, 'vnc_display_set_pointer_grab', Pointer(vnc_display_set_pointer_grab))
        and Bind(h, 'vnc_display_set_shared_flag', Pointer(vnc_display_set_shared_flag))
        and Bind(h, 'vnc_display_set_lossy_encoding', Pointer(vnc_display_set_lossy_encoding))
        and Bind(h, 'vnc_display_send_keys', Pointer(vnc_display_send_keys))
        and Bind(h, 'vnc_display_get_pixbuf', Pointer(vnc_display_get_pixbuf))
        and Bind(h, 'vnc_display_get_width', Pointer(vnc_display_get_width))
        and Bind(h, 'vnc_display_get_height', Pointer(vnc_display_get_height))
        and Bind(h, 'vnc_display_get_name', Pointer(vnc_display_get_name));
      if ok then VncState := lsOk;
    end;
  end;
  Result := VncState = lsOk;
end;

function WebKitAvailable: Boolean;
var
  h: TLibHandle;
  ok: Boolean;
begin
  if WebState = lsUnknown then
  begin
    WebState := lsFailed;
    h := LoadLibrary('libwebkit2gtk-4.1.so.0');
    if h <> NilHandle then
    begin
      ok := Bind(h, 'webkit_web_view_new', Pointer(webkit_web_view_new))
        and Bind(h, 'webkit_web_view_load_uri', Pointer(webkit_web_view_load_uri))
        and Bind(h, 'webkit_web_view_go_back', Pointer(webkit_web_view_go_back))
        and Bind(h, 'webkit_web_view_go_forward', Pointer(webkit_web_view_go_forward))
        and Bind(h, 'webkit_web_view_reload', Pointer(webkit_web_view_reload))
        and Bind(h, 'webkit_web_view_stop_loading', Pointer(webkit_web_view_stop_loading))
        and Bind(h, 'webkit_web_view_get_uri', Pointer(webkit_web_view_get_uri))
        and Bind(h, 'webkit_web_view_get_title', Pointer(webkit_web_view_get_title))
        and Bind(h, 'webkit_web_view_can_go_back', Pointer(webkit_web_view_can_go_back))
        and Bind(h, 'webkit_web_view_can_go_forward', Pointer(webkit_web_view_can_go_forward));
      if ok then WebState := lsOk;
    end;
  end;
  Result := WebState = lsOk;
end;

function TermpropsAvailable: Boolean;
var
  h: TLibHandle;
begin
  if PropState = lsUnknown then
  begin
    PropState := lsFailed;
    h := LoadLibrary('libvte-2.91.so.0');
    if (h <> NilHandle) and Bind(h, 'vte_terminal_get_termprop_uint', Pointer(vte_terminal_get_termprop_uint))
      and Bind(h, 'vte_install_termprop', Pointer(vte_install_termprop)) then
      PropState := lsOk;
  end;
  Result := PropState = lsOk;
end;

function SecretAvailable: Boolean;
var
  h: TLibHandle;
  ok: Boolean;
begin
  if SecState = lsUnknown then
  begin
    SecState := lsFailed;
    h := LoadLibrary('libsecret-1.so.0');
    if h <> NilHandle then
    begin
      ok := Bind(h, 'secret_password_storev_sync', Pointer(secret_password_storev_sync))
        and Bind(h, 'secret_password_lookupv_sync', Pointer(secret_password_lookupv_sync))
        and Bind(h, 'secret_password_clearv_sync', Pointer(secret_password_clearv_sync))
        and Bind(h, 'secret_password_free', Pointer(secret_password_free));
      if ok then SecState := lsOk;
    end;
  end;
  Result := SecState = lsOk;
end;

end.

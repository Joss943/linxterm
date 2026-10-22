{ LinXterm - Object Pascal bindings for GLib / GObject / GIO / GDK / GTK 3 / VTE.
  Only the API surface used by LinXterm is declared. Optional libraries
  (GtkSourceView, GTK-VNC, WebKit2GTK, libsecret) are loaded at runtime in
  lxdyn.pas so that the application still starts when they are missing. }
unit lxgtk;

{$mode objfpc}{$H+}
{$packrecords C}

interface

const
  LIB_GLIB    = 'glib-2.0';
  LIB_GOBJECT = 'gobject-2.0';
  LIB_GIO     = 'gio-2.0';
  LIB_GDK     = 'gdk-3';
  LIB_GTK     = 'gtk-3';
  LIB_PIXBUF  = 'gdk_pixbuf-2.0';
  LIB_PANGO   = 'pango-1.0';
  LIB_VTE     = 'vte-2.91';

type
  gboolean = LongBool;
  gint = LongInt;
  guint = LongWord;
  gint8 = ShortInt;
  guint16 = Word;
  guint32 = LongWord;
  gint64 = Int64;
  guint64 = QWord;
  glong = PtrInt;
  gulong = PtrUInt;
  gsize = PtrUInt;
  gssize = PtrInt;
  gdouble = Double;
  gpointer = Pointer;
  GType = PtrUInt;
  GPid = LongInt;
  GQuark = guint32;
  PPChar = ^PChar;
  PPPChar = ^PPChar;
  PGPid = ^GPid;
  Pgint = ^gint;
  Pguint = ^guint;
  Pgdouble = ^gdouble;

  PGError = ^TGError;
  PPGError = ^PGError;
  TGError = record
    domain: GQuark;
    code: gint;
    message: PChar;
  end;

  PGList = ^TGList;
  TGList = record
    data: gpointer;
    next: PGList;
    prev: PGList;
  end;

  PGSList = ^TGSList;
  TGSList = record
    data: gpointer;
    next: PGSList;
  end;

  PGtkTreeIter = ^TGtkTreeIter;
  TGtkTreeIter = record
    stamp: gint;
    user_data: gpointer;
    user_data2: gpointer;
    user_data3: gpointer;
  end;

  PGtkTextIter = ^TGtkTextIter;
  TGtkTextIter = record
    dummy: array[0..9] of Int64;
  end;

  PGdkRGBA = ^TGdkRGBA;
  TGdkRGBA = record
    red, green, blue, alpha: gdouble;
  end;

  PGValue = ^TGValue;
  TGValue = record
    g_type: GType;
    data: array[0..1] of Int64;
  end;

  PGValueArray = ^TGValueArray;
  TGValueArray = record
    n_values: guint;
    values: PGValue;
    n_prealloced: guint;
  end;

  PGtkTargetEntry = ^TGtkTargetEntry;
  TGtkTargetEntry = record
    target: PChar;
    flags: guint;
    info: guint;
  end;

  PGtkAllocation = ^TGtkAllocation;
  TGtkAllocation = record
    x, y, width, height: gint;
  end;

  TGSourceFunc = function(data: gpointer): gboolean; cdecl;
  TGChildWatchFunc = procedure(pid: GPid; status: gint; data: gpointer); cdecl;
  TGIOFunc = function(source: Pointer; condition: guint; data: gpointer): gboolean; cdecl;
  TGDestroyNotify = procedure(data: gpointer); cdecl;
  TVteSpawnCB = procedure(terminal: Pointer; pid: GPid; error: PGError; data: gpointer); cdecl;

const
  { GObject }
  G_CONNECT_AFTER = 1;
  G_TYPE_INVALID = 0;
  G_TYPE_BOOLEAN = 5 shl 2;
  G_TYPE_INT = 6 shl 2;
  G_TYPE_UINT = 7 shl 2;
  G_TYPE_INT64 = 10 shl 2;
  G_TYPE_STRING = 16 shl 2;
  G_TYPE_POINTER = 17 shl 2;

  { GLib spawn / IO }
  G_SPAWN_LEAVE_DESCRIPTORS_OPEN = 1;
  G_SPAWN_DO_NOT_REAP_CHILD = 2;
  G_SPAWN_SEARCH_PATH = 4;
  G_SPAWN_STDOUT_TO_DEV_NULL = 8;
  G_SPAWN_STDERR_TO_DEV_NULL = 16;
  G_SPAWN_CHILD_INHERITS_STDIN = 32;
  G_SPAWN_CLOEXEC_PIPES = 256;
  G_IO_IN = 1;
  G_IO_PRI = 2;
  G_IO_OUT = 4;
  G_IO_ERR = 8;
  G_IO_HUP = 16;
  G_IO_NVAL = 32;
  G_IO_FLAG_NONBLOCK = 2;
  G_IO_STATUS_ERROR = 0;
  G_IO_STATUS_NORMAL = 1;
  G_IO_STATUS_EOF = 2;
  G_IO_STATUS_AGAIN = 3;
  G_PRIORITY_DEFAULT = 0;
  G_PRIORITY_DEFAULT_IDLE = 200;
  G_APPLICATION_FLAGS_NONE = 0;
  G_APPLICATION_HANDLES_OPEN = 4;
  G_APPLICATION_HANDLES_COMMAND_LINE = 8;
  G_APPLICATION_NON_UNIQUE = 32;
  G_SIGNAL_MATCH_FUNC = 8;
  G_SIGNAL_MATCH_DATA = 16;
  G_FILE_CREATE_NONE = 0;
  G_FILE_CREATE_PRIVATE = 1;
  G_FILE_CREATE_REPLACE_DESTINATION = 2;

  { GTK enums }
  GTK_WINDOW_TOPLEVEL = 0;
  GTK_WINDOW_POPUP = 1;
  GTK_ORIENTATION_HORIZONTAL = 0;
  GTK_ORIENTATION_VERTICAL = 1;
  GTK_POLICY_ALWAYS = 0;
  GTK_POLICY_AUTOMATIC = 1;
  GTK_POLICY_NEVER = 2;
  GTK_POLICY_EXTERNAL = 3;
  GTK_ALIGN_FILL = 0;
  GTK_ALIGN_START = 1;
  GTK_ALIGN_END = 2;
  GTK_ALIGN_CENTER = 3;
  GTK_POS_LEFT = 0;
  GTK_POS_RIGHT = 1;
  GTK_POS_TOP = 2;
  GTK_POS_BOTTOM = 3;
  GTK_PACK_START = 0;
  GTK_PACK_END = 1;
  GTK_RESPONSE_NONE = -1;
  GTK_RESPONSE_REJECT = -2;
  GTK_RESPONSE_ACCEPT = -3;
  GTK_RESPONSE_DELETE_EVENT = -4;
  GTK_RESPONSE_OK = -5;
  GTK_RESPONSE_CANCEL = -6;
  GTK_RESPONSE_CLOSE = -7;
  GTK_RESPONSE_YES = -8;
  GTK_RESPONSE_NO = -9;
  GTK_RESPONSE_APPLY = -10;
  GTK_RESPONSE_HELP = -11;
  GTK_DIALOG_MODAL = 1;
  GTK_DIALOG_DESTROY_WITH_PARENT = 2;
  GTK_MESSAGE_INFO = 0;
  GTK_MESSAGE_WARNING = 1;
  GTK_MESSAGE_QUESTION = 2;
  GTK_MESSAGE_ERROR = 3;
  GTK_MESSAGE_OTHER = 4;
  GTK_BUTTONS_NONE = 0;
  GTK_BUTTONS_OK = 1;
  GTK_BUTTONS_CLOSE = 2;
  GTK_BUTTONS_CANCEL = 3;
  GTK_BUTTONS_YES_NO = 4;
  GTK_BUTTONS_OK_CANCEL = 5;
  GTK_FILE_CHOOSER_ACTION_OPEN = 0;
  GTK_FILE_CHOOSER_ACTION_SAVE = 1;
  GTK_FILE_CHOOSER_ACTION_SELECT_FOLDER = 2;
  GTK_SELECTION_NONE = 0;
  GTK_SELECTION_SINGLE = 1;
  GTK_SELECTION_BROWSE = 2;
  GTK_SELECTION_MULTIPLE = 3;
  GTK_ICON_SIZE_MENU = 1;
  GTK_ICON_SIZE_SMALL_TOOLBAR = 2;
  GTK_ICON_SIZE_LARGE_TOOLBAR = 3;
  GTK_ICON_SIZE_BUTTON = 4;
  GTK_ICON_SIZE_DND = 5;
  GTK_ICON_SIZE_DIALOG = 6;
  GTK_RELIEF_NORMAL = 0;
  GTK_RELIEF_NONE = 2;
  GTK_SHADOW_NONE = 0;
  GTK_SHADOW_IN = 1;
  GTK_SHADOW_OUT = 2;
  GTK_SHADOW_ETCHED_IN = 3;
  GTK_WIN_POS_NONE = 0;
  GTK_WIN_POS_CENTER = 1;
  GTK_WIN_POS_MOUSE = 2;
  GTK_WIN_POS_CENTER_ON_PARENT = 4;
  GTK_ACCEL_VISIBLE = 1;
  GTK_TREE_VIEW_COLUMN_GROW_ONLY = 0;
  GTK_TREE_VIEW_COLUMN_AUTOSIZE = 1;
  GTK_TREE_VIEW_COLUMN_FIXED = 2;
  GTK_SORT_ASCENDING = 0;
  GTK_SORT_DESCENDING = 1;
  GTK_TREE_SORTABLE_DEFAULT_SORT_COLUMN_ID = -1;
  GTK_STACK_TRANSITION_TYPE_NONE = 0;
  GTK_STYLE_PROVIDER_PRIORITY_APPLICATION = 600;
  GTK_STYLE_PROVIDER_PRIORITY_USER = 800;
  GTK_DEST_DEFAULT_MOTION = 1;
  GTK_DEST_DEFAULT_HIGHLIGHT = 2;
  GTK_DEST_DEFAULT_DROP = 4;
  GTK_DEST_DEFAULT_ALL = 7;
  GTK_TARGET_SAME_APP = 1;
  GTK_TARGET_OTHER_APP = 4;
  GTK_JUSTIFY_LEFT = 0;
  GTK_JUSTIFY_CENTER = 2;
  GTK_WRAP_NONE = 0;
  GTK_WRAP_CHAR = 1;
  GTK_WRAP_WORD = 2;
  GTK_WRAP_WORD_CHAR = 3;
  GTK_INPUT_PURPOSE_PASSWORD = 8;
  GTK_STATE_FLAG_NORMAL = 0;
  GTK_REVEALER_TRANSITION_TYPE_NONE = 0;
  GTK_REVEALER_TRANSITION_TYPE_SLIDE_DOWN = 5;
  GTK_PROGRESS_BAR = 0;
  GTK_LEVEL_BAR_MODE_CONTINUOUS = 0;
  GTK_SPIN_BUTTON_UPDATE_IF_VALID = 1;
  PANGO_ELLIPSIZE_NONE = 0;
  PANGO_ELLIPSIZE_START = 1;
  PANGO_ELLIPSIZE_MIDDLE = 2;
  PANGO_ELLIPSIZE_END = 3;
  PANGO_WEIGHT_BOLD = 700;

  { GDK }
  GDK_SHIFT_MASK = 1;
  GDK_LOCK_MASK = 2;
  GDK_CONTROL_MASK = 4;
  GDK_MOD1_MASK = 8;
  GDK_BUTTON1_MASK = 1 shl 8;
  GDK_SUPER_MASK = 1 shl 26;
  GDK_META_MASK = 1 shl 28;
  GDK_BUTTON_PRESS_MASK = 1 shl 8;
  GDK_BUTTON_RELEASE_MASK = 1 shl 9;
  GDK_KEY_PRESS_MASK = 1 shl 10;
  GDK_POINTER_MOTION_MASK = 1 shl 2;
  GDK_SCROLL_MASK = 1 shl 21;
  GDK_SCROLL_UP = 0;
  GDK_SCROLL_DOWN = 1;
  GDK_BUTTON_PRESS = 4;
  GDK_2BUTTON_PRESS = 5;
  GDK_3BUTTON_PRESS = 6;
  GDK_BUTTON_RELEASE = 7;
  GDK_KEY_PRESS = 8;
  GDK_ACTION_DEFAULT = 1;
  GDK_ACTION_COPY = 2;
  GDK_ACTION_MOVE = 4;
  GDK_GRAVITY_NORTH_WEST = 1;
  GDK_GRAVITY_SOUTH_WEST = 7;
  GDK_INTERP_BILINEAR = 2;

  GDK_KEY_BackSpace = $ff08;
  GDK_KEY_Tab = $ff09;
  GDK_KEY_Return = $ff0d;
  GDK_KEY_Escape = $ff1b;
  GDK_KEY_Delete = $ffff;
  GDK_KEY_Home = $ff50;
  GDK_KEY_Left = $ff51;
  GDK_KEY_Up = $ff52;
  GDK_KEY_Right = $ff53;
  GDK_KEY_Down = $ff54;
  GDK_KEY_Page_Up = $ff55;
  GDK_KEY_Page_Down = $ff56;
  GDK_KEY_End = $ff57;
  GDK_KEY_Insert = $ff63;
  GDK_KEY_KP_Enter = $ff8d;
  GDK_KEY_KP_Add = $ffab;
  GDK_KEY_KP_Subtract = $ffad;
  GDK_KEY_KP_0 = $ffb0;
  GDK_KEY_ISO_Left_Tab = $fe20;
  GDK_KEY_F1 = $ffbe;
  GDK_KEY_F2 = $ffbf;
  GDK_KEY_F3 = $ffc0;
  GDK_KEY_F5 = $ffc2;
  GDK_KEY_F11 = $ffc8;
  GDK_KEY_Control_L = $ffe3;
  GDK_KEY_Alt_L = $ffe9;
  GDK_KEY_Delete_KP = $ff9f;
  GDK_KEY_space = $20;
  GDK_KEY_plus = $2b;
  GDK_KEY_minus = $2d;
  GDK_KEY_equal = $3d;
  GDK_KEY_0 = $30;
  GDK_KEY_UPPER_A = $41;
  GDK_KEY_LOWER_A = $61;

  { VTE }
  VTE_PTY_DEFAULT = 0;
  VTE_CURSOR_SHAPE_BLOCK = 0;
  VTE_CURSOR_SHAPE_IBEAM = 1;
  VTE_CURSOR_SHAPE_UNDERLINE = 2;
  VTE_CURSOR_BLINK_SYSTEM = 0;
  VTE_CURSOR_BLINK_ON = 1;
  VTE_CURSOR_BLINK_OFF = 2;
  VTE_FORMAT_TEXT = 1;
  VTE_FORMAT_HTML = 2;
  VTE_WRITE_DEFAULT = 0;
  VTE_ERASE_AUTO = 0;
  VTE_ERASE_ASCII_BACKSPACE = 1;
  VTE_ERASE_ASCII_DELETE = 2;
  VTE_ERASE_DELETE_SEQUENCE = 3;
  PCRE2_CASELESS = $00000008;
  PCRE2_MULTILINE = $00000400;
  PCRE2_UTF = $00080000;

function GDK_SELECTION_CLIPBOARD: Pointer; inline;
function GDK_SELECTION_PRIMARY: Pointer; inline;

{ ---------------- GLib ---------------- }
procedure g_free(mem: gpointer); cdecl; external LIB_GLIB;
function g_malloc0(n: gsize): gpointer; cdecl; external LIB_GLIB;
function g_strdup(s: PChar): PChar; cdecl; external LIB_GLIB;
procedure g_strfreev(v: PPChar); cdecl; external LIB_GLIB;
procedure g_error_free(e: PGError); cdecl; external LIB_GLIB;
procedure g_clear_error(e: PPGError); cdecl; external LIB_GLIB;
function g_idle_add(f: TGSourceFunc; data: gpointer): guint; cdecl; external LIB_GLIB;
function g_idle_add_full(prio: gint; f: TGSourceFunc; data: gpointer; notify: TGDestroyNotify): guint; cdecl; external LIB_GLIB;
function g_timeout_add(ms: guint; f: TGSourceFunc; data: gpointer): guint; cdecl; external LIB_GLIB;
function g_source_remove(id: guint): gboolean; cdecl; external LIB_GLIB;
function g_get_environ: PPChar; cdecl; external LIB_GLIB;
function g_environ_setenv(envp: PPChar; variable, value: PChar; overwrite: gboolean): PPChar; cdecl; external LIB_GLIB;
function g_environ_unsetenv(envp: PPChar; variable: PChar): PPChar; cdecl; external LIB_GLIB;
function g_spawn_async_with_pipes(wd: PChar; argv, envp: PPChar; flags: gint;
  setup, setupdata: gpointer; child_pid: PGPid; sin, sout, serr: Pgint; error: PPGError): gboolean; cdecl; external LIB_GLIB;
function g_spawn_sync(wd: PChar; argv, envp: PPChar; flags: gint; setup, setupdata: gpointer;
  sout, serr: PPChar; status: Pgint; error: PPGError): gboolean; cdecl; external LIB_GLIB;
function g_child_watch_add(pid: GPid; f: TGChildWatchFunc; data: gpointer): guint; cdecl; external LIB_GLIB;
procedure g_spawn_close_pid(pid: GPid); cdecl; external LIB_GLIB;
function g_io_channel_unix_new(fd: gint): Pointer; cdecl; external LIB_GLIB;
function g_io_channel_set_flags(ch: Pointer; flags: gint; error: PPGError): gint; cdecl; external LIB_GLIB;
function g_io_channel_set_encoding(ch: Pointer; enc: PChar; error: PPGError): gint; cdecl; external LIB_GLIB;
procedure g_io_channel_set_buffered(ch: Pointer; buffered: gboolean); cdecl; external LIB_GLIB;
procedure g_io_channel_set_close_on_unref(ch: Pointer; doclose: gboolean); cdecl; external LIB_GLIB;
function g_io_channel_read_chars(ch: Pointer; buf: PChar; count: gsize; bytes_read: PPtrUInt; error: PPGError): gint; cdecl; external LIB_GLIB;
function g_io_channel_write_chars(ch: Pointer; buf: PChar; count: gssize; written: PPtrUInt; error: PPGError): gint; cdecl; external LIB_GLIB;
function g_io_channel_flush(ch: Pointer; error: PPGError): gint; cdecl; external LIB_GLIB;
function g_io_channel_shutdown(ch: Pointer; flush: gboolean; error: PPGError): gint; cdecl; external LIB_GLIB;
procedure g_io_channel_unref(ch: Pointer); cdecl; external LIB_GLIB;
function g_io_add_watch(ch: Pointer; cond: guint; f: TGIOFunc; data: gpointer): guint; cdecl; external LIB_GLIB;
function g_get_user_config_dir: PChar; cdecl; external LIB_GLIB;
function g_get_user_data_dir: PChar; cdecl; external LIB_GLIB;
{ variants, actions and desktop notifications }
function g_variant_new_int32(v: gint): Pointer; cdecl; external LIB_GLIB;
function g_variant_get_int32(v: Pointer): gint; cdecl; external LIB_GLIB;
function g_variant_type_new(s: PChar): Pointer; cdecl; external LIB_GLIB;
procedure g_variant_type_free(t: Pointer); cdecl; external LIB_GLIB;
function g_simple_action_new(name: PChar; ptype: Pointer): Pointer; cdecl; external LIB_GIO;
procedure g_action_map_add_action(map, action: Pointer); cdecl; external LIB_GIO;
function g_notification_new(title: PChar): Pointer; cdecl; external LIB_GIO;
procedure g_notification_set_body(n: Pointer; body: PChar); cdecl; external LIB_GIO;
procedure g_notification_set_default_action_and_target_value(n: Pointer; action: PChar; target: Pointer); cdecl; external LIB_GIO;
procedure g_application_send_notification(app: Pointer; id: PChar; n: Pointer); cdecl; external LIB_GIO;
function g_get_user_cache_dir: PChar; cdecl; external LIB_GLIB;
function g_get_user_runtime_dir: PChar; cdecl; external LIB_GLIB;
function g_get_home_dir: PChar; cdecl; external LIB_GLIB;
function g_get_user_name: PChar; cdecl; external LIB_GLIB;
function g_get_host_name: PChar; cdecl; external LIB_GLIB;
function g_get_tmp_dir: PChar; cdecl; external LIB_GLIB;
function g_get_user_special_dir(directory: gint): PChar; cdecl; external LIB_GLIB;
function g_filename_from_uri(uri: PChar; hostname: PPChar; error: PPGError): PChar; cdecl; external LIB_GLIB;
function g_filename_to_uri(filename: PChar; hostname: PChar; error: PPGError): PChar; cdecl; external LIB_GLIB;
function g_markup_escape_text(text: PChar; len: gssize): PChar; cdecl; external LIB_GLIB;
function g_regex_escape_string(s: PChar; len: gint): PChar; cdecl; external LIB_GLIB;
function g_shell_quote(s: PChar): PChar; cdecl; external LIB_GLIB;
function g_shell_parse_argv(cmdline: PChar; argcp: Pgint; argvp: PPPChar; error: PPGError): gboolean; cdecl; external LIB_GLIB;
function g_get_monotonic_time: gint64; cdecl; external LIB_GLIB;
function g_utf8_validate(s: PChar; maxlen: gssize; endp: PPChar): gboolean; cdecl; external LIB_GLIB;
function g_locale_to_utf8(s: PChar; len: gssize; br, bw: PPtrUInt; error: PPGError): PChar; cdecl; external LIB_GLIB;
function g_convert_with_fallback(s: PChar; len: gssize; tocs, fromcs, fallback: PChar; br, bw: PPtrUInt; error: PPGError): PChar; cdecl; external LIB_GLIB;
procedure g_list_free(l: PGList); cdecl; external LIB_GLIB;
procedure g_list_free_full(l: PGList; f: TGDestroyNotify); cdecl; external LIB_GLIB;
function g_list_length(l: PGList): guint; cdecl; external LIB_GLIB;
procedure g_slist_free(l: PGSList); cdecl; external LIB_GLIB;
function g_hash_table_new(hash, equal: Pointer): Pointer; cdecl; external LIB_GLIB;
function g_hash_table_insert(h: Pointer; key, value: gpointer): gboolean; cdecl; external LIB_GLIB;
procedure g_hash_table_unref(h: Pointer); cdecl; external LIB_GLIB;
function g_str_hash(v: gpointer): guint; cdecl; external LIB_GLIB;
function g_str_equal(a, b: gpointer): gboolean; cdecl; external LIB_GLIB;
function g_find_program_in_path(prog: PChar): PChar; cdecl; external LIB_GLIB;
procedure g_set_prgname(name: PChar); cdecl; external LIB_GLIB;
procedure g_set_application_name(name: PChar); cdecl; external LIB_GLIB;
function g_main_context_iteration(ctx: Pointer; may_block: gboolean): gboolean; cdecl; external LIB_GLIB;
function g_main_context_pending(ctx: Pointer): gboolean; cdecl; external LIB_GLIB;

{ ---------------- GObject ---------------- }
function g_signal_connect_data(instance: gpointer; signal: PChar; handler: Pointer; data: gpointer;
  destroy: Pointer; flags: gint): gulong; cdecl; external LIB_GOBJECT;
procedure g_signal_handler_disconnect(instance: gpointer; id: gulong); cdecl; external LIB_GOBJECT;
procedure g_signal_handler_block(instance: gpointer; id: gulong); cdecl; external LIB_GOBJECT;
procedure g_signal_handler_unblock(instance: gpointer; id: gulong); cdecl; external LIB_GOBJECT;
procedure g_signal_stop_emission_by_name(instance: gpointer; signal: PChar); cdecl; external LIB_GOBJECT;
function g_signal_handlers_disconnect_matched(instance: gpointer; mask: gint; signal_id: guint; detail: GQuark;
  closure, func, data: gpointer): guint; cdecl; external LIB_GOBJECT;
function g_object_ref(obj: gpointer): gpointer; cdecl; external LIB_GOBJECT;
procedure g_object_unref(obj: gpointer); cdecl; external LIB_GOBJECT;
function g_object_ref_sink(obj: gpointer): gpointer; cdecl; external LIB_GOBJECT;
procedure g_object_set_data(obj: gpointer; key: PChar; data: gpointer); cdecl; external LIB_GOBJECT;
procedure g_object_set_data_full(obj: gpointer; key: PChar; data: gpointer; destroy: Pointer); cdecl; external LIB_GOBJECT;
function g_signal_handlers_block_matched(instance: gpointer; mask: gint; signal_id: guint; detail: GQuark;
  closure, func, data: gpointer): guint; cdecl; external LIB_GOBJECT;
function g_signal_handlers_unblock_matched(instance: gpointer; mask: gint; signal_id: guint; detail: GQuark;
  closure, func, data: gpointer): guint; cdecl; external LIB_GOBJECT;
function g_object_get_data(obj: gpointer; key: PChar): gpointer; cdecl; external LIB_GOBJECT;
procedure g_object_set(obj: gpointer; first: PChar); cdecl; varargs; external LIB_GOBJECT;
procedure g_object_get(obj: gpointer; first: PChar); cdecl; varargs; external LIB_GOBJECT;
function g_value_init(v: PGValue; t: GType): PGValue; cdecl; external LIB_GOBJECT;
procedure g_value_unset(v: PGValue); cdecl; external LIB_GOBJECT;
function g_value_get_enum(v: PGValue): gint; cdecl; external LIB_GOBJECT;
function g_value_get_int(v: PGValue): gint; cdecl; external LIB_GOBJECT;
function g_value_get_string(v: PGValue): PChar; cdecl; external LIB_GOBJECT;
procedure g_value_set_string(v: PGValue; s: PChar); cdecl; external LIB_GOBJECT;
function g_type_check_instance_is_a(inst: gpointer; t: GType): gboolean; cdecl; external LIB_GOBJECT;

{ ---------------- GIO ---------------- }
function g_file_new_for_path(path: PChar): Pointer; cdecl; external LIB_GIO;
function g_file_replace(f: Pointer; etag: PChar; backup: gboolean; flags: gint; cancellable: Pointer; error: PPGError): Pointer; cdecl; external LIB_GIO;
function g_output_stream_close(s: Pointer; cancellable: Pointer; error: PPGError): gboolean; cdecl; external LIB_GIO;
function g_application_run(app: Pointer; argc: gint; argv: PPChar): gint; cdecl; external LIB_GIO;
function g_application_command_line_get_arguments(cmdline: Pointer; argc: Pgint): PPChar; cdecl; external LIB_GIO;
procedure g_application_quit(app: Pointer); cdecl; external LIB_GIO;
procedure g_application_hold(app: Pointer); cdecl; external LIB_GIO;
procedure g_application_release(app: Pointer); cdecl; external LIB_GIO;
function g_app_info_launch_default_for_uri(uri: PChar; ctx: Pointer; error: PPGError): gboolean; cdecl; external LIB_GIO;

{ ---------------- GDK ---------------- }
function gdk_event_get_keyval(ev: Pointer; keyval: Pguint): gboolean; cdecl; external LIB_GDK;
function gdk_event_get_state(ev: Pointer; state: Pguint): gboolean; cdecl; external LIB_GDK;
function gdk_event_get_button(ev: Pointer; button: Pguint): gboolean; cdecl; external LIB_GDK;
function gdk_event_get_event_type(ev: Pointer): gint; cdecl; external LIB_GDK;
function gdk_event_get_coords(ev: Pointer; x, y: Pgdouble): gboolean; cdecl; external LIB_GDK;
function gdk_event_get_scroll_direction(ev: Pointer; dir: Pgint): gboolean; cdecl; external LIB_GDK;
function gdk_event_get_scroll_deltas(ev: Pointer; dx, dy: Pgdouble): gboolean; cdecl; external LIB_GDK;
function gdk_event_get_root_coords(ev: Pointer; x, y: Pgdouble): gboolean; cdecl; external LIB_GDK;
function gdk_event_triggers_context_menu(ev: Pointer): gboolean; cdecl; external LIB_GDK;
function gdk_rgba_parse(rgba: PGdkRGBA; spec: PChar): gboolean; cdecl; external LIB_GDK;
function gdk_rgba_to_string(rgba: PGdkRGBA): PChar; cdecl; external LIB_GDK;
function gdk_screen_get_default: Pointer; cdecl; external LIB_GDK;
function gdk_display_get_default: Pointer; cdecl; external LIB_GDK;
function gdk_display_get_name(d: Pointer): PChar; cdecl; external LIB_GDK;
procedure gdk_display_beep(d: Pointer); cdecl; external LIB_GDK;
function gdk_keyval_to_unicode(keyval: guint): guint32; cdecl; external LIB_GDK;
function gdk_keyval_to_lower(keyval: guint): guint; cdecl; external LIB_GDK;
procedure gdk_cairo_set_source_rgba(cr: Pointer; rgba: PGdkRGBA); cdecl; external LIB_GDK;
procedure gdk_cairo_set_source_pixbuf(cr: Pointer; pixbuf: Pointer; x, y: gdouble); cdecl; external LIB_GDK;
function gdk_atom_intern(name: PChar; only_if_exists: gboolean): Pointer; cdecl; external LIB_GDK;
procedure gdk_window_set_cursor(w: Pointer; cursor: Pointer); cdecl; external LIB_GDK;

{ ---------------- GdkPixbuf ---------------- }
function gdk_pixbuf_new_from_file_at_size(filename: PChar; w, h: gint; error: PPGError): Pointer; cdecl; external LIB_PIXBUF;
function gdk_pixbuf_save(pixbuf: Pointer; filename, ftype: PChar; error: PPGError): gboolean; cdecl; varargs; external LIB_PIXBUF;
function gdk_pixbuf_scale_simple(src: Pointer; w, h: gint; interp: gint): Pointer; cdecl; external LIB_PIXBUF;
function gdk_pixbuf_get_width(p: Pointer): gint; cdecl; external LIB_PIXBUF;
function gdk_pixbuf_get_height(p: Pointer): gint; cdecl; external LIB_PIXBUF;
function gdk_pixbuf_get_type: GType; cdecl; external LIB_PIXBUF;
function gdk_pixbuf_copy(p: Pointer): Pointer; cdecl; external LIB_PIXBUF;
procedure gdk_pixbuf_saturate_and_pixelate(src, dest: Pointer; saturation: Single; pixelate: gboolean); cdecl; external LIB_PIXBUF;

{ ---------------- Pango ---------------- }
function pango_font_description_from_string(s: PChar): Pointer; cdecl; external LIB_PANGO;
procedure pango_font_description_free(d: Pointer); cdecl; external LIB_PANGO;
function pango_font_description_to_string(d: Pointer): PChar; cdecl; external LIB_PANGO;

{ ---------------- GTK ---------------- }
function gtk_application_new(id: PChar; flags: gint): Pointer; cdecl; external LIB_GTK;
function gtk_application_window_new(app: Pointer): Pointer; cdecl; external LIB_GTK;
procedure gtk_window_set_application(w, app: Pointer); cdecl; external LIB_GTK;
function gtk_get_major_version: guint; cdecl; external LIB_GTK;
function gtk_get_minor_version: guint; cdecl; external LIB_GTK;
procedure gtk_init(argc, argv: Pointer); cdecl; external LIB_GTK;
procedure gtk_main; cdecl; external LIB_GTK;
procedure gtk_main_quit; cdecl; external LIB_GTK;
function gtk_events_pending: gboolean; cdecl; external LIB_GTK;
function gtk_main_iteration: gboolean; cdecl; external LIB_GTK;
function gtk_get_current_event_time: guint32; cdecl; external LIB_GTK;
function gtk_get_current_event: Pointer; cdecl; external LIB_GTK;
procedure gdk_event_free(ev: Pointer); cdecl; external LIB_GDK;

{ widget }
procedure gtk_widget_show(w: Pointer); cdecl; external LIB_GTK;
procedure gtk_widget_show_all(w: Pointer); cdecl; external LIB_GTK;
procedure gtk_widget_hide(w: Pointer); cdecl; external LIB_GTK;
procedure gtk_widget_destroy(w: Pointer); cdecl; external LIB_GTK;
procedure gtk_widget_set_visible(w: Pointer; v: gboolean); cdecl; external LIB_GTK;
function gtk_widget_get_visible(w: Pointer): gboolean; cdecl; external LIB_GTK;
procedure gtk_widget_set_no_show_all(w: Pointer; v: gboolean); cdecl; external LIB_GTK;
procedure gtk_widget_set_sensitive(w: Pointer; v: gboolean); cdecl; external LIB_GTK;
function gtk_widget_get_sensitive(w: Pointer): gboolean; cdecl; external LIB_GTK;
procedure gtk_widget_set_size_request(w: Pointer; width, height: gint); cdecl; external LIB_GTK;
procedure gtk_widget_set_hexpand(w: Pointer; v: gboolean); cdecl; external LIB_GTK;
procedure gtk_widget_set_vexpand(w: Pointer; v: gboolean); cdecl; external LIB_GTK;
procedure gtk_widget_set_halign(w: Pointer; a: gint); cdecl; external LIB_GTK;
procedure gtk_widget_set_valign(w: Pointer; a: gint); cdecl; external LIB_GTK;
procedure gtk_widget_set_margin_start(w: Pointer; m: gint); cdecl; external LIB_GTK;
procedure gtk_widget_set_margin_end(w: Pointer; m: gint); cdecl; external LIB_GTK;
procedure gtk_widget_set_margin_top(w: Pointer; m: gint); cdecl; external LIB_GTK;
procedure gtk_widget_set_margin_bottom(w: Pointer; m: gint); cdecl; external LIB_GTK;
procedure gtk_widget_grab_focus(w: Pointer); cdecl; external LIB_GTK;
function gtk_widget_has_focus(w: Pointer): gboolean; cdecl; external LIB_GTK;
function gtk_widget_is_focus(w: Pointer): gboolean; cdecl; external LIB_GTK;
procedure gtk_widget_set_can_focus(w: Pointer; v: gboolean); cdecl; external LIB_GTK;
procedure gtk_widget_queue_draw(w: Pointer); cdecl; external LIB_GTK;
procedure gtk_widget_set_tooltip_text(w: Pointer; t: PChar); cdecl; external LIB_GTK;
procedure gtk_widget_set_tooltip_markup(w: Pointer; t: PChar); cdecl; external LIB_GTK;
function gtk_widget_get_toplevel(w: Pointer): Pointer; cdecl; external LIB_GTK;
function gtk_widget_get_parent(w: Pointer): Pointer; cdecl; external LIB_GTK;
function gtk_widget_get_allocated_width(w: Pointer): gint; cdecl; external LIB_GTK;
function gtk_widget_get_allocated_height(w: Pointer): gint; cdecl; external LIB_GTK;
procedure gtk_widget_get_allocation(w: Pointer; a: PGtkAllocation); cdecl; external LIB_GTK;
procedure gtk_widget_add_events(w: Pointer; events: gint); cdecl; external LIB_GTK;
function gtk_widget_get_window(w: Pointer): Pointer; cdecl; external LIB_GTK;
procedure gtk_widget_realize(w: Pointer); cdecl; external LIB_GTK;
function gtk_widget_get_mapped(w: Pointer): gboolean; cdecl; external LIB_GTK;
function gtk_widget_get_realized(w: Pointer): gboolean; cdecl; external LIB_GTK;
procedure gtk_widget_draw(w: Pointer; cr: Pointer); cdecl; external LIB_GTK;
function gtk_widget_get_style_context(w: Pointer): Pointer; cdecl; external LIB_GTK;
procedure gtk_widget_set_name(w: Pointer; name: PChar); cdecl; external LIB_GTK;
procedure gtk_widget_add_accelerator(w: Pointer; signal: PChar; group: Pointer; key: guint; mods: guint; flags: gint); cdecl; external LIB_GTK;
function gtk_widget_is_ancestor(w, ancestor: Pointer): gboolean; cdecl; external LIB_GTK;
function gtk_widget_get_ancestor(w: Pointer; t: GType): Pointer; cdecl; external LIB_GTK;
procedure gtk_widget_set_opacity(w: Pointer; o: gdouble); cdecl; external LIB_GTK;
function gtk_widget_get_scale_factor(w: Pointer): gint; cdecl; external LIB_GTK;
function gtk_widget_activate(w: Pointer): gboolean; cdecl; external LIB_GTK;
procedure gtk_widget_get_preferred_width(w: Pointer; min, nat: Pgint); cdecl; external LIB_GTK;

{ style / css }
function gtk_css_provider_new: Pointer; cdecl; external LIB_GTK;
function gtk_css_provider_load_from_data(p: Pointer; data: PChar; len: gssize; error: PPGError): gboolean; cdecl; external LIB_GTK;
procedure gtk_style_context_add_provider_for_screen(screen, provider: Pointer; prio: guint); cdecl; external LIB_GTK;
procedure gtk_style_context_remove_provider_for_screen(screen, provider: Pointer); cdecl; external LIB_GTK;
procedure gtk_style_context_add_class(ctx: Pointer; name: PChar); cdecl; external LIB_GTK;
procedure gtk_style_context_remove_class(ctx: Pointer; name: PChar); cdecl; external LIB_GTK;
function gtk_settings_get_default: Pointer; cdecl; external LIB_GTK;

{ window }
function gtk_window_new(t: gint): Pointer; cdecl; external LIB_GTK;
procedure gtk_window_set_title(w: Pointer; t: PChar); cdecl; external LIB_GTK;
procedure gtk_window_set_urgency_hint(w: Pointer; v: gboolean); cdecl; external LIB_GTK;
function gtk_window_is_active(w: Pointer): gboolean; cdecl; external LIB_GTK;
procedure gtk_window_set_default_size(w: Pointer; width, height: gint); cdecl; external LIB_GTK;
procedure gtk_window_resize(w: Pointer; width, height: gint); cdecl; external LIB_GTK;
procedure gtk_window_get_size(w: Pointer; width, height: Pgint); cdecl; external LIB_GTK;
procedure gtk_window_set_transient_for(w, parent: Pointer); cdecl; external LIB_GTK;
procedure gtk_window_set_modal(w: Pointer; m: gboolean); cdecl; external LIB_GTK;
procedure gtk_window_set_decorated(w: Pointer; v: gboolean); cdecl; external LIB_GTK;
procedure gtk_window_set_position(w: Pointer; p: gint); cdecl; external LIB_GTK;
procedure gtk_window_present(w: Pointer); cdecl; external LIB_GTK;
procedure gtk_window_fullscreen(w: Pointer); cdecl; external LIB_GTK;
procedure gtk_window_unfullscreen(w: Pointer); cdecl; external LIB_GTK;
procedure gtk_window_maximize(w: Pointer); cdecl; external LIB_GTK;
function gtk_window_is_maximized(w: Pointer): gboolean; cdecl; external LIB_GTK;
procedure gtk_window_set_icon(w: Pointer; pixbuf: Pointer); cdecl; external LIB_GTK;
procedure gtk_window_set_icon_name(w: Pointer; name: PChar); cdecl; external LIB_GTK;
procedure gtk_window_set_default_icon(pixbuf: Pointer); cdecl; external LIB_GTK;
procedure gtk_window_add_accel_group(w, group: Pointer); cdecl; external LIB_GTK;
procedure gtk_window_set_resizable(w: Pointer; r: gboolean); cdecl; external LIB_GTK;
procedure gtk_window_set_destroy_with_parent(w: Pointer; v: gboolean); cdecl; external LIB_GTK;
procedure gtk_window_set_type_hint(w: Pointer; hint: gint); cdecl; external LIB_GTK;
function gtk_window_get_focus(w: Pointer): Pointer; cdecl; external LIB_GTK;
procedure gtk_window_set_keep_above(w: Pointer; v: gboolean); cdecl; external LIB_GTK;
procedure gtk_window_set_role(w: Pointer; role: PChar); cdecl; external LIB_GTK;
function gtk_window_list_toplevels: PGList; cdecl; external LIB_GTK;
procedure gtk_window_close(w: Pointer); cdecl; external LIB_GTK;
function gtk_accel_group_new: Pointer; cdecl; external LIB_GTK;

{ containers }
procedure gtk_container_add(c, w: Pointer); cdecl; external LIB_GTK;
procedure gtk_container_remove(c, w: Pointer); cdecl; external LIB_GTK;
procedure gtk_container_set_border_width(c: Pointer; w: guint); cdecl; external LIB_GTK;
function gtk_container_get_children(c: Pointer): PGList; cdecl; external LIB_GTK;
function gtk_bin_get_child(b: Pointer): Pointer; cdecl; external LIB_GTK;
function gtk_box_new(orientation: gint; spacing: gint): Pointer; cdecl; external LIB_GTK;
procedure gtk_box_pack_start(b, w: Pointer; expand, fill: gboolean; padding: guint); cdecl; external LIB_GTK;
procedure gtk_box_pack_end(b, w: Pointer; expand, fill: gboolean; padding: guint); cdecl; external LIB_GTK;
procedure gtk_box_set_spacing(b: Pointer; s: gint); cdecl; external LIB_GTK;
procedure gtk_box_set_homogeneous(b: Pointer; h: gboolean); cdecl; external LIB_GTK;
procedure gtk_box_reorder_child(b, w: Pointer; pos: gint); cdecl; external LIB_GTK;
function gtk_grid_new: Pointer; cdecl; external LIB_GTK;
procedure gtk_grid_attach(g, w: Pointer; left, top, width, height: gint); cdecl; external LIB_GTK;
procedure gtk_grid_set_row_spacing(g: Pointer; s: guint); cdecl; external LIB_GTK;
procedure gtk_grid_set_column_spacing(g: Pointer; s: guint); cdecl; external LIB_GTK;
procedure gtk_grid_set_row_homogeneous(g: Pointer; h: gboolean); cdecl; external LIB_GTK;
procedure gtk_grid_set_column_homogeneous(g: Pointer; h: gboolean); cdecl; external LIB_GTK;
function gtk_paned_new(orientation: gint): Pointer; cdecl; external LIB_GTK;
procedure gtk_paned_pack1(p, w: Pointer; resize, shrink: gboolean); cdecl; external LIB_GTK;
procedure gtk_paned_pack2(p, w: Pointer; resize, shrink: gboolean); cdecl; external LIB_GTK;
procedure gtk_paned_set_position(p: Pointer; pos: gint); cdecl; external LIB_GTK;
function gtk_paned_get_position(p: Pointer): gint; cdecl; external LIB_GTK;
procedure gtk_paned_set_wide_handle(p: Pointer; w: gboolean); cdecl; external LIB_GTK;
function gtk_scrolled_window_new(h, v: Pointer): Pointer; cdecl; external LIB_GTK;
procedure gtk_scrolled_window_set_policy(s: Pointer; h, v: gint); cdecl; external LIB_GTK;
procedure gtk_scrolled_window_set_shadow_type(s: Pointer; t: gint); cdecl; external LIB_GTK;
procedure gtk_scrolled_window_set_min_content_height(s: Pointer; h: gint); cdecl; external LIB_GTK;
procedure gtk_scrolled_window_set_min_content_width(s: Pointer; w: gint); cdecl; external LIB_GTK;
function gtk_scrolled_window_get_vadjustment(s: Pointer): Pointer; cdecl; external LIB_GTK;
procedure gtk_scrolled_window_set_propagate_natural_height(s: Pointer; v: gboolean); cdecl; external LIB_GTK;
function gtk_adjustment_get_upper(a: Pointer): gdouble; cdecl; external LIB_GTK;
function gtk_adjustment_get_lower(a: Pointer): gdouble; cdecl; external LIB_GTK;
procedure gtk_adjustment_set_value(a: Pointer; v: gdouble); cdecl; external LIB_GTK;
function gtk_adjustment_get_page_size(a: Pointer): gdouble; cdecl; external LIB_GTK;
function gtk_frame_new(lbl: PChar): Pointer; cdecl; external LIB_GTK;
procedure gtk_frame_set_shadow_type(f: Pointer; t: gint); cdecl; external LIB_GTK;
function gtk_frame_get_label_widget(f: Pointer): Pointer; cdecl; external LIB_GTK;
function gtk_event_box_new: Pointer; cdecl; external LIB_GTK;
procedure gtk_event_box_set_visible_window(e: Pointer; v: gboolean); cdecl; external LIB_GTK;
function gtk_overlay_new: Pointer; cdecl; external LIB_GTK;
procedure gtk_overlay_add_overlay(o, w: Pointer); cdecl; external LIB_GTK;
function gtk_stack_new: Pointer; cdecl; external LIB_GTK;
procedure gtk_stack_add_named(s, w: Pointer; name: PChar); cdecl; external LIB_GTK;
procedure gtk_stack_set_visible_child_name(s: Pointer; name: PChar); cdecl; external LIB_GTK;
procedure gtk_stack_set_visible_child(s, w: Pointer); cdecl; external LIB_GTK;
function gtk_stack_get_visible_child_name(s: Pointer): PChar; cdecl; external LIB_GTK;
procedure gtk_stack_set_transition_type(s: Pointer; t: gint); cdecl; external LIB_GTK;
procedure gtk_stack_set_homogeneous(s: Pointer; h: gboolean); cdecl; external LIB_GTK;
function gtk_revealer_new: Pointer; cdecl; external LIB_GTK;
procedure gtk_revealer_set_reveal_child(r: Pointer; v: gboolean); cdecl; external LIB_GTK;
function gtk_revealer_get_reveal_child(r: Pointer): gboolean; cdecl; external LIB_GTK;
procedure gtk_revealer_set_transition_type(r: Pointer; t: gint); cdecl; external LIB_GTK;
function gtk_separator_new(orientation: gint): Pointer; cdecl; external LIB_GTK;
function gtk_expander_new(lbl: PChar): Pointer; cdecl; external LIB_GTK;
procedure gtk_expander_set_expanded(e: Pointer; v: gboolean); cdecl; external LIB_GTK;
function gtk_flow_box_new: Pointer; cdecl; external LIB_GTK;
procedure gtk_flow_box_insert(f, w: Pointer; pos: gint); cdecl; external LIB_GTK;
procedure gtk_flow_box_set_selection_mode(f: Pointer; m: gint); cdecl; external LIB_GTK;
procedure gtk_flow_box_set_max_children_per_line(f: Pointer; n: guint); cdecl; external LIB_GTK;
procedure gtk_flow_box_set_min_children_per_line(f: Pointer; n: guint); cdecl; external LIB_GTK;
procedure gtk_flow_box_set_homogeneous(f: Pointer; h: gboolean); cdecl; external LIB_GTK;
procedure gtk_flow_box_set_column_spacing(f: Pointer; s: guint); cdecl; external LIB_GTK;
procedure gtk_flow_box_set_row_spacing(f: Pointer; s: guint); cdecl; external LIB_GTK;
function gtk_list_box_new: Pointer; cdecl; external LIB_GTK;
procedure gtk_list_box_insert(l, w: Pointer; pos: gint); cdecl; external LIB_GTK;
procedure gtk_list_box_set_selection_mode(l: Pointer; m: gint); cdecl; external LIB_GTK;
function gtk_list_box_row_get_index(r: Pointer): gint; cdecl; external LIB_GTK;
function gtk_list_box_row_new: Pointer; cdecl; external LIB_GTK;
procedure gtk_list_box_set_activate_on_single_click(l: Pointer; v: gboolean); cdecl; external LIB_GTK;
procedure gtk_list_box_set_placeholder(l, w: Pointer); cdecl; external LIB_GTK;
function gtk_list_box_get_selected_row(l: Pointer): Pointer; cdecl; external LIB_GTK;
procedure gtk_list_box_select_row(l, r: Pointer); cdecl; external LIB_GTK;
function gtk_list_box_get_row_at_index(l: Pointer; i: gint): Pointer; cdecl; external LIB_GTK;

{ notebook }
function gtk_notebook_new: Pointer; cdecl; external LIB_GTK;
function gtk_notebook_append_page(nb, child, lbl: Pointer): gint; cdecl; external LIB_GTK;
function gtk_notebook_insert_page(nb, child, lbl: Pointer; pos: gint): gint; cdecl; external LIB_GTK;
procedure gtk_notebook_remove_page(nb: Pointer; page: gint); cdecl; external LIB_GTK;
function gtk_notebook_page_num(nb, child: Pointer): gint; cdecl; external LIB_GTK;
function gtk_notebook_get_current_page(nb: Pointer): gint; cdecl; external LIB_GTK;
procedure gtk_notebook_set_current_page(nb: Pointer; page: gint); cdecl; external LIB_GTK;
function gtk_notebook_get_n_pages(nb: Pointer): gint; cdecl; external LIB_GTK;
function gtk_notebook_get_nth_page(nb: Pointer; n: gint): Pointer; cdecl; external LIB_GTK;
procedure gtk_notebook_set_tab_pos(nb: Pointer; pos: gint); cdecl; external LIB_GTK;
procedure gtk_notebook_set_scrollable(nb: Pointer; v: gboolean); cdecl; external LIB_GTK;
procedure gtk_notebook_set_show_border(nb: Pointer; v: gboolean); cdecl; external LIB_GTK;
procedure gtk_notebook_set_show_tabs(nb: Pointer; v: gboolean); cdecl; external LIB_GTK;
procedure gtk_notebook_set_tab_reorderable(nb, child: Pointer; v: gboolean); cdecl; external LIB_GTK;
procedure gtk_notebook_set_tab_detachable(nb, child: Pointer; v: gboolean); cdecl; external LIB_GTK;
procedure gtk_notebook_set_group_name(nb: Pointer; name: PChar); cdecl; external LIB_GTK;
procedure gtk_notebook_set_action_widget(nb, w: Pointer; pack: gint); cdecl; external LIB_GTK;
procedure gtk_notebook_set_tab_label(nb, child, lbl: Pointer); cdecl; external LIB_GTK;
procedure gtk_notebook_next_page(nb: Pointer); cdecl; external LIB_GTK;
procedure gtk_notebook_prev_page(nb: Pointer); cdecl; external LIB_GTK;
procedure gtk_notebook_reorder_child(nb, child: Pointer; pos: gint); cdecl; external LIB_GTK;
procedure gtk_notebook_detach_tab(nb, child: Pointer); cdecl; external LIB_GTK;
procedure gtk_notebook_popup_enable(nb: Pointer); cdecl; external LIB_GTK;

{ label / image / button / entry }
function gtk_label_new(s: PChar): Pointer; cdecl; external LIB_GTK;
procedure gtk_label_set_text(l: Pointer; s: PChar); cdecl; external LIB_GTK;
function gtk_label_get_text(l: Pointer): PChar; cdecl; external LIB_GTK;
procedure gtk_label_set_markup(l: Pointer; s: PChar); cdecl; external LIB_GTK;
procedure gtk_label_set_xalign(l: Pointer; x: Single); cdecl; external LIB_GTK;
procedure gtk_label_set_yalign(l: Pointer; y: Single); cdecl; external LIB_GTK;
procedure gtk_label_set_angle(l: Pointer; a: gdouble); cdecl; external LIB_GTK;
procedure gtk_label_set_ellipsize(l: Pointer; m: gint); cdecl; external LIB_GTK;
procedure gtk_label_set_line_wrap(l: Pointer; v: gboolean); cdecl; external LIB_GTK;
procedure gtk_label_set_selectable(l: Pointer; v: gboolean); cdecl; external LIB_GTK;
procedure gtk_label_set_justify(l: Pointer; j: gint); cdecl; external LIB_GTK;
procedure gtk_label_set_max_width_chars(l: Pointer; n: gint); cdecl; external LIB_GTK;
procedure gtk_label_set_width_chars(l: Pointer; n: gint); cdecl; external LIB_GTK;
procedure gtk_label_set_mnemonic_widget(l, w: Pointer); cdecl; external LIB_GTK;
procedure gtk_label_set_use_markup(l: Pointer; v: gboolean); cdecl; external LIB_GTK;
function gtk_image_new_from_pixbuf(p: Pointer): Pointer; cdecl; external LIB_GTK;
function gtk_image_new_from_icon_name(name: PChar; size: gint): Pointer; cdecl; external LIB_GTK;
procedure gtk_image_set_from_pixbuf(i, p: Pointer); cdecl; external LIB_GTK;
procedure gtk_image_set_from_icon_name(i: Pointer; name: PChar; size: gint); cdecl; external LIB_GTK;
procedure gtk_image_set_pixel_size(i: Pointer; size: gint); cdecl; external LIB_GTK;
function gtk_button_new: Pointer; cdecl; external LIB_GTK;
function gtk_button_new_with_label(s: PChar): Pointer; cdecl; external LIB_GTK;
function gtk_button_new_with_mnemonic(s: PChar): Pointer; cdecl; external LIB_GTK;
function gtk_button_new_from_icon_name(name: PChar; size: gint): Pointer; cdecl; external LIB_GTK;
procedure gtk_button_set_label(b: Pointer; s: PChar); cdecl; external LIB_GTK;
procedure gtk_button_set_image(b, img: Pointer); cdecl; external LIB_GTK;
procedure gtk_button_set_always_show_image(b: Pointer; v: gboolean); cdecl; external LIB_GTK;
procedure gtk_button_set_relief(b: Pointer; r: gint); cdecl; external LIB_GTK;
procedure gtk_button_set_image_position(b: Pointer; p: gint); cdecl; external LIB_GTK;
procedure gtk_button_clicked(b: Pointer); cdecl; external LIB_GTK;
function gtk_toggle_button_new: Pointer; cdecl; external LIB_GTK;
function gtk_toggle_button_new_with_label(s: PChar): Pointer; cdecl; external LIB_GTK;
function gtk_toggle_button_get_active(b: Pointer): gboolean; cdecl; external LIB_GTK;
procedure gtk_toggle_button_set_active(b: Pointer; v: gboolean); cdecl; external LIB_GTK;
procedure gtk_toggle_button_set_mode(b: Pointer; draw_indicator: gboolean); cdecl; external LIB_GTK;
function gtk_check_button_new: Pointer; cdecl; external LIB_GTK;
function gtk_check_button_new_with_label(s: PChar): Pointer; cdecl; external LIB_GTK;
function gtk_check_button_new_with_mnemonic(s: PChar): Pointer; cdecl; external LIB_GTK;
function gtk_radio_button_new_with_label(group: PGSList; s: PChar): Pointer; cdecl; external LIB_GTK;
function gtk_radio_button_new_with_label_from_widget(w: Pointer; s: PChar): Pointer; cdecl; external LIB_GTK;
function gtk_link_button_new_with_label(uri, lbl: PChar): Pointer; cdecl; external LIB_GTK;
function gtk_menu_button_new: Pointer; cdecl; external LIB_GTK;
procedure gtk_menu_button_set_popup(b, menu: Pointer); cdecl; external LIB_GTK;
function gtk_switch_new: Pointer; cdecl; external LIB_GTK;
function gtk_switch_get_active(s: Pointer): gboolean; cdecl; external LIB_GTK;
procedure gtk_switch_set_active(s: Pointer; v: gboolean); cdecl; external LIB_GTK;
function gtk_entry_new: Pointer; cdecl; external LIB_GTK;
function gtk_search_entry_new: Pointer; cdecl; external LIB_GTK;
function gtk_entry_get_text(e: Pointer): PChar; cdecl; external LIB_GTK;
procedure gtk_entry_set_text(e: Pointer; s: PChar); cdecl; external LIB_GTK;
procedure gtk_entry_set_completion(e, c: Pointer); cdecl; external LIB_GTK;
function gtk_entry_completion_new: Pointer; cdecl; external LIB_GTK;
procedure gtk_entry_completion_set_model(c, model: Pointer); cdecl; external LIB_GTK;
procedure gtk_entry_completion_set_text_column(c: Pointer; col: gint); cdecl; external LIB_GTK;
procedure gtk_entry_completion_set_minimum_key_length(c: Pointer; len: gint); cdecl; external LIB_GTK;
procedure gtk_entry_completion_set_match_func(c: Pointer; func: Pointer; data: gpointer; notify: Pointer); cdecl; external LIB_GTK;
procedure gtk_entry_completion_set_popup_set_width(c: Pointer; v: gboolean); cdecl; external LIB_GTK;
function gtk_entry_completion_get_entry(c: Pointer): Pointer; cdecl; external LIB_GTK;
procedure gtk_cell_layout_pack_start(layout, cell: Pointer; expand: gboolean); cdecl; external LIB_GTK;
procedure gtk_cell_layout_add_attribute(layout, cell: Pointer; attr: PChar; column: gint); cdecl; external LIB_GTK;
procedure gtk_entry_set_placeholder_text(e: Pointer; s: PChar); cdecl; external LIB_GTK;
procedure gtk_entry_set_visibility(e: Pointer; v: gboolean); cdecl; external LIB_GTK;
procedure gtk_entry_set_width_chars(e: Pointer; n: gint); cdecl; external LIB_GTK;
procedure gtk_entry_set_activates_default(e: Pointer; v: gboolean); cdecl; external LIB_GTK;
procedure gtk_entry_set_icon_from_icon_name(e: Pointer; pos: gint; name: PChar); cdecl; external LIB_GTK;
procedure gtk_entry_set_input_purpose(e: Pointer; p: gint); cdecl; external LIB_GTK;
procedure gtk_entry_set_max_length(e: Pointer; n: gint); cdecl; external LIB_GTK;
procedure gtk_editable_select_region(e: Pointer; s, en: gint); cdecl; external LIB_GTK;
procedure gtk_editable_set_editable(e: Pointer; v: gboolean); cdecl; external LIB_GTK;
procedure gtk_editable_set_position(e: Pointer; p: gint); cdecl; external LIB_GTK;
function gtk_spin_button_new_with_range(min, max, step: gdouble): Pointer; cdecl; external LIB_GTK;
function gtk_spin_button_get_value_as_int(s: Pointer): gint; cdecl; external LIB_GTK;
function gtk_spin_button_get_value(s: Pointer): gdouble; cdecl; external LIB_GTK;
procedure gtk_spin_button_set_value(s: Pointer; v: gdouble); cdecl; external LIB_GTK;
procedure gtk_spin_button_set_digits(s: Pointer; d: guint); cdecl; external LIB_GTK;
procedure gtk_spin_button_update(s: Pointer); cdecl; external LIB_GTK;
function gtk_combo_box_text_new: Pointer; cdecl; external LIB_GTK;
function gtk_combo_box_text_new_with_entry: Pointer; cdecl; external LIB_GTK;
procedure gtk_combo_box_text_append_text(c: Pointer; s: PChar); cdecl; external LIB_GTK;
procedure gtk_combo_box_text_append(c: Pointer; id, s: PChar); cdecl; external LIB_GTK;
procedure gtk_combo_box_text_remove_all(c: Pointer); cdecl; external LIB_GTK;
function gtk_combo_box_text_get_active_text(c: Pointer): PChar; cdecl; external LIB_GTK;
function gtk_combo_box_get_active(c: Pointer): gint; cdecl; external LIB_GTK;
procedure gtk_combo_box_set_active(c: Pointer; i: gint); cdecl; external LIB_GTK;
function gtk_combo_box_get_active_id(c: Pointer): PChar; cdecl; external LIB_GTK;
function gtk_combo_box_set_active_id(c: Pointer; id: PChar): gboolean; cdecl; external LIB_GTK;
function gtk_progress_bar_new: Pointer; cdecl; external LIB_GTK;
procedure gtk_progress_bar_set_fraction(p: Pointer; f: gdouble); cdecl; external LIB_GTK;
procedure gtk_progress_bar_set_text(p: Pointer; s: PChar); cdecl; external LIB_GTK;
procedure gtk_progress_bar_set_show_text(p: Pointer; v: gboolean); cdecl; external LIB_GTK;
procedure gtk_progress_bar_pulse(p: Pointer); cdecl; external LIB_GTK;
function gtk_level_bar_new_for_interval(min, max: gdouble): Pointer; cdecl; external LIB_GTK;
procedure gtk_level_bar_set_value(l: Pointer; v: gdouble); cdecl; external LIB_GTK;
procedure gtk_level_bar_add_offset_value(l: Pointer; name: PChar; v: gdouble); cdecl; external LIB_GTK;
procedure gtk_level_bar_remove_offset_value(l: Pointer; name: PChar); cdecl; external LIB_GTK;
function gtk_spinner_new: Pointer; cdecl; external LIB_GTK;
procedure gtk_spinner_start(s: Pointer); cdecl; external LIB_GTK;
procedure gtk_spinner_stop(s: Pointer); cdecl; external LIB_GTK;
function gtk_scrollbar_new(orientation: gint; adj: Pointer): Pointer; cdecl; external LIB_GTK;
function gtk_scrollable_get_vadjustment(s: Pointer): Pointer; cdecl; external LIB_GTK;
function gtk_drawing_area_new: Pointer; cdecl; external LIB_GTK;
function gtk_font_button_new_with_font(font: PChar): Pointer; cdecl; external LIB_GTK;
function gtk_font_chooser_get_font(fc: Pointer): PChar; cdecl; external LIB_GTK;
procedure gtk_font_chooser_set_font(fc: Pointer; font: PChar); cdecl; external LIB_GTK;
procedure gtk_font_button_set_use_font(b: Pointer; v: gboolean); cdecl; external LIB_GTK;
function gtk_color_button_new_with_rgba(c: PGdkRGBA): Pointer; cdecl; external LIB_GTK;
procedure gtk_color_chooser_get_rgba(c: Pointer; rgba: PGdkRGBA); cdecl; external LIB_GTK;
function gtk_info_bar_new: Pointer; cdecl; external LIB_GTK;
function gtk_info_bar_get_content_area(b: Pointer): Pointer; cdecl; external LIB_GTK;
procedure gtk_info_bar_set_message_type(b: Pointer; t: gint); cdecl; external LIB_GTK;
function gtk_info_bar_add_button(b: Pointer; text: PChar; resp: gint): Pointer; cdecl; external LIB_GTK;
function gtk_statusbar_new: Pointer; cdecl; external LIB_GTK;

{ text view }
function gtk_text_view_new: Pointer; cdecl; external LIB_GTK;
function gtk_text_view_new_with_buffer(b: Pointer): Pointer; cdecl; external LIB_GTK;
function gtk_text_view_get_buffer(v: Pointer): Pointer; cdecl; external LIB_GTK;
procedure gtk_text_view_set_editable(v: Pointer; e: gboolean); cdecl; external LIB_GTK;
procedure gtk_text_view_set_monospace(v: Pointer; m: gboolean); cdecl; external LIB_GTK;
procedure gtk_text_view_set_wrap_mode(v: Pointer; m: gint); cdecl; external LIB_GTK;
procedure gtk_text_view_set_cursor_visible(v: Pointer; c: gboolean); cdecl; external LIB_GTK;
procedure gtk_text_view_set_left_margin(v: Pointer; m: gint); cdecl; external LIB_GTK;
procedure gtk_text_view_set_top_margin(v: Pointer; m: gint); cdecl; external LIB_GTK;
procedure gtk_text_view_scroll_to_mark(v, mark: Pointer; margin: gdouble; use_align: gboolean; xa, ya: gdouble); cdecl; external LIB_GTK;
function gtk_text_view_scroll_to_iter(v: Pointer; iter: PGtkTextIter; margin: gdouble; use_align: gboolean; xa, ya: gdouble): gboolean; cdecl; external LIB_GTK;
function gtk_text_buffer_new(table: Pointer): Pointer; cdecl; external LIB_GTK;
procedure gtk_text_buffer_set_text(b: Pointer; s: PChar; len: gint); cdecl; external LIB_GTK;
procedure gtk_text_buffer_get_start_iter(b: Pointer; it: PGtkTextIter); cdecl; external LIB_GTK;
procedure gtk_text_buffer_get_end_iter(b: Pointer; it: PGtkTextIter); cdecl; external LIB_GTK;
procedure gtk_text_buffer_get_bounds(b: Pointer; s, e: PGtkTextIter); cdecl; external LIB_GTK;
function gtk_text_buffer_get_text(b: Pointer; s, e: PGtkTextIter; hidden: gboolean): PChar; cdecl; external LIB_GTK;
procedure gtk_text_buffer_insert(b: Pointer; it: PGtkTextIter; s: PChar; len: gint); cdecl; external LIB_GTK;
procedure gtk_text_buffer_insert_with_tags_by_name(b: Pointer; it: PGtkTextIter; s: PChar; len: gint; first_tag: PChar); cdecl; varargs; external LIB_GTK;
function gtk_text_buffer_create_tag(b: Pointer; name: PChar; first_prop: PChar): Pointer; cdecl; varargs; external LIB_GTK;
function gtk_text_buffer_get_insert(b: Pointer): Pointer; cdecl; external LIB_GTK;
function gtk_text_buffer_create_mark(b: Pointer; name: PChar; it: PGtkTextIter; left: gboolean): Pointer; cdecl; external LIB_GTK;
procedure gtk_text_buffer_move_mark(b, mark: Pointer; it: PGtkTextIter); cdecl; external LIB_GTK;
procedure gtk_text_buffer_place_cursor(b: Pointer; it: PGtkTextIter); cdecl; external LIB_GTK;
procedure gtk_text_buffer_select_range(b: Pointer; ins, bound: PGtkTextIter); cdecl; external LIB_GTK;
function gtk_text_buffer_get_selection_bounds(b: Pointer; s, e: PGtkTextIter): gboolean; cdecl; external LIB_GTK;
procedure gtk_text_buffer_get_iter_at_mark(b: Pointer; it: PGtkTextIter; mark: Pointer); cdecl; external LIB_GTK;
procedure gtk_text_buffer_get_iter_at_line(b: Pointer; it: PGtkTextIter; line: gint); cdecl; external LIB_GTK;
function gtk_text_buffer_get_modified(b: Pointer): gboolean; cdecl; external LIB_GTK;
procedure gtk_text_buffer_set_modified(b: Pointer; v: gboolean); cdecl; external LIB_GTK;
procedure gtk_text_buffer_delete(b: Pointer; s, e: PGtkTextIter); cdecl; external LIB_GTK;
function gtk_text_buffer_get_line_count(b: Pointer): gint; cdecl; external LIB_GTK;
function gtk_text_buffer_get_char_count(b: Pointer): gint; cdecl; external LIB_GTK;
procedure gtk_text_buffer_begin_user_action(b: Pointer); cdecl; external LIB_GTK;
procedure gtk_text_buffer_end_user_action(b: Pointer); cdecl; external LIB_GTK;
function gtk_text_iter_get_line(it: PGtkTextIter): gint; cdecl; external LIB_GTK;
function gtk_text_iter_get_line_offset(it: PGtkTextIter): gint; cdecl; external LIB_GTK;
function gtk_text_iter_forward_search(it: PGtkTextIter; s: PChar; flags: gint; ms, me, limit: PGtkTextIter): gboolean; cdecl; external LIB_GTK;
function gtk_text_iter_backward_search(it: PGtkTextIter; s: PChar; flags: gint; ms, me, limit: PGtkTextIter): gboolean; cdecl; external LIB_GTK;

{ dialogs }
function gtk_dialog_new_with_buttons(title: PChar; parent: Pointer; flags: gint; first: PChar): Pointer; cdecl; varargs; external LIB_GTK;
function gtk_dialog_get_content_area(d: Pointer): Pointer; cdecl; external LIB_GTK;
function gtk_dialog_get_type: GType; cdecl; external LIB_GTK;
function gtk_notebook_get_type: GType; cdecl; external LIB_GTK;
function gtk_button_get_type: GType; cdecl; external LIB_GTK;
function gtk_container_get_type: GType; cdecl; external LIB_GTK;
function gtk_label_get_type: GType; cdecl; external LIB_GTK;
function gtk_window_get_type: GType; cdecl; external LIB_GTK;
function gtk_dialog_get_action_area(d: Pointer): Pointer; cdecl; external LIB_GTK;
function gtk_dialog_add_button(d: Pointer; text: PChar; resp: gint): Pointer; cdecl; external LIB_GTK;
function gtk_dialog_run(d: Pointer): gint; cdecl; external LIB_GTK;
procedure gtk_dialog_response(d: Pointer; resp: gint); cdecl; external LIB_GTK;
procedure gtk_dialog_set_default_response(d: Pointer; resp: gint); cdecl; external LIB_GTK;
function gtk_dialog_get_widget_for_response(d: Pointer; resp: gint): Pointer; cdecl; external LIB_GTK;
function gtk_message_dialog_new(parent: Pointer; flags, mtype, buttons: gint; fmt: PChar): Pointer; cdecl; varargs; external LIB_GTK;
procedure gtk_message_dialog_format_secondary_text(d: Pointer; fmt: PChar); cdecl; varargs; external LIB_GTK;
function gtk_file_chooser_native_new(title: PChar; parent: Pointer; action: gint; accept, cancel: PChar): Pointer; cdecl; external LIB_GTK;
function gtk_native_dialog_run(d: Pointer): gint; cdecl; external LIB_GTK;
procedure gtk_native_dialog_set_modal(d: Pointer; m: gboolean); cdecl; external LIB_GTK;
function gtk_file_chooser_get_filename(c: Pointer): PChar; cdecl; external LIB_GTK;
function gtk_file_chooser_get_filenames(c: Pointer): PGSList; cdecl; external LIB_GTK;
procedure gtk_file_chooser_set_select_multiple(c: Pointer; v: gboolean); cdecl; external LIB_GTK;
function gtk_file_chooser_set_current_folder(c: Pointer; f: PChar): gboolean; cdecl; external LIB_GTK;
procedure gtk_file_chooser_set_current_name(c: Pointer; n: PChar); cdecl; external LIB_GTK;
function gtk_file_chooser_set_filename(c: Pointer; f: PChar): gboolean; cdecl; external LIB_GTK;
procedure gtk_file_chooser_set_do_overwrite_confirmation(c: Pointer; v: gboolean); cdecl; external LIB_GTK;
procedure gtk_file_chooser_set_show_hidden(c: Pointer; v: gboolean); cdecl; external LIB_GTK;
function gtk_about_dialog_new: Pointer; cdecl; external LIB_GTK;
procedure gtk_about_dialog_set_program_name(d: Pointer; s: PChar); cdecl; external LIB_GTK;
procedure gtk_about_dialog_set_version(d: Pointer; s: PChar); cdecl; external LIB_GTK;
procedure gtk_about_dialog_set_comments(d: Pointer; s: PChar); cdecl; external LIB_GTK;
procedure gtk_about_dialog_set_copyright(d: Pointer; s: PChar); cdecl; external LIB_GTK;
procedure gtk_about_dialog_set_logo(d: Pointer; p: Pointer); cdecl; external LIB_GTK;
procedure gtk_about_dialog_set_license_type(d: Pointer; t: gint); cdecl; external LIB_GTK;
procedure gtk_about_dialog_set_website(d: Pointer; s: PChar); cdecl; external LIB_GTK;
procedure gtk_about_dialog_set_authors(d: Pointer; a: PPChar); cdecl; external LIB_GTK;
function gtk_show_uri_on_window(parent: Pointer; uri: PChar; ts: guint32; error: PPGError): gboolean; cdecl; external LIB_GTK;

{ menus }
function gtk_menu_bar_new: Pointer; cdecl; external LIB_GTK;
function gtk_menu_new: Pointer; cdecl; external LIB_GTK;
function gtk_menu_item_new_with_label(s: PChar): Pointer; cdecl; external LIB_GTK;
function gtk_menu_item_new_with_mnemonic(s: PChar): Pointer; cdecl; external LIB_GTK;
function gtk_menu_item_new: Pointer; cdecl; external LIB_GTK;
procedure gtk_menu_item_set_submenu(i, m: Pointer); cdecl; external LIB_GTK;
function gtk_menu_item_get_submenu(i: Pointer): Pointer; cdecl; external LIB_GTK;
procedure gtk_menu_item_activate(i: Pointer); cdecl; external LIB_GTK;
procedure gtk_menu_item_set_label(i: Pointer; s: PChar); cdecl; external LIB_GTK;
function gtk_separator_menu_item_new: Pointer; cdecl; external LIB_GTK;
function gtk_check_menu_item_new_with_label(s: PChar): Pointer; cdecl; external LIB_GTK;
function gtk_check_menu_item_new_with_mnemonic(s: PChar): Pointer; cdecl; external LIB_GTK;
function gtk_check_menu_item_get_active(i: Pointer): gboolean; cdecl; external LIB_GTK;
procedure gtk_check_menu_item_set_active(i: Pointer; v: gboolean); cdecl; external LIB_GTK;
procedure gtk_check_menu_item_set_draw_as_radio(i: Pointer; v: gboolean); cdecl; external LIB_GTK;
function gtk_image_menu_item_new_with_mnemonic(s: PChar): Pointer; cdecl; external LIB_GTK;
procedure gtk_image_menu_item_set_image(i, img: Pointer); cdecl; external LIB_GTK;
procedure gtk_image_menu_item_set_always_show_image(i: Pointer; v: gboolean); cdecl; external LIB_GTK;
procedure gtk_menu_shell_append(shell, item: Pointer); cdecl; external LIB_GTK;
procedure gtk_menu_popup_at_pointer(m: Pointer; ev: Pointer); cdecl; external LIB_GTK;
procedure gtk_menu_popup_at_widget(m, w: Pointer; wa, ma: gint; ev: Pointer); cdecl; external LIB_GTK;
procedure gtk_menu_attach_to_widget(m, w: Pointer; detacher: Pointer); cdecl; external LIB_GTK;
procedure gtk_menu_set_accel_group(m, g: Pointer); cdecl; external LIB_GTK;
procedure gtk_menu_set_reserve_toggle_size(m: Pointer; v: gboolean); cdecl; external LIB_GTK;

{ tree / list }
function gtk_tree_store_newv(n: gint; types: PPtrUInt): Pointer; cdecl; external LIB_GTK;
function gtk_list_store_newv(n: gint; types: PPtrUInt): Pointer; cdecl; external LIB_GTK;
procedure gtk_tree_store_append(s: Pointer; it, parent: PGtkTreeIter); cdecl; external LIB_GTK;
procedure gtk_tree_store_set(s: Pointer; it: PGtkTreeIter); cdecl; varargs; external LIB_GTK;
procedure gtk_tree_store_clear(s: Pointer); cdecl; external LIB_GTK;
function gtk_tree_store_remove(s: Pointer; it: PGtkTreeIter): gboolean; cdecl; external LIB_GTK;
procedure gtk_list_store_append(s: Pointer; it: PGtkTreeIter); cdecl; external LIB_GTK;
procedure gtk_list_store_set(s: Pointer; it: PGtkTreeIter); cdecl; varargs; external LIB_GTK;
procedure gtk_list_store_clear(s: Pointer); cdecl; external LIB_GTK;
function gtk_list_store_remove(s: Pointer; it: PGtkTreeIter): gboolean; cdecl; external LIB_GTK;
procedure gtk_tree_model_get(m: Pointer; it: PGtkTreeIter); cdecl; varargs; external LIB_GTK;
function gtk_tree_model_get_iter(m: Pointer; it: PGtkTreeIter; path: Pointer): gboolean; cdecl; external LIB_GTK;
function gtk_tree_model_get_iter_first(m: Pointer; it: PGtkTreeIter): gboolean; cdecl; external LIB_GTK;
function gtk_tree_model_iter_next(m: Pointer; it: PGtkTreeIter): gboolean; cdecl; external LIB_GTK;
function gtk_tree_model_iter_children(m: Pointer; it, parent: PGtkTreeIter): gboolean; cdecl; external LIB_GTK;
function gtk_tree_model_iter_n_children(m: Pointer; it: PGtkTreeIter): gint; cdecl; external LIB_GTK;
function gtk_tree_model_iter_parent(m: Pointer; it, child: PGtkTreeIter): gboolean; cdecl; external LIB_GTK;
function gtk_tree_model_get_path(m: Pointer; it: PGtkTreeIter): Pointer; cdecl; external LIB_GTK;
procedure gtk_tree_path_free(p: Pointer); cdecl; external LIB_GTK;
function gtk_tree_path_new_first: Pointer; cdecl; external LIB_GTK;
function gtk_tree_path_new_from_string(s: PChar): Pointer; cdecl; external LIB_GTK;
function gtk_tree_view_new_with_model(m: Pointer): Pointer; cdecl; external LIB_GTK;
procedure gtk_tree_view_set_model(v, m: Pointer); cdecl; external LIB_GTK;
function gtk_tree_view_get_model(v: Pointer): Pointer; cdecl; external LIB_GTK;
function gtk_tree_view_append_column(v, c: Pointer): gint; cdecl; external LIB_GTK;
function gtk_tree_view_get_selection(v: Pointer): Pointer; cdecl; external LIB_GTK;
procedure gtk_tree_view_set_headers_visible(v: Pointer; h: gboolean); cdecl; external LIB_GTK;
procedure gtk_tree_view_set_enable_search(v: Pointer; e: gboolean); cdecl; external LIB_GTK;
procedure gtk_tree_view_set_search_column(v: Pointer; c: gint); cdecl; external LIB_GTK;
procedure gtk_tree_view_expand_all(v: Pointer); cdecl; external LIB_GTK;
function gtk_tree_view_expand_row(v, path: Pointer; all: gboolean): gboolean; cdecl; external LIB_GTK;
function gtk_tree_view_collapse_row(v, path: Pointer): gboolean; cdecl; external LIB_GTK;
function gtk_tree_view_row_expanded(v, path: Pointer): gboolean; cdecl; external LIB_GTK;
procedure gtk_tree_view_expand_to_path(v, path: Pointer); cdecl; external LIB_GTK;
function gtk_tree_view_get_path_at_pos(v: Pointer; x, y: gint; path: PPointer; col: PPointer; cx, cy: Pgint): gboolean; cdecl; external LIB_GTK;
procedure gtk_tree_view_set_cursor(v, path, col: Pointer; edit: gboolean); cdecl; external LIB_GTK;
procedure gtk_tree_view_scroll_to_cell(v, path, col: Pointer; use_align: gboolean; ra, ca: Single); cdecl; external LIB_GTK;
procedure gtk_tree_view_set_rubber_banding(v: Pointer; e: gboolean); cdecl; external LIB_GTK;
procedure gtk_tree_view_set_grid_lines(v: Pointer; g: gint); cdecl; external LIB_GTK;
procedure gtk_tree_view_set_level_indentation(v: Pointer; i: gint); cdecl; external LIB_GTK;
procedure gtk_tree_view_set_tooltip_column(v: Pointer; c: gint); cdecl; external LIB_GTK;
procedure gtk_tree_view_set_activate_on_single_click(v: Pointer; s: gboolean); cdecl; external LIB_GTK;
procedure gtk_tree_view_enable_model_drag_source(v: Pointer; mask: gint; targets: PGtkTargetEntry; n: gint; actions: gint); cdecl; external LIB_GTK;
procedure gtk_tree_view_enable_model_drag_dest(v: Pointer; targets: PGtkTargetEntry; n: gint; actions: gint); cdecl; external LIB_GTK;
function gtk_tree_view_get_dest_row_at_pos(v: Pointer; x, y: gint; path: PPointer; pos: Pgint): gboolean; cdecl; external LIB_GTK;
procedure gtk_tree_view_columns_autosize(v: Pointer); cdecl; external LIB_GTK;
function gtk_tree_view_column_new: Pointer; cdecl; external LIB_GTK;
procedure gtk_tree_view_column_set_title(c: Pointer; t: PChar); cdecl; external LIB_GTK;
procedure gtk_tree_view_column_pack_start(c, cell: Pointer; expand: gboolean); cdecl; external LIB_GTK;
procedure gtk_tree_view_column_add_attribute(c, cell: Pointer; attr: PChar; col: gint); cdecl; external LIB_GTK;
procedure gtk_tree_view_column_set_sort_column_id(c: Pointer; id: gint); cdecl; external LIB_GTK;
procedure gtk_tree_view_column_set_resizable(c: Pointer; r: gboolean); cdecl; external LIB_GTK;
procedure gtk_tree_view_column_set_expand(c: Pointer; e: gboolean); cdecl; external LIB_GTK;
procedure gtk_tree_view_column_set_sizing(c: Pointer; t: gint); cdecl; external LIB_GTK;
procedure gtk_tree_view_column_set_fixed_width(c: Pointer; w: gint); cdecl; external LIB_GTK;
procedure gtk_tree_view_column_set_min_width(c: Pointer; w: gint); cdecl; external LIB_GTK;
procedure gtk_tree_view_column_set_spacing(c: Pointer; s: gint); cdecl; external LIB_GTK;
function gtk_cell_renderer_text_new: Pointer; cdecl; external LIB_GTK;
function gtk_cell_renderer_pixbuf_new: Pointer; cdecl; external LIB_GTK;
function gtk_cell_renderer_toggle_new: Pointer; cdecl; external LIB_GTK;
function gtk_cell_renderer_progress_new: Pointer; cdecl; external LIB_GTK;
procedure gtk_cell_renderer_set_padding(c: Pointer; x, y: gint); cdecl; external LIB_GTK;
procedure gtk_cell_renderer_set_alignment(c: Pointer; x, y: Single); cdecl; external LIB_GTK;
function gtk_tree_selection_get_selected(s: Pointer; model: PPointer; it: PGtkTreeIter): gboolean; cdecl; external LIB_GTK;
function gtk_tree_selection_get_selected_rows(s: Pointer; model: PPointer): PGList; cdecl; external LIB_GTK;
procedure gtk_tree_selection_set_mode(s: Pointer; m: gint); cdecl; external LIB_GTK;
procedure gtk_tree_selection_select_iter(s: Pointer; it: PGtkTreeIter); cdecl; external LIB_GTK;
procedure gtk_tree_selection_select_path(s, path: Pointer); cdecl; external LIB_GTK;
procedure gtk_tree_selection_unselect_all(s: Pointer); cdecl; external LIB_GTK;
function gtk_tree_selection_path_is_selected(s, path: Pointer): gboolean; cdecl; external LIB_GTK;
function gtk_tree_selection_count_selected_rows(s: Pointer): gint; cdecl; external LIB_GTK;
procedure gtk_tree_sortable_set_sort_column_id(s: Pointer; id: gint; order: gint); cdecl; external LIB_GTK;
procedure gtk_tree_sortable_set_sort_func(s: Pointer; id: gint; f: Pointer; data: Pointer; destroy: Pointer); cdecl; external LIB_GTK;
function gtk_tree_sortable_get_sort_column_id(s: Pointer; id: Pgint; order: Pgint): gboolean; cdecl; external LIB_GTK;

{ clipboard / dnd / selection }
function gtk_clipboard_get(atom: Pointer): Pointer; cdecl; external LIB_GTK;
procedure gtk_clipboard_set_text(c: Pointer; s: PChar; len: gint); cdecl; external LIB_GTK;
function gtk_clipboard_wait_for_text(c: Pointer): PChar; cdecl; external LIB_GTK;
procedure gtk_drag_dest_set(w: Pointer; flags: gint; targets: PGtkTargetEntry; n: gint; actions: gint); cdecl; external LIB_GTK;
procedure gtk_drag_source_set(w: Pointer; mask: gint; targets: PGtkTargetEntry; n: gint; actions: gint); cdecl; external LIB_GTK;
procedure gtk_drag_finish(ctx: Pointer; success, del: gboolean; time: guint32); cdecl; external LIB_GTK;
function gtk_selection_data_get_uris(sd: Pointer): PPChar; cdecl; external LIB_GTK;
function gtk_selection_data_set_uris(sd: Pointer; uris: PPChar): gboolean; cdecl; external LIB_GTK;
function gtk_selection_data_get_text(sd: Pointer): PChar; cdecl; external LIB_GTK;
function gtk_selection_data_set_text(sd: Pointer; s: PChar; len: gint): gboolean; cdecl; external LIB_GTK;
function gtk_selection_data_get_data(sd: Pointer): PChar; cdecl; external LIB_GTK;
function gtk_selection_data_get_length(sd: Pointer): gint; cdecl; external LIB_GTK;
procedure gtk_selection_data_set(sd: Pointer; atype: Pointer; format: gint; data: PChar; len: gint); cdecl; external LIB_GTK;
function gtk_selection_data_get_target(sd: Pointer): Pointer; cdecl; external LIB_GTK;
function gtk_drag_get_source_widget(ctx: Pointer): Pointer; cdecl; external LIB_GTK;

{ icon theme }
function gtk_icon_theme_get_default: Pointer; cdecl; external LIB_GTK;
function gtk_icon_theme_new: Pointer; cdecl; external LIB_GTK;
procedure gtk_icon_theme_set_custom_theme(t: Pointer; name: PChar); cdecl; external LIB_GTK;
function gtk_icon_theme_load_icon(t: Pointer; name: PChar; size: gint; flags: gint; error: PPGError): Pointer; cdecl; external LIB_GTK;
function gtk_icon_theme_has_icon(t: Pointer; name: PChar): gboolean; cdecl; external LIB_GTK;
procedure gtk_icon_theme_append_search_path(t: Pointer; path: PChar); cdecl; external LIB_GTK;

{ ---------------- VTE ---------------- }
function vte_terminal_new: Pointer; cdecl; external LIB_VTE;
procedure vte_terminal_spawn_async(t: Pointer; ptyflags: gint; wd: PChar; argv, envv: PPChar; spawnflags: gint;
  setup, setupdata, setupdestroy: Pointer; timeout: gint; cancellable: Pointer; cb: TVteSpawnCB; data: gpointer); cdecl; external LIB_VTE;
procedure vte_terminal_feed(t: Pointer; data: PChar; len: gssize); cdecl; external LIB_VTE;
procedure vte_terminal_feed_child(t: Pointer; data: PChar; len: gssize); cdecl; external LIB_VTE;
procedure vte_terminal_set_font(t: Pointer; desc: Pointer); cdecl; external LIB_VTE;
function vte_terminal_get_font(t: Pointer): Pointer; cdecl; external LIB_VTE;
procedure vte_terminal_set_font_scale(t: Pointer; s: gdouble); cdecl; external LIB_VTE;
function vte_terminal_get_font_scale(t: Pointer): gdouble; cdecl; external LIB_VTE;
procedure vte_terminal_set_colors(t: Pointer; fg, bg: PGdkRGBA; palette: PGdkRGBA; size: gsize); cdecl; external LIB_VTE;
procedure vte_terminal_set_color_cursor(t: Pointer; c: PGdkRGBA); cdecl; external LIB_VTE;
procedure vte_terminal_set_color_cursor_foreground(t: Pointer; c: PGdkRGBA); cdecl; external LIB_VTE;
procedure vte_terminal_set_color_highlight(t: Pointer; c: PGdkRGBA); cdecl; external LIB_VTE;
procedure vte_terminal_set_color_highlight_foreground(t: Pointer; c: PGdkRGBA); cdecl; external LIB_VTE;
procedure vte_terminal_set_color_bold(t: Pointer; c: PGdkRGBA); cdecl; external LIB_VTE;
procedure vte_terminal_set_bold_is_bright(t: Pointer; v: gboolean); cdecl; external LIB_VTE;
procedure vte_terminal_set_scrollback_lines(t: Pointer; n: glong); cdecl; external LIB_VTE;
procedure vte_terminal_set_cursor_shape(t: Pointer; s: gint); cdecl; external LIB_VTE;
procedure vte_terminal_set_cursor_blink_mode(t: Pointer; m: gint); cdecl; external LIB_VTE;
procedure vte_terminal_set_audible_bell(t: Pointer; v: gboolean); cdecl; external LIB_VTE;
procedure vte_terminal_set_scroll_on_output(t: Pointer; v: gboolean); cdecl; external LIB_VTE;
procedure vte_terminal_set_scroll_on_keystroke(t: Pointer; v: gboolean); cdecl; external LIB_VTE;
procedure vte_terminal_set_mouse_autohide(t: Pointer; v: gboolean); cdecl; external LIB_VTE;
procedure vte_terminal_set_allow_hyperlink(t: Pointer; v: gboolean); cdecl; external LIB_VTE;
procedure vte_terminal_set_backspace_binding(t: Pointer; b: gint); cdecl; external LIB_VTE;
procedure vte_terminal_set_delete_binding(t: Pointer; b: gint); cdecl; external LIB_VTE;
procedure vte_terminal_set_word_char_exceptions(t: Pointer; s: PChar); cdecl; external LIB_VTE;
procedure vte_terminal_copy_clipboard_format(t: Pointer; fmt: gint); cdecl; external LIB_VTE;
procedure vte_terminal_copy_primary(t: Pointer); cdecl; external LIB_VTE;
procedure vte_terminal_paste_clipboard(t: Pointer); cdecl; external LIB_VTE;
procedure vte_terminal_paste_primary(t: Pointer); cdecl; external LIB_VTE;
procedure vte_terminal_paste_text(t: Pointer; s: PChar); cdecl; external LIB_VTE;
procedure vte_terminal_select_all(t: Pointer); cdecl; external LIB_VTE;
procedure vte_terminal_unselect_all(t: Pointer); cdecl; external LIB_VTE;
function vte_terminal_get_has_selection(t: Pointer): gboolean; cdecl; external LIB_VTE;
function vte_terminal_get_text_selected(t: Pointer; fmt: gint): PChar; cdecl; external LIB_VTE;
procedure vte_terminal_reset(t: Pointer; clear_tabstops, clear_history: gboolean); cdecl; external LIB_VTE;
procedure vte_terminal_search_set_regex(t: Pointer; regex: Pointer; flags: guint32); cdecl; external LIB_VTE;
function vte_terminal_search_find_next(t: Pointer): gboolean; cdecl; external LIB_VTE;
function vte_terminal_search_find_previous(t: Pointer): gboolean; cdecl; external LIB_VTE;
procedure vte_terminal_search_set_wrap_around(t: Pointer; v: gboolean); cdecl; external LIB_VTE;
function vte_regex_new_for_search(pattern: PChar; len: gssize; flags: guint32; error: PPGError): Pointer; cdecl; external LIB_VTE;
function vte_regex_new_for_match(pattern: PChar; len: gssize; flags: guint32; error: PPGError): Pointer; cdecl; external LIB_VTE;
function vte_regex_unref(r: Pointer): Pointer; cdecl; external LIB_VTE;
function vte_terminal_match_add_regex(t: Pointer; regex: Pointer; flags: guint32): gint; cdecl; external LIB_VTE;
procedure vte_terminal_match_set_cursor_name(t: Pointer; tag: gint; name: PChar); cdecl; external LIB_VTE;
function vte_terminal_match_check_event(t: Pointer; ev: Pointer; tag: Pgint): PChar; cdecl; external LIB_VTE;
function vte_terminal_hyperlink_check_event(t: Pointer; ev: Pointer): PChar; cdecl; external LIB_VTE;
function vte_terminal_get_current_directory_uri(t: Pointer): PChar; cdecl; external LIB_VTE;
function vte_terminal_get_window_title(t: Pointer): PChar; cdecl; external LIB_VTE;
function vte_terminal_write_contents_sync(t: Pointer; stream: Pointer; flags: gint; cancellable: Pointer; error: PPGError): gboolean; cdecl; external LIB_VTE;
function vte_terminal_get_text_format(t: Pointer; fmt: gint): PChar; cdecl; external LIB_VTE;
function vte_terminal_get_column_count(t: Pointer): glong; cdecl; external LIB_VTE;
procedure vte_terminal_get_cursor_position(t: Pointer; col, row: Pointer); cdecl; external LIB_VTE;
function vte_terminal_get_text_range_format(t: Pointer; fmt: gint; start_row, start_col, end_row, end_col: glong;
  length: PPtrUInt): PChar; cdecl; external LIB_VTE;
function vte_terminal_get_row_count(t: Pointer): glong; cdecl; external LIB_VTE;
procedure vte_terminal_set_size(t: Pointer; cols, rows: glong); cdecl; external LIB_VTE;
procedure vte_terminal_set_cell_height_scale(t: Pointer; s: gdouble); cdecl; external LIB_VTE;
procedure vte_terminal_set_enable_bidi(t: Pointer; v: gboolean); cdecl; external LIB_VTE;
procedure vte_terminal_set_input_enabled(t: Pointer; v: gboolean); cdecl; external LIB_VTE;
function vte_get_minor_version: guint; cdecl; external LIB_VTE;

{ ---------------- helpers ---------------- }
function Connect(obj: Pointer; const sig: string; cb: Pointer; data: Pointer = nil): gulong;
function ConnectAfter(obj: Pointer; const sig: string; cb: Pointer; data: Pointer = nil): gulong;
function CStr(p: PChar): string;
function TakeStr(p: PChar): string;     { converts and g_free()s }
function ErrMsg(var e: PGError): string; { converts and frees GError }
function MarkupEscape(const s: string): string;
function EventKeyval(ev: Pointer): guint;
function EventState(ev: Pointer): guint;
function EventButton(ev: Pointer): guint;
{ canonical C boolean (0 / 1) for varargs and GValues }
function GBool(B: Boolean): gint; inline;
procedure g_signal_handlers_block_by_func(instance: gpointer; func: Pointer; data: gpointer);
procedure g_signal_handlers_unblock_by_func(instance: gpointer; func: Pointer; data: gpointer);
procedure DestroyChildren(Container: Pointer);

implementation

function GDK_SELECTION_CLIPBOARD: Pointer; inline;
begin
  Result := Pointer(PtrUInt(69));
end;

function GDK_SELECTION_PRIMARY: Pointer; inline;
begin
  Result := Pointer(PtrUInt(1));
end;

function Connect(obj: Pointer; const sig: string; cb: Pointer; data: Pointer): gulong;
begin
  Result := g_signal_connect_data(obj, PChar(sig), cb, data, nil, 0);
end;

function ConnectAfter(obj: Pointer; const sig: string; cb: Pointer; data: Pointer): gulong;
begin
  Result := g_signal_connect_data(obj, PChar(sig), cb, data, nil, G_CONNECT_AFTER);
end;

function CStr(p: PChar): string;
begin
  if p = nil then Result := '' else Result := AnsiString(p);
end;

function TakeStr(p: PChar): string;
begin
  if p = nil then Exit('');
  Result := AnsiString(p);
  g_free(p);
end;

function ErrMsg(var e: PGError): string;
begin
  if e = nil then Exit('');
  Result := CStr(e^.message);
  g_error_free(e);
  e := nil;
end;

function MarkupEscape(const s: string): string;
begin
  Result := TakeStr(g_markup_escape_text(PChar(s), -1));
end;

function EventKeyval(ev: Pointer): guint;
begin
  Result := 0;
  if ev <> nil then gdk_event_get_keyval(ev, @Result);
end;

function EventState(ev: Pointer): guint;
begin
  Result := 0;
  if ev <> nil then gdk_event_get_state(ev, @Result);
end;

procedure g_signal_handlers_block_by_func(instance: gpointer; func: Pointer; data: gpointer);
begin
  g_signal_handlers_block_matched(instance, G_SIGNAL_MATCH_FUNC or G_SIGNAL_MATCH_DATA, 0, 0, nil, func, data);
end;

procedure g_signal_handlers_unblock_by_func(instance: gpointer; func: Pointer; data: gpointer);
begin
  g_signal_handlers_unblock_matched(instance, G_SIGNAL_MATCH_FUNC or G_SIGNAL_MATCH_DATA, 0, 0, nil, func, data);
end;

function GBool(B: Boolean): gint; inline;
begin
  Result := Ord(B);
end;

procedure DestroyChildren(Container: Pointer);
var
  lst, it: PGList;
begin
  lst := gtk_container_get_children(Container);
  it := lst;
  while it <> nil do
  begin
    gtk_widget_destroy(it^.data);
    it := it^.next;
  end;
  g_list_free(lst);
end;

function EventButton(ev: Pointer): guint;
begin
  Result := 0;
  if ev <> nil then gdk_event_get_button(ev, @Result);
end;

end.

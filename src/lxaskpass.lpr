{ LinXterm - SSH_ASKPASS helper.
  - returns the stored session password once (file given by LINXTERM_PASSFILE,
    deleted after the first read);
  - otherwise shows a graphical password / confirmation dialog. }
program lxaskpass;

{$mode objfpc}{$H+}

uses
  cthreads, SysUtils, BaseUnix, lxgtk;

function IsSecretPrompt(const P: string): Boolean;
var
  l: string;
begin
  l := LowerCase(P);
  Result := (Pos('password', l) > 0) or (Pos('passphrase', l) > 0) or (Pos('mot de passe', l) > 0);
end;

function ReadAndDelete(const FileName: string; out Content: string): Boolean;
var
  f: file;
  n: Int64;
begin
  Result := False;
  Content := '';
  if (FileName = '') or not FileExists(FileName) then Exit;
  AssignFile(f, FileName);
  {$I-}
  Reset(f, 1);
  {$I+}
  if IOResult <> 0 then Exit;
  n := FileSize(f);
  SetLength(Content, n);
  if n > 0 then BlockRead(f, Content[1], n);
  CloseFile(f);
  DeleteFile(FileName);
  Result := True;
end;

procedure Output(const S: string);
var
  t: string;
begin
  t := S + #10;
  fpWrite(1, t[1], Length(t));
end;

function Confirm(const Prompt: string): Boolean;
var
  d: Pointer;
begin
  d := gtk_message_dialog_new(nil, GTK_DIALOG_MODAL, GTK_MESSAGE_QUESTION, GTK_BUTTONS_YES_NO, '%s',
    PChar('LinXterm - SSH'));
  gtk_message_dialog_format_secondary_text(d, '%s', PChar(Prompt));
  gtk_window_set_title(d, 'LinXterm - SSH');
  gtk_window_set_keep_above(d, True);
  gtk_window_set_position(d, GTK_WIN_POS_CENTER);
  Result := gtk_dialog_run(d) = GTK_RESPONSE_YES;
  gtk_widget_destroy(d);
end;

procedure Info(const Prompt: string);
var
  d: Pointer;
begin
  d := gtk_message_dialog_new(nil, GTK_DIALOG_MODAL, GTK_MESSAGE_INFO, GTK_BUTTONS_OK, '%s', PChar('LinXterm - SSH'));
  gtk_message_dialog_format_secondary_text(d, '%s', PChar(Prompt));
  gtk_window_set_keep_above(d, True);
  gtk_window_set_position(d, GTK_WIN_POS_CENTER);
  gtk_dialog_run(d);
  gtk_widget_destroy(d);
end;

function AskSecret(const Prompt: string; Hidden: Boolean; out Value: string): Boolean;
var
  d, area, box, lbl, entry, hb, icon: Pointer;
begin
  d := gtk_dialog_new_with_buttons('LinXterm - SSH authentication', nil, GTK_DIALOG_MODAL,
    '_Cancel', GTK_RESPONSE_CANCEL, '_OK', GTK_RESPONSE_OK, nil);
  gtk_window_set_keep_above(d, True);
  gtk_window_set_position(d, GTK_WIN_POS_CENTER);
  gtk_dialog_set_default_response(d, GTK_RESPONSE_OK);
  area := gtk_dialog_get_content_area(d);
  hb := gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 12);
  gtk_container_set_border_width(hb, 12);
  icon := gtk_image_new_from_icon_name('dialog-password', GTK_ICON_SIZE_DIALOG);
  gtk_widget_set_valign(icon, GTK_ALIGN_START);
  gtk_box_pack_start(hb, icon, False, False, 0);
  box := gtk_box_new(GTK_ORIENTATION_VERTICAL, 8);
  lbl := gtk_label_new(PChar(Prompt));
  gtk_label_set_xalign(lbl, 0);
  gtk_label_set_line_wrap(lbl, True);
  gtk_label_set_max_width_chars(lbl, 60);
  gtk_box_pack_start(box, lbl, False, False, 0);
  entry := gtk_entry_new;
  gtk_entry_set_visibility(entry, not Hidden);
  if Hidden then gtk_entry_set_input_purpose(entry, GTK_INPUT_PURPOSE_PASSWORD);
  gtk_entry_set_activates_default(entry, True);
  gtk_entry_set_width_chars(entry, 36);
  gtk_box_pack_start(box, entry, False, False, 0);
  gtk_box_pack_start(hb, box, True, True, 0);
  gtk_container_add(area, hb);
  gtk_widget_show_all(d);
  gtk_widget_grab_focus(entry);
  Result := gtk_dialog_run(d) = GTK_RESPONSE_OK;
  if Result then Value := CStr(gtk_entry_get_text(entry)) else Value := '';
  gtk_widget_destroy(d);
end;

var
  prompt, mode, pw, v: string;
begin
  prompt := ParamStr(1);
  mode := LowerCase(GetEnvironmentVariable('SSH_ASKPASS_PROMPT'));
  if (mode = '') and IsSecretPrompt(prompt) then
    if ReadAndDelete(GetEnvironmentVariable('LINXTERM_PASSFILE'), pw) then
    begin
      Output(pw);
      Halt(0);
    end;
  gtk_init(nil, nil);
  if mode = 'confirm' then
  begin
    if Confirm(prompt) then Halt(0) else Halt(1);
  end;
  if mode = 'none' then
  begin
    Info(prompt);
    Halt(0);
  end;
  if Pos('(yes/no', prompt) > 0 then
  begin
    if Confirm(prompt) then Output('yes') else Output('no');
    Halt(0);
  end;
  if AskSecret(prompt, IsSecretPrompt(prompt) or (Pos('pin', LowerCase(prompt)) > 0) or
    (Pos('code', LowerCase(prompt)) > 0), v) then
  begin
    Output(v);
    Halt(0);
  end;
  Halt(1);
end.

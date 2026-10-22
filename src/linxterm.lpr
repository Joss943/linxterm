{ LinXterm - an enhanced terminal for Linux with the MobaXterm interface.
  Object Pascal (Free Pascal) + GTK 3 + VTE. }
program linxterm;

{$mode objfpc}{$H+}

uses
  cthreads, cwstring, Classes, SysUtils,
  lxgtk, lxutil, lxconfig, lxtabs, lxterminal, lxmainwin,
  lxsftppanel, lxfiletab, lxremote, lxeditor, lxmacros, lxtools, lxservers, lxtunnels, lxpackages, lxsettingsdlg, lxgames;

begin
  Settings := TSettings.Create;
  Settings.Load;
  Store := TSessionStore.Create;
  Store.Load;
  RunApplication;
end.

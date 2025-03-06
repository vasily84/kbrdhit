unit Unit1;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls,
  LCLType,LCLIntf,
  BaseUnix, Termio;
const
  keybrdPath = '/dev/input/by-path/platform-i8042-serio-0-event-kbd';
  mousePath = '/dev/input/by-path/platform-i8042-serio-1-event-mouse';
  BTN_LEFT = $110;
  BTN_RIGHT	=	$111;
  KEY_UP = 103;
  KEY_PAGEUP = 104;
  KEY_LEFT = 105;
  KEY_RIGHT = 106;

type

  { TForm1 }

  TInput_Event = packed record
    Time: timeval;
    etype: Word;
    code: Word;
    value: LongInt;
  end;

TKeyAndMouse = class(TObject)
  public
  oldTAttr,TAttr: TermIOS;
  pfds: Tpollfd;
  ret: Integer;
  ev: Tinput_event;

  function openDevice(devPath: string): Boolean;
  function readKeys(keys:array of Word; var isPressed:array of SmallInt; Count: Integer): BOOLEAN;

  end;

type TAsyncKeyThread = class(TThread)
// класс для асинхронного чтения событий клавиатуры и мыши
  public
  KeybrdOk,MouseOk: Boolean;

  // последовательность кодов клавиш и мыши, которые мы отслеживаем
  keyCodes: array of integer;
  // считанные состояния клавиш на текущий момент
  keyStates: array of integer;
  // начать работу по отслеживанию
  procedure initAllKeys(AKeyCodes: array of integer; Count: Integer);
  procedure getKeyboardState(keyToRead: array of integer; var keyResult: array of integer; AkeyCount: Integer);
  procedure Execute;override;

  constructor Create;
  destructor Destroy;override;
end;


//---------------------------------------------------------------
  TForm1 = class(TForm)
    Button1: TButton;
    Button2: TButton;
    Label1: TLabel;
    Label2: TLabel;
    Memo1: TMemo;
    Timer1: TTimer;
    Timer2: TTimer;
    procedure Button1Click(Sender: TObject);
    procedure Button2Click(Sender: TObject);
    procedure Timer1Timer(Sender: TObject);
    procedure Timer2Timer(Sender: TObject);
  private

  public
    keyToRead, keyStates: array of Integer;

   Keys: array of Word;
   isKeyPressed: array of SmallInt;
   keyPoll1,keyPoll2: TKeyAndMouse;
   myThread: TAsyncKeyThread;
   myCs: TRTLCriticalSection;
  end;

var
  Form1: TForm1;

implementation

{$R *.frm}

{ TForm1 }
//---------------------------------------------------------------------------------------
procedure TAsyncKeyThread.Execute;
var
  i,n: Integer;
  pfdKeybrd, pfdMouse: Tpollfd;
  ret: Integer;
  ev: Tinput_event;
begin
  // создаем и открываем что нужно
  pfdKeybrd.fd := fpOpen(keybrdPath,O_RDONLY);
  if(pfdKeybrd.fd<0) then begin KeybrdOk := False; end;
  pfdKeybrd.events:=POLLIN;

  pfdMouse.fd := fpOpen(mousePath,O_RDONLY);
  if(pfdMouse.fd<0) then begin MouseOk := False; end;
  pfdMouse.events:=POLLIN;

  while not Terminated do begin
    // читаем клавиатуру
    ret := fpPoll(@pfdKeybrd,1,0);
    while(ret>0) do begin
      n := fpRead(pfdKeybrd.fd, ev,sizeof(TInput_event));
      if n<sizeof(sizeof(TInput_event)) then break;

      for i:=0 to Length(keyCodes)-1 do begin
        if (ev.code=keyCodes[i]) then begin keyStates[i]:=ev.value;end;
        end;
      ret := fpPoll(@pfdKeybrd,1,0);
      end;

    // читаем мышь
    ret := fpPoll(@pfdMouse,1,0);
    while(ret>0) do begin
      n := fpRead(pfdMouse.fd, ev,sizeof(TInput_event));
      if n<sizeof(sizeof(TInput_event)) then break;

      for i:=0 to Length(keyCodes)-1 do begin
        if (ev.code=keyCodes[i]) then begin keyStates[i]:=ev.value;end;
        end;
      ret := fpPoll(@pfdMouse,1,0);
      end;

    // 100мс не опрашиваем - для пользователя нормально, для ЦПУ не обременительно
    Sleep(100);
    end;
  // освобождаем, завершаем работу
  SetLength(keyCodes,0);
  SetLength(keyStates,0);
end;
//---------------------------------------------------------------------------------
procedure TAsyncKeyThread.initAllKeys(AKeyCodes: array of integer; Count: Integer);
var
  i: Integer;
begin
  SetLength(keyCodes,Count);
  SetLength(keyStates,Count);
  for i:=0 to Count-1 do begin
    keyCodes[i] := AKeyCodes[i];
    keyStates[i] := 0;
    end;

  Start;
end;

procedure TAsyncKeyThread.getKeyboardState(keyToRead: array of integer; var keyResult: array of integer; AkeyCount: Integer);
var
  i,j: Integer;
begin
  for j:=0 to AKeyCount-1 do begin
    for i:=0 to Length(keyCodes)-1 do begin
      if keyCodes[i]=keyToRead[j] then begin
        keyResult[j]:=keyStates[i];
        break;
        end;
      end;
    end;
end;

constructor TAsyncKeyThread.Create;
begin
  inherited Create(True);
  FreeOnTerminate := True;
end;

destructor TAsyncKeyThread.Destroy;
begin
  inherited Destroy;
end;

function TKeyAndMouse.openDevice(devPath:string): Boolean;
begin
    Result := True;
    pfds.fd := fpOpen(devPath,O_RDONLY);
    if(pfds.fd<0) then begin
        Result := False;
        Exit;
        end;
    pfds.events:=POLLIN;
end;

function TKeyAndMouse.readKeys(keys:array of Word; var isPressed:array of SmallInt; Count: Integer): BOOLEAN;
const
  EV_KEY = $01;
  EV_REL = $02;
  EV_REP = $14;
var
  i,n: Integer;
begin
  Result := True;

  ret := fpPoll(@pfds,1,0); // узнаем, есть ли данные в буфере
  if ret=0 then exit;

  repeat
    n := fpRead(pfds.fd, ev,sizeof(TInput_event));
    if n<sizeof(sizeof(TInput_event)) then exit;

    for i:=0 to Count-1 do begin
      if (ev.code=keys[i]) then begin isPressed[i]:=ev.value;end;
      end;
    ret := fpPoll(@pfds,1,0);
  until ret=0;
end;

procedure TForm1.Button1Click(Sender: TObject);
var
  allkeys: array of Integer;
begin
  SetLength(allkeys,3);
  SetLength(keyToRead,3);
  SetLength(keyStates,3);

  allKeys[0] := BTN_LEFT;
  allKeys[1] := KEY_UP;
  allKeys[2] := KEY_LEFT;

  SetLength(keyToRead,3);
  KeyToRead[0] := BTN_LEFT;
  KeyToRead[1] := KEY_UP;
  KeyToRead[2] := KEY_LEFT;

  myThread := TAsyncKeyThread.Create;
  myThread.initAllKeys(allKeys,Length(allKeys));
  Timer2.Enabled := True;
end;

procedure TForm1.Button2Click(Sender: TObject);
var
  i: Integer;
begin
   SetLength(Keys,3);
   SetLength(isKeyPressed,3);
   Keys[0] := BTN_LEFT;
   Keys[1] := KEY_UP;
   Keys[2] := KEY_LEFT;

   for i:= 0 to Length(Keys)-1 do begin // нулим массив со считанными клавишами
    isKeyPressed[i] := 100;
    end;

   keyPoll1:= TKeyAndMouse.Create;
   keyPoll1.openDevice(mousePath);
   keyPoll2:= TKeyAndMouse.Create;
   keyPoll2.openDevice(keybrdPath);
   Timer1.Enabled := True;
end;

procedure TForm1.Timer1Timer(Sender: TObject);
var
  str1: string;
  i: integer;
begin
  // опрос клавиатуры в таймере
  str1 := '';
  keyPoll1.readKeys(Keys,isKeyPressed,Length(Keys));
  keyPoll2.readKeys(Keys,isKeyPressed,Length(Keys));

  for i:=0 to Length(Keys)-1 do begin
    str1 := str1 +' '+IntToStr(isKeyPressed[i]);
    end;
  Label1.Caption := str1;
end;

procedure TForm1.Timer2Timer(Sender: TObject);
var
  i: Integer;
  str1: string;
begin
  myThread.getKeyboardState(keyToRead,keyStates,Length(keyToRead));

  for i:=0 to Length(KeyStates)-1 do begin
    str1 := str1 +' '+IntToStr(KeyStates[i]);
    end;
  Label2.Caption := str1;
end;


end.


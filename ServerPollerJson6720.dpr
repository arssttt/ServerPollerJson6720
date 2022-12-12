program ServerPollerJson6720;

{$APPTYPE CONSOLE}

uses
  SysUtils,
  StrUtils,
  Vcl.Forms,
  windows,
  Classes,
  Math,
  KM_Defaults,
  KM_Settings,
  KM_ServerQuery,
  KM_NetworkTypes,
  KM_utils,
  DBXJSON;

const
  GameStateTextIDs: array [TMPGameState] of string = ('mgsNone', 'mgsLobby', 'mgsLoading', 'mgsGame');
  PlayerTypeTextIDs: array [TNetPlayerType] of string = ('nptHuman', 'nptComputer', 'nptClosed');
  MasterServerAddress = 'http://kam.hodgman.id.au/';
  TIMEOUT=10000;

var
  fServerQuery: TKMServerQuery;
  I, J, TIME, PlayerCount: Integer;
  R: TKMRoomInfo;
  S: TKMServerInfo;
  DisplayName, ShortName: string;

  JSONObject, RoomObject, PlayerObject : TJSONObject;
  RoomsArray,PlayersArray: TJSONArray;


begin
  fServerQuery := TKMServerQuery.Create(MasterServerAddress);
  fServerQuery.RefreshList;
  TIME := GetTickCount;

  while (GetTickCount - TIME) < TIMEOUT do
  begin
    Application.ProcessMessages;
    CheckSynchronize;
    fserverquery.UpdateStateIdle;
    //writeln('start ' + inttostr(GetTickCount - TIME));
    //writeln('Rcount='+inttostr(fServerQuery.Rooms.Count));
   // writeln('ActiveCount='+inttostr(fServerQuery.Servers.Count));
    //writeln('TIME='+inttostr(TIME));
    sleep(50);
    if fServerQuery.GetQueriesIsDone then break;
  end;

  JSONObject := TJSONObject.Create;
  RoomsArray := TJSONArray.Create();
  for I := 0 to fServerQuery.Rooms.Count - 1 do
       begin
       R := fServerQuery.Rooms[I];
       S := fServerQuery.Servers[R.ServerIndex];
       ShortName := StripColor(S.Name + ' #' + IntToStr(R.RoomID + 1));

       RoomObject:=TJSONObject.Create;
       RoomObject.AddPair('ServerName',ShortName);
       RoomObject.AddPair('Description',R.GameInfo.Description);
       RoomObject.AddPair('Password', boolToStr(R.GameInfo.PasswordLocked,true));
       RoomObject.AddPair('Map',R.GameInfo.Map);
       RoomObject.AddPair('GameTime',TimeToStr(R.GameInfo.GameTime));
       RoomObject.AddPair('GameState',GameStateTextIDs[R.GameInfo.GameState]);
       //RoomObject.AddPair('PlayerCount',TJSONNumber.Create(R.GameInfo.PlayerCount));

       PlayersArray := TJSONArray.Create();
       PlayerCount := 0;
       for J := 1 to 10 do
       begin
        if (R.GameInfo.Players[J].Connected) and (PlayerTypeTextIDs[R.GameInfo.Players[J].PlayerType] <> 'nptClosed') then
          begin
          inc(PlayerCount);
          PlayerObject := TJSONObject.Create;
          if (PlayerTypeTextIDs[R.GameInfo.Players[J].PlayerType] = 'nptComputer') then
            PlayerObject.AddPair('Name','Computer')
            else
            PlayerObject.AddPair('Name',R.GameInfo.Players[J].Name);
          PlayerObject.AddPair('Color',inttohex(R.GameInfo.Players[J].Color,8));
          PlayerObject.AddPair('PlayerType',PlayerTypeTextIDs[R.GameInfo.Players[J].PlayerType]);
          PlayersArray.AddElement(PlayerObject);
          end;

       end;

       RoomObject.AddPair('PlayerCount',TJSONNumber.Create(PlayerCount));
       RoomObject.AddPair('Players',PlayersArray);
       RoomsArray.AddElement(RoomObject);
      end;
  JSONObject.AddPair('RoomsCount',TJSONNumber.Create(fServerQuery.Rooms.Count));
  JSONObject.AddPair('Rooms',RoomsArray);
  writeln(JSONObject.ToString);
  JSONObject.Destroy;
  fserverquery.Destroy;

end.


unit KM_ServerQuery;
{$I KaM_Remake.inc}
interface
uses Classes, SysUtils,
  KM_Defaults, KM_CommonClasses, KM_CommonTypes, KM_NetUDP,
  KM_NetworkTypes, KM_NetworkClasses, KM_Utils, KM_MasterServer, KM_NetClient;

const
  MAX_QUERIES = 15; //The maximum number of individual server queries that can be happening at once
  QUERY_TIMEOUT = 4000; //The maximum amount of time for an individual query to take (will take at least 2*ping)
  MIN_UDP_SCAN_TIME = 100; //Assume we won't get any more UDP responses after this time (remove 'Refreshing...' text if no servers found)

type
  TKMServerInfo = record
    Name: string;
    IP: string;
    Port: string;
    ServerType: TKMServerType;
    Ping: Word;
  end;

  TKMRoomInfo = record
    ServerIndex: Integer; //Points to some TKMServerInfo in TKMServerList
    RoomID: Integer;
    OnlyRoom: Boolean; //Is this the only room in the server?
    GameInfo: TMPGameInfo;
  end;

  TServerDataEvent = procedure(aServerID: Integer; aStream: TKMemoryStream; aPingStarted: Cardinal) of object;

  TServerSortMethod = (
    ssmByTypeAsc, ssmByTypeDesc, //Client or dedicated
    ssmByPasswordAsc, ssmByPasswordDesc, //Passworded or not
    ssmByNameAsc, ssmByNameDesc, //Server names
    ssmByPingAsc, ssmByPingDesc, //Server pings
    ssmByStateAsc, ssmByStateDesc, //Room state
    ssmByPlayersAsc, ssmByPlayersDesc); //Player count in room

  TKMQuery = class
  private
    fNetClient: TKMNetClient;
    fQueryActive:boolean;
    fQueryIsDone: boolean;
    fPingStarted:cardinal;
    fQueryStarted:cardinal;
    fIndexOnServer:integer;
    fServerID:integer;
    fOnServerData: TServerDataEvent;
    fOnQueryDone: TNotifyEvent;
    procedure NetClientReceive(aNetClient:TKMNetClient; aSenderIndex:integer; aData:pointer; aLength:cardinal);
    procedure PacketSend(aRecipient: Integer; aKind: TKMessageKind); overload;
  public
    constructor Create;
    destructor Destroy; override;
    procedure PerformQuery(aAddress, aPort:string; aServerID:integer);
    procedure Disconnect;
    property OnServerData:TServerDataEvent read fOnServerData write fOnServerData;
    property OnQueryDone:TNotifyEvent read fOnQueryDone write fOnQueryDone;
    procedure UpdateStateIdle;
  end;

  TKMRoomList = class
  private
    fCount:integer;
    fRooms:array of TKMRoomInfo;
    procedure AddRoom(aServerIndex, aRoomID: Integer; aOnlyRoom:Boolean; aGameInfoStream: TKMemoryStream);
    function GetRoom(aIndex: Integer): TKMRoomInfo;
    procedure Clear;
  public
    destructor Destroy; override;
    property Rooms[aIndex: Integer]: TKMRoomInfo read GetRoom; default;
    property Count: Integer read fCount;
    procedure LoadData(aServerID:integer; aStream: TKMemoryStream);
    procedure SwapRooms(A,B:Integer);
  end;

  TKMServerList = class
  private
    fCount:integer;
    fLastQueried:integer;
    fServers:array of TKMServerInfo;
    procedure AddServer(aIP, aPort, aName: string; aType: TKMServerType; aPing: word);
    function GetServer(aIndex: Integer): TKMServerInfo;
    procedure Clear;
    procedure AddFromText(const aText: UnicodeString);
  public
    property Servers[aIndex: Integer]: TKMServerInfo read GetServer; default;
    property Count: Integer read fCount;
    procedure TakeNewQuery(aQuery:TKMQuery);
    procedure SetPing(aServerID:integer; aPing: Cardinal);
  end;

  //Handles the master-server querrying and carries ServerList
  TKMServerQuery = class
  private
    fMasterServer: TKMMasterServer;
    fServerList: TKMServerList; //List of servers fetch from master
    fRoomList: TKMRoomList; //Info about each room populated after query completed
    fQuery: array[0..MAX_QUERIES-1] of TKMQuery;
    fSortMethod: TServerSortMethod;
    fRefreshStartedTime: Cardinal;
    fReceivedMasterServerList: Boolean;
    fQueriesIsDone: boolean;

    fUDPScanner: TKMNetUDPScan;

    fOnListUpdated: TNotifyEvent;
    fOnAnnouncements: TUnicodeStringEvent;

    procedure DetectUDPServer(const aAddress: string; const aPort: string; const aName: string);
    procedure ReceiveServerList(const S: string);
    procedure ReceiveAnnouncements(const S: string);

    procedure ServerDataReceive(aServerID: Integer; aStream: TKMemoryStream; aPingStarted: Cardinal);
    procedure QueryDone(Sender:TObject);

    procedure Sort;
    procedure SetSortMethod(aMethod: TServerSortMethod);

  public
    constructor Create(aMasterServerAddress: string);
    destructor Destroy; override;

    function ActiveQueryCount: Integer;
    property OnListUpdated: TNotifyEvent read fOnListUpdated write fOnListUpdated;
    property OnAnnouncements: TUnicodeStringEvent read fOnAnnouncements write fOnAnnouncements;
    property Servers: TKMServerList read fServerList;
    property Rooms: TKMRoomList read fRoomList;

    property SortMethod: TServerSortMethod read fSortMethod write SetSortMethod;

    procedure RefreshList;
    procedure FetchAnnouncements(aLocale: AnsiString);
    procedure SendMapInfo(const aMapName: UnicodeString; aCRC: Cardinal; aPlayerCount: Integer);
    procedure UpdateStateIdle;
    function GetQueriesIsDone: Boolean;
  end;


implementation


{ TKMRoomList }
destructor TKMRoomList.Destroy;
begin
  Clear; //Frees GameInfo
  inherited;
end;


procedure TKMRoomList.AddRoom(aServerIndex, aRoomID: Integer; aOnlyRoom:Boolean; aGameInfoStream: TKMemoryStream);
begin
  if Length(fRooms) <= fCount then SetLength(fRooms, fCount+16);
  fRooms[fCount].ServerIndex := aServerIndex;
  fRooms[fCount].RoomID := aRoomID;
  fRooms[fCount].OnlyRoom := aOnlyRoom;
  fRooms[fCount].GameInfo := TMPGameInfo.Create;
  fRooms[fCount].GameInfo.LoadFromStream(aGameInfoStream);
  inc(fCount);
end;


function TKMRoomList.GetRoom(aIndex:integer):TKMRoomInfo;
begin
  Result := fRooms[aIndex];
end;


procedure TKMRoomList.Clear;
var i: Integer;
begin
  for i := 0 to fCount - 1 do
    fRooms[i].GameInfo.Free;
  fCount := 0;
  SetLength(fRooms, 0);
end;


procedure TKMRoomList.LoadData(aServerID:integer; aStream: TKMemoryStream);
var
  i, RoomCount, RoomID: Integer;
begin

  aStream.Read(RoomCount);
  for i := 0 to RoomCount - 1 do //We don't actually use i as the server sends us RoomID (rooms might not be in order)
  begin
    aStream.Read(RoomID);
    AddRoom(aServerID, RoomID, (RoomCount = 1), aStream);
  end;

end;


procedure TKMRoomList.SwapRooms(A,B: Integer);
var TempRoomInfo: TKMRoomInfo;
begin
  TempRoomInfo := fRooms[A];
  fRooms[A] := fRooms[B];
  fRooms[B] := TempRoomInfo;
end;


{ TKMServerList }
procedure TKMServerList.AddServer(aIP, aPort, aName: string; aType: TKMServerType; aPing: Word);
begin
  if Length(fServers) <= fCount then SetLength(fServers, fCount+16);
  fServers[fCount].Name := aName;
  fServers[fCount].IP := aIP;
  fServers[fCount].Port := aPort;
  fServers[fCount].ServerType := aType;
  fServers[fCount].Ping := aPing;
  Inc(fCount);
end;


function TKMServerList.GetServer(aIndex:integer):TKMServerInfo;
begin
  Result := fServers[aIndex];
end;


procedure TKMServerList.Clear;
begin
  fCount := 0;
  SetLength(fServers, 0);
  fLastQueried := -1; //First is 0
end;


procedure TKMServerList.AddFromText(const aText: UnicodeString);

  function GetServerType(aDedicated, aOS: UnicodeString): TKMServerType;
  begin
    if aDedicated = '0' then
      Result := mstClient
    else
      Result := mstDedicated;
  end;

var
  srvList, srvInfo: TStringList;
  I: Integer;
begin
  srvList := TStringList.Create;
  srvInfo := TStringList.Create;
  srvList.Text := aText; //Parse according to EOLs
  for I := 0 to srvList.Count - 1 do
  begin
    ParseDelimited(srvList[I], ',', srvInfo); //Automatically clears srvInfo and loads each value
    if srvInfo.Count = 5 then //Must have 5 parameters
      AddServer(srvInfo[1], srvInfo[2], srvInfo[0], GetServerType(srvInfo[3], srvInfo[4]), 0);
  end;

  srvInfo.Free;
  srvList.Free;
end;


procedure TKMServerList.TakeNewQuery(aQuery:TKMQuery);
begin
 // writeln('newQ');
  if fLastQueried < fCount-1 then
  begin
    Inc(fLastQueried);
    aQuery.PerformQuery(Servers[fLastQueried].IP, Servers[fLastQueried].Port, fLastQueried);
  end
  else
  begin
    aQuery.Disconnect;
    //writeln('discon_newQ');
  end;
end;


procedure TKMServerList.SetPing(aServerID:Integer; aPing: Cardinal);
begin
  fServers[aServerID].Ping := aPing;
end;


{ TKMQuery }
constructor TKMQuery.Create;
begin
  inherited;
  fNetClient := TKMNetClient.Create;
  fQueryIsDone := false;
  fQueryActive := false;
end;


destructor TKMQuery.Destroy;
begin
  fNetClient.Free;
  inherited;
end;


procedure TKMQuery.PerformQuery(aAddress, aPort:string; aServerID:integer);
begin
  fQueryActive := true;
  fServerID := aServerID;
  fQueryStarted := TimeGet;
  fNetClient.Disconnect;
  fNetClient.OnRecieveData := NetClientReceive;
  fNetClient.ConnectTo(aAddress,aPort);
 // writeln('per_query');
end;


procedure TKMQuery.Disconnect;
begin
  fNetClient.Disconnect;
  fNetClient.OnRecieveData := nil;
end;


procedure TKMQuery.UpdateStateIdle;
begin
 // writeln('updateIdle');
  if not fQueryActive then exit;
  fNetClient.UpdateStateIdle;
  if GetTimeSince(fQueryStarted) > QUERY_TIMEOUT then
  begin
    fQueryIsDone := true; //Give up
   // writeln('timeout');
  end;
  if fQueryIsDone then
  begin
    fQueryIsDone := false;
    fQueryActive := false;
    fOnQueryDone(Self);
  end;
end;


procedure TKMQuery.NetClientReceive(aNetClient: TKMNetClient; aSenderIndex: Integer; aData: Pointer; aLength: Cardinal);
var
  M: TKMemoryStream;
  Kind: TKMessageKind;
  tmpInteger: Integer;
  tmpString: AnsiString;
begin

  Assert(aLength >= 1, 'Unexpectedly short message'); //Kind, Message

  M := TKMemoryStream.Create;
  M.WriteBuffer(aData^, aLength);
  M.Position := 0;
  M.Read(Kind, SizeOf(TKMessageKind)); //Depending on kind message contains either Text or a Number

  case Kind of
    mk_GameVersion:
      begin
    //  writeln('mk_version');
        M.ReadA(tmpString);
        if tmpString <> NET_PROTOCOL_REVISON then
          fQueryIsDone := True;
      end;

    mk_IndexOnServer:
      begin
     // writeln('mk_index');
        M.Read(tmpInteger);
        fIndexOnServer := tmpInteger;
        fPingStarted := TimeGet;
        PacketSend(NET_ADDRESS_SERVER, mk_GetServerInfo);
      end;

    mk_ServerInfo:
      begin
    //     writeln('mk_serinfo');
        fOnServerData(fServerID, M, fPingStarted);
        //fOnQueryDone(self);
        fQueryIsDone := true; //We cannot call fOnQueryDone now because that would disconnect the socket halfway through the receive procedure (crashes)
      //  fQueryIsDone := false;
       // fQueryActive := false;
       // fOnQueryDone(Self);
        //UpdateStateIdle;

      end;
  end;

  M.Free;
end;


procedure TKMQuery.PacketSend(aRecipient: Integer; aKind: TKMessageKind);
var
  M: TKMemoryStream;
begin
  Assert(NetPacketType[aKind] = pfNoData);

  M := TKMemoryStream.Create;
  M.Write(aKind, SizeOf(TKMessageKind));

  fNetClient.SendData(fIndexOnServer, aRecipient, M.Memory, M.Size);
  M.Free;
end;


{ TKMServerQuery }
constructor TKMServerQuery.Create(aMasterServerAddress: string);
var I: Integer;
begin
  inherited Create;
  fQueriesIsDone := false;
  fMasterServer := TKMMasterServer.Create(aMasterServerAddress, False);
  fMasterServer.OnServerList := ReceiveServerList;
 // fMasterServer.OnAnnouncements := ReceiveAnnouncements;

  //fUDPScanner := TKMNetUDPScan.Create;
  //fUDPScanner.OnServerDetected := DetectUDPServer;

  fSortMethod := ssmByStateAsc; //Default sorting is by state

  fServerList := TKMServerList.Create;
  fRoomList := TKMRoomList.Create;
  for I := 0 to MAX_QUERIES - 1 do
  begin
    fQuery[I] := TKMQuery.Create;
    fQuery[I].OnServerData := ServerDataReceive;
    //fQuery[I].OnQueryDone := QueryDone;
    fQuery[I].OnQueryDone := QueryDone;
  end;
end;


destructor TKMServerQuery.Destroy;
var
  I: Integer;
begin
  fMasterServer.Free;
  fUDPScanner.Free;
  fServerList.Free;
  fRoomList.Free;
  for I := 0 to MAX_QUERIES - 1 do
    fQuery[I].Free;

  inherited;
end;


procedure TKMServerQuery.RefreshList;
var I: Integer;
begin
  //Clean up first
  for I := 0 to MAX_QUERIES - 1 do
    fQuery[I].Disconnect;
  fRoomList.Clear;
  fServerList.Clear;
  fReceivedMasterServerList := False;
  fQueriesIsDone := false;
  fRefreshStartedTime := TimeGet;

  fMasterServer.QueryServer; //Start the query
end;


procedure TKMServerQuery.DetectUDPServer(const aAddress: string; const aPort: string; const aName: string);
var I: Integer;
begin
  //Make sure this isn't a duplicate (UDP is connectionless so we could get a response from an old query)
  for I := 0 to fServerList.Count-1 do
    if (fServerList[I].IP = aAddress) and (fServerList[I].Port = aPort) then
      Exit;

  fServerList.AddServer(aAddress, aPort, aName, mstLocal, 0);
  for I := 0 to MAX_QUERIES - 1 do
    if not fQuery[I].fQueryActive then
      fServerList.TakeNewQuery(fQuery[I]);
end;


procedure TKMServerQuery.ReceiveServerList(const S: string);
var I: Integer;
begin
  fReceivedMasterServerList := True;
  fServerList.AddFromText(S);
  for I := 0 to MAX_QUERIES - 1 do
    if not fQuery[I].fQueryActive then
      fServerList.TakeNewQuery(fQuery[I]);
end;


procedure TKMServerQuery.ReceiveAnnouncements(const S: string);
begin
  if Assigned(fOnAnnouncements) then
    fOnAnnouncements(S);
end;


procedure TKMServerQuery.ServerDataReceive(aServerID: Integer; aStream: TKMemoryStream; aPingStarted: Cardinal);
begin
  fRoomList.LoadData(aServerID, aStream); //Tell RoomsList to load data about rooms
  fServerList.SetPing(aServerID, GetTimeSince(aPingStarted)); //Tell ServersList ping

  Sort; //Apply sorting
  //QueryDone(nil);

  if Assigned(fOnListUpdated) then begin
 // writeln('ser_d_r_done');
    fOnListUpdated(Self);
  end;
end;


procedure TKMServerQuery.QueryDone(Sender: TObject);
begin
 // writeln('done');
  fServerList.TakeNewQuery(TKMQuery(Sender));
end;


//Get the server announcements in specified language
procedure TKMServerQuery.FetchAnnouncements(aLocale: AnsiString);
begin
  fMasterServer.FetchAnnouncements(aLocale);
end;


procedure TKMServerQuery.SendMapInfo(const aMapName: UnicodeString; aCRC: Cardinal; aPlayerCount: Integer);
begin
  fMasterServer.SendMapInfo(aMapName, aCRC, aPlayerCount);
end;


procedure TKMServerQuery.UpdateStateIdle;
var I: Integer;
begin

  //writeln('upd-s-id');
  fMasterServer.UpdateStateIdle;
  //UDPScanner.UpdateStateIdle;
  for I := 0 to MAX_QUERIES - 1 do
    fQuery[I].UpdateStateIdle;

  //Once we've received the master list, finished all queries and waited long enough for UDP scan
  //we should update the list (this removes 'Refreshing...' when no servers respond)
  if fReceivedMasterServerList and (ActiveQueryCount = 0) and (GetTimeSince(fRefreshStartedTime) > MIN_UDP_SCAN_TIME) then
  begin
   //writeln('UDP??');
   fReceivedMasterServerList := False; //Don't do this again until the next refresh
   fQueriesIsDone :=True;
 //   fUDPScanner.TerminateScan; //Closes UDP listen
    if Assigned(fOnListUpdated) then
      fOnListUpdated(Self);
  end;
end;

function TKMServerQuery.GetQueriesIsDone: Boolean;
begin
  Result := fQueriesIsDone;
end;


procedure TKMServerQuery.Sort;

  function Compare(A, B: TKMRoomInfo; aMethod: TServerSortMethod):Boolean;
  var AServerInfo, BServerInfo: TKMServerInfo;
  const StateSortOrder: array[TMPGameState] of byte = (4,1,2,3);
  begin
    Result := False; //By default everything remains in place
    AServerInfo := Servers[A.ServerIndex];
    BServerInfo := Servers[B.ServerIndex];
    case aMethod of
      ssmByPasswordAsc: Result := A.GameInfo.PasswordLocked and not B.GameInfo.PasswordLocked;
      ssmByPasswordDesc:Result := not A.GameInfo.PasswordLocked and B.GameInfo.PasswordLocked;
      ssmByTypeAsc:     Result := AServerInfo.ServerType > BServerInfo.ServerType;
      ssmByTypeDesc:    Result := AServerInfo.ServerType < BServerInfo.ServerType;
      ssmByNameAsc:     Result := CompareText(AServerInfo.Name, BServerInfo.Name) > 0;
      ssmByNameDesc:    Result := CompareText(AServerInfo.Name, BServerInfo.Name) < 0;
      ssmByPingAsc:     Result := AServerInfo.Ping > BServerInfo.Ping;
      ssmByPingDesc:    Result := AServerInfo.Ping < BServerInfo.Ping;
      ssmByStateAsc:    Result := StateSortOrder[A.GameInfo.GameState] > StateSortOrder[B.GameInfo.GameState];
      ssmByStateDesc:   Result := StateSortOrder[A.GameInfo.GameState] < StateSortOrder[B.GameInfo.GameState];
      ssmByPlayersAsc:  Result := A.GameInfo.PlayerCount > B.GameInfo.PlayerCount;
      ssmByPlayersDesc: Result := A.GameInfo.PlayerCount < B.GameInfo.PlayerCount;
    end;
    //Always put local servers at the top
    if (AServerInfo.ServerType = mstLocal) and (BServerInfo.ServerType <> mstLocal) then
      Result := False
    else
      if (AServerInfo.ServerType <> mstLocal) and (BServerInfo.ServerType = mstLocal) then
        Result := True;
  end;

var
  i, k: Integer;
begin
  for i:=0 to fRoomList.Count-1 do
  for k:=i to fRoomList.Count-1 do
  if Compare(Rooms[i], Rooms[k], fSortMethod) then
    fRoomList.SwapRooms(i,k);
end;


procedure TKMServerQuery.SetSortMethod(aMethod: TServerSortMethod);
begin
  fSortMethod := aMethod;
  Sort; //New sorting method has been set, we need to apply it
end;


function TKMServerQuery.ActiveQueryCount: Integer;
var I: Integer;
begin
  Result := 0;
  for I := 0 to MAX_QUERIES-1 do
    if fQuery[I].fQueryActive then
      Inc(Result);
end;

end.

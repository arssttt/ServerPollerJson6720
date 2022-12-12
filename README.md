# ServerPollerJson6720
Console Application for KaM Remake R6720. Polls servers status and returns detailed JSON.\
Based on original from reyandme/kam_remake ..\Utils\Server Poller\
Application used: Delphi XE2

# Format JSON
GameStat ('mgsNone', 'mgsLobby', 'mgsLoading', 'mgsGame')\
PlayerType ('nptHuman', 'nptComputer')\
Example:
```json
{
  "RoomsCount": 1,
  "Rooms": [
    {
      "ServerName": "[GER/EU] GNet KaM #1",
      "Description": "2v2 3v3 4v4",
      "Password": "False",
      "Map": "A Reverse Cor. V 2.99_3_EMO_no cheat",
      "GameTime": "1:33:44",
      "GameState": "mgsGame",
      "PlayerCount": 4,
      "Players": [
        {
          "Name": "demian",
          "Color": "FF103C52",
          "PlayerType": "nptHuman"
        },
        {
          "Name": "mosta",
          "Color": "FF0000EB",
          "PlayerType": "nptHuman"
        },
        {
          "Name": "Captain Nathan",
          "Color": "FF1B1B1B",
          "PlayerType": "nptHuman"
        },
        {
          "Name": "diogok",
          "Color": "FF973400",
          "PlayerType": "nptHuman"
        }
      ]
    }
  ]
}
```

# Example usage Powershell
```powershell
PS> $JSON = ./ServerPollerJson6720.exe | Out-String | ConvertFrom-Json
PS> $JSON

RoomsCount Rooms
---------- -----
        22 {@{ServerName=[GER/EU] GNet KaM #4; Password=False; Map=Stone Wars 3.6_CEF60B68; GameTime=0:00:00; GameSt...


PS> $JSON.RoomsCount
22
PS> $JSON.Rooms[1]


ServerName  : [GER/EU] GNet KaM #1
Password    : False
Map         : Annie
GameTime    : 0:08:17
GameState   : mgsGame
PlayerCount : 1
Players     : {@{Name=kimst; Color=FF0000EB; PlayerType=nptHuman}}



PS> $JSON.Rooms[0]


ServerName  : [GER/EU] GNet KaM #4
Password    : False
Map         : Stone Wars 3.6_CEF60B68
GameTime    : 0:00:00
GameState   : mgsLobby
PlayerCount : 3
Players     : {@{Name=demian; Color=FF134B00; PlayerType=nptHuman}, @{Name=[HoJ] Styds; Color=FF7A9E00; PlayerType=nptH
              uman}, @{Name=parollo; Color=FF103C52; PlayerType=nptHuman}}
```

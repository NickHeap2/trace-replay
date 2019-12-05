set BOOTSTRAP_PROPATH=ablcontainer/ABLContainer.pl
set OPENEDGE_ENVIRONMENT=Development

REM set OpenEdge__propath=src,ablcontainer/ABLContainer.pl
set OpenEdge__propath=build/oe11/pl/app.pl,ablcontainer/ABLContainer.pl
set OpenEdge__databases__0__db=db
set OpenEdge__databases__0__host=localhost
set OpenEdge__databases__0__port=20666
set OpenEdge__databases__0__logical=db
set OpenEdge__databases__0__username=
set OpenEdge__databases__0__password=

set Application__AppserverPF=pf/appserver.pf
set Application__Playthroughs=1
set Application__TraceLogFiles=trace.log
set Application__TimeLimitMinutes=15
set Application__DisplayRecordsInclude=*
set Application__DisplayRecordsExclude=NONE
set Application__DisplayRecordsLimit=10

set Serilog__MinimumLevel__Default=Debug
REM set Serilog__WriteTo__0__Args__formatter=Serilog.Formatting.Compact.CompactJsonFormatter, Serilog.Formatting.Compact
REM set Serilog__WriteTo__1__Name=Elasticsearch
REM set Serilog__WriteTo__1__Args__nodeUris=http://elastic:9200
REM set Serilog__WriteTo__1__Args__indexFormat=test-index-{0:yyyy.MM.dd}
REM set Serilog__WriteTo__1__Args__emitEventFailure=ThrowException

set NumberOfAgents=%1
IF "%1" == "" SET NumberOfAgents=1
IF "%NumberOfAgents%" == "1" (
  CALL agent.bat 1
) ELSE (
  FOR /L %%A IN (1,1,%NumberOfAgents%) DO (
    IF "%2" == "keep" (
      START "Agent %%A" CMD /K agent.bat %%A
    ) ELSE (
      START "Agent %%A" agent.bat %%A
    )
  )
)

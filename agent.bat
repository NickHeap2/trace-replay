set Serilog__WriteTo__1__Args__path=logs\replay_%1.log
set Application__JunitResultsFilename=results%1.xml
C:\Progress\Openedge\_progres.exe -param "BATCH" -mmax 10000 -nb 1000 -s 1000 -b -q -p  "ablcontainer/ABLContainer.pl<<ABLContainer/start.r>>" -assemblies assemblies
REM -clientlog agent.log -logentrytypes DB.Connects,4GLMessages:4,4GLTrace:4

USING ABLContainer.Logging.* FROM PROPATH.
USING System.IO.*.
USING Progress.Lang.*.
USING Settings.* FROM PROPATH.
USING TraceReplay.* FROM PROPATH.

BLOCK-LEVEL ON ERROR UNDO, THROW.

CLASS TraceReplay.ReplaySession:
  DEFINE VARIABLE MS_IN_A_MINUTE AS INT64 INIT 60000 NO-UNDO.
  DEFINE VARIABLE replayer AS Replayer NO-UNDO.
  DEFINE VARIABLE replaySource AS ReplaySource NO-UNDO.
  DEFINE VARIABLE startTime AS INT64 NO-UNDO.
  DEFINE VARIABLE duration AS INT64 NO-UNDO.
  DEFINE VARIABLE grandTotalAppserverMs AS INT64 NO-UNDO.
  DEFINE VARIABLE traceFileSources AS TraceFileSource EXTENT NO-UNDO.

  DEFINE PUBLIC PROPERTY ReplaySources AS ReplaySource EXTENT  NO-UNDO
  GET.
  SET.

  DEFINE TEMP-TABLE CallDetail NO-UNDO
    FIELD traceFilename AS CHARACTER
    FIELD procedureName AS CHARACTER
    FIELD internalProcedureName AS CHARACTER
    FIELD duration AS INT64
    INDEX iPrimary IS PRIMARY traceFilename procedureName internalProcedureName.

  DEFINE TEMP-TABLE CallSummary NO-UNDO
    FIELD traceFilename AS CHARACTER
    FIELD procedureName AS CHARACTER
    FIELD internalProcedureName AS CHARACTER
    FIELD totalCalls AS INTEGER
    FIELD totalDuration AS INT64
    FIELD averageDuration AS INT64
    INDEX iPrimary IS PRIMARY traceFilename procedureName internalProcedureName.

  DEFINE TEMP-TABLE SourceSummary NO-UNDO
    FIELD traceFilename AS CHARACTER
    FIELD totalErrors AS INTEGER
    FIELD totalFailures AS INTEGER
    FIELD totalTests AS INTEGER
    FIELD totalDuration AS INT64
    INDEX iPrimary IS PRIMARY traceFilename.

  DEFINE TEMP-TABLE SessionSummary NO-UNDO
    FIELD totalErrors AS INTEGER
    FIELD totalFailures AS INTEGER
    FIELD totalTests AS INTEGER
    FIELD totalDuration AS INT64.

  METHOD VOID AddCallDetail(traceFileName AS CHARACTER, procedureName AS CHARACTER, internalProcedureName AS CHARACTER, callDuration AS INT64):
    CREATE CallDetail.
    ASSIGN
      CallDetail.traceFilename = traceFileName
      CallDetail.procedureName = procedureName
      CallDetail.internalProcedureName = internalProcedureName
      CallDetail.duration = callDuration.
  END METHOD.

  METHOD PUBLIC INTEGER CreateReplaySources(replaySourceString AS CHARACTER):
    DEFINE VARIABLE numberOfReplaySources AS INTEGER NO-UNDO.
    DEFINE VARIABLE traceLogFileEntry AS INTEGER NO-UNDO.

    /*create our list of sources*/
    numberOfReplaySources = NUM-ENTRIES(replaySourceString).
    IF numberOfReplaySources = 0 THEN DO:
      Log:Error("No trace file sources defined!").
      RETURN 0.
    END.

    IF numberOfReplaySources = 1
      AND Directory:Exists(replaySourceString)
    THEN DO:
      DEFINE VARIABLE directoryFiles AS CHARACTER EXTENT NO-UNDO.
      directoryFiles = Directory:GetFiles(replaySourceString, "*.log").
      numberOfReplaySources = EXTENT(directoryFiles).
      Log:Information("Initialising ~{NumberOfReplaySources~} trace file sources from directory ~{SourceDirectory~}...", BOX(numberOfReplaySources), BOX(replaySourceString)).
      EXTENT(traceFileSources) = numberOfReplaySources.
      DO traceLogFileEntry = 1 TO EXTENT(directoryFiles):
        traceFileSources[traceLogFileEntry] = NEW TraceFileSource(directoryFiles[traceLogFileEntry]).
      END.
    END.
    ELSE DO:
      Log:Information("Initialising ~{NumberOfReplaySources~} trace file sources...", BOX(numberOfReplaySources)).
      EXTENT(traceFileSources) = numberOfReplaySources.
      DO traceLogFileEntry = 1 TO numberOfReplaySources:
        traceFileSources[traceLogFileEntry] = NEW TraceFileSource(ENTRY(traceLogFileEntry, replaySourceString)).
      END.
    END.

    /* create our replay sources from trace file sources */
    EXTENT(THIS-OBJECT:ReplaySources) = numberOfReplaySources.
    Log:Information("Populating ~{NumberOfReplaySources~} replay sources...", BOX(numberOfReplaySources)).
    DO traceLogFileEntry = 1 TO numberOfReplaySources:
      THIS-OBJECT:ReplaySources[traceLogFileEntry] = NEW ReplaySource(traceFileSources[traceLogFileEntry]).
    END.

    RETURN numberOfReplaySources.
  END METHOD.

  METHOD PUBLIC VOID StartSession():
    CREATE WIDGET-POOL "TempTablePool" PERSISTENT NO-ERROR.

    DEFINE VARIABLE numberOfReplaySources AS INTEGER NO-UNDO.
    DEFINE VARIABLE traceLogFileEntry AS INTEGER NO-UNDO.

    numberOfReplaySources = CreateReplaySources(Settings:Application:TraceLogFiles).
    IF numberOfReplaySources = 0 THEN DO:
      RETURN.
    END.

    DEFINE VARIABLE tempTableSource AS TempTableSource NO-UNDO.
    Log:Information("Creating temp-table source...").
    tempTableSource = NEW TempTableSource().

    DEFINE VARIABLE replayFilename AS CHARACTER NO-UNDO.
    DO traceLogFileEntry = 1 TO numberOfReplaySources:
      replayFilename = traceFileSources[traceLogFileEntry]:TraceFilePath.
      ttusageFilename = SUBSTITUTE("&1.ttusage", replayFilename).

    END.

    tempTableSource:CreateTempTables().

    /* set the end time*/
    DEFINE VARIABLE endTime AS INTEGER NO-UNDO.
    endTime = Settings:Application:TimeLimitMinutes.
    IF endTime <> 0 THEN DO:
      endTime = ETIME + (endTime * MS_IN_A_MINUTE).
      replayer = NEW Replayer(tempTableSource, endTime).
    END.
    ELSE DO:
      replayer = NEW Replayer(tempTableSource, 0).
    END.
    replayer:ReplaySession = THIS-OBJECT.

    DEFINE VARIABLE playthroughs AS INTEGER NO-UNDO.
    playthroughs = Settings:Application:Playthroughs.

    DEFINE VARIABLE randomiseSources AS LOGICAL NO-UNDO.
    randomiseSources = Settings:Application:RandomiseSources.

    DEFINE VARIABLE playthrough AS INTEGER NO-UNDO.
    DEFINE VARIABLE currentSource AS INTEGER NO-UNDO.
    DEFINE VARIABLE completedReplays AS INTEGER NO-UNDO.

    currentSource = 0.
    _PLAYTHROUGHS:
    DO playthrough = 1 TO playthroughs:
      IF randomiseSources
        AND numberOfReplaySources > 1
      THEN DO:
        currentSource = RANDOM(1, numberOfReplaySources).
      END.
      ELSE DO:
        currentSource = currentSource + 1.
        IF currentSource > numberOfReplaySources THEN DO:
          currentSource = 1.
        END.
      END.

      Log:Information("Starting replay ~{Playthrough~} with log file ~{ReplaySource~}...", BOX(playthrough), BOX(traceFileSources[currentSource]:TraceFilePath)).

      /* replay the current source */
      startTime = ETIME.
      replayer:Replay(replaySources[currentSource]).
      duration = ETIME - startTime.

      grandTotalAppserverMs = grandTotalAppserverMs + replayer:totalAppserverCallMs.
      Log:Information("Total Appserver call duration was ~{TotalAppserverCallMs~}ms (~{TotalAppserverCallS~}s).", BOX(replayer:totalAppserverCallMs), BOX(replayer:totalAppserverCallMs / 1000)).
      Log:Information("Successfully replayed TraceLog in ~{ReplayDurationMs~}ms (~{ReplayDurationS~}s).", BOX(duration), BOX(duration / 1000)).

      completedReplays = completedReplays + 1.
      IF endTime <> 0
        AND ETIME >= endTime
      THEN DO:
        Log:Information("Exiting as end time has been reached.").
        LEAVE _PLAYTHROUGHS.
      END.

    END. /*_PLAYTHROUGHS*/

    Log:Information("Grand Total Appserver call duration was ~{TotalAppserverCallMs~}ms (~{GrandTotalAppserverCallS~}s).", BOX(grandTotalAppserverMs), BOX(grandTotalAppserverMs / 1000)).
    Log:Information("Successfully replayed ~{CompletedPlaythroughs~} replays.", BOX(completedReplays)).


    /* write the temp-table usage files */
    IF numberOfReplaySources = 1 THEN DO:
      DO traceLogFileEntry = 1 TO numberOfReplaySources:
        DEFINE VARIABLE usedSourceFiles AS CHARACTER NO-UNDO.
        DEFINE VARIABLE usedSourceFile AS INTEGER NO-UNDO.

        replayFilename = traceFileSources[traceLogFileEntry]:TraceFilePath.
        ttusageFilename = SUBSTITUTE("&1.ttusage", replayFilename).
        IF NOT File:Exists(ttusageFilename) THEN DO:
          OUTPUT TO VALUE(ttusageFilename).

          usedSourceFiles = tempTableSource:GetUsedSourceFiles().
          DO usedSourceFile = 1 TO NUM-ENTRIES(usedSourceFiles):
            PUT UNFORMATTED ENTRY(usedSourceFile, usedSourceFiles) "~n".
          END.

          OUTPUT CLOSE.
        END.
      END.
    END.

    Summarise().
    WriteCallSummaries().

    IF Settings:Application:JunitResultsFilename <> "" THEN DO:
      WriteJunitResults().
    END.
  END METHOD.


  METHOD VOID Summarise():
    FOR EACH CallDetail
      BY CallDetail.traceFilename BY CallDetail.procedureName BY CallDetail.internalProcedureName
      :
      FIND FIRST CallSummary
        WHERE CallSummary.traceFilename = CallDetail.traceFilename
          AND CallSummary.procedureName = CallDetail.procedureName
          AND CallSummary.internalProcedureName = CallDetail.internalProcedureName
        NO-ERROR.
      IF NOT AVAILABLE(CallSummary) THEN DO:
        CREATE CallSummary.
        ASSIGN
          CallSummary.traceFilename = CallDetail.traceFilename
          CallSummary.procedureName = CallDetail.procedureName
          CallSummary.internalProcedureName = CallDetail.internalProcedureName.
      END.
      CallSummary.totalCalls = CallSummary.totalCalls + 1.
      CallSummary.totalDuration = CallSummary.totalDuration + CallDetail.duration.
      CallSummary.averageDuration = CallSummary.totalDuration / CallSummary.totalCalls.
    END.

    CREATE SessionSummary.

    FOR EACH CallSummary
      BREAK BY CallSummary.traceFilename:
      IF FIRST-OF(CallSummary.traceFilename) THEN DO:
        CREATE SourceSummary.
        SourceSummary.traceFilename = CallSummary.traceFilename.
      END.
      SourceSummary.totalTests = SourceSummary.totalTests + 1.
/*      SourceSummary.totalErrors = SourceSummary.totalErrors + ?.    */
/*      SourceSummary.totalFailures = SourceSummary.totalFailures + ?.*/
      SourceSummary.totalDuration = SourceSummary.totalDuration + CallSummary.averageDuration.

      SessionSummary.totalTests = SessionSummary.totalTests + 1.
/*      SessionSummary.totalErrors = SessionSummary.totalErrors + ?.    */
/*      SessionSummary.totalFailures = SessionSummary.totalFailures + ?.*/
      SessionSummary.totalDuration = SessionSummary.totalDuration + CallSummary.averageDuration.
    END.

  END METHOD.

  METHOD PUBLIC VOID WriteJunitResults():
    DEFINE VARIABLE numberOfReplaySources AS INTEGER NO-UNDO.
    DEFINE VARIABLE traceLogFileEntry AS INTEGER NO-UNDO.

    DEFINE VARIABLE hDoc   AS HANDLE  NO-UNDO.
    DEFINE VARIABLE hTestSuites AS HANDLE NO-UNDO.
    DEFINE VARIABLE hTestSuite AS HANDLE NO-UNDO.
    DEFINE VARIABLE hTestCase AS HANDLE NO-UNDO.


    CREATE X-DOCUMENT hDoc.
    CREATE X-NODEREF hTestSuites.
    CREATE X-NODEREF hTestSuite.
    CREATE X-NODEREF hTestCase.

    FIND FIRST SessionSummary.

    hDoc:CREATE-NODE(hTestSuites,"testsuites","ELEMENT").
    hTestSuites:SET-ATTRIBUTE("name", "TraceReplay").
    hTestSuites:SET-ATTRIBUTE("errors", STRING(SessionSummary.totalErrors)).
    hTestSuites:SET-ATTRIBUTE("failures", STRING(SessionSummary.totalFailures)).
    hTestSuites:SET-ATTRIBUTE("tests", STRING(SessionSummary.totalTests)).
    hTestSuites:SET-ATTRIBUTE("time", STRING(SessionSummary.totalDuration)).
    hDoc:APPEND-CHILD(hTestSuites).

    FOR EACH SourceSummary
      BY SourceSummary.traceFilename:

      hDoc:CREATE-NODE(hTestSuite,"testsuite","ELEMENT").
      hTestSuite:SET-ATTRIBUTE("name", SourceSummary.traceFilename).
      hTestSuite:SET-ATTRIBUTE("errors", STRING(SourceSummary.totalErrors)).
      hTestSuite:SET-ATTRIBUTE("failures", STRING(SourceSummary.totalFailures)).
      hTestSuite:SET-ATTRIBUTE("tests", STRING(SourceSummary.totalTests)).
      hTestSuite:SET-ATTRIBUTE("time", STRING(SourceSummary.totalDuration)).
      hTestSuites:APPEND-CHILD(hTestSuite).

      FOR EACH CallSummary
        WHERE CallSummary.traceFilename = SourceSummary.traceFilename
        :
        hDoc:CREATE-NODE(hTestCase,"testcase","ELEMENT").
        hTestCase:SET-ATTRIBUTE("name", CallSummary.internalProcedureName + " in " + CallSummary.procedureName).
        hTestCase:SET-ATTRIBUTE("status", "Success").
        hTestCase:SET-ATTRIBUTE("time", STRING(CallSummary.averageDuration)).
        hTestSuite:APPEND-CHILD(hTestCase).
      END.

    END.

    hDoc:SAVE("file", Settings:Application:JunitResultsFilename).

  END METHOD.

END CLASS.
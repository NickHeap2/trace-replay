USING Progress.Lang.*.
USING TraceReplay.* FROM PROPATH.
USING TraceAnalysis.* FROM ASSEMBLY.
USING ABLContainer.Logging.* FROM PROPATH.
USING Settings.* FROM PROPATH.

BLOCK-LEVEL ON ERROR UNDO, THROW.

CLASS TraceReplay.Replayer:

  DEFINE VARIABLE lh_AppServerHandle AS HANDLE NO-UNDO.
  DEFINE VARIABLE hValueReplaceProcedure AS HANDLE NO-UNDO.
  DEFINE VARIABLE listSeperationChar AS CHARACTER NO-UNDO.
  DEFINE VARIABLE currentReplaySource AS ReplaySource NO-UNDO.

  DEFINE VARIABLE outputCharacter AS CHARACTER NO-UNDO.
  DEFINE VARIABLE outputDecimal AS DECIMAL NO-UNDO.
  DEFINE VARIABLE outputInteger AS INTEGER NO-UNDO.
  DEFINE VARIABLE outputLogical AS LOGICAL NO-UNDO.
  DEFINE VARIABLE outputDate AS DATE NO-UNDO.
  DEFINE VARIABLE outputHandle AS HANDLE NO-UNDO.

  DEFINE VARIABLE inputCharacter AS CHARACTER NO-UNDO.
  DEFINE VARIABLE inputDecimal AS DECIMAL NO-UNDO.
  DEFINE VARIABLE inputInteger AS INTEGER NO-UNDO.
  DEFINE VARIABLE inputLogical AS LOGICAL NO-UNDO.
  DEFINE VARIABLE inputDate AS DATE NO-UNDO.
  DEFINE VARIABLE inputHandle AS HANDLE NO-UNDO.

  DEFINE TEMP-TABLE ProcedureSignature NO-UNDO
    FIELD hash AS CHARACTER
    FIELD signature AS CHARACTER
    INDEX iPrimary IS PRIMARY hash.

  DEFINE TEMP-TABLE ReplayErrors NO-UNDO
    FIELD errorMessage AS CHARACTER
    FIELD procedureName AS CHARACTER
    FIELD internalProcedureName AS CHARACTER.

  DEFINE TEMP-TABLE SpaceValue NO-UNDO
    FIELD numberOfSpaces AS INTEGER
    FIELD charredValue AS CHARACTER
    FIELD spacedValue AS CHARACTER
    INDEX iPrimary IS PRIMARY numberOfSpaces charredValue
    INDEX iSpaceValue charredValue.

  DEFINE TEMP-TABLE BlacklistedCall NO-UNDO
    FIELD procedureName AS CHARACTER
    FIELD internalProcedureName AS CHARACTER
    INDEX iPrimary IS PRIMARY procedureName internalProcedureName.

  DEFINE VARIABLE passedReplays AS INTEGER NO-UNDO.
  DEFINE VARIABLE failedReplays AS INTEGER NO-UNDO.
  DEFINE VARIABLE endTime AS INT64 NO-UNDO.

  DEFINE PUBLIC PROPERTY totalAppserverCallMs AS INTEGER NO-UNDO
  GET.
  SET.

  DEFINE PUBLIC PROPERTY ReplaySession AS ReplaySession NO-UNDO
  GET.
  SET.

  DEFINE VARIABLE tempTableSource AS TempTableSource NO-UNDO.
  DEFINE VARIABLE hProcedureCall AS HANDLE NO-UNDO.
  DEFINE VARIABLE outputTables AS CHARACTER NO-UNDO.

  CONSTRUCTOR Replayer (tempTableSource AS TempTableSource, endTime AS INT64):
    listSeperationChar = CHR(248).

    THIS-OBJECT:endTime = endTime.
    THIS-OBJECT:tempTableSource = tempTableSource.

    IF Settings:Application:ValueReplaceProcedure <> "" THEN DO:
      Log:Information("Starting value replacement procedure...").
      RUN VALUE(Settings:Application:ValueReplaceProcedure) PERSISTENT SET hValueReplaceProcedure.
    END.

    Log:Information("Adding known space values to cache...").
    AddToSpaceValueCache("Example space value").
    AddBlacklistedCall("procedure.p", "InternalEntry").

  END CONSTRUCTOR.

  METHOD PUBLIC VOID ResetReplay():
    totalAppserverCallMs = 0.
    passedReplays = 0.
    failedReplays = 0.
    tempTableSource:EmptyTempTables().
  END METHOD.

  METHOD PUBLIC VOID ConnectToAppserver(appserverPF AS CHARACTER):
    IF NOT VALID-HANDLE(lh_AppServerHandle) THEN DO:
      CREATE SERVER lh_AppServerHandle.
    END.
    IF NOT lh_AppServerHandle:CONNECTED() THEN DO:
      Log:Information("Connecting to Appserver...").
      lh_AppServerHandle:CONNECT("-pf ~"" + appserverPF + "~"","","","").
    END.
    IF NOT lh_AppServerHandle:CONNECTED() THEN DO:
       Log:Error("    ERROR: Appserver unavailable!").
       RETURN.
    END.
    Log:Information("    Connected to Appserver").
  END METHOD.

  METHOD PUBLIC LOGICAL IsBlacklisted(procedureName AS CHARACTER, internalProcedureName AS CHARACTER):
    FIND FIRST BlacklistedCall
      WHERE BlacklistedCall.procedureName = procedureName
        AND BlacklistedCall.internalProcedureName = internalProcedureName
      NO-LOCK NO-ERROR.
    RETURN AVAILABLE(BlacklistedCall).
  END METHOD.

  METHOD PUBLIC VOID Replay(replaySource AS ReplaySource):
    DEFINE VARIABLE lh_ProcHandle AS HANDLE NO-UNDO.
    DEFINE VARIABLE appserverCall AS AppserverCall NO-UNDO.

    currentReplaySource = replaySource.

    ResetReplay().

    ConnectToAppserver(Settings:Application:AppserverPF).
    totalAppserverCallMs = 0.

    replaySource:Reset().
    _REPLAY_CALLS:
    DO WHILE replaySource:GetNext():
      IF endTime <> 0
        AND ETIME >= endTime
      THEN DO:
        RETURN.
      END.

      appserverCall = replaySource:Current.
      IF IsBlacklisted(appserverCall:ProcedureName, appserverCall:InternalProcedureName) THEN DO:
        Log:Information("Ignoring blacklisted call: ~{InternalProcedure~} in ~{Procedure~}", BOX(appserverCall:InternalProcedureName), BOX(appserverCall:ProcedureName)).
        NEXT _REPLAY_CALLS.
      END.

      Log:Information("Running ~{InternalProcedure~} in ~{Procedure~} on Appserver...", BOX(appserverCall:InternalProcedureName), BOX(appserverCall:ProcedureName)).
  /*    Log:Debug("        ~{Parameters~}", BOX(appserverCall:Parameters)).*/

      /* start the singleton on the appserver */
      RUN VALUE(appserverCall:ProcedureName) SINGLETON SET lh_ProcHandle ON SERVER lh_AppServerHandle TRANSACTION DISTINCT.
      IF NOT VALID-HANDLE(hProcedureCall) THEN DO:
        /* create the call */
        CREATE CALL hProcedureCall.
        hProcedureCall:CALL-TYPE = PROCEDURE-CALL-TYPE.
      END.

      hProcedureCall:CALL-NAME = appserverCall:InternalProcedureName.
      hProcedureCall:IN-HANDLE = lh_ProcHandle.
      /* clear parameters */
      hProcedureCall:NUM-PARAMETERS = 0.

      SetParameters(hProcedureCall, appserverCall:ProcedureName, appserverCall:InternalProcedureName, appserverCall:Parameters).
    END.

    IF CAN-FIND(FIRST ReplayErrors) THEN DO:
      Log:Error("!!! ERRORS DURING RUN !!!").
      FOR EACH ReplayErrors:
        Log:Error("~{ErrorLocation~} ERROR: ~{ErrorMessage~}", BOX(ReplayErrors.procedureName + " in " + ReplayErrors.internalProcedureName), BOX(ReplayErrors.errorMessage)).
      END.
    END.

    Log:Information("Passed Replays: ~{PassedReplays~}", BOX(passedReplays)).
    IF failedReplays > 0 THEN DO:
      Log:Error("Failed Replays: ~{FailedReplays~}", BOX(failedReplays)).
    END.
    ELSE DO:
      Log:Information("Failed Replays: ~{FailedReplays~}", BOX(failedReplays)).
    END.

  END METHOD.

  METHOD INTEGER GetExpectedNumberOfParameters(procedureSignature AS CHARACTER):
    DEFINE VARIABLE parameterMode AS CHARACTER NO-UNDO.
    DEFINE VARIABLE parameterDataType AS CHARACTER NO-UNDO.
    DEFINE VARIABLE iParam AS INTEGER NO-UNDO.

    DEFINE VARIABLE expectedNumerOfParameters AS INTEGER NO-UNDO.
    DO iParam = 3 TO NUM-ENTRIES(procedureSignature):
      DEFINE VARIABLE parameterSig AS CHARACTER NO-UNDO.
      parameterSig = ENTRY(iParam, procedureSignature).

      parameterMode = ENTRY(1, parameterSig, " ").
      parameterDataType = ENTRY(3, parameterSig, " ").

      IF parameterMode MATCHES "*INPUT*"
        AND parameterDataType <> "TABLE-HANDLE"
      THEN DO:
        expectedNumerOfParameters = expectedNumerOfParameters + 1.
      END.
    END.

    RETURN expectedNumerOfParameters.
  END METHOD.

  METHOD PUBLIC CHARACTER GetProcedureSignature(procedureName AS CHARACTER, internalProcedureName AS CHARACTER):

    DEFINE VARIABLE hashValue AS CHARACTER NO-UNDO.
    hashValue = procedureName + "," + internalProcedureName.

    FIND FIRST ProcedureSignature
      WHERE ProcedureSignature.hash = hashValue
      NO-LOCK NO-ERROR.
    IF AVAILABLE ProcedureSignature THEN DO:
      Log:Debug("    Got Signature for ~{InternalProcedureName~} in ~{ProcedureName~} from cache.", BOX(internalProcedureName), BOX(procedureName)).
    END.
    ELSE DO:
      DEFINE VARIABLE lh_LocalProcHandle AS HANDLE NO-UNDO.
      Log:Debug("    Running ~{ProcedureName~} locally...", BOX(procedureName)).
      RUN VALUE(procedureName) PERSISTENT SET lh_LocalProcHandle NO-ERROR.
      IF ERROR-STATUS:ERROR THEN DO:
        Log:Error("    ERROR: ~{ErrorMessage~}", BOX(ERROR-STATUS:GET-MESSAGE(1))).
      END.
      IF NOT VALID-HANDLE(lh_LocalProcHandle) THEN DO:
        RETURN ?.
      END.

      IF INDEX(lh_LocalProcHandle:INTERNAL-ENTRIES, internalProcedureName) = 0 THEN DO:
        Log:Debug("      ~{InternalProcedureName~} not found in ~{ProcedureName~} internal entries!", BOX(internalProcedureName), BOX(procedureName)).
        StoreError(procedureName, internalProcedureName, SUBSTITUTE("&1 not found in &2 internal entries!", internalProcedureName, procedureName)).
        DELETE PROCEDURE lh_LocalProcHandle.
        RETURN ?.
      END.


      DEFINE VARIABLE procedureSignature AS CHARACTER NO-UNDO.
      Log:Debug("      Getting Signature for ~{InternalProcedureName~} in ~{ProcedureName~}...", BOX(internalProcedureName), BOX(procedureName)).

      CREATE ProcedureSignature.
      ASSIGN
        ProcedureSignature.hash = hashValue
        ProcedureSignature.signature = lh_LocalProcHandle:GET-SIGNATURE(internalProcedureName).

      Log:Debug("ProcedureSignature=[~{ProcedureSignature~}]", BOX(ProcedureSignature.signature)).
      DELETE PROCEDURE lh_LocalProcHandle.
    END.

    RETURN ProcedureSignature.signature.

  END METHOD.

  METHOD PUBLIC VOID SetParameters(procedureCall AS HANDLE, procedureName AS CHARACTER, internalProcedureName AS CHARACTER, parameters AS CHARACTER):
    DEFINE VARIABLE procedureSignature AS CHARACTER NO-UNDO.
    procedureSignature = GetProcedureSignature(procedureName, internalProcedureName).
    IF procedureSignature = ? THEN DO:
      failedReplays = failedReplays + 1.
      RETURN.
    END.

    DEFINE VARIABLE cSigType AS CHARACTER NO-UNDO.
    cSigType = ENTRY(1, procedureSignature).
    DEFINE VARIABLE cReturnType AS CHARACTER NO-UNDO.
    cReturnType = ENTRY(2, procedureSignature).
    DEFINE VARIABLE iParam AS INTEGER NO-UNDO.

    procedureCall:NUM-PARAMETERS = NUM-ENTRIES(procedureSignature) - 2.
    IF procedureCall:NUM-PARAMETERS = 0 THEN RETURN.

    DEFINE VARIABLE expectedNumberOfParameters AS INTEGER NO-UNDO.
    expectedNumberOfParameters = GetExpectedNumberOfParameters(procedureSignature).

    DEFINE VARIABLE parameterValues AS CHARACTER NO-UNDO.
    DEFINE VARIABLE parameterValue AS CHARACTER NO-UNDO.

    IF parameters <> ? THEN DO:
      /* here we can replace things like usernames etc */
      IF hValueReplaceProcedure <> ? THEN DO:
        RUN ReplaceValues IN hValueReplaceProcedure
          (INPUT-OUTPUT parameters) NO-ERROR.
      END.

      parameterValues = GetParameterValues(expectedNumberOfParameters, parameters).
      Log:Information("  with parameters: [~{Parameters~}]", BOX(parameterValues)).

      DEFINE VARIABLE numberOfParameterValues AS INTEGER NO-UNDO.
      numberOfParameterValues = NUM-ENTRIES(parameterValues, listSeperationChar).
      IF numberOfParameterValues <> expectedNumberOfParameters
        /* a blank will report 0 parameters instead of 1 parameter as blank */
        AND NOT(numberOfParameterValues = 0
                AND expectedNumberOfParameters = 1)
      THEN DO:
        Log:Warning("    Expected ~{ExpectedNumberOfParameters~} parameters but parsed ~{ParsedNumberOfParameters~}!", BOX(expectedNumberOfParameters), BOX(numberOfParameterValues)).
        Log:Warning("        [~{ParameterValues~}]", BOX(parameterValues)).
      END.
    END.

    outputTables = "".
    _PARAMETER:
    DO iParam = 3 TO NUM-ENTRIES(procedureSignature):
      DEFINE VARIABLE parameterSig AS CHARACTER NO-UNDO.
      parameterSig = ENTRY(iParam, procedureSignature).
/*      Log:Debug(parameterSig).*/

      DEFINE VARIABLE parameterNumber AS INTEGER NO-UNDO.
      DEFINE VARIABLE parameterMode AS CHARACTER NO-UNDO.
      DEFINE VARIABLE parameterName AS CHARACTER NO-UNDO.
      DEFINE VARIABLE parameterDataType AS CHARACTER NO-UNDO.
      DEFINE VARIABLE temptableHandle AS HANDLE NO-UNDO.

      parameterNumber = iParam - 2.
      parameterMode = ENTRY(1, parameterSig, " ").
      parameterName = ENTRY(2, parameterSig, " ").
      parameterDataType = ENTRY(3, parameterSig, " ").

      IF parameterMode MATCHES "*OUTPUT*" THEN DO:
        IF parameterDataType = "CHARACTER" THEN DO:
          procedureCall:SET-PARAMETER(parameterNumber, parameterDataType, parameterMode, outputCharacter).
        END.
        ELSE IF parameterDataType = "DECIMAL" THEN DO:
          procedureCall:SET-PARAMETER(parameterNumber, parameterDataType, parameterMode, outputDecimal).
        END.
        ELSE IF parameterDataType = "INTEGER" THEN DO:
          procedureCall:SET-PARAMETER(parameterNumber, parameterDataType, parameterMode, outputInteger).
        END.
        ELSE IF parameterDataType = "LOGICAL" THEN DO:
          procedureCall:SET-PARAMETER(parameterNumber, parameterDataType, parameterMode, outputLogical).
        END.
        ELSE IF parameterDataType = "DATE" THEN DO:
          procedureCall:SET-PARAMETER(parameterNumber, parameterDataType, parameterMode, outputDate).
        END.
        ELSE IF parameterName = "TABLE" THEN DO:
          temptableHandle = tempTableSource:GetTempTable(parameterDataType, procedureName, internalProcedureName).
          IF temptableHandle = ? THEN DO:
            StoreError(procedureName, internalProcedureName, SUBSTITUTE("Error creating temp-table for &1", parameterDataType)).
            NEXT _PARAMETER.
          END.

          procedureCall:SET-PARAMETER(parameterNumber, "TABLE-HANDLE", parameterMode, temptableHandle).
          IF outputTables <> "" THEN outputTables = outputTables + ",".
          outputTables = outputTables + STRING(temptableHandle).
        END.
        ELSE DO:
          procedureCall:SET-PARAMETER(parameterNumber, parameterDataType, parameterMode, ?).
        END.

        Log:Debug("        Parameter ~{ParameterNumber~} ~{ParameterMode~} ~{ParameterDataType~}", BOX(parameterNumber), BOX(parameterMode), BOX(parameterDataType)).
      END.
      ELSE DO:
        IF parameterDataType = "CHARACTER" THEN DO:
          inputCharacter = ENTRY(parameterNumber, parameterValues, listSeperationChar) NO-ERROR.
          parameterValue = SUBSTITUTE("&1", inputCharacter).
          procedureCall:SET-PARAMETER(parameterNumber, parameterDataType, parameterMode, inputCharacter).
        END.
        ELSE IF parameterDataType = "DECIMAL" THEN DO:
          inputDecimal = DECIMAL(ENTRY(parameterNumber, parameterValues, listSeperationChar)) NO-ERROR.
          parameterValue = SUBSTITUTE("&1", inputDecimal).
          procedureCall:SET-PARAMETER(parameterNumber, parameterDataType, parameterMode, inputDecimal).
        END.
        ELSE IF parameterDataType = "INTEGER" THEN DO:
          inputInteger = INTEGER(ENTRY(parameterNumber, parameterValues, listSeperationChar)) NO-ERROR.
          parameterValue = SUBSTITUTE("&1", inputInteger).
          procedureCall:SET-PARAMETER(parameterNumber, parameterDataType, parameterMode, inputInteger).
        END.
        ELSE IF parameterDataType = "LOGICAL" THEN DO:
          inputLogical = LOGICAL(ENTRY(parameterNumber, parameterValues, listSeperationChar)) NO-ERROR.
          parameterValue = SUBSTITUTE("&1", inputLogical).
          procedureCall:SET-PARAMETER(parameterNumber, parameterDataType, parameterMode, inputLogical).
        END.
        ELSE IF parameterDataType = "DATE" THEN DO:
          inputDate = DATE(ENTRY(parameterNumber, parameterValues, listSeperationChar)) NO-ERROR.
          parameterValue = SUBSTITUTE("&1", inputDate).
          procedureCall:SET-PARAMETER(parameterNumber, parameterDataType, parameterMode, inputDate).
        END.
        ELSE IF parameterName = "TABLE" THEN DO:
          temptableHandle = tempTableSource:GetTempTable(parameterDataType, procedureName, internalProcedureName).
          IF temptableHandle = ? THEN DO:
            StoreError(procedureName, internalProcedureName, SUBSTITUTE("Error creating temp-table for &1", parameterDataType)).
            NEXT _PARAMETER.
          END.

          procedureCall:SET-PARAMETER(parameterNumber, "TABLE-HANDLE", parameterMode, temptableHandle).

          tempTableSource:LogTableRecordCount(parameterMode, tempTableHandle).
        END.
        ELSE DO:
          procedureCall:SET-PARAMETER(parameterNumber, parameterDataType, parameterMode, ?).
        END.

        Log:Debug("        Parameter ~{ParameterNumber~} ~{ParameterMode~} ~{ParameterDataType~} = [~{ParameterValue~}]", BOX(parameterNumber), BOX(parameterMode), BOX(parameterDataType), BOX(parameterValue)).
      END.

    END.

    DEFINE VARIABLE startTime AS INT64 NO-UNDO.
    DEFINE VARIABLE callDuration AS INT64 NO-UNDO.
    startTime = ETIME.

    /*this should be moved out of here if possible*/
    DO ON ERROR UNDO, THROW:
      procedureCall:INVOKE NO-ERROR.
      IF ERROR-STATUS:ERROR THEN DO:
        DEFINE VARIABLE getErrorMessage AS CHARACTER NO-UNDO.
        getErrorMessage = ERROR-STATUS:GET-MESSAGE(1).

        failedReplays = failedReplays + 1.
        callDuration = MTIME - startTime.

        Log:Error("    Run failed: ~{ErrorMessage~}", BOX(getErrorMessage)).
        StoreError(procedureName, internalProcedureName, getErrorMessage).
        RETURN.
      END.
      LogOutputTables().

      CATCH se AS Progress.Lang.SysError:
        failedReplays = failedReplays + 1.
        Log:Error("    Run failed: ~{ErrorMessage~}", BOX(se:GetMessage(1))).
        StoreError(procedureName, internalProcedureName, se:GetMessage(1)).
        RETURN.
      END CATCH.
      CATCH e AS Progress.Lang.Error:
        failedReplays = failedReplays + 1.
        Log:Error("    Run failed: ~{ErrorMessage~}", BOX(e:GetMessage(1))).
        StoreError(procedureName, internalProcedureName, e:GetMessage(1)).
        RETURN.
      END CATCH.
    END.
    callDuration = ETIME - startTime.
    totalAppserverCallMs = totalAppserverCallMs + callDuration.
    passedReplays = passedReplays + 1.

    Log:Information("    Run completed in ~{CallDurationMs~}ms (~{CallDurationS~}s)", BOX(callDuration), BOX(callDuration / 1000)).
/*    Log:Information("    Ran ~{InternalProcedure~} on ~{Procedure~} on Appserver in ~{CallDurationMs~}ms (~{CallDurationS~}s)", BOX(traceRun:InternalProcedure), BOX(traceRun:Procedure), BOX(callDuration), BOX(callDuration / 1000)).*/

    THIS-OBJECT:ReplaySession:AddCallDetail(currentReplaySource:TraceFileSource:TraceFilePath, procedureName, internalProcedureName, callDuration).

  END METHOD.

  METHOD VOID LogOutputTables():
    DEFINE VARIABLE thisTable AS INTEGER NO-UNDO.
    DEFINE VARIABLE temptableHandle AS HANDLE NO-UNDO.

    IF outputTables <> "" THEN DO:
      DO thisTable = 1 TO NUM-ENTRIES(outputTables):
        temptableHandle = HANDLE(ENTRY(thisTable, outputTables)).
        tempTableSource:LogTableRecordCount("OUTPUT", temptableHandle).

        IF ShouldLogTableRecords(temptableHandle:NAME) THEN DO:
          tempTableSource:LogTableRecords(temptableHandle).
        END.
      END.
    END.
  END METHOD.

  METHOD PUBLIC LOGICAL ShouldLogTableRecords(tableName AS CHARACTER):
    RETURN (
              (Settings:Application:DisplayRecordsInclude = "*"
                OR LOOKUP(tableName, Settings:Application:DisplayRecordsInclude) > 0
              )
              AND NOT
              (Settings:Application:DisplayRecordsExclude = "*"
                OR LOOKUP(tableName, Settings:Application:DisplayRecordsExclude) > 0
              )
           ).
  END.

  METHOD PUBLIC CHARACTER StoreError(procedureName AS CHARACTER, internalProcedureName AS CHARACTER, errorMessage AS CHARACTER):
    CREATE ReplayErrors.
    ASSIGN
      ReplayErrors.procedureName = procedureName
      ReplayErrors.internalProcedureName = internalProcedureName
      ReplayErrors.errorMessage = errorMessage.
  END METHOD.

  METHOD PUBLIC CHARACTER AddToSpaceValueCache(parameterValue AS CHARACTER):
    DEFINE VARIABLE charredValue AS CHARACTER NO-UNDO.
    charredValue = REPLACE(parameterValue, " ", listSeperationChar).
    IF NOT CAN-FIND(FIRST SpaceValue WHERE SpaceValue.charredValue = charredValue) THEN DO:
      Log:Debug("    Adding space value ~"~{SpaceValue~}~"", BOX(parameterValue)).
      CREATE SpaceValue.
      ASSIGN
        SpaceValue.charredValue = charredValue
        SpaceValue.spacedValue = parameterValue
        SpaceValue.numberOfSpaces = NUM-ENTRIES(parameterValue, listSeperationChar).
    END.
  END METHOD.

  METHOD PUBLIC CHARACTER AddBlacklistedCall(procedureName AS CHARACTER, internalProcedureName AS CHARACTER):
    IF NOT CAN-FIND(FIRST BlacklistedCall
                      WHERE BlacklistedCall.procedureName = procedureName
                        AND BlacklistedCall.internalProcedureName = internalProcedureName)
    THEN DO:
      CREATE BlacklistedCall.
      ASSIGN
        BlacklistedCall.procedureName = procedureName
        BlacklistedCall.internalProcedureName = internalProcedureName.
    END.
  END METHOD.

  METHOD PUBLIC CHARACTER GetParameterValues(expectedNumberOfParameters AS INTEGER, parameterString AS CHARACTER):
    DEFINE VARIABLE parameterValues AS CHARACTER NO-UNDO.

    /* if only expecting 1 value then we know it's the whole parameter string*/
    IF expectedNumberOfParameters = 1 THEN DO:
      IF INDEX(parameterString, " ") > 0 THEN DO:
        AddToSpaceValueCache(parameterString).
      END.
      RETURN parameterString.
    END.

    /* no spaces in values*/
    parameterValues = REPLACE(parameterString, " ", listSeperationChar).
    IF NUM-ENTRIES(parameterValues, listSeperationChar) = expectedNumberOfParameters THEN DO:
      RETURN parameterValues.
    END.

    /* replace known space values starting with most spaces */
    FOR EACH SpaceValue BY numberOfSpaces DESCENDING:
      parameterValues = REPLACE(parameterValues, SpaceValue.charredValue, SpaceValue.spacedValue).
      IF NUM-ENTRIES(parameterValues, listSeperationChar) = expectedNumberOfParameters THEN DO:
        RETURN parameterValues.
      END.
    END.

    RETURN parameterValues.
  END METHOD.

END CLASS.
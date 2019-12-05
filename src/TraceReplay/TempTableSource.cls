USING ABLContainer.Logging.* FROM PROPATH.
USING System.IO.* FROM ASSEMBLY.
USING Progress.Lang.*.
USING Settings.* FROM PROPATH.
USING TraceReplay.* FROM PROPATH.

BLOCK-LEVEL ON ERROR UNDO, THROW.

CLASS TraceReplay.TempTableSource:

  DEFINE VARIABLE hStaticTempTables AS HANDLE NO-UNDO.
  DEFINE VARIABLE countQuery AS HANDLE NO-UNDO.

  DEFINE TEMP-TABLE CreatedTempTable NO-UNDO
    FIELD tableName AS CHARACTER
    FIELD ttHandle AS HANDLE
    FIELD sourceFile AS CHARACTER
    FIELD wasUsed AS LOGICAL
    INDEX iPrimary IS PRIMARY tableName.

  DEFINE PUBLIC PROPERTY TempTableDefinitions AS TempTableDefinitions NO-UNDO
  GET.
  SET.

  CONSTRUCTOR TempTableSource ():
    TempTableDefinitions = NEW TempTableDefinitions().
    IF Settings:Application:StaticTempTableProcedure <> "" THEN DO:
      RUN VALUE(Settings:Application:StaticTempTableProcedure) PERSISTENT SET hStaticTempTables.
    END.
  END CONSTRUCTOR.

    CREATE QUERY countQuery.

  END CONSTRUCTOR.

  METHOD PUBLIC VOID EmptyTempTables():
    Log:Information("Emptying temp-tables...").
    FOR EACH CreatedTempTable:
      CreatedTempTable.ttHandle:DEFAULT-BUFFER-HANDLE:EMPTY-TEMP-TABLE().
    END.
  END METHOD.

  METHOD PUBLIC INTEGER CountTableRecords(tempTableHandle AS HANDLE):
    DEFINE VARIABLE recordCount AS INTEGER NO-UNDO.

    countQuery:SET-BUFFERS(tempTableHandle:DEFAULT-BUFFER-HANDLE).
    countQuery:QUERY-PREPARE(SUBSTITUTE("FOR EACH &1 NO-LOCK", tempTableHandle:NAME)).
    countQuery:QUERY-OPEN().
    recordCount = 0.
    countQuery:GET-NEXT().
    DO WHILE countQuery:QUERY-OFF-END = FALSE:
      recordCount = recordCount + 1.
      countQuery:GET-NEXT().
    END.
    countQuery:QUERY-CLOSE().

    RETURN recordCount.
  END METHOD.

  METHOD PUBLIC HANDLE GetTempTable(tempTableName AS CHARACTER, sourceProcedure AS CHARACTER, sourceInternalProcedure AS CHARACTER):
    DEFINE VARIABLE tableName AS CHARACTER NO-UNDO.
    DEFINE VARIABLE tempTableHandle AS HANDLE NO-UNDO.

    tableName = REPLACE(tempTableName, "tt_", "").

    FIND FIRST CreatedTempTable
      WHERE CreatedTempTable.tableName = tempTableName
      NO-LOCK NO-ERROR.
    IF AVAILABLE CreatedTempTable THEN DO:
      tempTableHandle = CreatedTempTable.ttHandle.
      Log:Debug("            Using temp-table ~{TempTableName~} from cache.", BOX(tempTableName)).
    END.
    ELSE DO:
      Log:Debug("            Creating temp-table ~{TempTableName~}...", BOX(tempTableName)).

      CREATE TEMP-TABLE tempTableHandle IN WIDGET-POOL "TempTablePool".
      tempTableHandle:CREATE-LIKE(tempTableName) NO-ERROR.
      IF ERROR-STATUS:ERROR THEN DO:
        DELETE OBJECT tempTableHandle.
        CREATE TEMP-TABLE tempTableHandle IN WIDGET-POOL "TempTablePool".
        tempTableHandle:CREATE-LIKE(tableName) NO-ERROR.
        IF ERROR-STATUS:ERROR THEN DO:
          tempTableHandle = GetTempTableFromSource(tempTableName, sourceProcedure).
          Log:Error("            ERROR: ~{ErrorMessage~}...", BOX(ERROR-STATUS:GET-MESSAGE(1))).
          RETURN ?.
        END.
      END.

      tempTableHandle:TEMP-TABLE-PREPARE(tempTableName).
      tempTableHandle:UNDO = FALSE.

      CacheTempTable(tempTableName, tempTableHandle).
    END.

    /* clear current results in certain cases */
    IF sourceProcedure = "trno.p"
      AND sourceInternalProcedure = "GetResultsTRNO"
    THEN DO:
      tempTableHandle:DEFAULT-BUFFER-HANDLE:EMPTY-TEMP-TABLE().
    END.
    RETURN tempTableHandle.

  END METHOD.

  METHOD PUBLIC HANDLE GetTempTableFromSource(tempTableName AS CHARACTER, sourceProcedure AS CHARACTER):
    RETURN ?.
  END METHOD.

  METHOD PUBLIC VOID CacheTempTable (tempTableName AS CHARACTER, tableHandle AS HANDLE, sourceFile AS CHARACTER):
    IF NOT CAN-FIND(FIRST CreatedTempTable WHERE CreatedTempTable.tableName = LC(tempTableName)) THEN DO:
      Log:Debug("    Caching temp-table ~{TempTableName~} with ~{NumberOfFields~} fields", BOX(tempTableName), BOX(tableHandle:DEFAULT-BUFFER-HANDLE:NUM-FIELDS)).
      CREATE CreatedTempTable.
      ASSIGN
        CreatedTempTable.tableName = LC(tempTableName)
        CreatedTempTable.ttHandle = tableHandle
        CreatedTempTable.sourceFile = sourceFile.
    END.
  END METHOD.

  METHOD VOID LogTableRecordCount(direction AS CHARACTER, temptableHandle AS HANDLE):
    DEFINE VARIABLE recordCount AS INTEGER NO-UNDO.
    recordCount = CountTableRecords(tempTableHandle).
    DEFINE VARIABLE directionText AS CHARACTER NO-UNDO.
    IF direction MATCHES "*INPUT*" THEN DO:
      directionText = "Passing".
    END.
    ELSE DO:
      directionText = "Received".
    END.

    IF recordCount > 0 THEN DO:
      Log:Information("        ~{Direction~} ~{RecordCount~} record(s) in temp-table ~{TempTableName~}", BOX(directionText), BOX(recordCount), BOX(tempTableHandle:NAME)).
    END.
  END METHOD.

  METHOD VOID LogTableRecords(temptableHandle AS HANDLE):
    DEFINE VARIABLE recordCount AS INTEGER NO-UNDO.
    DEFINE VARIABLE tempTableBuffer AS HANDLE NO-UNDO.

    DEFINE VARIABLE displayRecordsLimit AS INTEGER NO-UNDO.
    displayRecordsLimit = Settings:Application:DisplayRecordsLimit.

    tempTableBuffer = temptableHandle:DEFAULT-BUFFER-HANDLE.

    countQuery:SET-BUFFERS(tempTableBuffer).
    countQuery:QUERY-PREPARE(SUBSTITUTE("FOR EACH &1 NO-LOCK", tempTableHandle:NAME)).
    countQuery:QUERY-OPEN().
    recordCount = 0.
    countQuery:GET-NEXT().
    _RECORDS:
    DO WHILE countQuery:QUERY-OFF-END = FALSE:
      recordCount = recordCount + 1.
      LogRecord(recordCount, tempTableBuffer).
      IF recordCount >= displayRecordsLimit THEN LEAVE _RECORDS.
      countQuery:GET-NEXT().
    END.
    countQuery:QUERY-CLOSE().

  END METHOD.

  METHOD VOID LogRecord(recordNumber AS INTEGER, recordBuffer AS HANDLE):
    DEFINE VARIABLE thisField AS INTEGER NO-UNDO.
    DEFINE VARIABLE bufferFieldHandle AS HANDLE NO-UNDO.

    Log:Information("          Record number ~{RecordNumber~}:", BOX(recordNumber)).
    DO thisField = 1 TO recordBuffer:NUM-FIELDS:
      bufferFieldHandle = recordBuffer:BUFFER-FIELD(thisField).
      Log:Information("            ~{FieldName~}=[~{FieldValue~}]", BOX(bufferFieldHandle:NAME), BOX(bufferFieldHandle:BUFFER-VALUE())).
    END.

  END METHOD.

END CLASS.
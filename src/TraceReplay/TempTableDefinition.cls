USING ABLContainer.Logging.* FROM PROPATH.
USING Progress.Lang.*.
USING TraceReplay.* FROM PROPATH.

BLOCK-LEVEL ON ERROR UNDO, THROW.

CLASS TraceReplay.TempTableDefinition:

  DEFINE VARIABLE fieldSequence AS INTEGER NO-UNDO.
  DEFINE TEMP-TABLE tt_FieldDefinitions NO-UNDO
    FIELD sequence AS INTEGER
    FIELD fieldDefinition AS CLASS Object.

  DEFINE PUBLIC PROPERTY SourceFile AS CHARACTER NO-UNDO
  GET.
  SET.
  DEFINE PUBLIC PROPERTY Name AS CHARACTER NO-UNDO
  GET.
  SET.
  DEFINE PUBLIC PROPERTY LikeTable AS CHARACTER NO-UNDO
  GET.
  SET.
  DEFINE PUBLIC PROPERTY IsLikeTempTable AS LOGICAL NO-UNDO
  GET.
  SET.
  DEFINE PUBLIC PROPERTY FieldDefinitions AS FieldDefinition EXTENT NO-UNDO
  GET.
  SET.
  DEFINE PUBLIC PROPERTY TempTableHandle AS HANDLE NO-UNDO
  GET.
  SET.
  DEFINE PUBLIC PROPERTY HasLikeFields AS LOGICAL NO-UNDO
  GET.
  SET.

  METHOD HANDLE CreateTempTable(tempTableSource AS TempTableSource):
    DEFINE VARIABLE tempTableHandle AS HANDLE NO-UNDO.

    CREATE TEMP-TABLE tempTableHandle IN WIDGET-POOL "TempTablePool".
    IF THIS-OBJECT:LikeTable <> "" THEN DO:
      Log:Debug("            Creating ~{TempTableName~} like ~{TempTableLike~} (~{SourceFile~})...", BOX(THIS-OBJECT:Name), BOX(THIS-OBJECT:LikeTable), BOX(THIS-OBJECT:SourceFile)).
      IF THIS-OBJECT:LikeTable BEGINS "tt_"
        OR THIS-OBJECT:LikeTable BEGINS "ltt_"
      THEN DO:
        DEFINE VARIABLE likeTableHandle AS HANDLE NO-UNDO.
        likeTableHandle = tempTableSource:GetTempTableFromCache(THIS-OBJECT:LikeTable).
        IF likeTableHandle = ? THEN DO:
          Log:Debug("                CREATE-LIKE ERROR: Temp table for like not found! ~{SourceFile~}", BOX(THIS-OBJECT:SourceFile)).
          RETURN ?.
        END.
        tempTableHandle:CREATE-LIKE(likeTableHandle) NO-ERROR.
      END.
      ELSE DO:
        tempTableHandle:CREATE-LIKE(THIS-OBJECT:LikeTable) NO-ERROR.
      END.
      IF ERROR-STATUS:ERROR THEN DO:
        Log:Debug("                CREATE-LIKE ERROR: ~{ErrorMessage~} ~{SourceFile~}", BOX(ERROR-STATUS:GET-MESSAGE(1)), BOX(THIS-OBJECT:SourceFile)).
        RETURN ?.
      END.
    END.
    ELSE DO:
      Log:Debug("            Creating ~{TempTableName~} (~{SourceFile~})...", BOX(THIS-OBJECT:Name), BOX(THIS-OBJECT:SourceFile)).
    END.

    DEFINE VARIABLE thisField AS INTEGER NO-UNDO.
    DEFINE VARIABLE numberOfFields AS INTEGER NO-UNDO.
    DEFINE VARIABLE fieldCreated AS LOGICAL NO-UNDO.

    IF EXTENT(THIS-OBJECT:FieldDefinitions) <> ? THEN DO:
      Log:Debug("            Adding fields...").
      numberOfFields = EXTENT(THIS-OBJECT:FieldDefinitions).
      DO thisField = 1 TO numberOfFields:
        fieldCreated = THIS-OBJECT:FieldDefinitions[thisField]:AddToTempTable(tempTableSource, tempTableHandle).
        IF NOT fieldCreated THEN DO:
          Log:Error("                ERROR: Field ~{FieldName~} was not created!", BOX(THIS-OBJECT:FieldDefinitions[thisField]:Name)).
          RETURN ?.
        END.
      END.
    END.

    tempTableHandle:TEMP-TABLE-PREPARE(THIS-OBJECT:Name) NO-ERROR.
    IF ERROR-STATUS:ERROR THEN DO:
      Log:Error("            TEMP-TABLE-PREPARE ERROR: ~{ErrorMesage~} ~{SourceFile~}", BOX(ERROR-STATUS:GET-MESSAGE(1)), BOX(THIS-OBJECT:SourceFile)).
      RETURN ?.
    END.

    tempTableHandle:UNDO = FALSE.

    THIS-OBJECT:TempTableHandle = tempTableHandle.

    RETURN tempTableHandle.
  END METHOD.

  METHOD VOID Finalise():
    IF fieldSequence = 0 THEN RETURN.

    EXTENT(FieldDefinitions) = fieldSequence.
    FOR EACH tt_FieldDefinitions BY sequence:
      FieldDefinitions[tt_FieldDefinitions.sequence] = CAST(tt_FieldDefinitions.fieldDefinition, FieldDefinition).
    END.
  END METHOD.

  METHOD VOID AddField(fieldDefinition AS FieldDefinition):
    fieldSequence = fieldSequence + 1.
    CREATE tt_FieldDefinitions.
    ASSIGN
      tt_FieldDefinitions.sequence = fieldSequence
      tt_FieldDefinitions.fieldDefinition = fieldDefinition.
    IF fieldDefinition:LikeField <> ""
      AND fieldDefinition:LikeField BEGINS "tt_"
    THEN DO:
      THIS-OBJECT:HasLikeFields = TRUE.
    END.
  END METHOD.

END CLASS.
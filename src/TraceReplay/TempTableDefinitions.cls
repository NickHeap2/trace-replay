
USING Progress.Lang.*.
USING TraceReplay.* FROM PROPATH.

BLOCK-LEVEL ON ERROR UNDO, THROW.

CLASS TraceReplay.TempTableDefinitions:

  DEFINE VARIABLE tempTableSequence AS INTEGER NO-UNDO.
  DEFINE TEMP-TABLE tt_TempTableDefinition NO-UNDO
    FIELD sequence AS INTEGER
    FIELD name AS CHARACTER
    FIELD likeTable AS CHARACTER
    FIELD hasLikeFields AS LOGICAL
    FIELD tempTableDefinition AS CLASS Object
    FIELD isLikeTempTable AS LOGICAL
    FIELD added AS LOGICAL
    FIELD valid AS LOGICAL.

  DEFINE PUBLIC PROPERTY TempTableDefinitions AS TempTableDefinition EXTENT NO-UNDO
  GET.
  SET.

  METHOD LOGICAL IsDefined(tempTableName AS CHARACTER):
    RETURN CAN-FIND(FIRST tt_TempTableDefinition WHERE tt_TempTableDefinition.name = tempTableName).
  END METHOD.

  METHOD VOID Finalise():
    IF tempTableSequence = 0 THEN RETURN.

    EXTENT(TempTableDefinitions) = tempTableSequence.
    DEFINE VARIABLE addedSequence AS INTEGER NO-UNDO.

    /* temp-table with no dependencies */
    FOR EACH tt_TempTableDefinition
      WHERE tt_TempTableDefinition.likeTable = ""
        AND tt_TempTableDefinition.hasLikeFields = FALSE
        AND tt_TempTableDefinition.added = FALSE
      BY sequence:
      addedSequence = addedSequence + 1.
      TempTableDefinitions[addedSequence] = CAST(tt_TempTableDefinition.tempTableDefinition, TempTableDefinition).
      tt_TempTableDefinition.added = TRUE.
    END.
    /* like base tables with no tt dependencies */
    FOR EACH tt_TempTableDefinition
      WHERE tt_TempTableDefinition.likeTable <> ""
        AND tt_TempTableDefinition.isLikeTempTable = FALSE
        AND tt_TempTableDefinition.hasLikeFields = FALSE
        AND tt_TempTableDefinition.added = FALSE
      BY sequence:
      addedSequence = addedSequence + 1.
      TempTableDefinitions[addedSequence] = CAST(tt_TempTableDefinition.tempTableDefinition, TempTableDefinition).
      tt_TempTableDefinition.added = TRUE.
    END.
    /* like a tt but no tt like fields*/
    FOR EACH tt_TempTableDefinition
      WHERE tt_TempTableDefinition.likeTable <> ""
        AND tt_TempTableDefinition.isLikeTempTable = TRUE
        AND tt_TempTableDefinition.hasLikeFields = FALSE
        AND tt_TempTableDefinition.added = FALSE
      BY sequence:
      addedSequence = addedSequence + 1.
      TempTableDefinitions[addedSequence] = CAST(tt_TempTableDefinition.tempTableDefinition, TempTableDefinition).
      tt_TempTableDefinition.added = TRUE.
    END.
    /* has tt like fields */
    FOR EACH tt_TempTableDefinition
      WHERE tt_TempTableDefinition.hasLikeFields = TRUE
        AND tt_TempTableDefinition.added = FALSE
      BY sequence:
      addedSequence = addedSequence + 1.
      TempTableDefinitions[addedSequence] = CAST(tt_TempTableDefinition.tempTableDefinition, TempTableDefinition).
      tt_TempTableDefinition.added = TRUE.
    END.

  END METHOD.

  METHOD VOID AddTempTable(tempTableDefinition AS TempTableDefinition):
    tempTableSequence = tempTableSequence + 1.
    CREATE tt_TempTableDefinition.
    ASSIGN
      tt_TempTableDefinition.sequence = tempTableSequence
      tt_TempTableDefinition.name = tempTableDefinition:Name
      tt_TempTableDefinition.likeTable = tempTableDefinition:LikeTable
      tt_TempTableDefinition.hasLikeFields = tempTableDefinition:HasLikeFields
      tt_TempTableDefinition.tempTableDefinition = tempTableDefinition.
    IF tempTableDefinition:LikeTable BEGINS "tt_" THEN DO:
      tt_TempTableDefinition.IsLikeTempTable = TRUE.
    END.
  END METHOD.

END CLASS.
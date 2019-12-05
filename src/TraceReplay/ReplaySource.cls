USING ABLContainer.Logging.* FROM PROPATH.
USING Progress.Lang.* FROM PROPATH.
USING System.IO.* FROM ASSEMBLY.
USING TraceReplay.* FROM PROPATH.
USING TraceAnalysis.* FROM ASSEMBLY.

BLOCK-LEVEL ON ERROR UNDO, THROW.

CLASS TraceReplay.ReplaySource:
  DEFINE VARIABLE lAppserverCallIsNext AS LOGICAL NO-UNDO.
  DEFINE VARIABLE currentCallSequence AS INTEGER NO-UNDO.

  DEFINE TEMP-TABLE tt_AppserverCall NO-UNDO
    FIELD callSequence AS INTEGER
    FIELD appservercall AS OBJECT
    INDEX iPrimary IS PRIMARY callSequence.

  DEFINE PUBLIC PROPERTY TraceFileSource AS TraceFileSource NO-UNDO
  GET.
  SET.

  DEFINE PUBLIC PROPERTY Current AS AppserverCall NO-UNDO
  GET.
  SET.

  CONSTRUCTOR ReplaySource (traceFileSource AS TraceFileSource):

    THIS-OBJECT:TraceFileSource = traceFileSource.
    currentCallSequence = 0.
    /* start visiting the replay source */
    traceFileSource:Accept(THIS-OBJECT).

  END CONSTRUCTOR.

  METHOD PUBLIC VOID VisitTraceRun(traceRun AS TraceRun):
    IF NOT lAppserverCallIsNext THEN RETURN.
    lAppserverCallIsNext = FALSE.

    currentCallSequence = currentCallSequence + 1.

    DEFINE VARIABLE appserverCall AS AppserverCall NO-UNDO.
    appserverCall = NEW AppserverCall().
    appserverCall:ProcedureName = traceRun:Procedure.
    appserverCall:InternalProcedureName = tracerun:InternalProcedure.
    appserverCall:Parameters = tracerun:Parameters.

    CREATE tt_AppserverCall.
    ASSIGN
      tt_AppserverCall.callSequence = currentCallSequence
      tt_AppserverCall.appservercall = appserverCall.
    Log:Debug("    Added ~{InternalProcedure~} in ~{Procedure~}.", BOX(appservercall:InternalProcedureName), BOX(appservercall:ProcedureName)).
    Log:Debug("        " + traceRun:Content).

  END METHOD.

  METHOD PUBLIC VOID VisitTraceFunc(traceFunc AS TraceFunc):
    /* this function is always used to call to the appserver */
    IF traceFunc:Function = "RunOnAppserver" THEN DO:
      lAppserverCallIsNext = TRUE.
    END.
  END METHOD.

  METHOD PUBLIC VOID Reset():
    FIND FIRST tt_AppserverCall NO-ERROR.
    FIND PREV tt_AppserverCall NO-ERROR.
  END METHOD.

  METHOD PUBLIC LOGICAL GetNext():
    FIND NEXT tt_AppserverCall NO-ERROR.
    IF AVAILABLE(tt_AppserverCall) THEN DO:
      THIS-OBJECT:Current = CAST(tt_AppserverCall.appservercall, AppserverCall).
    END.
    ELSE DO:
      THIS-OBJECT:Current = ?.
    END.

    RETURN AVAILABLE(tt_AppserverCall).
  END METHOD.

END CLASS.
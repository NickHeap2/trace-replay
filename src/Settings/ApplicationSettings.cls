USING ABLContainer.Logging.* FROM PROPATH.
USING Progress.Lang.*.

BLOCK-LEVEL ON ERROR UNDO, THROW.

CLASS Settings.ApplicationSettings INHERITS System.Object:

  DEFINE PUBLIC PROPERTY AppserverPF AS CHARACTER NO-UNDO
  GET.
  SET.
  DEFINE PUBLIC PROPERTY Playthroughs AS INTEGER NO-UNDO
  GET.
  SET.
  DEFINE PUBLIC PROPERTY StubProcedure AS CHARACTER NO-UNDO
  GET.
  SET.
  DEFINE PUBLIC PROPERTY TraceLogFiles AS CHARACTER NO-UNDO
  GET.
  SET.
  DEFINE PUBLIC PROPERTY RandomiseSources AS LOGICAL NO-UNDO
  GET.
  SET.
  DEFINE PUBLIC PROPERTY TimeLimitMinutes AS INTEGER NO-UNDO
  GET.
  SET.
  DEFINE PUBLIC PROPERTY StaticTempTableProcedure AS CHARACTER NO-UNDO
  GET.
  SET.
  DEFINE PUBLIC PROPERTY ValueReplaceProcedure AS CHARACTER NO-UNDO
  GET.
  SET.
  DEFINE PUBLIC PROPERTY DisplayRecordsInclude AS CHARACTER NO-UNDO
  GET.
  SET.
  DEFINE PUBLIC PROPERTY DisplayRecordsExclude AS CHARACTER NO-UNDO
  GET.
  SET.
  DEFINE PUBLIC PROPERTY DisplayRecordsLimit AS INTEGER NO-UNDO
  GET.
  SET.
  DEFINE PUBLIC PROPERTY JunitResultsFilename AS CHARACTER NO-UNDO
  GET.
  SET.

  METHOD PUBLIC VOID LogCurrent(  ):

    Log:Information("Application Settings").
    Log:Information("  AppserverPF: ~{AppserverPF~}", BOX(THIS-OBJECT:AppserverPF)).
    Log:Information("  Playthroughs: ~{Playthroughs~}", BOX(THIS-OBJECT:Playthroughs)).
    Log:Information("  StubProcedure: ~{StubProcedure~}", BOX(THIS-OBJECT:StubProcedure)).
    Log:Information("  TraceLogFiles: ~{TraceLogFiles~}", BOX(THIS-OBJECT:TraceLogFiles)).
    Log:Information("  RandomiseSources: ~{RandomiseSources~}", BOX(THIS-OBJECT:RandomiseSources)).
    Log:Information("  TimeLimitMinutes: ~{TimeLimitMinutes~}", BOX(THIS-OBJECT:TimeLimitMinutes)).
    Log:Information("  StaticTempTableProcedure: ~{StaticTempTableProcedure~}", BOX(THIS-OBJECT:StaticTempTableProcedure)).
    Log:Information("  ValueReplaceProcedure: ~{ValueReplaceProcedure~}", BOX(THIS-OBJECT:ValueReplaceProcedure)).
    Log:Information("  DisplayRecordsInclude: ~{DisplayRecordsInclude~}", BOX(THIS-OBJECT:DisplayRecordsInclude)).
    Log:Information("  DisplayRecordsExclude: ~{DisplayRecordsExclude~}", BOX(THIS-OBJECT:DisplayRecordsExclude)).
    Log:Information("  DisplayRecordsLimit: ~{DisplayRecordsLimit~}", BOX(THIS-OBJECT:DisplayRecordsLimit)).
    Log:Information("  JunitResultsFilename: ~{JunitResultsFilename~}", BOX(THIS-OBJECT:JunitResultsFilename)).

  END METHOD.

END CLASS.
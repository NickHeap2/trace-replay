/* ***************************  Definitions  ************************** */
USING ABLContainer.Logging.* FROM PROPATH.
USING Settings.* FROM PROPATH.
USING TraceReplay.* FROM PROPATH.

BLOCK-LEVEL ON ERROR UNDO, THROW.

/* ********************  Preprocessor Definitions  ******************** */

/* ***************************  Main Block  *************************** */

DEFINE VARIABLE stubProcedure AS HANDLE NO-UNDO.

DO ON ERROR UNDO, LEAVE:
  /* run stub class if defined */
  IF Settings:Application:StubProcedure <> "" THEN DO:
    Log:Information("Initialising stub procedure ~{StubProcedure~}...", BOX(Settings:Application:StubProcedure)).
    RUN VALUE(Settings:Application:StubProcedure) PERSISTENT SET stubProcedure.
    RUN Initialise IN stubProcedure.
  END.

  DEFINE VARIABLE replaySession AS ReplaySession NO-UNDO.
  Log:Information("Starting replay session...").
  replaySession = NEW ReplaySession().
  replaySession:StartSession().

  CATCH apper AS Progress.Lang.AppError :
    Log:Error("[Startup.p]ERROR: (~{ErrorMessage~})", BOX(apper:ReturnValue)).
  END CATCH.
  CATCH er AS Progress.Lang.Error :
    Log:Error("[Startup.p]ERROR: (~{ErrorMessage~})", BOX(er:GetMessage(1))).
    Log:Error("[Startup.p]     : (~{CallStack~})", BOX(er:CallStack)).
  END CATCH.
  FINALLY:
    Log:CloseAndFlush().
    IF VALID-OBJECT(replaySession) THEN DO:
      DELETE OBJECT replaySession.
    END.
  END FINALLY.
END.


USING ABLContainer.Configuration.* FROM PROPATH.
USING OpenEdge.Core.Assert FROM PROPATH.
USING Settings.* FROM PROPATH.
USING System.IO.* FROM ASSEMBLY.
USING TraceReplay.* FROM PROPATH.

BLOCK-LEVEL ON ERROR UNDO, THROW.

CLASS TraceReplay.test_ReplaySession:

  DEFINE VARIABLE test_replaySession AS TraceReplay.ReplaySession NO-UNDO.

  @Before.
  METHOD PUBLIC VOID before(  ):
    DEFINE VARIABLE configurationBuilder AS ABLContainer.Configuration.ConfigurationBuilder NO-UNDO.
    configurationBuilder = NEW ConfigurationBuilder().
    configurationBuilder:AddJsonFile("appsettings.test.json", FALSE).
    ABLContainer.Configuration.Configuration:Current = configurationBuilder:Build().

    test_replaySession = NEW TraceReplay.ReplaySession().
    Assert:NotNull(test_replaySession).

    DEFINE VARIABLE test_traceFileSource AS TraceFileSource NO-UNDO.
    test_traceFileSource = NEW TraceFileSource("testing.log").
    Assert:NotNull(test_traceFileSource).

    EXTENT(test_replaySession:ReplaySources) = 1.
    test_replaySession:ReplaySources[1] = NEW ReplaySource(test_traceFileSource).

  END METHOD.

  @Test.
  METHOD PUBLIC VOID canLogStats(  ):
    DEFINE VARIABLE resultsFilename AS CHARACTER NO-UNDO.
    resultsFilename = Settings:Application:JunitResultsFilename.
    File:Delete(resultsFilename) NO-ERROR.
    Assert:IsFalse(File:Exists(resultsFilename)).

    test_replaySession:AddCallDetail("testing.log", "test1.p", "DoShortCall", 10).
    test_replaySession:AddCallDetail("testing.log", "test2.p", "DoLongCall", 99999).

    test_replaySession:Summarise().
    test_replaySession:WriteJunitResults().

    Assert:IsTrue(File:Exists(resultsFilename)).
    MESSAGE File:ReadAllText(resultsFilename).
  END METHOD.


  @After.
  METHOD PUBLIC VOID after(  ):
    IF VALID-OBJECT(test_replaySession) THEN DO:
      DELETE OBJECT test_replaySession NO-ERROR.
    END.
  END METHOD.

END CLASS.
USING ABLContainer.Logging.* FROM PROPATH.
USING Progress.Lang.* FROM PROPATH.
USING System.IO.* FROM ASSEMBLY.
USING TraceReplay.* FROM PROPATH.
USING TraceAnalysis.* FROM ASSEMBLY.

BLOCK-LEVEL ON ERROR UNDO, THROW.

CLASS TraceReplay.TraceFileSource:

  DEFINE PUBLIC PROPERTY TraceFilePath AS CHARACTER NO-UNDO
  GET.
  SET.
  DEFINE PUBLIC PROPERTY TraceEntries AS TraceEntry NO-UNDO
  GET.
  SET.

  DEFINE VARIABLE visitorMethods AS CHARACTER NO-UNDO.

  CONSTRUCTOR TraceFileSource (traceFilePath AS CHARACTER):
    IF NOT File:Exists(traceFilePath) THEN DO:
      UNDO, THROW NEW Progress.Lang.AppError(SUBSTITUTE("Input file path [&1] not found!", traceFilePath)).
    END.
    THIS-OBJECT:TraceFilePath = traceFilePath.

    DEFINE VARIABLE traceAnal AS TraceAnal NO-UNDO.
    traceAnal = NEW TraceAnal().
    Log:Information("    Analysing ~{FileName~}...", BOX(traceFilePath)).
    traceAnal:Analyse(traceFilePath).
    Log:Information("        Parsed ~{ParsedLines~} of ~{InputLines~} lines (~{UnparsedLines~} were not parsed).", BOX(traceAnal:ParsedLines), BOX(traceAnal:InputLines), BOX(traceAnal:UnparsedLines)).
    THIS-OBJECT:TraceEntries = traceAnal:TraceEntryTree.

  END CONSTRUCTOR.

  METHOD PUBLIC VOID Accept(visitor AS CLASS Progress.Lang.Object):
    visitorMethods = GetClassMethods(visitor).

    VisitVisitor(visitor, TraceEntries).

  END METHOD.

  METHOD PRIVATE CHARACTER VisitVisitor(visitor AS CLASS Progress.Lang.Object, traceEntry AS TraceEntry):

    DEFINE VARIABLE visitClassName AS CHARACTER NO-UNDO.
    DEFINE VARIABLE visitMethodName AS CHARACTER NO-UNDO.

    visitClassName = ENTRY(2, traceEntry:GetClass():TypeName, ".").
    visitMethodName = "Visit" + visitClassName.

/*    Log:Debug("At ~{ClassName~} ~{Description~}", BOX(visitClassName), BOX(traceEntry:Description)).*/

    IF INDEX(visitorMethods, visitMethodName) > 0 THEN DO:
/*      Log:Debug("    Visiting ~{ClassName~}", BOX(visitClassName)).*/
      DYNAMIC-INVOKE(visitor, visitMethodName, traceEntry).
    END.

    DEFINE VARIABLE childrenEnumerator AS "System.Collections.Generic.List<TraceAnalysis.TraceEntry>+Enumerator" NO-UNDO.
    childrenEnumerator = traceEntry:Children:GetEnumerator().
/*    DEFINE VARIABLE iChild AS INTEGER NO-UNDO.*/
    DEFINE VARIABLE childTraceEntry AS TraceEntry NO-UNDO.

    DO WHILE(childrenEnumerator:MoveNext()):
      childTraceEntry = childrenEnumerator:Current.
/*      iChild = iChild + 1.*/
/*      Log:Information("    Child ~{ChildNumber~} ~{Description~}", BOX(iChild), BOX(childTraceEntry:Description)).*/
      VisitVisitor(visitor, childTraceEntry).
    END.

  END METHOD.

  METHOD PRIVATE CHARACTER GetClassMethods(theClass AS CLASS Progress.Lang.Object):
    DEFINE VARIABLE classMethodsArray AS Progress.Reflect.Method EXTENT NO-UNDO.
    classMethodsArray = theClass:GetClass():GetMethods().

    DEFINE VARIABLE iClassMethod AS INTEGER NO-UNDO.
    DEFINE VARIABLE classMethods AS CHARACTER NO-UNDO.
    DO iClassMethod = 1 TO EXTENT(classMethodsArray):
/*      Log:Debug("~{ClassMethods~}", BOX(classMethodsArray[iClassMethod]:Name)).*/
      classMethods = classMethods + "," + classMethodsArray[iClassMethod]:Name.
    END.

    RETURN classMethods.

  END METHOD.

END CLASS.
/* ***************************  Definitions  ************************** */
USING TraceReplay.* FROM PROPATH.

BLOCK-LEVEL ON ERROR UNDO, THROW.

/* static temp table definitions */
DEFINE TEMP-TABLE tt_temptable NO-UNDO
  FIELD field1 AS CHARACTER
  FIELD field2 AS CHARACTER.

/* ********************  Preprocessor Definitions  ******************** */


/* ***************************  Main Block  *************************** */

PROCEDURE CacheTempTables:
  DEFINE INPUT PARAMETER tempTableSource AS TempTableSource NO-UNDO.

  tempTableSource:CacheTempTable("tt_temptable", TEMP-TABLE tt_temptable:HANDLE).

END.
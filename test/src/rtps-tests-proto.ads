------------------------------------------------------------------------------
--  RTPS.Tests.Proto -- AUnit tests for the StatefulWriter/StatefulReader
--  protocol machines (8.4.9.2 / 8.4.12.2)
------------------------------------------------------------------------------

with AUnit;
with AUnit.Test_Cases;

package RTPS.Tests.Proto is

   type Proto_Test is new AUnit.Test_Cases.Test_Case with null record;

   overriding procedure Register_Tests (T : in out Proto_Test);
   overriding function Name (T : Proto_Test) return AUnit.Message_String;

end RTPS.Tests.Proto;
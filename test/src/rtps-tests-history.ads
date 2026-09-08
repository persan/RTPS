------------------------------------------------------------------------------
--  RTPS.Tests.History -- HistoryCache checks (8.2.2)
------------------------------------------------------------------------------

with AUnit;
with AUnit.Test_Cases;

package RTPS.Tests.History is

   type History_Test is new AUnit.Test_Cases.Test_Case with null record;

   overriding procedure Register_Tests (T : in out History_Test);
   overriding function Name (T : History_Test) return AUnit.Message_String;

end RTPS.Tests.History;
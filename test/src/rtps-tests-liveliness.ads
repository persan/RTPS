------------------------------------------------------------------------------
--  RTPS.Tests.Liveliness -- AUnit tests for the Writer Liveliness
--  Protocol (8.4.13)
------------------------------------------------------------------------------

with AUnit;
with AUnit.Test_Cases;

package RTPS.Tests.Liveliness is

   type Liveliness_Test is new AUnit.Test_Cases.Test_Case with null record;

   overriding function Name
     (T : Liveliness_Test) return AUnit.Message_String;

   overriding procedure Register_Tests (T : in out Liveliness_Test);

end RTPS.Tests.Liveliness;
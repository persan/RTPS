------------------------------------------------------------------------------
--  RTPS.Tests.Header -- header encoding checks (clause 9.4.4 wire diagram)
------------------------------------------------------------------------------

with AUnit;
with AUnit.Test_Cases;
with RTPS.Messages;

package RTPS.Tests.Header is

   type Header_Test is new AUnit.Test_Cases.Test_Case with null record;

   overriding procedure Register_Tests (T : in out Header_Test);
   overriding function Name (T : Header_Test) return AUnit.Message_String;

end RTPS.Tests.Header;
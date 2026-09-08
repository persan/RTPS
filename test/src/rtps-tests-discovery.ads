------------------------------------------------------------------------------
--  RTPS.Tests.Discovery -- AUnit tests for SPDP/SEDP (clause 8.5)
------------------------------------------------------------------------------

with AUnit;
with AUnit.Test_Cases;

package RTPS.Tests.Discovery is

   type Discovery_Test is new AUnit.Test_Cases.Test_Case with null record;

   overriding function Name
     (T : Discovery_Test) return AUnit.Message_String;

   overriding procedure Register_Tests (T : in out Discovery_Test);

end RTPS.Tests.Discovery;
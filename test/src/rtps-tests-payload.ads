------------------------------------------------------------------------------
--  RTPS.Tests.Payload -- AUnit tests for the clause-10 data
--  encapsulation (CDR / PL_CDR, Table 10.1)
------------------------------------------------------------------------------

with AUnit;
with AUnit.Test_Cases;

package RTPS.Tests.Payload is

   type Payload_Test is new AUnit.Test_Cases.Test_Case with null record;

   overriding function Name
     (T : Payload_Test) return AUnit.Message_String;

   overriding procedure Register_Tests (T : in out Payload_Test);

end RTPS.Tests.Payload;
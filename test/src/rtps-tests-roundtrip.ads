------------------------------------------------------------------------------
--  RTPS.Tests.Roundtrip -- submessage round-trips in both endiannesses
--  and the SequenceNumberSet bitmap semantics (9.4.2.6).
------------------------------------------------------------------------------

with AUnit;
with AUnit.Test_Cases;
with RTPS.CDR;

package RTPS.Tests.Roundtrip is

   type Roundtrip_Test is new AUnit.Test_Cases.Test_Case with null record;

   overriding procedure Register_Tests (T : in out Roundtrip_Test);
   overriding function Name (T : Roundtrip_Test) return AUnit.Message_String;

end RTPS.Tests.Roundtrip;
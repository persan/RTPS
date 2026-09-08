------------------------------------------------------------------------------
--  RTPS.Tests.Receiver -- Message Receiver checks (8.3.4)
------------------------------------------------------------------------------

with AUnit;
with AUnit.Test_Cases;

package RTPS.Tests.Receiver is

   type Receiver_Test is new AUnit.Test_Cases.Test_Case with null record;

   overriding procedure Register_Tests (T : in out Receiver_Test);
   overriding function Name (T : Receiver_Test) return AUnit.Message_String;

end RTPS.Tests.Receiver;
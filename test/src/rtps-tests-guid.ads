------------------------------------------------------------------------------
--  RTPS.Tests.Guid -- GUID ordering relations (9.3.1.5)
------------------------------------------------------------------------------

with AUnit;
with AUnit.Test_Cases;

package RTPS.Tests.Guid is

   type Guid_Test is new AUnit.Test_Cases.Test_Case with null record;

   overriding procedure Register_Tests (T : in out Guid_Test);
   overriding function Name (T : Guid_Test) return AUnit.Message_String;

end RTPS.Tests.Guid;
------------------------------------------------------------------------------
--  RTPS.Tests.Guid -- body
------------------------------------------------------------------------------

with AUnit.Assertions;
use AUnit.Assertions;
with RTPS.Types;
with RTPS.Entities;

package body RTPS.Tests.Guid is

   package T renames RTPS.Types;
   package E renames RTPS.Entities;
   use all type T.Octet;

   ---------------------------------------------------------------------

   procedure Test_Guid_Relations (Tc : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Tc);
      G1 : constant T.GUID_T :=
        (Guid_Prefix => [others => 1], Entity_Id => [0, 0, 1, 16#C2#]);
      G2 : constant T.GUID_T :=
        (Guid_Prefix => [others => 1], Entity_Id => [0, 0, 1, 16#C7#]);
      G3 : constant T.GUID_T :=
        (Guid_Prefix => [others => 2], Entity_Id => [0, 0, 1, 16#C2#]);
   begin
      Assert (E."=" (G1, G1), "guid eq");
      Assert (not E."=" (G1, G2), "guid ne");
      Assert (E."<" (G1, G2), "guid lt entity");
      Assert (not E."<" (G3, G1), "guid lt prefix");
   end Test_Guid_Relations;

   ---------------------------------------------------------------------

   overriding procedure Register_Tests (T : in out Guid_Test) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine (T, Test_Guid_Relations'Access, "guid relations");
   end Register_Tests;

   overriding function Name (T : Guid_Test) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return new String'("RTPS.Guid");
   end Name;

end RTPS.Tests.Guid;
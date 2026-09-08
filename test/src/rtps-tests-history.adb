------------------------------------------------------------------------------
--  RTPS.Tests.History -- body
------------------------------------------------------------------------------

with AUnit.Assertions;
use AUnit.Assertions;
with RTPS.Types;
with RTPS.History;

package body RTPS.Tests.History is

   package T renames RTPS.Types;
   package H renames RTPS.History;
   use all type T.Octet;
   use all type T.SequenceNumber_T;
   use all type H.Cache_Change_Ref;

   ---------------------------------------------------------------------

   procedure Test_History_Cache (Tc : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Tc);
      Cache : H.History_Cache (Capacity => 4);
      C     : H.Cache_Change_Ref;
   begin
      Cache.Set_Writer_Guid
        (P => [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12],
         E => [0, 0, 1, 16#C2#]);

      for K in 1 .. 3 loop
         Cache.Add_Change
           (Kind        => T.ALIVE,
            Write_Time  => T.TIME_ZERO,
            Instance    => 0,
            Data        => null,
            Data_Length => 0,
            Change      => C);
      end loop;

      Assert (Cache.Get_Seq_Num_Min = 1, "history min");
      Assert (Cache.Get_Seq_Num_Max = 3, "history max");
      Assert (Cache.Count = 3, "history count");
      Assert (C.all.SN = 3, "history sn");

      C := Cache.Find (2);
      Assert (C /= null and then C.all.SN = 2, "history find");
      Assert (C /= null and then C.all.Guid_Prefix (1) = 1,
              "history prefix");

      --  Fill past capacity; oldest is evicted.
      for K in 1 .. 3 loop
         Cache.Add_Change
           (Kind        => T.ALIVE,
            Write_Time  => T.TIME_ZERO,
            Instance    => 0,
            Data        => null,
            Data_Length => 0,
            Change      => C);
      end loop;

      Assert (Cache.Get_Seq_Num_Min = 3, "history window min");
      Assert (Cache.Get_Seq_Num_Max = 6, "history window max");
      Assert (Cache.Find (1) = null, "history evicted");
      Assert (Cache.Find (5) /= null, "history retained");
   end Test_History_Cache;

   ---------------------------------------------------------------------

   overriding procedure Register_Tests (T : in out History_Test) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine (T, Test_History_Cache'Access, "history cache");
   end Register_Tests;

   overriding function Name (T : History_Test) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return new String'("RTPS.History");
   end Name;

end RTPS.Tests.History;
------------------------------------------------------------------------------
--  RTPS.Tests.Header -- body
------------------------------------------------------------------------------

with AUnit.Assertions;
use AUnit.Assertions;
with RTPS.Types;
with RTPS.CDR;

package body RTPS.Tests.Header is

   use all type RTPS.Types.Octet;

   ---------------------------------------------------------------------

   procedure Test_Header_Encoding (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      use all type RTPS.Types.Octet;
      H    : Messages.Header_T;
      BufA : CDR.Octet_Array_Access := new RTPS.Types.Octet_Array (1 .. 64);
      Buf  : RTPS.Types.Octet_Array renames BufA.all;
      S    : CDR.Stream;
   begin
      H.Version := (2, 2);
      H.Vendor_Id := [16#01#, 16#0F#];
      H.Guid_Prefix :=
        [16#10#, 16#20#, 16#30#, 16#40#, 16#50#, 16#60#,
         16#70#, 16#80#, 16#90#, 16#A0#, 16#B0#, 16#C0#];
      CDR.Bind (S, BufA, 64);
      Messages.Encode_Header (S, H);

      AUnit.Assertions.Assert
        (S.Last = 20, "header length is 20 octets");
      AUnit.Assertions.Assert
        (Buf (1) = 16#52# and Buf (2) = 16#54#
         and Buf (3) = 16#50# and Buf (4) = 16#53#,
         "header magic is 'R''T''P''S'");
      AUnit.Assertions.Assert
        (Buf (5) = 2 and Buf (6) = 2, "header version 2.2");
      AUnit.Assertions.Assert
        (Buf (7) = 16#01# and Buf (8) = 16#0F#, "header vendorId");
      AUnit.Assertions.Assert
        (Buf (9) = 16#10# and Buf (20) = 16#C0#, "header guidPrefix");
   end Test_Header_Encoding;

   ---------------------------------------------------------------------

   overriding procedure Register_Tests (T : in out Header_Test) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine (T, Test_Header_Encoding'Access, "header encoding");
   end Register_Tests;

   overriding function Name (T : Header_Test) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return new String'("RTPS.Header");
   end Name;

end RTPS.Tests.Header;
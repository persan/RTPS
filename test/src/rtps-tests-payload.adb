------------------------------------------------------------------------------
--  RTPS.Tests.Payload -- body
--
--  * Header identifier round trips for all four Table 10.1 schemes
--  * The spec's 10.2.2.1 example: struct {long a; char b[4];} with
--    a=1, b="abcd" in both endiannesses, byte-for-byte
--  * PL_CDR encode/decode round trip with parameter payload
--  * Malformed input rejection (short buffers, unknown ids)
------------------------------------------------------------------------------

with AUnit.Assertions;
with RTPS.CDR;
with RTPS.Messages;
with RTPS.Payload;
with RTPS.Types;

package body RTPS.Tests.Payload is

   package P  renames RTPS.Payload;
   package T  renames RTPS.Types;
   package C  renames RTPS.CDR;
   package M  renames RTPS.Messages;
   use AUnit.Assertions;

   use all type T.Octet;
   use all type T.Octet_Array;
   use type T.Octet_Buffer;
   use type M.Parameter_Array_Ref;

   ---------------------------------------------------------------------

   function Name (T : Payload_Test) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("RTPS.Payload");
   end Name;

   ---------------------------------------------------------------------

   procedure Test_Spec_Example_CDR
     (Tc : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Tc);
      --  struct example { long a; char b[4]; } with a=1, b="abcd"
      --  (10.2.2.1): serialized by hand with RTPS.CDR in each order.
      function Serialize (Little : Boolean) return T.Octet_Array;

      function Serialize (Little : Boolean) return T.Octet_Array
      is
         Buf : constant T.Octet_Buffer := new T.Octet_Array (1 .. 16);
         S   : C.Stream;
         E   : constant C.Endianness :=
           (if Little then C.Little_Endian else C.Big_Endian);
      begin
         C.Bind (S, C.Octet_Array_Access (Buf), Buf.all'Length);
         C.Put_Long (S, 1, E);
         for K in 1 .. 4 loop
            declare
               Ch : constant Character :=
                 Character'Val (97 + Integer (K) - 1);  --  "abcd"
            begin
               C.Put_Octet (S, T.Octet (Character'Pos (Ch)));
            end;
         end loop;
         return Buf (1 .. C.Encoded_Length (S));
      end Serialize;

      Wire  : T.Octet_Buffer;
      Start : Natural;
      Little : Boolean;
      Opts  : T.Unsigned_Short;
      Ok    : Boolean;
      use type T.Unsigned_Short;
   begin
      --  Big endian: identifier 0x00 0x00, options 0, then the data.
      Wire := P.Encode_CDR (Serialize (Little => False),
                            Little => False);
      P.Decode_CDR (Wire.all, Start, Little, Opts, Ok);
      Assert (Ok, "CDR_BE header parses");
      Assert (not Little, "CDR_BE byte order");
      Assert (Opts = 0, "options zero");
      Assert (Wire.all (1 .. 2) = (16#00#, 16#00#), "CDR_BE id octets");
      Assert (Wire.all (5 .. 8) = (16#00#, 16#00#, 16#00#, 16#01#),
              "spec example big-endian long");
      Assert (Wire.all (9 .. 12) = (Character'Pos ('a'),
                                    Character'Pos ('b'),
                                    Character'Pos ('c'),
                                    Character'Pos ('d')),
              "spec example char array");

      --  Little endian: identifier 0x00 0x01, long is 0x01 0x00 0x00
      --  0x00 (10.2.2.1 second figure).
      Wire := P.Encode_CDR (Serialize (Little => True),
                            Little => True);
      P.Decode_CDR (Wire.all, Start, Little, Opts, Ok);
      Assert (Ok, "CDR_LE header parses");
      Assert (Little, "CDR_LE byte order");
      Assert (Wire.all (1 .. 2) = (16#00#, 16#01#), "CDR_LE id octets");
      Assert (Wire.all (5 .. 8) = (16#01#, 16#00#, 16#00#, 16#00#),
              "spec example little-endian long");
      Assert (Start = 5, "body starts after header");
   end Test_Spec_Example_CDR;

   ---------------------------------------------------------------------

   procedure Test_PL_CDR_Roundtrip
     (Tc : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Tc);
      List : constant M.Parameter_Array (1 .. 2) :=
        (1 => (Parameter_Id => T.PID_TOPIC_NAME,
               Length => 4,
               Value  => new T.Octet_Array'(1 => 65, 2 => 66,
                                            3 => 67, 4 => 68)),
         2 => (Parameter_Id => T.PID_TYPE_NAME,
               Length => 2,
               Value  => new T.Octet_Array'(1 => 88, 2 => 89)));
      Wire : T.Octet_Buffer;
      Out_List : M.Parameter_Array_Ref;
      Opts  : T.Unsigned_Short;
      Ok    : Boolean;
      use type T.ParameterId_T;
   begin
      Wire := P.Encode_PL_CDR (List, Little => True);
      Assert (Wire.all (1 .. 2) = (16#00#, 16#03#), "PL_CDR_LE id octets");

      P.Decode_PL_CDR (Wire.all, Out_List, Opts, Ok);
      Assert (Ok, "PL_CDR_LE round trip");
      Assert (Out_List /= null and then Out_List.all'Length = 2,
              "parameter count round trip");
      Assert (Out_List.all (1).Parameter_Id = T.PID_TOPIC_NAME,
              "topic name parameter id round trip");
      Assert (Out_List.all (2).Parameter_Id = T.PID_TYPE_NAME,
              "type name parameter id round trip");

      --  Big endian variant carries the same parameter set.
      Wire := P.Encode_PL_CDR (List, Little => False);
      Assert (Wire.all (1 .. 2) = (16#00#, 16#02#), "PL_CDR_BE id octets");
      P.Decode_PL_CDR (Wire.all, Out_List, Opts, Ok);
      Assert (Ok, "PL_CDR_BE round trip");
      Assert (Out_List.all (1).Parameter_Id = T.PID_TOPIC_NAME,
              "BE parameter id round trip");
   end Test_PL_CDR_Roundtrip;

   ---------------------------------------------------------------------

   procedure Test_Malformed_Rejected
     (Tc : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Tc);
      Short  : constant T.Octet_Array (1 .. 3) := (others => 0);
      Bad_Id : constant T.Octet_Array (1 .. 8) :=
        (1 => 16#DE#, 2 => 16#AD#, others => 0);
      Start  : Natural;
      Little : Boolean;
      Opts   : T.Unsigned_Short;
      List   : M.Parameter_Array_Ref;
      Ok     : Boolean;
   begin
      P.Decode_CDR (Short, Start, Little, Opts, Ok);
      Assert (not Ok, "short CDR payload rejected");

      P.Decode_CDR (Bad_Id, Start, Little, Opts, Ok);
      Assert (not Ok, "unknown CDR scheme rejected");

      P.Decode_PL_CDR (Bad_Id, List, Opts, Ok);
      Assert (not Ok, "unknown PL scheme rejected");
      Assert (List = null, "no list allocated on error");
   end Test_Malformed_Rejected;

   ---------------------------------------------------------------------

   overriding procedure Register_Tests (T : in out Payload_Test) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine (T, Test_Spec_Example_CDR'Access,
                        "spec example CDR both endiannesses");
      Register_Routine (T, Test_PL_CDR_Roundtrip'Access,
                        "PL_CDR round trip");
      Register_Routine (T, Test_Malformed_Rejected'Access,
                        "malformed payloads rejected");
   end Register_Tests;

end RTPS.Tests.Payload;
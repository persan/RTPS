------------------------------------------------------------------------------
--  RTPS.Tests.Roundtrip -- body
--
--  Every submessage kind round-trips through encode/decode in both
--  endiannesses; SN-set bitmap semantics checked against the spec
--  example 1234/12:00110.
------------------------------------------------------------------------------

with AUnit.Assertions;
use AUnit.Assertions;
with RTPS.Types;
with RTPS.Messages;
with RTPS.Tests.Support;

package body RTPS.Tests.Roundtrip is

   package T  renames RTPS.Types;
   package C  renames RTPS.CDR;
   package M  renames RTPS.Messages;
   use all type T.Octet;
   use all type T.Unsigned_Long;
   use all type T.SequenceNumber_T;
   use all type T.Count_T;
   use all type T.EntityId_T;
   use all type T.Long;
   use all type T.FragmentNumber_T;
   use all type M.Submessage_Kind;

   ---------------------------------------------------------------------

   procedure Roundtrip
     (E   : C.Endianness;
      Tag : String;
      Tc  : in out AUnit.Test_Cases.Test_Case'Class)
   is
      Hdr  : M.Header_T;
      SMs  : constant M.Submessage_Array_Ref :=
        new M.Submessage_Array (1 .. 1);
      SM   : M.Submessage_T;
      Buf  : T.Octet_Buffer;
      S    : C.Stream;
      H2   : M.Header_T;
      X    : constant String := " " & Tag;
   begin
      --  Heartbeat
      declare
         HB : M.Submessage_T (M.KIND_HEARTBEAT);
      begin
         HB.Endianness := E;
         HB.Reader_Id := [16#00#, 16#00#, 16#01#, 16#C7#];
         HB.Writer_Id := [16#00#, 16#00#, 16#01#, 16#C2#];
         HB.First_SN  := 5;
         HB.Last_SN   := 10;
         HB.Count     := 7;
         HB.Final     := True;
         HB.Liveliness := True;
         SMs (1) := HB;
      end;
      Buf := Support.Encode_Message (Hdr, SMs);
      C.Bind (S, C.Octet_Array_Access (Buf), Support.Enc_Len);
      M.Decode_Header (S, H2);
      M.Decode_Submessage (S, SM);
      Assert (SM.Kind = M.KIND_HEARTBEAT, "hb" & X & " kind");
      Assert (SM.First_SN = 5, "hb" & X & " first");
      Assert (SM.Last_SN = 10, "hb" & X & " last");
      Assert (SM.Count = 7, "hb" & X & " count");
      Assert (SM.Final and SM.Liveliness, "hb" & X & " flags");
      Assert (SM.Reader_Id = [16#00#, 16#00#, 16#01#, 16#C7#],
              "hb" & X & " reader");

      --  AckNack
      declare
         AN : M.Submessage_T (M.KIND_ACKNACK);
      begin
         AN.Endianness := E;
         AN.Reader_Id := [16#00#, 16#00#, 16#01#, 16#C7#];
         AN.Writer_Id := [16#00#, 16#00#, 16#01#, 16#C2#];
         AN.Reader_SN_State := (Bitmap_Base => 4, Num_Bits => 32,
                                Bitmap => 16#C000_0000#);
         AN.Count := 9;
         AN.Final := True;
         SMs (1) := AN;
      end;
      Buf := Support.Encode_Message (Hdr, SMs);
      C.Bind (S, C.Octet_Array_Access (Buf), Support.Enc_Len);
      M.Decode_Header (S, H2);
      M.Decode_Submessage (S, SM);
      Assert (SM.Kind = M.KIND_ACKNACK, "an" & X & " kind");
      Assert (SM.Reader_SN_State.Bitmap_Base = 4, "an" & X & " base");
      Assert (SM.Reader_SN_State.Num_Bits = 32, "an" & X & " bits");
      Assert (SM.Reader_SN_State.Bitmap = 16#C000_0000#, "an" & X & " bitmap");
      Assert (SM.Count = 9, "an" & X & " count");

      --  Gap
      declare
         G : M.Submessage_T (M.KIND_GAP);
      begin
         G.Endianness := E;
         G.Reader_Id := [16#00#, 16#00#, 16#01#, 16#C7#];
         G.Writer_Id := [16#00#, 16#00#, 16#01#, 16#C2#];
         G.Gap_Start := 2;
         G.Gap_List  := (Bitmap_Base => 10, Num_Bits => 8,
                         Bitmap => 16#C000_0000#);
         SMs (1) := G;
      end;
      Buf := Support.Encode_Message (Hdr, SMs);
      C.Bind (S, C.Octet_Array_Access (Buf), Support.Enc_Len);
      M.Decode_Header (S, H2);
      M.Decode_Submessage (S, SM);
      Assert (SM.Kind = M.KIND_GAP, "gap" & X & " kind");
      Assert (SM.Gap_Start = 2, "gap" & X & " start");
      Assert (SM.Gap_List.Bitmap_Base = 10, "gap" & X & " base");

      --  InfoTS
      declare
         TS : M.Submessage_T (M.KIND_INFO_TS);
      begin
         TS.Endianness := E;
         TS.Timestamp := (16#0102_0304#, 16#0506_0708#);
         SMs (1) := TS;
      end;
      Buf := Support.Encode_Message (Hdr, SMs);
      C.Bind (S, C.Octet_Array_Access (Buf), Support.Enc_Len);
      M.Decode_Header (S, H2);
      M.Decode_Submessage (S, SM);
      Assert (SM.Kind = M.KIND_INFO_TS, "ts" & X & " kind");
      Assert (SM.Timestamp.Seconds = 16#0102_0304#, "ts" & X & " sec");
      Assert (SM.Timestamp.Fraction = 16#0506_0708#, "ts" & X & " frac");

      --  InfoDst
      declare
         D : M.Submessage_T (M.KIND_INFO_DST);
         P : constant T.GuidPrefix_T :=
           [16#11#, 16#22#, 16#33#, 16#44#, 16#55#, 16#66#,
            16#77#, 16#88#, 16#99#, 16#AA#, 16#BB#, 16#CC#];
      begin
         D.Endianness := E;
         D.Dst_Guid_Prefix := P;
         SMs (1) := D;
      end;
      Buf := Support.Encode_Message (Hdr, SMs);
      C.Bind (S, C.Octet_Array_Access (Buf), Support.Enc_Len);
      M.Decode_Header (S, H2);
      M.Decode_Submessage (S, SM);
      Assert (SM.Kind = M.KIND_INFO_DST, "dst" & X & " kind");
      Assert (SM.Dst_Guid_Prefix (1) = 16#11#
              and SM.Dst_Guid_Prefix (12) = 16#CC#, "dst" & X & " prefix");

      --  Data (with payload, no inline qos)
      declare
         D : M.Submessage_T (M.KIND_DATA);
      begin
         D.Endianness := E;
         D.Reader_Id := [16#00#, 16#00#, 16#02#, 16#C7#];
         D.Writer_Id := [16#00#, 16#00#, 16#02#, 16#C2#];
         D.Writer_SN := 42;
         D.Has_Payload := True;
         D.Is_Key := False;
         D.Payload := new T.Octet_Array'(16#DE#, 16#AD#, 16#BE#, 16#EF#);
         D.Payload_Length := 4;
         SMs (1) := D;
      end;
      Buf := Support.Encode_Message (Hdr, SMs);
      C.Bind (S, C.Octet_Array_Access (Buf), Support.Enc_Len);
      M.Decode_Header (S, H2);
      M.Decode_Submessage (S, SM);
      Assert (SM.Kind = M.KIND_DATA, "data" & X & " kind");
      Assert (SM.Writer_SN = 42, "data" & X & " sn");
      Assert (SM.Has_Payload and not SM.Is_Key, "data" & X & " has");
      Assert (SM.Payload_Length = 4, "data" & X & " len");
      Assert (SM.Payload.all (1) = 16#DE# and SM.Payload.all (4) = 16#EF#,
              "data" & X & " bytes");

      --  HeartbeatFrag
      declare
         HF : M.Submessage_T (M.KIND_HEARTBEAT_FRAG);
      begin
         HF.Endianness := E;
         HF.Reader_Id := [16#00#, 16#00#, 16#01#, 16#C7#];
         HF.Writer_Id := [16#00#, 16#00#, 16#01#, 16#C2#];
         HF.Writer_SN := 7;
         HF.Last_Fragment_Num := 13;
         HF.Count := 3;
         SMs (1) := HF;
      end;
      Buf := Support.Encode_Message (Hdr, SMs);
      C.Bind (S, C.Octet_Array_Access (Buf), Support.Enc_Len);
      M.Decode_Header (S, H2);
      M.Decode_Submessage (S, SM);
      Assert (SM.Kind = M.KIND_HEARTBEAT_FRAG, "hbf" & X & " kind");
      Assert (SM.Writer_SN = 7, "hbf" & X & " sn");
      Assert (SM.Last_Fragment_Num = 13, "hbf" & X & " frag");
      Assert (SM.Count = 3, "hbf" & X & " count");
   end Roundtrip;

   ---------------------------------------------------------------------

   procedure Test_LE (Tc : in out AUnit.Test_Cases.Test_Case'Class) is
   begin
      Roundtrip (C.Little_Endian, "LE", Tc);
   end Test_LE;

   procedure Test_BE (Tc : in out AUnit.Test_Cases.Test_Case'Class) is
   begin
      Roundtrip (C.Big_Endian, "BE", Tc);
   end Test_BE;

   ---------------------------------------------------------------------

   procedure Test_SN_Set (Tc : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (Tc);
      use all type T.Unsigned_Long;
      Set  : Messages.SequenceNumberSet_T;
      Bits : T.Unsigned_Long;
   begin
      Set.Bitmap_Base := 1234;
      Set.Num_Bits := 12;
      --  Example 1234/12:00110: offsets 2 and 3 set (seqs 1236, 1237).
      --  Bit for offset i is bit (31 - i) of the first bitmap long.
      Bits := 0;
      Bits := Bits or 2**29;  --  offset 2
      Bits := Bits or 2**28;  --  offset 3
      Set.Bitmap := Bits;

      for Offset in 0 .. 11 loop
         declare
            In_Set : constant Boolean :=
              (Set.Bitmap and 2**(31 - Offset)) /= 0;
            Expect : constant Boolean := Offset in 2 | 3;
         begin
            Assert (In_Set = Expect,
                    "snset offset" & Natural'Image (Offset)
                    & (if Expect then " member" else " nonmember"));
         end;
      end loop;
   end Test_SN_Set;

   ---------------------------------------------------------------------

   overriding procedure Register_Tests (T : in out Roundtrip_Test) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine (T, Test_LE'Access, "submessage round-trip LE");
      Register_Routine (T, Test_BE'Access, "submessage round-trip BE");
      Register_Routine (T, Test_SN_Set'Access, "SequenceNumberSet bitmap");
   end Register_Tests;

   overriding function Name (T : Roundtrip_Test) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return new String'("RTPS.Messages");
   end Name;

end RTPS.Tests.Roundtrip;
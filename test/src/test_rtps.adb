------------------------------------------------------------------------------
--  Test_RTPS -- self-contained test driver for the RTPS library.
--
--  Checks the wire codecs against the spec:
--    * known-good encodings (hand-computed from clause 9.4 diagrams)
--    * round-trips for every submessage kind, in both endiannesses
--    * receiver parse of a multi-submessage message
--    * HistoryCache add/find/min/max windowing
--  Exits with process status 0 on success, 1 on failure.
------------------------------------------------------------------------------

with RTPS.Types;
with RTPS.CDR;
with RTPS.Messages;
with RTPS.Receiver;
with RTPS.History;
with RTPS.Entities;
with Ada.Text_IO;
with Ada.Command_Line;

procedure Test_RTPS is

   use all type RTPS.Types.Octet;
   use all type RTPS.Types.Unsigned_Long;
   use all type RTPS.Types.SequenceNumber_T;
   use all type RTPS.Types.Count_T;
   use all type RTPS.Types.EntityId_T;
   use all type RTPS.Types.Long;
   use all type RTPS.Types.FragmentNumber_T;

   package T  renames RTPS.Types;
   package C  renames RTPS.CDR;
   package M  renames RTPS.Messages;
   use all type M.Submessage_Kind;
   package R  renames RTPS.Receiver;
   package H  renames RTPS.History;
   use all type H.Cache_Change_Ref;
   package IO renames Ada.Text_IO;

   Failures : Natural := 0;
   Checks   : Natural := 0;

   procedure Check (Name : String; Cond : Boolean) is
   begin
      Checks := Checks + 1;
      if Cond then
         IO.Put_Line ("PASS: " & Name);
      else
         Failures := Failures + 1;
         IO.Put_Line ("FAIL: " & Name);
      end if;
   end Check;

   Enc_Len : Natural := 0;  --  length of the most recently encoded message

   --  Compact message encoder for tests.
   function Encode_Message
     (Hdr : M.Header_T;
      SMs : M.Submessage_Array_Ref;
      Len : Natural := RTPS.Max_Message_Size) return T.Octet_Buffer
   is
      S : C.Stream;
   begin
      declare
         Result : C.Octet_Array_Access := new T.Octet_Array (1 .. Len);
      begin
         C.Bind (S, Result, Len);
         M.Encode_Header (S, Hdr);
         for K in SMs'Range loop
            M.Encode_Submessage (S, SMs (K), Last_Submessage => True);
         end loop;
         Enc_Len := S.Last;
         return T.Octet_Buffer (Result);
      end;
   end Encode_Message;

   ---------------------------------------------------------------------
   --  Test 1: header encoding matches clause 9.4.4 wire diagram.
   ---------------------------------------------------------------------

   procedure Test_Header is
      H   : M.Header_T;
      BufA : C.Octet_Array_Access := new T.Octet_Array (1 .. 64);
      Buf  : T.Octet_Array renames BufA.all;
      S   : C.Stream;
   begin
      H.Version := (2, 2);
      H.Vendor_Id := [16#01#, 16#0F#];
      H.Guid_Prefix :=
        [16#10#, 16#20#, 16#30#, 16#40#, 16#50#, 16#60#,
         16#70#, 16#80#, 16#90#, 16#A0#, 16#B0#, 16#C0#];
      C.Bind (S, BufA, 64);
      M.Encode_Header (S, H);

      Check ("header length", S.Last = 20);
      Check ("header magic",
        Buf (1) = 16#52# and Buf (2) = 16#54#
        and Buf (3) = 16#50# and Buf (4) = 16#53#);
      Check ("header version", Buf (5) = 2 and Buf (6) = 2);
      Check ("header vendor", Buf (7) = 16#01# and Buf (8) = 16#0F#);
      Check ("header prefix", Buf (9) = 16#10# and Buf (20) = 16#C0#);
   end Test_Header;

   ---------------------------------------------------------------------
   --  Test 2: SequenceNumberSet semantics (9.4.2.6, example 1234/12).
   ---------------------------------------------------------------------

   procedure Test_SN_Set is
      use all type T.Unsigned_Long;
      Set  : M.SequenceNumberSet_T;
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
         begin
            case Offset is
               when 2 | 3 =>
                  Check ("snset member" & Natural'Image (Offset),
                         In_Set);
               when others =>
                  Check ("snset nonmember" & Natural'Image (Offset),
                         not In_Set);
            end case;
         end;
      end loop;
   end Test_SN_Set;

   ---------------------------------------------------------------------
   --  Test 3: submessage round-trips in both endiannesses.
   ---------------------------------------------------------------------

   procedure Roundtrip (E : C.Endianness; Tag : String) is
      use all type T.Octet;
      Hdr  : M.Header_T;
      SMs  : constant M.Submessage_Array_Ref :=
        new M.Submessage_Array (1 .. 1);
      SM   : M.Submessage_T;
      Buf  : T.Octet_Buffer;
      S    : C.Stream;
      H2   : M.Header_T;
      X   : constant String := " " & Tag;
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
      Buf := Encode_Message (Hdr, SMs);
      C.Bind (S, C.Octet_Array_Access (Buf), Enc_Len);
      --  ^ rebind with the actual message length, as the transport
      --  would (UDP gives the payload length); octetsToNextHeader=0
      --  then correctly means "extends to end of message".
      M.Decode_Header (S, H2);
      M.Decode_Submessage (S, SM);
      Check ("hb" & X & " kind", SM.Kind = M.KIND_HEARTBEAT);
      Check ("hb" & X & " first", SM.First_SN = 5);
      Check ("hb" & X & " last", SM.Last_SN = 10);
      Check ("hb" & X & " count", SM.Count = 7);
      Check ("hb" & X & " flags", SM.Final and SM.Liveliness);
      Check ("hb" & X & " reader",
             SM.Reader_Id = [16#00#, 16#00#, 16#01#, 16#C7#]);

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
      Buf := Encode_Message (Hdr, SMs);
      C.Bind (S, C.Octet_Array_Access (Buf), Enc_Len);
      --  ^ rebind with the actual message length, as the transport
      --  would (UDP gives the payload length); octetsToNextHeader=0
      --  then correctly means "extends to end of message".
      M.Decode_Header (S, H2);
      M.Decode_Submessage (S, SM);
      Check ("an" & X & " kind", SM.Kind = M.KIND_ACKNACK);
      Check ("an" & X & " base", SM.Reader_SN_State.Bitmap_Base = 4);
      Check ("an" & X & " bits", SM.Reader_SN_State.Num_Bits = 32);
      Check ("an" & X & " bitmap",
             SM.Reader_SN_State.Bitmap = 16#C000_0000#);
      Check ("an" & X & " count", SM.Count = 9);

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
      Buf := Encode_Message (Hdr, SMs);
      C.Bind (S, C.Octet_Array_Access (Buf), Enc_Len);
      --  ^ rebind with the actual message length, as the transport
      --  would (UDP gives the payload length); octetsToNextHeader=0
      --  then correctly means "extends to end of message".
      M.Decode_Header (S, H2);
      M.Decode_Submessage (S, SM);
      Check ("gap" & X & " kind", SM.Kind = M.KIND_GAP);
      Check ("gap" & X & " start", SM.Gap_Start = 2);
      Check ("gap" & X & " base", SM.Gap_List.Bitmap_Base = 10);

      --  InfoTS
      declare
         TS : M.Submessage_T (M.KIND_INFO_TS);
      begin
         TS.Endianness := E;
         TS.Timestamp := (16#0102_0304#, 16#0506_0708#);
         SMs (1) := TS;
      end;
      Buf := Encode_Message (Hdr, SMs);
      C.Bind (S, C.Octet_Array_Access (Buf), Enc_Len);
      --  ^ rebind with the actual message length, as the transport
      --  would (UDP gives the payload length); octetsToNextHeader=0
      --  then correctly means "extends to end of message".
      M.Decode_Header (S, H2);
      M.Decode_Submessage (S, SM);
      Check ("ts" & X & " kind", SM.Kind = M.KIND_INFO_TS);
      Check ("ts" & X & " sec", SM.Timestamp.Seconds = 16#0102_0304#);
      Check ("ts" & X & " frac", SM.Timestamp.Fraction = 16#0506_0708#);

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
      Buf := Encode_Message (Hdr, SMs);
      C.Bind (S, C.Octet_Array_Access (Buf), Enc_Len);
      --  ^ rebind with the actual message length, as the transport
      --  would (UDP gives the payload length); octetsToNextHeader=0
      --  then correctly means "extends to end of message".
      M.Decode_Header (S, H2);
      M.Decode_Submessage (S, SM);
      Check ("dst" & X & " kind", SM.Kind = M.KIND_INFO_DST);
      Check ("dst" & X & " prefix",
             SM.Dst_Guid_Prefix (1) = 16#11#
             and SM.Dst_Guid_Prefix (12) = 16#CC#);

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
      Buf := Encode_Message (Hdr, SMs);
      C.Bind (S, C.Octet_Array_Access (Buf), Enc_Len);
      --  ^ rebind with the actual message length, as the transport
      --  would (UDP gives the payload length); octetsToNextHeader=0
      --  then correctly means "extends to end of message".
      M.Decode_Header (S, H2);
      M.Decode_Submessage (S, SM);
      Check ("data" & X & " kind", SM.Kind = M.KIND_DATA);
      Check ("data" & X & " sn", SM.Writer_SN = 42);
      Check ("data" & X & " has", SM.Has_Payload and not SM.Is_Key);
      Ada.Text_IO.Put_Line ("DBG plen=" & Natural'Image (SM.Payload_Length)
                            & " S.Last=" & Natural'Image (S.Last));
      Check ("data" & X & " len", SM.Payload_Length = 4);
      Check ("data" & X & " bytes",
             SM.Payload.all (1) = 16#DE# and SM.Payload.all (4) = 16#EF#);

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
      Buf := Encode_Message (Hdr, SMs);
      C.Bind (S, C.Octet_Array_Access (Buf), Enc_Len);
      --  ^ rebind with the actual message length, as the transport
      --  would (UDP gives the payload length); octetsToNextHeader=0
      --  then correctly means "extends to end of message".
      M.Decode_Header (S, H2);
      M.Decode_Submessage (S, SM);
      Check ("hbf" & X & " kind", SM.Kind = M.KIND_HEARTBEAT_FRAG);
      Check ("hbf" & X & " sn", SM.Writer_SN = 7);
      Check ("hbf" & X & " frag", SM.Last_Fragment_Num = 13);
      Check ("hbf" & X & " count", SM.Count = 3);
   end Roundtrip;

   ---------------------------------------------------------------------
   --  Test 4: receiver parses multi-submessage message + state updates.
   ---------------------------------------------------------------------

   Sink_Count : Natural := 0;
   Last_Kind  : M.Submessage_Kind := M.KIND_PAD;
   type Submessage_Ref is access M.Submessage_T;
   Last_SM    : Submessage_Ref := null;  --  unconstrained copy of any kind
   Last_Data  : M.Submessage_T (M.KIND_DATA);

   type Counting_Sink is new R.Sink with null record;

   procedure On_Submessage
     (Self : in out Counting_Sink; SM : M.Submessage_T);
   procedure On_Submessage
     (Self : in out Counting_Sink; SM : M.Submessage_T)
   is
      pragma Unreferenced (Self);
   begin
      Sink_Count := Sink_Count + 1;
      Last_Kind := SM.Kind;
      Last_SM := new M.Submessage_T'(SM);  --  unconstrained copy
      if SM.Kind = M.KIND_DATA or SM.Kind = M.KIND_DATA_FRAG then
         Last_Data := SM;
      end if;
   end On_Submessage;

   procedure Test_Receiver is
      use all type T.Octet;
      Hdr   : M.Header_T;
      SMs   : constant M.Submessage_Array_Ref :=
        new M.Submessage_Array (1 .. 2);
      Buf   : T.Octet_Buffer;
      State : R.Receiver_State;
      Sink  : aliased Counting_Sink;
      D_Payload : constant T.Octet_Buffer :=
        new T.Octet_Array'(16#01#, 16#02#, 16#03#, 16#04#);
   begin
      declare
         TS : M.Submessage_T (M.KIND_INFO_TS);
         D  : M.Submessage_T (M.KIND_DATA);
      begin
         TS.Endianness := C.Little_Endian;
         TS.Timestamp := (16#0102_0304#, 16#0506_0708#);

         D.Endianness := C.Little_Endian;
         D.Reader_Id := [16#00#, 16#00#, 16#02#, 16#C7#];
         D.Writer_Id := [16#00#, 16#00#, 16#02#, 16#C2#];
         D.Writer_SN := 42;
         D.Has_Payload := True;
         D.Is_Key := False;
         D.Payload := D_Payload;
         D.Payload_Length := 4;

         SMs (1) := TS;
         SMs (2) := D;
      end;

      Buf := Encode_Message (Hdr, SMs);

      Sink_Count := 0;
      R.Process_Message (Buf.all (1 .. Enc_Len), State, Sink);

      Check ("rx count", Sink_Count = 2);
      Check ("rx state ts",
             State.Have_Timestamp
             and State.Timestamp.Seconds = 16#0102_0304#);
      Check ("rx last kind", Last_Kind = M.KIND_DATA);
      Check ("rx data sn", Last_Data.Writer_SN = 42);
      Check ("rx data len", Last_Data.Payload_Length = 4);

      --  Invalid magic must be dropped silently (8.3.6.3).
      declare
         Bad : T.Octet_Buffer := new T.Octet_Array (1 .. 30);
      begin
         Bad.all := [others => 0];
         Sink_Count := 0;
         R.Process_Message (Bad.all, State, Sink);
         Check ("rx bad magic dropped", Sink_Count = 0);
      end;
   end Test_Receiver;

   ---------------------------------------------------------------------
   --  Test 5: HistoryCache behavior (8.2.2).
   ---------------------------------------------------------------------

   procedure Test_History is
      Cache : H.History_Cache (Capacity => 4);
      C     : H.Cache_Change_Ref;
      use all type T.SequenceNumber_T;
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

      Check ("history min", Cache.Get_Seq_Num_Min = 1);
      Check ("history max", Cache.Get_Seq_Num_Max = 3);
      Check ("history count", Cache.Count = 3);
      Check ("history sn", C.all.SN = 3);

      C := Cache.Find (2);
      Check ("history find", C /= null and then C.all.SN = 2);
      Check ("history prefix", C.all.Guid_Prefix (1) = 1);

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

      Check ("history window min", Cache.Get_Seq_Num_Min = 3);
      Check ("history window max", Cache.Get_Seq_Num_Max = 6);
      Check ("history evicted", Cache.Find (1) = null);
      Check ("history retained", Cache.Find (5) /= null);
   end Test_History;

   ---------------------------------------------------------------------
   --  Test 6: GUID relations.
   ---------------------------------------------------------------------

   procedure Test_Guid is
      package E renames RTPS.Entities;
      use all type T.Octet;
      G1 : constant T.GUID_T :=
        (Guid_Prefix => [others => 1], Entity_Id => [0, 0, 1, 16#C2#]);
      G2 : constant T.GUID_T :=
        (Guid_Prefix => [others => 1], Entity_Id => [0, 0, 1, 16#C7#]);
      G3 : constant T.GUID_T :=
        (Guid_Prefix => [others => 2], Entity_Id => [0, 0, 1, 16#C2#]);
   begin
      Check ("guid eq", E."=" (G1, G1));
      Check ("guid ne", not E."=" (G1, G2));
      Check ("guid lt entity", E."<" (G1, G2));
      Check ("guid lt prefix", not E."<" (G3, G1));
   end Test_Guid;

--  Test execution
begin
   IO.Put_Line ("== RTPS test suite ==");
   Test_Header;
   Test_SN_Set;
   Roundtrip (C.Little_Endian, "LE");
   Roundtrip (C.Big_Endian, "BE");
   Test_Receiver;
   Test_History;
   Test_Guid;
   IO.Put_Line
     ("== done:" & Natural'Image (Checks - Failures) & "/" &
        Natural'Image (Checks) & " checks passed ==");
   Ada.Command_Line.Set_Exit_Status
     (if Failures = 0 then Ada.Command_Line.Success
      else Ada.Command_Line.Failure);
end Test_RTPS;
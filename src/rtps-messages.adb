------------------------------------------------------------------------------
--  RTPS.Messages -- body: wire codecs for the UDP PSM (clause 9.4.5)
------------------------------------------------------------------------------

package body RTPS.Messages is

   use all type RTPS.Types.Unsigned_Long;
   use all type RTPS.Types.Unsigned_Short;
   use all type RTPS.Types.Octet;
   use all type RTPS.Types.Octet_Array;
   use all type RTPS.Types.Octet_Buffer;
   use all type RTPS.Types.Locator_Buffer;
   use all type CDR.Endianness;
   use all type RTPS.Types.ParameterId_T;

   --  Local bit-shift helper for the 256-bit set model.
   function Shift_Left_U32
     (V : RTPS.Types.Unsigned_Long; A : Natural) return RTPS.Types.Unsigned_Long
   is (RTPS.Types.Unsigned_Long (V * 2**A));

   ---------------------------------------------------------------------
   --  Header
   ---------------------------------------------------------------------

   procedure Encode_Header
     (S : in out CDR.Stream'Class; H : Header_T)
   is
   begin
      RTPS.CDR.Put_Octets (S, PROTOCOL_RTPS);
      RTPS.CDR.Put_Octet (S, H.Version.Major);
      RTPS.CDR.Put_Octet (S, H.Version.Minor);
      for K in H.Vendor_Id'Range loop
         RTPS.CDR.Put_Octet (S, H.Vendor_Id (K));
      end loop;
      for K in H.Guid_Prefix'Range loop
         RTPS.CDR.Put_Octet (S, H.Guid_Prefix (K));
      end loop;
   end Encode_Header;

   procedure Decode_Header
     (S : in out CDR.Stream'Class; H : out Header_T)
   is
      Proto : RTPS.Types.Octet_Array (1 .. 4);
      B     : RTPS.Types.Octet;
   begin
      RTPS.CDR.Get_Octets (S, Proto);
      if Proto /= PROTOCOL_RTPS then
         raise Constraint_Error with "not an RTPS message";
      end if;
      RTPS.CDR.Get_Octet (S, B);
      H.Version := (Major => B, Minor => 0);
      RTPS.CDR.Get_Octet (S, B);
      H.Version.Minor := B;
      for K in H.Vendor_Id'Range loop
         RTPS.CDR.Get_Octet (S, B);
         H.Vendor_Id (K) := B;
      end loop;
      for K in H.Guid_Prefix'Range loop
         RTPS.CDR.Get_Octet (S, B);
         H.Guid_Prefix (K) := B;
      end loop;
   end Decode_Header;

   ---------------------------------------------------------------------
   --  Helpers
   ---------------------------------------------------------------------

   function Decode_Kind (Code : RTPS.Types.Octet) return Submessage_Kind is
   begin
      case Code is
         when 16#01# => return KIND_PAD;
         when 16#06# => return KIND_ACKNACK;
         when 16#07# => return KIND_HEARTBEAT;
         when 16#08# => return KIND_GAP;
         when 16#09# => return KIND_INFO_TS;
         when 16#0C# => return KIND_INFO_SRC;
         when 16#0D# => return KIND_INFO_REPLY_IP4;
         when 16#0E# => return KIND_INFO_DST;
         when 16#0F# => return KIND_INFO_REPLY;
         when 16#12# => return KIND_NACK_FRAG;
         when 16#13# => return KIND_HEARTBEAT_FRAG;
         when 16#15# => return KIND_DATA;
         when 16#16# => return KIND_DATA_FRAG;
         when others => raise Unknown_Kind;
      end case;
   end Decode_Kind;

   procedure Put_EntityId
     (S : in out CDR.Stream'Class; Id : RTPS.Types.EntityId_T)
   is
   begin
      for K in Id'Range loop
         RTPS.CDR.Put_Octet (S, Id (K));
      end loop;
   end Put_EntityId;

   procedure Get_EntityId
     (S : in out CDR.Stream'Class; Id : out RTPS.Types.EntityId_T)
   is
      B : RTPS.Types.Octet;
   begin
      for K in Id'Range loop
         RTPS.CDR.Get_Octet (S, B);
         Id (K) := B;
      end loop;
   end Get_EntityId;

   procedure Put_SequenceNumber
     (S : in out CDR.Stream'Class; SN : RTPS.Types.SequenceNumber_T;
      E : CDR.Endianness)
   is
   begin
      --  SequenceNumber: long high; unsigned long low; (9.4.2.5)
      RTPS.CDR.Put_Long (S, RTPS.Types.High_Word (SN), E);
      RTPS.CDR.Put_ULong (S, RTPS.Types.Low_Word (SN), E);
   end Put_SequenceNumber;

   procedure Get_SequenceNumber
     (S : in out CDR.Stream'Class; SN : out RTPS.Types.SequenceNumber_T;
      E : CDR.Endianness)
   is
      High : RTPS.Types.Long;
      Low  : RTPS.Types.Unsigned_Long;
   begin
      RTPS.CDR.Get_Long (S, High, E);
      RTPS.CDR.Get_ULong (S, Low, E);
      SN := RTPS.Types.Make_Sequence_Number (High, Low);
   end Get_SequenceNumber;

   procedure Put_SN_Set
     (S : in out CDR.Stream'Class; Set : SequenceNumberSet_T;
      E : CDR.Endianness)
   is
      use type RTPS.Types.Unsigned_Short;
      Num_Longs : constant RTPS.Types.Unsigned_Short :=
        RTPS.Types.Unsigned_Short ((Set.Num_Bits + 31) / 32);
   begin
      --  SequenceNumberSet: bitmapBase, numBits, bitmap[M] where
      --  M = (numBits + 31) / 32 (9.4.2.6).  Not CDR aligned: the
      --  numBits field encodes both the significant bits and the
      --  number of bitmap elements.
      Put_SequenceNumber (S, Set.Bitmap_Base, E);
      RTPS.CDR.Put_ULong (S, Set.Num_Bits, E);
      RTPS.CDR.Put_ULong (S, Set.Bitmap, E);
      if Num_Longs > 2 then
         raise Constraint_Error with "SequenceNumberSet too large";
      end if;
      if Num_Longs > 1 then
         RTPS.CDR.Put_ULong (S, 0, E);  --  second bitmap long (bits 32..255)
      end if;
   end Put_SN_Set;

   procedure Get_SN_Set
     (S : in out CDR.Stream'Class; Set : out SequenceNumberSet_T;
      E : CDR.Endianness)
   is
      Num_Bits : RTPS.Types.Unsigned_Long;
      W0, W1   : RTPS.Types.Unsigned_Long;
      Num_Longs : RTPS.Types.Unsigned_Long;
      use type RTPS.Types.Unsigned_Long;
   begin
      Get_SequenceNumber (S, Set.Bitmap_Base, E);
      RTPS.CDR.Get_ULong (S, Num_Bits, E);
      if Num_Bits > 256 then
         raise Constraint_Error with "SequenceNumberSet numBits > 256";
      end if;
      Set.Num_Bits := Num_Bits;
      RTPS.CDR.Get_ULong (S, W0, E);
      Set.Bitmap := W0;
      Num_Longs := (Num_Bits + 31) / 32;
      if Num_Longs > 2 then
         raise Constraint_Error with "SequenceNumberSet too large";
      end if;
      if Num_Longs > 1 then
         RTPS.CDR.Get_ULong (S, W1, E);
         --  fold second long into the 256-bit model (bits 32..63 kept)
         Set.Bitmap :=
           Set.Bitmap or Shift_Left_U32 (W1, 32);
      end if;
   end Get_SN_Set;

   procedure Put_FN_Set
     (S : in out CDR.Stream'Class; Set : FragmentNumberSet_T;
      E : CDR.Endianness)
   is
      Num_Longs : constant RTPS.Types.Unsigned_Long :=
        (Set.Num_Bits + 31) / 32;
   begin
      --  FragmentNumberSet (9.4.2.8)
      RTPS.CDR.Put_ULong (S, RTPS.Types.Unsigned_Long (Set.Bitmap_Base), E);
      RTPS.CDR.Put_ULong (S, Set.Num_Bits, E);
      RTPS.CDR.Put_ULong (S, Set.Bitmap, E);
      if Num_Longs > 2 then
         raise Constraint_Error with "FragmentNumberSet too large";
      end if;
      if Num_Longs > 1 then
         RTPS.CDR.Put_ULong (S, 0, E);
      end if;
   end Put_FN_Set;

   procedure Get_FN_Set
     (S : in out CDR.Stream'Class; Set : out FragmentNumberSet_T;
      E : CDR.Endianness)
   is
      Base, Num_Bits, W0, W1 : RTPS.Types.Unsigned_Long;
      Num_Longs : RTPS.Types.Unsigned_Long;
      use type RTPS.Types.Unsigned_Long;
   begin
      RTPS.CDR.Get_ULong (S, Base, E);
      RTPS.CDR.Get_ULong (S, Num_Bits, E);
      if Num_Bits > 256 then
         raise Constraint_Error with "FragmentNumberSet numBits > 256";
      end if;
      Set.Bitmap_Base := RTPS.Types.FragmentNumber_T (Base);
      Set.Num_Bits := Num_Bits;
      RTPS.CDR.Get_ULong (S, W0, E);
      Set.Bitmap := W0;
      Num_Longs := (Num_Bits + 31) / 32;
      if Num_Longs > 2 then
         raise Constraint_Error with "FragmentNumberSet too large";
      end if;
      if Num_Longs > 1 then
         RTPS.CDR.Get_ULong (S, W1, E);
         Set.Bitmap := Set.Bitmap or Shift_Left_U32 (W1, 32);
      end if;
   end Get_FN_Set;

   procedure Put_Parameter_List
     (S : in out CDR.Stream'Class; List : Parameter_Array;
      E : CDR.Endianness)
   is
      use type RTPS.Types.ParameterId_T;
   begin
      for P of List loop
         RTPS.CDR.Put_UShort (S, RTPS.Types.Unsigned_Short (P.Parameter_Id), E);
         RTPS.CDR.Put_UShort (S, P.Length, E);
         if P.Value /= null and then P.Length > 0 then
            declare
               V : RTPS.Types.Octet_Array (1 .. Natural (P.Length)) :=
                 (others => 0);
               N : constant Natural := Natural
                 (Integer'Min (Integer (P.Length), P.Value.all'Length));
            begin
               for K in 1 .. N loop
                  V (K) := P.Value.all (P.Value.all'First + K - 1);
               end loop;
               RTPS.CDR.Put_Octets (S, V);
            end;
         else
            declare
               V : constant RTPS.Types.Octet_Array (1 .. Natural (P.Length)) :=
                 (others => 0);
            begin
               RTPS.CDR.Put_Octets (S, V);
            end;
         end if;
      end loop;
      --  Sentinel terminates the list (9.4.2.11).
      RTPS.CDR.Put_UShort
        (S, RTPS.Types.Unsigned_Short (RTPS.Types.PID_SENTINEL), E);
      RTPS.CDR.Put_UShort (S, 0, E);
   end Put_Parameter_List;

   ---------------------------------------------------------------------
   --  Submessage encoding (9.4.5)
   ---------------------------------------------------------------------

   procedure Encode_Submessage
     (S   : in out CDR.Stream'Class;
      SM  : Submessage_T;
      Last_Submessage : Boolean := True)
   is
      E : constant CDR.Endianness := SM.Endianness;
      Flags : RTPS.Types.Octet := FLAG_E;
   begin
      if E = CDR.Little_Endian then
         Flags := Flags or FLAG_E;  --  E = 1: little endian
      else
         Flags := 0;                --  E = 0: big endian
      end if;

      case SM.Kind is
         when KIND_PAD =>
            null;

         when KIND_ACKNACK =>
            if SM.Final then
               Flags := Flags or FLAG_F;
            end if;

         when KIND_HEARTBEAT =>
            if SM.Final then
               Flags := Flags or FLAG_F;
            end if;
            if SM.Liveliness then
               Flags := Flags or FLAG_L;
            end if;

         when KIND_GAP | KIND_INFO_SRC | KIND_INFO_DST |
              KIND_NACK_FRAG | KIND_HEARTBEAT_FRAG =>
            null;

         when KIND_INFO_TS =>
            if SM.Invalidate then
               Flags := Flags or FLAG_I;
            end if;

         when KIND_INFO_REPLY =>
            if SM.Has_Multicast then
               Flags := Flags or FLAG_M;
            end if;

         when KIND_INFO_REPLY_IP4 =>
            if SM.Has_Multicast then
               Flags := Flags or FLAG_M;
            end if;

         when KIND_DATA =>
            if SM.Inline_Qos /= null then
               Flags := Flags or FLAG_Q;
            end if;
            if SM.Has_Payload and then not SM.Is_Key then
               Flags := Flags or FLAG_D;
            end if;
            if SM.Has_Payload and then SM.Is_Key then
               Flags := Flags or FLAG_K;
            end if;

         when KIND_DATA_FRAG =>
            if SM.Inline_Qos /= null then
               Flags := Flags or FLAG_Q;
            end if;
            if SM.Is_Key then
               Flags := Flags or FLAG_K;
            end if;
      end case;

      RTPS.CDR.Put_Octet (S, Kind_Code (SM.Kind));
      RTPS.CDR.Put_Octet (S, Flags);
      --  octetsToNextHeader placeholder; patched below.
      declare
         Len_Pos : constant Natural := S.Last + 1;
         Body_First : constant Natural := S.Last + 3;
         use type RTPS.Types.Octet;
      begin
         RTPS.CDR.Put_UShort (S, 0, E);  --  placeholder

         case SM.Kind is
            when KIND_PAD =>
               null;

            when KIND_ACKNACK =>
               Put_EntityId (S, SM.Reader_Id);
               Put_EntityId (S, SM.Writer_Id);
               Put_SN_Set (S, SM.Reader_SN_State, E);
               RTPS.CDR.Put_Long
                 (S, RTPS.Types.Long (SM.Count), E);

            when KIND_HEARTBEAT =>
               Put_EntityId (S, SM.Reader_Id);
               Put_EntityId (S, SM.Writer_Id);
               Put_SequenceNumber (S, SM.First_SN, E);
               Put_SequenceNumber (S, SM.Last_SN, E);
               RTPS.CDR.Put_Long (S, RTPS.Types.Long (SM.Count), E);

            when KIND_GAP =>
               Put_EntityId (S, SM.Reader_Id);
               Put_EntityId (S, SM.Writer_Id);
               Put_SequenceNumber (S, SM.Gap_Start, E);
               Put_SN_Set (S, SM.Gap_List, E);

            when KIND_INFO_TS =>
               if not SM.Invalidate then
                  RTPS.CDR.Put_Long (S, SM.Timestamp.Seconds, E);
                  RTPS.CDR.Put_ULong (S, SM.Timestamp.Fraction, E);
               end if;

            when KIND_INFO_SRC =>
               RTPS.CDR.Put_ULong (S, SM.Unused, E);
               RTPS.CDR.Put_Octet (S, SM.Version.Major);
               RTPS.CDR.Put_Octet (S, SM.Version.Minor);
               for K in SM.Vendor_Id'Range loop
                  RTPS.CDR.Put_Octet (S, SM.Vendor_Id (K));
               end loop;
               for K in SM.Src_Guid_Prefix'Range loop
                  RTPS.CDR.Put_Octet (S, SM.Src_Guid_Prefix (K));
               end loop;

            when KIND_INFO_REPLY_IP4 =>
               --  LocatorUDPv4: unsigned long address; unsigned long port
               declare
                  A : constant RTPS.Types.Unsigned_Long :=
                    RTPS.Types.Unsigned_Long (SM.Unicast.Address (13)) * 2**24
                    + RTPS.Types.Unsigned_Long (SM.Unicast.Address (14)) * 2**16
                    + RTPS.Types.Unsigned_Long (SM.Unicast.Address (15)) * 2**8
                    + RTPS.Types.Unsigned_Long (SM.Unicast.Address (16));
                  M : RTPS.Types.Unsigned_Long := 0;
               begin
                  RTPS.CDR.Put_ULong (S, A, E);
                  RTPS.CDR.Put_ULong (S, SM.Unicast.Port, E);
                  if SM.Has_Multicast then
                     M :=
                       RTPS.Types.Unsigned_Long (SM.Multicast.Address (13)) * 2**24
                       + RTPS.Types.Unsigned_Long (SM.Multicast.Address (14)) * 2**16
                       + RTPS.Types.Unsigned_Long (SM.Multicast.Address (15)) * 2**8
                       + RTPS.Types.Unsigned_Long (SM.Multicast.Address (16));
                     RTPS.CDR.Put_ULong (S, M, E);
                     RTPS.CDR.Put_ULong (S, SM.Multicast.Port, E);
                  end if;
               end;

            when KIND_INFO_DST =>
               for K in SM.Dst_Guid_Prefix'Range loop
                  RTPS.CDR.Put_Octet (S, SM.Dst_Guid_Prefix (K));
               end loop;

            when KIND_INFO_REPLY =>
               declare
                  U : RTPS.Types.Locator_Buffer := SM.Unicast_List;
                  M : RTPS.Types.Locator_Buffer := SM.Multicast_List;
               begin
                  if U = null then
                     RTPS.CDR.Put_ULong (S, 0, E);
                  else
                     RTPS.CDR.Put_ULong (S, U'Length, E);
                     for L of U.all loop
                        RTPS.CDR.Put_Long (S, L.Kind, E);
                        RTPS.CDR.Put_ULong (S, L.Port, E);
                        declare
                        Addr : RTPS.Types.Octet_Array (1 .. 16);
                     begin
                        for K in L.Address'Range loop
                           Addr (K) := L.Address (K);
                        end loop;
                        RTPS.CDR.Put_Octets (S, Addr);
                     end;
                     end loop;
                  end if;
                  if SM.Has_Multicast then
                     if M = null then
                        RTPS.CDR.Put_ULong (S, 0, E);
                     else
                        RTPS.CDR.Put_ULong (S, M'Length, E);
                        for L of M.all loop
                           RTPS.CDR.Put_Long (S, L.Kind, E);
                           RTPS.CDR.Put_ULong (S, L.Port, E);
                           declare
                        Addr : RTPS.Types.Octet_Array (1 .. 16);
                     begin
                        for K in L.Address'Range loop
                           Addr (K) := L.Address (K);
                        end loop;
                        RTPS.CDR.Put_Octets (S, Addr);
                     end;
                        end loop;
                     end if;
                  end if;
               end;

            when KIND_NACK_FRAG =>
               Put_EntityId (S, SM.Reader_Id);
               Put_EntityId (S, SM.Writer_Id);
               Put_SequenceNumber (S, SM.Writer_SN, E);
               Put_FN_Set (S, SM.Fragment_Number_State, E);
               RTPS.CDR.Put_Long (S, RTPS.Types.Long (SM.Count), E);

            when KIND_HEARTBEAT_FRAG =>
               Put_EntityId (S, SM.Reader_Id);
               Put_EntityId (S, SM.Writer_Id);
               Put_SequenceNumber (S, SM.Writer_SN, E);
               RTPS.CDR.Put_ULong
                 (S, RTPS.Types.Unsigned_Long (SM.Last_Fragment_Num), E);
               RTPS.CDR.Put_Long (S, RTPS.Types.Long (SM.Count), E);

            when KIND_DATA =>
               RTPS.CDR.Put_UShort (S, SM.Extra_Flags, E);
               --  octetsToInlineQos: offset from first octet after this
               --  field to the first octet of inlineQos (or, if absent,
               --  to the field after inlineQos): always
               --  readerId+writerId+writerSN = 4+4+8 = 16.
               RTPS.CDR.Put_UShort (S, 16, E);
               Put_EntityId (S, SM.Reader_Id);
               Put_EntityId (S, SM.Writer_Id);
               Put_SequenceNumber (S, SM.Writer_SN, E);
               if SM.Inline_Qos /= null then
                  Put_Parameter_List (S, SM.Inline_Qos.all, E);
               end if;
               if SM.Has_Payload then
                  declare
                     N : constant Natural :=
                       Integer'Min (SM.Payload_Length,
                                    SM.Payload.all'Length);
                  begin
                     for K in 1 .. N loop
                        RTPS.CDR.Put_Octet
                          (S, SM.Payload.all (SM.Payload.all'First + K - 1));
                     end loop;
                  end;
               end if;

            when KIND_DATA_FRAG =>
               RTPS.CDR.Put_UShort (S, SM.Extra_Flags, E);
               RTPS.CDR.Put_UShort (S, 16, E);
               Put_EntityId (S, SM.Reader_Id);
               Put_EntityId (S, SM.Writer_Id);
               Put_SequenceNumber (S, SM.Writer_SN, E);
               RTPS.CDR.Put_ULong
                 (S, RTPS.Types.Unsigned_Long (SM.Fragment_Starting_Num), E);
               RTPS.CDR.Put_UShort (S, SM.Fragments_In_Submessage, E);
               RTPS.CDR.Put_UShort (S, SM.Fragment_Size, E);
               RTPS.CDR.Put_ULong (S, SM.Sample_Size, E);
               if SM.Inline_Qos /= null then
                  Put_Parameter_List (S, SM.Inline_Qos.all, E);
               end if;
               if SM.Payload /= null then
                  declare
                     N : constant Natural :=
                       Integer'Min (SM.Payload_Length,
                                    SM.Payload.all'Length);
                  begin
                     for K in 1 .. N loop
                        RTPS.CDR.Put_Octet
                          (S, SM.Payload.all (SM.Payload.all'First + K - 1));
                     end loop;
                  end;
               end if;
         end case;

         --  Patch octetsToNextHeader (9.4.5.1.3): number of octets from
         --  the first octet of the contents of the Submessage until the
         --  first octet of the header of the next Submessage.
         declare
            Body_Last : constant Natural := S.Last;
            Body_Len  : constant Natural := Body_Last - Body_First + 1;
            use type RTPS.Types.Octet;
         begin
            if Last_Submessage then
               null;  --  stays 0 (PAD/INFO_TS: next header follows at once)
            else
               --  Write body length (must be <= 65535).
               if Body_Len > 65535 then
                  raise Constraint_Error
                    with "submessage body exceeds 64k; must be last";
               end if;
               declare
                  Pos : Natural := Len_Pos;
                  V   : RTPS.Types.Unsigned_Short :=
                    RTPS.Types.Unsigned_Short (Body_Len);
                  Hi  : constant RTPS.Types.Octet :=
                    RTPS.Types.Octet (V / 256);
                  Lo  : constant RTPS.Types.Octet :=
                    RTPS.Types.Octet (V mod 256);
               begin
                  if E = CDR.Little_Endian then
                     S.Buffer.all (Pos) := Lo;
                     S.Buffer.all (Pos + 1) := Hi;
                  else
                     S.Buffer.all (Pos) := Hi;
                     S.Buffer.all (Pos + 1) := Lo;
                  end if;
               end;
            end if;
         end;
      end;
   end Encode_Submessage;

   function Flags_E_Endianness (Flags : RTPS.Types.Octet) return CDR.Endianness
   is (if (Flags and FLAG_E) /= 0 then CDR.Little_Endian
       else CDR.Big_Endian);

   function Octet_Mid
     (V : RTPS.Types.Unsigned_Long; Byte_Index : Natural)
     return RTPS.Types.Octet
   is (RTPS.Types.Octet ((V / 256**Byte_Index) mod 256));

   procedure Decode_Locator
     (S : in out CDR.Stream'Class; L : out RTPS.Types.Locator_T;
      E : CDR.Endianness)
   is
      B : RTPS.Types.Octet;
   begin
      RTPS.CDR.Get_Long (S, L.Kind, E);
      RTPS.CDR.Get_ULong (S, L.Port, E);
      for K in L.Address'Range loop
         RTPS.CDR.Get_Octet (S, B);
         L.Address (K) := B;
      end loop;
   end Decode_Locator;

   procedure Decode_Parameter_List
     (S : in out CDR.Stream'Class; List : out Parameter_Array_Ref;
      E : CDR.Endianness)
   is
      Count : Natural := 0;
      use type RTPS.Types.ParameterId_T;
   begin
      --  Two-pass: count parameters, then allocate and fill.
      declare
         Save : constant Natural := S.Last;
      begin
         loop
            declare
               Id     : RTPS.Types.Unsigned_Short;
               Length : RTPS.Types.Unsigned_Short;
            begin
               RTPS.CDR.Get_UShort (S, Id, E);
               RTPS.CDR.Get_UShort (S, Length, E);
               exit when RTPS.Types.ParameterId_T (Id) = RTPS.Types.PID_SENTINEL;
               Count := Count + 1;
               --  Skip value octets (aligned to 4).
               declare
                  Skip : constant Natural :=
                    (Natural (Length) + 3) / 4 * 4;
               begin
                  if S.Last + Skip > S.Buffer.all'Length + (S.First - 1) then
                     raise Constraint_Error with "parameter overruns stream";
                  end if;
                  S.Last := S.Last + Skip;
               end;
            end;
         end loop;
         S.Last := Save;
      end;

      List := new Parameter_Array (1 .. Count);
      for P of List.all loop
         declare
            Id     : RTPS.Types.Unsigned_Short;
            Length : RTPS.Types.Unsigned_Short;
         begin
            RTPS.CDR.Get_UShort (S, Id, E);
            RTPS.CDR.Get_UShort (S, Length, E);
            exit when RTPS.Types.ParameterId_T (Id) = RTPS.Types.PID_SENTINEL;
            P.Parameter_Id := RTPS.Types.ParameterId_T (Id);
            P.Length := Length;
            P.Value := new RTPS.Types.Octet_Array (1 .. Natural (Length));
            for K in 1 .. Natural (Length) loop
               declare
                  B : RTPS.Types.Octet;
               begin
                  RTPS.CDR.Get_Octet (S, B);
                  P.Value.all (K) := B;
               end;
            end loop;
            --  Skip padding to 4-byte boundary.
            declare
               Pad : constant Natural :=
                 (4 - Natural (Length) mod 4) mod 4;
               B : RTPS.Types.Octet;
            begin
               for K in 1 .. Pad loop
                  RTPS.CDR.Get_Octet (S, B);
               end loop;
            end;
         end;
      end loop;
   end Decode_Parameter_List;

   procedure Copy_Payload
     (S : in out CDR.Stream'Class; SM : in out Submessage_T;
      Body_End : Natural)
   is
      Remaining : constant Natural := Body_End - S.Last;
   begin
      if Remaining <= 0 then
         SM.Has_Payload := False;
         SM.Payload_Length := 0;
         return;
      end if;
      SM.Payload := new RTPS.Types.Octet_Array (1 .. Remaining);
      for K in 1 .. Remaining loop
         declare
            B : RTPS.Types.Octet;
         begin
            RTPS.CDR.Get_Octet (S, B);
            SM.Payload.all (K) := B;
         end;
      end loop;
      SM.Payload_Length := Remaining;
   end Copy_Payload;

   ---------------------------------------------------------------------
   --  Submessage decoding
   ---------------------------------------------------------------------

   procedure Decode_Submessage
     (S   : in out CDR.Stream'Class;
      SM  : out Submessage_T)
   is
      Code  : RTPS.Types.Octet;
      Flags : RTPS.Types.Octet;
      Octets_To_Next : RTPS.Types.Unsigned_Short;
      E    : CDR.Endianness;
      Kind : Submessage_Kind;
      Body_First, Body_End : Natural;
      use type RTPS.Types.Unsigned_Short;
      use type RTPS.Types.Unsigned_Long;
   begin
      RTPS.CDR.Get_Octet (S, Code);
      RTPS.CDR.Get_Octet (S, Flags);
      Kind := Decode_Kind (Code);
      RTPS.CDR.Get_UShort (S, Octets_To_Next, Flags_E_Endianness (Flags));
      E := Flags_E_Endianness (Flags);

      if Octets_To_Next = 0 then
         --  Last submessage in message (except PAD/INFO_TS, for which 0
         --  means the next header follows immediately); extends to end
         --  of the message (Limit), not of the whole buffer.
         Body_First := S.Last + 1;
         Body_End   := S.Limit;
      else
         Body_First := S.Last + 1;
         Body_End   := Body_First + Natural (Octets_To_Next) - 1;
      end if;

      declare
         --  Per-kind default: each branch below fully determines the
         --  variant.  KIND_PAD has no variant components, so a bare
         --  (Kind => KIND_PAD) aggregate is complete; other kinds are
         --  filled field-by-field after the switch.
         Result : Submessage_T (Kind => Kind);
      begin
         Result.Endianness := E;
         SM := Result;
      end;

      case Kind is
         when KIND_PAD =>
            null;

         when KIND_ACKNACK =>
            SM.Final := (Flags and FLAG_F) /= 0;
            Get_EntityId (S, SM.Reader_Id);
            Get_EntityId (S, SM.Writer_Id);
            Get_SN_Set (S, SM.Reader_SN_State, E);
            declare
               C : RTPS.Types.Long;
            begin
               RTPS.CDR.Get_Long (S, C, E);
               SM.Count := RTPS.Types.Count_T (C);
            end;

         when KIND_HEARTBEAT =>
            SM.Final := (Flags and FLAG_F) /= 0;
            SM.Liveliness := (Flags and FLAG_L) /= 0;
            Get_EntityId (S, SM.Reader_Id);
            Get_EntityId (S, SM.Writer_Id);
            Get_SequenceNumber (S, SM.First_SN, E);
            Get_SequenceNumber (S, SM.Last_SN, E);
            declare
               C : RTPS.Types.Long;
            begin
               RTPS.CDR.Get_Long (S, C, E);
               SM.Count := RTPS.Types.Count_T (C);
            end;

         when KIND_GAP =>
            Get_EntityId (S, SM.Reader_Id);
            Get_EntityId (S, SM.Writer_Id);
            Get_SequenceNumber (S, SM.Gap_Start, E);
            Get_SN_Set (S, SM.Gap_List, E);

         when KIND_INFO_TS =>
            SM.Invalidate := (Flags and FLAG_I) /= 0;
            if not SM.Invalidate then
               RTPS.CDR.Get_Long (S, SM.Timestamp.Seconds, E);
               RTPS.CDR.Get_ULong (S, SM.Timestamp.Fraction, E);
            end if;

         when KIND_INFO_SRC =>
            RTPS.CDR.Get_ULong (S, SM.Unused, E);
            declare
               B : RTPS.Types.Octet;
            begin
               RTPS.CDR.Get_Octet (S, B);
               SM.Version := (Major => B, Minor => 0);
               RTPS.CDR.Get_Octet (S, B);
               SM.Version.Minor := B;
            end;
            for K in SM.Vendor_Id'Range loop
               declare
                  B : RTPS.Types.Octet;
               begin
                  RTPS.CDR.Get_Octet (S, B);
                  SM.Vendor_Id (K) := B;
               end;
            end loop;
            for K in SM.Src_Guid_Prefix'Range loop
               declare
                  B : RTPS.Types.Octet;
               begin
                  RTPS.CDR.Get_Octet (S, B);
                  SM.Src_Guid_Prefix (K) := B;
               end;
            end loop;

         when KIND_INFO_REPLY_IP4 =>
            declare
               A, P : RTPS.Types.Unsigned_Long;
               function Byte_Of
                 (V : RTPS.Types.Unsigned_Long; Idx : Natural)
                 return RTPS.Types.Octet is
                 (RTPS.Types.Octet ((V / 256**Idx) mod 256));
            begin
               RTPS.CDR.Get_ULong (S, A, E);
               RTPS.CDR.Get_ULong (S, P, E);
               SM.Unicast := RTPS.Types.Make_UDPv4_Locator
                 (Byte_Of (A, 3), Byte_Of (A, 2),
                  Byte_Of (A, 1), Byte_Of (A, 0), P);
               if (Flags and FLAG_M) /= 0 then
                  SM.Has_Multicast := True;
                  RTPS.CDR.Get_ULong (S, A, E);
                  RTPS.CDR.Get_ULong (S, P, E);
                  SM.Multicast := RTPS.Types.Make_UDPv4_Locator
                    (Byte_Of (A, 3), Byte_Of (A, 2),
                     Byte_Of (A, 1), Byte_Of (A, 0), P);
               end if;
            end;

         when KIND_INFO_DST =>
            for K in SM.Dst_Guid_Prefix'Range loop
               declare
                  B : RTPS.Types.Octet;
               begin
                  RTPS.CDR.Get_Octet (S, B);
                  SM.Dst_Guid_Prefix (K) := B;
               end;
            end loop;

         when KIND_INFO_REPLY =>
            declare
               Num : RTPS.Types.Unsigned_Long;
            begin
               RTPS.CDR.Get_ULong (S, Num, E);
               SM.Unicast_List := new RTPS.Types.Locator_Array (1 .. Natural (Num));
               for K in 1 .. Natural (Num) loop
                  Decode_Locator (S, SM.Unicast_List.all (K), E);
               end loop;
               if (Flags and FLAG_M) /= 0 then
                  SM.Has_Multicast := True;
                  RTPS.CDR.Get_ULong (S, Num, E);
                  SM.Multicast_List :=
                    new RTPS.Types.Locator_Array (1 .. Natural (Num));
                  for K in 1 .. Natural (Num) loop
                     Decode_Locator (S, SM.Multicast_List.all (K), E);
                  end loop;
               end if;
            end;

         when KIND_NACK_FRAG =>
            Get_EntityId (S, SM.Reader_Id);
            Get_EntityId (S, SM.Writer_Id);
            Get_SequenceNumber (S, SM.Writer_SN, E);
            Get_FN_Set (S, SM.Fragment_Number_State, E);
            declare
               C : RTPS.Types.Long;
            begin
               RTPS.CDR.Get_Long (S, C, E);
               SM.Count := RTPS.Types.Count_T (C);
            end;

         when KIND_HEARTBEAT_FRAG =>
            Get_EntityId (S, SM.Reader_Id);
            Get_EntityId (S, SM.Writer_Id);
            Get_SequenceNumber (S, SM.Writer_SN, E);
            declare
               F : RTPS.Types.Unsigned_Long;
            begin
               RTPS.CDR.Get_ULong (S, F, E);
               SM.Last_Fragment_Num :=
                 RTPS.Types.FragmentNumber_T (F);
            end;
            declare
               C : RTPS.Types.Long;
            begin
               RTPS.CDR.Get_Long (S, C, E);
               SM.Count := RTPS.Types.Count_T (C);
            end;

         when KIND_DATA =>
            RTPS.CDR.Get_UShort (S, SM.Extra_Flags, E);
            RTPS.CDR.Get_UShort (S, SM.Octets_To_Inline_Qos, E);
            Get_EntityId (S, SM.Reader_Id);
            Get_EntityId (S, SM.Writer_Id);
            Get_SequenceNumber (S, SM.Writer_SN, E);
            if (Flags and FLAG_Q) /= 0 then
               Decode_Parameter_List (S, SM.Inline_Qos, E);
            end if;
            --  Payload: D=1 data, K=1 key, D=K=0 none; D=K=1 invalid.
            if (Flags and FLAG_D) /= 0 then
               SM.Has_Payload := True;
               SM.Is_Key := False;
            elsif (Flags and FLAG_K) /= 0 then
               SM.Has_Payload := True;
               SM.Is_Key := True;
            end if;
            if SM.Has_Payload then
               Copy_Payload (S, SM, Body_End);
            end if;

         when KIND_DATA_FRAG =>
            RTPS.CDR.Get_UShort (S, SM.Extra_Flags, E);
            RTPS.CDR.Get_UShort (S, SM.Octets_To_Inline_Qos, E);
            Get_EntityId (S, SM.Reader_Id);
            Get_EntityId (S, SM.Writer_Id);
            Get_SequenceNumber (S, SM.Writer_SN, E);
            declare
               F : RTPS.Types.Unsigned_Long;
            begin
               RTPS.CDR.Get_ULong (S, F, E);
               SM.Fragment_Starting_Num :=
                 RTPS.Types.FragmentNumber_T (F);
            end;
            RTPS.CDR.Get_UShort (S, SM.Fragments_In_Submessage, E);
            RTPS.CDR.Get_UShort (S, SM.Fragment_Size, E);
            RTPS.CDR.Get_ULong (S, SM.Sample_Size, E);
            if (Flags and FLAG_Q) /= 0 then
               Decode_Parameter_List (S, SM.Inline_Qos, E);
            end if;
            SM.Has_Payload := True;
            SM.Is_Key := (Flags and FLAG_K) /= 0;
            Copy_Payload (S, SM, Body_End);
      end case;

      --  Skip to the next submessage header if the decoder has not
      --  consumed all body octets (e.g. unknown inline parameters).
      if S.Last < Body_End then
         S.Last := Body_End;
      end if;
   end Decode_Submessage;

   ---------------------------------------------------------------------

end RTPS.Messages;
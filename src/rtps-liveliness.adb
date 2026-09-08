------------------------------------------------------------------------------
--  RTPS.Liveliness -- body
--
--  The built-in writer/reader wrap the reliable protocol machines;
--  the DATA payloads are the ParticipantMessageData CDR form of
--  9.6.2.1.
------------------------------------------------------------------------------

with RTPS.CDR;
with RTPS.Messages;
with RTPS.StatefulReader;
with RTPS.StatefulWriter;

package body RTPS.Liveliness is

   package M  renames RTPS.Messages;
   package H  renames RTPS.History;
   package SW renames RTPS.StatefulWriter;
   package SR renames RTPS.StatefulReader;
   package C  renames RTPS.CDR;
   package TR renames RTPS.Transports;

   use all type T.Octet;
   use all type T.EntityId_T;
   use all type T.GuidPrefix_T;
   use all type T.GUID_T;

   Built_In_Writer_Id : constant T.EntityId_T :=
     T.ENTITYID_P2P_BUILTIN_PARTICIPANT_MESSAGE_WRITER;
   Built_In_Reader_Id : constant T.EntityId_T :=
     T.ENTITYID_P2P_BUILTIN_PARTICIPANT_MESSAGE_READER;

   ---------------------------------------------------------------------
   --  ParticipantMessageData wire mapping (9.6.2.1)
   ---------------------------------------------------------------------

   function Encode
     (Participant : T.GuidPrefix_T;
      Kind        : Message_Kind;
      Data        : T.Octet_Array) return T.Octet_Buffer
   is
      Pad   : constant Natural := (4 - Data'Length mod 4) mod 4;
      --  sequence<octet>: length + value, padded to 4.
      Total : constant Natural :=
        12 + 4 + 4 + Data'Length + Pad;
      Buf   : constant T.Octet_Buffer :=
        new T.Octet_Array (1 .. Total);
      S     : C.Stream;
      Len   : constant T.Unsigned_Long := T.Unsigned_Long (Data'Length);
   begin
      C.Bind (S, C.Octet_Array_Access (Buf), Total);
      for K in 1 .. 12 loop
         C.Put_Octet (S, Participant (K));
      end loop;
      for K in 1 .. 4 loop
         C.Put_Octet (S, Kind (K));
      end loop;
      --  data.length (unsigned long)
      C.Put_ULong (S, Len, C.Little_Endian);
      --  data.value + padding
      for K in Data'Range loop
         C.Put_Octet (S, Data (K));
      end loop;
      for K in 1 .. Pad loop
         C.Put_Octet (S, 0);
      end loop;
      return Buf;
   end Encode;

   procedure Decode
     (Wire        :        T.Octet_Array;
      Participant :    out T.GuidPrefix_T;
      Kind        :    out Message_Kind;
      Data        :    out T.Octet_Buffer;
      Data_Length :    out Natural;
      Ok          :    out Boolean)
   is
      S     : C.Stream;
      Len   : T.Unsigned_Long;
      Pad   : Natural;
      use type T.Unsigned_Long;
   begin
      Participant := T.GUIDPREFIX_UNKNOWN;
      Kind        := PMDK_UNKNOWN;
      Data        := null;
      Data_Length := 0;
      Ok := False;

      --  Minimum: 12 + 4 + 4 = 20 octets.
      if Wire'Length < 20 then
         return;
      end if;

      declare
         Copy : constant T.Octet_Buffer :=
           new T.Octet_Array'(Wire);
      begin
         C.Bind (S, C.Octet_Array_Access (Copy), Copy.all'Length);
         for K in 1 .. 12 loop
            C.Get_Octet (S, Participant (K));
         end loop;
         for K in 1 .. 4 loop
            C.Get_Octet (S, Kind (K));
         end loop;
         C.Get_ULong (S, Len, C.Little_Endian);
      end;

      if Natural (Len) > 2**22 then
         return;  --  implausible length (spec: >= 128 octets support)
      end if;

      Pad := (4 - Natural (Len) mod 4) mod 4;
      if 20 + Natural (Len) > Wire'Length then
         return;
      end if;

      Data_Length := Natural (Len);
      Data := new T.Octet_Array (1 .. Data_Length);
      Data.all := Wire
        (Wire'First + 20 .. Wire'First + 20 + Data_Length - 1);
      Ok := True;
   end Decode;

   ---------------------------------------------------------------------
   --  Writer side
   ---------------------------------------------------------------------

   procedure New_Writer
     (Self        : in out Writer;
      Participant  :        T.GuidPrefix_T;
      Cache        :        RTPS.History.History_Cache_Ref)
   is
   begin
      Self.Participant := Participant;
      Self.Cache := Cache;
      SW.New_Writer
        (Self.Inner,
         (Guid_Prefix => Participant,
          Entity_Id   => Built_In_Writer_Id),
         Cache);
   end New_Writer;

   procedure Open
     (Self : in out Writer; To : TR.Transport_Ref) is
   begin
      SW.Open (Self.Inner, To);
   end Open;

   procedure Matched_Reader_Add
     (Self       : in out Writer;
      Reader_Guid :        T.GUID_T;
      Meta_Port   :        T.Unsigned_Long)
   is
   begin
      SW.Matched_Reader_Add
        (Self.Inner,
         Proxy        =>
           (Remote_Reader_Guid => Reader_Guid,
            Expects_Inline_Qos => False,
            Unicast_Port   => Meta_Port,
            Multicast_Port => 0),
         Window_First => 1,
         Window_Last  => 64);
   end Matched_Reader_Add;

   procedure Matched_Reader_Remove
     (Self : in out Writer; Reader_Guid : T.GUID_T) is
   begin
      SW.Matched_Reader_Remove (Self.Inner, Reader_Guid);
   end Matched_Reader_Remove;

   procedure Assert
     (Self : in out Writer;
      Kind :        Liveliness_Kind;
      Data :        T.Octet_Array := (1 .. 0 => 0))
   is
      Wire_Kind : constant Message_Kind :=
        (case Kind is
           when Liveliness_Automatic => PMDK_AUTOMATIC_LIVELINESS_UPDATE,
           when Liveliness_Manual_By_Participant =>
             PMDK_MANUAL_LIVELINESS_UPDATE);
      Wire : constant T.Octet_Buffer :=
        Encode (Self.Participant, Wire_Kind, Data);
      Change : H.Cache_Change_Ref;
      It     : SW.Reader_Iterator;
      Guid   : T.GUID_T;
   begin
      --  Write (or replace: KEEP_LAST(1) per instance) the sample in
      --  the built-in HistoryCache and register it with every matched
      --  reader (8.4.13.5).
      Self.Cache.Add_Change
        (Kind        => T.ALIVE,
         Write_Time  => (Seconds => 0, Fraction => 0),
         Instance    => 0,
         Data        => Wire,
         Data_Length => Wire.all'Length,
         Is_Key      => False,
         Change      => Change);

      SW.On_New_Change (Self.Inner, Change.all.SN);

      --  Push immediately (the sample asserts liveliness; the remote
      --  side must see it inside its lease period).
      SW.First_Reader (Self.Inner, It, Guid);
      while Guid /= T.GUID_UNKNOWN loop
         SW.Push_Next (Self.Inner, Guid);
         SW.Next_Reader (Self.Inner, It, Guid);
      end loop;
   end Assert;

   procedure Push_Pending (Self : in out Writer) is
      It     : SW.Reader_Iterator;
      Guid   : T.GUID_T;
      Guard  : Natural := 0;
   begin
      while SW.Has_Pending (Self.Inner) and then Guard < 4096 loop
         Guard := Guard + 1;
         SW.First_Reader (Self.Inner, It, Guid);
         exit when Guid = T.GUID_UNKNOWN;
         SW.Push_Next (Self.Inner, Guid);
      end loop;
   end Push_Pending;

   procedure Send_Heartbeat (Self : in out Writer) is
   begin
      SW.Send_Heartbeat (Self.Inner);
   end Send_Heartbeat;

   procedure On_Acknack
     (Self      : in out Writer;
      Reader_Id :        T.EntityId_T;
      Base_SN   :        T.SequenceNumber_T;
      Bitmap    :        T.Unsigned_Long;
      Num_Bits  :        T.Unsigned_Long;
      Final     :        Boolean;
      Repair    :    out Boolean)
   is
   begin
      SW.On_Acknack
        (Self.Inner, Reader_Id, Built_In_Writer_Id,
         Base_SN, Bitmap, Num_Bits, Final, Repair);
   end On_Acknack;

   function Reader_Count (Self : Writer) return Natural is
     (SW.Reader_Count (Self.Inner));

   function Has_Pending (Self : Writer) return Boolean is
     (SW.Has_Pending (Self.Inner));

   ---------------------------------------------------------------------
   --  Reader side
   ---------------------------------------------------------------------

   procedure New_Reader
     (Self        : in out Reader;
      Participant  :        T.GuidPrefix_T;
      Cache        :        RTPS.History.History_Cache_Ref)
   is
   begin
      Self.Participant := Participant;
      Self.Cache := Cache;
      SR.New_Reader
        (Self.Inner,
         (Guid_Prefix => Participant,
          Entity_Id   => Built_In_Reader_Id),
         Cache);
   end New_Reader;

   procedure Matched_Writer_Add
     (Self        : in out Reader;
      Writer_Guid :        T.GUID_T;
      Meta_Port   :        T.Unsigned_Long := 0)
   is
   begin
      SR.Matched_Writer_Add (Self.Inner, Writer_Guid, Meta_Port);
   end Matched_Writer_Add;

   procedure Matched_Writer_Remove
     (Self : in out Reader; Writer_Guid : T.GUID_T) is
   begin
      SR.Matched_Writer_Remove (Self.Inner, Writer_Guid);
   end Matched_Writer_Remove;

   procedure On_Data
     (Self           : in out Reader;
      Writer_Id      :        T.EntityId_T;
      SN             :        T.SequenceNumber_T;
      Payload        :        T.Octet_Buffer;
      Payload_Length :        Natural;
      Handled        :    out Boolean)
   is
      use type T.Octet_Buffer;
      Part : T.GuidPrefix_T;
      Kind : Message_Kind;
      Data : T.Octet_Buffer;
      Data_Length : Natural;
      Ok   : Boolean;
      Lease_Idx : Natural;
   begin
      Handled := False;

      if Writer_Id /= Built_In_Writer_Id then
         return;  --  not for us
      end if;

      if Payload = null or else Payload_Length = 0 then
         return;
      end if;

      declare
         Wire : constant T.Octet_Array :=
           Payload (1 .. Payload_Length);
      begin
         Decode (Wire, Part, Kind, Data, Data_Length, Ok);
      end;
      if not Ok then
         return;
      end if;

      --  Route into the reader cache and proxy state (T8 of 8.4.12.2).
      SR.On_Data (Self.Inner, Writer_Id, SN, Payload,
                  Payload_Length, Handled);

      --  Renew the lease of the corresponding instance.
      if Kind = PMDK_AUTOMATIC_LIVELINESS_UPDATE then
         Lease_Idx := 1;
      elsif Kind = PMDK_MANUAL_LIVELINESS_UPDATE then
         Lease_Idx := 2;
      else
         return;  --  vendor-specific kind: no lease bookkeeping
      end if;
      Self.Last_Seen (Lease_Idx) := Self.Clock_Now;
   end On_Data;

   procedure On_Heartbeat
     (Self        : in out Reader;
      Writer_Id   :        T.EntityId_T;
      First_SN    :        T.SequenceNumber_T;
      Last_SN     :        T.SequenceNumber_T;
      Final       :        Boolean;
      Ack_Request :    out Boolean)
   is
      Ack : Boolean;
   begin
      if Writer_Id /= Built_In_Writer_Id then
         Ack_Request := False;
         return;
      end if;
      SR.On_Heartbeat
        (Self.Inner, Writer_Id, First_SN, Last_SN, Final,
         Liveliness => False, Ack => Ack);
      Ack_Request := Ack;
   end On_Heartbeat;

   procedure Make_Acknack
     (Self     : in out Reader;
      Writer_Id :       T.EntityId_T;
      Acknack   :    out M.Submessage_T;
      Ok        :    out Boolean) is
   begin
      if Writer_Id /= Built_In_Writer_Id then
         Ok := False;
         return;
      end if;
      SR.Make_Acknack (Self.Inner, Writer_Id, Acknack, Ok);
   end Make_Acknack;

   ---------------------------------------------------------------------

   procedure Set_Now (Self : in out Reader; Now : Duration) is
   begin
      Self.Clock_Now := Now;
   end Set_Now;

   procedure Set_Lease
     (Self     : in out Reader;
      Kind     :        Liveliness_Kind;
      Lease    :        Duration)
   is
   begin
      case Kind is
         when Liveliness_Automatic =>
            Self.Leases (1) := Lease;
         when Liveliness_Manual_By_Participant =>
            Self.Leases (2) := Lease;
      end case;
   end Set_Lease;

   function Lease_Expired
     (Self : Reader; Kind : Liveliness_Kind; Now : Duration)
      return Boolean
   is
      Idx : constant Natural :=
        (case Kind is
           when Liveliness_Automatic => 1,
           when Liveliness_Manual_By_Participant => 2);
      use type T.Octet;
   begin
      if Self.Last_Seen (Idx) = 0.0 then
         return False;  --  nothing ever received: no expiry bookkeeping
      end if;
      return Now - Self.Last_Seen (Idx) > Self.Leases (Idx);
   end Lease_Expired;

   function Last_Assertion
     (Self : Reader; Kind : Liveliness_Kind) return Duration
   is
     (Self.Last_Seen
        (case Kind is
           when Liveliness_Automatic => 1,
           when Liveliness_Manual_By_Participant => 2));

end RTPS.Liveliness;
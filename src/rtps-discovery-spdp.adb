------------------------------------------------------------------------------
--  RTPS.Discovery.SPDP -- body
--
--  Message construction: RTPS Header (9.4.4) + INFO_TS + DATA with
--  SerializedData = ParameterList (9.6.2.2).  Sent best-effort: no
--  HEARTBEATs are exchanged for the SPDP endpoints.
------------------------------------------------------------------------------

with RTPS.CDR;
with RTPS.Messages;

package body RTPS.Discovery.SPDP is

   package D renames RTPS.Discovery.Data;
   package M renames RTPS.Messages;
   package C renames RTPS.CDR;

   use all type T.Octet;
   use all type T.Unsigned_Long;
   use all type T.BuiltinEndpointSet_T;
   use all type M.Submessage_Kind;
   use all type T.EntityId_T;
   use type T.Octet_Buffer;
   use all type T.ParameterId_T;
   use all type T.Unsigned_Short;
   use type Transports.Transport_Ref;
   use all type T.GUID_T;

   Loopback_Addr : constant T.Octet_Array16 :=
     (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 127, 0, 0, 1);

   --  8.5.3.4 / Table 9.8: SPDP well-known unicast port =
   --  PB + DG * domainId + d1 + PG * participantId.
   function SPDP_Well_Known_Unicast_Port
     (Domain_Id, Participant_Id : T.Unsigned_Long) return T.Unsigned_Long
   is (T.PB + T.DG * Domain_Id + T.D1 + T.PG * Participant_Id);

   --  Convert a Time_T duration to Ada Duration.
   function Lease_Of (V : T.Time_T) return Duration
   is (Duration (V.Seconds)
       + Duration (Long_Float (V.Fraction) / 2.0**32));

   ---------------------------------------------------------------------
   --  Local SPDPdiscoveredParticipantData (8.5.3.2), wrapped in a
   --  Header + INFO_TS + DATA message (SerializedData = ParameterList,
   --  9.6.2.2).
   ---------------------------------------------------------------------

   function Build_Announcement
     (Self : Participant_State; Length : out Natural)
      return T.Octet_Buffer
   is
      Buf : constant T.Octet_Buffer := new T.Octet_Array (1 .. 1024);
      S   : C.Stream;
      Guid : constant T.GUID_T :=
        (Guid_Prefix => Self.Prefix,
         Entity_Id   => T.ENTITYID_SPDP_BUILTIN_PARTICIPANT_WRITER);

      Local : constant D.Participant_Data :=
        (Protocol_Version => T.PROTOCOLVERSION,
         Guid_Prefix      => Self.Prefix,
         Vendor_Id        => Self.Vendor_Id,
         Expects_Inline_Qos => False,
         Available_Builtin_Endpoints =>
           T.DISC_BUILTIN_ENDPOINT_PARTICIPANT_ANNOUNCER or
           T.DISC_BUILTIN_ENDPOINT_PARTICIPANT_DETECTOR or
           T.DISC_BUILTIN_ENDPOINT_PUBLICATION_ANNOUNCER or
           T.DISC_BUILTIN_ENDPOINT_PUBLICATION_DETECTOR or
           T.DISC_BUILTIN_ENDPOINT_SUBSCRIPTION_ANNOUNCER or
           T.DISC_BUILTIN_ENDPOINT_SUBSCRIPTION_DETECTOR,
         Metatraffic_Unicast_Port =>
           T.Metatraffic_Unicast_Port
             (Self.Domain_Id, Self.Participant_Id),
         Metatraffic_Multicast_Port =>
           T.Metatraffic_Multicast_Port (Self.Domain_Id),
         Default_Unicast_Port =>
           T.User_Unicast_Port (Self.Domain_Id, Self.Participant_Id),
         Default_Multicast_Port =>
           T.User_Multicast_Port (Self.Domain_Id),
         Manual_Liveliness_Count => 0,
         Lease_Duration =>
           (Seconds => T.Long (Self.Lease_Duration), Fraction => 0));

      List : constant M.Parameter_Array_Ref :=
        D.Encode_Participant_Data (Local, Guid);

      SM_Info : M.Submessage_T (M.KIND_INFO_TS);
      SM_Data : M.Submessage_T (M.KIND_DATA);
   begin
      C.Bind (S, C.Octet_Array_Access (Buf), Buf.all'Length);

      --  Header (9.4.4).
      declare
         Hdr : M.Header_T;
      begin
         Hdr.Version := T.PROTOCOLVERSION;
         Hdr.Vendor_Id := Self.Vendor_Id;
         Hdr.Guid_Prefix := Self.Prefix;
         M.Encode_Header (S, Hdr);
      end;

      --  INFO_TS.
      SM_Info.Endianness := C.Little_Endian;
      SM_Info.Invalidate := False;
      SM_Info.Timestamp  := (Seconds => 0, Fraction => 0);
      M.Encode_Submessage (S, SM_Info, Last_Submessage => False);

      --  DATA with the ParameterList as SerializedData (9.6.2.2).
      SM_Data.Endianness := C.Little_Endian;
      SM_Data.Reader_Id  := T.ENTITYID_SPDP_BUILTIN_PARTICIPANT_READER;
      SM_Data.Writer_Id  := T.ENTITYID_SPDP_BUILTIN_PARTICIPANT_WRITER;
      SM_Data.Writer_SN  := 1;
      SM_Data.Has_Payload := True;
      SM_Data.Is_Key     := False;
      SM_Data.Inline_Qos := null;
      declare
         Pay  : C.Stream;
         Wire : constant T.Octet_Buffer :=
           new T.Octet_Array'(1 .. 512 => 0);
      begin
         C.Bind (Pay, C.Octet_Array_Access (Wire), Wire.all'Length);
         M.Put_Parameter_List (Pay, List.all, C.Little_Endian);
         SM_Data.Payload_Length := C.Encoded_Length (Pay);
         SM_Data.Payload := Wire;
      end;

      M.Encode_Submessage (S, SM_Data, Last_Submessage => True);
      Length := C.Encoded_Length (S);
      return Buf;
   end Build_Announcement;

   ---------------------------------------------------------------------

   procedure Parse_Announcement
     (Msg  :        T.Octet_Array;
      Guid :    out T.GUID_T;
      PD   :    out D.Participant_Data;
      Ok   :    out Boolean)
   is
      Pay : constant T.Octet_Buffer :=
        new T.Octet_Array'(Msg (Msg'First .. Msg'Last));
      St  : C.Stream;
      Hdr : M.Header_T;
      SM  : M.Submessage_T;
      Found : Boolean := False;
   begin
      Guid := T.GUID_UNKNOWN;
      PD   := D.Participant_Data'(others => <>);
      Ok := False;

      C.Bind (St, C.Octet_Array_Access (Pay), Pay.all'Length);
      M.Decode_Header (St, Hdr);
      Guid.Guid_Prefix := Hdr.Guid_Prefix;

      --  Walk the submessages; take the first DATA from the SPDP
      --  writer (9.6.2.2: discovery data rides in standard DATA).
      while C.Encoded_Length (St) < Pay.all'Length loop
         M.Decode_Submessage (St, SM);
         if SM.Kind = M.KIND_DATA
           and then SM.Writer_Id =
             T.ENTITYID_SPDP_BUILTIN_PARTICIPANT_WRITER
           and then SM.Payload /= null
         then
            declare
               Wire : constant T.Octet_Buffer :=
                 new T.Octet_Array'(SM.Payload (1 .. SM.Payload_Length));
               PSt  : C.Stream;
               List : M.Parameter_Array_Ref;
            begin
               C.Bind (PSt, C.Octet_Array_Access (Wire),
                       Wire.all'Length);
               M.Decode_Parameter_List (PSt, List, C.Little_Endian);
               for P of List.all loop
                  if P.Parameter_Id = T.PID_PARTICIPANT_GUID
                    and then P.Value /= null and then P.Length >= 16
                  then
                     --  The parameter is authoritative (Table 9.10
                     --  permits omitting the guidPrefix elsewhere).
                     for K in 1 .. 12 loop
                        Guid.Guid_Prefix (K) :=
                          P.Value (P.Value'First + K - 1);
                     end loop;
                     for K in 1 .. 4 loop
                        Guid.Entity_Id (K) :=
                          P.Value (P.Value'First + 12 + K - 1);
                     end loop;
                  end if;
               end loop;
               PD := D.Decode_Participant_Data (List);
            end;
            Found := True;
            exit;
         end if;
      end loop;
      Ok := Found;
   end Parse_Announcement;

   ---------------------------------------------------------------------

   procedure New_Participant
     (Self           : in out Participant_State;
      Guid_Prefix    :        T.GuidPrefix_T;
      Domain_Id      :        T.Unsigned_Long;
      Participant_Id :        T.Unsigned_Long;
      Vendor_Id      :        T.VendorId_T := (16#42#, 16#13#);
      Lease_Duration :        Duration := 100.0;
      Resend_Period  :        Duration := 30.0)
   is
   begin
      Self :=
        (Prefix         => Guid_Prefix,
         Domain_Id      => Domain_Id,
         Participant_Id => Participant_Id,
         Vendor_Id      => Vendor_Id,
         Lease_Duration => Lease_Duration,
         Resend_Period  => Resend_Period,
         Transport      => null,
         Remotes        => (others => <>),
         Remote_Count   => 0,
         Last_Announce  => 0.0,
         Have_Announced => False,
         Clock_Now      => 0.0);
   end New_Participant;

   procedure Open
     (Self : in out Participant_State; To : Transports.Transport_Ref)
   is
   begin
      Self.Transport := To;
   end Open;

   ---------------------------------------------------------------------

   function Needs_Announce
     (Self : Participant_State; Now : Duration) return Boolean
   is
   begin
      if not Self.Have_Announced then
         return True;
      end if;
      return Now - Self.Last_Announce >= Self.Resend_Period;
   end Needs_Announce;

   procedure Announce (Self : in out Participant_State)
   is
      Msg    : T.Octet_Buffer;
      Length : Natural;
      Tr     : constant Transports.Transport_Ref := Self.Transport;
   begin
      if Tr = null then
         return;
      end if;

      Msg := Build_Announcement (Self, Length);

         --  Well-known multicast locator (9.6.1.4.1):
         --  {LOCATOR_KIND_UDPv4, "239.255.0.1", PB + DG*domainId + d0}.
         Transports.Send
           (Self => Tr.all,
            Dest =>
              (Kind    => T.LOCATOR_KIND_UDPv4,
               Address => T.SPDP_Multicast_Addr,
               Port    => T.SPDP_Multicast_Port (Self.Domain_Id)),
            Data => Msg (1 .. Length));

         --  Well-known unicast locator of this node (Table 9.8):
         --  reaches co-located participants on the same host.
         Transports.Send
           (Self => Tr.all,
            Dest =>
              (Kind    => T.LOCATOR_KIND_UDPv4,
               Address => Loopback_Addr,
               Port    => SPDP_Well_Known_Unicast_Port
                            (Self.Domain_Id, Self.Participant_Id)),
            Data => Msg (1 .. Length));

      Self.Have_Announced := True;
      Self.Last_Announce := Self.Clock_Now;
   end Announce;

   ---------------------------------------------------------------------

   procedure On_Data
     (Self     : in out Participant_State;
      Data     :        T.Octet_Array;
      Src_Addr :        T.Octet_Array16;
      Src_Port :        T.Unsigned_Long;
      Fresh    :    out Boolean;
      Guid     :    out T.GUID_T)
   is
      Info : D.Participant_Data;
      Ok   : Boolean;
      Slot : Natural := 0;
      pragma Unreferenced (Src_Addr, Src_Port);
   begin
      Fresh := False;
      Parse_Announcement (Data, Guid, Info, Ok);
      if not Ok then
         return;
      end if;

      --  Look for an existing entry keyed by the participant GUID
      --  (8.5.3.3.2).
      for K in 1 .. Max_Remote_Participants loop
         if Self.Remotes (K).Used
           and then Self.Remotes (K).Guid = Guid
         then
            Slot := K;
            exit;
         end if;
      end loop;

      if Slot = 0 then
         for K in 1 .. Max_Remote_Participants loop
            if not Self.Remotes (K).Used then
               Slot := K;
               exit;
            end if;
         end loop;
         if Slot = 0 then
            return;  --  table full; drop
         end if;
         Self.Remotes (Slot) :=
           (Used      => True,
            Guid      => Guid,
            Meta_Port => Info.Metatraffic_Unicast_Port,
            Lease     => Lease_Of (Info.Lease_Duration),
            Last_Seen => Self.Clock_Now);
         Self.Remote_Count := Self.Remote_Count + 1;
         Fresh := True;
      else
         --  Refresh lease (8.5.3.3.2: renewed on every announcement).
         Self.Remotes (Slot).Lease := Lease_Of (Info.Lease_Duration);
         Self.Remotes (Slot).Last_Seen := Self.Clock_Now;
         Self.Remotes (Slot).Meta_Port := Info.Metatraffic_Unicast_Port;
      end if;
   end On_Data;

   ---------------------------------------------------------------------

   procedure Expire_Stale
     (Self : in out Participant_State; Now : Duration)
   is
   begin
      Self.Clock_Now := Now;
      for K in 1 .. Max_Remote_Participants loop
         if Self.Remotes (K).Used
           and then Now - Self.Remotes (K).Last_Seen
                      > Self.Remotes (K).Lease
         then
            Self.Remotes (K) := (Used => False, others => <>);
            Self.Remote_Count := Self.Remote_Count - 1;
         end if;
      end loop;
   end Expire_Stale;

   function Remote_Count (Self : Participant_State) return Natural is
     (Self.Remote_Count);

   procedure Remotes
     (Self  : Participant_State;
      Guids :    out Participant_Guid_Array;
      Count :    out Natural)
   is
   begin
      Count := 0;
      Guids := (others => T.GUID_UNKNOWN);
      for K in 1 .. Max_Remote_Participants loop
         if Self.Remotes (K).Used then
            Count := Count + 1;
            Guids (Count) := Self.Remotes (K).Guid;
         end if;
      end loop;
   end Remotes;

   function Remote_Metatraffic_Port
     (Self : Participant_State; Guid : T.GUID_T) return T.Unsigned_Long
   is
   begin
      for K in 1 .. Max_Remote_Participants loop
         if Self.Remotes (K).Used and then Self.Remotes (K).Guid = Guid
         then
            return Self.Remotes (K).Meta_Port;
         end if;
      end loop;
      return 0;
   end Remote_Metatraffic_Port;

end RTPS.Discovery.SPDP;
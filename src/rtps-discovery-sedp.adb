------------------------------------------------------------------------------
--  RTPS.Discovery.SEDP -- body
------------------------------------------------------------------------------

with RTPS.CDR;
with RTPS.Messages;
with RTPS.Transports;
with RTPS.Types;

package body RTPS.Discovery.SEDP is

   package D renames RTPS.Discovery.Data;
   package M renames RTPS.Messages;
   package H renames RTPS.History;
   package SW renames RTPS.StatefulWriter;
   package SR renames RTPS.StatefulReader;
   package C  renames RTPS.CDR;

   use all type T.EntityId_T;
   use all type T.GUID_T;

   ---------------------------------------------------------------------
   --  Helpers
   ---------------------------------------------------------------------

   D2_Max_String : constant := 256;

   procedure Set_String
     (Dst : out T.Octet_Array; Len : out Natural; S : String)
   with Pre => S'Length <= D2_Max_String;

   procedure Set_String
     (Dst : out T.Octet_Array; Len : out Natural; S : String)
   is
      use all type T.Octet;
   begin
      Len := S'Length;
      for K in S'Range loop
         Dst (1 + K - S'First) := T.Octet (Character'Pos (S (K)));
      end loop;
   end Set_String;

   function Desc_Of
     (Guid : T.GUID_T; Topic : String; Kind : Endpoint_Kind)
      return D.Endpoint_Data
   is
      R : D.Endpoint_Data;
   begin
      Set_String (R.Topic_Name, R.Topic_Len, Topic);
      Set_String (R.Type_Name, R.Type_Len, "");
      R.Writer_Or_Reader_Guid := Guid;
      R.Reliability := True;   --  SEDP endpoints are reliable (8.5.4.2)
      R.Unicast_Port := 0;
      R.Expects_Inline_Qos := False;
      return R;
   end Desc_Of;

   ---------------------------------------------------------------------

   procedure New_Sedp
     (Self            : in out Sedp_State;
      Participant_Guid :       T.GUID_T;
      Publications_Cache :     H.History_Cache_Ref;
      Subscriptions_Cache :    H.History_Cache_Ref)
   is
   begin
      Self.Participant_Guid := Participant_Guid;
      Self.Pub_Cache := Publications_Cache;
      Self.Sub_Cache := Subscriptions_Cache;

      SW.New_Writer
        (Self.Pub_Writer,
         (Guid_Prefix => Participant_Guid.Guid_Prefix,
          Entity_Id   => T.ENTITYID_SEDP_BUILTIN_PUBLICATIONS_WRITER),
         Publications_Cache);
      SR.New_Reader
        (Self.Pub_Reader,
         (Guid_Prefix => Participant_Guid.Guid_Prefix,
          Entity_Id   => T.ENTITYID_SEDP_BUILTIN_PUBLICATIONS_READER),
         Publications_Cache);
      SW.New_Writer
        (Self.Sub_Writer,
         (Guid_Prefix => Participant_Guid.Guid_Prefix,
          Entity_Id   => T.ENTITYID_SEDP_BUILTIN_SUBSCRIPTIONS_WRITER),
         Subscriptions_Cache);
      SR.New_Reader
        (Self.Sub_Reader,
         (Guid_Prefix => Participant_Guid.Guid_Prefix,
          Entity_Id   => T.ENTITYID_SEDP_BUILTIN_SUBSCRIPTIONS_READER),
         Subscriptions_Cache);
   end New_Sedp;

   procedure Open
     (Self : in out Sedp_State; To : RTPS.Transports.Transport_Ref)
   is
   begin
      SW.Open (Self.Pub_Writer, To);
      SW.Open (Self.Sub_Writer, To);
   end Open;

   ---------------------------------------------------------------------

   procedure Match_Participant
     (Self          : in out Sedp_State;
      Participant    :        T.GUID_T;
      Meta_Port      :        T.Unsigned_Long;
      Expects_Inline  :        Boolean := False)
   is
      use type T.EntityId_T;
   begin
      --  8.5.5.1: match the local SEDP machines with the remote
      --  built-in endpoints.  The remote participant data announces
      --  which endpoints it has; we match all four (publications and
      --  subscriptions, writer and reader roles).
      declare
         Reader_Proxy : constant SW.Match_Info :=
           (Remote_Reader_Guid =>
              (Guid_Prefix => Participant.Guid_Prefix,
               Entity_Id   => T.ENTITYID_SEDP_BUILTIN_PUBLICATIONS_READER),
            Expects_Inline_Qos => Expects_Inline,
            Unicast_Port   => Meta_Port,
            Multicast_Port => 0);
         Writer_Guid  : constant T.GUID_T :=
           (Guid_Prefix => Participant.Guid_Prefix,
            Entity_Id   => T.ENTITYID_SEDP_BUILTIN_PUBLICATIONS_WRITER);
      begin
         SW.Matched_Reader_Add
           (Self.Pub_Writer, Reader_Proxy, Window_First => 1,
            Window_Last  => 32);
         SR.Matched_Writer_Add (Self.Pub_Reader, Writer_Guid, Meta_Port);
      end;

      declare
         Reader_Proxy : constant SW.Match_Info :=
           (Remote_Reader_Guid =>
              (Guid_Prefix => Participant.Guid_Prefix,
               Entity_Id   => T.ENTITYID_SEDP_BUILTIN_SUBSCRIPTIONS_READER),
            Expects_Inline_Qos => Expects_Inline,
            Unicast_Port   => Meta_Port,
            Multicast_Port => 0);
         Writer_Guid  : constant T.GUID_T :=
           (Guid_Prefix => Participant.Guid_Prefix,
            Entity_Id   => T.ENTITYID_SEDP_BUILTIN_SUBSCRIPTIONS_WRITER);
      begin
         SW.Matched_Reader_Add
           (Self.Sub_Writer, Reader_Proxy, Window_First => 1,
            Window_Last  => 32);
         SR.Matched_Writer_Add (Self.Sub_Reader, Writer_Guid, Meta_Port);
      end;
   end Match_Participant;

   procedure Unmatch_Participant
     (Self : in out Sedp_State; Participant : T.GUID_T)
   is
      use type T.EntityId_T;
   begin
      --  8.5.5.2: remove the proxies of the remote built-in endpoints.
      SW.Matched_Reader_Remove
        (Self.Pub_Writer,
         (Guid_Prefix => Participant.Guid_Prefix,
          Entity_Id   => T.ENTITYID_SEDP_BUILTIN_PUBLICATIONS_READER));
      SR.Matched_Writer_Remove
        (Self.Pub_Reader,
         (Guid_Prefix => Participant.Guid_Prefix,
          Entity_Id   => T.ENTITYID_SEDP_BUILTIN_PUBLICATIONS_WRITER));
      SW.Matched_Reader_Remove
        (Self.Sub_Writer,
         (Guid_Prefix => Participant.Guid_Prefix,
          Entity_Id   => T.ENTITYID_SEDP_BUILTIN_SUBSCRIPTIONS_READER));
      SR.Matched_Writer_Remove
        (Self.Sub_Reader,
         (Guid_Prefix => Participant.Guid_Prefix,
          Entity_Id   => T.ENTITYID_SEDP_BUILTIN_SUBSCRIPTIONS_WRITER));
   end Unmatch_Participant;

   ---------------------------------------------------------------------


   ---------------------------------------------------------------------
   --  Internal helpers
   ---------------------------------------------------------------------

   procedure Add_Remote
     (Self : in out Sedp_State;
      Kind :        Endpoint_Kind;
      Desc :        D.Endpoint_Data)
   is
      use all type T.Octet;
   begin
      --  Update-or-insert keyed by the endpoint GUID (8.5.4.4: one
      --  data-object per endpoint in the reader caches).
      for K in 1 .. Self.Remote_Num loop
         if Self.Remote_List (K).Guid = Desc.Writer_Or_Reader_Guid
           and then Self.Remote_List (K).Kind = Kind
         then
            Self.Remote_List (K).Topic := Desc;
            return;
         end if;
      end loop;
      if Self.Remote_Num < Max_Remote_Endpoints then
         Self.Remote_Num := Self.Remote_Num + 1;
         Self.Remote_List (Self.Remote_Num) :=
           (Guid        => Desc.Writer_Or_Reader_Guid,
            Kind        => Kind,
            Topic       => Desc,
            Participant => Desc.Writer_Or_Reader_Guid.Guid_Prefix);
      end if;
   end Add_Remote;

   --  Push all pending changes of a SEDP writer to all matched
   --  readers (T4/T12 for every proxy).
   procedure Push_All_Writer (W : in out SW.Writer_State) is
      It   : SW.Reader_Iterator;
      Guid : T.GUID_T;
      Guard : Natural := 0;
   begin
      --  Each Push_Next sends one change to one reader; loop until
      --  nothing is pending (bounded by history capacity).
      while SW.Has_Pending (W) and then Guard < 4096 loop
         Guard := Guard + 1;
         SW.First_Reader (W, It, Guid);
         exit when Guid = T.GUID_UNKNOWN;
         SW.Push_Next (W, Guid);
      end loop;
   end Push_All_Writer;

   procedure Register_On
     (W          : in out SW.Writer_State;
      Cache      :          H.History_Cache_Ref;
      Kind       :          Endpoint_Kind;
      Guid       :          T.GUID_T;
      Desc       :          D.Endpoint_Data;
      Num        : in out Natural;
      Locals     : in out Local_Endpoints;
      Max_Locals :          Natural)
   is
      Change : H.Cache_Change_Ref;
      List   : constant M.Parameter_Array_Ref :=
        (if Kind = Kind_Writer
         then D.Encode_Writer_Data (Desc)
         else D.Encode_Reader_Data (Desc));
      Pay : C.Stream;
      Wire : constant T.Octet_Buffer := new T.Octet_Array'(1 .. 1024 => 0);
      use all type T.Octet;
   begin
      --  Serialize the parameter list payload.
      C.Bind (Pay, C.Octet_Array_Access (Wire), Wire.all'Length);
      M.Put_Parameter_List (Pay, List.all, C.Little_Endian);

      Cache.Add_Change
        (Kind        => T.ALIVE,
         Write_Time  => (Seconds => 0, Fraction => 0),
         Instance    => 0,
         Data        => Wire,
         Data_Length => C.Encoded_Length (Pay),
         Change      => Change);

      SW.On_New_Change (W, Change.all.SN);

      if Num < Max_Locals then
         Num := Num + 1;
         Locals (Num) :=
           (Guid => Guid, Kind => Kind, Topic => Desc);
      end if;
   end Register_On;

   procedure Register_Writer
     (Self  : in out Sedp_State;
      Guid  :        T.GUID_T;
      Desc  :        D.Endpoint_Data)
   is
   begin
      Register_On
        (Self.Pub_Writer, Self.Pub_Cache, Kind_Writer,
         Guid, Desc, Self.Local_Count, Self.Locals, Max_Local_Endpoints);
   end Register_Writer;

   procedure Register_Reader
     (Self  : in out Sedp_State;
      Guid  :        T.GUID_T;
      Desc  :        D.Endpoint_Data)
   is
   begin
      Register_On
        (Self.Sub_Writer, Self.Sub_Cache, Kind_Reader,
         Guid, Desc, Self.Local_Count, Self.Locals, Max_Local_Endpoints);
   end Register_Reader;

   ---------------------------------------------------------------------

   procedure Send_Heartbeats (Self : in out Sedp_State) is
   begin
      SW.Send_Heartbeat (Self.Pub_Writer);
      SW.Send_Heartbeat (Self.Sub_Writer);
   end Send_Heartbeats;

   procedure Push_Pending (Self : in out Sedp_State) is
   begin
      --  T4/T12 for every proxy of both SEDP writers.
      Push_All_Writer (Self.Pub_Writer);
      Push_All_Writer (Self.Sub_Writer);
   end Push_Pending;

   ---------------------------------------------------------------------

   procedure On_Data
     (Self     : in out Sedp_State;
      Writer_Id :       T.EntityId_T;
      SN       :        T.SequenceNumber_T;
      Payload  :        T.Octet_Buffer;
      Payload_Length : Natural;
      Handled  :    out Boolean)
   is
      use type T.EntityId_T;
      use type T.Octet_Buffer;
      Desc : D.Endpoint_Data;
      List : M.Parameter_Array_Ref;
      St   : C.Stream;
      Wire : constant T.Octet_Buffer :=
        new T.Octet_Array'(Payload (1 .. Payload_Length));
   begin
      Handled := False;

      --  Decode the parameter list payload (9.6.2.2).
      if Payload = null or else Payload_Length = 0 then
         return;
      end if;
      C.Bind (St, C.Octet_Array_Access (Wire), Wire.all'Length);
      M.Decode_Parameter_List (St, List, C.Little_Endian);

      --  Route to the publications or subscriptions reader based on
      --  the writer EntityId.
      if Writer_Id = T.ENTITYID_SEDP_BUILTIN_PUBLICATIONS_WRITER then
         SR.On_Data (Self.Pub_Reader, Writer_Id, SN, Payload,
                     Payload_Length, Handled);
         Desc := D.Decode_Writer_Data (List);
         Add_Remote (Self, Kind_Writer, Desc);
         Handled := True;
      elsif Writer_Id = T.ENTITYID_SEDP_BUILTIN_SUBSCRIPTIONS_WRITER then
         SR.On_Data (Self.Sub_Reader, Writer_Id, SN, Payload,
                     Payload_Length, Handled);
         Desc := D.Decode_Reader_Data (List);
         Add_Remote (Self, Kind_Reader, Desc);
         Handled := True;
      end if;
   end On_Data;

   procedure On_Heartbeat
     (Self     : in out Sedp_State;
      Writer_Id :       T.EntityId_T;
      First_SN :        T.SequenceNumber_T;
      Last_SN  :        T.SequenceNumber_T;
      Final    :        Boolean;
      Ack_Request :  out Boolean)
   is
      use type T.EntityId_T;
      Ack : Boolean;
   begin
      Ack_Request := False;
      if Writer_Id = T.ENTITYID_SEDP_BUILTIN_PUBLICATIONS_WRITER then
         SR.On_Heartbeat
           (Self.Pub_Reader, Writer_Id, First_SN, Last_SN, Final,
            Liveliness => False, Ack => Ack);
         Ack_Request := Ack;
      elsif Writer_Id = T.ENTITYID_SEDP_BUILTIN_SUBSCRIPTIONS_WRITER
      then
         SR.On_Heartbeat
           (Self.Sub_Reader, Writer_Id, First_SN, Last_SN, Final,
            Liveliness => False, Ack => Ack);
         Ack_Request := Ack;
      end if;
   end On_Heartbeat;

   procedure On_Acknack
     (Self     : in out Sedp_State;
      Reader_Id :       T.EntityId_T;
      Writer_Id :       T.EntityId_T;
      Base_SN  :        T.SequenceNumber_T;
      Bitmap   :        T.Unsigned_Long;
      Num_Bits :        T.Unsigned_Long;
      Final    :        Boolean;
      Repair   :    out Boolean)
   is
      use type T.EntityId_T;
   begin
      if Writer_Id = T.ENTITYID_SEDP_BUILTIN_PUBLICATIONS_WRITER then
         SW.On_Acknack (Self.Pub_Writer, Reader_Id, Writer_Id, Base_SN,
                        Bitmap, Num_Bits, Final, Repair);
      elsif Writer_Id = T.ENTITYID_SEDP_BUILTIN_SUBSCRIPTIONS_WRITER
      then
         SW.On_Acknack (Self.Sub_Writer, Reader_Id, Writer_Id, Base_SN,
                        Bitmap, Num_Bits, Final, Repair);
      else
         Repair := False;
      end if;
   end On_Acknack;

   ---------------------------------------------------------------------

   function Remote_Count (Self : Sedp_State) return Natural is
     (Self.Remote_Num);

   procedure Remotes
     (Self  : Sedp_State;
      List  :    out Remote_Endpoints;
      Count :    out Natural)
   is
   begin
      List := (others => (Guid => T.GUID_UNKNOWN,
                          Kind => Kind_Writer,
                          Topic => <>,
                          Participant => T.GUIDPREFIX_UNKNOWN));
      Count := Self.Remote_Num;
      for K in 1 .. Self.Remote_Num loop
         List (K) := Self.Remote_List (K);
      end loop;
   end Remotes;

   function Local_Count (Self : Sedp_State) return Natural is
     (Self.Local_Count);

   ---------------------------------------------------------------------

   function Matches
     (Writer_Desc : D.Endpoint_Data;
      Reader_Desc : D.Endpoint_Data) return Boolean
   is
      use all type T.Octet;
   begin
      if not Writer_Desc.Reliability or else not Reader_Desc.Reliability
      then
         return False;
      end if;
      if Writer_Desc.Topic_Len /= Reader_Desc.Topic_Len then
         return False;
      end if;
      for K in 1 .. Writer_Desc.Topic_Len loop
         if Writer_Desc.Topic_Name (K) /= Reader_Desc.Topic_Name (K) then
            return False;
         end if;
      end loop;
      return True;
   end Matches;

end RTPS.Discovery.SEDP;
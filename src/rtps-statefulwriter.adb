------------------------------------------------------------------------------
--  RTPS.StatefulWriter -- body
--
--  Implements the Reliable StatefulWriter behavior of 8.4.9.2 against
--  the abstract Transport.  Each outgoing DATA/HEARTBEAT/GAP is sent
--  as its own RTPS Message (Header + submessage).
------------------------------------------------------------------------------

with RTPS.CDR;

package body RTPS.StatefulWriter is

   use all type Types.SequenceNumber_T;
   use all type Types.Octet;
   use all type Types.Octet_Buffer;
   use all type History.History_Cache_Ref;
   use all type Types.Unsigned_Long;
   use all type Types.EntityId_T;
   use all type Transports.Transport_Ref;
   use all type History.Cache_Change_Ref;
   use all type Types.ChangeKind_T;

   ---------------------------------------------------------------------
   --  Setup
   ---------------------------------------------------------------------

   procedure New_Writer
     (Self          : in out Writer_State;
      Writer_Guid   :        Types.GUID_T;
      Cache         :        History.History_Cache_Ref;
      Heartbeat_Period :     Duration := RTPS.Proto.Default_Heartbeat_Period)
   is
   begin
      Self.Guid := Writer_Guid;
      Self.Cache := Cache;
      Self.Heartbeat_Period := Heartbeat_Period;
      Self.Reader_Count := 0;
      for K in Self.Readers'Range loop
         Self.Readers (K).Used := False;
      end loop;
   end New_Writer;

   procedure Open
     (Self : in out Writer_State; To_Transport : Transports.Transport_Ref)
   is
   begin
      Self.Transport := To_Transport;
   end Open;

   ---------------------------------------------------------------------
   --  Match management
   ---------------------------------------------------------------------

   procedure Matched_Reader_Add
     (Self      : in out Writer_State;
      Proxy     :        Match_Info;
      Window_First :    Types.SequenceNumber_T;
      Window_Last  :    Types.SequenceNumber_T)
   is
      use all type P.ChangeForReader_Status_Kind;
      Slot : Natural := 0;
      New_Proxy : P.ReaderProxy;
      Min_SN : Types.SequenceNumber_T := 0;
      Max_SN : Types.SequenceNumber_T := 0;
      Cache_C : History.History_Cache_Ref := Self.Cache;
   begin
      if Self.Reader_Count >= Max_Matched_Readers then
         raise Match_Count;
      end if;

      for K in Self.Readers'Range loop
         if not Self.Readers (K).Used then
            Slot := K;
            exit;
         end if;
      end loop;

      if Cache_C /= null then
         Min_SN := Cache_C.Get_Seq_Num_Min;
         Max_SN := Cache_C.Get_Seq_Num_Max;
         --  Empty history reports UNKNOWN (0): nothing is acked then.
         if Min_SN = 0 then
            Min_SN := 1;
         end if;
         if Max_SN = 0 then
            Max_SN := 0;
         end if;
      end if;

      --  Build the ReaderProxy with a status window covering
      --  [Window_First .. Window_Last] where SNs beyond the cache max
      --  are UNKNOWN; the spec's change-for-reader lifecycle maps to:
      --    SN < cache_min  -> ACKNOWLEDGED (already gone from history)
      --    cache_min..max  -> UNSENT (push mode)
      --  We allocate a status window over [Window_First .. Window_Last].
      New_Proxy := P.ReaderProxy'
        (Remote_Reader_Guid => Proxy.Remote_Reader_Guid,
         Expects_Inline_Qos => Proxy.Expects_Inline_Qos,
         Is_Active          => True,
         First_SN           => Window_First,
         Last_SN            => Window_Last,
         Status             => new P.CFR_Status_Array
                                   (0 .. Integer (Window_Last - Window_First)),
         Unsent_Size        => 0,
         Acked_Up_To        => 0,
         Req_Count          => 0,
         Req_Min_SN         => 0,
         Highest_Req_SN     => 0,
         Unicast_Port       => Proxy.Unicast_Port,
         Multicast_Port     => Proxy.Multicast_Port);

      --  Initialize window statuses.
      declare
         SN : Types.SequenceNumber_T := Window_First;
      begin
         while SN <= Window_Last loop
            declare
               Idx : constant Natural := Natural (SN - Window_First);
            begin
               if SN < Min_SN then
                  New_Proxy.Status.all (Idx) := P.ACKNOWLEDGED;
               else
                  New_Proxy.Status.all (Idx) := P.UNSENT;
                  New_Proxy.Unsent_Size := New_Proxy.Unsent_Size + 1;
               end if;
            end;
            SN := SN + 1;
         end loop;
      end;

      Self.Readers (Slot) := (Used => True, Proxy => New_Proxy);
      Self.Reader_Count := Self.Reader_Count + 1;
   end Matched_Reader_Add;

   procedure Matched_Reader_Remove
     (Self  : in out Writer_State;
      Guid  :        Types.GUID_T)
   is
   begin
      for K in Self.Readers'Range loop
         if Self.Readers (K).Used
           and then P.GUID_Equal (Self.Readers (K).Proxy.Remote_Reader_Guid,
                                  Guid)
         then
            Self.Readers (K).Used := False;
            Self.Reader_Count := Self.Reader_Count - 1;
            return;
         end if;
      end loop;
      raise Unknown_Reader with "matched_reader_remove: guid not found";
   end Matched_Reader_Remove;

   function Find_Reader
     (Self : Writer_State; Guid : Types.GUID_T) return Natural
   is
   begin
      for K in Self.Readers'Range loop
         if Self.Readers (K).Used
           and then P.GUID_Equal (Self.Readers (K).Proxy.Remote_Reader_Guid,
                                  Guid)
         then
            return K;
         end if;
      end loop;
      return 0;
   end Find_Reader;

   ---------------------------------------------------------------------
   --  Wire helpers: send one submessage as one Message
   ---------------------------------------------------------------------

   procedure Send_Message
     (Self    : in out Writer_State;
      Dest    :        Types.Locator_T;
      SM      :        M.Submessage_T)
   is
      S : CDR.Stream;
      use all type Types.Octet;
      Buf : constant CDR.Octet_Array_Access :=
        new Types.Octet_Array (1 .. RTPS.Max_Message_Size);
   begin
      if Self.Transport = null then
         raise Not_Open with "no transport attached";
      end if;
      CDR.Bind (S, Buf, Buf.all'Length);
      M.Encode_Header
        (S,
         (Version     => Types.PROTOCOLVERSION,
          Vendor_Id   => Types.VENDORID_UNKNOWN,
          Guid_Prefix => Self.Guid.Guid_Prefix));
      M.Encode_Submessage (S, SM, Last_Submessage => True);
      declare
         T : constant Transports.Transport_Ref := Self.Transport;
      begin
         Transports.Send
           (T.all, Dest, Buf.all (1 .. S.Last));
      end;
   end Send_Message;

   --  8.4.9.2.4: DATA for a relevant change, GAP for an irrelevant one.
   procedure Send_Data_Or_Gap
     (Self    : in out Writer_State;
      Slot    :        Natural;
      SN      :        Types.SequenceNumber_T;
      Relevant:        Boolean;
      For_Request : Boolean)
   is
      Proxy  : P.ReaderProxy renames Self.Readers (Slot).Proxy;
      D      : M.Submessage_T (M.KIND_DATA);
      G      : M.Submessage_T (M.KIND_GAP);
      Change : History.Cache_Change_Ref;
   begin
      if Relevant then
         Change := Self.Cache.Find (SN);
         if Change = null then
            --  Change was removed from history; send a GAP instead.
            G.Endianness := CDR.Little_Endian;
            G.Gap_Start  := SN;
            G.Gap_List   := (Bitmap_Base => SN + 1, Num_Bits => 0, Bitmap => 0);
            Send_Message (Self,
              Types.Make_UDPv4_Locator (127, 0, 0, 1, Proxy.Unicast_Port), G);
            return;
         end if;
         D.Endianness := CDR.Little_Endian;
         D.Reader_Id  := Proxy.Remote_Reader_Guid.Entity_Id;
         D.Writer_Id  := Self.Guid.Entity_Id;
         D.Writer_SN  := SN;
         D.Has_Payload := Change.Data /= null and then Change.Data_Length > 0;
         D.Is_Key     := False;
         D.Payload        := Change.Data;
         D.Payload_Length := Change.Data_Length;
         Send_Message (Self,
           Types.Make_UDPv4_Locator (127, 0, 0, 1, Proxy.Unicast_Port), D);
      else
         G.Endianness := CDR.Little_Endian;
         G.Gap_Start  := SN;
         G.Gap_List   := (Bitmap_Base => SN + 1, Num_Bits => 0, Bitmap => 0);
         Send_Message (Self,
           Types.Make_UDPv4_Locator (127, 0, 0, 1, Proxy.Unicast_Port), G);
      end if;
   end Send_Data_Or_Gap;

   ---------------------------------------------------------------------
   --  Protocol operations
   ---------------------------------------------------------------------

   function Is_Acked_By_All
     (Self : Writer_State; SN : Types.SequenceNumber_T) return Boolean
   is
      use all type P.ChangeForReader_Status_Kind;
      Found_Any : Boolean := False;
      Idx : Natural;
   begin
      for K in Self.Readers'Range loop
         if Self.Readers (K).Used then
            declare
               Proxy : P.ReaderProxy renames Self.Readers (K).Proxy;
            begin
                     if SN >= Proxy.First_SN and then SN <= Proxy.Last_SN then
                        Found_Any := True;
                        Idx := Natural (SN - Proxy.First_SN);
                        if Proxy.Status.all (Idx) /= P.ACKNOWLEDGED then
                           return False;
                        end if;
               end if;
            end;
         end if;
      end loop;
      return True;
   end Is_Acked_By_All;

   procedure Push_Next
     (Self  : in out Writer_State;
      Guid  :        Types.GUID_T;
      For_Request : Boolean := False)
   is
      Slot  : constant Natural := Find_Reader (Self, Guid);
      SN    : Types.SequenceNumber_T;
      Idx   : Natural;
      Proxy : P.ReaderProxy renames Self.Readers (Slot).Proxy;
      use all type P.ChangeForReader_Status_Kind;
      use all type Types.SequenceNumber_T;
   begin
      if Slot = 0 then
         raise Unknown_Reader with "push_next: guid not found";
      end if;

      if For_Request then
         SN := P.Next_Requested_SN (Proxy);
         if SN = 0 then
            return;
         end if;
         Idx := Natural (SN - Proxy.First_SN);
         --  Relevance from the cached change (irrelevant => GAP).
         declare
            Change : constant History.Cache_Change_Ref := Self.Cache.Find (SN);
            Relevant : constant Boolean := Change = null
              or else Change.Kind = Types.ALIVE;
            pragma Unreferenced (Change);
         begin
            Send_Data_Or_Gap (Self, Slot, SN, Relevant, For_Request => True);
            Proxy.Status.all (Idx) := P.ACKNOWLEDGED;
            if Proxy.Req_Count > 0 then
               Proxy.Req_Count := Proxy.Req_Count - 1;
            end if;
         end;
      else
         SN := P.Next_Unsent_SN (Proxy);
         if SN = 0 then
            return;
         end if;
         Idx := Natural (SN - Proxy.First_SN);
         declare
            Change : constant History.Cache_Change_Ref := Self.Cache.Find (SN);
            Relevant : constant Boolean := Change /= null
              and then Change.Kind = Types.ALIVE;
         begin
            Send_Data_Or_Gap (Self, Slot, SN, Relevant, For_Request => False);
            --  Push mode: DATA sent counts as UNACKNOWLEDGED until
            --  acked (reliable); irrelevant => treat as acked (GAP).
            if Relevant then
               Proxy.Status.all (Idx) := P.UNACKNOWLEDGED;
            else
               Proxy.Status.all (Idx) := P.ACKNOWLEDGED;
            end if;
         end;
      end if;
   end Push_Next;

   procedure Send_Heartbeat (Self : in out Writer_State) is
      HB   : M.Submessage_T (M.KIND_HEARTBEAT);
      use all type Types.Octet;
      Cache_C : constant History.History_Cache_Ref := Self.Cache;
      Min_SN  : Types.SequenceNumber_T := Cache_C.Get_Seq_Num_Min;
      Max_SN  : Types.SequenceNumber_T := Cache_C.Get_Seq_Num_Max;
   begin
      if Min_SN = 0 then
         return;  --  empty history
      end if;
      HB.Endianness := CDR.Little_Endian;
      HB.Reader_Id  := Types.ENTITYID_UNKNOWN;
      HB.Writer_Id  := Self.Guid.Entity_Id;
      HB.First_SN   := Min_SN;
      HB.Last_SN    := Max_SN;
      HB.Count      := 0;
      HB.Final      := False;  --  FinalFlag NOT_SET: demands a response
      HB.Liveliness := False;

      for K in Self.Readers'Range loop
         if Self.Readers (K).Used then
            Send_Message (Self,
              Types.Make_UDPv4_Locator
                 (127, 0, 0, 1, Self.Readers (K).Proxy.Unicast_Port), HB);
         end if;
      end loop;
   end Send_Heartbeat;

   procedure On_Acknack
     (Self      : in out Writer_State;
      Reader_Id :        Types.EntityId_T;
      Writer_Id :        Types.EntityId_T;
      Base_SN   :        Types.SequenceNumber_T;
      Bitmap    :        Types.Unsigned_Long;
      Num_Bits  :        Types.Unsigned_Long;
      Final     :        Boolean;
      Reply     :    out Boolean)
   is
      use all type Types.SequenceNumber_T;
      use type Types.Octet;
      Slot  : Natural := 0;
      Found : Boolean := False;
   begin
      Reply := False;

      for K in Self.Readers'Range loop
         if Self.Readers (K).Used
           and then Self.Readers (K).Proxy.Remote_Reader_Guid.Entity_Id
                      = Reader_Id
         then
            Slot := K;
            Found := True;
            exit;
         end if;
      end loop;
      if not Found then
         return;
      end if;

      --  8.4.9.2.8: acked_changes_set (all SNs < base are acked).
      P.Acked_Changes_Set (Self.Readers (Slot).Proxy, Base_SN - 1);

      --  requested_changes_set: bits in the bitmap mark NACKed SNs.
      if Num_Bits > 0 then
         declare
            use type Types.Unsigned_Long;
            Base : constant Types.SequenceNumber_T := Base_SN;
         begin
            for Offset in 0 .. Natural (Num_Bits) - 1 loop
               declare
                  Bit : constant Boolean :=
                    (Bitmap and 2**(31 - Offset)) /= 0;
                  SN  : constant Types.SequenceNumber_T :=
                    Base + Types.SequenceNumber_T (Offset);
               begin
                  if Bit then
                     P.Requested_Changes_Set (Self.Readers (Slot).Proxy, SN);
                  end if;
               end;
            end loop;
         end;
      end if;

      Reply := Self.Readers (Slot).Proxy.Req_Count > 0;
   end On_Acknack;

   procedure On_New_Change
     (Self : in out Writer_State; SN : Types.SequenceNumber_T) is
   begin
      --  T14: extend every proxy's window to include SN as UNSENT.
      for K in Self.Readers'Range loop
         if Self.Readers (K).Used then
            declare
               Proxy : P.ReaderProxy renames Self.Readers (K).Proxy;
               use all type P.ChangeForReader_Status_Kind;
            begin
               if SN > Proxy.Last_SN then
                  --  Grow the window to include SN (implicitly UNSENT
                  --  by window growth).
                  Proxy.Last_SN := SN;
                  Proxy.Unsent_Size := Proxy.Unsent_Size + 1;
               end if;
            end;
         end if;
      end loop;
   end On_New_Change;

   function Has_Pending (Self : Writer_State) return Boolean is
   begin
      for K in Self.Readers'Range loop
         if Self.Readers (K).Used then
            if P.Next_Unsent_SN (Self.Readers (K).Proxy) /= 0
              or else P.Next_Requested_SN (Self.Readers (K).Proxy) /= 0
            then
               return True;
            end if;
         end if;
      end loop;
      return False;
   end Has_Pending;

   function Reader_Count (Self : Writer_State) return Natural is
   begin
      return Self.Reader_Count;
   end Reader_Count;

   function Transport (Self : Writer_State) return Transports.Transport_Ref is
   begin
      return Self.Transport;
   end Transport;


   ---------------------------------------------------------------------
   --  Reader enumeration (used by the discovery layer)
   ---------------------------------------------------------------------

   procedure First_Reader
     (Self : Writer_State; It : out Reader_Iterator;
      Guid : out Types.GUID_T)
   is
   begin
      It := Reader_Iterator'First;
      loop
         exit when It = Reader_Iterator'Last;
         if Self.Readers (Natural (It)).Used then
            Guid := Self.Readers (Natural (It)).Proxy.Remote_Reader_Guid;
            return;
         end if;
         It := It + 1;
      end loop;
      Guid := Types.GUID_UNKNOWN;
   end First_Reader;

   procedure Next_Reader
     (Self : Writer_State; It : in out Reader_Iterator;
      Guid : out Types.GUID_T)
   is
   begin
      It := Reader_Iterator'Succ (It);
      loop
         exit when It = Reader_Iterator'Last;
         if Self.Readers (Natural (It)).Used then
            Guid := Self.Readers (Natural (It)).Proxy.Remote_Reader_Guid;
            return;
         end if;
         It := It + 1;
      end loop;
      Guid := Types.GUID_UNKNOWN;
   end Next_Reader;

   function Reader_Guid_Of_It (It : Reader_Iterator) return Types.GUID_T
   is (Types.GUID_UNKNOWN);
   --  Iteration returns GUIDs directly; this accessor exists for
   --  completeness.

end RTPS.StatefulWriter;
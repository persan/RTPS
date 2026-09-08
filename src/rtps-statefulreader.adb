------------------------------------------------------------------------------
--  RTPS.StatefulReader -- body
--
--  Implements the Reliable StatefulReader behavior of 8.4.12.2.  All
--  window/proxy state lives in RTPS.Proto.WriterProxy.
------------------------------------------------------------------------------

with RTPS.CDR;
with RTPS.Proto;

package body RTPS.StatefulReader is

   use all type Types.SequenceNumber_T;
   use all type Types.Unsigned_Long;
   use all type Types.EntityId_T;

   Window_Size : constant Types.SequenceNumber_T := 256;

   ---------------------------------------------------------------------
   --  Setup
   ---------------------------------------------------------------------

   procedure New_Reader
     (Self          : in out Reader_State;
      Reader_Guid   :        Types.GUID_T;
      Cache         :        History.History_Cache_Ref;
      Heartbeat_Response_Delay : Duration :=
        RTPS.Proto.Default_Heartbeat_Response_Delay)
   is
   begin
      Self.Guid := Reader_Guid;
      Self.Cache := Cache;
      Self.HB_Response_Delay := Heartbeat_Response_Delay;
      Self.Writer_Count := 0;
      for K in Self.Writers'Range loop
         Self.Writers (K).Used := False;
      end loop;
   end New_Reader;

   ---------------------------------------------------------------------
   --  Match management
   ---------------------------------------------------------------------

   function Find_Writer
     (Self : Reader_State; Writer_Id : Types.EntityId_T) return Natural
   is
   begin
      for K in Self.Writers'Range loop
         if Self.Writers (K).Used
           and then Self.Writers (K).Proxy.Remote_Writer_Guid.Entity_Id
                      = Writer_Id
         then
            return K;
         end if;
      end loop;
      return 0;
   end Find_Writer;

   procedure Matched_Writer_Add
     (Self      : in out Reader_State;
      Writer_Guid :      Types.GUID_T;
      Unicast_Port :   Types.Unsigned_Long := 0)
   is
      Slot : Natural := 0;
      New_Proxy : P.WriterProxy;
   begin
      if Self.Writer_Count >= Max_Matched_Writers then
         raise Constraint_Error with "too many matched writers";
      end if;
      if Find_Writer (Self, Writer_Guid.Entity_Id) /= 0 then
         return;  --  already matched
      end if;

      for K in Self.Writers'Range loop
         if not Self.Writers (K).Used then
            Slot := K;
            exit;
         end if;
      end loop;

      --  8.4.10.4.1: changes_from_writer initialized to UNKNOWN over
      --  a first window; statuses become MISSING/RECEIVED/LOST as
      --  HEARTBEATs and DATA arrive.
      New_Proxy := P.WriterProxy'
        (Remote_Writer_Guid => Writer_Guid,
         First_SN           => 1,
         Last_SN            => Window_Size,
         Status             => new P.CFW_Array (0 .. Natural (Window_Size) - 1),
         Available_Max      => 0,
         Heartbeat_Response_Delay => Self.HB_Response_Delay,
         Unicast_Port       => Unicast_Port);
      for K in 0 .. Natural (Window_Size) - 1 loop
         New_Proxy.Status.all (K) := P.UNKNOWN;
      end loop;

      Self.Writers (Slot) := (Used => True, Proxy => New_Proxy);
      Self.Writer_Count := Self.Writer_Count + 1;
   end Matched_Writer_Add;

   procedure Matched_Writer_Remove
     (Self : in out Reader_State; Writer_Guid : Types.GUID_T)
   is
   begin
      for K in Self.Writers'Range loop
         if Self.Writers (K).Used
           and then P.GUID_Equal (Self.Writers (K).Proxy.Remote_Writer_Guid,
                                  Writer_Guid)
         then
            Self.Writers (K).Used := False;
            Self.Writer_Count := Self.Writer_Count - 1;
            return;
         end if;
      end loop;
      raise Unknown_Writer with "matched_writer_remove: guid not found";
   end Matched_Writer_Remove;

   ---------------------------------------------------------------------
   --  Submessage handlers
   ---------------------------------------------------------------------

   procedure On_Heartbeat
     (Self      : in out Reader_State;
      Writer_Id :        Types.EntityId_T;
      First_SN  :        Types.SequenceNumber_T;
      Last_SN   :        Types.SequenceNumber_T;
      Final     :        Boolean;
      Liveliness:        Boolean;
      Ack       :    out Boolean)
   is
      use all type P.ChangeFromWriter_Status_Kind;
      Slot : constant Natural := Find_Writer (Self, Writer_Id);
      Proxy : P.WriterProxy renames Self.Writers (Slot).Proxy;
   begin
      Ack := False;

      if Slot = 0 then
         return;  --  HEARTBEAT from an unmatched writer: drop (T7 note)
      end if;

      --  T7: missing_changes_update(lastSN) + lost_changes_update(firstSN)
      if Last_SN > Proxy.Last_SN then
         --  Writer announced beyond the current window: grow it.
         declare
            New_Size : constant Natural := Natural (Last_SN - Proxy.First_SN + 1);
            Old_Status : constant P.CFW_Buffer := Proxy.Status;
            New_Status : constant P.CFW_Buffer :=
              new P.CFW_Array (0 .. New_Size - 1);
         begin
            for K in New_Status.all'Range loop
               New_Status.all (K) := P.UNKNOWN;
            end loop;
            --  Preserve old statuses.
            declare
               Old_Last : constant Natural :=
                 Natural (Proxy.Last_SN - Proxy.First_SN + 1);
            begin
               for K in 0 .. Old_Last - 1 loop
                  New_Status.all (K) := Old_Status.all (K);
               end loop;
            end;
            Proxy.Status := New_Status;
         end;
      end if;
      Proxy.Last_SN := Last_SN;

      P.Missing_Changes_Update (Proxy, Last_SN);
      P.Lost_Changes_Update (Proxy, First_SN);

      --  T2: HEARTBEAT.FinalFlag NOT_SET -> must_send_ack; else only
      --  when LivelinessFlag NOT_SET -> may_send_ack (and ack only if
      --  there is something missing).
      if not Final then
         Ack := True;
      elsif P.Missing_Count (Proxy) > 0 then
         Ack := True;
      end if;
   end On_Heartbeat;

   procedure On_Data
     (Self      : in out Reader_State;
      Writer_Id :        Types.EntityId_T;
      SN        :        Types.SequenceNumber_T;
      Payload   :        Types.Octet_Buffer;
      Payload_Length : Natural;
      Handled   :    out Boolean)
   is
      Slot  : constant Natural := Find_Writer (Self, Writer_Id);
      Proxy : P.WriterProxy renames Self.Writers (Slot).Proxy;
   begin
      if Slot = 0 then
         Handled := False;
         return;
      end if;
      Handled := True;

      --  T8: add to reader cache + received_change_set.
      declare
         Change : History.Cache_Change_Ref;
      begin
         Self.Cache.Add_Change
           (Kind        => Types.ALIVE,
            Write_Time  => Types.TIME_ZERO,
            Instance    => 0,
            Data        => Payload,
            Data_Length => Payload_Length,
            Is_Key      => False,
            Change      => Change);
         --  The History assigns its own ring SN; record the writer SN
         --  on the returned change (writer SN kept separately).
         Change.all.SN := SN;
         Change.all.Guid_Prefix := Proxy.Remote_Writer_Guid.Guid_Prefix;
         Change.all.Entity_Id   := Proxy.Remote_Writer_Guid.Entity_Id;
      end;

      P.Received_Change_Set (Proxy, SN);
   end On_Data;

   procedure On_Gap
     (Self      : in out Reader_State;
      Writer_Id :        Types.EntityId_T;
      Gap_Start :        Types.SequenceNumber_T;
      Gap_Base  :        Types.SequenceNumber_T;
      Bitmap    :        Types.Unsigned_Long;
      Num_Bits  :        Types.Unsigned_Long)
   is
      Slot  : constant Natural := Find_Writer (Self, Writer_Id);
      Proxy : P.WriterProxy renames Self.Writers (Slot).Proxy;
      use all type Types.SequenceNumber_T;
      SN    : Types.SequenceNumber_T;
   begin
      if Slot = 0 then
         return;
      end if;

      --  T9 part 1: [gapStart .. gapList.base - 1] are irrelevant.
      SN := Gap_Start;
      while SN < Gap_Base loop
         P.Irrelevant_Change_Set (Proxy, SN);
         SN := SN + 1;
      end loop;

      --  T9 part 2: every SN in the bitmap is irrelevant.
      if Num_Bits > 0 then
         for Offset in 0 .. Natural (Num_Bits) - 1 loop
            declare
               Bit : constant Boolean :=
                 (Bitmap and 2**(31 - Offset)) /= 0;
               Gap_SN : constant Types.SequenceNumber_T :=
                 Gap_Base + Types.SequenceNumber_T (Offset);
            begin
               if Bit then
                  P.Irrelevant_Change_Set (Proxy, Gap_SN);
               end if;
            end;
         end loop;
      end if;
   end On_Gap;

   procedure Make_Acknack
     (Self      : in out Reader_State;
      Writer_Id :        Types.EntityId_T;
      Acknack   :    out M.Submessage_T;
      Ok        :    out Boolean)
   is
      use all type P.ChangeFromWriter_Status_Kind;
      use all type Types.SequenceNumber_T;
      Slot  : constant Natural := Find_Writer (Self, Writer_Id);
      Proxy : P.WriterProxy renames Self.Writers (Slot).Proxy;
      Missing_Base : Types.SequenceNumber_T;
      Bitmap  : Types.Unsigned_Long := 0;
      Num_Bits : Natural := 0;
      Count   : Natural := 0;
   begin
      if Slot = 0 then
         Ok := False;
         Acknack := (Kind => M.KIND_PAD, others => <>);
         return;
      end if;

      --  T5: base = available_changes_max() + 1; set = missing SNs.
      Missing_Base := P.Available_Changes_Max (Proxy) + 1;

      declare
         SN : Types.SequenceNumber_T := Proxy.First_SN;
         Offset : Natural;
      begin
         while SN <= Proxy.Last_SN loop
            Offset := Natural (SN - Proxy.First_SN);
            if Proxy.Status.all (Offset) = P.MISSING
              and then SN >= Missing_Base
              and then SN - Missing_Base < 32
            then
               Bitmap := Bitmap or 2**Natural (31 - (SN - Missing_Base));
               Num_Bits := Num_Bits + 1;
               Count := Count + 1;
            end if;
            SN := SN + 1;
         end loop;
      end;

      Acknack := (Kind => M.KIND_ACKNACK, others => <>);
      Acknack.Endianness := CDR.Little_Endian;
      Acknack.Reader_Id  := Self.Guid.Entity_Id;
      Acknack.Writer_Id  := Writer_Id;
      Acknack.Reader_SN_State :=
        (Bitmap_Base => Missing_Base,
         Num_Bits    => Types.Unsigned_Long (Num_Bits),
         Bitmap      => Bitmap);
      Acknack.Count := 0;
      Acknack.Final := Count = 0;  --  final when nothing is missing

      Ok := True;
   end Make_Acknack;

   function Writer_Count (Self : Reader_State) return Natural is
   begin
      return Self.Writer_Count;
   end Writer_Count;

end RTPS.StatefulReader;
------------------------------------------------------------------------------
--  RTPS.StatefulReader -- Reliable StatefulReader protocol machine
--  (clause 8.4.10.3, 8.4.12.2)
--
--  Maintains per-matched-writer state (WriterProxy) and drives the
--  transitions T2/T5/T7/T8/T9 of Figure 8.24:
--    * HEARTBEAT handling: missing_changes_update + lost_changes_update
--      (T7), then ACKNACK after heartbeatResponseDelay (T5)
--    * DATA: add to reader cache + received_change_set (T8)
--    * GAP: irrelevant_change_set for the range (T9)
------------------------------------------------------------------------------

with RTPS.Types;
with RTPS.History;
with RTPS.Proto;
with RTPS.Messages;
with RTPS.Transports;

package RTPS.StatefulReader is

   package T  renames RTPS.Types;
   package M  renames RTPS.Messages;
   package P  renames RTPS.Proto;

   Max_Matched_Writers : constant := 64;

   type Reader_State is private;

   Not_Open       : exception;
   Unknown_Writer : exception;

   ---------------------------------------------------------------------
   --  Setup (8.4.10.1.2 / 8.4.10.3.1)
   ---------------------------------------------------------------------

   procedure New_Reader
     (Self          : in out Reader_State;
      Reader_Guid   :        Types.GUID_T;
      Cache         :        History.History_Cache_Ref;
      Heartbeat_Response_Delay : Duration :=
        RTPS.Proto.Default_Heartbeat_Response_Delay);

   ---------------------------------------------------------------------
   --  Match management (8.4.10.3.2 / 8.4.10.3.3)
   ---------------------------------------------------------------------

   procedure Matched_Writer_Add
     (Self      : in out Reader_State;
      Writer_Guid :      Types.GUID_T;
      Unicast_Port :   Types.Unsigned_Long := 0);

   procedure Matched_Writer_Remove
     (Self : in out Reader_State; Writer_Guid : Types.GUID_T);

   ---------------------------------------------------------------------
   --  Submessage handlers (T7, T8, T9, T5)
   ---------------------------------------------------------------------

   --  8.4.12.2.7 (T7): process a HEARTBEAT.  Updates the writer proxy
   --  window (missing/lost) and, when the HEARTBEAT demands a response
   --  (FinalFlag NOT_SET) or changes are missing, returns Ack = True
   --  meaning: send an ACKNACK (after heartbeatResponseDelay).
   procedure On_Heartbeat
     (Self      : in out Reader_State;
      Writer_Id :        Types.EntityId_T;
      First_SN  :        Types.SequenceNumber_T;
      Last_SN   :        Types.SequenceNumber_T;
      Final     :        Boolean;
      Liveliness:        Boolean;
      Ack       :    out Boolean);

   --  8.4.12.2.8 (T8): process a DATA submessage.  Adds the change to
   --  the reader cache and marks it received on the writer proxy.
   procedure On_Data
     (Self      : in out Reader_State;
      Writer_Id :        Types.EntityId_T;
      SN        :        Types.SequenceNumber_T;
      Payload   :        Types.Octet_Buffer;
      Payload_Length : Natural;
      Handled   :    out Boolean);
   --  Handled is False when the writer is unknown (drop silently).

   --  8.4.12.2.9 (T9): process a GAP submessage: mark the range
   --  [Gap_Start .. Gap_List base-1] and every SN in the bitmap as
   --  irrelevant (received, not relevant).
   procedure On_Gap
     (Self      : in out Reader_State;
      Writer_Id :        Types.EntityId_T;
      Gap_Start :        Types.SequenceNumber_T;
      Gap_Base  :        Types.SequenceNumber_T;
      Bitmap    :        Types.Unsigned_Long;
      Num_Bits  :        Types.Unsigned_Long);

   --  8.4.12.2.5 (T5): build the ACKNACK submessage from the writer
   --  proxy state (base = available_max + 1; bitmap over missing SNs).
   procedure Make_Acknack
     (Self      : in out Reader_State;
      Writer_Id :        Types.EntityId_T;
      Acknack   :    out M.Submessage_T;
      Ok        :    out Boolean);

   --  Number of matched writers.
   function Writer_Count (Self : Reader_State) return Natural;

private

   type Writer_Slot is record
      Used  : Boolean := False;
      Proxy : P.WriterProxy;
   end record;

   type Writer_Slots is array (1 .. Max_Matched_Writers) of Writer_Slot;

   type Reader_State is record
      Guid             : Types.GUID_T := Types.GUID_UNKNOWN;
      Cache            : History.History_Cache_Ref := null;
      HB_Response_Delay: Duration :=
        RTPS.Proto.Default_Heartbeat_Response_Delay;
      Writers          : Writer_Slots;
      Writer_Count     : Natural := 0;
   end record;

end RTPS.StatefulReader;
------------------------------------------------------------------------------
--  RTPS.Proto -- types shared by the StatefulWriter / StatefulReader
--  protocol machines (clauses 8.4.7.5, 8.4.7.6, 8.4.10.4, 8.4.12.3)
--
--  ChangeForReader / ChangeFromWriter status enumerations, the Reader /
--  Writer proxy types, and the protocol tuning parameters.
------------------------------------------------------------------------------

with RTPS.Types;
with RTPS.History;
with Ada.Real_Time;

package RTPS.Proto is

   use all type Types.SequenceNumber_T;

   package Types renames RTPS.Types;
   package RT  renames Ada.Real_Time;

   ---------------------------------------------------------------------
   --  Timing defaults (8.4.10.1.1, 8.4.15)
   ---------------------------------------------------------------------

   Default_Heartbeat_Period : constant Duration := 3.0;
   --  W::heartbeatPeriod, HEARTBEAT periodic announce (8.4.9.2.7).

   Default_Nack_Response_Delay : constant Duration := 0.0;
   --  W::nackResponseDelay (8.4.9.2.11).

   Default_Heartbeat_Response_Delay : constant Duration := 0.5;
   --  R::heartbeatResponseDelay = 500 ms (8.4.10.1.1).

   ---------------------------------------------------------------------
   --  ReaderProxy (8.4.7.5) -- state a StatefulWriter keeps per matched
   --  reader, plus the ChangeForReader status (8.4.7.6).
   ---------------------------------------------------------------------

   type ChangeForReader_Status_Kind is
     (UNSENT, UNACKNOWLEDGED, REQUESTED, ACKNOWLEDGED, UNDERWAY);

   type Change_Kind is record
      SN          : Types.SequenceNumber_T := 1;
      Is_Relevant : Boolean := True;
      Status      : ChangeForReader_Status_Kind := UNSENT;
   end record;

   type CFR_Status_Array is array (Natural range <>) of
     ChangeForReader_Status_Kind;
   type CFR_Status_Buffer is access CFR_Status_Array;

   --  Per-reader protocol state window over sequence numbers.  The
   --  window is identified by First_SN .. Last_SN; a parallel status
   --  array covers the window (ChangeForReader).
   type ReaderProxy is record
      Remote_Reader_Guid : Types.GUID_T := Types.GUID_UNKNOWN;
      Expects_Inline_Qos : Boolean      := False;
      Is_Active          : Boolean      := True;
      --  Sequence number window [First_SN .. Last_SN].
      First_SN           : Types.SequenceNumber_T := 1;
      Last_SN            : Types.SequenceNumber_T := 0;
      Status             : CFR_Status_Buffer := null;
      --  Status window state (for iteration):
      Unsent_Size        : Natural := 0;
      Acked_Up_To        : Types.SequenceNumber_T := 0;
      --  Set of requested (NACKed) sequence numbers below:
      Req_Count          : Natural := 0;
      Req_Min_SN         : Types.SequenceNumber_T := 0;
      Highest_Req_SN     : Types.SequenceNumber_T := 0;
      --  Locators for sending to this reader:
      Unicast_Port       : Types.Unsigned_Long := 0;
      Multicast_Port     : Types.Unsigned_Long := 0;
   end record;

   --  ReaderProxy operations (Table 8.56) on the SN window.
   procedure Acked_Changes_Set
     (P : in out ReaderProxy; Committed_SN : Types.SequenceNumber_T)
     with Pre => Committed_SN >= 1;
   --  8.4.7.5.2: all changes with SN <= committed become ACKNOWLEDGED.

   procedure Requested_Changes_Set
     (P : in out ReaderProxy; SN : Types.SequenceNumber_T)
     with Pre => SN >= 1;
   --  8.4.7.5.6: mark SN as REQUESTED (from ACKNACK.readerSNState).

   function Next_Requested_SN (P : ReaderProxy) return Types.SequenceNumber_T;
   --  8.4.7.5.3: lowest SN with status REQUESTED, 0 if none.

   function Next_Unsent_SN (P : ReaderProxy) return Types.SequenceNumber_T;
   --  8.4.7.5.4: lowest SN with status UNSENT, 0 if none.

   function Unacked_Count (P : ReaderProxy) return Natural;
   --  8.4.7.5.8: number of changes with status UNACKNOWLEDGED.

   function Requested_Count (P : ReaderProxy) return Natural;

   ---------------------------------------------------------------------
   --  WriterProxy (8.4.10.4) -- state a StatefulReader keeps per
   --  matched writer, with the ChangeFromWriter status (8.4.12.3).
   ---------------------------------------------------------------------

   type ChangeFromWriter_Status_Kind is
     (LOST, MISSING, RECEIVED, UNKNOWN);

   type CFW_Array is array (Natural range <>) of
     ChangeFromWriter_Status_Kind;
   type CFW_Buffer is access CFW_Array;

   type WriterProxy is record
      Remote_Writer_Guid : Types.GUID_T := Types.GUID_UNKNOWN;
      --  Sequence number window [First_SN .. Last_SN].
      First_SN           : Types.SequenceNumber_T := 1;
      Last_SN            : Types.SequenceNumber_T := 0;
      --  Status for Last_SN - First_SN + 1 window entries.
      Status             : CFW_Buffer := null;
      --  Highest SN that is RECEIVED or LOST (available_changes_max).
      Available_Max      : Types.SequenceNumber_T := 0;
      --  Reader timing (8.4.10.1.1):
      Heartbeat_Response_Delay : Duration := Default_Heartbeat_Response_Delay;
      --  Locators for sending ACKNACK to this writer:
      Unicast_Port       : Types.Unsigned_Long := 0;
   end record;

   --  WriterProxy operations (Table 8.68).
   procedure Missing_Changes_Update
     (P : in out WriterProxy; Last_Available_SN : Types.SequenceNumber_T)
     with Pre => Last_Available_SN >= 1;
   --  8.4.10.4.6: UNKNOWN changes with SN <= last_available become
   --  MISSING (a HEARTBEAT announced them).

   procedure Lost_Changes_Update
     (P : in out WriterProxy; First_Available_SN : Types.SequenceNumber_T)
     with Pre => First_Available_SN >= 1;
   --  8.4.10.4.4: UNKNOWN/MISSING changes with SN < first_available
   --  become LOST (no longer in the writer's history).

   procedure Received_Change_Set
     (P : in out WriterProxy; SN : Types.SequenceNumber_T)
     with Pre => SN >= 1;
   --  8.4.10.4.7: SN becomes RECEIVED.

   procedure Irrelevant_Change_Set
     (P : in out WriterProxy; SN : Types.SequenceNumber_T)
     with Pre => SN >= 1;
   --  8.4.10.4.3: SN becomes RECEIVED with is_relevant = FALSE.

   function Available_Changes_Max (P : WriterProxy)
     return Types.SequenceNumber_T;
   --  8.4.10.4.2: max SN that is RECEIVED or LOST (0 if none).

   function Missing_Count (P : WriterProxy) return Natural;
   --  8.4.10.4.5: number of changes with status MISSING.

   ---------------------------------------------------------------------
   --  Matched-endpoint lookup helpers
   ---------------------------------------------------------------------

   function GUID_Equal (L, R : Types.GUID_T) return Boolean;

end RTPS.Proto;
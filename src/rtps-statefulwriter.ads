------------------------------------------------------------------------------
--  RTPS.StatefulWriter -- Reliable StatefulWriter protocol machine
--  (clause 8.4.7.4, 8.4.9.2)
--
--  Maintains per-matched-reader state (ReaderProxy) and drives the
--  transitions T2/T4/T7/T8/T12 of Figure 8.19:
--    * push mode: send DATA/GAP for unsent changes (T4, T12)
--    * periodic HEARTBEAT with FinalFlag NOT_SET (T7)
--    * ACKNACK handling: acked_changes_set on the writer, then
--      requested_changes_set per reader proxy (T8/T10)
--
--  Transport is abstracted through an access-to-Transport, so the same
--  machine works over UDPv4 or any other PSM realization.
------------------------------------------------------------------------------

with RTPS.Types;
with RTPS.History;
with RTPS.Proto;
with RTPS.Messages;
with RTPS.Transports;

package RTPS.StatefulWriter is

   package T  renames RTPS.Types;
   package P  renames RTPS.Proto;
   package M  renames RTPS.Messages;
   use all type T.GUID_T;

   Max_Matched_Readers : constant := 64;

   type Writer_State is private;

   Not_Open     : exception;
   Unknown_Reader : exception;

   ---------------------------------------------------------------------
   --  Setup (8.4.7.1.2 / 8.4.7.4.1)
   ---------------------------------------------------------------------

   procedure New_Writer
     (Self          : in out Writer_State;
      Writer_Guid   :        Types.GUID_T;
      Cache         :        History.History_Cache_Ref;
      Heartbeat_Period :     Duration := RTPS.Proto.Default_Heartbeat_Period);
   --  8.4.7.4.1: matched_readers := <empty>.

   procedure Open
     (Self : in out Writer_State; To_Transport : Transports.Transport_Ref);
   --  Attach the transport used for all outgoing submessages.

   ---------------------------------------------------------------------
   --  Match management (8.4.7.4.3 / 8.4.7.4.4)
   ---------------------------------------------------------------------

   type Match_Info is record
      Remote_Reader_Guid : Types.GUID_T := Types.GUID_UNKNOWN;
      Expects_Inline_Qos : Boolean      := False;
      Unicast_Port       : Types.Unsigned_Long := 0;
      Multicast_Port     : Types.Unsigned_Long := 0;
   end record;

   procedure Matched_Reader_Add
     (Self      : in out Writer_State;
      Proxy     :        Match_Info;
      Window_First :    Types.SequenceNumber_T;
      Window_Last  :    Types.SequenceNumber_T);
   --  8.4.9.2.1 (T1): create the ReaderProxy and add it.  The status
   --  window covers [Window_First .. Window_Last]: SNs below the
   --  history minimum are ACKNOWLEDGED (already gone), the rest UNSENT.

   procedure Matched_Reader_Remove
     (Self  : in out Writer_State;
      Guid  :        Types.GUID_T) with Pre => Guid /= Types.GUID_UNKNOWN;
   --  8.4.9.2.16 (T6 / T16).

   ---------------------------------------------------------------------
   --  Protocol operations
   ---------------------------------------------------------------------

   --  8.4.7.4.2 is_acked_by_all: True iff every matched reader has
   --  ACKNOWLEDGED the change (relevant ones only).
   function Is_Acked_By_All
     (Self : Writer_State; SN : Types.SequenceNumber_T) return Boolean;

   --  8.4.9.2.4 (T4/T12): send DATA (or GAP for irrelevant SNs) for
   --  one unsent/requested change to the given reader proxy.  No-ops
   --  when the reader has nothing to send.
   procedure Push_Next
     (Self  : in out Writer_State;
      Guid  :        Types.GUID_T;
      For_Request : Boolean := False);

   --  8.4.9.2.7 (T7): send a periodic HEARTBEAT (FinalFlag NOT_SET) to
   --  all matched readers.
   procedure Send_Heartbeat (Self : in out Writer_State);

   --  8.4.9.2.8 (T8/T10): process a received ACKNACK.  Returns True if
   --  the reader is known; performs acked_changes_set on the writer
   --  level and requested_changes_set on the matching ReaderProxy.
   procedure On_Acknack
     (Self      : in out Writer_State;
      Reader_Id :        Types.EntityId_T;
      Writer_Id :        Types.EntityId_T;
      Base_SN   :        Types.SequenceNumber_T;
      Bitmap    :        Types.Unsigned_Long;
      Num_Bits  :        Types.Unsigned_Long;
      Final     :        Boolean;
      Reply     :    out Boolean);
   --  Reply is True when the ACKNACK requests data (a repair is due).

   --  8.4.7.4.2 / T14: register a new change with all matched readers
   --  (adds to each proxy's window as UNSENT/UNACKNOWLEDGED).
   procedure On_New_Change (Self : in out Writer_State; SN : Types.SequenceNumber_T);

   --  True when the writer has matched readers and needs to push
   --  (unsent/requested changes exist for any of them).
   function Has_Pending (Self : Writer_State) return Boolean;

   Match_Count : exception;

   --  Number of matched readers currently registered.
   function Reader_Count (Self : Writer_State) return Natural;

   type Reader_Iterator is private;

   --  Enumerate matched reader GUIDs: call First, then Next until
   --  Done.  Invalid (GUID_UNKNOWN) when Done.
   procedure First_Reader
     (Self : Writer_State; It : out Reader_Iterator;
      Guid : out Types.GUID_T);
   procedure Next_Reader
     (Self : Writer_State; It : in out Reader_Iterator;
      Guid : out Types.GUID_T);

   function Reader_Guid_Of_It (It : Reader_Iterator) return Types.GUID_T;

   --  Access the transport for sending (null if not open).
   function Transport (Self : Writer_State) return Transports.Transport_Ref;

private

   type Reader_Iterator is new Natural range 1 .. Max_Matched_Readers;
   --  Index into the Readers table; 0 = before first.

   type Reader_Slot is record
      Used  : Boolean := False;
      Proxy : P.ReaderProxy;
   end record;

   type Reader_Slots is array (1 .. Max_Matched_Readers) of Reader_Slot;

   type Writer_State is record
      Guid             : Types.GUID_T       := Types.GUID_UNKNOWN;
      Cache            : History.History_Cache_Ref := null;
      Heartbeat_Period : Duration := RTPS.Proto.Default_Heartbeat_Period;
      Readers          : Reader_Slots;
      Reader_Count     : Natural := 0;
      Transport        : Transports.Transport_Ref := null;
   end record;

end RTPS.StatefulWriter;
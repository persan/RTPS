------------------------------------------------------------------------------
--  RTPS.Discovery.SPDP -- Simple Participant Discovery Protocol
--  (8.5.3)
--
--  For each Participant the SPDP creates two built-in endpoints
--  (8.5.3.1):
--    * SPDPbuiltinParticipantWriter -- a Best-Effort StatelessWriter
--      whose HistoryCache holds a single SPDPdiscoveredParticipantData
--      object; it is sent periodically to a pre-configured locator
--      list (9.6.1.4: multicast 239.255.0.1 : PB+DG*domainId+d0 and
--      the well-known unicast ports).
--    * SPDPbuiltinParticipantReader -- collects the announcements of
--      remote participants; entries expire after leaseDuration
--      (8.5.3.3.2).
--
--  The wire message is a Header + INFO_TS + DATA submessage whose
--  SerializedData is the participant data as a ParameterList
--  (9.6.2.2), sent best-effort (no HEARTBEAT/ACKNACK for SPDP).
------------------------------------------------------------------------------

with RTPS.Discovery.Data;
with RTPS.Transports;
with RTPS.Types;

package RTPS.Discovery.SPDP is

   package T renames RTPS.Types;

   Max_Remote_Participants : constant := 64;

   type Participant_State is limited private;

   ---------------------------------------------------------------------
   --  Setup
   ---------------------------------------------------------------------

   procedure New_Participant
     (Self           : in out Participant_State;
      Guid_Prefix    :        T.GuidPrefix_T;
      Domain_Id      :        T.Unsigned_Long;
      Participant_Id :        T.Unsigned_Long;
      Vendor_Id      :        T.VendorId_T := (16#42#, 16#13#);
      Lease_Duration :        Duration := 100.0;
      Resend_Period  :        Duration := 30.0);
   --  Vendor_Id default: (0x42, 0x13) is a vendor-id placeholder in
   --  the implementation-specific space; override for interop testing.
   --  Resend_Period default = 9.6.1.4.2 (30 s); the tests use seconds
   --  scale periods.

   procedure Open
     (Self : in out Participant_State; To : Transports.Transport_Ref);
   --  Attach the transport used for both announcing and listening.

   ---------------------------------------------------------------------
   --  Announcing (SPDPbuiltinParticipantWriter, 8.5.3.3.1)
   ---------------------------------------------------------------------

   procedure Announce (Self : in out Participant_State);
   --  Serialize the local SPDPdiscoveredParticipantData and send it to
   --  the well-known multicast locator and, when configured, the
   --  unicast locators of this domain (Table 8.76 / Table 9.8).

   function Needs_Announce
     (Self : Participant_State; Now : Duration) return Boolean;
   --  True when Resend_Period has elapsed since the last announcement
   --  (StatelessWriter::unsent_changes_reset, 8.5.3.1).

   ---------------------------------------------------------------------
   --  Listening (SPDPbuiltinParticipantReader, 8.5.3.3.2)
   ---------------------------------------------------------------------

   type Participant_Guid_Array is
     array (1 .. Max_Remote_Participants) of T.GUID_T;

   procedure On_Data
     (Self     : in out Participant_State;
      Data     :        T.Octet_Array;
      Src_Addr :        T.Octet_Array16;   --  UDPv4 source address octets
      Src_Port :        T.Unsigned_Long;
      Fresh    :    out Boolean;
      Guid     :    out T.GUID_T);
   --  Process a received SPDP announcement (DATA payload holding the
   --  ParameterList).  Fresh is True when this participant was not
   --  known before (8.5.5.1: the caller then configures the SEDP
   --  endpoints and may answer with an extra announcement).

   procedure Expire_Stale
     (Self : in out Participant_State; Now : Duration);
   --  Remove participants whose lease has expired (8.5.3.3.2: "Stale
   --  entries are removed").  Lease is renewed on every announcement.

   function Remote_Count (Self : Participant_State) return Natural;

   --  Iterate the discovered participants (array + count).
   procedure Remotes
     (Self  : Participant_State;
      Guids :    out Participant_Guid_Array;
      Count :    out Natural);

   --  Metatraffic port of a discovered participant (from its
   --  PID_METATRAFFIC_UNICAST_LOCATOR); 0 when unknown.
   function Remote_Metatraffic_Port
     (Self : Participant_State; Guid : T.GUID_T) return T.Unsigned_Long;

   ---------------------------------------------------------------------
   --  Serialization used by the SPDP announcement (also exercised by
   --  the test suite directly)
   ---------------------------------------------------------------------

   function Build_Announcement
     (Self : Participant_State; Length : out Natural)
      return T.Octet_Buffer;
   --  Full RTPS message: Header + INFO_TS + DATA(SerializedData =
   --  ParameterList of the local participant data).  Caller frees.

   procedure Parse_Announcement
     (Msg  :        T.Octet_Array;
      Guid :    out T.GUID_T;
      PD   :    out Data.Participant_Data;
      Ok   :    out Boolean);
   --  Parse a DATA payload back into (guid, data).  Ok is False for
   --  malformed input.

private

   type Remote_Slot is record
      Used     : Boolean := False;
      Guid     : T.GUID_T := T.GUID_UNKNOWN;
      Meta_Port : T.Unsigned_Long := 0;
      Lease    : Duration := 0.0;
      Last_Seen : Duration := 0.0;
   end record;

   type Remote_Slots is
     array (1 .. Max_Remote_Participants) of Remote_Slot;

   type Participant_State is record
      Prefix         : T.GuidPrefix_T := T.GUIDPREFIX_UNKNOWN;
      Domain_Id      : T.Unsigned_Long := 0;
      Participant_Id : T.Unsigned_Long := 0;
      Vendor_Id      : T.VendorId_T := (16#42#, 16#13#);
      Lease_Duration : Duration := 100.0;
      Resend_Period  : Duration := 30.0;
      Transport      : Transports.Transport_Ref := null;
      Remotes        : Remote_Slots;
      Remote_Count   : Natural := 0;
      Last_Announce  : Duration := 0.0;
      Have_Announced : Boolean := False;
      Clock_Now      : Duration := 0.0;
      --  Applications drive time by passing Now to Needs_Announce /
      --  Expire_Stale; Clock_Now tracks the latest value seen.
   end record;

end RTPS.Discovery.SPDP;
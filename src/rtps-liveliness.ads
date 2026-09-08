------------------------------------------------------------------------------
--  RTPS.Liveliness -- Writer Liveliness Protocol (8.4.13)
--
--  Asserts the liveliness of the Writers contained by a Participant
--  through the general-purpose built-in endpoints
--  BuiltinParticipantMessageWriter / BuiltinParticipantMessageReader
--  (8.4.13.2, EntityIds ENTITYID_P2P_BUILTIN_PARTICIPANT_MESSAGE_*).
--
--  Both endpoints are RELIABLE / TRANSIENT_LOCAL / KEEP_LAST(1)
--  (8.4.13.3) and are realized here with the reliable
--  StatefulWriter / StatefulReader protocol machines of 8.4.9.2 /
--  8.4.12.2.
--
--  The logical content is ParticipantMessageData (9.6.2.1):
--    struct { GuidPrefix_t participantGuidPrefix;
--             OctetArray4   kind;
--             OctetSeq      data; }
--  with reserved kinds (9.6.2.1):
--    PARTICIPANT_MESSAGE_DATA_KIND_UNKNOWN                  (0,0,0,0)
--    PARTICIPANT_MESSAGE_DATA_KIND_AUTOMATIC_LIVELINESS_UPDATE
--                                                           (0,0,0,1)
--    PARTICIPANT_MESSAGE_DATA_KIND_MANUAL_LIVELINESS_UPDATE (0,0,0,2)
--
--  Per 8.4.13.5 the liveliness of a subset of Writers is asserted by
--  writing a sample: AUTOMATIC liveliness Writers are covered by the
--  kind (0,0,0,1) instance and MANUAL_BY_PARTICIPANT Writers by the
--  kind (0,0,0,2) instance, each written at a rate faster than the
--  smallest lease duration among the Writers sharing that QoS.  The
--  instance key is <participantGuidPrefix, kind>.
--
--  MANUAL_BY_TOPIC liveliness is NOT handled by this protocol
--  (8.4.13.5: asserted by the individual Writer, e.g. by its own
--  periodic DATA / HEARTBEAT traffic).
------------------------------------------------------------------------------

with RTPS.History;
with RTPS.Messages;
with RTPS.StatefulReader;
with RTPS.StatefulWriter;
with RTPS.Types;
with RTPS.Transports;

package RTPS.Liveliness is

   package T renames RTPS.Types;

   ---------------------------------------------------------------------
   --  ParticipantMessageData kinds (9.6.2.1)
   ---------------------------------------------------------------------

   type Message_Kind is array (1 .. 4) of T.Octet;

   PMDK_UNKNOWN : constant Message_Kind := (0, 0, 0, 0);
   PMDK_AUTOMATIC_LIVELINESS_UPDATE : constant Message_Kind :=
     (0, 0, 0, 1);
   PMDK_MANUAL_LIVELINESS_UPDATE : constant Message_Kind :=
     (0, 0, 0, 2);
   --  kind.value[0] & 0x80 = 0: reserved by RTPS; = 1: vendor specific.

   ---------------------------------------------------------------------
   --  Liveliness QoS kinds (8.4.13.5; the DDS manual-by-topic case is
   --  out of scope of this protocol)
   ---------------------------------------------------------------------

   type Liveliness_Kind is (Liveliness_Automatic,
                            Liveliness_Manual_By_Participant);

   ---------------------------------------------------------------------
   --  Writer side (BuiltinParticipantMessageWriter)
   ---------------------------------------------------------------------

   type Writer is limited private;

   procedure New_Writer
     (Self        : in out Writer;
      Participant  :        T.GuidPrefix_T;
      Cache        :        RTPS.History.History_Cache_Ref);
   --  The HistoryCache holds the ParticipantMessageData instances
   --  (one per kind; KEEP_LAST(1) per instance).

   procedure Open
     (Self : in out Writer; To : Transports.Transport_Ref);

   --  Match with the remote BuiltinParticipantMessageReader after the
   --  SPDP discovered the participant (8.4.13.1: the presence of the
   --  built-in endpoints is assumed).
   procedure Matched_Reader_Add
     (Self       : in out Writer;
      Reader_Guid :        T.GUID_T;
      Meta_Port   :        T.Unsigned_Long);
   procedure Matched_Reader_Remove
     (Self : in out Writer; Reader_Guid : T.GUID_T);

   --  8.4.13.5: assert liveliness of the Writers with the given kind.
   --  Writes (or replaces, KEEP_LAST(1)) the sample
   --  <participantGuidPrefix, kind> in the built-in HistoryCache and
   --  registers it with all matched readers.  For
   --  Liveliness_Manual_By_Participant the SPDP
   --  manualLivelinessCount is incremented as well (Table 8.73) --
   --  call Bump_Manual_Count for that.
   procedure Assert
     (Self : in out Writer;
      Kind :        Liveliness_Kind;
      Data :        T.Octet_Array := (1 .. 0 => 0));

   --  Application-driven periodic pump: pushes pending changes to all
   --  matched readers and sends a HEARTBEAT (both SEDP-style, T4/T12
   --  and T7 of 8.4.9.2).
   procedure Push_Pending (Self : in out Writer);
   procedure Send_Heartbeat (Self : in out Writer);

   --  Process a received ACKNACK for the built-in writer (T8/T10).
   --  Repair is True when the ACKNACK requests data.
   procedure On_Acknack
     (Self      : in out Writer;
      Reader_Id :        T.EntityId_T;
      Base_SN   :        T.SequenceNumber_T;
      Bitmap    :        T.Unsigned_Long;
      Num_Bits  :        T.Unsigned_Long;
      Final     :        Boolean;
      Repair    :    out Boolean);

   function Reader_Count (Self : Writer) return Natural;
   function Has_Pending (Self : Writer) return Boolean;

   ---------------------------------------------------------------------
   --  Reader side (BuiltinParticipantMessageReader)
   ---------------------------------------------------------------------

   type Reader is limited private;

   type Lease_Array is array (1 .. 2) of Duration;
   --  Index 1: automatic-liveliness instance; index 2:
   --  manual-by-participant instance.

   procedure New_Reader
     (Self        : in out Reader;
      Participant  :        T.GuidPrefix_T;
      Cache        :        RTPS.History.History_Cache_Ref);
   --  The reader's HistoryCache collects the ParticipantMessageData
   --  samples of the remote participants; the key of each instance is
   --  <participantGuidPrefix, kind> (8.4.13.5).

   procedure Matched_Writer_Add
     (Self        : in out Reader;
      Writer_Guid :        T.GUID_T;
      Meta_Port   :        T.Unsigned_Long := 0);
   procedure Matched_Writer_Remove
     (Self : in out Reader; Writer_Guid : T.GUID_T);

   --  Deliver a received DATA for the built-in reader (T8): adds the
   --  sample to the reader cache and renews the lease of the
   --  corresponding instance.
   procedure On_Data
     (Self           : in out Reader;
      Writer_Id      :        T.EntityId_T;
      SN             :        T.SequenceNumber_T;
      Payload        :        T.Octet_Buffer;
      Payload_Length :        Natural;
      Handled        :    out Boolean);

   --  Deliver a received HEARTBEAT for the built-in reader (T7).
   --  Ack_Request is True when an ACKNACK is due.
   procedure On_Heartbeat
     (Self        : in out Reader;
      Writer_Id   :        T.EntityId_T;
      First_SN    :        T.SequenceNumber_T;
      Last_SN     :        T.SequenceNumber_T;
      Final       :        Boolean;
      Ack_Request :    out Boolean);

   --  Build the ACKNACK answering a HEARTBEAT (T5).
   procedure Make_Acknack
     (Self     : in out Reader;
      Writer_Id :       T.EntityId_T;
      Acknack   :    out RTPS.Messages.Submessage_T;
      Ok        :    out Boolean);

   ---------------------------------------------------------------------
   --  Lease bookkeeping (the DDS-visible effect of the protocol)
   ---------------------------------------------------------------------

   procedure Set_Lease
     (Self     : in out Reader;
      Kind     :        Liveliness_Kind;
      Lease    :        Duration);
   --  The smallest lease duration among the local Writers sharing the
   --  QoS (8.4.13.5: samples must be written faster than this).

   --  True when the lease of the instance expired: the Writers of the
   --  remote participant sharing that QoS are no longer ALIVE.
   function Lease_Expired
     (Self : Reader; Kind : Liveliness_Kind; Now : Duration)
      return Boolean;

   --  Time of the last received assertion of the instance; 0.0 when
   --  never received.
   function Last_Assertion
     (Self : Reader; Kind : Liveliness_Kind) return Duration;

   ---------------------------------------------------------------------
   --  Application-driven clock (mirrors the SPDP design: the
   --  application owns the time source and passes Now in)
   ---------------------------------------------------------------------

   procedure Set_Now (Self : in out Reader; Now : Duration);
   --  Advances the reader's clock; On_Data stamps the received
   --  assertions with the latest value seen.

   ---------------------------------------------------------------------
   --  ParticipantMessageData wire mapping (9.6.2.1)
   ---------------------------------------------------------------------

   function Encode
     (Participant : T.GuidPrefix_T;
      Kind        : Message_Kind;
      Data        : T.Octet_Array) return T.Octet_Buffer;
   --  CDR wire form: participantGuidPrefix (12 octets) + kind (4) +
   --  data.length (4) + data.value (padded to 4).  Caller frees.

   procedure Decode
     (Wire        :        T.Octet_Array;
      Participant :    out T.GuidPrefix_T;
      Kind        :    out Message_Kind;
      Data        :    out T.Octet_Buffer;
      Data_Length :    out Natural;
      Ok          :    out Boolean);
   --  Inverse of Encode; Ok is False on malformed input.  Data is a
   --  fresh buffer owned by the caller.

private

   type Writer is record
      Participant : T.GuidPrefix_T := T.GUIDPREFIX_UNKNOWN;
      Cache       : RTPS.History.History_Cache_Ref := null;
      Inner       : RTPS.StatefulWriter.Writer_State;
   end record;

   type Reader is record
      Participant : T.GuidPrefix_T := T.GUIDPREFIX_UNKNOWN;
      Cache       : RTPS.History.History_Cache_Ref := null;
      Inner       : RTPS.StatefulReader.Reader_State;
      Leases      : Lease_Array := (others => 100.0);
      Last_Seen   : Lease_Array := (others => 0.0);
      Clock_Now   : Duration := 0.0;
   end record;

end RTPS.Liveliness;
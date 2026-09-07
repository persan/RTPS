------------------------------------------------------------------------------
--  RTPS.Types
--
--  Platform Independent Model (PIM) types of the DDS Interoperability
--  Wire Protocol (RTPS), version 2.2 -- OMG document formal/2014-09-01.
--
--  Corresponds to clause 8.2.1.2 (Table 8.2) and the PSM type mappings of
--  clause 9.3.2 (Table 9.4).  Submessage elements (8.3.5) are in
--  RTPS.Messages; entities (8.2) in RTPS.Entities.
------------------------------------------------------------------------------

package RTPS.Types is

   ---------------------------------------------------------------------
   --  Basic scalar types (clause 9.2, CDR mapping)
   ---------------------------------------------------------------------

   type Octet is mod 2**8;
   for Octet'Size use 8;

   type Octet_Array is array (Positive range <>) of Octet;
   type Octet_Buffer is access all Octet_Array;

   type Short  is range -2**15 .. 2**15 - 1;
   for Short'Size use 16;

   type Unsigned_Short is mod 2**16;
   for Unsigned_Short'Size use 16;

   type Long is range -2**31 .. 2**31 - 1;
   for Long'Size use 32;

   type Unsigned_Long is mod 2**32;
   for Unsigned_Long'Size use 32;

   type Long_Long is range -2**63 .. 2**63 - 1;
   for Long_Long'Size use 64;

   type Unsigned_Long_Long is mod 2**64;
   for Unsigned_Long_Long'Size use 64;

   ---------------------------------------------------------------------
   --  GuidPrefix_t, EntityId_t, GUID_t (clause 9.3.1)
   ---------------------------------------------------------------------

   --  9.3.1.1: type used to hold the prefix of the globally-unique
   --  RTPS-entity identifiers.  Must be possible to represent using
   --  12 octets.  Reserved value: GUIDPREFIX_UNKNOWN.
   type GuidPrefix_T is array (1 .. 12) of Octet;
   GUIDPREFIX_UNKNOWN : constant GuidPrefix_T := (others => 0);

   --  9.3.1.2: type used to hold the suffix part of the globally-unique
   --  RTPS-entity identifiers.  The EntityId_t uniquely identifies an
   --  Entity within a Participant.  Must be possible to represent using
   --  4 octets.  Reserved value: ENTITYID_UNKNOWN.
   type EntityId_T is array (1 .. 4) of Octet;
   ENTITYID_UNKNOWN : constant EntityId_T := (0, 0, 0, 0);

   --  9.3.1.5: struct GUID_t { GuidPrefix_t guidPrefix; EntityId_t entityId; }
   type GUID_T is record
      Guid_Prefix : GuidPrefix_T := GUIDPREFIX_UNKNOWN;
      Entity_Id   : EntityId_T   := ENTITYID_UNKNOWN;
   end record;
   GUID_UNKNOWN : constant GUID_T :=
     (Guid_Prefix => GUIDPREFIX_UNKNOWN, Entity_Id => ENTITYID_UNKNOWN);

   --  entityKey: first 3 octets of the EntityId_T (9.3.1.2)
   type EntityKey_T is array (1 .. 3) of Octet;

   function Entity_Key_Of (Id : EntityId_T) return EntityKey_T is
     (Id (1) & Id (2) & Id (3)) with Inline;
   --  The entityKey part of an EntityId.

   function Entity_Kind_Of (Id : EntityId_T) return Octet is (Id (4))
     with Inline;
   --  The entityKind octet (Table 9.1).

   --  Bits 7..6 of entityKind (9.3.1.2): entity scope.
   ENTITYKIND_BUILTIN_MASK         : constant Octet := 16#C0#;
   ENTITYKIND_USER_DEFINED_MASK    : constant Octet := 16#00#;
   ENTITYKIND_VENDOR_SPECIFIC_MASK : constant Octet := 16#40#;
   --  Bits 5..0 of entityKind (9.3.1.2): entity kind (Table 9.1).
   ENTITYKIND_KIND_MASK            : constant Octet := 16#3F#;

   ---------------------------------------------------------------------
   --  entityKind octet values (Table 9.1)
   ---------------------------------------------------------------------

   ENTITYKIND_UNKNOWN_BUILTIN            : constant Octet := 16#C0#;
   ENTITYKIND_PARTICIPANT                : constant Octet := 16#C1#;
   ENTITYKIND_WRITER_WITH_KEY_BUILTIN    : constant Octet := 16#C2#;
   ENTITYKIND_WRITER_NO_KEY_BUILTIN      : constant Octet := 16#C3#;
   ENTITYKIND_READER_NO_KEY_BUILTIN      : constant Octet := 16#C4#;
   ENTITYKIND_READER_WITH_KEY_BUILTIN    : constant Octet := 16#C7#;
   ENTITYKIND_UNKNOWN_USER               : constant Octet := 16#00#;
   ENTITYKIND_WRITER_WITH_KEY_USER       : constant Octet := 16#02#;
   ENTITYKIND_WRITER_NO_KEY_USER         : constant Octet := 16#03#;
   ENTITYKIND_READER_NO_KEY_USER         : constant Octet := 16#04#;
   ENTITYKIND_READER_WITH_KEY_USER       : constant Octet := 16#07#;

   ---------------------------------------------------------------------
   --  Predefined EntityIds (Table 9.2)
   ---------------------------------------------------------------------

   ENTITYID_PARTICIPANT : constant EntityId_T :=
     (16#00#, 16#00#, 16#01#, 16#C1#);
   ENTITYID_SEDP_BUILTIN_TOPIC_WRITER : constant EntityId_T :=
     (16#00#, 16#00#, 16#02#, 16#C2#);
   ENTITYID_SEDP_BUILTIN_TOPIC_READER : constant EntityId_T :=
     (16#00#, 16#00#, 16#02#, 16#C7#);
   ENTITYID_SEDP_BUILTIN_PUBLICATIONS_WRITER : constant EntityId_T :=
     (16#00#, 16#00#, 16#03#, 16#C2#);
   ENTITYID_SEDP_BUILTIN_PUBLICATIONS_READER : constant EntityId_T :=
     (16#00#, 16#00#, 16#03#, 16#C7#);
   ENTITYID_SEDP_BUILTIN_SUBSCRIPTIONS_WRITER : constant EntityId_T :=
     (16#00#, 16#00#, 16#04#, 16#C2#);
   ENTITYID_SEDP_BUILTIN_SUBSCRIPTIONS_READER : constant EntityId_T :=
     (16#00#, 16#00#, 16#04#, 16#C7#);
   ENTITYID_SPDP_BUILTIN_PARTICIPANT_WRITER : constant EntityId_T :=
     (16#00#, 16#01#, 16#00#, 16#C2#);
   ENTITYID_SPDP_BUILTIN_PARTICIPANT_READER : constant EntityId_T :=
     (16#00#, 16#01#, 16#00#, 16#C7#);
   ENTITYID_P2P_BUILTIN_PARTICIPANT_MESSAGE_WRITER : constant EntityId_T :=
     (16#00#, 16#02#, 16#00#, 16#C2#);
   ENTITYID_P2P_BUILTIN_PARTICIPANT_MESSAGE_READER : constant EntityId_T :=
     (16#00#, 16#02#, 16#00#, 16#C7#);

   ---------------------------------------------------------------------
   --  ProtocolVersion_t (Table 9.4 / 8.3.5.3)
   ---------------------------------------------------------------------

   type ProtocolVersion_T is record
      Major : Octet := 2;
      Minor : Octet := 2;
   end record;

   PROTOCOLVERSION_1_0 : constant ProtocolVersion_T := (1, 0);
   PROTOCOLVERSION_1_1 : constant ProtocolVersion_T := (1, 1);
   PROTOCOLVERSION_2_0 : constant ProtocolVersion_T := (2, 0);
   PROTOCOLVERSION_2_1 : constant ProtocolVersion_T := (2, 1);
   PROTOCOLVERSION_2_2 : constant ProtocolVersion_T := (2, 2);
   --  PROTOCOLVERSION is an alias for the most recent version (2.2):
   PROTOCOLVERSION     : constant ProtocolVersion_T := PROTOCOLVERSION_2_2;

   ---------------------------------------------------------------------
   --  VendorId_t (Table 9.4 / 8.3.5.2)
   ---------------------------------------------------------------------

   type VendorId_T is array (1 .. 2) of Octet;
   VENDORID_UNKNOWN : constant VendorId_T := (0, 0);
   --  Other values are assigned by the OMG.  Reserved for testing:
   VENDORID_IN_DEPENDENT : constant VendorId_T := (16#00#, 16#00#);

   ---------------------------------------------------------------------
   --  SequenceNumber_t (Table 9.4 / 8.3.5.4)
   ---------------------------------------------------------------------

   --  Wire mapping: struct SequenceNumber_t { long high; unsigned long low; }
   --  with seq_num = high * 2^32 + low.  Sequence numbers begin at 1 and
   --  the protocol reserves SEQUENCENUMBER_UNKNOWN = {-1, 0}.
   --  Internally we use a 64-bit unsigned where the reserved value is
   --  represented as 0; conversion helpers map to/from the wire form.
   type SequenceNumber_T is new Unsigned_Long_Long;
   SEQUENCENUMBER_UNKNOWN : constant SequenceNumber_T := 0;

   SEQUENCE_NUMBER_FIRST : constant SequenceNumber_T := 1;

   --  Construction / decomposition (wire representation).
   function Make_Sequence_Number
     (High : Long; Low : Unsigned_Long) return SequenceNumber_T;
   --  Build from the wire representation {-1,0} -> UNKNOWN.

   function High_Word (SN : SequenceNumber_T) return Long with Inline;
   function Low_Word  (SN : SequenceNumber_T) return Unsigned_Long with Inline;

   ---------------------------------------------------------------------
   --  FragmentNumber_t / Count_t (Table 9.4 / 8.3.5.6, 8.3.5.10)
   ---------------------------------------------------------------------

   --  32-bit unsigned; fragment numbers start at 1.
   type FragmentNumber_T is new Unsigned_Long;
   FRAGMENT_NUMBER_FIRST : constant FragmentNumber_T := 1;

   --  Count that is incremented monotonically to identify duplicates.
   type Count_T is new Long;
   COUNT_ZERO : constant Count_T := 0;

   ---------------------------------------------------------------------
   --  Time_t (Table 9.4 / 8.3.5.8) -- NTP representation, RFC 1305.
   --  time = seconds + fraction / 2^32, origin = Unix prime epoch.
   ---------------------------------------------------------------------

   type Time_T is record
      Seconds  : Long           := 0;
      Fraction : Unsigned_Long  := 0;
   end record;

   TIME_ZERO     : constant Time_T := (0, 0);
   TIME_INVALID  : constant Time_T := (-1, 16#FFFF_FFFF#);
   TIME_INFINITE : constant Time_T := (16#7FFF_FFFF#, 16#FFFF_FFFF#);

   ---------------------------------------------------------------------
   --  Locator_t (Table 9.4 / 8.3.5.11)
   ---------------------------------------------------------------------

   LOCATOR_KIND_INVALID   : constant Long := -1;
   LOCATOR_KIND_RESERVED  : constant Long := 0;
   LOCATOR_KIND_UDPv4     : constant Long := 1;
   LOCATOR_KIND_UDPv6     : constant Long := 2;

   type Octet_Array16 is array (1 .. 16) of Octet;
   LOCATOR_ADDRESS_INVALID : constant Octet_Array16 := (others => 0);
   LOCATOR_PORT_INVALID    : constant Unsigned_Long := 0;

   type Locator_T is record
      Kind    : Long          := LOCATOR_KIND_INVALID;
      Port    : Unsigned_Long := LOCATOR_PORT_INVALID;
      Address : Octet_Array16 := LOCATOR_ADDRESS_INVALID;
   end record;

   LOCATOR_INVALID : constant Locator_T :=
     (LOCATOR_KIND_INVALID, LOCATOR_PORT_INVALID, LOCATOR_ADDRESS_INVALID);

   type Locator_Array is array (Positive range <>) of Locator_T;
   type Locator_Buffer is access Locator_Array;

   function Make_UDPv4_Locator
     (A, B, C, D : Octet; Port : Unsigned_Long) return Locator_T
     with Post => Make_UDPv4_Locator'Result.Kind = LOCATOR_KIND_UDPv4;
   --  9.3.2: for LOCATOR_KIND_UDPv4 the leading 12 octets of the address
   --  are zero and the last 4 octets hold the IPv4 address a.b.c.d.

   ---------------------------------------------------------------------
   --  TopicKind_t, ChangeKind_t, ReliabilityKind_t (Table 8.2)
   ---------------------------------------------------------------------

   type TopicKind_T is (NO_KEY, WITH_KEY);

   type ChangeKind_T is
     (ALIVE, NOT_ALIVE_DISPOSED, NOT_ALIVE_UNREGISTERED);

   type ReliabilityKind_T is (BEST_EFFORT, RELIABLE);

   type InstanceHandle_T is new Unsigned_Long_Long;

   ---------------------------------------------------------------------
   --  ParameterId_t (clause 9.6.2.2, Tables 9.11 / 9.12)
   ---------------------------------------------------------------------

   type ParameterId_T is new Unsigned_Short;

   --  Table 9.11 - ParameterId subspaces:
   --    bit 15 (0x8000): 0 = reserved by protocol, 1 = vendor-specific
   --    bit 14 (0x4000): 0 = skip&ignore if unknown, 1 = incompatible QoS
   PID_VENDOR_SPECIFIC_FLAG   : constant ParameterId_T := 16#8000#;
   PID_INCOMPATIBLE_FLAG      : constant ParameterId_T := 16#4000#;

   --  Table 9.12 - ParameterId values.
   PID_PAD                                : constant ParameterId_T := 16#0000#;
   PID_SENTINEL                           : constant ParameterId_T := 16#0001#;
   PID_PARTICIPANT_LEASE_DURATION         : constant ParameterId_T := 16#0002#;
   PID_PARTICIPANT_MANUAL_LIVELINESS_COUNT: constant ParameterId_T := 16#0034#;
   PID_PARTICIPANT_BUILTIN_ENDPOINTS      : constant ParameterId_T := 16#0044#;
   PID_PARTICIPANT_GUID                   : constant ParameterId_T := 16#0050#;
   PID_PARTICIPANT_ENTITYID               : constant ParameterId_T := 16#0051#;
   PID_GROUP_GUID                         : constant ParameterId_T := 16#0052#;
   PID_GROUP_ENTITYID                     : constant ParameterId_T := 16#0053#;
   PID_BUILTIN_ENDPOINT_SET               : constant ParameterId_T := 16#0058#;
   PID_PROPERTY_LIST                      : constant ParameterId_T := 16#0059#;
   PID_TYPE_MAX_SIZE_SERIALIZED           : constant ParameterId_T := 16#0060#;
   PID_ENTITY_NAME                        : constant ParameterId_T := 16#0062#;
   PID_KEY_HASH                           : constant ParameterId_T := 16#0070#;
   PID_STATUS_INFO                        : constant ParameterId_T := 16#0071#;
   PID_TIME_BASED_FILTER                  : constant ParameterId_T := 16#0004#;
   PID_TOPIC_NAME                         : constant ParameterId_T := 16#0005#;
   PID_OWNERSHIP_STRENGTH                 : constant ParameterId_T := 16#0006#;
   PID_TYPE_NAME                          : constant ParameterId_T := 16#0007#;
   PID_METATRAFFIC_MULTICAST_IPADDRESS    : constant ParameterId_T := 16#000B#;
   PID_METATRAFFIC_UNICAST_IPADDRESS      : constant ParameterId_T := 16#000B#;
   PID_DEFAULT_UNICAST_IPADDRESS          : constant ParameterId_T := 16#000C#;
   PID_METATRAFFIC_UNICAST_PORT           : constant ParameterId_T := 16#000D#;
   PID_DEFAULT_UNICAST_PORT               : constant ParameterId_T := 16#000E#;
   PID_METATRAFFIC_MULTICAST_IPADDRESS2   : constant ParameterId_T := 16#0011#;
   PID_RELIABILITY                        : constant ParameterId_T := 16#001A#;
   PID_LIVELINESS                         : constant ParameterId_T := 16#001B#;
   PID_DURABILITY                         : constant ParameterId_T := 16#001D#;
   PID_DURABILITY_SERVICE                 : constant ParameterId_T := 16#001E#;
   PID_OWNERSHIP                          : constant ParameterId_T := 16#001F#;
   PID_PRESENTATION                       : constant ParameterId_T := 16#0021#;
   PID_DEADLINE                           : constant ParameterId_T := 16#0023#;
   PID_DESTINATION_ORDER                  : constant ParameterId_T := 16#0025#;
   PID_LATENCY_BUDGET                     : constant ParameterId_T := 16#0027#;
   PID_PARTITION                          : constant ParameterId_T := 16#0029#;
   PID_LIFESPAN                           : constant ParameterId_T := 16#002B#;
   PID_USER_DATA                          : constant ParameterId_T := 16#002C#;
   PID_GROUP_DATA                         : constant ParameterId_T := 16#002D#;
   PID_TOPIC_DATA                         : constant ParameterId_T := 16#002E#;
   PID_UNICAST_LOCATOR                    : constant ParameterId_T := 16#002F#;
   PID_MULTICAST_LOCATOR                  : constant ParameterId_T := 16#0030#;
   PID_DEFAULT_UNICAST_LOCATOR            : constant ParameterId_T := 16#0031#;
   PID_METATRAFFIC_UNICAST_LOCATOR        : constant ParameterId_T := 16#0032#;
   PID_METATRAFFIC_MULTICAST_LOCATOR      : constant ParameterId_T := 16#0033#;
   PID_CONTENT_FILTER_PROPERTY            : constant ParameterId_T := 16#0035#;
   PID_HISTORY                            : constant ParameterId_T := 16#0040#;
   PID_RESOURCE_LIMITS                    : constant ParameterId_T := 16#0041#;
   PID_EXPECTS_INLINE_QOS                 : constant ParameterId_T := 16#0043#;
   PID_METATRAFFIC_MULTICAST_PORT         : constant ParameterId_T := 16#0046#;
   PID_DEFAULT_MULTICAST_LOCATOR          : constant ParameterId_T := 16#0048#;
   PID_TRANSPORT_PRIORITY                 : constant ParameterId_T := 16#0049#;
   PID_PROTOCOL_VERSION                   : constant ParameterId_T := 16#0015#;
   PID_VENDORID                           : constant ParameterId_T := 16#0016#;

   ---------------------------------------------------------------------
   --  BuiltinEndpointSet_t (9.6.2.2 / Table 9.4)
   ---------------------------------------------------------------------

   type BuiltinEndpointSet_T is new Unsigned_Long;

   DISC_BUILTIN_ENDPOINT_PARTICIPANT_ANNOUNCER : constant :=
     BuiltinEndpointSet_T (2**0);
   DISC_BUILTIN_ENDPOINT_PARTICIPANT_DETECTOR : constant :=
     BuiltinEndpointSet_T (2**1);
   DISC_BUILTIN_ENDPOINT_PUBLICATION_ANNOUNCER : constant :=
     BuiltinEndpointSet_T (2**2);
   DISC_BUILTIN_ENDPOINT_PUBLICATION_DETECTOR : constant :=
     BuiltinEndpointSet_T (2**3);
   DISC_BUILTIN_ENDPOINT_SUBSCRIPTION_ANNOUNCER : constant :=
     BuiltinEndpointSet_T (2**4);
   DISC_BUILTIN_ENDPOINT_SUBSCRIPTION_DETECTOR : constant :=
     BuiltinEndpointSet_T (2**5);
   DISC_BUILTIN_ENDPOINT_PARTICIPANT_PROXY_ANNOUNCER : constant :=
     BuiltinEndpointSet_T (2**6);
   DISC_BUILTIN_ENDPOINT_PARTICIPANT_PROXY_DETECTOR : constant :=
     BuiltinEndpointSet_T (2**7);
   DISC_BUILTIN_ENDPOINT_PARTICIPANT_STATE_ANNOUNCER : constant :=
     BuiltinEndpointSet_T (2**8);
   DISC_BUILTIN_ENDPOINT_PARTICIPANT_STATE_DETECTOR : constant :=
     BuiltinEndpointSet_T (2**9);
   BUILTIN_ENDPOINT_PARTICIPANT_MESSAGE_DATA_WRITER : constant :=
     BuiltinEndpointSet_T (2**10);
   BUILTIN_ENDPOINT_PARTICIPANT_MESSAGE_DATA_READER : constant :=
     BuiltinEndpointSet_T (2**11);

   ---------------------------------------------------------------------
   --  PSM defaults: default port numbers (clause 9.6.1.3) and SPDP
   --  defaults (9.6.1.4)
   ---------------------------------------------------------------------

   PB : constant Unsigned_Long := 7400;   --  Port Base number
   DG : constant Unsigned_Long := 250;    --  DomainId Gain
   PG : constant Unsigned_Long := 2;      --  ParticipantId Gain
   D0 : constant Unsigned_Long := 0;
   D1 : constant Unsigned_Long := 10;
   D2 : constant Unsigned_Long := 1;
   D3 : constant Unsigned_Long := 11;

   function SPDP_Multicast_Addr return Octet_Array16 is
     ((0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 239, 255, 0, 1)) with Inline;
   --  "239.255.0.1" in the 16-octet locator address form.

   function SPDP_Multicast_Port (Domain_Id : Unsigned_Long)
     return Unsigned_Long is (PB + DG * Domain_Id + D0) with Inline;
   --  DefaultMulticastLocator = {LOCATOR_KIND_UDPv4, "239.255.0.1",
   --                             PB + DG * domainId + d0}

   function Metatraffic_Multicast_Port (Domain_Id : Unsigned_Long)
     return Unsigned_Long is (PB + DG * Domain_Id + D1) with Inline;

   function Metatraffic_Unicast_Port
     (Domain_Id, Participant_Id : Unsigned_Long) return Unsigned_Long is
     (PB + DG * Domain_Id + D2 + PG * Participant_Id) with Inline;

   function User_Multicast_Port (Domain_Id : Unsigned_Long)
     return Unsigned_Long is (PB + DG * Domain_Id + D2) with Inline;

   function User_Unicast_Port
     (Domain_Id, Participant_Id : Unsigned_Long) return Unsigned_Long is
     (PB + DG * Domain_Id + D3 + PG * Participant_Id) with Inline;

   SPDP_RESEND_PERIOD : constant Time_T := (30, 0);
   --  SPDPbuiltinParticipantWriter.resendPeriod = {30, 0} (9.6.1.4.2)

end RTPS.Types;
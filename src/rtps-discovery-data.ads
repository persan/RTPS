------------------------------------------------------------------------------
--  RTPS.Discovery.Data
--
--  Data types of the Discovery Module (clause 8.5) and their wire
--  mapping (9.6.2.2):
--    * SPDPdiscoveredParticipantData (8.5.3.2, Table 8.73)
--    * DiscoveredWriterData          (8.5.4.4, Figure 8.31)
--    * DiscoveredReaderData          (8.5.4.4, Figure 8.31)
--
--  On the wire the discovery data is carried in the SerializedData of
--  standard DATA submessages as a ParameterList (9.6.2.2): each field
--  is encapsulated in a parameter identified by its ParameterId
--  (Table 9.12).
------------------------------------------------------------------------------

with RTPS.Types;
with RTPS.CDR;
with RTPS.Messages;

package RTPS.Discovery.Data is

   package T renames RTPS.Types;
   package M renames RTPS.Messages;

   ---------------------------------------------------------------------
   --  SPDPdiscoveredParticipantData (Table 8.73)
   ---------------------------------------------------------------------

   type Participant_Data is record
      Protocol_Version : T.ProtocolVersion_T := T.PROTOCOLVERSION;
      Guid_Prefix      : T.GuidPrefix_T      := T.GUIDPREFIX_UNKNOWN;
      Vendor_Id        : T.VendorId_T        := T.VENDORID_UNKNOWN;
      Expects_Inline_Qos : Boolean           := False;

      --  ParticipantProxy part:
      Available_Builtin_Endpoints : T.BuiltinEndpointSet_T := 0;
      Metatraffic_Unicast_Port    : T.Unsigned_Long := 0;
      Metatraffic_Multicast_Port  : T.Unsigned_Long := 0;
      Default_Unicast_Port        : T.Unsigned_Long := 0;
      Default_Multicast_Port      : T.Unsigned_Long := 0;
      Manual_Liveliness_Count     : T.Count_T       := 0;

      Lease_Duration : T.Time_T := (Seconds => 100, Fraction => 0);
   end record;
   --  Locators are kept as (address, port) pairs of the UDPv4 PSM:
   --  the address is always the announcing participant's, so only the
   --  ports are carried; the addresses come from the transport layer
   --  of the receiving side (source of the datagram / multicast group).

   ---------------------------------------------------------------------
   --  DiscoveredWriterData / DiscoveredReaderData (Figure 8.31)
   ---------------------------------------------------------------------

   type Endpoint_Data is record
      Topic_Name    : T.Octet_Array (1 .. 256) := (others => 0);
      Topic_Len     : Natural := 0;   --  valid octets in Topic_Name
      Type_Name     : T.Octet_Array (1 .. 256) := (others => 0);
      Type_Len      : Natural := 0;   --  valid octets in Type_Name
      Reliability   : Boolean := False;  --  PID_RELIABILITY value
      Writer_Or_Reader_Guid : T.GUID_T := T.GUID_UNKNOWN;

      --  Proxy part (metatraffic unicast locator of the remote side):
      Unicast_Port  : T.Unsigned_Long := 0;
      Expects_Inline_Qos : Boolean    := False;
   end record;
   --  One record shape serves DiscoveredWriterData and
   --  DiscoveredReaderData; the GUID is the remote endpoint's.

   ---------------------------------------------------------------------
   --  ParameterList wire mapping (9.6.2.2)
   ---------------------------------------------------------------------

   Max_Parameter_List : constant := 32;

   function Encode_Participant_Data
     (D    : Participant_Data;
      Guid : T.GUID_T)
      return M.Parameter_Array_Ref;
   --  Serialize into a parameter list: PID_PROTOCOL_VERSION,
   --  PID_VENDORID, PID_PARTICIPANT_GUID, PID_BUILTIN_ENDPOINT_SET,
   --  PID_METATRAFFIC_UNICAST_LOCATOR, PID_METATRAFFIC_MULTICAST_LOCATOR,
   --  PID_DEFAULT_UNICAST_LOCATOR, PID_DEFAULT_MULTICAST_LOCATOR,
   --  PID_PARTICIPANT_MANUAL_LIVELINESS_COUNT, PID_PARTICIPANT_LEASE_
   --  DURATION, PID_EXPECTS_INLINE_QOS (Table 9.12).

   function Decode_Participant_Data
     (List : M.Parameter_Array_Ref)
      return Participant_Data;
   --  Inverse of Encode; unknown parameters are skipped (Table 9.11).
   --  Fields whose parameter is absent keep their default value.

   function Encode_Writer_Data
     (D : Endpoint_Data) return M.Parameter_Array_Ref;
   --  PID_TOPIC_NAME, PID_TYPE_NAME, PID_RELIABILITY,
   --  PID_UNICAST_LOCATOR, PID_EXPECTS_INLINE_QOS + writer GUID
   --  (PID_KEY_HASH carries the endpoint GUID).

   function Decode_Writer_Data
     (List : M.Parameter_Array_Ref) return Endpoint_Data;

   function Encode_Reader_Data
     (D : Endpoint_Data) return M.Parameter_Array_Ref;
   --  Same parameter set as the writer data (the endpoint GUID
   --  disambiguates the role).

   function Decode_Reader_Data
     (List : M.Parameter_Array_Ref) return Endpoint_Data;

   ---------------------------------------------------------------------
   --  Helpers for locator parameters (Table 9.12: Locator_t)
   ---------------------------------------------------------------------

   function Parameter_Locator
     (Id : T.ParameterId_T; Port : T.Unsigned_Long) return M.Parameter_T;
   --  One PID_*_LOCATOR parameter: kind LOCATOR_KIND_UDPv4 +
   --  12 zero octets + a.b.c.d (0.0.0.0: the announcing participant
   --  fills in its address on the receiver side) + port (9.3.2).

private

end RTPS.Discovery.Data;
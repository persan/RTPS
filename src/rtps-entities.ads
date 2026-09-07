------------------------------------------------------------------------------
--  RTPS.Entities
--
--  The RTPS Structure Module (clause 8.2): Entities, GUIDs, Participants,
--  Endpoints, Writers, Readers, and the HistoryCache.
--
--  The PIM describes the entities as abstract classes; we map them to
--  Ada interfaces and tagged types rooted at Entity root type.
------------------------------------------------------------------------------

with RTPS.Types;

package RTPS.Entities is

   ---------------------------------------------------------------------
   --  8.2.4.1 The GUID
   ---------------------------------------------------------------------

   use type RTPS.Types.Octet;

   function "=" (L, R : RTPS.Types.EntityId_T) return Boolean;
   --  Defaults suffice; kept explicit for documentation.

   function "<" (L, R : RTPS.Types.EntityId_T) return Boolean;
   --  Lexicographic ordering over the 4 octets; used for containers.

   function "=" (L, R : RTPS.Types.GuidPrefix_T) return Boolean;

   function "<" (L, R : RTPS.Types.GuidPrefix_T) return Boolean;

   function "=" (L, R : RTPS.Types.GUID_T) return Boolean;

   function "<" (L, R : RTPS.Types.GUID_T) return Boolean;

   ---------------------------------------------------------------------
   --  8.2.4 The RTPS Entity
   ---------------------------------------------------------------------

   type Entity is interface;
   --  Entity root class: "RTPS Entity is an abstract class; it has no
   --  instances." (8.2.4)

   function Get_Guid (Self : Entity) return RTPS.Types.GUID_T is abstract;
   --  @guid attribute.

   function Is_Built_In (Self : Entity) return Boolean is abstract;

   ---------------------------------------------------------------------
   --  8.2.5 The RTPS Participant
   ---------------------------------------------------------------------

   type Participant is interface and Entity;

   function Protocol_Version_Of (Self : Participant)
     return RTPS.Types.ProtocolVersion_T is abstract;
   --  @protocolRTPSMajorVersion / @protocolRTPSMinorVersion

   function Vendor_Id_Of (Self : Participant) return RTPS.Types.VendorId_T
     is abstract;
   --  @vendorid

   function Default_Unicast_Locator_List (Self : Participant)
     return RTPS.Types.Locator_Buffer is abstract;

   function Default_Multicast_Locator_List (Self : Participant)
     return RTPS.Types.Locator_Buffer is abstract;

   ---------------------------------------------------------------------
   --  8.2.6 The RTPS Endpoint
   ---------------------------------------------------------------------

   type Endpoint is interface and Entity;

   function Topic_Kind_Of (Self : Endpoint) return RTPS.Types.TopicKind_T
     is abstract;
   --  @topicKind

   function Reliability_Level_Of (Self : Endpoint)
     return RTPS.Types.ReliabilityKind_T is abstract;
   --  @reliabilityLevel

   function Unicast_Locator_List (Self : Endpoint)
     return RTPS.Types.Locator_Buffer is abstract;

   function Multicast_Locator_List (Self : Endpoint)
     return RTPS.Types.Locator_Buffer is abstract;

   ---------------------------------------------------------------------
   --  8.2.7 / 8.2.8 Writer and Reader
   ---------------------------------------------------------------------

   type Writer is interface and Endpoint;

   function Reader_Proxy_Of (Self : Writer) return Natural is abstract;
   --  Placeholder for the matched-readers state (8.4.7.5).

   type Reader is interface and Endpoint;

   function Writer_Proxy_Of (Self : Reader) return Natural is abstract;
   --  Placeholder for the matched-writers state (8.4.10.4).

end RTPS.Entities;
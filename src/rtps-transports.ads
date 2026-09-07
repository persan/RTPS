------------------------------------------------------------------------------
--  RTPS.Transports
--
--  Transport abstraction for the RTPS PSM (clause 9.6).  A Transport
--  sends and receives whole RTPS Messages on a Locator; the UDP/IP PSM
--  of clause 9 is one realization, shared memory another.
------------------------------------------------------------------------------

with RTPS.Types;
with Ada.Streams;

package RTPS.Transports is

  use type Ada.Streams.Stream_Element_Offset;
  use all type RTPS.Types.Long;

   type Transport is limited interface;

   function Max_Message_Size (Self : Transport)
     return Ada.Streams.Stream_Element_Count is abstract;
   --  Largest message the transport can carry (e.g. 65507 for UDPv4).

   function Supports_Multicast (Self : Transport) return Boolean is abstract;

   function Kind_Of (Self : Transport) return RTPS.Types.Long is abstract;
   --  LOCATOR_KIND_UDPv4 / LOCATOR_KIND_UDPv6 / vendor-defined.

   subtype Port_Type is Ada.Streams.Stream_Element_Count;

   --  A received datagram: message bytes plus the locator it came from.
   type Received_Message is record
      Data        : RTPS.Types.Octet_Buffer := null;
      Length      : Natural := 0;
      Source_Loc  : RTPS.Types.Locator_T := RTPS.Types.LOCATOR_INVALID;
   end record;

end RTPS.Transports;
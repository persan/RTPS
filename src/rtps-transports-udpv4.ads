------------------------------------------------------------------------------
--  RTPS.Transports.UDPv4 -- UDP/IP PSM (clause 9) transport on GNAT.Sockets
--
--  Implements the Transport interface over UDPv4 sockets:
--    * one socket bound to (any, port), optionally joining multicast
--      groups (SPDP uses 239.255.0.1);
--    * Send datagrams to a locator;
--    * Receive datagrams (blocking or with timeout), returning the
--      payload and the source locator.
--
--  Wire mapping per clause 9.5: an RTPS Message is the payload of
--  exactly one UDP datagram.
--
--  Thread-safety: the socket is protected; concurrent Send and Receive
--  are allowed (GNAT.Sockets datagram sockets are themselves safe to
--  share for UDP).
------------------------------------------------------------------------------

with RTPS.Types;
with RTPS.Transports;
with GNAT.Sockets;

package RTPS.Transports.UDPv4 is

   --  Raised by Open when the socket cannot be created or bound, and by
   --  Join_Group / Leave_Group on multicast membership errors.
   Socket_Error : exception renames GNAT.Sockets.Socket_Error;

   type UDPv4_Transport is new Transports.Transport with private;

   ---------------------------------------------------------------------
   --  Setup
   ---------------------------------------------------------------------

   procedure Open
     (Self       : in out UDPv4_Transport;
      Port       :        Types.Unsigned_Long;
      Reuse_Addr :        Boolean := True;
      Multicast  :        Boolean := True);
   --  Create and bind a UDP socket on 0.0.0.0:Port.  When Multicast is
   --  True the socket is bound to the wildcard address so that it also
   --  receives multicast datagrams (SO_REUSEADDR is set on Windows,
   --  where multicast reception requires it).

   procedure Join_Group
     (Self  : in out UDPv4_Transport;
      Group :        Types.Octet; A, B, C, D : Types.Octet);
   --  Join the multicast group a.b.c.d (IP_ADD_MEMBERSHIP) on the
   --  default interface.

   procedure Join_Group
     (Self  : in out UDPv4_Transport;
      Group :        Types.Locator_T);
   --  Same, taking a Locator of kind LOCATOR_KIND_UDPv4.

   procedure Leave_Group
     (Self  : in out UDPv4_Transport;
      Group :        RTPS.Types.Locator_T);

   procedure Close (Self : in out UDPv4_Transport);
   --  Close the socket; the transport becomes unusable.

   ---------------------------------------------------------------------
   --  Transport interface (RTPS.Transports)
   ---------------------------------------------------------------------

   overriding function Max_Message_Size (Self : UDPv4_Transport)
     return Ada.Streams.Stream_Element_Count;
   --  65507 = 65535 - IP(20) - UDP(8) header octets.

   overriding function Supports_Multicast (Self : UDPv4_Transport)
     return Boolean;
   --  Always True.

   overriding function Kind_Of (Self : UDPv4_Transport)
     return RTPS.Types.Long;
   --  LOCATOR_KIND_UDPv4.

   ---------------------------------------------------------------------
   --  Sending
   ---------------------------------------------------------------------

   procedure Send
     (Self  : in out UDPv4_Transport;
      Dest  :        RTPS.Types.Locator_T;
      Data  :        RTPS.Types.Octet_Array);
   --  Send one datagram carrying Data to the UDPv4 locator Dest.
   --  Raises Socket_Error if the socket is not open.

   ---------------------------------------------------------------------
   --  Receiving
   ---------------------------------------------------------------------

   procedure Receive
     (Self    : in out UDPv4_Transport;
      Item    :    out RTPS.Transports.Received_Message;
      Timeout :        Duration := 0.0);
   --  Wait up to Timeout seconds for one datagram; Timeout = 0.0 means
   --  block until one arrives.  On timeout, Item.Length is 0 and
   --  Item.Source_Loc is LOCATOR_INVALID.  Item.Data holds a freshly
   --  allocated buffer of Max_Message_Size octets; Length is the
   --  datagram size.

   function Local_Port (Self : UDPv4_Transport) return Types.Unsigned_Long;
   --  The bound port (useful after Open with Port 0 to pick an
   --  ephemeral port).

private

   type UDPv4_Transport is new Transports.Transport with record
      Socket  : GNAT.Sockets.Socket_Type := GNAT.Sockets.No_Socket;
      Opened  : Boolean := False;
      Port    : Types.Unsigned_Long := 0;
   end record;

end RTPS.Transports.UDPv4;
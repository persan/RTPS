------------------------------------------------------------------------------
--  RTPS.Transports.UDPv4 -- body
--
--  UDP/IP PSM (clause 9) transport over GNAT.Sockets.  One datagram per
--  RTPS message (9.5).
------------------------------------------------------------------------------

with Ada.Streams;

package body RTPS.Transports.UDPv4 is

   use all type GNAT.Sockets.Port_Type;
   use all type GNAT.Sockets.Inet_Addr_Comp_Type;
   use all type GNAT.Sockets.Family_Type;
   use all type GNAT.Sockets.Inet_Addr_Type;
   use all type RTPS.Types.Octet;

   Max_Datagram_Size : constant Ada.Streams.Stream_Element_Count := 65_507;

   ---------------------------------------------------------------------
   --  Helpers: locator <-> socket address conversion
   ---------------------------------------------------------------------

   function To_Socket_Addr (L : Types.Locator_T)
     return GNAT.Sockets.Sock_Addr_Type
   is
   begin
      if L.Kind /= Types.LOCATOR_KIND_UDPv4 then
         raise Constraint_Error with "locator is not UDPv4";
      end if;
      --  Clause 9.3.2: for LOCATOR_KIND_UDPv4 the leading 12 octets of
      --  the address must be zero; the last 4 hold a.b.c.d.
      for K in 1 .. 12 loop
         if L.Address (K) /= 0 then
            raise Constraint_Error with "UDPv4 locator address has junk";
         end if;
      end loop;
      declare
         Addr : GNAT.Sockets.Inet_Addr_Type (GNAT.Sockets.Family_Inet);
      begin
         Addr.Sin_V4 (1) := GNAT.Sockets.Inet_Addr_Comp_Type (L.Address (13));
         Addr.Sin_V4 (2) := GNAT.Sockets.Inet_Addr_Comp_Type (L.Address (14));
         Addr.Sin_V4 (3) := GNAT.Sockets.Inet_Addr_Comp_Type (L.Address (15));
         Addr.Sin_V4 (4) := GNAT.Sockets.Inet_Addr_Comp_Type (L.Address (16));
         return (Family => GNAT.Sockets.Family_Inet,
                 Addr   => Addr,
                 Port   => GNAT.Sockets.Port_Type (L.Port));
      end;
   end To_Socket_Addr;

   function To_Locator (A : GNAT.Sockets.Sock_Addr_Type) return Types.Locator_T
   is
   begin
      if A.Addr.Family /= GNAT.Sockets.Family_Inet then
         return RTPS.Types.LOCATOR_INVALID;
      end if;
      declare
         Result : constant Types.Locator_T :=
           Types.Make_UDPv4_Locator
             (A    => Types.Octet (A.Addr.Sin_V4 (1)),
              B    => Types.Octet (A.Addr.Sin_V4 (2)),
              C    => Types.Octet (A.Addr.Sin_V4 (3)),
              D    => Types.Octet (A.Addr.Sin_V4 (4)),
              Port => Types.Unsigned_Long (A.Port));
      begin
         return Result;
      end;
   end To_Locator;

   ---------------------------------------------------------------------
   --  Setup
   ---------------------------------------------------------------------

   procedure Open
     (Self       : in out UDPv4_Transport;
      Port       :        Types.Unsigned_Long;
      Reuse_Addr :        Boolean := True;
      Multicast  :        Boolean := True)
   is
      pragma Unreferenced (Multicast);
      --  Binding to Any_Inet_Addr (wildcard) receives unicast and
      --  (once groups are joined) multicast alike; SO_REUSEADDR is set
      --  when Reuse_Addr because Windows requires it for sharing a
      --  multicast (group, port) across sockets.
      Bound : GNAT.Sockets.Sock_Addr_Type;
   begin
      GNAT.Sockets.Create_Socket
        (Socket => Self.Socket,
         Family => GNAT.Sockets.Family_Inet,
         Mode   => GNAT.Sockets.Socket_Datagram);
      Self.Opened := True;

      if Reuse_Addr then
         GNAT.Sockets.Set_Socket_Option
           (Self.Socket,
            GNAT.Sockets.Socket_Level,
            (Name    => GNAT.Sockets.Reuse_Address,
             Enabled => True));
      end if;

      GNAT.Sockets.Bind_Socket
        (Self.Socket,
         (Family => GNAT.Sockets.Family_Inet,
          Addr   => GNAT.Sockets.Any_Inet_Addr,
          Port   => GNAT.Sockets.Port_Type (Port)));

      Bound := GNAT.Sockets.Get_Socket_Name (Self.Socket);
      Self.Port := Types.Unsigned_Long (Bound.Port);
   end Open;

   procedure Join_Group
     (Self  : in out UDPv4_Transport;
      Group :        Types.Octet; A, B, C, D : Types.Octet)
   is
      pragma Unreferenced (Group);
      G : constant Types.Locator_T :=
        Types.Make_UDPv4_Locator
          (A    => A,
           B    => B,
           C    => C,
           D    => D,
           Port => Types.Unsigned_Long'(0));
   begin
      Join_Group (Self, G);
   end Join_Group;

   procedure Join_Group
     (Self  : in out UDPv4_Transport;
      Group :        Types.Locator_T)
   is
   begin
      GNAT.Sockets.Set_Socket_Option
        (Self.Socket,
         GNAT.Sockets.IP_Protocol_For_IP_Level,
         (Name              => GNAT.Sockets.Add_Membership_V4,
          Multicast_Address => To_Socket_Addr (Group).Addr,
          Local_Interface   => GNAT.Sockets.Any_Inet_Addr));
   end Join_Group;

   procedure Leave_Group
     (Self  : in out UDPv4_Transport;
      Group :        RTPS.Types.Locator_T)
   is
   begin
      GNAT.Sockets.Set_Socket_Option
        (Self.Socket,
         GNAT.Sockets.IP_Protocol_For_IP_Level,
         (Name              => GNAT.Sockets.Drop_Membership_V4,
          Multicast_Address => To_Socket_Addr (Group).Addr,
          Local_Interface   => GNAT.Sockets.Any_Inet_Addr));
   end Leave_Group;

   procedure Close (Self : in out UDPv4_Transport) is
   begin
      if Self.Opened then
         GNAT.Sockets.Close_Socket (Self.Socket);
         Self.Opened := False;
         Self.Socket := GNAT.Sockets.No_Socket;
      end if;
   end Close;

   ---------------------------------------------------------------------
   --  Transport interface
   ---------------------------------------------------------------------

   overriding function Max_Message_Size (Self : UDPv4_Transport)
     return Ada.Streams.Stream_Element_Count
   is
      pragma Unreferenced (Self);
   begin
      return 65_507;  --  65535 - IP(20) - UDP(8)
   end Max_Message_Size;

   overriding function Supports_Multicast (Self : UDPv4_Transport)
     return Boolean
   is
      pragma Unreferenced (Self);
   begin
      return True;
   end Supports_Multicast;

   overriding function Kind_Of (Self : UDPv4_Transport)
     return RTPS.Types.Long
   is
      pragma Unreferenced (Self);
   begin
      return RTPS.Types.LOCATOR_KIND_UDPv4;
   end Kind_Of;

   function Local_Port (Self : UDPv4_Transport) return Types.Unsigned_Long is
   begin
      return Self.Port;
   end Local_Port;

   ---------------------------------------------------------------------
   --  Sending
   ---------------------------------------------------------------------

   procedure Send
     (Self  : in out UDPv4_Transport;
      Dest  :        RTPS.Types.Locator_T;
      Data  :        RTPS.Types.Octet_Array)
   is
      use type Ada.Streams.Stream_Element_Offset;
      Addr : constant GNAT.Sockets.Sock_Addr_Type :=
        To_Socket_Addr (Dest);
      Last : Ada.Streams.Stream_Element_Offset;
      Buf  : Ada.Streams.Stream_Element_Array (1 .. Data'Length);
   begin
      if not Self.Opened then
         raise Socket_Error with "transport not open";
      end if;
      if Data'Length > Natural (Max_Datagram_Size) then
         raise Constraint_Error with "message larger than UDP datagram";
      end if;
      for K in Data'Range loop
         Buf (Ada.Streams.Stream_Element_Offset (K - Data'First + 1))
           := Ada.Streams.Stream_Element (Data (K));
      end loop;
      GNAT.Sockets.Send_Socket
        (Self.Socket,
         Buf (1 .. Data'Length),
         Last,
         To   => Addr);
      if Last /= Ada.Streams.Stream_Element_Offset (Data'Length) then
         raise Socket_Error with "short send";
      end if;
   end Send;

   ---------------------------------------------------------------------
   --  Receiving
   ---------------------------------------------------------------------

   procedure Receive
     (Self    : in out UDPv4_Transport;
      Item    :    out RTPS.Transports.Received_Message;
      Timeout :        Duration := 0.0)
   is
      use type Ada.Streams.Stream_Element_Offset;
      Buf    : Ada.Streams.Stream_Element_Array (1 .. Max_Datagram_Size);
      Last   : Ada.Streams.Stream_Element_Offset;
      From   : GNAT.Sockets.Sock_Addr_Type;
      use all type GNAT.Sockets.Selector_Status;

      R_Set  : GNAT.Sockets.Socket_Set_Type;
      W_Set  : GNAT.Sockets.Socket_Set_Type;
      Status : GNAT.Sockets.Selector_Status;
   begin
      Item := (Data => null, Length => 0,
               Source_Loc => RTPS.Types.LOCATOR_INVALID);

      if not Self.Opened then
         raise Socket_Error with "transport not open";
      end if;

      if Timeout > 0.0 then
         GNAT.Sockets.Empty (R_Set);
         GNAT.Sockets.Set (R_Set, Self.Socket);
         --  Null_Selector works when Abort_Selector is not used
         --  (GNAT.Sockets docs): pass the null selector constant.
         GNAT.Sockets.Check_Selector
           (GNAT.Sockets.Null_Selector, R_Set, W_Set, Status, Timeout);
         case Status is
            when GNAT.Sockets.Completed =>
               null;  --  datagram pending
            when others =>
               return;  --  timed out (or aborted)
         end case;
      end if;

      GNAT.Sockets.Receive_Socket (Self.Socket, Buf, Last, From => From);

      Item.Length := Natural (Last);
      Item.Source_Loc := To_Locator (From);
      Item.Data := new Types.Octet_Array (1 .. Item.Length);
      for K in 1 .. Item.Length loop
         Item.Data.all (K) :=
           Types.Octet (Buf (Ada.Streams.Stream_Element_Offset (K)));
      end loop;
   end Receive;

begin
   GNAT.Sockets.Initialize;  --  once per partition (idempotent)
end RTPS.Transports.UDPv4;